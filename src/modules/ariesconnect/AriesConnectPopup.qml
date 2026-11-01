pragma ComponentBehavior: Bound

import QtQuick
import "../theme"
import "../icon"
import "../popup"
import "../widgets"

// Paired devices known to the `aries-connect` daemon, each with an `Unpair`
// action. A pending pairing request gets its own Accept / Reject block (the
// backend cancels it after 30 s and reports the reason). Phone notifications
// mirrored by the daemon follow, newest first, each dismissable.
BarPopup {
    id: popup

    popupWidth: 320

    readonly property var request: AriesConnectService.request

    // Paired devices only: connected first, then name. `connected` alone is not
    // a criterion (an unpaired device can keep a link after a phone-side unpair).
    readonly property var pairedList: {
        const list = AriesConnectService.devices.filter(d => d.paired === true && !d.request)
        list.sort((a, b) => {
            const ca = a.connected ? 0 : 1
            const cb = b.connected ? 0 : 1
            if (ca !== cb)
                return ca - cb
            return AriesConnectService.deviceLabel(a).localeCompare(AriesConnectService.deviceLabel(b))
        })
        return list
    }

    // Backend order is oldest first; the popup shows the newest on top.
    readonly property var notificationList: AriesConnectService.notifications.slice().reverse()

    // The daemon may have (re)started while the popup was closed.
    function popupOpened() {
        AriesConnectService.refresh()
    }

    // Header: title + close
    Item {
        width: parent.width
        height: 26

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Aries Connect"
            color: Theme.fgColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
        }

        Icon {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            glyph: "\ue02f" // dismiss

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: popup.visible = false
            }
        }
    }

    // Pending pairing request: the phone shows a prompt, the backend waits
    // 30 s for a decision.
    Rectangle {
        visible: popup.request !== null
        width: popup.contentWidth
        implicitHeight: requestColumn.implicitHeight + 16
        radius: 6
        color: Qt.rgba(Theme.urgentColor.r, Theme.urgentColor.g, Theme.urgentColor.b, 0.12)
        border.width: 1
        border.color: Theme.urgentColor

        Column {
            id: requestColumn
            anchors.fill: parent
            anchors.margins: 8
            spacing: 4

            Text {
                width: parent.width
                text: "Pairing request"
                color: Theme.urgentColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }

            Text {
                width: parent.width
                text: popup.request !== null ? AriesConnectService.deviceLabel(popup.request) : ""
                color: Theme.fgColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                elide: Text.ElideRight
            }

            Row {
                spacing: 6

                Chip {
                    text: "Reject"
                    onClicked: {
                        if (popup.request !== null)
                            AriesConnectService.rejectPairing(popup.request.deviceId)
                    }
                }

                Chip {
                    text: "Accept"
                    active: true
                    onClicked: {
                        if (popup.request !== null)
                            AriesConnectService.acceptPairing(popup.request.deviceId)
                    }
                }
            }
        }
    }

    Text {
        visible: !AriesConnectService.available
        width: parent.width
        text: "Aries Connect is not running"
        color: Theme.fgColor
        opacity: 0.6
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    Text {
        visible: AriesConnectService.available && popup.pairedList.length === 0 && popup.request === null
        width: parent.width
        text: "No paired devices"
        color: Theme.fgColor
        opacity: 0.6
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    // Square icon button used for the row's quick actions. `background` is the
    // resting fill (hover lightens it); disabled uses 40% opacity. Compact on
    // purpose (the icon nearly fills the button) so new actions match.
    component QuickAction: Rectangle {
        id: actionButton
        property string glyph: ""
        property color background: Theme.buttonBgColor
        property color foreground: Theme.fgColor
        signal clicked

        implicitWidth: 22
        implicitHeight: 22
        radius: 5
        color: !actionButton.enabled ? actionButton.background : actionMouse.containsMouse ? Qt.lighter(actionButton.background, 1.25) : actionButton.background
        opacity: actionButton.enabled ? 1 : 0.4

        Icon {
            anchors.fill: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            glyph: actionButton.glyph
            color: actionButton.foreground
            font.pixelSize: 16
        }

        MouseArea {
            id: actionMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: actionButton.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: actionButton.clicked()
        }
    }

    // One paired device: big phone glyph, name, and the quick actions on the
    // line under it (right aligned). Unpair is destructive: critical fill.
    component DeviceRow: Rectangle {
        id: deviceRow
        required property var modelData
        readonly property bool connected: modelData.connected === true
        // An `Unpair` call is in flight until `PairingRemoved` answers.
        readonly property bool unpairing: modelData.unpairing === true
        width: popup.contentWidth
        // Content + 6 px padding top/bottom: the quick-action button must not
        // sit against the row's tinted edge (the name/action stack is taller
        // than the glyph).
        height: Math.max(48, deviceColumn.implicitHeight + 12)
        radius: 6
        color: deviceRow.connected ? Qt.rgba(Theme.accentColor.r, Theme.accentColor.g, Theme.accentColor.b, 0.12) : "transparent"

        Row {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 12

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                width: 27
                horizontalAlignment: Text.AlignHCenter
                glyph: "\ue033" // phone
                color: deviceRow.connected ? Theme.accentColor : Theme.fgColor
                opacity: deviceRow.connected ? 1 : 0.6
                font.pixelSize: 30
            }

            Column {
                id: deviceColumn
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 27 - parent.spacing
                spacing: 3

                Text {
                    width: parent.width
                    text: AriesConnectService.deviceLabel(deviceRow.modelData)
                    color: Theme.fgColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    elide: Text.ElideRight
                }

                // Quick actions (right aligned, same line the status chips used
                // to occupy).
                Item {
                    width: parent.width
                    height: 22

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        QuickAction {
                            glyph: "\ue08e" // phone-subtract
                            background: Theme.urgencyCriticalColor
                            enabled: !deviceRow.unpairing
                            onClicked: AriesConnectService.unpair(deviceRow.modelData.deviceId)
                        }
                    }
                }
            }
        }
    }

    Repeater {
        model: popup.pairedList
        delegate: DeviceRow {}
    }

    // Phone notifications mirrored by the daemon, newest first.
    Text {
        visible: AriesConnectService.notificationCount > 0
        width: parent.width
        topPadding: 4
        text: "Notifications"
        color: Theme.fgColorMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 4
        font.bold: true
    }

    component NotificationRow: Rectangle {
        id: notificationRow
        required property var modelData
        width: popup.contentWidth
        implicitHeight: notificationColumn.implicitHeight + 16
        radius: 6
        color: notificationMouse.containsMouse ? Theme.bgColorHover : "transparent"

        // Hover highlight only; the row itself is not clickable (dismissing
        // from an accidental click would be destructive).
        MouseArea {
            id: notificationMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }

        Column {
            id: notificationColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Row {
                width: parent.width
                spacing: 6

                Text {
                    width: parent.width - dismissIcon.width - parent.spacing
                    text: notificationRow.modelData.appName
                    color: Theme.fgColorMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 4
                    elide: Text.ElideRight
                }

                Icon {
                    id: dismissIcon
                    glyph: "\ue02f" // dismiss
                    color: Theme.fgColorMuted
                    font.pixelSize: Theme.fontSize - 2

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: AriesConnectService.dismissNotification(notificationRow.modelData.deviceId, notificationRow.modelData.notificationId)
                    }
                }
            }

            Text {
                width: parent.width
                text: notificationRow.modelData.title
                color: Theme.fgColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
                font.bold: true
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }

            Text {
                // Android text may embed line breaks; keep one visual line.
                width: parent.width
                visible: text !== ""
                text: notificationRow.modelData.text.replace(/\s*\n\s*/g, " ")
                color: Theme.fgColorMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
        }
    }

    Repeater {
        model: popup.notificationList
        delegate: NotificationRow {}
    }
}
