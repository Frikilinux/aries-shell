pragma ComponentBehavior: Bound

import QtQuick
import "../theme"
import "../icon"
import "../popup"
import "../widgets"

// Devices paired with the `aries-connect` daemon. Only paired devices are
// listed; a pending pairing request gets its own Accept / Reject block (the
// backend cancels it after 30 s and reports the reason). Phone notifications
// mirrored by the daemon follow, newest first, each dismissable.
BarPopup {
    id: popup

    popupWidth: 320

    readonly property var request: AriesConnectService.request

    // Paired only. `connected` alone is not enough: the backend keeps the
    // device's link flag after a phone-side unpair (the row stays
    // `paired: false, connected: true` until the socket closes), and an
    // unpaired device is not actionable from the popup.
    readonly property var deviceList: {
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
        visible: AriesConnectService.available && popup.deviceList.length === 0 && popup.request === null
        width: parent.width
        text: "No paired devices"
        color: Theme.fgColor
        opacity: 0.6
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    // One paired / connected device: name + status flags.
    component DeviceRow: Rectangle {
        id: deviceRow
        required property var modelData
        readonly property bool connected: modelData.connected
        // Switch is only usable while connected; `disconnecting` covers the
        // round trip until `Disconnected` arrives.
        readonly property bool disconnecting: modelData.disconnecting === true
        readonly property bool canDisconnect: deviceRow.connected && !deviceRow.disconnecting
        width: popup.contentWidth
        height: 44
        radius: 6
        color: deviceRow.connected ? Qt.rgba(Theme.accentColor.r, Theme.accentColor.g, Theme.accentColor.b, 0.12) : "transparent"

        Row {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 8

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                horizontalAlignment: Text.AlignHCenter
                glyph: "\ue033" // phone
                color: deviceRow.connected ? Theme.accentColor : Theme.fgColor
                opacity: deviceRow.connected ? 1 : 0.6
                font.pixelSize: 20
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 18 - 34 - 2 * parent.spacing
                spacing: 3

                Text {
                    width: parent.width
                    text: AriesConnectService.deviceLabel(deviceRow.modelData)
                    color: Theme.fgColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    elide: Text.ElideRight
                }

                Row {
                    spacing: 4

                    Chip {
                        text: "Paired"
                        active: deviceRow.modelData.paired === true
                        interactive: false
                    }

                    Chip {
                        text: "Connected"
                        active: deviceRow.connected
                        interactive: false
                    }
                }
            }

            Switch {
                anchors.verticalCenter: parent.verticalCenter
                checked: deviceRow.connected
                enabled: deviceRow.canDisconnect
                onToggled: AriesConnectService.disconnect(deviceRow.modelData.deviceId)
            }
        }
    }

    Repeater {
        model: popup.deviceList
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
