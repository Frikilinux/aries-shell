import QtQuick
import "../theme"
import "../icon"

// DeepSeek API off-peak indicator.
//
// Peak (standard price) is weekdays 01:00-04:00 and 06:00-10:00 UTC; weekends
// are entirely off-peak. The bar shows the DeepSeek glyph, green while
// off-peak and red during peak. Clicking it opens the detailed popup.
Item {
    id: offPeak

    // Show this module only on specific outputs (monitors).
    // Set to a string ("HDMI-A-1") or array (["eDP-1"]). If undefined/null, shows on all.
    property var outputs
    // The output being rendered.
    property string output: ""

    // The popup window, exposed for shell.qml.
    property alias popup: popupWindow

    implicitWidth: indicator.implicitWidth
    implicitHeight: indicator.implicitHeight

    // Module is visible only if outputs property is unset, matches this output, or contains it
    visible: !outputs || (Array.isArray(outputs) ? outputs.includes(output) : outputs === output)

    readonly property color statusColor: OffpeakService.peak ? Theme.peakColor : Theme.offPeakColor

    Icon {
        id: indicator
        glyph: "\ue078" // deepseek
        color: offPeak.statusColor
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: popup.visible = !popup.visible
    }

    OffpeakPopup {
        id: popupWindow
        anchorItem: offPeak
    }
}
