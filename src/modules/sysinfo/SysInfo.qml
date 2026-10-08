import QtQuick
import "../theme"
import "../icon"
import "../config"

// CPU temperature in the bar: thermometer glyph + current package value.
// The number shares the thermometer's color (normal / warm / hot), and the
// module hides itself when the machine exposes no temperature sensor.
Item {
    id: sysInfo

    // Show this module only on specific outputs (monitors).
    // Set to a string ("HDMI-A-1") or array (["eDP-1"]). If undefined/null, shows on all.
    property var outputs
    // The output being rendered.
    property string output: ""

    // The popup window, exposed for shell.qml.
    property alias popup: popupWindow

    readonly property real temperature: SysInfoService.temperature
    readonly property bool hasTemperature: SysInfoService.hasTemp
    readonly property color stateColor: Theme.temperatureColor(sysInfo.temperature, Theme.fgBarColor)

    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight

    // Module is visible only if outputs property is unset, matches this output, or contains it
    visible: SysInfoService.hasTemp
        && (!outputs || (Array.isArray(outputs) ? outputs.includes(output) : outputs === output))

    // A plain Row would top-align the glyph and the value (differing heights),
    // so the two are anchored inside an Item instead.
    Item {
        id: content

        implicitWidth: tempValue.implicitWidth + 4 + tempIcon.implicitWidth
        implicitHeight: Math.max(tempIcon.implicitHeight, tempValue.implicitHeight)

        Icon {
            id: tempIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            glyph: "\ue085" // cpu
            color: sysInfo.stateColor
            font.pixelSize: Math.round(Theme.iconSize * 1.1)
        }

        Text {
            id: tempValue
            anchors.left: tempIcon.right
            anchors.leftMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            text: sysInfo.hasTemperature ? Math.round(sysInfo.temperature) + "\u00b0" : "\u2014"
            color: sysInfo.stateColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
            font.features: { "tnum": 1 }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: sysInfo.popup.visible = !sysInfo.popup.visible
    }

    SysInfoPopup {
        id: popupWindow
        anchorItem: sysInfo
    }
}
