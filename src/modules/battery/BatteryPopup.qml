import QtQuick
import "../theme"
import "../icon"
import "../popup"

BarPopup {
    id: popup

    // Icon style used by this popup's icons. Defaults to Theme.iconStyle.
    property string iconStyle: Theme.iconStyle

    // Selectable charge profiles (end threshold, %)
    property var profiles: [60, 80, 100]

    readonly property bool showPower: Math.abs(BatteryService.changeRate) >= 0.05
    readonly property string powerLabel: BatteryService.discharging ? "Consumption" : "Charge"
    readonly property string powerText: Math.abs(BatteryService.changeRate).toFixed(1) + " W"

    readonly property string timeLabel: BatteryService.discharging ? "Time remaining" : "Time to full"
    readonly property string timeText: popup.formatDuration(
        BatteryService.discharging ? BatteryService.timeToEmpty : BatteryService.timeToFull)

    readonly property bool showHealth: BatteryService.healthPercentage >= 0
    readonly property string energyText: BatteryService.energy.toFixed(1) + " / "
        + BatteryService.energyCapacity.toFixed(1) + " Wh"
    readonly property string healthText: Math.round(BatteryService.healthPercentage) + "%"

    function formatDuration(seconds) {
        if (!(seconds > 0))
            return "\u2014"
        const total = Math.floor(seconds / 60)
        const hours = Math.floor(total / 60)
        const minutes = total % 60
        if (hours > 0)
            return hours + " h " + minutes + " min"
        return minutes + " min"
    }

    function popupOpened() {
        BatteryService.applyError = ""
        BatteryService.refresh()
    }

    component InfoRow: Item {
        property string label: ""
        property string value: ""
        width: popup.contentWidth
        height: 20

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label
            color: Theme.fgColor
            opacity: 0.6
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }

        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: parent.value
            color: Theme.fgColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
            font.features: { "tnum": 1 }
        }
    }

    // Header: title + refresh + close
    Item {
        width: parent.width
        height: 26

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Battery"
            color: Theme.fgColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            Icon {
                glyph: "\ue01a" // arrow-clockwise (refresh)
                style: popup.iconStyle
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: BatteryService.refresh()
                }
            }

            Icon {
                glyph: "\ue02f" // dismiss
                style: popup.iconStyle
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: popup.visible = false
                }
            }
        }
    }

    Text {
        visible: !BatteryService.present
        width: parent.width
        text: "No battery"
        color: Theme.fgColor
        opacity: 0.6
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    // Current charge summary: icon + % on the left, power-profile button
    // at the right edge of the percentage line (an Item wrapper so the
    // summary can be laid out with anchors).
    Item {
        visible: BatteryService.present
        width: parent.width
        implicitHeight: summaryRow.implicitHeight

        Row {
            id: summaryRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14

            Icon {
                id: summaryIcon
                anchors.verticalCenter: parent.verticalCenter
                glyph: BatteryService.batteryGlyph(BatteryService.percentage, BatteryService.pluggedIn)
                style: popup.iconStyle
                color: BatteryService.charging ? Theme.accentColor : Theme.fgColor
                font.pixelSize: Math.round(34 * 1.5)
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                // Percentage line: value at the left, power-profile button
                // at the right, both anchored to THIS line so the button is
                // centered exactly with the value.
                Item {
                    id: percentLine
                    width: popup.contentWidth - summaryIcon.width - summaryRow.spacing
                    implicitHeight: Math.max(percentText.implicitHeight, powerProfileButton.height)

                    Text {
                        id: percentText
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: Math.round(BatteryService.percentage) + "%"
                        color: Theme.fgColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 11
                        font.bold: true
                        font.features: { "tnum": 1 }
                    }

                    // Power-profiles-daemon button: current profile name,
                    // colored by profile (red/blue/green); click cycles.
                    Rectangle {
                        id: powerProfileButton
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: powerProfileText.implicitWidth + 14
                        height: 20
                        radius: 5
                        color: Qt.rgba(BatteryService.powerProfileColor.r, BatteryService.powerProfileColor.g, BatteryService.powerProfileColor.b, 0.5)
                        border.width: 1
                        border.color: Theme.buttonBorder

                        Text {
                            id: powerProfileText
                            anchors.centerIn: parent
                            text: BatteryService.powerProfileLabel
                            color: Theme.fgColor
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 4
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: BatteryService.cyclePowerProfile()
                        }
                    }
                }

                Text {
                    text: BatteryService.stateText
                        + (BatteryService.limitActive ? "   ·   Limit " + BatteryService.endThreshold + "%" : "")
                    color: BatteryService.charging ? Theme.accentColor : Theme.fgColor
                    opacity: 0.8
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
            }
        }
    }

    InfoRow {
        label: "State"
        value: BatteryService.stateText
    }

    InfoRow {
        label: popup.timeLabel
        value: popup.timeText
    }

    InfoRow {
        label: popup.powerLabel
        value: popup.powerText
        visible: popup.showPower
    }

    InfoRow {
        label: "Energy"
        value: popup.energyText
    }

    InfoRow {
        label: "Health"
        value: popup.healthText
        visible: popup.showHealth
    }

    // Charge limits / profiles
    Rectangle {
        width: parent.width
        height: 1
        color: Theme.popupBorderColor
        visible: BatteryService.thresholdSupported
    }

    Text {
        visible: BatteryService.thresholdSupported
        width: parent.width
        text: "Charge limit"
        color: Theme.fgColor
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
        font.bold: true
    }

    Text {
        visible: BatteryService.thresholdSupported
        width: parent.width
        text: "Start " + BatteryService.startThreshold + "%   ·   End " + BatteryService.endThreshold + "%"
        color: Theme.fgColor
        opacity: 0.6
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 2
    }

    Row {
        visible: BatteryService.thresholdSupported
        width: parent.width
        spacing: 8

        Repeater {
            model: popup.profiles

            delegate: Rectangle {
                id: profileButton
                required property int modelData

                readonly property bool active: BatteryService.endThreshold === modelData
                width: (popup.contentWidth - 2 * parent.spacing) / 3
                height: 30
                radius: 6
                color: active
                    ? Theme.accentColor
                    : Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.08)
                border.width: 1
                border.color: active
                    ? Theme.accentColor
                    : Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.25)
                opacity: BatteryService.applying ? 0.5 : 1

                Text {
                    anchors.centerIn: parent
                    text: profileButton.modelData + "%"
                    color: profileButton.active ? Theme.bgColor : Theme.fgColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    font.features: { "tnum": 1 }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !BatteryService.applying
                    cursorShape: Qt.PointingHandCursor
                    onClicked: BatteryService.applyProfile(profileButton.modelData)
                }
            }
        }
    }

    Text {
        visible: BatteryService.applying
        width: parent.width
        text: "Applying\u2026"
        color: Theme.fgColor
        opacity: 0.6
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 2
    }

    Text {
        visible: BatteryService.applyError !== ""
        width: parent.width
        text: BatteryService.applyError
        color: Theme.urgentColor
        wrapMode: Text.WordWrap
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 2
    }

    Text {
        visible: !BatteryService.thresholdSupported
        width: parent.width
        text: "This device does not support charge limits."
        color: Theme.fgColor
        opacity: 0.6
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 2
    }
}
