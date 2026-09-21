import QtQuick
import Quickshell.Io
import Quickshell.Bluetooth
import "../theme"
import "../icon"
import "../popup"
import "../battery"
import "../widgets"

BarPopup {
    id: popup

    // Icon style used by this popup's icons. Defaults to Theme.iconStyle.
    property string iconStyle: Theme.iconStyle

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool adapterEnabled: adapter !== null && adapter.enabled
    readonly property bool discovering: adapter !== null && adapter.discovering
    // Bar/header state icon: disabled / searching / connected / generic
    readonly property string stateGlyph: !adapterEnabled ? "\ue026"
        : discovering ? "\ue027"
        : connectedCount > 0 ? "\ue025"
        : "\ue024"
    readonly property var devices: adapter !== null ? adapter.devices.values : []
    readonly property int connectedCount: devices.filter(d => d.connected).length
    readonly property var deviceList: {
        const list = devices.slice()
        list.sort((a, b) => {
            const ca = a.connected ? 0 : 1
            const cb = b.connected ? 0 : 1
            if (ca !== cb)
                return ca - cb
            const pa = (a.paired || a.bonded) ? 0 : 1
            const pb = (b.paired || b.bonded) ? 0 : 1
            if (pa !== pb)
                return pa - pb
            return popup.deviceLabel(a).localeCompare(popup.deviceLabel(b))
        })
        return list
    }

    // Connected devices are always expanded; disconnected ones are collapsed
    // until clicked.
    readonly property var connectedList: deviceList.filter(d => d.connected)
    readonly property var disconnectedList: deviceList.filter(d => !d.connected)
    // Disconnected devices visible before the section starts scrolling.
    readonly property int maxDisconnectedRows: 6
    // Height of a device row with its info hidden.
    readonly property int collapsedRowHeight: 40

    function deviceLabel(dev) {
        if (dev.name && dev.name !== "")
            return dev.name
        if (dev.deviceName && dev.deviceName !== "")
            return dev.deviceName
        return dev.address
    }

    function deviceGlyph(dev) {
        const i = dev.icon
        if (i === "audio-headset" || i === "audio-headphones")
            return "\ue030" // headphones
        if (i === "audio-card")
            return "\ue03e" // speaker-box
        if (i === "input-mouse")
            return "\ue06a" // mouse-simple
        if (i === "input-keyboard")
            return "\ue06d" // keyboard
        if (i === "input-gaming" || i === "input-joystick")
            return "\ue073" // xbox-controller
        if (i === "input-tablet")
            return "\ue072" // tablet
        if (i === "phone")
            return "\ue033" // phone
        if (i === "camera-video")
            return "\ue047" // video-bluetooth
        if (i === "camera-photo")
            return "\ue06b" // camera
        if (i === "printer")
            return "\ue06f" // print
        if (i === "computer")
            return "\ue06e" // laptop
        if (i === "multimedia-player")
            return "\ue06c" // headphones-sound-wave
        return "\ue024" // bluetooth
    }

    // Battery glyph for a device. BlueZ reports a 0..1 fraction.
    function deviceBatteryGlyph(dev) {
        return BatteryService.batteryGlyph(dev.battery * 100, false)
    }

    // Battery level as a percentage string (0..100)
    function deviceBatteryText(dev) {
        return Math.round(Math.max(0, Math.min(1, dev.battery)) * 100) + "%"
    }

    // Info rows for disconnected devices stay hidden until the row is clicked;
    // only one can be open at a time (clicking another closes the previous).
    // Connected devices always show their info.
    property string expandedAddress: ""

    function isExpanded(dev) {
        return popup.expandedAddress === dev.address
    }

    function toggleExpanded(dev) {
        popup.expandedAddress = popup.expandedAddress === dev.address ? "" : dev.address
    }

    function canToggle(dev) {
        if (!popup.adapterEnabled)
            return false
        return dev.state !== BluetoothDeviceState.Connecting
            && dev.state !== BluetoothDeviceState.Disconnecting
    }

    function toggleDevice(dev) {
        if (!popup.canToggle(dev))
            return
        if (dev.connected)
            dev.disconnect()
        else if (dev.paired || dev.bonded)
            dev.connect()
        else
            dev.pair()
    }

    Process {
        id: settingsApp
        command: ["overskride"]
    }

    // Header: title + settings + power toggle + close
    Item {
        width: parent.width
        height: 26

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Bluetooth"
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
                glyph: "\ue071" // settings
                style: popup.iconStyle
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: settingsApp.running = true
                }
            }

            Icon {
                glyph: popup.stateGlyph // bluetooth power
                style: popup.iconStyle
                color: popup.adapterEnabled ? Theme.accentColor : Theme.fgColor
                opacity: popup.adapter !== null ? (popup.adapterEnabled ? 1 : 0.45) : 0.3
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    enabled: popup.adapter !== null
                    onClicked: popup.adapter.enabled = !popup.adapter.enabled
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
        visible: popup.adapter === null
        width: parent.width
        text: "No Bluetooth adapter"
        color: Theme.fgColor
        opacity: 0.6
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    Text {
        visible: popup.adapter !== null && popup.deviceList.length === 0
        width: parent.width
        text: popup.adapterEnabled ? "No devices" : "Bluetooth is off"
        color: Theme.fgColor
        opacity: 0.6
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    // Single device row, shared by the connected and disconnected sections.
    // Connected rows always show their info; disconnected rows reveal it on
    // click (only one open at a time).
    component DeviceRow: Rectangle {
        id: deviceRow
        required property var modelData
        readonly property bool connected: modelData.connected
        readonly property bool hasBattery: modelData.batteryAvailable
        readonly property bool expanded: deviceRow.connected || popup.isExpanded(modelData)
        width: popup.contentWidth
        height: Math.max(popup.collapsedRowHeight, deviceInfo.implicitHeight + 10)
        radius: 6
        // Background only for connected devices
        color: deviceRow.connected ? Qt.rgba(Theme.accentColor.r, Theme.accentColor.g, Theme.accentColor.b, 0.12) : "transparent"

        // Clicking a disconnected row reveals/hides its info; clicking any
        // other device closes the open one. It never connects (connecting/
        // disconnecting stays on the Switch).
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (deviceRow.connected)
                    popup.expandedAddress = ""
                else
                    popup.toggleExpanded(deviceRow.modelData)
            }
        }

        Row {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 8

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                horizontalAlignment: Text.AlignHCenter
                glyph: popup.deviceGlyph(deviceRow.modelData)
                style: popup.iconStyle
                color: deviceRow.connected ? Theme.accentColor : Theme.fgColor
                opacity: deviceRow.connected ? 1 : 0.6
            }

            Column {
                id: deviceInfo
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 18 - 34 - 2 * parent.spacing
                spacing: 1

                Text {
                    width: parent.width
                    text: popup.deviceLabel(deviceRow.modelData)
                    color: Theme.fgColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    elide: Text.ElideRight
                }

                // Info row 1: battery level (icon + %) and MAC address.
                Row {
                    id: infoRow
                    visible: deviceRow.expanded
                    width: parent.width
                    height: Theme.fontSize
                    spacing: 10

                    readonly property real batteryWidth: deviceRow.hasBattery
                        ? batteryIcon.implicitWidth + batteryText.implicitWidth + 2 * infoRow.spacing
                        : 0

                    Icon {
                        id: batteryIcon
                        anchors.verticalCenter: parent.verticalCenter
                        visible: deviceRow.hasBattery
                        glyph: popup.deviceBatteryGlyph(deviceRow.modelData)
                        style: popup.iconStyle
                        color: deviceRow.connected ? Theme.accentColor : Theme.fgColorMuted
                        font.pixelSize: Theme.fontSize
                    }

                    Text {
                        id: batteryText
                        anchors.verticalCenter: parent.verticalCenter
                        visible: deviceRow.hasBattery
                        text: popup.deviceBatteryText(deviceRow.modelData)
                        color: Theme.fgColorMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, infoRow.width - infoRow.batteryWidth)
                        text: deviceRow.modelData.address
                        color: Theme.fgColorMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                        elide: Text.ElideRight
                    }
                }

                // Info row 2: paired / trusted / blocked flags.
                // trusted and blocked are writable; paired is read-only.
                Row {
                    visible: deviceRow.expanded
                    width: parent.width
                    height: 20
                    spacing: 4

                    Chip {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Paired"
                        active: deviceRow.modelData.paired || deviceRow.modelData.bonded
                        interactive: false
                    }

                    Chip {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Trusted"
                        active: deviceRow.modelData.trusted
                        onClicked: deviceRow.modelData.trusted = !deviceRow.modelData.trusted
                    }

                    Chip {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Blocked"
                        active: deviceRow.modelData.blocked
                        onClicked: deviceRow.modelData.blocked = !deviceRow.modelData.blocked
                    }
                }
            }

            Switch {
                anchors.verticalCenter: parent.verticalCenter
                checked: deviceRow.connected
                enabled: popup.canToggle(deviceRow.modelData)
                onToggled: popup.toggleDevice(deviceRow.modelData)
            }
        }
    }

    // Connected devices: their info is always visible.
    Repeater {
        model: popup.connectedList
        delegate: DeviceRow {}
    }

    // Disconnected devices: info hidden until clicked. Capped to
    // `maxDisconnectedRows` visible rows; the rest scrolls within this section.
    Flickable {
        id: disconnectedFlick
        visible: popup.disconnectedList.length > 0
        width: parent.width
        // Exactly `maxDisconnectedRows` collapsed rows (including the 6px gaps
        // the content column uses); taller content scrolls.
        height: Math.min(disconnectedColumn.implicitHeight,
            popup.maxDisconnectedRows * popup.collapsedRowHeight
                + 6 * (popup.maxDisconnectedRows - 1))
        contentWidth: width
        contentHeight: disconnectedColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: disconnectedColumn
            width: parent.width
            spacing: 6

            Repeater {
                model: popup.disconnectedList
                delegate: DeviceRow {}
            }
        }
    }
}
