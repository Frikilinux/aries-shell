pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// User configuration for the bar.
//
// Settings live in a JSON file (default:
// `$XDG_CONFIG_HOME/aries/config.json`, falling back to
// `~/.config/aries/config.json`). On startup the file and its parent
// directory are created if missing, filled with the hardcoded defaults below.
// Values from the file are merged over those defaults (the user's values win;
// unknown keys are ignored). A broken/empty file falls back to the defaults.
//
// `settings` holds the merged, canonical runtime object. QML bindings read
// values through it (e.g. `Config.settings.modules.clock.timeFormat`), so any
// re-apply (Config.read/save/update) live-updates every bound widget.
Singleton {
    id: root

    // ------------------------------------------------------------------
    // Load state
    // ------------------------------------------------------------------
    property bool ready: false
    property int revision: 0
    property string loadError: ""
    // Last config file contents that were applied/saved; `onFileLoaded()`
    // re-applies only when the file really differs (avoids reacting to our own
    // save()).
    property string lastRaw: ""

    // First arg of outputs() must be `root.revision`: it makes the shell's
    // `outputs:` bindings re-evaluate every time the config is (re)applied.
    function outputs(revision, moduleName, screenName) {
        const o = root.settings.modules[moduleName].outputs
        if (o === undefined || o === null || o === "*"
            || (Array.isArray(o) && o.indexOf("*") !== -1))
            return undefined                       // all screens
        const list = Array.isArray(o) ? o : [o]
        if (list.length === 0)
            return list
        if (list.includes(screenName)
            || (list.includes("primary") && screenName === root.primaryScreen))
            return [screenName]
        return []
    }

    // Screen with the global origin (0,0) is treated as the primary monitor;
    // falls back to the first screen when no output sits at the origin.
    readonly property string primaryScreen: {
        const screens = Quickshell.screens
        for (let i = 0; i < screens.length; i++) {
            if (screens[i].x === 0 && screens[i].y === 0)
                return screens[i].name
        }
        return screens.length > 0 ? screens[0].name : ""
    }

    // ------------------------------------------------------------------
    // Config file location
    // ------------------------------------------------------------------
    readonly property string configDir: {
        const xdg = Quickshell.env("XDG_CONFIG_HOME")
        const home = Quickshell.env("HOME")
        const base = xdg ? ("" + xdg) : ((home ? "" + home : "") + "/.config")
        return base + "/aries"
    }
    readonly property string configPath: root.configDir + "/config.json"

    // ------------------------------------------------------------------
    // Defaults (also the first-run contents of the user's config file)
    // ------------------------------------------------------------------
    readonly property var defaults: ({
        bar: {
            height: 30,
            spacing: 10,
            reloadOnChange: true
        },
        font: {
            family: "SF Compact Display",
            styleName: "Regular",
            size: 17
        },
        colors: {
          fgBarColor: "#9198a1",
          bgBarColor: "#151b23",
          bgColor: "#212830",
          bgColorMuted: "#262c36",
          overlayBgColor: "#2a313c",
          bgOpacity: 0.9,
          fgColor: "#d1d7e0",
          fgColorMuted: "#9198a1",
          buttonPrimaryBgColor: "#347d39",
          buttonChipBgColor: "#76b9002e",
          buttonBgColor: "#2a313c",
          buttonBorder: "#3d444db3",
          accent: "#478be6",
          urgent: "#e0af68",
          offPeak: "#3fb950",
          peak: "#f85149",
          popupBorder: "#3d444db3",
          popupRadius: 13,
          popupBorderWidth: 1
        },
        modules: {
            workspaces:   { outputs: ["primary"] },
            activeWindow: { outputs: ["primary"], maxLabelWidth: 200, appNames: {} },
            mpris:        { outputs: ["primary"], maxLabelWidth: 180 },
            systray:      { outputs: ["primary"] },
            bluetooth:    { outputs: ["primary"] },
            network:      { outputs: ["primary"] },
            volume:       { outputs: ["primary"], scrollStep: 0.03, naturalScroll: true },
            battery:      { outputs: ["primary"], lowThreshold: 20 },
            clock:        { outputs: ["primary"], timeFormat: "HH:mm", showDate: true },
            weather:      { outputs: ["primary"],
                            apiKey: "",
                            apiKeyDaily: "",
                            latitude: "-34.6",
                            longitude: "-60.4",
                            units: "metric" },
            power:        { outputs: ["primary"] },
            offpeak:      { outputs: ["primary"] },
            wallpaper:    { outputs: "*",
                            path: "",
                            fillMode: "crop",
                            position: "center",
                            dim: 0.0 }
        }
    })

    readonly property string defaultText: JSON.stringify(root.defaults, null, 4)

    // ------------------------------------------------------------------
    // Canonical merged settings (user values over the defaults)
    // ------------------------------------------------------------------
    property var settings: root.defaults

    // Merge `over` into `base`, following the base schema (unknown keys in
    // `over` are dropped, so typos don't slip into settings). Plain objects are
    // recursed; everything else (scalars, arrays) takes the user's value as-is.
    // Map keys passed in `additive` (e.g. appNames) are additive key→value
    // maps: the user's entries are merged ON TOP of the defaults, so new appIds
    // the user adds are kept instead of being dropped as unknown keys.
    function merge(base, over, additive) {
        if (over === undefined || over === null || typeof over !== "object")
            return over
        const out = {}
        for (const k in base) {
            const b = base[k]
            const o = over[k]
            if (additive !== undefined && k in additive) {
                const map = (o === undefined || o === null || typeof o !== "object") ? {} : o
                out[k] = {}
                for (const bk in b)
                    out[k][bk] = b[bk]
                for (const ok in map)
                    out[k][ok] = map[ok]
            } else if (b !== null && typeof b === "object" && !Array.isArray(b)) {
                out[k] = o === undefined ? b : root.merge(b, o, additive)
            } else {
                out[k] = o === undefined ? b : o
            }
        }
        return out
    }

    // Replace the canonical settings with a (re)merge, then wake up the bound
    // widgets via `revision`. Also called after save()/update() to refresh.
    function apply(over) {
        root.settings = over === undefined ? root.defaults : root.merge(root.defaults, over, { appNames: true })
        root.ready = true
        root.revision++
        root.syncWatch()
    }

    // Give the FileView its config path once the file exists (the watcher can't
    // watch a missing path, and boot() creates it). Called on every apply, but
    // FileView ignores repeated identical path assignments.
    function syncWatch() {
        if (!fileWatch || fileWatch.path === root.configPath)
            return
        fileWatch.path = root.configPath
    }

    function parseConfig(text) {
        root.lastRaw = text
        try {
            const data = JSON.parse(text)
            root.loadError = ""
            root.apply(data)
        } catch (e) {
            root.loadError = "config: invalid JSON at " + root.configPath
            if (root.ready) {
                // Keep the last good settings during a transient edit (the
                // editor writes in two steps); only the first boot falls back.
            } else {
                root.apply(root.defaults)
            }
        }
    }

    // Called when FileView finishes (re)reading the file (after fileChanged ->
    // reload, or the initial read). The text is fresh here, unlike text() right
    // after an (async) reload() call. Only re-apply when the contents differ
    // from the last thing we applied/saved.
    //
    // The OS-level watcher is always armed; the bar.reloadOnChange toggle only
    // gates re-application here. When it is off, edits are ignored UNLESS they
    // are the very edit that re-enables the toggle (otherwise you could never
    // turn it back on just by editing the file).
    function onFileLoaded() {
        if (!root.ready)
            return
        const text = fileWatch.text()
        if (text === "" || text === root.lastRaw)
            return
        if (root.settings.bar.reloadOnChange === false) {
            let enables = false
            try { enables = JSON.parse(text).bar.reloadOnChange !== false } catch (e) {}
            if (!enables)
                return
        }
        root.parseConfig(text)
    }

    // Create directory + file if missing, then read the contents.
    function load() {
        root.loadError = ""
        boot.command = ["/bin/sh", "-c",
            "d=\"$1\"; f=\"$2\"; mkdir -p \"$d\"; "
                + "[ -f \"$f\" ] || printf '%s' \"$3\" > \"$f\"; cat \"$f\"",
            "sh", root.configDir, root.configPath, root.defaultText]
        boot.running = true
    }

    // Re-read the file from disk and re-apply (used by the future settings UI).
    function reload() {
        root.load()
    }

    // Mutate a module's setting and re-apply so bindings update live.
    function setModule(moduleName, key, value) {
        root.update(s => { s.modules[moduleName][key] = value })
    }

    // Mutate the canonical settings through a callback, then re-apply.
    function update(callback) {
        const next = JSON.parse(JSON.stringify(root.settings))
        callback(next)
        root.apply(next)
    }

    // Persist the current canonical settings to disk.
    function save() {
        const text = JSON.stringify(root.settings, null, 4)
        root.lastRaw = text
        saveProcess.command = ["/bin/sh", "-c",
            "d=\"$1\"; f=\"$2\"; mkdir -p \"$d\"; printf '%s' \"$3\" > \"$f\"",
            "sh", root.configDir, root.configPath, text]
        saveProcess.running = true
    }

    Component.onCompleted: {
        root.load()
    }

    // Watches the config file (inotify underneath) so external edits re-apply
    // live. Always armed: the bar.reloadOnChange toggle only gates re-apply in
    // onFileLoaded(). `loaded` fires whenever a (re)read finishes, so `text()`
    // there is always current.
    FileView {
        id: fileWatch
        watchChanges: true
        onFileChanged: fileWatch.reload()
        onLoaded: root.onFileLoaded()
    }

    Process {
        id: boot
        stdout: StdioCollector {
            onStreamFinished: root.parseConfig(text)
        }
        onExited: function (exitCode, exitStatus) {
            if (!root.ready)
                root.apply(root.defaults)
        }
    }

    Process {
        id: saveProcess
    }
}
