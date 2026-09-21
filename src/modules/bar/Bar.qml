import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../popup"
import "../config"

PanelWindow {
    id: bar

    required property var modelData

    readonly property color bgColor: Theme.bgBarColor
    property real bgOpacity: Theme.bgOpacity
    property real spacing: Config.settings.bar.spacing

    // Wayland layer-shell namespace reported by compositors (e.g. niri msg layers)
    WlrLayershell.namespace: "z-shell"

    // Allow the bar to take keyboard focus on click so that popups with text
    // inputs (e.g. the Wi-Fi password prompt) can receive keystrokes.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // Zones where modules are added (from shell.qml or any Bar instance)
    property alias left: leftRow.data
    property alias center: centerRow.data
    property alias right: rightRow.data

    screen: modelData
    color: Qt.rgba(bar.bgColor.r, bar.bgColor.g, bar.bgColor.b, bar.bgOpacity)

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Config.settings.bar.height

    // A Row that vertically centers its children within the bar. A plain Row
    // top-aligns children of differing heights, so anchor each one.
    component Zone: Row {
        spacing: bar.spacing

        Component.onCompleted: {
            for (let i = 0; i < children.length; i++)
                children[i].anchors.verticalCenter = verticalCenter
        }
    }

    // Clicking empty space (or a module without its own handler) dismisses popups
    MouseArea {
        anchors.fill: parent
        onClicked: Popups.closeAll()
    }

    // Popups are layer-shell surfaces (not xdg popups), so they no longer grab
    // keys or auto-dismiss. The click that opens a popup leaves keyboard focus
    // on the bar, so Esc is handled here (plus per-popup Shortcut for when the
    // popup itself has focus, e.g. after typing in the Wi-Fi field).
    Shortcut {
        sequence: "Escape"
        onActivated: Popups.closeAll()
    }

    Zone {
        id: leftRow
        anchors.left: parent.left
        anchors.leftMargin: bar.spacing
        anchors.verticalCenter: parent.verticalCenter
    }

    Zone {
        id: centerRow
        anchors.centerIn: parent
    }

    Zone {
        id: rightRow
        anchors.right: parent.right
        anchors.rightMargin: bar.spacing
        anchors.verticalCenter: parent.verticalCenter
    }
}
