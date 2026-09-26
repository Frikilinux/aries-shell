import QtQuick
import "../theme"
import "../icon"

Item {
    id: bluetooth

    // Show this module only on specific outputs (monitors).
    // Set to a string ("HDMI-A-1") or array (["eDP-1"]). If undefined/null, shows on all.
    property var outputs
    // The output being rendered.
    property string output: ""

    // The popup window, exposed so shell.qml can configure it (e.g. popup.iconStyle)
    property alias popup: popupWindow
    // Icon style used by this module's bar icon. Defaults to Theme.iconStyle.
    property string iconStyle: Theme.iconStyle

    implicitWidth: indicator.implicitWidth
    implicitHeight: indicator.implicitHeight

    // Module is visible only if outputs property is unset, matches this output, or contains it
    visible: !outputs || (Array.isArray(outputs) ? outputs.includes(output) : outputs === output)

    Icon {
        id: indicator
        glyph: popup.stateGlyph
        style: bluetooth.iconStyle
        color: Theme.fgBarColor
        opacity: popup.adapterEnabled ? (popup.connectedCount > 0 ? 1 : 0.6) : 0.35
        font.pixelSize: Math.round(Theme.iconSize * 1)
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: popup.visible = !popup.visible
    }

    BluetoothPopup {
        id: popupWindow
        anchorItem: bluetooth
    }
}
