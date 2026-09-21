import QtQuick
import "../theme"
import "../icon"
import "../config"

Item {
    id: battery

    // Show this module only on specific outputs (monitors).
    // Set to a string ("HDMI-A-1") or array (["eDP-1"]). If undefined/null, shows on all.
    property var outputs
    // The output being rendered.
    property string output: ""

    // The popup window, exposed so shell.qml can configure it (e.g. popup.iconStyle)
    property alias popup: popupWindow
    // Icon style used by this module's bar icon. Defaults to Theme.iconStyle.
    property string iconStyle: Theme.iconStyle

    // Below this percentage (and not charging) the icon turns urgent-colored
    property int lowThreshold: Config.settings.modules.battery.lowThreshold
    // Faint green used while a charge limit is active
    property color limitColor: "#8fbf8f"

    readonly property bool present: BatteryService.present
    readonly property real percent: BatteryService.percentage
    readonly property bool charging: BatteryService.charging
    readonly property bool plugged: BatteryService.pluggedIn
    readonly property bool low: present && percent <= lowThreshold && !charging
    readonly property color stateColor: !present ? Theme.fgBarColor
        : BatteryService.atLimit ? limitColor
        : low ? Theme.urgentColor
        : Theme.fgBarColor

    implicitWidth: indicator.implicitWidth
    implicitHeight: indicator.implicitHeight

    // Module is visible only if outputs property is unset, matches this output, or contains it
    visible: present && (!outputs || (Array.isArray(outputs) ? outputs.includes(output) : outputs === output))

    Icon {
        id: indicator
        // Battery level, with the bolt variant while the charger is plugged in
        glyph: BatteryService.batteryGlyph(battery.percent, battery.plugged)
        style: battery.iconStyle
        color: battery.stateColor
        font.pixelSize: Math.round(Theme.iconSize * 1.4)
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: popup.visible = !popup.visible
    }

    BatteryPopup {
        id: popupWindow
        anchorItem: battery
    }
}
