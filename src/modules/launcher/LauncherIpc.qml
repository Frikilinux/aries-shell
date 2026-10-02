pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../niri"

// External control surface for the launcher popup, so a keybind can open it
// without clicking the bar icon:
//     qs ipc -p <config path> call launcher toggle
//     qs ipc -p <config path> call launcher open
//     qs ipc -p <config path> call launcher close
// The selector (-p / -c / $QS_CONFIG_PATH) must match how the shell was
// launched; plain `qs ipc call` only resolves the default config.
//
// One handler per shell: an IpcHandler inside every bar instance would collide
// on the same target, so each LauncherPopup registers itself here instead.
//
// The popups are built lazily (Loader.active in shell.qml gated on `enabled`):
// nothing exists until the launcher is first opened, then the surfaces stay.
// `show()`/`toggle()` open the popup on the currently focused output (derived
// from niri); `toggleOutput(name)` is used by a bar icon for its own output.
Singleton {
    id: root

    // Registered launcher popups (one per screen); set by LauncherPopup.
    property var popups: []

    // Loaders in shell.qml create the popups; flipped on first use and kept on.
    property bool enabled: false

    // A request arrived before the popups were built; resolved once they
    // register (the timer is restarted on each registration).
    property bool pending: false
    property string pendingOutput: ""

    function registerPopup(win) {
        if (win && root.popups.indexOf(win) === -1)
            root.popups = root.popups.concat([win])
        if (root.pending || root.pendingOutput !== "")
            openTimer.restart()
    }

    function unregisterPopup(win) {
        root.popups = root.popups.filter(w => w !== win)
    }

    // Build the popups if they don't exist yet.
    function ensure() {
        if (!root.enabled)
            root.enabled = true
    }

    // Popups with a screen assigned (all registered ones, in practice).
    function targets() {
        return root.popups.filter(w => w.screen !== null && w.screen !== undefined)
    }

    // Popup bound to a given output name, or null.
    function targetForOutput(name) {
        return root.targets().find(w => w.screen.name === name) || null
    }

    // Popup to open for the keybind: the focused output, falling back to the
    // primary output (global origin) and finally the first when niri focus is
    // unknown or no popup exists on the focused output.
    function focusedTarget() {
        const list = root.targets()
        if (list.length === 0)
            return null
        const out = Niri.focusedOutput
        if (out !== "") {
            const hit = root.targetForOutput(out)
            if (hit)
                return hit
        }
        return list.find(w => w.screen.x === 0 && w.screen.y === 0) || list[0]
    }

    // Show `target` and hide every other launcher popup.
    function openTarget(target) {
        for (const w of root.popups)
            w.visible = (w === target)
    }

    function show() {
        root.ensure()
        if (root.targets().length === 0) {
            root.pending = true
            openTimer.restart()
            return
        }
        root.openTarget(root.focusedTarget())
    }

    function hide() {
        for (const w of root.popups)
            w.visible = false
    }

    function toggle() {
        if (root.popups.some(w => w.visible))
            root.hide()
        else
            root.show()
    }

    // Toggle the popup on a specific output (bar icon click).
    function toggleOutput(name) {
        root.ensure()
        const target = root.targetForOutput(name)
        if (target === null) {
            root.pendingOutput = name
            openTimer.restart()
            return
        }
        if (target.visible)
            target.visible = false
        else
            root.openTarget(target)
    }

    // Resolves a request that arrived before the popups were built. Restarted
    // by each registerPopup so it fires only after the last one registers.
    Timer {
        id: openTimer
        interval: 30
        onTriggered: {
            if (root.pending) {
                root.pending = false
                root.openTarget(root.focusedTarget())
            }
            if (root.pendingOutput !== "") {
                const name = root.pendingOutput
                root.pendingOutput = ""
                const t = root.targetForOutput(name)
                if (t !== null)
                    root.openTarget(t)
            }
        }
    }

    IpcHandler {
        target: "launcher"
        function toggle() { root.toggle() }
        function open() { root.show() }
        function close() { root.hide() }
    }
}
