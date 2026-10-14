pragma Singleton

import QtQuick
import Quickshell

// Tracks which bar popup is open so that opening one closes any other and a
// click elsewhere on the bar dismisses the current one.
Singleton {
    id: root

    property var current: null

    // Single, central Escape handler for every popup (and the bar). With
    // Qt.ApplicationShortcut it fires whenever any Quickshell window holds
    // keyboard focus, so it does not depend on *which* surface has focus (the
    // bar never takes focus; popups grab it on open via BarPopup.grabKeys()).
    // Quickshell is its own process, so this never intercepts an app's Escape.
    Shortcut {
        sequence: "Escape"
        context: Qt.ApplicationShortcut
        onActivated: root.closeAll()
    }

    function open(win) {
        if (root.current === win)
            return
        if (root.current !== null)
            root.current.visible = false
        root.current = win
    }

    function close(win) {
        if (root.current === win)
            root.current = null
    }

    function closeAll() {
        if (root.current !== null)
            root.current.visible = false
        root.current = null
    }
}
