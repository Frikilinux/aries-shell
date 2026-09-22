pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking

// Shared network-interface ordering used by the bar module and its popup:
//   0 ethernet internal  ·  1 ethernet external
//   2 wifi internal      ·  3 wifi external
// Groups are then sorted by name. External = attached over USB, detected from
// /sys/class/net/<iface>/device/subsystem.
//
// Also holds the helpers shared by the bar indicator and its popup so neither
// duplicates them (glyphs, security labels, band names).
Singleton {
    id: root

    readonly property var devices: Networking.devices.values

    // iface -> true when the interface hangs off USB
    property var externalMap: ({})

    function isExternal(dev) {
        return root.externalMap[dev.name] === true
    }

    function rank(dev) {
        const external = root.isExternal(dev) ? 1 : 0
        if (dev.type === DeviceType.Wired)
            return external
        return 2 + external
    }

    readonly property var ordered: {
        const list = root.devices.filter(
            x => x.type === DeviceType.Wifi || x.type === DeviceType.Wired)
        list.sort((a, b) => {
            const ra = root.rank(a)
            const rb = root.rank(b)
            if (ra !== rb)
                return ra - rb
            return String(a.name).localeCompare(String(b.name))
        })
        return list
    }

    readonly property var wifiDevices: ordered.filter(x => x.type === DeviceType.Wifi)
    readonly property var wiredDevices: ordered.filter(x => x.type === DeviceType.Wired)

    // ------------------------------------------------------------------
    // Shared helpers (bar + popup)
    // ------------------------------------------------------------------
    // `NetworkDevice.connected` is already bound to `state == Connected`.
    function isUp(dev) {
        return dev !== null && dev !== undefined && dev.connected
    }

    function connectedNetwork(dev) {
        if (dev === null || dev === undefined)
            return null
        const n = dev.networks.values.find(x => x.connected)
        return n === undefined ? null : n
    }

    // First connected device (internal preferred). If none is connected, fall
    // back to the first device so its off/disabled state is still represented.
    function activeDevice(list) {
        if (list.length === 0)
            return null
        const up = list.find(d => d.connected)
        return up === undefined ? list[0] : up
    }

    function isOpen(net) {
        return net.security === WifiSecurityType.Open
            || net.security === WifiSecurityType.Owe
            || net.security === WifiSecurityType.Unknown
    }

    // 0.0..1.0 -> wifi1..wifi4 glyph (shared by bar and popup rows).
    function signalGlyph(strength) {
        if (strength >= 0.75)
            return "\ue065" // wifi4
        if (strength >= 0.50)
            return "\ue064" // wifi3
        if (strength >= 0.25)
            return "\ue063" // wifi2
        return "\ue062"     // wifi1
    }

    function securityLabel(sec) {
        switch (sec) {
        case WifiSecurityType.Wpa3SuiteB192:
            return "WPA3 Suite-B"
        case WifiSecurityType.Sae:
            return "WPA3-SAE"
        case WifiSecurityType.Wpa2Eap:
            return "WPA2-Enterprise"
        case WifiSecurityType.Wpa2Psk:
            return "WPA2-PSK"
        case WifiSecurityType.WpaEap:
            return "WPA-Enterprise"
        case WifiSecurityType.WpaPsk:
            return "WPA-PSK"
        case WifiSecurityType.StaticWep:
            return "WEP"
        case WifiSecurityType.DynamicWep:
            return "WEP (dynamic)"
        case WifiSecurityType.Leap:
            return "LEAP"
        case WifiSecurityType.Owe:
            return "OWE"
        case WifiSecurityType.Open:
            return "Open"
        default:
            return "Unknown"
        }
    }

    // "5745" / "5745 MHz" -> "2.4 GHz" | "5 GHz" | "6 GHz"
    function freqBand(freq) {
        const f = parseFloat(freq)
        if (isNaN(f) || f <= 0)
            return ""
        if (f < 3000)
            return "2.4 GHz"
        if (f < 5925)
            return "5 GHz"
        return "6 GHz"
    }

    readonly property string deviceNames: devices.map(d => d.name).sort().join(",")
    // Only re-scan the bus when the set of interfaces changes.
    onDeviceNamesChanged: if (busProcess) busProcess.running = true

    // No Quickshell API exposes whether a NIC hangs off USB; keep the sysfs read.
    Process {
        id: busProcess
        command: ["/bin/sh", "-c",
            "for i in /sys/class/net/*; do "
            + "iface=${i##*/}; "
            + "bus=$(readlink -f \"$i/device/subsystem\" 2>/dev/null); "
            + "case \"$bus\" in */usb) echo \"$iface 1\";; *) echo \"$iface 0\";; esac; "
            + "done"]
        stdout: StdioCollector {
            onStreamFinished: root.parseExternal(text)
        }
        Component.onCompleted: running = true
    }

    function parseExternal(text) {
        const map = {}
        const lines = String(text).split("\n")
        for (let i = 0; i < lines.length; i++) {
            const p = lines[i].trim().split(/\s+/)
            if (p.length === 2 && p[0] !== "")
                map[p[0]] = p[1] === "1"
        }
        root.externalMap = map
    }
}
