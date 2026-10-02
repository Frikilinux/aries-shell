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
// The launcher popups are independent per-screen overlays (created in
// shell.qml), so `show()` opens the one on the currently focused output
// (derived from niri) instead of every monitor or the primary one.
Singleton {
    id: root

    // Registered launcher popups (one per screen); set by LauncherPopup.
    property var popups: []

    function registerPopup(win) {
        if (win && root.popups.indexOf(win) === -1)
            root.popups = root.popups.concat([win])
    }

    function unregisterPopup(win) {
        root.popups = root.popups.filter(w => w !== win)
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
        const target = root.targetForOutput(name)
        if (target === null)
            return
        if (target.visible)
            target.visible = false
        else
            root.openTarget(target)
    }

    IpcHandler {
        target: "launcher"
        function toggle() { root.toggle() }
        function open() { root.show() }
        function close() { root.hide() }
    }
}
