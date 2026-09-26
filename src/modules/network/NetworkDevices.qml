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

    // ------------------------------------------------------------------
    // VPN (nmcli + warp-cli; Quickshell.Networking exposes no VPN API).
    // Shared by the bar shield badge and the popup section, and polled
    // always so the bar tracks state while the popup is closed.
    // ------------------------------------------------------------------
    // [{ name, uuid, warp, active, status }]
    property var vpnConnections: []
    readonly property int vpnActiveCount: vpnConnections.filter(v => v.active).length
    readonly property bool vpnActive: vpnActiveCount > 0
    // Profile pinned in the popup header card (mirrors the connected AP).
    readonly property var activeVpn: {
        const v = root.vpnConnections.find(x => x.active)
        return v === undefined ? null : v
    }

    // Non-active profiles listed below the popup header; the active one is pinned.
    function vpnProfiles() {
        return root.vpnConnections.filter(v => !v.active)
    }

    function refreshVpn() {
        vpnProcess.running = true
    }

    // Split one `nmcli -t` line, honouring `\:` / `\\` escapes.
    function splitTerse(line) {
        const out = []
        let cur = ""
        for (let i = 0; i < line.length; i++) {
            const c = line.charAt(i)
            if (c === "\\" && i + 1 < line.length) {
                cur += line.charAt(i + 1)
                i++
            } else if (c === ":") {
                out.push(cur)
                cur = ""
            } else {
                cur += c
            }
        }
        out.push(cur)
        return out
    }

    function parseVpn(text) {
        const active = {}
        const list = []
        let warpState = null
        const lines = String(text).split("\n")
        for (let i = 0; i < lines.length; i++) {
            const raw = lines[i]
            if (raw === "")
                continue
            if (raw.startsWith("K\t")) {
                const f = root.splitTerse(raw.slice(2))
                if (f.length >= 2)
                    active[f[1]] = true
            } else if (raw.startsWith("V\t")) {
                const f = root.splitTerse(raw.slice(2))
                // vpn = IPsec/OpenVPN/etc · wireguard = native WG profiles
                if (f.length >= 3 && (f[1] === "vpn" || f[1] === "wireguard"))
                    list.push({ name: f[0], uuid: f[2], warp: false, active: false, status: "" })
            } else if (raw.startsWith("W\t")) {
                // warp-cli status, 1st line minus "Status update: "
                warpState = raw.slice(2)
            }
        }
        for (let j = 0; j < list.length; j++) {
            list[j].active = active[list[j].uuid] === true
            list[j].status = list[j].active ? "Connected" : "Disconnected"
        }
        // Cloudflare WARP runs outside NetworkManager (warp-svc) -> synthetic
        // row, always listed first when warp-cli is installed.
        if (warpState !== null && warpState !== "")
            list.unshift({ name: "Cloudflare WARP", uuid: "", warp: true,
                active: warpState === "Connected", status: warpState })
        root.vpnConnections = list
    }

    // Connect / disconnect by UUID. `id` only takes a connection NAME ->
    // must use the `uuid` keyword. Connecting a profile first brings the
    // active one down, so only one VPN is ever up.
    function vpnQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    function toggleVpn(v) {
        const commands = []
        const same = (a, b) => a.warp === b.warp && (a.warp || a.uuid === b.uuid)
        for (const o of root.vpnConnections) {
            if (o.active && !same(o, v))
                commands.push(o.warp ? "warp-cli disconnect"
                    : "nmcli connection down uuid " + root.vpnQuote(o.uuid))
        }
        commands.push(v.warp
            ? "warp-cli " + (v.active ? "disconnect" : "connect")
            : "nmcli connection " + (v.active ? "down" : "up")
                + " uuid " + root.vpnQuote(v.uuid))
        vpnCommand.command = ["/bin/sh", "-c", commands.join("\n")]
        vpnCommand.running = true
    }

    // VPN profiles: full list (V, TYPE-filtered in parseVpn) + active set (K,
    // matched by UUID) + WARP state (W).
    Process {
        id: vpnProcess
        command: ["/bin/sh", "-c",
            "nmcli -t -f NAME,TYPE,UUID connection show 2>/dev/null"
            + " | while IFS= read -r l; do printf 'V\\t%s\\n' \"$l\"; done\n"
            + "nmcli -t -f NAME,UUID connection show --active 2>/dev/null"
            + " | while IFS= read -r l; do printf 'K\\t%s\\n' \"$l\"; done\n"
            + "if command -v warp-cli >/dev/null 2>&1; then\n"
            + "  w=$(warp-cli status 2>/dev/null"
            + " | awk 'NR==1 { sub(/^Status update: /, \"\"); print; exit }')\n"
            + "  [ -n \"$w\" ] && printf 'W\\t%s\\n' \"$w\"\n"
            + "fi"]
        stdout: StdioCollector {
            onStreamFinished: root.parseVpn(text)
        }
    }

    // Re-read VPN state after every connect / disconnect attempt, plus once
    // more after a settle delay (WARP still reports "Connecting" right away).
    Process {
        id: vpnCommand
        onExited: {
            root.refreshVpn()
            vpnSettle.restart()
        }
    }

    Timer {
        id: vpnSettle
        interval: 1500
        onTriggered: root.refreshVpn()
    }

    // Always-on poll so the bar badge tracks VPN state with the popup closed.
    Timer {
        interval: 10000
        repeat: true
        running: true
        onTriggered: root.refreshVpn()
        Component.onCompleted: root.refreshVpn()
    }
}
