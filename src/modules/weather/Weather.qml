import QtQuick
import "../theme"
import "../icon"

Item {
    id: weather

    // Show this module only on specific outputs (monitors).
    // Set to a string ("HDMI-A-1") or array (["eDP-1"]). If undefined/null, shows on all.
    property var outputs
    // The output being rendered.
    property string output: ""

    readonly property int spacing: Theme.spacing

    // The popup window, exposed so shell.qml can configure it (e.g. popup.iconStyle)
    property alias popup: popupWindow
    // Icon style used by this module's bar icon. Defaults to Theme.iconStyle.
    property string iconStyle: Theme.iconStyle

    implicitWidth: indicator.implicitWidth
        + (WeatherService.available ? tempLabel.implicitWidth : 0)
    implicitHeight: Math.max(indicator.implicitHeight, tempLabel.implicitHeight)

    // Module is visible only if outputs property is unset, matches this output, or contains it
    visible: !outputs || (Array.isArray(outputs) ? outputs.includes(output) : outputs === output)

    Icon {
        id: indicator
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        glyph: WeatherService.iconGlyph
        style: weather.iconStyle
        color: Theme.fgBarColor
        opacity: WeatherService.available ? 1 : 0.5
    }

    Text {
        id: tempLabel
        anchors.left: indicator.right
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        visible: WeatherService.available
        text: WeatherService.temp + "°"
        color: Theme.fgBarColor
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.features: ({ "tnum": 1 })
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: popup.visible = !popup.visible
    }

    WeatherPopup {
        id: popupWindow
        anchorItem: weather
    }
}
