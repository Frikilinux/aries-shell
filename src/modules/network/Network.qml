import QtQuick
import Quickshell
import Quickshell.Networking
import "../theme"
import "../icon"

Item {
    id: network

    // Show this module only on specific outputs.
    // Set to a string ("HDMI-A-1") or array (["eDP-1"]). If undefined/null, shows on all.
    property var outputs
    // The output being rendered.
    property string output: ""

    // The popup window, exposed so shell.qml can configure it (e.g. popup.iconStyle)
    property alias popup: popupWindow
    // Icon style used by this module's bar icons. Defaults to Theme.iconStyle.
    property string iconStyle: Theme.iconStyle

    // Ordered internal-first: eth internal, eth external, wifi internal, wifi external
    readonly property var wifiDevices: NetworkDevices.wifiDevices
    readonly property var wiredDevices: NetworkDevices.wiredDevices

    readonly property bool hasWifi: wifiDevices.length > 0
    readonly property bool hasWired: wiredDevices.length > 0

    function isUp(dev) {
        if (dev.connected)
            return true
        return dev.networks.values.some(n => n.connected)
    }

    // First connected device (internal preferred). If none is connected, fall
    // back to the first device so its off/disabled state is still represented.
    function activeDevice(list) {
        if (list.length === 0)
            return null
        const up = list.find(d => network.isUp(d))
        return up === undefined ? list[0] : up
    }

    readonly property var activeWifi: activeDevice(wifiDevices)
    readonly property var activeWired: activeDevice(wiredDevices)
    readonly property bool wifiConnected: activeWifi !== null && isUp(activeWifi)
    readonly property bool wiredConnected: activeWired !== null && isUp(activeWired)

    readonly property string wifiGlyph: {
        if (activeWifi !== null && network.wifiConnected) {
            const n = activeWifi.networks.values.find(x => x.connected)
            if (n !== undefined) {
                const s = n.signalStrength
                if (s >= 0.75)
                    return "\ue065" // wifi4
                if (s >= 0.50)
                    return "\ue064" // wifi3
                if (s >= 0.25)
                    return "\ue063" // wifi2
                return "\ue062"     // wifi1
            }
        }
        if (!Networking.wifiEnabled)
            return "\ue067" // wifi-off
        return "\ue069"     // wifi-warning (enabled, not connected)
    }

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    // Module is visible only if outputs property is unset, matches this output, or contains it
    visible: !outputs || (Array.isArray(outputs) ? outputs.includes(output) : outputs === output)

    Row {
        id: row
        spacing: Theme.spacing

        Icon {
            visible: network.hasWired
            glyph: "\ue075" // ethernet
            style: network.iconStyle
            color: Theme.fgBarColor
            opacity: network.wiredConnected ? 1 : 0.45
        }

        Icon {
            visible: network.hasWifi
            glyph: network.wifiGlyph
            style: network.iconStyle
            color: Theme.fgBarColor
            opacity: network.wifiConnected ? 1 : 0.45
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: popup.visible = !popup.visible
    }

    NetworkPopup {
        id: popupWindow
        anchorItem: network
    }
}
