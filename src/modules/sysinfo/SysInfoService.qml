pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// CPU/system readings shared by the bar indicator and its popup.
//
// One /bin/sh sample reads procfs/sysfs: package temperature (hwmon label
// first, thermal-zone fallback), per-core scaling_cur_freq (the global
// frequency is their average), /proc/loadavg, /proc/cpuinfo (model + core
// counts) and /proc/stat. Usage (total and per core) comes from the
// /proc/stat deltas, so the first sample only seeds the baseline.
//
// Sampling never stops: `pollMs` while the popup is open (`detail`), else
// `idlePollMs`. The bar keeps a fresh temperature and the usage chart already
// holds history when the popup opens.
Singleton {
    id: root

    // Sampling cadence + chart length (user config)
    readonly property int pollMs: Config.settings.modules.sysinfo.pollMs
    readonly property int idlePollMs: Config.settings.modules.sysinfo.idlePollMs
    readonly property int historyLimit: Config.settings.modules.sysinfo.history
    // Temperature color thresholds (user config), applied by Theme
    readonly property int warnTemp: Config.settings.modules.sysinfo.warnTemp
    readonly property int critTemp: Config.settings.modules.sysinfo.critTemp

    // True while the popup is open (fast sampling for the charts)
    property bool detail: false

    // --- static hardware info ---------------------------------------
    property string modelName: ""
    property int coresLogical: 0
    property int coresPhysical: 0
    property real maxFreqMHz: 0
    property real baseFreqMHz: 0

    // --- live readings -----------------------------------------------
    property real temperature: -1      // deg C; -1 = no sensor found
    property real freqMHz: 0           // average across all cores
    property real freqMinMHz: 0
    property real freqMaxMHz: 0
    property string governor: ""
    property string energyPref: ""
    property real load1: 0
    property real load5: 0
    property real load15: 0
    property real usage: 0             // 0..100, total
    property var coreUsage: []         // 0..100 per logical core
    property var history: []           // recent total usage samples (oldest first)
    property bool usageReady: false

    readonly property bool hasTemp: root.temperature >= 0
    readonly property bool hasFreq: root.freqMHz > 0
    // 1-minute load average scaled to the core count (0..100)
    readonly property real loadRatio: root.coresLogical > 0
        ? Math.min(100, root.load1 / root.coresLogical * 100) : 0

    // Previous /proc/stat sample, kept for the deltas
    property real prevTotal: 0
    property real prevIdle: 0
    property var prevCores: []

    // ------------------------------------------------------------------
    // Formatting helpers
    // ------------------------------------------------------------------
    function formatFreq(mhz) {
        if (!(mhz > 0))
            return "\u2014"
        return Math.round(mhz) + "MHz"
    }

    function formatLoad() {
        if (!root.usageReady)
            return "\u2014"
        return root.load1.toFixed(2) + " \u00b7 " + root.load5.toFixed(2)
            + " \u00b7 " + root.load15.toFixed(2)
    }

    function formatCores() {
        if (root.coresLogical <= 0)
            return "\u2014"
        if (root.coresPhysical > 0 && root.coresPhysical !== root.coresLogical)
            return root.coresPhysical + " physical \u00b7 " + root.coresLogical + " threads"
        return root.coresLogical + " threads"
    }

    // Trigger an immediate sample (popup refresh button)
    function refresh() {
        root.poll()
    }

    function poll() {
        if (!sample.running)
            sample.running = true
    }

    // ------------------------------------------------------------------
    // Output parsing
    // ------------------------------------------------------------------
    function handleOutput(text) {
        const lines = String(text).split("\n")
        const statLines = []
        let inStat = false
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i]
            if (line === "")
                continue
            if (line === "S") {
                inStat = true
                continue
            }
            if (inStat) {
                statLines.push(line)
                continue
            }
            const p = line.split("\t")
            switch (p[0]) {
            case "T": {
                const t = parseInt(p[1], 10)
                root.temperature = isNaN(t) || t < 0 ? -1 : t / 1000
                break
            }
            case "F": {
                const sum = parseInt(p[1], 10)
                const n = parseInt(p[2], 10)
                const lo = parseInt(p[3], 10)
                const hi = parseInt(p[4], 10)
                root.freqMHz = n > 0 && sum > 0 ? sum / n / 1000 : 0
                root.freqMinMHz = n > 0 ? lo / 1000 : 0
                root.freqMaxMHz = n > 0 ? hi / 1000 : 0
                break
            }
            case "X": {
                const mx = parseInt(p[1], 10)
                const bs = parseInt(p[2], 10)
                root.maxFreqMHz = isNaN(mx) || mx <= 0 ? 0 : mx / 1000
                root.baseFreqMHz = isNaN(bs) || bs <= 0 ? 0 : bs / 1000
                break
            }
            case "G":
                root.governor = p[1] === undefined ? "" : p[1]
                break
            case "E":
                root.energyPref = p[1] === undefined ? "" : p[1]
                break
            case "L": {
                const l1 = parseFloat(p[1])
                const l5 = parseFloat(p[2])
                const l15 = parseFloat(p[3])
                root.load1 = isNaN(l1) ? 0 : l1
                root.load5 = isNaN(l5) ? 0 : l5
                root.load15 = isNaN(l15) ? 0 : l15
                break
            }
            case "M":
                root.modelName = p[1] === undefined ? "" : p[1]
                break
            case "C": {
                const cl = parseInt(p[1], 10)
                const cp = parseInt(p[2], 10)
                root.coresLogical = isNaN(cl) ? 0 : cl
                root.coresPhysical = isNaN(cp) || cp <= 0 ? root.coresLogical : cp
                break
            }
            }
        }
        root.applyStat(statLines)
    }

    // Usage from two consecutive /proc/stat samples: total and per core.
    // `usageReady` only flips once a real delta exists (second sample on).
    function applyStat(lines) {
        if (lines.length === 0)
            return
        const now = []
        let totalT = 0
        let totalI = 0
        for (let i = 0; i < lines.length; i++) {
            const f = lines[i].split(/\s+/)
            let t = 0
            const last = Math.min(8, f.length - 1)
            for (let j = 1; j <= last; j++)
                t += parseInt(f[j], 10) || 0
            const idle = (parseInt(f[4], 10) || 0) + (parseInt(f[5], 10) || 0)
            if (f[0] === "cpu") {
                totalT = t
                totalI = idle
            } else {
                now.push({ t: t, i: idle })
            }
        }
        if (totalT <= 0)
            return

        const prev = root.prevCores
        const usages = []
        let totalU = root.usage
        if (root.prevTotal > 0) {
            const dt = totalT - root.prevTotal
            if (dt > 0) {
                totalU = clampPct(100 * (dt - (totalI - root.prevIdle)) / dt)
                for (let k = 0; k < now.length; k++) {
                    const before = prev[k]
                    if (before === undefined || before.t === undefined) {
                        usages.push(0)
                        continue
                    }
                    const d = now[k].t - before.t
                    usages.push(d > 0
                        ? clampPct(100 * (d - (now[k].i - before.i)) / d)
                        : (before.u || 0))
                }
                root.usage = totalU
                root.coreUsage = usages
                root.pushHistory(totalU)
                root.usageReady = true
            }
        }

        // Keep this sample as the baseline for the next one
        const keep = []
        for (let k = 0; k < now.length; k++)
            keep.push({ t: now[k].t, i: now[k].i, u: usages[k] === undefined ? 0 : usages[k] })
        root.prevTotal = totalT
        root.prevIdle = totalI
        root.prevCores = keep
    }

    function clampPct(v) {
        return Math.max(0, Math.min(100, v))
    }

    function pushHistory(v) {
        const h = root.history.concat([Math.round(v * 10) / 10])
        root.history = h.length > root.historyLimit
            ? h.slice(h.length - root.historyLimit)
            : h
    }

    // ------------------------------------------------------------------
    // The sample: key/value lines, then `S` and the /proc/stat cpu lines
    // ------------------------------------------------------------------
    readonly property string script:
        "t=\"\"; "
        + "for l in /sys/class/hwmon/hwmon*/temp*_label; do "
        + "[ -r \"$l\" ] || continue; "
        + "case \"$(cat \"$l\" 2>/dev/null)\" in "
        + "\"Package id 0\"|Tctl|Tdie) v=$(cat \"${l%_label}_input\" 2>/dev/null); "
        + "case \"$v\" in ''|*[!0-9]*) ;; *) t=$v; break;; esac;; "
        + "esac; "
        + "done; "
        + "if [ -z \"$t\" ]; then "
        + "for z in /sys/class/thermal/thermal_zone*; do "
        + "[ -r \"$z/temp\" ] || continue; "
        + "case \"$(cat \"$z/type\" 2>/dev/null)\" in "
        + "x86_pkg_temp|*CPU*|*cpu*) v=$(cat \"$z/temp\" 2>/dev/null); "
        + "case \"$v\" in ''|*[!0-9]*) ;; *) t=$v; break;; esac;; "
        + "esac; "
        + "done; "
        + "fi; "
        + "[ -n \"$t\" ] || t=-1; "
        + "printf 'T\t%s\n' \"$t\"; "
        + "fs=0; fn=0; fmin=0; fmax=0; "
        + "for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; do "
        + "[ -r \"$c\" ] || continue; "
        + "v=$(cat \"$c\" 2>/dev/null); "
        + "case \"$v\" in ''|*[!0-9]*) continue;; esac; "
        + "if [ \"$fn\" -eq 0 ]; then fmin=$v; fmax=$v; fi; "
        + "[ \"$v\" -lt \"$fmin\" ] && fmin=$v; "
        + "[ \"$v\" -gt \"$fmax\" ] && fmax=$v; "
        + "fs=$((fs+v)); fn=$((fn+1)); "
        + "done; "
        + "printf 'F\t%s\t%s\t%s\t%s\n' \"$fs\" \"$fn\" \"$fmin\" \"$fmax\"; "
        + "printf 'X\t%s\t%s\n' \"$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null)\" "
        + "\"$(cat /sys/devices/system/cpu/cpu0/cpufreq/base_frequency 2>/dev/null)\"; "
        + "printf 'G\t%s\n' \"$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)\"; "
        + "printf 'E\t%s\n' \"$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null)\"; "
        + "set -- $(cat /proc/loadavg); "
        + "printf 'L\t%s\t%s\t%s\n' \"$1\" \"$2\" \"$3\"; "
        + "m=$(awk -F: '/model name/{sub(/^[ \\t]+/,\"\",$2); print $2; exit}' /proc/cpuinfo); "
        + "[ -n \"$m\" ] || m=$(awk -F: '/^Model|^Hardware/{sub(/^[ \\t]+/,\"\",$2); print $2; exit}' /proc/cpuinfo); "
        + "cl=$(grep -c '^processor' /proc/cpuinfo); "
        + "cp=$(awk -F: '/physical id/{gsub(/[ \\t]/,\"\",$2); s=$2} "
        + "/core id/{gsub(/[ \\t]/,\"\",$2); print s\":\"$2}' /proc/cpuinfo | sort -u | wc -l); "
        + "cl=$((cl+0)); cp=$((cp+0)); "
        + "printf 'M\t%s\n' \"$m\"; "
        + "printf 'C\t%s\t%s\n' \"$cl\" \"$cp\"; "
        + "printf 'S\n'; "
        + "grep '^cpu' /proc/stat"

    Component.onCompleted: root.poll()

    // detail() is 1s, otherwise idlePollMs; changing `interval` restarts the
    // timer, which is exactly what we want when the popup opens/closes.
    Timer {
        interval: Math.max(250, root.detail ? root.pollMs : root.idlePollMs)
        repeat: true
        running: true
        onTriggered: root.poll()
    }

    Process {
        id: sample
        command: ["/bin/sh", "-c", root.script, "sh"]
        stdout: StdioCollector {
            onStreamFinished: root.handleOutput(text)
        }
    }
}
