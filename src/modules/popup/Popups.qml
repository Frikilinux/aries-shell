pragma Singleton

import QtQuick
import Quickshell

// Tracks which bar popup is open so that opening one closes any other and a
// click elsewhere on the bar dismisses the current one.
Singleton {
    id: root

    property var current: null

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
