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

    readonly property var devices: NetworkDevices.devices
    // Ordered internal-first: eth internal, eth external, wifi internal, wifi external.
    readonly property var deviceSections: NetworkDevices.ordered

    // Access-point list scrolling: at most `maxApRows` rows fit; beyond that
    // the section scrolls.
    readonly property int maxApRows: 5
    readonly property int apRowHeight: 38
    readonly property int apRowSpacing: 2

    // ------------------------------------------------------------------
    // Extra link info Quickshell.Networking does not expose, read from
    // `iw` + `nmcli` (freq / width / bitrate / signal / IPv4 / per-AP band).
    // SSID, security, signal, connected, known, state all come natively.
    // ------------------------------------------------------------------
    // iface -> { freq, width, rate, signal, ip }  (only while connected)
    property var linkMap: ({})
    // iface -> { ssid -> freq }  (strongest BSSID per SSID wins)
    property var freqMap: ({})

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
        const links = {}
        const freqs = {}
        const lines = String(text).split("\n")
        for (let i = 0; i < lines.length; i++) {
            const raw = lines[i]
            if (raw === "")
                continue
            const p = raw.split("\t")
            if (p[0] === "C" && p.length >= 7) {
                // C <iface> <freq> <width> <rate> <signal> <ip>
                links[p[1]] = { freq: p[2], width: p[3], rate: p[4], signal: p[5], ip: p[6] }
            } else if (p[0] === "A" && p.length >= 3) {
                // A <iface> <nmcli SSID:FREQ line>
                const fields = popup.splitTerse(p[2])
                if (fields.length < 2 || fields[0] === "")
                    continue
                if (freqs[p[1]] === undefined)
                    freqs[p[1]] = {}
                // list is signal-sorted: keep the strongest BSSID per SSID
                if (freqs[p[1]][fields[0]] === undefined)
                    freqs[p[1]][fields[0]] = fields[1]
            }
        }
        popup.linkMap = links
        popup.freqMap = freqs
    }

    function deviceSecurity(dev) {
        const n = NetworkDevices.connectedNetwork(dev)
        return n === null ? "" : NetworkDevices.securityLabel(n.security)
    }

    // Single info line for a wired device: link speed.
    function wiredInfoLine(dev) {
        if (dev.hasLink && dev.linkSpeed > 0)
            return dev.linkSpeed + " Mb/s"
        return ""
    }

    // Single info line for an access point: band · security (band is the only
    // value still read from nmcli; everything else is native).
    function apInfo(net) {
        const parts = []
        const m = popup.freqMap[net.device.name]
        const band = NetworkDevices.freqBand(m === undefined ? "" : m[net.name])
        if (band !== "")
            parts.push(band)
        const sec = NetworkDevices.securityLabel(net.security)
        if (sec !== "" && sec !== "Unknown")
            parts.push(sec)
        return parts.join("   ·   ")
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
        const info = popup.linkMap[dev.name]
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
        const info = popup.linkMap[dev.name]
        if (info === undefined)
            return ""
        const parts = []
        if (info.rate !== "")
            parts.push(info.rate + " Mbps")
        if (info.width !== "")
            parts.push(info.width + " MHz")
        if (info.signal !== "")
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
        for (const d of NetworkDevices.wifiDevices)
            d.scannerEnabled = true
        refreshWifiInfo()
    }

    function popupClosed() {
        for (const d of NetworkDevices.wifiDevices)
            d.scannerEnabled = false
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

    function activate(net) {
        // Starting a new interaction closes any open password prompt.
        if (popup.pendingNetwork !== null) {
            popup.pendingNetwork = null
            popup.password = ""
        }
        if (net.connected) {
            net.disconnect()
        } else if (net.known || NetworkDevices.isOpen(net)) {
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

    // Link details Quickshell.Networking does not expose. Emitted lines:
    //   C <iface> <freq> <width> <rate> <signal> <ip>   (only when connected)
    //   A <iface> <nmcli SSID:FREQ line>                (per scanned AP)
    // Native rescan: Quickshell already issues RequestScan every ~10 s while
    // `scannerEnabled`, so no explicit `nmcli ... rescan` is needed.
    Process {
        id: wifiInfoProcess
        command: ["/bin/sh", "-c",
            "for i in /sys/class/net/*; do\n"
            + "  iface=${i##*/}\n"
            + "  [ -d \"$i/wireless\" ] || continue\n"
            + "  nmcli -t -f SSID,FREQ device wifi list ifname \"$iface\" --rescan no 2>/dev/null | while IFS= read -r line; do\n"
            + "    printf 'A\\t%s\\t%s\\n' \"$iface\" \"$line\"\n"
            + "  done\n"
            + "  ip=$(ip -4 -o addr show dev \"$iface\" 2>/dev/null | awk '{ split($4, a, \"/\"); print a[1]; exit }')\n"
            + "  link=$(iw dev \"$iface\" link 2>/dev/null)\n"
            + "  case \"$link\" in\n"
            + "  \"Connected to\"*)\n"
            + "    info=$(iw dev \"$iface\" info 2>/dev/null)\n"
            + "    printf '%s\\n%s\\n' \"$link\" \"$info\" | awk -v iface=\"$iface\" -v ip=\"$ip\" '\n"
            + "      /^Connected/ { conn = 1 }\n"
            + "      /freq:/ && f == \"\" { f = $2 }\n"
            + "      /signal:/ && s == \"\" { s = $2 }\n"
            + "      /tx bitrate:/ { r = $3 }\n"
            + "      /bitrate:/ && r == \"\" { r = $3 }\n"
            + "      /width:/ && w == \"\" { for (j = 1; j <= NF; j++) if ($j == \"width:\") { w = $(j+1); exit } }\n"
            + "      END { if (conn) print \"C\\t\" iface \"\\t\" f \"\\t\" w \"\\t\" r \"\\t\" s \"\\t\" ip }\n"
            + "    '\n"
            + "    ;;\n"
            + "  esac\n"
            + "done"]
        stdout: StdioCollector {
            onStreamFinished: popup.parseWifiInfo(text)
        }
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

    // Native link-state changes refresh the CLI data immediately instead of
    // waiting for the poll above (IP / bitrate right after connecting).
    Item {
        id: linkWatcher
        width: 0
        height: 0
        visible: false

        Repeater {
            model: NetworkDevices.wifiDevices

            delegate: Item {
                id: watcher
                required property var modelData
                width: 0
                height: 0

                Connections {
                    target: watcher.modelData

                    function onConnectedChanged() {
                        if (popup.visible)
                            popup.refreshWifiInfo()
                    }

                    function onStateChanged() {
                        if (popup.visible)
                            popup.refreshWifiInfo()
                    }
                }
            }
        }
    }

    // Internet reachability is a system-global NetworkManager value, not a
    // per-device one, so it lives in the popup header only. Only anomalies
    // are shown: `Full` / `Unknown` render nothing.
    function connectivityLabel(conn) {
        switch (conn) {
        case NetworkConnectivity.None:
            return "No internet"
        case NetworkConnectivity.Portal:
            return "Portal"
        case NetworkConnectivity.Limited:
            return "Limited"
        default:
            return ""
        }
    }

    function connectivityColor(conn) {
        return conn === NetworkConnectivity.Portal
            ? Theme.accentColor : Theme.urgentColor
    }

    // Header: title + connectivity status + connection editor + close
    Item {
        width: parent.width
        height: 26

        Text {
            id: headerTitle
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Networks"
            color: Theme.fgColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
        }

        Text {
            id: connectivityBadge
            anchors.left: headerTitle.right
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: popup.connectivityLabel(Networking.connectivity)
            visible: text !== ""
            color: popup.connectivityColor(Networking.connectivity)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 3
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
            // Mid-transition (NM connect/disconnect in flight). NetworkDevice
            // has no `stateChanging`; derive it from `state`.
            readonly property bool changing: modelData.state === ConnectionState.Connecting
                || modelData.state === ConnectionState.Disconnecting
            readonly property var aps: section.isWifi ? popup.networksOf(section.modelData) : []
            readonly property var connectedAp: section.isWifi
                ? NetworkDevices.connectedNetwork(section.modelData) : null
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

                    // Header row: type icon + name + enable switch
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


                        Text {
                            id: devName
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignHCenter
                            text: section.modelData.name
                            color: Theme.fgColor
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Text {
                            anchors.left: devName.right
                            anchors.right: controls.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignLeft
                            text: section.isWifi ? "Wifi" : "Ethernet"
                            color: Theme.fgColorMuted
                            font.pixelSize: Math.round(Theme.fontSize * 0.8)
                        }

                        Row {
                            id: controls
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10

                            // Enable / disable the interface (NetworkManager managed).
                            // Disabled while NM is still flipping the state.
                            // Kept last so it always sits at the far right.
                            Switch {
                                anchors.verticalCenter: parent.verticalCenter
                                checked: section.modelData.nmManaged
                                enabled: !section.changing
                                onToggled: section.modelData.nmManaged = !section.modelData.nmManaged
                            }
                        }
                    }

                    // Connected AP: same background as the header, two info lines.
                    Item {
                        width: parent.width
                        visible: section.connectedAp !== null
                        height: visible ? connectedInfo.implicitHeight + 16 : 0

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: section.modelData.disconnect()
                        }

                        Row {
                            id: connectedInfo
                            anchors.fill: parent
                            // Same 8px horizontal padding as the AP rows below so
                            // every signal icon lands in one vertical column.
                            anchors.margins: 8
                            spacing: 8

                            // Tick removed earlier: the signal icon on the
                            // right is the only trailing slot.

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 18 - parent.spacing
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
                                    ? NetworkDevices.signalGlyph(section.connectedAp.signalStrength) : ""
                                color: Theme.accentColor
                                opacity: 0.8
                            }
                        }
                    }
                }
            }

            // Device info line, only for wired devices (Wi-Fi info lives in
            // the connected AP block above).
            Text {
                visible: !section.isWifi
                width: parent.width
                text: popup.wiredInfoLine(section.modelData)
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
                            // Mid-connect/disconnect: ignore clicks, show status.
                            readonly property bool changing: modelData.stateChanging
                            // Saved profile that is not the active link -> forget.
                            readonly property bool canForget: modelData.known && !modelData.connected
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
                                enabled: !apRow.prompting && !apRow.changing
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
                                        : (NetworkDevices.isOpen(apRow.modelData) ? "\ue065" : "\ue066")
                                    color: apRow.connected ? Theme.accentColor : Theme.fgColor
                                    opacity: apRow.connected ? 1 : 0.7
                                }

                                // An icon slot is reserved for "forget" so the
                                // name column never shifts on hover, and the
                                // signal icon stays last -> same vertical column
                                // as the one in the connected-AP header block.
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 18 * 3 - 3 * parent.spacing
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
                                        text: apRow.changing ? "Connecting…"
                                            : popup.apInfo(apRow.modelData)
                                        color: Theme.fgColor
                                        opacity: apRow.changing ? 0.9 : 0.6
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize - 4
                                        elide: Text.ElideRight
                                    }
                                }

                                // Drop the saved profile (hover-revealed).
                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 18
                                    horizontalAlignment: Text.AlignHCenter
                                    glyph: "\ue037" // sign-out = leave/forget
                                    color: Theme.fgColorMuted
                                    opacity: apRow.canForget && apMouse.containsMouse ? 1 : 0
                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: apRow.canForget && apMouse.containsMouse
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: apRow.modelData.forget()
                                    }
                                }

                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 18
                                    horizontalAlignment: Text.AlignHCenter
                                    glyph: NetworkDevices.signalGlyph(apRow.modelData.signalStrength)
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
