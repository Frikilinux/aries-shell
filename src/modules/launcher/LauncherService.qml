pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Application launcher backend. Exposes the XDG desktop entries, a fuzzy
// ranked search over name / description / categories, and a persisted usage
// counter so the most-used apps come first. Shared by the bar icon and the
// popup. `results` is the ranked match list; `launch()` runs one.
Singleton {
    id: root

    // Every launchable desktop entry (visible, with a Name and an Exec line).
    // Bound to the model's `values` so it re-evaluates while the async scan
    // fills the list (`applications` itself is a constant property).
    readonly property var apps: {
        const model = DesktopEntries.applications
        const vals = model ? model.values : []
        const out = []
        for (let i = 0; i < vals.length; i++) {
            const e = vals[i]
            if (!e || e.noDisplay || !e.name)
                continue
            if (!e.command || e.command.length === 0)
                continue
            out.push(e)
        }
        return out
    }

    // Live search string typed in the popup.
    property string query: ""

    // Grid/apps glyph shared by the bar icon and the popup search box.
    readonly property string glyph: "\ue082"

    // Ranked matches for `query`: [{ entry, name, subtitle, nameHits, subHits,
    // score, uses }], best first. An empty query lists every app by usage
    // (most used first, then alphabetical).
    readonly property var results: root.compute(root.query)

    // ---------------------------------------------------------------- usage
    // Launch counts keyed by desktop-entry id: { "<id>": { count, last } }.
    property var usage: ({})
    // True once the on-disk cache has been read (or confirmed absent).
    property bool loaded: false

    readonly property string cacheDir: {
        const xdg = Quickshell.env("XDG_CACHE_HOME")
        const home = Quickshell.env("HOME")
        const base = xdg ? ("" + xdg) : ((home ? "" + home : "") + "/.cache")
        return base + "/aries"
    }
    readonly property string statePath: root.cacheDir + "/launcher.json"

    function usageOf(entry) {
        if (!entry || !entry.id)
            return 0
        const u = root.usage[entry.id]
        return u ? u.count : 0
    }

    function recordUsage(entry) {
        if (!entry || !entry.id)
            return
        const cur = root.usage[entry.id] || { count: 0, last: 0 }
        const next = {}
        for (const k in root.usage)
            next[k] = root.usage[k]
        next[entry.id] = { count: cur.count + 1, last: Date.now() }
        root.usage = next
        root.schedulePersist()
    }

    // ---------------------------------------------------------------- search
    function compute(q) {
        const list = []
        const needle = q.trim().toLowerCase()
        for (let i = 0; i < root.apps.length; i++) {
            const rec = root.record(root.apps[i], needle)
            if (rec.score >= 0)
                list.push(rec)
        }
        // Relevance first; usage breaks ties and orders the empty query.
        list.sort((a, b) => b.score - a.score || b.uses - a.uses || a.name.localeCompare(b.name))
        return list.slice(0, 200)
    }

    // One match record. `score` is the best weighted field score (name ranks
    // highest, then keywords/generic name, description and category). `nameHits`
    // / `subHits` are the matched character indices for highlighting.
    function record(entry, needle) {
        const sub = root.subtitle(entry)
        if (needle === "") {
            return {
                entry: entry, name: entry.name, subtitle: sub,
                nameHits: [], subHits: [], score: 0, uses: root.usageOf(entry),
            }
        }

        const score = Math.max(
            root.scoreText(needle, entry.name),
            root.scoreText(needle, entry.genericName) * 0.85,
            root.scoreText(needle, (entry.keywords || []).join(" ")) * 0.75,
            root.scoreText(needle, entry.comment) * 0.7,
            root.scoreText(needle, (entry.categories || []).join(" ")) * 0.6
        )
        return {
            entry: entry, name: entry.name, subtitle: sub,
            nameHits: root.matchIndices(needle, entry.name),
            subHits: root.matchIndices(needle, sub),
            score: score, uses: root.usageOf(entry),
        }
    }

    // Second line under the name: description, else the category list.
    function subtitle(entry) {
        if (entry.comment)
            return entry.comment
        return (entry.categories || []).join(", ")
    }

    // Fuzzy score of `needle` (lowercase) against `hay`, or -1 when it does not
    // match. Substring hits rank above scattered subsequences; word starts,
    // adjacency and an early position add bonus points.
    function scoreText(needle, hay) {
        if (needle === "")
            return 0
        const t = ("" + (hay || "")).toLowerCase()
        if (t === "")
            return -1

        const idx = t.indexOf(needle)
        if (idx >= 0) {
            let s = 1000 - idx * 3 - Math.min(t.length, 60)
            if (idx === 0 || !root.isWordChar(t.charAt(idx - 1)))
                s += 150
            return s
        }

        let pos = 0
        let prev = -2
        let streak = 0
        let score = 0
        for (let i = 0; i < needle.length; i++) {
            const ch = needle.charAt(i)
            let found = -1
            for (let k = pos; k < t.length; k++) {
                if (t.charAt(k) === ch) {
                    found = k
                    break
                }
            }
            if (found === -1)
                return -1
            streak = found === prev + 1 ? streak + 1 : 0
            let bonus = streak > 0 ? 6 * streak : 0
            if (found === 0 || !root.isWordChar(t.charAt(found - 1)))
                bonus += 10
            score += 8 + bonus - Math.min(found - pos, 5)
            prev = found
            pos = found + 1
        }
        return score
    }

    // Character indices in `hay` matched by `needle`, for highlighting. Mirrors
    // scoreText's strategy (substring first, else subsequence). Empty if none.
    function matchIndices(needle, hay) {
        if (!needle)
            return []
        const t = ("" + (hay || "")).toLowerCase()
        if (t === "")
            return []

        const out = []
        const idx = t.indexOf(needle)
        if (idx >= 0) {
            for (let i = 0; i < needle.length; i++)
                out.push(idx + i)
            return out
        }

        let pos = 0
        for (let i = 0; i < needle.length; i++) {
            const ch = needle.charAt(i)
            let found = -1
            for (let k = pos; k < t.length; k++) {
                if (t.charAt(k) === ch) {
                    found = k
                    break
                }
            }
            if (found === -1)
                return []
            out.push(found)
            pos = found + 1
        }
        return out
    }

    // Build StyledText markup for `text`, colouring the matched characters
    // (`hits`) with `color`. HTML-escapes everything else.
    function highlight(text, hits, color) {
        const s = "" + (text || "")
        if (!hits || hits.length === 0)
            return root.escapeHtml(s)

        const set = {}
        for (let i = 0; i < hits.length; i++)
            set[hits[i]] = true

        let out = ""
        let open = false
        for (let i = 0; i < s.length; i++) {
            const on = set[i] === true
            if (on && !open) {
                out += "<font color=\"" + color + "\">"
                open = true
            } else if (!on && open) {
                out += "</font>"
                open = false
            }
            out += root.escapeHtml(s.charAt(i))
        }
        if (open)
            out += "</font>"
        return out
    }

    function escapeHtml(s) {
        return ("" + (s || ""))
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;")
    }

    function isWordChar(c) {
        return /[a-z0-9]/.test(c)
    }

    // Resolve an entry's icon to an Image source (themed lookup, then raw path).
    function iconSource(entry) {
        if (!entry || !entry.icon)
            return ""
        const ic = entry.icon
        if (ic.charAt(0) === "/")
            return "file://" + ic
        const p = Quickshell.iconPath(ic, true)
        return p !== "" ? p : ""
    }

    // ------------------------------------------------------------- terminal
    // Apps whose desktop entry sets `Terminal=true` must run inside a terminal
    // emulator. Quickshell's `entry.execute()` ignores `runInTerminal`, so the
    // launcher wraps the command itself. The emulator comes from the config
    // (`modules.launcher.terminal`); an empty value falls back to $TERMINAL.
    readonly property string terminal: {
        const t = ("" + (Config.settings.modules.launcher.terminal || "")).trim()
        return t !== "" ? t : ("" + (Quickshell.env("TERMINAL") || "")).trim()
    }

    // Command separator expected by `name` (the terminal's basename). Most
    // terminals take `-e <cmd...>`; a few use different conventions.
    function terminalSeparator(name) {
        if (name === "wezterm")
            return ["start", "--"]
        if (name === "gnome-terminal" || name === "kgx" || name === "ptyxis"
            || name === "tilix" || name === "terminator")
            return ["--"]
        return ["-e"]
    }

    // Full argv to run `entry` inside the configured terminal, or [] when no
    // terminal is configured. Options already present in the config are kept;
    // a separator the user typed themselves is not duplicated.
    function terminalArgv(entry) {
        const t = root.terminal
        if (t === "")
            return []
        const tokens = t.split(/\s+/)
        const name = tokens[0].replace(/.*\//, "")
        const cmd = entry.command ? [].concat(entry.command) : []
        const hasSep = tokens.some(x => x === "-e" || x === "--" || x === "start")
        if (hasSep)
            return [].concat(tokens, cmd)
        return [].concat(tokens, root.terminalSeparator(name), cmd)
    }

    // Run the entry and count the use (so frequent apps rise to the top).
    function launch(entry) {
        if (!entry)
            return
        root.recordUsage(entry)
        if (entry.runInTerminal) {
            const argv = root.terminalArgv(entry)
            if (argv.length > 0) {
                Quickshell.execDetached({
                    command: argv,
                    workingDirectory: entry.workingDirectory
                })
                return
            }
        }
        entry.execute()
    }

    // ----------------------------------------------------------- persistence
    function schedulePersist() {
        if (!root.loaded)
            return
        persistTimer.restart()
    }

    function writeState() {
        if (!root.loaded)
            return
        stateFile.setText(JSON.stringify(root.usage, null, 2))
    }

    function loadState() {
        stateFile.path = root.statePath
        stateFile.reload()
    }

    function onStateLoaded() {
        let parsed = {}
        try {
            parsed = JSON.parse(stateFile.text())
        } catch (e) {
            parsed = {}
        }
        if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
            parsed = {}
        root.usage = parsed
        root.loaded = true
    }

    function onStateLoadFailed(error) {
        // Missing file is the normal first run: stay empty and let the first
        // debounced write create it.
        root.loaded = true
    }

    // Create the cache directory before the first read/write.
    Process {
        id: boot
        command: ["/bin/sh", "-c", "mkdir -p \"$1\"", "sh", root.cacheDir]
        running: true
        onExited: root.loadState()
    }

    FileView {
        id: stateFile
        atomicWrites: true
        onLoaded: root.onStateLoaded()
        onLoadFailed: function (error) { root.onStateLoadFailed(error) }
    }

    // Coalesces rapid launches into a single disk write.
    Timer {
        id: persistTimer
        interval: 1000
        onTriggered: root.writeState()
    }
}
