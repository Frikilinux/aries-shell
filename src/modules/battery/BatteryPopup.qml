pragma ComponentBehavior: Bound

import QtQuick
import "../theme"
import "../icon"
import "../popup"
import "../widgets"

BarPopup {
    id: popup

    readonly property bool showPower: Math.abs(BatteryService.changeRate) >= 0.05
    readonly property string powerLabel: BatteryService.discharging ? "Consumption" : "Charge"
    readonly property string powerText: Math.abs(BatteryService.changeRate).toFixed(1) + " W"

    readonly property string timeLabel: BatteryService.discharging ? "Time remaining" : "Time to full"
    readonly property string timeText: popup.formatDuration(BatteryService.discharging ? BatteryService.timeToEmpty : BatteryService.timeToFull)

    readonly property bool showHealth: BatteryService.healthPercentage >= 0
    readonly property string energyText: BatteryService.energy.toFixed(1) + " / " + BatteryService.energyCapacity.toFixed(1) + " Wh"
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
        BatteryService.refreshScheduler()
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
            font.features: {
                "tnum": 1
            }
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
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        BatteryService.refresh()
                        BatteryService.refreshScheduler()
                    }
                }
            }

            Icon {
                glyph: "\ue02f" // dismiss
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

    // Current charge summary: battery icon + percentage + state line.
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
                anchors.verticalCenter: parent.verticalCenter
                glyph: BatteryService.batteryGlyph(BatteryService.percentage, BatteryService.pluggedIn)
                color: BatteryService.charging ? Theme.accentColor : Theme.fgColor
                font.pixelSize: Math.round(34 * 1.5)
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                    text: Math.round(BatteryService.percentage) + "%"
                    color: Theme.fgColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 11
                    font.bold: true
                    font.features: {
                        "tnum": 1
                    }
                }

                Text {
                    text: BatteryService.stateText + (BatteryService.limitActive ? "   ·   Limit " + BatteryService.endThreshold + "%" : "")
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

    // sched_ext scheduler attached by scx_loader (CachyOS).
    InfoRow {
        label: "Scheduler"
        value: BatteryService.schedulerLabel
        visible: BatteryService.schedulerActive
    }

    // Charge limits: libadwaita radio list -- one boxed group, one row per
    // preset (radio + title + window), the whole row selects. Thin divider
    // above separates the read-only info from the controls.
    Rectangle {
        width: parent.width
        height: 1
        color: Theme.borderColorRest
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

    Rectangle {
        id: profileGroup
        visible: BatteryService.thresholdSupported
        width: parent.width
        implicitHeight: profileColumn.implicitHeight
        // libadwaita boxed list: one lighter surface, no border, no gaps; the
        // rows only draw hairline separators between themselves.
        radius: 6
        color: Qt.alpha(Theme.fgColor, 0.05)
        opacity: BatteryService.applying ? 0.5 : 1

        Column {
            id: profileColumn
            width: parent.width
            spacing: 0

            Repeater {
                model: BatteryService.profiles

                delegate: Item {
                    id: profileRow
                    required property var modelData
                    required property int index
                    // Selected from the live thresholds, never from local state:
                    // a window changed outside the shell deselects every row.
                    readonly property bool active: BatteryService.startThreshold === modelData.start && BatteryService.endThreshold === modelData.end
                    readonly property bool first: index === 0
                    readonly property bool last: index === BatteryService.profiles.length - 1
                    width: parent.width
                    height: 54

                    // Hover fill, clipped by hand: the first/last rows follow the
                    // group's rounded corners instead of a hard rectangle.
                    Rectangle {
                        anchors.fill: parent
                        topLeftRadius: profileRow.first ? profileGroup.radius : 0
                        topRightRadius: profileRow.first ? profileGroup.radius : 0
                        bottomLeftRadius: profileRow.last ? profileGroup.radius : 0
                        bottomRightRadius: profileRow.last ? profileGroup.radius : 0
                        color: rowHover.hovered && !BatteryService.applying ? Qt.alpha(Theme.fgColor, 0.10) : "transparent"

                        Behavior on color {
                            ColorAnimation {
                                duration: 120
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    HoverHandler {
                        id: rowHover
                    }

                    // Whole row is the hit target (libadwaita activatable row).
                    MouseArea {
                        anchors.fill: parent
                        enabled: !BatteryService.applying
                        cursorShape: Qt.PointingHandCursor
                        onClicked: BatteryService.applyProfile(profileRow.modelData)
                    }

                    // libadwaita radio (shared control, see widgets/Radio.qml):
                    // muted ring when off, accent disc + light dot when on.
                    Radio {
                        id: radio
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        checked: profileRow.active
                    }

                    Column {
                        anchors.left: radio.right
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        Text {
                            width: parent.width
                            text: profileRow.modelData.title
                            color: Theme.fgColor
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: profileRow.modelData.range
                            color: Theme.fgColor
                            opacity: 0.6
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 5
                            elide: Text.ElideRight
                        }
                    }

                    // Hairline between rows, inset to the text column
                    // (12 pad + 18 radio + 12 gap) so it starts at the title.
                    Rectangle {
                        visible: !profileRow.last
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 42
                        height: 1
                        color: Qt.alpha(Theme.bgBarColor, 0.85)
                    }
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
