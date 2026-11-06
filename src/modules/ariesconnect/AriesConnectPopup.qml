pragma ComponentBehavior: Bound

import QtQuick
import "../battery"
import "../theme"
import "../icon"
import "../popup"
import "../widgets"

// Paired devices known to the `aries-connect` daemon, each with an `Unpair`
// action. A pending pairing request gets its own Accept / Reject block (the
// backend cancels it after 30 s and reports the reason). Device notifications
// are mirrored by the daemon per phone: one card per device (network-popup
// style) and only the selected card expands its notifications under it, at
// most `maxNotifRows` before that list scrolls while the card stays put.
BarPopup {
    id: popup

    popupWidth: 380
    // Never taller than 75% of the screen height (same as the network popup).
    maxContentHeight: popup.screen ? Math.round(popup.screen.height * 0.75) : 540

    // The pending pairing request, or null when none (the popup also renders
    // the Accept/Reject block for it).
    readonly property var request: AriesConnectService.request

    // A click on the gear in the header asks the module to open the settings
    // window (the popup cannot own a separate toplevel itself).
    signal settingsRequested

    // Card background shared with the network popup (foreground tint).
    readonly property color devHeaderBgColor: Qt.rgba(Theme.fgBarColor.r, Theme.fgBarColor.g, Theme.fgBarColor.b, 0.07)

    // Accordion: `null` = no explicit choice yet (the first device with
    // notifications opens), `""` = every card folded, else the device id.
    property var expandedDevice: null

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

    // Expanded card. The explicit choice wins while it still exists; otherwise
    // the first device with notifications, else the first device.
    readonly property string expandedId: {
        if (popup.expandedDevice !== null) {
            const chosen = String(popup.expandedDevice)
            if (chosen === "")
                return ""
            if (popup.pairedList.some(d => d.deviceId === chosen))
                return chosen
        }
        const withNotes = popup.pairedList.find(d => AriesConnectService.notifications.some(n => n.deviceId === d.deviceId))
        if (withNotes !== undefined)
            return withNotes.deviceId
        return popup.pairedList.length > 0 ? popup.pairedList[0].deviceId : ""
    }

    // Notification list scrolling: at most `maxNotifRows` rows fit, beyond that
    // the device's list scrolls (the card header does not move).
    readonly property int maxNotifRows: 5
    readonly property int notifRowHeight: 60
    readonly property int notifRowSpacing: 2

    // Header click: open this device, or fold it when it is already open.
    function toggleDevice(deviceId) {
        popup.expandedDevice = popup.expandedId === deviceId ? "" : deviceId
    }

    // Newest first (the backend keeps them oldest first).
    function notificationsOf(deviceId) {
        const list = AriesConnectService.notifications.filter(n => n.deviceId === deviceId)
        list.reverse()
        return list
    }

    function notificationCountOf(deviceId) {
        return AriesConnectService.notifications.filter(n => n.deviceId === deviceId).length
    }

    function notificationLabel(count) {
        if (count === 0)
            return "No notifications"
        return count === 1 ? "1 notification" : count + " notifications"
    }

    // Cellular indicator from the connectivity report: bars and generation
    // label come from the service (shared with the settings window).

    // The daemon may have (re)started while the popup was closed.
    function popupOpened() {
        AriesConnectService.refresh()
    }

    // Action errors belong to one attempt: don't keep them across opens.
    function popupClosed() {
        AriesConnectService.actionError = null
    }

    // Header: title, close, and the gear that opens the settings window.
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
            id: closeIcon
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            glyph: "\ue02f" // dismiss

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: popup.visible = false
            }
        }

        // Opens the plugin settings window (the module closes this popup
        // first, since both are separate surfaces).
        Icon {
            anchors.right: closeIcon.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            glyph: "\ue071" // settings

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: popup.settingsRequested()
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

    // Square icon button used for the row's quick actions: neutral fill plus
    // the resting border color (hover lightens it); disabled uses 40% opacity.
    // `background`/`hoverBackground` let a single action stand out (unpair is
    // critical). Compact on purpose so the icon nearly fills the button.
    component QuickAction: Rectangle {
        id: actionButton
        property string glyph: ""
        property color background: Theme.bgColor
        property color hoverBackground: Qt.lighter(Theme.bgColorHover, 1.15)
        property color foreground: Theme.fgColor
        signal clicked

        implicitWidth: 28
        implicitHeight: 28
        radius: 5
        color: actionMouse.containsMouse ? actionButton.hoverBackground : actionButton.background
        border.width: 1
        border.color: Theme.borderColorRest
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

    // One paired device (network-popup card style): big phone glyph, name with
    // the last reported battery on the right, then the notification count on
    // the left and the quick actions on the right. Clicking the card (outside
    // the buttons) opens / folds this device's notifications. Ping and
    // clipboard need a live link and their plugin on (disabled otherwise, no
    // explanatory text).
    component DeviceCard: Rectangle {
        id: deviceCard
        required property var modelData
        readonly property bool connected: modelData.connected === true
        // An `Unpair` call is in flight until `Paired` flips to false.
        readonly property bool unpairing: modelData.unpairing === true
        // `null` = not queried yet; treat it as disabled (backend default for
        // unknown/unpaired devices).
        readonly property bool pingEnabled: modelData.pingEnabled === true
        readonly property bool pingReady: deviceCard.connected && deviceCard.pingEnabled
        readonly property bool clipboardEnabled: modelData.clipboardEnabled === true
        readonly property bool clipboardReady: deviceCard.connected && deviceCard.clipboardEnabled
        readonly property string actionErrorText: AriesConnectService.actionError !== null && AriesConnectService.actionError.deviceId === deviceCard.modelData.deviceId ? AriesConnectService.actionError.text : ""
        // Charge to show: the current report, or the last one seen while the
        // phone is offline (the daemon clears `BatteryLevel` when the control
        // channel closes, so the stale value is cached here).
        readonly property int batteryLevel: modelData.batteryLevel >= 0 ? modelData.batteryLevel : modelData.lastBatteryLevel
        readonly property bool batteryKnown: deviceCard.batteryLevel >= 0
        // Only a connected device with a live report gets the bright
        // indicator; a cached value is dimmed.
        readonly property bool batteryCurrent: deviceCard.connected && modelData.batteryLevel >= 0
        readonly property bool charging: modelData.charging === true
        // Cellular bars (coarse level) and generation label of the first
        // subscription ("" = nothing to show). The daemon clears the values on
        // disconnect and the phone only re-pushes on change, so the last
        // report is kept dimmed instead of vanishing (same as the battery).
        readonly property bool signalCurrent: modelData.signalType !== ""
        readonly property string signalType: deviceCard.signalCurrent ? modelData.signalType : (modelData.lastSignalType || "")
        readonly property int signalLevel: deviceCard.signalCurrent ? modelData.signalLevel : (typeof modelData.lastSignalLevel === "number" ? modelData.lastSignalLevel : -1)
        readonly property string signalGlyph: AriesConnectService.signalGlyph(deviceCard.signalLevel)
        readonly property string signalText: AriesConnectService.signalLabel(deviceCard.signalType)
        width: popup.contentWidth
        // Content + 6 px padding top/bottom: the quick-action button must not
        // sit against the card's edge (the name/action stack is taller than the
        // glyph).
        height: Math.max(48, cardColumn.implicitHeight + 12)
        radius: 6
        color: popup.devHeaderBgColor
        border.width: 1
        border.color: Theme.borderColorRest

        // Card click (accordion). Declared first so the quick actions above it
        // win their own clicks.
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: popup.toggleDevice(deviceCard.modelData.deviceId)
        }

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
                color: deviceCard.connected ? Theme.accentColor : Theme.fgColor
                opacity: deviceCard.connected ? 1 : 0.6
                font.pixelSize: 30
            }

            Column {
                id: cardColumn
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 27 - parent.spacing
                spacing: 3

                // Name line: name on the left, then the status group on the
                // right (the generation + bars, then the battery: percent and
                // glyph rightmost).
                Item {
                    width: parent.width
                    height: Math.max(nameText.implicitHeight, statusRow.height)

                    Text {
                        id: nameText
                        anchors.left: parent.left
                        anchors.right: statusRow.visible ? statusRow.left : parent.right
                        anchors.rightMargin: statusRow.visible ? 6 : 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: AriesConnectService.deviceLabel(deviceCard.modelData)
                        color: Theme.fgColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        elide: Text.ElideRight
                    }

                    Row {
                        id: statusRow
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: deviceCard.batteryKnown || deviceCard.signalGlyph !== "" || deviceCard.signalText !== ""
                        spacing: 8

                        // Cellular signal from the connectivity report: the
                        // generation as text (5G / 4G / 3G / 2G) then the bars
                        // for the coarse level. Only while the daemon reports
                        // it: plugin enabled, phone connected, one report.
                        Row {
                            height: batteryGroup.height
                            // spacing: 1
                            visible: deviceCard.signalGlyph !== "" || deviceCard.signalText !== ""
                            // Dimmed when it is the last known report, never
                            // live data (the phone has not re-pushed yet).
                            opacity: deviceCard.signalCurrent ? 1 : 0.5

                            Text {
                                visible: deviceCard.signalText !== ""
                                text: deviceCard.signalText
                                color: Theme.fgColorMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 3
                                // Same treatment as the battery text/icon: the
                                // line box is centered, never a forced height.
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Icon {
                                id: signalIcon
                                visible: deviceCard.signalGlyph !== ""
                                glyph: deviceCard.signalGlyph
                                color: Theme.fgColorMuted
                                anchors.verticalCenter: parent.verticalCenter
                                font.pixelSize: Theme.fontSize * 1.1
                            }
                        }

                        // Battery icon + percentage. Hidden when no level was
                        // ever reported. While the phone is offline (or the
                        // level is currently unknown) the last value is shown
                        // dimmed, never as if it were live.
                        Row {
                            id: batteryGroup
                            visible: deviceCard.batteryKnown
                            width: batteryIcon.implicitWidth + 6 + batteryText.implicitWidth
                            height: Math.max(batteryIcon.implicitHeight, batteryText.implicitHeight)
                            opacity: deviceCard.batteryCurrent ? 1 : 0.5
                            spacing: 6

                            Text {
                                id: batteryText
                                // anchors.right: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: Math.round(deviceCard.batteryLevel) + "%"
                                color: Theme.fgColorMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 3
                            }

                            Icon {
                                id: batteryIcon
                                // anchors.left: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                glyph: BatteryService.batteryLevelGlyph(deviceCard.batteryLevel, deviceCard.charging)
                                color: Theme.fgColorMuted
                                font.pixelSize: Theme.fontSize * 1.2
                            }
                        }
                    }
                }

                // Notification count (left) + quick actions (right).
                Item {
                    width: parent.width
                    height: actionsRow.implicitHeight

                    Text {
                        anchors.left: parent.left
                        anchors.right: actionsRow.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: popup.notificationLabel(popup.notificationCountOf(deviceCard.modelData.deviceId))
                        color: Theme.fgColorMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 4
                        elide: Text.ElideRight
                    }

                    Row {
                        id: actionsRow
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        QuickAction {
                            glyph: "\ue090" // clipboard
                            enabled: deviceCard.clipboardReady
                            onClicked: AriesConnectService.sendClipboard(deviceCard.modelData.deviceId)
                        }

                        QuickAction {
                            glyph: "\ue091" // megaphone-loud
                            enabled: deviceCard.pingReady
                            onClicked: AriesConnectService.ping(deviceCard.modelData.deviceId)
                        }

                        QuickAction {
                            glyph: "\ue08e" // phone-subtract
                            background: Theme.urgencyCriticalColor
                            hoverBackground: Qt.lighter(Theme.urgencyCriticalColor, 1.15)
                            enabled: !deviceCard.unpairing
                            onClicked: AriesConnectService.unpair(deviceCard.modelData.deviceId)
                        }
                    }
                }

                // Backend error for the last action (D-Bus message, verbatim).
                Text {
                    visible: deviceCard.actionErrorText !== ""
                    width: parent.width
                    text: deviceCard.actionErrorText
                    color: Theme.urgencyCriticalColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 3
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    // Phone notification mirrored by the daemon: app, title and text on one
    // line each (newlines flattened), dismiss icon on the app line. Hover
    // highlight only; the row itself is not clickable (dismissing from an
    // accidental click would be destructive).
    component NotificationRow: Rectangle {
        id: notificationRow
        required property var modelData
        width: popup.contentWidth
        height: popup.notifRowHeight
        radius: 6
        color: notificationMouse.containsMouse ? Theme.bgColorHover : "transparent"

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

    // One section per paired device: the card, then its notifications (newest
    // first) while it is the expanded one.
    Repeater {
        model: popup.pairedList

        delegate: Column {
            id: section
            required property var modelData
            readonly property bool open: popup.expandedId === section.modelData.deviceId
            readonly property var notes: popup.notificationsOf(section.modelData.deviceId)
            width: popup.contentWidth
            spacing: 4

            DeviceCard {
                modelData: section.modelData
            }

            Flickable {
                id: notesFlick
                visible: section.open && section.notes.length > 0
                width: parent.width
                height: Math.min(notesColumn.implicitHeight, popup.maxNotifRows * popup.notifRowHeight + popup.notifRowSpacing * (popup.maxNotifRows - 1))
                contentWidth: width
                contentHeight: notesColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: notesColumn
                    width: parent.width
                    spacing: popup.notifRowSpacing

                    Repeater {
                        model: section.notes

                        delegate: NotificationRow {}
                    }
                }
            }
        }
    }
}
