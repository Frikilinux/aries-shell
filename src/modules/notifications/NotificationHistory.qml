import QtQuick
import "../theme"
import "../icon"
import "../popup"

// Notification history viewer: a bar popup listing every recorded notification
// (newest first), with per-row delete, a "clear all" action and a Do-Not-Disturb
// toggle. Opening it marks everything as read.
BarPopup {
    id: popup

    popupWidth: 400
    maxContentHeight: 460

    // Icon style used by this popup's icons. Defaults to Theme.iconStyle.
    property string iconStyle: Theme.iconStyle

    function popupOpened() {
        NotificationService.markRead()
    }

    // Small labelled icon button used in the header.
    component HeaderButton: Icon {
        id: button
        property color tint: Theme.fgColor

        color: tint
        font.pixelSize: Theme.fontSize + 1

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }

        signal clicked()
    }

    // One history row: urgency stripe, app + time, summary, body.
    component HistoryRow: Item {
        id: row
        required property var modelData
        readonly property var entry: modelData

        width: popup.contentWidth
        implicitHeight: rowBody.implicitHeight + 12

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 3
            radius: 1.5
            color: Theme.urgencyColor(row.entry.urgency)
        }

        Column {
            id: rowBody
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.right: removeButton.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Row {
                width: parent.width
                spacing: 8

                Text {
                    width: parent.width - rowTime.implicitWidth - parent.spacing
                    text: row.entry.appName !== "" ? row.entry.appName : "Notification"
                    color: Theme.fgColorMuted
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 3
                }

                Text {
                    id: rowTime
                    text: NotificationService.formatTime(row.entry.time)
                    color: Theme.fgColorMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 4
                }
            }

            Text {
                width: parent.width
                text: row.entry.summary
                color: Theme.fgColor
                visible: text !== ""
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
                font.bold: true
            }

            Text {
                width: parent.width
                text: row.entry.body
                color: Theme.fgColor
                opacity: 0.7
                visible: text !== ""
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }
        }

        Icon {
            id: removeButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            glyph: "\ue02f" // dismiss
            color: Theme.fgColorMuted
            font.pixelSize: Theme.fontSize - 2

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: NotificationService.removeEntry(row.entry.entryId)
            }
        }
    }

    // Header: title + DND toggle + clear all + close.
    Item {
        width: popup.contentWidth
        height: 26

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Notifications"
            color: Theme.fgColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            HeaderButton {
                glyph: "\ue07a"
                tint: NotificationService.dnd ? Theme.accentColor : Theme.fgColorMuted
                onClicked: NotificationService.toggleDnd()
            }

            HeaderButton {
                glyph: "\ue07d" // trash (clear all)
                tint: NotificationService.entries.length > 0 ? Theme.fgColor : Theme.fgColorMuted
                onClicked: NotificationService.clearHistory()
            }

            HeaderButton {
                glyph: "\ue02f" // dismiss
                tint: Theme.fgColor
                onClicked: popup.visible = false
            }
        }
    }

    // Separator.
    Rectangle {
        width: popup.contentWidth
        height: 1
        color: Theme.popupBorderColor
    }

    // Empty state.
    Text {
        width: popup.contentWidth
        text: "No notifications"
        color: Theme.fgColorMuted
        horizontalAlignment: Text.AlignHCenter
        visible: NotificationService.entries.length === 0
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
        topPadding: 12
        bottomPadding: 12
    }

    Repeater {
        model: NotificationService.entries
        delegate: HistoryRow {}
    }
}
