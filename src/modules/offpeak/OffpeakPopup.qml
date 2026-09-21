import QtQuick
import "../theme"
import "../popup"

// Detailed off-peak/peak panel for the DeepSeek API module.
BarPopup {
    id: popup

    popupWidth: 350

    readonly property color statusColor: OffpeakService.peak ? Theme.peakColor : Theme.offPeakColor

    // Hour tick under the timeline (00, 06, 12, 18, 24)
    component HourLabel: Text {
        required property string label
        required property real fraction

        text: label
        x: Math.min(parent.width * fraction, parent.width - implicitWidth)
        color: Theme.fgColorMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 4
        font.features: ({ "tnum": 1 })
    }

    // Header: status, big countdown and what comes next
    Rectangle {
        width: parent.width
        radius: 6
        color: Qt.rgba(popup.statusColor.r, popup.statusColor.g, popup.statusColor.b, 0.16)
        implicitHeight: header.implicitHeight + 24

        Column {
            id: header
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Row {
                spacing: 6

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8
                    height: 8
                    radius: 4
                    color: popup.statusColor
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: OffpeakService.statusLabel
                    color: popup.statusColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 3
                    font.bold: true
                    font.letterSpacing: 1
                }
            }

            Row {
                spacing: 8

                Text {
                    id: clockText
                    text: OffpeakService.formatClock(OffpeakService.remainingMs)
                    color: popup.statusColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.round(Theme.fontSize * 2.4)
                    font.bold: true
                    font.features: ({ "tnum": 1 })
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "left"
                    color: Theme.fgColorMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
            }

            Text {
                text: "\u2192 " + OffpeakService.nextLabel
                color: Theme.fgColorMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.12)
    }

    Text {
        text: "DEEPSEEK PRICE WINDOWS \u00b7 LOCAL"
        color: Theme.fgColorMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 3
        font.letterSpacing: 1
    }

    // Current window first, then the following ones (merged off-peak/peak blocks)
    Repeater {
        model: OffpeakService.windows(4)

        delegate: Item {
            id: windowRow
            required property var modelData
            required property int index

            readonly property color rowColor: windowRow.modelData.peak ? Theme.peakColor : Theme.offPeakColor

            width: popup.contentWidth
            height: 26

            Text {
                id: windowName
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: windowRow.modelData.peak ? "Peak" : "Off-peak"
                color: windowRow.rowColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
                font.bold: true
            }

            Text {
                anchors.left: windowName.right
                anchors.leftMargin: 10
                anchors.right: windowValue.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: OffpeakService.formatRange(windowRow.modelData.start, windowRow.modelData.end)
                color: Theme.fgColor
                opacity: 0.55
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
            }

            Text {
                id: windowValue
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: windowRow.index === 0
                    ? "now \u00b7 " + OffpeakService.formatDuration(OffpeakService.remainingMs) + " left"
                    : OffpeakService.formatDuration(windowRow.modelData.end - windowRow.modelData.start)
                color: windowRow.index === 0 ? windowRow.rowColor : Theme.fgColorMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
                font.features: ({ "tnum": 1 })
            }
        }
    }

    // 24h timeline for the current UTC day
    Item {
        width: parent.width
        height: 12

        Rectangle {
            id: track
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 6
            radius: 3
            color: Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.10)

            Row {
                anchors.fill: parent

                Repeater {
                    model: 24

                    delegate: Rectangle {
                        required property int index

                        width: track.width / 24
                        height: track.height
                        color: OffpeakService.hourPeak(index)
                            ? Qt.rgba(Theme.peakColor.r, Theme.peakColor.g, Theme.peakColor.b, 0.55)
                            : Qt.rgba(Theme.offPeakColor.r, Theme.offPeakColor.g, Theme.offPeakColor.b, 0.55)
                    }
                }
            }
        }

        // "now" marker
        Rectangle {
            width: 2
            height: track.height + 6
            x: track.width * OffpeakService.nowFraction - width / 2
            y: track.y - 3
            color: Theme.fgColor
        }
    }

    // Hour labels under the timeline
    Item {
        width: parent.width
        height: 12

        HourLabel { label: "00"; fraction: 0 }
        HourLabel { label: "06"; fraction: 0.25 }
        HourLabel { label: "12"; fraction: 0.5 }
        HourLabel { label: "18"; fraction: 0.75 }
        HourLabel { label: "24"; fraction: 1 }
    }
}
