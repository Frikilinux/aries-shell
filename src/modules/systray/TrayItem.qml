import QtQuick
import "../theme"
// import Quickshell
// import Quickshell.Services.SystemTray

// A single system tray icon button: left click activates, middle click performs
// the secondary action, the wheel scrolls, and right click opens the item's
// DBus context menu (a custom QML menu, see TrayMenu) or falls back to the
// secondary action when the item has no menu.

Item {
    id: root

    // The SystemTrayItem this button represents
    required property var item
    // Displayed icon size in px. Systray sets this from its own `iconSize`;
    // the default keeps the component usable (and sane) standalone.
    property int iconSize: Theme.iconSize

    // Extra hover area around the icon (does not affect layout size)
    property int itemPadding: 5

    // Layout box matches the icon exactly so the bar's uniform Theme.spacing
    // produces equal edge-to-edge gaps between tray icons and other modules.
    implicitWidth: root.iconSize
    implicitHeight: root.iconSize

    TrayIcon {
        anchors.centerIn: parent
        name: root.item.icon
        iconSize: root.iconSize
    }

    // Context menu, dropped below the bar and centered on this icon
    TrayMenu {
        id: trayMenu
        menuHandle: root.item.menu
        anchorItem: root
    }

    function openMenu() {
        if (root.item.hasMenu)
            trayMenu.visible = !trayMenu.visible
        else
            root.item.secondaryActivate()
    }

    MouseArea {
        x: -root.itemPadding
        y: -root.itemPadding
        width: parent.width + root.itemPadding * 2
        height: parent.height + root.itemPadding * 2
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor

        onWheel: (wheel) => {
            const horizontal = Math.abs(wheel.pixelDelta.x) > Math.abs(wheel.pixelDelta.y)
            let delta = horizontal ? wheel.pixelDelta.x : wheel.pixelDelta.y
            if (delta === 0) delta = horizontal ? wheel.angleDelta.x : wheel.angleDelta.y
            root.item.scroll(delta > 0 ? 1 : (delta < 0 ? -1 : 0), horizontal)
        }

        onPressed: (event) => {
            if (event.button === Qt.RightButton) {
                root.openMenu()
                event.accepted = true
            }
        }

        onClicked: (event) => {
            if (event.button === Qt.LeftButton) {
                trayMenu.visible = false
                root.item.activate()
            } else if (event.button === Qt.MiddleButton) {
                trayMenu.visible = false
                root.item.secondaryActivate()
            }
            event.accepted = true
        }
    }
}
