import QtQuick
import "../theme"
import "../icon"

Item {
    id: rss

    // Show this module only on specific outputs (monitors).
    // Set to a string ("HDMI-A-1") or array (["eDP-1"]). If undefined/null, shows on all.
    property var outputs
    // The output being rendered.
    property string output: ""

    // The popup window, exposed for shell.qml.
    property alias popup: popupWindow

    implicitWidth: indicator.implicitWidth
    implicitHeight: indicator.implicitHeight

    // The module is visible only while there is news (no read state), and only
    // if outputs is unset, matches this output, or contains it.
    visible: (!outputs || (Array.isArray(outputs) ? outputs.includes(output) : outputs === output))
        && RssService.hasNews

    Icon {
        id: indicator
        anchors.centerIn: parent
        glyph: RssService.iconGlyph
        color: Theme.fgBarColor
        font.pixelSize: Math.round(Theme.iconSize * 1.2)
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: rss.popup.visible = !rss.popup.visible
    }

    RssPopup {
        id: popupWindow
        anchorItem: rss
    }
}
