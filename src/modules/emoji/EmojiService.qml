pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Backend of the emoji picker. Owns the bundled emoji database (loaded once
// at boot), the search filter over its rows, the persisted recently-used list
// and the two-step insertion: `queueForTyping()` records the usage and returns
// after the popup has closed, then `typer` runs `wtype` so the compositor
// delivers the emoji as a keyboard input to whatever surface is focused at
// that moment (close popup -> short settle -> type).
//
// Process exit code drives the fallback chain: no `wtype` binary or a failed
// run copies the emoji to the clipboard with `wl-copy` instead (manual paste).
Singleton {
    id: root

    // All rows of emoji-data.json: [{ c, n, g, k }] (char, name, group,
    // keywords). Filled by the boot load; empty until then.
    property var all: []

    property bool loaded: false

    // Live search string typed in the popup.
    property string query: ""

    // Bar icon + popup search glyph (smiley, added to the icon font).
    readonly property string glyph: "\ue08d"

    // Grid geometry from the config (`modules.emoji.*`, clamped so a bad or
    // extreme value can't produce a broken popup): emoji tile size in px and
    // the exact column / visible-row counts of the grid. The popup and cell
    // sizes derive from these (see EmojiPopup).
    readonly property int tileSize: root.intSetting("tileSize", 16, 64, 28)
    readonly property int columns: root.intSetting("columns", 4, 16, 9)
    readonly property int rows: root.intSetting("rows", 3, 14, 7)

    // Clamp-or-default for an int config value (NaN / non-int -> default).
    function intSetting(key, lo, hi, def) {
        const n = parseInt(Config.settings.modules.emoji[key])
        return isNaN(n) ? def : Math.max(lo, Math.min(hi, n))
    }

    // Filtered rows for `query`; an empty query lists everything in dataset
    // order with the recently used emojis first.
    readonly property var results: root.compute(root.query)

    // -------------------------------------------------------------- recents
    // Recently used chars (most recent first), persisted to disk.
    property var recents: []

    readonly property int maxRecents: 36

    readonly property string cacheDir: {
        const xdg = Quickshell.env("XDG_CACHE_HOME")
        const home = Quickshell.env("HOME")
        const base = xdg ? ("" + xdg) : ((home ? "" + home : "") + "/.cache")
        return base + "/aries"
    }

    readonly property string statePath: root.cacheDir + "/emoji.json"

    function recordRecent(char) {
        const next = [char]
        for (let i = 0; i < root.recents.length; i++) {
            const c = root.recents[i]
            if (c !== char) {
                next.push(c)
                if (next.length >= root.maxRecents)
                    break
            }
        }
        root.recents = next
        root.schedulePersist()
    }

    // ---------------------------------------------------------------- search
    // Rows matching `q`: substring match over the emoji name and keywords.
    // Each row is returned as-is (the popup only needs model fields + its own
    // highlight-free rendering, so no match offsets are tracked).
    function compute(q) {
        const rows = root.all
        if (rows.length === 0)
            return []

        if (q.trim() === "")
            return root.withRecents(rows)

        const needle = q.trim().toLowerCase()
        const out = []
        for (let i = 0; i < rows.length; i++) {
            const rec = rows[i]
            if (rec.n.toLowerCase().includes(needle) || rec.k.includes(needle))
                out.push(rec)
        }
        return out
    }

    // Recents first (deduped against the dataset itself), then the rest.
    function withRecents(rows) {
        if (root.recents.length === 0 || rows.length === 0)
            return rows
        const seen = {}
        for (let i = 0; i < rows.length; i++)
            seen[rows[i].c] = true
        // Recents in model order (newest first), deduped against the dataset
        // itself, then the remaining rows in dataset order.
        const head = []
        for (let i = 0; i < root.recents.length; i++) {
            const row = root.byChar[root.recents[i]]
            if (row && seen[row.c] === true) {
                seen[row.c] = false
                head.push(row)
            }
        }
        for (let i = 0; i < rows.length; i++)
            if (seen[rows[i].c] === true)
                head.push(rows[i])
        return head
    }

    // char -> row, for rebuilding recent entries from `recents`.
    readonly property var byChar: {
        const map = {}
        for (let i = 0; i < root.all.length; i++)
            map[root.all[i].c] = root.all[i]
        return map
    }

    // ------------------------------------------------------------- insertion
    // Emoji queued by the popup right after it closed: typed once the popup
    // released Wayland keyboard focus (see the settle timer below).
    property string pendingText: ""

    // Called by the popup right after setting `visible = false` so the usage
    // is recorded while the popup unregisters; the typing starts after the
    // compositor handed focus back to the app.
    function queueForTyping(char) {
        root.pendingText = char
        root.recordRecent(char)
        typeTimer.restart()
    }

    // Resolved by the probe at boot: whether `wtype` / `wl-copy` are usable.
    property bool hasWtype: false
    property bool hasClipboard: false

    function typePending() {
        const char = root.pendingText
        root.pendingText = ""
        if (char === "")
            return
        if (root.hasWtype)
            // `--` ends wtype's option parsing; the emoji is never a flag.
            typer.command = ["wtype", "--", char]
        else if (root.hasClipboard)
            typer.command = ["wl-copy", "--", char]
        else {
            console.warn("emoji: neither wtype nor wl-copy available, cannot insert")
            return
        }
        typer.running = true
    }

    function onTyped(exitCode) {
        // wtype can fail when no text-input-capable surface exists; put the
        // emoji on the clipboard so the character isn't lost.
        if (exitCode === 0 || !root.hasClipboard)
            return
        if (typer.command.length < 3 || typer.command[0] !== "wtype")
            return
        typer.command = ["wl-copy", "--", typer.command[2]]
        typer.running = true
    }

    // ------------------------------------------------------------------ boot
    // Load the bundled database once the shell starts (instant first open).
    FileView {
        id: dataFile
        path: Quickshell.shellDir + "/modules/emoji/emoji-data.json"

        onLoaded: {
            let rows = []
            try {
                rows = JSON.parse(dataFile.text())
            } catch (e) {
                rows = []
            }
            root.all = Array.isArray(rows) ? rows : []
            root.loaded = true
        }

        onLoadFailed: {
            root.all = []
            root.loaded = true
        }
    }

    // Create the cache directory before the first read/write.
    Process {
        id: boot
        command: ["/bin/sh", "-c", "mkdir -p \"$1\"", "sh", root.cacheDir]
        running: true
        onExited: root.loadState()
    }

    function loadState() {
        stateFile.path = root.statePath
        stateFile.reload()
    }

    function onStateLoaded() {
        let parsed = []
        try {
            parsed = JSON.parse(stateFile.text())
        } catch (e) {
            parsed = []
        }
        root.recents = Array.isArray(parsed && parsed.chars) ? parsed.chars : []
        root.persistReady = true
    }

    function onStateLoadFailed() {
        // Missing file is the normal first run.
        root.recents = []
        root.persistReady = true
    }

    property bool persistReady: false

    function schedulePersist() {
        if (root.persistReady)
            persistTimer.restart()
    }

    function writeState() {
        if (!root.persistReady)
            return
        stateFile.setText(JSON.stringify({
            chars: root.recents
        }, null, 2))
    }

    FileView {
        id: stateFile
        atomicWrites: true
        onLoaded: root.onStateLoaded()
        onLoadFailed: function (error) {
            root.onStateLoadFailed()
        }
    }

    Timer {
        id: persistTimer
        interval: 1000
        onTriggered: root.writeState()
    }

    // Types (or copies) `pendingText` once the Wayland keyboard focus is back
    // on the target window. 150ms ~= 2x the bar popup's own 90ms key-grab
    // settle; the compositor needs the layer surface gone before the typed
    // characters reach the right surface.
    Timer {
        id: typeTimer
        interval: 150
        onTriggered: root.typePending()
    }

    Process {
        id: typer
        onExited: function (exitCode) {
            root.onTyped(exitCode)
        }
    }

    // Probe for `wtype` (typed insertion) and `wl-copy` (fallback).
    Process {
        id: probes
        command: ["/bin/sh", "-c", "command -v wtype >/dev/null 2>&1 && echo wtype; command -v wl-copy >/dev/null 2>&1 && echo wlcopy"]
        running: true
        stdout: SplitParser {
            onRead: function (data) {
                if (data.trim() === "wtype")
                    root.hasWtype = true
                if (data.trim() === "wlcopy")
                    root.hasClipboard = true
            }
        }
    }
}
