pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Client for the `aries-connect` daemon (KDE Connect phone bridge) over the
// session bus. Quickshell ships no generic D-Bus client, so this keeps one
// `busctl monitor` process for the signals and fires `busctl call` invocations
// for the methods. Contract: aries-connect-ipc.md (no properties, `s` args).
//
// Initial sync follows the spec: subscribe to the signals first (monitor
// running), then call `Devices()` and `ActiveNotifications()` — otherwise an
// event arriving between a query and the subscription would be lost.
Singleton {
    id: root

    readonly property string busName: "dev.zotta.AriesConnect"
    readonly property string objectPath: "/dev/zotta/AriesConnect"
    readonly property string iface: "dev.zotta.AriesConnect"

    // Every device heard of this session:
    //   { deviceId, name, paired, connected, request, unpairing, pingEnabled }
    // `request` = a pairing request is pending (backend gives it 30 s),
    // `unpairing` = an `Unpair` call is in flight,
    // `pingEnabled` = last `PluginEnabled(id, "kdeconnect.ping")` reply
    // (null until queried; unknown devices count as disabled).
    property var devices: []

    // A `Devices()` call succeeded: the daemon is up on the bus.
    property bool available: false
    // First `ActiveNotifications()` reply arrived: later changes are live and
    // get toasted by the notification server (the startup snapshot doesn't).
    property bool synced: false
    // Last rejection reason ("" = none), e.g. "timeout" / "cancelled".
    property string lastRejectReason: ""

    // Last `PingDevice` failure: { deviceId, text } or null. The backend
    // reports unpaired / plugin disabled / no active channel as a D-Bus error.
    property var pingError: null

    // Queue of device ids waiting for a `PluginEnabled(..., "kdeconnect.ping")`
    // reply (one call at a time; see queryPlugins()).
    property var pluginQueue: []

    // The phone pinged us (popup/toast surfaces it).
    signal pingReceived(string deviceId, string name, string message)

    // Notifications mirrored from the phones, oldest first (backend order:
    // phone timestamp for `ActiveNotifications()`, reception for signals):
    //   { deviceId, notificationId, appName, title, text }
    // Updated in place by id (Android reuses it); removed on dismiss.
    property var notifications: []

    readonly property int notificationCount: root.notifications.length

    // Pending pairing request (popup shows Accept / Reject for it).
    readonly property var request: {
        for (let i = 0; i < root.devices.length; i++) {
            if (root.devices[i].request)
                return root.devices[i]
        }
        return null
    }

    // Live devices only: a lingering link on an unpaired device must not light
    // the glyph (see the popup's device filter).
    readonly property int connectedCount: {
        let n = 0
        for (let i = 0; i < root.devices.length; i++) {
            if (root.devices[i].paired && root.devices[i].connected)
                n++
        }
        return n
    }

    readonly property int pairedCount: {
        let n = 0
        for (let i = 0; i < root.devices.length; i++) {
            if (root.devices[i].paired)
                n++
        }
        return n
    }

    // Label fallback: the daemon may report an empty name before the identity
    // exchange completes.
    function deviceLabel(dev) {
        if (dev === null || dev === undefined)
            return ""
        if (dev.name && dev.name !== "")
            return dev.name
        return dev.deviceId
    }

    // Copy-on-write patch of one device; the array is always replaced so
    // bindings reading `devices` re-evaluate. Missing ids are appended, so a
    // signal arriving for an unseen device (daemon restart) still lands.
    function patch(id, fields, name) {
        const list = root.devices.slice()
        let index = -1
        for (let i = 0; i < list.length; i++) {
            if (list[i].deviceId === id) {
                index = i
                break
            }
        }
        const dev = index === -1 ? {
            "deviceId": id,
            "name": "",
            "paired": false,
            "connected": false,
            "request": false,
            "unpairing": false,
            "pingEnabled": null
        } : Object.assign({}, list[index])
        Object.assign(dev, fields)
        if (name !== undefined && name !== "")
            dev.name = name
        if (index === -1)
            list.push(dev)
        else
            list[index] = dev
        root.devices = list
        return dev
    }

    // Re-read devices + notifications (popup open / monitor restart).
    function refresh() {
        if (!devicesProcess.running)
            devicesProcess.running = true
        if (!notificationsProcess.running)
            notificationsProcess.running = true
    }

    // Coalesced refresh: link churn and rejected pairings are the only hints
    // the daemon gives for changes it does not signal (a phone-side unpair
    // arrives as `PairingRejected("peer unpaired")`, and Android replaces its
    // socket often), so they are followed by an authoritative query.
    function scheduleRefresh() {
        refreshTimer.restart()
    }

    function acceptPairing(deviceId) {
        root.invoke("AcceptPairing", ["s", deviceId])
    }

    function rejectPairing(deviceId) {
        root.invoke("RejectPairing", ["s", deviceId])
    }

    // The row disappears when the backend emits NotificationDismissed.
    function dismissNotification(deviceId, notificationId) {
        root.invoke("DismissNotification", ["ss", deviceId, notificationId])
    }

    // Forget the pairing (KDE Connect "unpair"). `PairingRemoved` moves the
    // device out of the popup; `unpairing` only locks the row until the backend
    // answers.
    function unpair(deviceId) {
        root.patch(deviceId, {
            "unpairing": true
        })
        root.invoke("Unpair", ["s", deviceId])
        unpairTimeout.restart()
    }

    // Desktop -> phone ping. Only meaningful when the device is paired,
    // connected and the plugin is on (the popup enforces it); failures are
    // reported by the backend as D-Bus errors and surfaced in `pingError`.
    function ping(deviceId) {
        root.pingError = null
        pingProcess.deviceId = deviceId
        pingProcess.command = ["busctl", "--user", "call", root.busName, root.objectPath, root.iface, "PingDevice", "ss", deviceId, ""]
        pingProcess.running = true
    }

    // `kdeconnect.ping` state for one device, straight from the backend.
    function queryPlugin(deviceId) {
        if (deviceId === "")
            return
        root.pluginQueue = root.pluginQueue.concat([deviceId])
        root.runPluginQuery()
    }

    function queryPlugins() {
        const ids = []
        for (let i = 0; i < root.devices.length; i++)
            ids.push(root.devices[i].deviceId)
        root.pluginQueue = ids
        root.runPluginQuery()
    }

    function runPluginQuery() {
        if (pluginProcess.running || root.pluginQueue.length === 0)
            return
        const queue = root.pluginQueue.slice()
        const deviceId = queue.shift()
        root.pluginQueue = queue
        pluginProcess.deviceId = deviceId
        pluginProcess.command = ["busctl", "--user", "--json=short", "call", root.busName, root.objectPath, root.iface, "PluginEnabled", "ss", deviceId, "kdeconnect.ping"]
        pluginProcess.running = true
    }

    // Patch only if the device is still known: a reply arriving after
    // `PairingRemoved` must not resurrect it.
    function setPingEnabled(deviceId, enabled) {
        const list = root.devices.slice()
        for (let i = 0; i < list.length; i++) {
            if (list[i].deviceId !== deviceId)
                continue
            if (list[i].pingEnabled === enabled)
                return
            list[i] = Object.assign({}, list[i], {
                "pingEnabled": enabled
            })
            root.devices = list
            return
        }
    }

    function deviceLabelById(deviceId) {
        for (let i = 0; i < root.devices.length; i++) {
            if (root.devices[i].deviceId === deviceId)
                return root.deviceLabel(root.devices[i])
        }
        return deviceId
    }

    function invoke(method, args) {
        action.command = ["busctl", "--user", "call", root.busName, root.objectPath, root.iface, method].concat(args)
        action.running = true
    }

    // `a(ssbb)` reply: data[0] = [[deviceId, name, paired, connected], ...].
    // The reply is authoritative: the daemon emits nothing when a phone
    // unpairs or when it restarts with an empty trust store, so a device
    // missing here was forgotten and must be dropped. Only pending pairing
    // requests survive from local state (they are signal-only).
    function applyDevices(text) {
        let rows
        try {
            rows = JSON.parse(text).data[0]
        } catch (e) {
            return
        }
        if (!Array.isArray(rows))
            return
        // Preserve per-device local state (`pingEnabled`) across reconciles.
        const previous = {}
        for (let i = 0; i < root.devices.length; i++)
            previous[root.devices[i].deviceId] = root.devices[i]
        const list = root.devices.filter(d => d.request === true).map(d => Object.assign({}, d))
        for (let r = 0; r < rows.length; r++) {
            const row = rows[r]
            if (!Array.isArray(row) || row.length < 4)
                continue
            let index = -1
            for (let i = 0; i < list.length; i++) {
                if (list[i].deviceId === row[0]) {
                    index = i
                    break
                }
            }
            const known = previous[row[0]]
            const prev = index === -1 ? {
                "deviceId": row[0],
                "name": "",
                "paired": false,
                "connected": false,
                "request": false,
                "unpairing": false,
                "pingEnabled": known !== undefined ? known.pingEnabled : null
            } : list[index]
            const dev = Object.assign({}, prev, {
                "paired": row[2] === true,
                "connected": row[3] === true
            })
            if (row[1] !== "")
                dev.name = row[1]
            if (index === -1)
                list.push(dev)
            else
                list[index] = dev
        }
        // Notifications of forgotten devices are gone on the daemon side too;
        // `ActiveNotifications()` confirms it, this keeps the mirror coherent
        // even if that reply is late.
        const known = {}
        for (let i = 0; i < list.length; i++)
            known[list[i].deviceId] = true
        const notes = root.notifications.filter(n => known[n.deviceId] === true)
        if (notes.length !== root.notifications.length)
            root.notifications = notes
        root.devices = list
        // Ping plugin state is per device and not part of `Devices()`.
        root.queryPlugins()
    }

    // `a(sssss)` reply: data[0] = [[deviceId, notificationId, appName,
    // title, text], ...]. Authoritative snapshot: replaces the mirror.
    function applyNotifications(text) {
        let rows
        try {
            rows = JSON.parse(text).data[0]
        } catch (e) {
            return
        }
        if (!Array.isArray(rows))
            return
        const list = []
        for (let r = 0; r < rows.length; r++) {
            const row = rows[r]
            if (!Array.isArray(row) || row.length < 5)
                continue
            list.push({
                "deviceId": String(row[0]),
                "notificationId": String(row[1]),
                "appName": String(row[2]),
                "title": String(row[3]),
                "text": String(row[4])
            })
        }
        root.notifications = list
    }

    // Updates reuse the same id: replace by (deviceId, notificationId)
    // instead of duplicating; new ones append in reception order.
    function upsertNotification(data) {
        if (data.length < 5)
            return
        const entry = {
            "deviceId": String(data[0]),
            "notificationId": String(data[1]),
            "appName": String(data[2]),
            "title": String(data[3]),
            "text": String(data[4])
        }
        const list = root.notifications.slice()
        for (let i = 0; i < list.length; i++) {
            if (list[i].deviceId === entry.deviceId && list[i].notificationId === entry.notificationId) {
                list[i] = entry
                root.notifications = list
                return
            }
        }
        list.push(entry)
        root.notifications = list
    }

    function removeNotification(deviceId, notificationId) {
        const list = root.notifications.filter(n => n.deviceId !== deviceId || n.notificationId !== notificationId)
        if (list.length !== root.notifications.length)
            root.notifications = list
    }

    // One `busctl monitor --json=short` line (a D-Bus message, not a signal
    // necessarily: our own calls and replies are matched too).
    function handleLine(line) {
        if (line === "")
            return
        let msg
        try {
            msg = JSON.parse(line)
        } catch (e) {
            return
        }
        if (msg.type !== "signal")
            return
        // The daemon coming or going is invisible on its own interface (no
        // "daemon stopped"/"unpaired" event), so the well-known name is
        // watched too: a restart must not leave the old table on screen.
        if (msg.interface === "org.freedesktop.DBus" && msg.member === "NameOwnerChanged") {
            const data = msg.payload && Array.isArray(msg.payload.data) ? msg.payload.data : []
            if (data.length >= 3 && String(data[0]) === root.busName)
                root.handleDaemonOwner(String(data[2]))
            return
        }
        if (msg.interface !== root.iface)
            return
        root.handleSignal(msg.member, msg.payload && Array.isArray(msg.payload.data) ? msg.payload.data : [])
    }

    // `newOwner` is empty when the daemon left the session bus. A restarting
    // daemon starts from an empty table (notifications are not persisted), so
    // the mirror is dropped and rebuilt from the next initial sync.
    function handleDaemonOwner(newOwner) {
        root.synced = false
        root.lastRejectReason = ""
        root.devices = []
        root.notifications = []
        root.pingError = null
        root.pluginQueue = []
        if (newOwner === "") {
            root.available = false
            return
        }
        root.refresh()
    }

    function handleSignal(member, data) {
        if (data.length === 0)
            return
        switch (member) {
        case "DeviceSeen":
            // May repeat on every announce; refresh name/visibility only.
            root.patch(String(data[0]), {}, String(data[1]))
            break
        case "Connected":
            root.available = true
            root.patch(String(data[0]), {
                "connected": true,
                "unpairing": false
            })
            break
        case "Disconnected":
            root.patch(String(data[0]), {
                "connected": false,
                "unpairing": false
            })
            root.scheduleRefresh()
            break
        case "PairingRequested":
            root.available = true
            root.patch(String(data[0]), {
                "request": true
            }, String(data[1]))
            // Backend window is 30 s; the matching PairingRejected normally
            // clears the flag first. The timer only drops a request whose
            // signal was missed (daemon restart).
            requestTimeout.restart()
            break
        case "PairingAccepted":
            root.available = true
            root.lastRejectReason = ""
            root.patch(String(data[0]), {
                "paired": true,
                "connected": true,
                "request": false,
                "unpairing": false
            })
            root.queryPlugin(String(data[0]))
            break
        case "PairingRemoved":
            // Unpaired from this desktop (`Unpair`) or another client: drop it
            // from the UI right away, then reconcile.
            root.devices = root.devices.filter(d => d.deviceId !== String(data[0]))
            if (root.pingError !== null && root.pingError.deviceId === String(data[0]))
                root.pingError = null
            root.scheduleRefresh()
            break
        case "PairingRejected":
            root.lastRejectReason = String(data[1])
            root.patch(String(data[0]), {
                "request": false
            })
            // A phone-side unpair arrives as this signal; the table says
            // whether the device is still paired.
            root.scheduleRefresh()
            break
        case "NotificationReceived":
            root.available = true
            root.upsertNotification(data)
            break
        case "NotificationDismissed":
            root.removeNotification(String(data[0]), String(data[1]))
            break
        case "PingReceived":
            // The phone pinged us: surface it (toast + popup history) and let
            // the popup keep the message.
            root.pingReceived(String(data[0]), root.deviceLabelById(String(data[0])), String(data[1]))
            break
        case "PluginStateChanged":
            // Only the ping plugin is shown for now; ignore the rest.
            if (String(data[1]) === "kdeconnect.ping")
                root.setPingEnabled(String(data[0]), data[2] === true)
            break
        }
    }

    // Drop pending requests whose decision signal never arrived.
    function clearRequests() {
        if (root.request === null)
            return
        const list = root.devices.slice()
        for (let i = 0; i < list.length; i++) {
            if (list[i].request)
                list[i] = Object.assign({}, list[i], {
                    "request": false
                })
        }
        root.devices = list
    }

    // A missed `PairingRemoved` (or an old backend without `Unpair`) must not
    // leave the Unpair chip locked forever.
    function clearUnpairing() {
        const list = root.devices.slice()
        let changed = false
        for (let i = 0; i < list.length; i++) {
            if (list[i].unpairing) {
                list[i] = Object.assign({}, list[i], {
                    "unpairing": false
                })
                changed = true
            }
        }
        if (changed)
            root.devices = list
    }

    Component.onCompleted: monitor.running = true

    // Persistent signal subscription. The match rule is on the interface, not
    // the name, so it survives a daemon restart.
    Process {
        id: monitor

        // Two rules: the daemon's signals plus ownership changes of its
        // well-known name (see handleDaemonOwner). The interface rule (not the
        // sender) keeps working across a daemon restart.
        command: ["busctl", "--user", "monitor", "--json=short", "--match", "interface=" + root.iface, "--match", "interface=org.freedesktop.DBus,member=NameOwnerChanged,arg0='" + root.busName + "'"]

        stdout: SplitParser {
            onRead: line => root.handleLine(line)
        }

        // Subscribed: query the current table (see the initial-sync note above).
        onStarted: root.refresh()

        onExited: {
            monitorRetry.restart()
        }
    }

    // busctl dropped (bus restart, command error): retry instead of giving up.
    Timer {
        id: monitorRetry
        interval: 2000

        onTriggered: monitor.running = true
    }

    // 31 s > the backend's 30 s pairing window.
    Timer {
        id: requestTimeout
        interval: 31000

        onTriggered: root.clearRequests()
    }

    // Upper bound for the `PairingRemoved` reply to an `Unpair` call.
    Timer {
        id: unpairTimeout
        interval: 8000

        onTriggered: root.clearUnpairing()
    }

    // Debounce for `scheduleRefresh()`: a burst of link churn collapses into
    // one query.
    Timer {
        id: refreshTimer
        interval: 1500

        onTriggered: root.refresh()
    }

    Process {
        id: devicesProcess

        command: ["busctl", "--user", "--json=short", "call", root.busName, root.objectPath, root.iface, "Devices"]

        stdout: StdioCollector {
            onStreamFinished: root.applyDevices(text)
        }

        onExited: function (exitCode) {
            root.available = exitCode === 0
        }
    }

    Process {
        id: notificationsProcess

        command: ["busctl", "--user", "--json=short", "call", root.busName, root.objectPath, root.iface, "ActiveNotifications"]

        stdout: StdioCollector {
            onStreamFinished: root.applyNotifications(text)
        }

        onExited: function (exitCode) {
            if (exitCode !== 0)
                return
            root.available = true
            root.synced = true
        }
    }

    // `PluginEnabled(id, "kdeconnect.ping")` replies, serialized (one call at a
    // time): `{"type":"b","data":[true]}`.
    Process {
        id: pluginProcess
        property string deviceId: ""

        stdout: StdioCollector {
            onStreamFinished: {
                let value
                try {
                    value = JSON.parse(text).data[0]
                } catch (e) {
                    return
                }
                if (typeof value === "boolean")
                    root.setPingEnabled(pluginProcess.deviceId, value)
            }
        }

        onExited: root.runPluginQuery()
    }

    // `PingDevice` reports "not paired" / "plugin disabled" / "no active
    // channel" as a D-Bus error: keep the message for the popup.
    Process {
        id: pingProcess
        property string deviceId: ""

        stderr: StdioCollector {
            id: pingStderr
        }

        onExited: function (exitCode) {
            if (exitCode === 0)
                return
            let text = String(pingStderr.text || "").trim()
            const prefix = "Call failed: "
            if (text.indexOf(prefix) === 0)
                text = text.slice(prefix.length)
            root.pingError = {
                "deviceId": pingProcess.deviceId,
                "text": text !== "" ? text : "Ping failed"
            }
        }
    }

    Process {
        id: action

        // Failed call (daemon gone, or an older backend without `Unpair`):
        // re-enable the action instead of waiting for the timeout.
        onExited: function (exitCode) {
            if (exitCode !== 0)
                root.clearUnpairing()
        }
    }
}
