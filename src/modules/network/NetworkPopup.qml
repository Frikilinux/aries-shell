import QtQuick
import Quickshell.Io
import Quickshell.Networking
import "../theme"
import "../icon"
import "../popup"
import "../widgets"

BarPopup {
    id: popup

    // Icon style used by this popup's icons. Defaults to Theme.iconStyle.
    property string iconStyle: Theme.iconStyle

    // Never taller than 75% of the screen height.
    maxContentHeight: popup.screen ? Math.round(popup.screen.height * 0.75) : 540

    readonly property var devices: Networking.devices.values
    // Ordered internal-first: eth internal, eth external, wifi internal, wifi external.
    readonly property var deviceSections: NetworkDevices.ordered

    // Access-point list scrolling: at most `maxApRows` rows fit; beyond that
    // the section scrolls.
    readonly property int maxApRows: 5
    readonly property int apRowHeight: 38
    readonly property int apRowSpacing: 2

    // ------------------------------------------------------------------
    // Per-device/AP extra info read from `iw` + `nmcli`
    // ------------------------------------------------------------------
    // iface -> { bands }
    property var wifiInfoMap: ({})
    // iface -> { ssid -> { bssid, chan, freq, signal, security } }
    property var apInfoMap: ({})

    function refreshWifiInfo() {
        wifiInfoProcess.running = true
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

    function parseWifiInfo(text) {
        const devMap = {}
        const apMap = {}
        const lines = String(text).split("\n")
        for (let i = 0; i < lines.length; i++) {
            const raw = lines[i]
            if (raw === "")
                continue
            const p = raw.split("\t")
            if (p[0] === "D" && p.length >= 3) {
                if (devMap[p[1]] === undefined)
                    devMap[p[1]] = popup.emptyDevInfo()
                devMap[p[1]].bands = p[2]
            } else if (p[0] === "C" && p.length >= 7) {
                // C <iface> <freq> <width> <rate> <signal> <ip>
                if (devMap[p[1]] === undefined)
                    devMap[p[1]] = popup.emptyDevInfo()
                devMap[p[1]].freq = p[2]
                devMap[p[1]].width = p[3]
                devMap[p[1]].rate = p[4]
                devMap[p[1]].signal = p[5]
                devMap[p[1]].ip = p[6]
            } else if (p[0] === "A" && p.length >= 3) {
                const iface = p[1]
                const fields = popup.splitTerse(p[2])
                // BSSID : SSID : CHAN : FREQ : SIGNAL : SECURITY
                if (fields.length >= 6) {
                    const ssid = fields[1]
                    if (apMap[iface] === undefined)
                        apMap[iface] = {}
                    // list is signal-sorted: keep the strongest BSSID per SSID
                    if (apMap[iface][ssid] === undefined) {
                        apMap[iface][ssid] = {
                            bssid: fields[0],
                            chan: fields[2],
                            freq: fields[3],
                            signal: fields[4],
                            security: fields[5]
                        }
                    }
                }
            }
        }
        popup.wifiInfoMap = devMap
        popup.apInfoMap = apMap
    }

    function emptyDevInfo() {
        return { bands: "", freq: "", width: "", rate: "", signal: "", ip: "" }
    }

    // "2.4,5,6" -> "2.4 · 5 · 6 GHz"
    function wifiBands(dev) {
        const info = popup.wifiInfoMap[dev.name]
        if (info === undefined || info.bands === "")
            return ""
        return info.bands.split(",").join(" · ") + " GHz"
    }

    // "5745 MHz" -> "5 GHz"
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

    // ------------------------------------------------------------------
    // Security / login info
    // ------------------------------------------------------------------
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

    function deviceSecurity(dev) {
        const n = dev.networks.values.find(x => x.connected)
        return n === undefined ? "" : popup.securityLabel(n.security)
    }

    // Single info line: bands · security (Wi-Fi) / link speed (wired).
    function deviceInfoLine(dev) {
        const parts = []
        if (dev.type === DeviceType.Wifi) {
            const bands = popup.wifiBands(dev)
            if (bands !== "")
                parts.push(bands)
            const sec = popup.deviceSecurity(dev)
            if (sec !== "")
                parts.push(sec)
        } else if (dev.connected && dev.linkSpeed > 0) {
            parts.push(dev.linkSpeed + " Mb/s")
        }
        return parts.join("   ·   ")
    }

    // Single info line for an access point: band · security.
    function apInfo(dev, ssid) {
        const m = popup.apInfoMap[dev.name]
        if (m === undefined)
            return ""
        const a = m[ssid]
        if (a === undefined)
            return ""
        const parts = []
        const band = popup.freqBand(a.freq)
        if (band !== "")
            parts.push(band)
        if (a.security !== "" && a.security !== "--")
            parts.push(a.security)
        return parts.join("   ·   ")
    }

    function connectedNetwork(dev) {
        const n = dev.networks.values.find(x => x.connected)
        return n === undefined ? null : n
    }

    // Access points for the scrolling list: the connected one is pinned under
    // the header, so it is excluded here.
    function networksOf(dev) {
        const list = dev.networks.values.filter(x => !x.connected)
        list.sort((a, b) => b.signalStrength - a.signalStrength)
        return list
    }

    // Connected AP info line 1: frequency · security · IP
    function connectedLine1(dev) {
        const info = popup.wifiInfoMap[dev.name]
        const parts = []
        if (info !== undefined && info.freq !== "")
            parts.push(Math.round(parseFloat(info.freq)) + " MHz")
        const sec = popup.deviceSecurity(dev)
        if (sec !== "")
            parts.push(sec)
        if (info !== undefined && info.ip !== "")
            parts.push(info.ip)
        return parts.join("   ·   ")
    }

    // Connected AP info line 2: link speed · channel width · signal
    function connectedLine2(dev) {
        const info = popup.wifiInfoMap[dev.name]
        const parts = []
        if (info !== undefined && info.rate !== "")
            parts.push(info.rate + " Mbps")
        if (info !== undefined && info.width !== "")
            parts.push(info.width + " MHz")
        if (info !== undefined && info.signal !== "")
            parts.push(info.signal + " dBm")
        return parts.join("   ·   ")
    }

    // Wi-Fi network awaiting a password (secured and unknown)
    property var pendingNetwork: null
    property string password: ""
    // Network we last tried to connect with a PSK: watched so a rejected
    // password re-opens the prompt.
    property var connectingNetwork: null
    property bool passwordFailed: false

    function popupOpened() {
        for (const d of popup.devices) {
            if (d.type === DeviceType.Wifi)
                d.scannerEnabled = true
        }
        refreshWifiInfo()
    }

    function popupClosed() {
        for (const d of popup.devices) {
            if (d.type === DeviceType.Wifi)
                d.scannerEnabled = false
        }
        pendingNetwork = null
        password = ""
        connectingNetwork = null
        passwordFailed = false
    }

    onDevicesChanged: if (popup.visible) refreshWifiInfo()

    // Wrong PSK / auth rejection: keep asking until the password works.
    Connections {
        target: popup.connectingNetwork

        function onConnectedChanged() {
            if (popup.connectingNetwork !== null && popup.connectingNetwork.connected) {
                popup.connectingNetwork = null
                popup.passwordFailed = false
            }
        }

        function onConnectionFailed(reason) {
            const net = popup.connectingNetwork
            if (net === null)
                return
            if (reason === ConnectionFailReason.NoSecrets
                || reason === ConnectionFailReason.WifiAuthTimeout
                || reason === ConnectionFailReason.WifiClientFailed) {
                popup.passwordFailed = true
                popup.pendingNetwork = net
                popup.password = ""
            } else {
                popup.connectingNetwork = null
            }
        }
    }

    function isOpen(net) {
        return net.security === WifiSecurityType.Open
            || net.security === WifiSecurityType.Owe
            || net.security === WifiSecurityType.Unknown
    }

    function signalGlyph(strength) {
        if (strength >= 0.75)
            return "\ue065" // wifi4
        if (strength >= 0.50)
            return "\ue064" // wifi3
        if (strength >= 0.25)
            return "\ue063" // wifi2
        return "\ue062"     // wifi1
    }

    function activate(net) {
        // Starting a new interaction closes any open password prompt.
        if (popup.pendingNetwork !== null) {
            popup.pendingNetwork = null
            popup.password = ""
        }
        if (net.connected) {
            net.disconnect()
        } else if (net.known || isOpen(net)) {
            popup.passwordFailed = false
            popup.connectingNetwork = net
            net.connect()
        } else {
            popup.passwordFailed = false
            popup.pendingNetwork = net
            popup.password = ""
        }
    }

    function submitPassword() {
        if (popup.pendingNetwork !== null) {
            popup.connectingNetwork = popup.pendingNetwork
            popup.pendingNetwork.connectWithPsk(popup.password)
            popup.pendingNetwork = null
            popup.password = ""
        }
    }

    // Force a fresh scan on a specific Wi-Fi interface.
    function rescan(dev) {
        rescanProcess.command = ["nmcli", "device", "wifi", "rescan", "ifname", dev.name]
        rescanProcess.running = true
    }

    // Bands for every wireless interface plus its scanned APs:
    //   D <iface> <2.4,5,6>
    //   C <iface> <freq> <width> <rate> <signal> <ip>   (only when connected)
    //   A <iface> <nmcli -t AP line>
    Process {
        id: wifiInfoProcess
        command: ["/bin/sh", "-c",
            "for i in /sys/class/net/*; do\n"
            + "  iface=${i##*/}\n"
            + "  [ -d \"$i/wireless\" ] || continue\n"
            + "  info=$(iw dev \"$iface\" info 2>/dev/null)\n"
            + "  wiphy=$(printf '%s\\n' \"$info\" | awk '/wiphy/ {print $2; exit}')\n"
            + "  bands=\"\"\n"
            + "  if [ -n \"$wiphy\" ]; then\n"
            + "    bands=$(iw phy \"phy$wiphy\" info 2>/dev/null | awk '/Band [0-9]+:/ {inb=1; got=0; next} inb && !got && /MHz \\[[0-9]+\\]/ {f=$2+0; got=1; if (f<3000) print \"2.4\"; else if (f<5925) print \"5\"; else print \"6\"}' | sort -u | paste -sd, -)\n"
            + "  fi\n"
            + "  printf 'D\\t%s\\t%s\\n' \"$iface\" \"$bands\"\n"
            + "  link=$(iw dev \"$iface\" link 2>/dev/null)\n"
            + "  if printf '%s\\n' \"$link\" | grep -q '^Connected'; then\n"
            + "    freq=$(printf '%s\\n' \"$link\" | awk '/freq:/ {print $2; exit}')\n"
            + "    sig=$(printf '%s\\n' \"$link\" | awk '/signal:/ {print $2; exit}')\n"
            + "    rate=$(printf '%s\\n' \"$link\" | awk '/tx bitrate:/ {print $3; exit}')\n"
            + "    [ -z \"$rate\" ] && rate=$(printf '%s\\n' \"$link\" | awk '/bitrate:/ {print $3; exit}')\n"
            + "    width=$(printf '%s\\n' \"$info\" | awk '/width:/ {for (j=1;j<=NF;j++) if ($j==\"width:\") {print $(j+1); exit}}')\n"
            + "    ip=$(ip -4 -o addr show dev \"$iface\" 2>/dev/null | awk '{print $4; exit}' | cut -d/ -f1)\n"
            + "    printf 'C\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' \"$iface\" \"$freq\" \"$width\" \"$rate\" \"$sig\" \"$ip\"\n"
            + "  fi\n"
            + "  nmcli -t -f BSSID,SSID,CHAN,FREQ,SIGNAL,SECURITY device wifi list ifname \"$iface\" --rescan no 2>/dev/null | while IFS= read -r line; do\n"
            + "    printf 'A\\t%s\\t%s\\n' \"$iface\" \"$line\"\n"
            + "  done\n"
            + "done"]
        stdout: StdioCollector {
            onStreamFinished: popup.parseWifiInfo(text)
        }
    }

    Process {
        id: rescanProcess
    }

    Process {
        id: connectionEditor
        command: ["nm-connection-editor"]
    }

    Timer {
        interval: 10000
        repeat: true
        running: popup.visible
        onTriggered: popup.refreshWifiInfo()
        onRunningChanged: if (running) popup.refreshWifiInfo()
    }

    // Header: title + connection editor + close
    Item {
        width: parent.width
        height: 26

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Networks"
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
                    onClicked: connectionEditor.running = true
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
        visible: popup.deviceSections.length === 0
        width: parent.width
        text: "No network devices"
        color: Theme.fgColor
        opacity: 0.6
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    // One section per network interface
    Repeater {
        model: popup.deviceSections

        delegate: Column {
            id: section
            required property var modelData
            readonly property bool isWifi: modelData.type === DeviceType.Wifi
            readonly property bool connected: modelData.connected
            readonly property var aps: section.isWifi ? popup.networksOf(section.modelData) : []
            readonly property var connectedAp: section.isWifi
                ? popup.connectedNetwork(section.modelData) : null
            width: popup.contentWidth
            spacing: 4

            // Header card: header row + the connected AP info share one
            // `bgColorMuted` background so the AP looks attached to the header.
            Rectangle {
                id: headerCard
                width: parent.width
                radius: 6
                color: Theme.bgColorMuted
                implicitHeight: headerColumn.implicitHeight

                Column {
                    id: headerColumn
                    width: parent.width
                    spacing: 0

                    // Header row: type icon + name + rescan + enable switch
                    Item {
                        width: parent.width
                        height: 30

                        // Wired: click to connect / disconnect (controls sit on top)
                        MouseArea {
                            anchors.fill: parent
                            anchors.rightMargin: controls.width + 16
                            enabled: !section.isWifi
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (section.modelData.connected)
                                    section.modelData.disconnect()
                                else if (section.modelData.network !== null)
                                    section.modelData.network.connect()
                            }
                        }

                        Icon {
                            id: sectionIcon
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignHCenter
                            glyph: section.isWifi ? "\ue077" : "\ue075" // wifi-logo / ethernet
                            style: popup.iconStyle
                            color: section.connected ? Theme.accentColor : Theme.fgColor
                            opacity: section.connected ? 1 : 0.6
                            // The wifi-logo is a detailed wordmark: it needs to be
                            // larger than the plain ethernet glyph to stay legible.
                            font.pixelSize: Math.round(Theme.iconSize * 1.3)
                        }

                        Text {
                            anchors.left: sectionIcon.right
                            anchors.leftMargin: 8
                            anchors.right: controls.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: section.modelData.name
                            color: Theme.fgColor
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Row {
                            id: controls
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10

                            Icon {
                                visible: section.isWifi
                                anchors.verticalCenter: parent.verticalCenter
                                glyph: "\ue01a" // arrow-clockwise
                                style: popup.iconStyle
                                opacity: 0.8
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: popup.rescan(section.modelData)
                                }
                            }

                            // Enable / disable the interface (NetworkManager managed).
                            // Kept last so it always sits at the far right.
                            Switch {
                                anchors.verticalCenter: parent.verticalCenter
                                checked: section.modelData.nmManaged
                                onToggled: section.modelData.nmManaged = !section.modelData.nmManaged
                            }
                        }
                    }

                    // Connected AP: same background as the header, two info lines.
                    Item {
                        width: parent.width
                        visible: section.connectedAp !== null
                        height: visible ? connectedInfo.implicitHeight + 12 : 0

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: section.modelData.disconnect()
                        }

                        Row {
                            id: connectedInfo
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 8

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18
                                horizontalAlignment: Text.AlignHCenter
                                glyph: "\ue029" // checkmark-circle
                                style: popup.iconStyle
                                color: Theme.accentColor
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 18 - 18 - 2 * parent.spacing
                                spacing: 0

                                Text {
                                    width: parent.width
                                    text: section.connectedAp ? section.connectedAp.name : ""
                                    color: Theme.fgColor
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                    elide: Text.ElideRight
                                }

                                // 1 — connected frequency · security · IP
                                Text {
                                    width: parent.width
                                    text: popup.connectedLine1(section.modelData)
                                    color: Theme.fgColor
                                    opacity: 0.6
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 4
                                    elide: Text.ElideRight
                                }

                                // 2 — link speed · channel width · signal
                                Text {
                                    width: parent.width
                                    text: popup.connectedLine2(section.modelData)
                                    color: Theme.fgColor
                                    opacity: 0.6
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 4
                                    elide: Text.ElideRight
                                }
                            }

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18
                                horizontalAlignment: Text.AlignHCenter
                                glyph: section.connectedAp
                                    ? popup.signalGlyph(section.connectedAp.signalStrength) : ""
                                style: popup.iconStyle
                                color: Theme.accentColor
                                opacity: 0.8
                            }
                        }
                    }
                }
            }

            // Device info line, only for wired devices (Wi-Fi moved to the
            // connected AP block above).
            Text {
                visible: !section.isWifi
                width: parent.width
                text: popup.deviceInfoLine(section.modelData)
                color: Theme.fgColor
                opacity: 0.6
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
                elide: Text.ElideRight
            }

            // Found access points (Wi-Fi). Capped to `maxApRows`; scrolls if more.
            Flickable {
                id: apsFlick
                visible: section.isWifi && section.aps.length > 0
                width: parent.width
                height: Math.min(apsColumn.implicitHeight,
                    popup.maxApRows * popup.apRowHeight
                        + popup.apRowSpacing * (popup.maxApRows - 1))
                contentWidth: width
                contentHeight: apsColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: apsColumn
                    width: parent.width
                    spacing: popup.apRowSpacing

                    Repeater {
                        model: section.aps

                        delegate: Rectangle {
                            id: apRow
                            required property var modelData
                            readonly property bool connected: modelData.connected
                            readonly property bool prompting: popup.pendingNetwork === apRow.modelData
                            width: popup.contentWidth
                            height: popup.apRowHeight
                            radius: 6
                            color: apMouse.containsMouse
                                ? Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.12)
                                : "transparent"

                            onPromptingChanged: if (prompting)
                                Qt.callLater(() => passwordField.forceActiveFocus())

                            // Row click (reveal password / connect). Declared
                            // first so the prompt below sits on top of it.
                            MouseArea {
                                id: apMouse
                                anchors.fill: parent
                                enabled: !apRow.prompting
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: popup.activate(apRow.modelData)
                            }

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 8
                                visible: !apRow.prompting

                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 18
                                    horizontalAlignment: Text.AlignHCenter
                                    glyph: apRow.connected ? "\ue029"
                                        : (popup.isOpen(apRow.modelData) ? "\ue065" : "\ue066")
                                    style: popup.iconStyle
                                    color: apRow.connected ? Theme.accentColor : Theme.fgColor
                                    opacity: apRow.connected ? 1 : 0.7
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 18 - 18 - 2 * parent.spacing
                                    spacing: 0

                                    Text {
                                        width: parent.width
                                        text: apRow.modelData.name
                                        color: Theme.fgColor
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        width: parent.width
                                        text: popup.apInfo(section.modelData, apRow.modelData.name)
                                        color: Theme.fgColor
                                        opacity: 0.6
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize - 4
                                        elide: Text.ElideRight
                                    }
                                }

                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 18
                                    horizontalAlignment: Text.AlignHCenter
                                    glyph: popup.signalGlyph(apRow.modelData.signalStrength)
                                    style: popup.iconStyle
                                    color: apRow.connected ? Theme.accentColor : Theme.fgColor
                                    opacity: 0.8
                                }
                            }

                            // Password prompt drawn over the requesting AP row
                            Rectangle {
                                visible: apRow.prompting
                                anchors.fill: parent
                                radius: 6
                                color: Qt.rgba(Theme.accentColor.r, Theme.accentColor.g, Theme.accentColor.b, 0.18)
                                border.width: 1
                                border.color: popup.passwordFailed ? Theme.urgentColor : Theme.accentColor

                                Row {
                                    anchors.fill: parent
                                    anchors.margins: 5
                                    spacing: 6

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 88
                                        text: apRow.modelData.name
                                        color: Theme.fgColor
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize - 2
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        width: parent.width - 88 - connectButton.width - 2 * parent.spacing
                                        height: parent.height
                                        radius: 4
                                        color: Qt.rgba(0, 0, 0, 0.25)
                                        border.width: 1
                                        border.color: Theme.buttonBorder

                                        Text {
                                            anchors.fill: parent
                                            anchors.leftMargin: 6
                                            verticalAlignment: Text.AlignVCenter
                                            visible: passwordField.text === ""
                                            text: popup.passwordFailed ? "Wrong password" : "Password"
                                            color: popup.passwordFailed ? Theme.urgentColor : Theme.fgColor
                                            opacity: popup.passwordFailed ? 0.9 : 0.4
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize - 2
                                        }

                                        TextInput {
                                            id: passwordField
                                            anchors.fill: parent
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 6
                                            verticalAlignment: TextInput.AlignVCenter
                                            echoMode: TextInput.Password
                                            color: Theme.fgColor
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize - 2
                                            selectByMouse: true
                                            focus: apRow.prompting
                                            text: popup.password
                                            onTextEdited: popup.password = text
                                            onAccepted: popup.submitPassword()
                                        }
                                    }

                                    Rectangle {
                                        id: connectButton
                                        width: 62
                                        height: parent.height
                                        radius: 4
                                        color: Theme.buttonPrimaryBgColor

                                        Text {
                                            anchors.centerIn: parent
                                            text: "Connect"
                                            color: Theme.fgColor
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize - 3
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: popup.submitPassword()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
