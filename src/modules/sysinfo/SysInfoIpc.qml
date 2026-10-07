pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// External control surface for the system-info popup, so a keybind can open it
// without clicking the bar icon:
//     qs ipc -p <config path> call sysinfo toggle
//     qs ipc -p <config path> call sysinfo open
//     qs ipc -p <config path> call sysinfo close
// The selector (-p / -c / $QS_CONFIG_PATH) must match how the shell was
// launched; plain `qs ipc call` only resolves the default config.
//
// One handler per shell: an IpcHandler inside every bar instance would collide
// on the same target, so each popup registers itself here instead.
// `show()` only opens popups whose bar module is on screen (outputs filter).
Singleton {
    id: root

    // Registered popups (one per bar); set by SysInfoPopup.
    property var popups: []

    function registerPopup(win) {
        if (win && root.popups.indexOf(win) === -1)
            root.popups = root.popups.concat([win])
    }

    function unregisterPopup(win) {
        root.popups = root.popups.filter(w => w !== win)
    }

    // Popups whose bar module is actually shown on its output.
    function targets() {
        return root.popups.filter(w => w.anchorItem && w.anchorItem.visible)
    }

    function show() {
        for (const w of root.targets())
            w.visible = true
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

    IpcHandler {
        target: "sysinfo"
        function toggle() { root.toggle() }
        function open() { root.show() }
        function close() { root.hide() }
    }
}
