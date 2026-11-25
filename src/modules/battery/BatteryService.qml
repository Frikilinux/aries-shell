pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// Shared battery state for the bar indicator and its popup.
//
// Charge data comes from UPower (Quickshell.Services.UPower). Charge limits are
// not exposed by UPower (the D-Bus properties are read-only in 1.91), so they
// are read straight from sysfs and written with pkexec (the polkit agent shows
// the usual authentication dialog).
Singleton {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property bool present: device !== null && device.isPresent && device.ready

    // Quickshell reports `percentage` as a 0..1 fraction; expose 0..100.
    // changeRate is in Watts
    readonly property real percentage: present ? device.percentage * 100 : 0
    readonly property int state: present ? device.state : UPowerDeviceState.Unknown
    readonly property real changeRate: present ? device.changeRate : 0
    readonly property real timeToEmpty: present ? device.timeToEmpty : 0
    readonly property real timeToFull: present ? device.timeToFull : 0
    readonly property real energy: present ? device.energy : 0
    readonly property real energyCapacity: present ? device.energyCapacity : 0
    readonly property real healthPercentage: present && device.healthSupported ? device.healthPercentage : -1

    readonly property bool charging: state === UPowerDeviceState.Charging
    readonly property bool discharging: state === UPowerDeviceState.Discharging
    readonly property bool full: state === UPowerDeviceState.FullyCharged

    // Charger connected (charging, full, waiting at a limit, or AC online)
    readonly property bool pluggedIn: present && (!UPower.onBattery || state === UPowerDeviceState.Charging || state === UPowerDeviceState.FullyCharged || state === UPowerDeviceState.PendingCharge)

    // sysfs node for charge thresholds, e.g. BAT0 -> /sys/class/power_supply/BAT0
    readonly property string batteryName: {
        const path = device !== null && device.nativePath ? device.nativePath : ""
        if (path === "")
            return "BAT0"
        const parts = path.split("/")
        return parts[parts.length - 1]
    }
    readonly property string sysfsDir: "/sys/class/power_supply/" + batteryName

    // charge_control_{start,end}_threshold, or -1 when unsupported
    property int startThreshold: -1
    property int endThreshold: -1
    readonly property bool thresholdSupported: endThreshold >= 0
    readonly property bool limitActive: thresholdSupported && endThreshold > 0 && endThreshold < 100
    // Plugged in and no longer charging because the end threshold was reached
    readonly property bool atLimit: thresholdSupported && pluggedIn && !charging && percentage >= endThreshold

    property string applyError: ""
    readonly property bool applying: applyProcess.running

    // Requested thresholds, used to verify the write once it lands
    property int pendingStart: -1
    property int pendingEnd: -1

    function refresh() {
        thresholdReader.running = true
    }

    function parseThresholds(text) {
        const parts = text.trim().split(/\s+/)
        const start = parseInt(parts[0], 10)
        const end = parseInt(parts[1], 10)
        root.startThreshold = isNaN(start) ? -1 : start
        root.endThreshold = isNaN(end) ? -1 : end
        // Verify a pending apply by reading the values back: Dell firmware
        // silently reverts thresholds that break its start <= end - 5 rule.
        if (root.pendingEnd >= 0) {
            if (root.startThreshold === root.pendingStart && root.endThreshold === root.pendingEnd) {
                root.applyError = ""
            } else {
                root.applyError = "Hardware rejected the thresholds: got " + root.startThreshold + "-" + root.endThreshold + "%, expected " + root.pendingStart + "-" + root.pendingEnd + "%"
            }
            root.pendingStart = -1
            root.pendingEnd = -1
        }
    }

    // Charge-limit presets, one libadwaita radio row each in the popup: the
    // title plus the window the battery is kept in. Windows honour the firmware
    // rule start <= end - 5 with start >= 50.
    readonly property var profiles: [
        {
            title: "Always plugged",
            range: "50% \u2013 60%",
            start: 50,
            end: 60
        },
        {
            title: "Battery care",
            range: "70% \u2013 80%",
            start: 70,
            end: 80
        },
        {
            title: "Full charge",
            range: "90% \u2013 100%",
            start: 90,
            end: 100
        }
    ]

    // Apply a charge window as root. `smbios-battery-ctl` (Dell: SMMBIOS tokens,
    // the same store the kernel's sysfs thresholds use) sets the custom
    // interval and switches the firmware to custom mode; machines without the
    // tool fall back to the sysfs thresholds. The script receives the
    // paths/values as positional arguments so they are never interpreted by the
    // shell. Firmware requires start to be at least 5% below end, so when
    // raising the window the end threshold must be written first (and when
    // lowering it, the start first); otherwise the intermediate state is
    // invalid and gets reverted.
    function applyProfile(profile) {
        if (!root.thresholdSupported)
            return
        root.applyError = ""
        root.pendingStart = profile.start
        root.pendingEnd = profile.end
        let script = "d=\"$1\"; s=\"$2\"; e=\"$3\"; "
        script += "if command -v smbios-battery-ctl >/dev/null 2>&1"
        script += " && smbios-battery-ctl --set-custom-charge-interval \"$s\" \"$e\" >/dev/null"
        script += " && smbios-battery-ctl --set-charging-mode=custom >/dev/null; then exit 0; fi; "
        script += "ce=$(cat \"$d/charge_control_end_threshold\" 2>/dev/null || echo 0); "
        script += "if [ \"$e\" -ge \"$ce\" ]; then "
        script += "printf '%s\\n' \"$e\" > \"$d/charge_control_end_threshold\"; "
        script += "printf '%s\\n' \"$s\" > \"$d/charge_control_start_threshold\"; "
        script += "else "
        script += "printf '%s\\n' \"$s\" > \"$d/charge_control_start_threshold\"; "
        script += "printf '%s\\n' \"$e\" > \"$d/charge_control_end_threshold\"; "
        script += "fi"
        applyProcess.command = ["pkexec", "/bin/sh", "-c", script, "sh", root.sysfsDir, String(profile.start), String(profile.end)]
        applyProcess.running = true
    }

    function handleApplyExit(code) {
        if (code === 0) {
            root.applyError = ""
            root.refresh()
        } else if (code === 126 || code === 127) {
            root.pendingStart = -1
            root.pendingEnd = -1
            root.applyError = "Authentication cancelled or not authorized"
        } else {
            root.pendingStart = -1
            root.pendingEnd = -1
            root.applyError = "Could not apply charge limit (code " + code + ")"
        }
    }

    // ------------------------------------------------------------------
    // sched_ext scheduler (CachyOS scx_loader, no ppd). `scxctl get` prints
    // "running Bpfland in PowerSave mode"; without scx_loader the raw ops
    // name from /sys/kernel/sched_ext/root/ops is used instead (version
    // suffix stripped). Read only on open / refresh: it is not polled.
    // ------------------------------------------------------------------
    // "Bpfland  ·  PowerSave" while a scheduler is attached, "" otherwise.
    property string schedulerLabel: ""
    readonly property bool schedulerActive: schedulerLabel !== ""

    function refreshScheduler() {
        schedulerProcess.running = true
    }

    function parseScheduler(text) {
        const raw = String(text).trim()
        if (raw === "") {
            root.schedulerLabel = ""
            return
        }
        const running = /running\s+(\S+)\s+in\s+(\S+)\s+mode/i.exec(raw)
        if (running !== null) {
            root.schedulerLabel = running[1] + "  ·  " + running[2]
            return
        }
        if (/not running|no scheduler|inactive|stopped|disabled/i.test(raw)) {
            root.schedulerLabel = ""
            return
        }
        // Kernel ops name: "<name>_<version>_<arch>_<os>_<libc>" -> "<Name>".
        const short = /^([^_]+)_\d/.exec(raw)
        const name = short === null ? raw : short[1]
        root.schedulerLabel = name.charAt(0).toUpperCase() + name.slice(1)
    }

    Process {
        id: schedulerProcess
        // scxctl only answers while scx_loader runs; otherwise read the kernel
        // ops name. `timeout` keeps a dead daemon from hanging the popup.
        command: {
            let cmd = "out=$(timeout 2 scxctl get 2>/dev/null); "
            cmd += "[ -n \"$out\" ] && printf '%s' \"$out\" "
            cmd += "|| cat /sys/kernel/sched_ext/root/ops 2>/dev/null"
            return ["/bin/sh", "-c", cmd]
        }
        stdout: StdioCollector {
            onStreamFinished: root.parseScheduler(text)
        }
    }

    // Battery level icons: index 0..10 (battery0 empty -> battery10 full)
    readonly property var batteryGlyphs: ["\ue000", "\ue002", "\ue003", "\ue004", "\ue005", "\ue006", "\ue007", "\ue008", "\ue009", "\ue00a", "\ue001"]
    // Charging battery icons: index 0..10 (battery-charge0 -> battery-charge10)
    readonly property var chargeGlyphs: ["\ue00b", "\ue00d", "\ue00f", "\ue010", "\ue011", "\ue012", "\ue013", "\ue014", "\ue015", "\ue016", "\ue00c"]

    // Shown while the charger is connected but the charge has not started yet
    readonly property string saverGlyph: "\ue018"

    // Plain level glyph for a 0..100 percentage, rounded to the nearest 10%
    // step. Ignores the local charger state -> use it for peripheral batteries
    // (Bluetooth devices, phones), which must only reflect their own charge:
    // pass `charging` to pick the battery-with-bolt variant of that device.
    function batteryLevelGlyph(percent, charging) {
        const level = Math.max(0, Math.min(10, Math.round(percent / 10)))
        if (charging === true)
            return root.chargeGlyphs[level]
        return root.batteryGlyphs[level]
    }

    // Battery icon for a 0..100 percentage.
    // When charging, the matching battery-with-bolt variant is returned; while
    // the charge is pending (charger just plugged in) the saver icon is used.
    function batteryGlyph(percent, charging) {
        if (root.state === UPowerDeviceState.PendingCharge)
            return root.saverGlyph
        if (charging)
            return root.chargeGlyphs[Math.max(0, Math.min(10, Math.round(percent / 10)))]
        return root.batteryLevelGlyph(percent)
    }

    readonly property string stateText: {
        switch (state) {
        case UPowerDeviceState.Charging:
            return "Charging"
        case UPowerDeviceState.Discharging:
            return "Discharging"
        case UPowerDeviceState.FullyCharged:
            return "Full"
        case UPowerDeviceState.Empty:
            return "Empty"
        case UPowerDeviceState.PendingCharge:
            return "Charge pending"
        case UPowerDeviceState.PendingDischarge:
            return "Discharge pending"
        default:
            return "Unknown"
        }
    }

    Component.onCompleted: refresh()
    onBatteryNameChanged: refresh()

    Process {
        id: thresholdReader
        command: ["/bin/sh", "-c", "printf '%s %s' " + "\"$(cat \"$1/charge_control_start_threshold\" 2>/dev/null || echo -1)\" " + "\"$(cat \"$1/charge_control_end_threshold\" 2>/dev/null || echo -1)\"", "sh", root.sysfsDir]
        stdout: StdioCollector {
            onStreamFinished: root.parseThresholds(text)
        }
    }

    Process {
        id: applyProcess
        onExited: function (exitCode, exitStatus) {
            root.handleApplyExit(exitCode)
        }
    }
}
