pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// External control surface for the history popup, so a keybind can open it
// without clicking the bar icon:
//     qs ipc -p <config path> call notifications toggle
//     qs ipc -p <config path> call notifications open
//     qs ipc -p <config path> call notifications close
// The selector (-p / -c / $QS_CONFIG_PATH) must match how the shell was
// launched; plain `qs ipc call` only resolves the default config.
//
// One handler per shell: an IpcHandler inside every bar instance would collide
// on the same target, so each NotificationHistory registers itself here instead.
// `show()` only opens popups whose bar module is on screen (outputs filter);
// `hide()` closes them all. Opening runs BarPopup's onVisibleChanged ->
// popupOpened() -> markRead(), so the badge clears like a click does.
Singleton {
    id: root

    // Registered history popups (one per bar); set by NotificationHistory.
    property var historyPopups: []

    function registerPopup(win) {
        if (win && root.historyPopups.indexOf(win) === -1)
            root.historyPopups = root.historyPopups.concat([win])
    }

    function unregisterPopup(win) {
        root.historyPopups = root.historyPopups.filter(w => w !== win)
    }

    // Popups on outputs where the bar module lives. This mirrors the module's
    // own `outputs` filter instead of testing `anchorItem.visible`: the module
    // now hides itself whenever everything is read (no pill, no DND), and
    // opening marks everything read, so a visibility-based filter would make
    // `open`/`toggle` a no-op right after the first use.
    function targetable(w) {
        const a = w.anchorItem
        if (!a)
            return false
        if (!a.outputs)
            return true
        return Array.isArray(a.outputs) ? a.outputs.includes(a.output) : a.outputs === a.output
    }

    function targets() {
        return root.historyPopups.filter(w => root.targetable(w))
    }

    function show() {
        for (const w of root.targets())
            w.visible = true
    }

    function hide() {
        for (const w of root.historyPopups)
            w.visible = false
    }

    function toggle() {
        if (root.historyPopups.some(w => w.visible))
            root.hide()
        else
            root.show()
    }

    IpcHandler {
        target: "notifications"
        function toggle() { root.toggle() }
        function open() { root.show() }
        function close() { root.hide() }
    }
}
