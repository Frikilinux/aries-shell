import QtQuick
import Quickshell
import "../theme"
import "../config"

Item {
    id: clock

    // Show this module only on specific outputs (monitors).
    // Set to a string ("HDMI-A-1") or array (["eDP-1"]). If undefined/null, shows on all.
    property var outputs
    // The output being rendered.
    property string output: ""

    // How the time is shown (from the user config)
    property string timeFormat: Config.settings.modules.clock.timeFormat
    property bool showSeconds: false

    // What else is shown
    property bool showDate: Config.settings.modules.clock.showDate
    property string dateFormat: "ddd MMM d"

    // Appearance
    property color color: Theme.fgBarColor
    property string fontFamily: Theme.fontFamily
    property int fontSize: Theme.fontSize
    property int spacing: Theme.spacing

    // Keep digits the same width (OpenType "tnum") so the time doesn't jitter
    property bool tabularNumbers: true

    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight

    // Module is visible only if outputs property is unset, matches this output, or contains it
    visible: !outputs || (Array.isArray(outputs) ? outputs.includes(output) : outputs === output)

    SystemClock {
        id: systemClock
        enabled: true
        precision: clock.showSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    Row {
        id: content
        spacing: clock.spacing

        Text {
            visible: clock.showDate
            color: clock.color
            font.family: clock.fontFamily
            font.pixelSize: clock.fontSize
            font.features: clock.tabularNumbers ? ({ "tnum": 1 }) : ({})
            text: Qt.formatDateTime(systemClock.date, clock.dateFormat)
        }

        Text {
            color: clock.color
            font.family: clock.fontFamily
            font.pixelSize: clock.fontSize
            font.features: clock.tabularNumbers ? ({ "tnum": 1 }) : ({})
            text: Qt.formatDateTime(systemClock.date, clock.timeFormat)
        }

    }
}
