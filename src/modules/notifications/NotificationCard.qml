import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "../theme"
import "../icon"
import "../widgets"

// One toast card inside the notification stack. The border color encodes the
// notification urgency; clicking dismisses, hovering pauses the auto-timeout.
Item {
    id: card

    // The NotificationService entry rendered by this card.
    required property var modelData
    readonly property var entry: modelData

    // Corner radius of the urgency border (the toast block passes a radius
    // concentric with its own).
    property int radius: Theme.popupRadius

    width: parent ? parent.width : 0
    implicitHeight: body.implicitHeight + 20

    readonly property color borderColor: Theme.urgencyColor(card.entry.urgency)

    // Resolve the app icon: a themed icon name -> a path; anything else (an
    // absolute path or a URL the client sent) is used as-is.
    readonly property string iconSource: {
        const e = card.entry
        if (!e || e.appIcon === "")
            return ""
        const p = Quickshell.iconPath(e.appIcon, true)
        return p !== "" ? p : e.appIcon
    }

    // App-supplied actions (identifier/text snapshots).
    component ActionButton: Chip {
        required property var modelData
        text: modelData.text
        onClicked: NotificationService.invokeAction(card.entry.entryId, modelData.identifier)
    }

    // Urgency border only: the solid background is provided once by the toast
    // block, so cards stay transparent to avoid an extra translucent layer.
    Rectangle {
        anchors.fill: parent
        radius: card.radius
        color: "transparent"
        border.width: Theme.popupBorderWidth
        border.color: card.borderColor
    }

    // Background click dismisses; declared first so the action buttons (below)
    // sit on top and receive their own clicks.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: NotificationService.pauseEntry(card.entry.entryId)
        onExited: NotificationService.resumeEntry(card.entry.entryId)
        onClicked: NotificationService.dismissEntry(card.entry.entryId)
    }

    Column {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 10
        spacing: 4

        // Header: app icon + name + relative time + close.
        Item {
            width: parent.width
            height: Math.max(18, headerText.implicitHeight)

            Item {
                id: appIconBox
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                height: 18

                Image {
                    id: appIconImage
                    anchors.fill: parent
                    source: card.iconSource
                    sourceSize.width: 18
                    sourceSize.height: 18
                    fillMode: Image.PreserveAspectFit
                    visible: status === Image.Ready
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 4
                    color: Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.12)
                    visible: appIconImage.status !== Image.Ready

                    Text {
                        anchors.centerIn: parent
                        text: card.entry.appName ? card.entry.appName.charAt(0).toUpperCase() : "?"
                        color: Theme.fgColorMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 6
                        font.bold: true
                    }
                }
            }

            Text {
                id: headerText
                anchors.left: appIconBox.right
                anchors.leftMargin: 8
                anchors.right: timeText.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: card.entry.appName
                color: Theme.fgColorMuted
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
            }

            Text {
                id: timeText
                anchors.right: urgentIcon.visible ? urgentIcon.left : closeButton.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: NotificationService.formatTime(card.entry.time)
                color: Theme.fgColorMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 4
            }

            Icon {
                id: urgentIcon
                anchors.right: closeButton.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                glyph: "\ue07b" // bell-urgent
                color: Theme.urgencyCriticalColor
                font.pixelSize: Theme.fontSize - 1
                visible: card.entry.urgency === NotificationUrgency.Critical
            }

            Icon {
                id: closeButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                glyph: "\ue02f" // dismiss
                color: Theme.fgColorMuted
                font.pixelSize: Theme.fontSize - 2

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NotificationService.dismissEntry(card.entry.entryId)
                }
            }
        }

        // Summary (bold) + body.
        Text {
            width: parent.width
            text: card.entry.summary
            color: Theme.fgColor
            visible: text !== ""
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
            font.bold: true
        }

        Text {
            width: parent.width
            text: card.entry.body
            color: Theme.fgColor
            opacity: 0.75
            visible: text !== ""
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
        }

        // Action buttons, if the client sent any.
        Row {
            width: parent.width
            spacing: 6
            visible: card.entry.actions.length > 0

            Repeater {
                model: card.entry.actions
                delegate: ActionButton {}
            }
        }
    }
}
