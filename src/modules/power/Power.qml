import QtQuick
import "../theme"
import "../icon"

Item {
    id: power

    // Show this module only on specific outputs (monitors).
    // Set to a string ("HDMI-A-1") or array (["eDP-1"]). If undefined/null, shows on all.
    property var outputs
    // The output being rendered.
    property string output: ""

    // The popup window, exposed so shell.qml can configure it (e.g. popup.iconStyle)
    property alias popup: popupWindow

    implicitWidth: indicator.implicitWidth
    implicitHeight: indicator.implicitHeight

    // Module is visible only if outputs property is unset, matches this output, or contains it
    visible: !outputs || (Array.isArray(outputs) ? outputs.includes(output) : outputs === output)

    Icon {
        id: indicator
        glyph: "\ue035" // power
        color: Theme.fgBarColor
        font.pixelSize: Theme.iconSize
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: popup.visible = !popup.visible
    }

    PowerPopup {
        id: popupWindow
        anchorItem: power
    }
}
