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
    // property string iconStyle: Theme.iconStyle

    // Ordered internal-first: eth internal, eth external, wifi internal, wifi external
    readonly property var wifiDevices: NetworkDevices.wifiDevices
    readonly property var wiredDevices: NetworkDevices.wiredDevices

    readonly property bool hasWifi: wifiDevices.length > 0
    readonly property bool hasWired: wiredDevices.length > 0

    readonly property var activeWifi: NetworkDevices.activeDevice(wifiDevices)
    readonly property var activeWired: NetworkDevices.activeDevice(wiredDevices)
    readonly property bool wifiConnected: NetworkDevices.isUp(activeWifi)
    readonly property bool wiredConnected: NetworkDevices.isUp(activeWired)
    // Carrier present even with no active connection (dimmer, not "off").
    readonly property bool wiredLinked: activeWired !== null && activeWired.hasLink
    // rfkill switch (sw) or the radio itself (hw) turned off.
    readonly property bool wifiOff: !Networking.wifiEnabled
        || !Networking.wifiHardwareEnabled

    readonly property string wifiGlyph: {
        if (wifiConnected) {
            const n = NetworkDevices.connectedNetwork(activeWifi)
            if (n !== null)
                return NetworkDevices.signalGlyph(n.signalStrength)
        }
        if (wifiOff)
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

        // Ethernet icon + VPN shield badge (only while the link is connected).
        Item {
            visible: network.hasWired
            implicitWidth: ethIcon.implicitWidth
            implicitHeight: ethIcon.implicitHeight

            Icon {
                id: ethIcon
                glyph: "\ue075" // ethernet
                // style: network.iconStyle
                color: Theme.fgBarColor
                opacity: network.wiredConnected ? 1 : (network.wiredLinked ? 0.7 : 0.45)
            }

            // Colored shield over the icon's bottom-right corner, on a bar-colored
            // disc so the icon underneath does not show through.
            Rectangle {
                visible: NetworkDevices.vpnActive && network.wiredConnected
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: -1
                anchors.bottomMargin: -3
                width: 13
                height: 13
                radius: height / 2
                color: Theme.bgBarColor

                Icon {
                    anchors.centerIn: parent
                    glyph: "\ue081" // shield
                    color: Theme.buttonPrimaryBgColor
                    font.pixelSize: 9
                }
            }
        }

        // Wifi icon + VPN shield badge (only while connected).
        Item {
            visible: network.hasWifi
            implicitWidth: wifiIcon.implicitWidth
            implicitHeight: wifiIcon.implicitHeight

            Icon {
                id: wifiIcon
                glyph: network.wifiGlyph
                // style: network.iconStyle
                color: Theme.fgBarColor
                opacity: network.wifiConnected ? 1 : 0.45
            }

            Rectangle {
                visible: NetworkDevices.vpnActive && network.wifiConnected
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: -1
                anchors.bottomMargin: -3
                width: 13
                height: 13
                radius: height / 2
                color: Theme.bgBarColor

                Icon {
                    anchors.centerIn: parent
                    glyph: "\ue081" // shield
                    color: Theme.urgentColor
                    font.pixelSize: 11
                }
            }
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
