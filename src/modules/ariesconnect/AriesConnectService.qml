pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Client for the `aries-connect` daemon (KDE Connect phone bridge) over the
// session bus. Quickshell ships no generic D-Bus client, so this keeps one
// `busctl monitor` process for the signals and fires `busctl call` invocations
// for the methods.
//
// The daemon exposes two kinds of objects (see its doc/dbus.md):
//   - the service object `/dev/zotta/AriesConnect`: pairing prompt, the
//     `Devices()` / `ActiveNotifications()` snapshots and ObjectManager;
//   - one object per known device under `/dev/zotta/AriesConnect/Device/<id>`
//     with `DeviceId`/`DeviceName`/`DeviceType`/`Paired`/`Connected`/`Plugins`
//     properties and the device actions + signals.
// The device table comes from `GetManagedObjects()` (canonical) and is kept
// live with `PropertiesChanged`, `InterfacesAdded`/`InterfacesRemoved` and the
// device signals. Object paths are never built by hand: the daemon sanitizes
// the id for the path, so the raw id comes from the `DeviceId` property.
//
// Snapshots are serialized: one call at a time, table first and notifications
// second, so the table is authoritative before the notification mirror is
// replaced. Both steps are guarded by their own dirty flag (a request made
// while one is in flight is re-run instead of dropped) and by an epoch
// (a reply older than a signal handled meanwhile is discarded, because the
// daemon snapshots it took would undo newer live state).
Singleton {
    id: root

    readonly property string busName: "dev.zotta.AriesConnect"
    readonly property string objectPath: "/dev/zotta/AriesConnect"
    readonly property string iface: "dev.zotta.AriesConnect"
    readonly property string deviceIface: "dev.zotta.AriesConnect.Device"
    readonly property string devicePathPrefix: "/dev/zotta/AriesConnect/Device/"
    readonly property string propertiesIface: "org.freedesktop.DBus.Properties"
    readonly property string objectManagerIface: "org.freedesktop.DBus.ObjectManager"

    // Every device known to the daemon, mirroring its device objects:
    //   { deviceId, path, name, type, paired, connected, request, unpairing,
    //     pingEnabled, clipboardEnabled, plugins, batteryLevel,
    //     lastBatteryLevel, charging, signalType, signalLevel, lastSignalType,
    //     lastSignalLevel }
    // `path` = the object path announced by the daemon ("" while a pairing
    // request arrives for a device whose object is not registered yet),
    // `request` = a pairing request is pending (backend gives it 30 s),
    // `unpairing` = an `Unpair` call is in flight,
    // `pingEnabled` = `Plugins["kdeconnect.ping"]` (the plugin map always lists
    // every implemented plugin, so a missing key means "not implemented"),
    // `clipboardEnabled` = `Plugins["kdeconnect.clipboard"]`,
    // `plugins` = the full `Plugins` map (`a{sb}`) for the settings window;
    // the popup reads the flat flags above, never this nested map,
    // `batteryLevel` = charge 0..100 as currently reported, `-1` when unknown
    // (no report yet, no battery, plugin disabled, unpaired or offline: the
    // daemon drops the cached value when the control channel closes),
    // `lastBatteryLevel` = last reported charge, kept locally so the popup can
    // still show it dimmed while the phone is offline (`-1` when never
    // reported),
    // `charging` = the phone currently reports that it is plugged in,
    // `signalType` = `SignalStrengths` (`a{s(si)}`, connectivity report) of the
    // first subscription (id order): the reported technology (`LTE`, `5G`,
    // `HSPA`...), `""` when unknown; `signalLevel` = its coarse level 0..4
    // (`-1` when unknown). Both are cleared when the plugin is disabled, the
    // device is unpaired or offline; `lastSignalType`/`lastSignalLevel` keep
    // the last report locally so the popup can dim it instead of hiding the
    // indicator (the phone only re-pushes on change).
    property var devices: []

    // A `GetManagedObjects()` call succeeded: the daemon is up on the bus.
    property bool available: false

    // Name the daemon announces to other devices (`DeviceName` on the service
    // object). It defaults to the host name; `SetDeviceName` changes it. Read
    // from the service object (not `GetManagedObjects`, which lists device
    // objects) and keep it live with `PropertiesChanged`.
    property string daemonName: ""

    // Display fallback for the brief window before the first property read.
    readonly property string daemonLabel: root.daemonName !== "" ? root.daemonName : "aries-connect"

    // Last `SetDeviceName` failure ("" = none), shown in the settings window.
    property string deviceNameError: ""

    // First `ActiveNotifications()` reply was applied: later changes are live
    // and get toasted by the notification server (the startup snapshot
    // doesn't).
    property bool synced: false

    // Snapshot pipeline (see the file header). `syncing` = one `busctl call`
    // of the chain is in flight; the dirty flags are consumed when their step
    // starts and set again by any request made while it runs. The epochs are
    // bumped by the live updates the snapshots would overwrite, so a reply
    // that started before them is discarded instead of applied.
    property bool syncing: false
    property bool devicesDirty: false
    property bool notificationsDirty: false
    property int devicesEpoch: 0
    property int notificationsEpoch: 0
    // Identifies the call that owns `syncing`: a timed-out process that is
    // killed and replaced exits later with an old token and must not advance
    // the chain (that would overlap it with the retry).
    property int syncToken: 0
    // Last rejection reason ("" = none), e.g. "rejected or timed out".
    property string lastRejectReason: ""

    // Last action failure: { deviceId, text } or null. `Ping` and
    // `SendClipboard` report unpaired / plugin disabled / no active channel as
    // a D-Bus error; the popup renders it under the row.
    property var actionError: null

    // Last `SetPluginEnabled` failure ("" = none), shown by the settings
    // window. The switch state itself comes from `PropertiesChanged(Plugins)`,
    // not from this call, so a failure only needs the message.
    property string pluginToggleError: ""

    // Whether the global settings window is open. The module is instantiated
    // once per bar (per screen), but settings are not per screen: every gear
    // flips this flag and a single window in shell.qml follows it.
    property bool settingsVisible: false

    // Output that asked for the settings window. The toplevel has no parent
    // window, so this is how it lands on the monitor whose bar was clicked
    // instead of a fixed default. Set before `settingsVisible`.
    property string settingsOutput: ""

    // Local clipboard timestamp (ms) for the `clipboard.connect` handshake:
    // set when this desktop writes the clipboard (our own send or an applied
    // phone update). A `ClipboardReceived` with a phone timestamp older than
    // this must not overwrite the newer local clipboard.
    property double clipboardTimestamp: 0

    // The phone clipboard was written to the local clipboard (toasted). The
    // content is deliberately NOT part of the signal: it must not leak into the
    // notification surface or its persisted history.
    signal clipboardReceived(string deviceId, string name)

    // The phone pinged us (popup/toast surfaces it).
    signal pingReceived(string deviceId, string name, string message)

    // A phone asked to pair (toasted; the popup keeps the decision block).
    // Emitted once per request, not for the repeats of the same id.
    signal pairingRequest(string deviceId, string name)

    // Notifications mirrored from the phones, oldest first (backend order:
    // phone timestamp for `ActiveNotifications()`, reception for signals):
    //   { deviceId, notificationId, appName, title, text }
    // Updated in place by id (Android reuses it); removed on dismiss.
    property var notifications: []

    readonly property int notificationCount: root.notifications.length

    // Pending `DismissNotification` clicks: the call owns one process, so a
    // second click while one is in flight waits instead of overwriting its
    // command (which would silently drop it).
    property var dismissQueue: []

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

    function deviceById(deviceId) {
        for (let i = 0; i < root.devices.length; i++) {
            if (root.devices[i].deviceId === deviceId)
                return root.devices[i]
        }
        return null
    }

    function deviceByPath(path) {
        for (let i = 0; i < root.devices.length; i++) {
            if (root.devices[i].path === path)
                return root.devices[i]
        }
        return null
    }

    function deviceLabelById(deviceId) {
        const dev = root.deviceById(deviceId)
        return dev !== null ? root.deviceLabel(dev) : deviceId
    }

    // Copy-on-write patch of one device; the array is always replaced so
    // bindings reading `devices` re-evaluate. Missing ids are appended, so a
    // signal arriving for an unseen device still lands.
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
            "path": "",
            "name": "",
            "type": "",
            "paired": false,
            "connected": false,
            "request": false,
            "unpairing": false,
            "pingEnabled": false,
            "clipboardEnabled": false,
            "plugins": {},
            "batteryLevel": -1,
            "lastBatteryLevel": -1,
            "charging": false
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

    // Re-read the device table + notifications (popup open / monitor restart).
    // Both are only marked: `pumpSync()` serializes them, table first.
    function refresh() {
        root.devicesDirty = true
        root.notificationsDirty = true
        // The service object's `DeviceName` is not part of the device table.
        deviceNameRead.running = true
        root.pumpSync()
    }

    // Notifications alone (unpair / plugin change: the table itself did not
    // change). The request is never dropped: if a step is in flight this flag
    // makes the chain run again when it finishes.
    function refreshNotifications() {
        root.notificationsDirty = true
        root.pumpSync()
    }

    // One snapshot step at a time: `GetManagedObjects()` before
    // `ActiveNotifications()` (the table is what prunes the mirror).
    function pumpSync() {
        if (root.syncing)
            return
        if (root.devicesDirty) {
            root.devicesDirty = false
            root.syncing = true
            root.syncToken = root.syncToken + 1
            devicesProcess.startEpoch = root.devicesEpoch
            devicesProcess.running = true
            return
        }
        if (root.notificationsDirty) {
            root.notificationsDirty = false
            root.syncing = true
            root.syncToken = root.syncToken + 1
            notificationsProcess.startEpoch = root.notificationsEpoch
            notificationsProcess.running = true
        }
    }

    function snapshotDone() {
        root.syncing = false
        root.pumpSync()
    }

    // Coalesced refresh: used when a signal points at a device object that is
    // not mirrored yet (the ObjectManager says nothing about objects that
    // already existed when its own path was registered).
    function scheduleRefresh() {
        refreshTimer.restart()
    }

    function acceptPairing(deviceId) {
        root.invoke(root.objectPath, root.iface, "AcceptPairing", ["s", deviceId])
    }

    function rejectPairing(deviceId) {
        root.invoke(root.objectPath, root.iface, "RejectPairing", ["s", deviceId])
    }

    // The row disappears when the device emits `NotificationDismissed`. The
    // call itself can fail ("device is not paired", "plugin disabled",
    // "notification is not active"): the error is logged, and an inactive id
    // also drops the local row, because the daemon already discarded it (cap
    // eviction, plugin off, phone-side cancel) and no signal is coming for it.
    function dismissNotification(deviceId, notificationId) {
        const dev = root.deviceById(deviceId)
        if (dev === null || dev.path === "")
            return
        root.dismissQueue = root.dismissQueue.concat([
            {
                "deviceId": deviceId,
                "notificationId": notificationId,
                "path": dev.path
            }
        ])
        root.pumpDismiss()
    }

    // One dismiss call at a time, in click order.
    function pumpDismiss() {
        if (dismissProcess.running || root.dismissQueue.length === 0)
            return
        const next = root.dismissQueue[0]
        root.dismissQueue = root.dismissQueue.slice(1)
        dismissProcess.deviceId = next.deviceId
        dismissProcess.notificationId = next.notificationId
        dismissProcess.command = ["busctl", "--user", "call", root.busName, next.path, root.deviceIface, "DismissNotification", "s", next.notificationId]
        dismissProcess.running = true
    }

    // Forget the pairing. `Unpair()` is a device method; the object stays and
    // only flips `Paired` to false (`PropertiesChanged`), which removes the row
    // from the popup. `unpairing` only locks the button meanwhile.
    function unpair(deviceId) {
        const dev = root.deviceById(deviceId)
        if (dev === null || dev.path === "")
            return
        root.patch(deviceId, {
            "unpairing": true
        })
        // Own process: a second click must not clobber the call in flight (a
        // failed `Unpair` re-enables the button right away).
        unpairProcess.deviceId = deviceId
        unpairProcess.command = ["busctl", "--user", "call", root.busName, dev.path, root.deviceIface, "Unpair"]
        unpairProcess.running = true
        unpairTimeout.restart()
    }

    // Desktop -> phone ping (`Ping(message)` on the device object). Only
    // meaningful when the device is paired, connected and the plugin is on
    // (the popup enforces it); failures are D-Bus errors surfaced in
    // `actionError`.
    function ping(deviceId) {
        const dev = root.deviceById(deviceId)
        if (dev === null || dev.path === "")
            return
        root.actionError = null
        pingProcess.deviceId = deviceId
        pingProcess.command = ["busctl", "--user", "call", root.busName, dev.path, root.deviceIface, "Ping", "s", ""]
        pingProcess.running = true
    }

    // Desktop -> phone "find my phone" (`FindMyPhone()` on the device
    // object). Mirrors `ping`: gated on paired + connected + plugin in the
    // popup; failures are D-Bus errors surfaced in `actionError`.
    function findMyPhone(deviceId) {
        const dev = root.deviceById(deviceId)
        if (dev === null || dev.path === "")
            return
        root.actionError = null
        findMyPhoneProcess.deviceId = deviceId
        findMyPhoneProcess.command = ["busctl", "--user", "call", root.busName, dev.path, root.deviceIface, "FindMyPhone"]
        findMyPhoneProcess.running = true
    }

    // Desktop -> phone clipboard. The daemon only relays packets: the local
    // clipboard is read here with `wl-paste` and sent with `SendClipboard`
    // (text only, empty ignored, backend limit 1 MiB). The button is gated on
    // paired + connected + `kdeconnect.clipboard`.
    function sendClipboard(deviceId) {
        const dev = root.deviceById(deviceId)
        if (dev === null || dev.path === "")
            return
        root.actionError = null
        // Separate process per action: a second click must not clobber the read
        // or the call in flight.
        clipboardRead.deviceId = deviceId
        clipboardRead.command = ["wl-paste", "--no-newline"]
        clipboardRead.running = true
    }

    // Enable/disable one plugin for a device (`SetPluginEnabled(sb)`). The
    // daemon announces the new `Plugins` map with `PropertiesChanged`, and that
    // is what updates the settings switch, so nothing is written optimistically
    // here. The call fails for plugins the daemon does not implement: keep the
    // message for the settings window.
    function setPluginEnabled(deviceId, pluginId, enabled) {
        const dev = root.deviceById(deviceId)
        if (dev === null || dev.path === "")
            return
        root.pluginToggleError = ""
        pluginToggle.deviceId = deviceId
        pluginToggle.pluginId = String(pluginId)
        pluginToggle.command = ["busctl", "--user", "call", root.busName, dev.path, root.deviceIface, "SetPluginEnabled", "sb", String(pluginId), enabled ? "true" : "false"]
        pluginToggle.running = true
    }

    // Change the name the daemon announces (`SetDeviceName s` on the service
    // object). The daemon trims it, rejects names over 128 chars, persists the
    // override and re-announces the identity; the effective value arrives as
    // `PropertiesChanged(DeviceName)`. An empty string resets it to the host
    // name. Nothing is written optimistically here.
    function setDeviceName(name) {
        root.deviceNameError = ""
        deviceNameSet.command = ["busctl", "--user", "call", root.busName, root.objectPath, root.iface, "SetDeviceName", "s", String(name)]
        deviceNameSet.running = true
    }

    // Phone -> desktop clipboard. The daemon emits `ClipboardReceived(content,
    // timestamp)`; the client owns the clipboard, so write it with `wl-copy`.
    // `timestamp` is 0 for regular updates and the phone's clipboard timestamp
    // for `clipboard.connect`: an older handshake must not clobber a newer
    // local clipboard (the daemon does not arbitrate). Returns whether the
    // local clipboard was updated.
    function applyClipboard(content, timestamp) {
        if (content === "")
            return false
        const ts = Number(timestamp)
        if (ts > 0) {
            if (ts <= root.clipboardTimestamp)
                return false
            root.clipboardTimestamp = ts
        }
        clipboardWrite.command = ["wl-copy", "--", content]
        clipboardWrite.running = true
        return true
    }

    // Strip the `Call failed: ` prefix busctl adds to D-Bus errors.
    function callErrorText(text) {
        let message = String(text || "").trim()
        const prefix = "Call failed: "
        if (message.indexOf(prefix) === 0)
            message = message.slice(prefix.length)
        return message
    }

    function invoke(path, ifaceName, method, args) {
        action.command = ["busctl", "--user", "call", root.busName, path, ifaceName, method].concat(args)
        action.running = true
    }

    // Unwrap a `{ Type: { type, data } }` property map into plain values.
    function propValue(props, name) {
        if (props === null || props === undefined)
            return undefined
        const entry = props[name]
        if (entry === null || entry === undefined || typeof entry !== "object")
            return undefined
        return entry.data
    }

    function pluginEnabled(props, plugin) {
        const plugins = root.propValue(props, "Plugins")
        if (plugins === null || plugins === undefined || typeof plugins !== "object")
            return false
        return plugins[plugin] === true
    }

    // Full `Plugins` map (`a{sb}`: plugin id -> enabled) from a property map.
    // Kept on the device entry so the settings window can list every plugin the
    // daemon implements; the popup still reads the flat ping/clipboard flags.
    function pluginsOf(props) {
        const plugins = root.propValue(props, "Plugins")
        if (plugins === null || plugins === undefined || typeof plugins !== "object")
            return {}
        return plugins
    }

    // Display order, labels and glyphs for the plugins the daemon implements
    // today. Anything else found in `Plugins` is appended with its raw id, so a
    // plugin added later still shows up instead of being silently hidden.
    readonly property var pluginLabels: [
        {
            "id": "kdeconnect.notification",
            "label": "Notifications",
            "icon": "\ue07c" // bell
        },
        {
            "id": "kdeconnect.ping",
            "label": "Ping",
            "icon": "\ue091" // megaphone-loud
        },
        {
            "id": "kdeconnect.battery",
            "label": "Battery",
            "icon": "\ue00e" // battery-charge
        },
        {
            "id": "kdeconnect.clipboard",
            "label": "Clipboard",
            "icon": "\ue090" // clipboard
        },
        {
            "id": "kdeconnect.connectivity_report",
            "label": "Connectivity report",
            "icon": "\ue092" // cellular-data-1 (full bars)
        },
        {
            "id": "kdeconnect.findmyphone.request",
            "label": "Find my phone",
            "icon": "\ue098" // call-connecting
        }
    ]

    // Plugin rows for the settings window (`{id, label, icon, enabled}`): a
    // fresh plain array built from the device's `plugins` map. Never hand the
    // nested map to the ListView model: a map read from a delegate arrives as a
    // non-enumerable wrapper, so the rows are materialised here (in the
    // singleton) instead.
    function pluginList(deviceId) {
        const dev = root.deviceById(deviceId)
        if (dev === null)
            return []
        const plugins = dev.plugins !== null && dev.plugins !== undefined && typeof dev.plugins === "object" ? dev.plugins : {}
        const list = []
        const seen = {}
        for (let i = 0; i < root.pluginLabels.length; i++) {
            const entry = root.pluginLabels[i]
            seen[entry.id] = true
            list.push({
                "id": entry.id,
                "label": entry.label,
                "icon": entry.icon,
                "enabled": plugins[entry.id] === true
            })
        }
        for (const id in plugins) {
            if (seen[id] === true)
                continue
            list.push({
                "id": id,
                "label": id,
                "icon": "",
                "enabled": plugins[id] === true
            })
        }
        return list
    }

    // Build one model entry from a device object path + its property map.
    // Local-only state (`request`, `unpairing`) is carried over; a paired
    // device has no pending request and no unpair in flight.
    function deviceFromProps(path, props, previous) {
        const id = root.propValue(props, "DeviceId")
        if (typeof id !== "string" || id === "")
            return null
        const old = previous[id]
        const paired = root.propValue(props, "Paired") === true
        const level = root.propValue(props, "BatteryLevel")
        const current = typeof level === "number" ? level : -1
        const signal = root.signalOf(props)
        return {
            "deviceId": id,
            "path": String(path),
            "name": root.propValue(props, "DeviceName") || "",
            "type": root.propValue(props, "DeviceType") || "",
            "paired": paired,
            "connected": root.propValue(props, "Connected") === true,
            "request": old !== undefined && old.request === true && !paired,
            "unpairing": old !== undefined && old.unpairing === true && paired,
            "pingEnabled": root.pluginEnabled(props, "kdeconnect.ping"),
            "clipboardEnabled": root.pluginEnabled(props, "kdeconnect.clipboard"),
            "findMyPhoneEnabled": root.pluginEnabled(props, "kdeconnect.findmyphone.request"),
            "plugins": root.pluginsOf(props),
            "batteryLevel": current,
            // The daemon drops the level when the phone goes offline: keep the
            // last reported one locally so the popup can dim it instead of
            // hiding the indicator.
            "lastBatteryLevel": current >= 0 ? current : root.lastBatteryOf(old),
            "charging": root.propValue(props, "IsCharging") === true,
            // Primitives on purpose: the popup is a Repeater delegate, and a
            // nested object reaches `modelData` as a non-enumerable wrapper.
            "signalType": signal === null ? "" : signal.type,
            "signalLevel": signal === null ? -1 : signal.level,
            // Last known report, kept across the daemon's clears (disconnect,
            // plugin off): the phone only re-pushes on change, so without this
            // the indicator would stay hidden for minutes after a reconnect.
            "lastSignalType": signal !== null ? signal.type : oldSignalType(old),
            "lastSignalLevel": signal !== null ? signal.level : oldSignalLevel(old)
        }
    }

    function oldSignalType(dev) {
        return dev !== undefined && typeof dev.lastSignalType === "string" ? dev.lastSignalType : ""
    }

    function oldSignalLevel(dev) {
        return dev !== undefined && typeof dev.lastSignalLevel === "number" ? dev.lastSignalLevel : -1
    }

    // `SignalStrengths` (`a{s(si)}`) -> { type, level } of the first
    // subscription (ids are sorted by the daemon), or `null` when the map is
    // absent/empty. busctl renders each struct as `[networkType, level]`.
    function signalOf(props) {
        const map = root.propValue(props, "SignalStrengths")
        if (map === null || map === undefined || typeof map !== "object")
            return null
        for (const id in map) {
            const entry = map[id]
            if (Array.isArray(entry) && entry.length >= 2)
                return {
                    "type": String(entry[0]),
                    "level": Number(entry[1])
                }
        }
        return null
    }

    function lastBatteryOf(dev) {
        if (dev === null || dev === undefined || typeof dev.lastBatteryLevel !== "number")
            return -1
        return dev.lastBatteryLevel
    }

    // Cellular bars for a coarse connectivity level (0..4). `cellular-data-1`
    // is the full five bars, so the level indexes the set reversed. Shared by
    // the popup and the settings window.
    readonly property var signalGlyphs: ["\ue096", "\ue095", "\ue094", "\ue093", "\ue092"]

    function signalGlyph(level) {
        const n = Number(level)
        if (!(n >= 0))
            return ""
        return root.signalGlyphs[Math.max(0, Math.min(4, Math.round(n)))]
    }

    // Coarse generation label next to the bars ("" when the reported
    // technology is unknown). Android reports NR for 5G.
    function signalLabel(type) {
        const name = String(type || "").toUpperCase()
        if (name === "" || name.indexOf("UNKNOWN") !== -1)
            return ""
        if (name.indexOf("5G") !== -1 || name === "NR" || name === "NRNSA")
            return "5G"
        if (name.indexOf("LTE") !== -1 || name.indexOf("4G") !== -1)
            return "4G"
        if (name.indexOf("HSPA") !== -1 || name.indexOf("UMTS") !== -1 || name.indexOf("EVDO") !== -1)
            return "3G"
        if (name.indexOf("EDGE") !== -1 || name.indexOf("GPRS") !== -1 || name === "GSM" || name === "CDMA")
            return "2G"
        return ""
    }

    // `a{oa{sa{sv}}}` reply: data[0] = { "<path>": { "<iface>": { "<prop>":
    // { type, data } } } }. The reply is authoritative: a device missing from
    // it was forgotten (daemon restart with an empty trust store) and must be
    // dropped. Only pending pairing requests survive from local state (they are
    // signal-only and may arrive before the object exists).
    function applyManagedObjects(text) {
        let objects
        try {
            objects = JSON.parse(text).data[0]
        } catch (e) {
            return
        }
        if (objects === null || typeof objects !== "object")
            return
        const previous = {}
        for (let i = 0; i < root.devices.length; i++)
            previous[root.devices[i].deviceId] = root.devices[i]

        const list = []
        for (const path in objects) {
            const ifaces = objects[path]
            if (ifaces === null || typeof ifaces !== "object")
                continue
            const props = ifaces[root.deviceIface]
            if (props === undefined || props === null || typeof props !== "object")
                continue
            const dev = root.deviceFromProps(path, props, previous)
            if (dev !== null)
                list.push(dev)
        }
        for (let i = 0; i < root.devices.length; i++) {
            const old = root.devices[i]
            if (old.request !== true || root.deviceByIdIn(list, old.deviceId) !== null)
                continue
            list.push(Object.assign({}, old))
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
    }

    function deviceByIdIn(list, deviceId) {
        for (let i = 0; i < list.length; i++) {
            if (list[i].deviceId === deviceId)
                return list[i]
        }
        return null
    }

    // `a(sssss)` reply: data[0] = [[deviceId, notificationId, appName,
    // title, text], ...]. Authoritative snapshot: replaces the mirror. Rows of
    // devices missing from the table are skipped (the table was applied just
    // before, so they cannot belong to a live device). Returns false when the
    // reply could not be used, so the caller keeps `synced` off.
    function applyNotifications(text) {
        let rows
        try {
            rows = JSON.parse(text).data[0]
        } catch (e) {
            return false
        }
        if (!Array.isArray(rows))
            return false
        const known = {}
        for (let i = 0; i < root.devices.length; i++)
            known[root.devices[i].deviceId] = true
        const list = []
        for (let r = 0; r < rows.length; r++) {
            const row = rows[r]
            if (!Array.isArray(row) || row.length < 5)
                continue
            if (known[String(row[0])] !== true)
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
        return true
    }

    // `NotificationReceived(id, appName, title, text)` on a device object.
    // Updates reuse the same id: replace by (deviceId, notificationId) instead
    // of duplicating; new ones append in reception order.
    function upsertNotification(deviceId, data) {
        if (data.length < 4)
            return
        const entry = {
            "deviceId": deviceId,
            "notificationId": String(data[0]),
            "appName": String(data[1]),
            "title": String(data[2]),
            "text": String(data[3])
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

    // One `busctl monitor --json=short` line (a D-Bus message, not necessarily
    // a signal: our own calls and replies are matched too).
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
        const path = String(msg.path || "")
        const data = msg.payload !== null && msg.payload !== undefined && Array.isArray(msg.payload.data) ? msg.payload.data : []

        // The daemon coming or going is invisible on its own interfaces, so
        // the well-known name is watched too: a restart must not leave the old
        // table on screen.
        if (msg.interface === "org.freedesktop.DBus" && msg.member === "NameOwnerChanged") {
            if (data.length >= 3 && String(data[0]) === root.busName)
                root.handleDaemonOwner(String(data[2]))
            return
        }

        // Everything else must come from the daemon's object subtree (the
        // Properties and ObjectManager match rules are session-wide).
        if (path !== root.objectPath && path.indexOf(root.devicePathPrefix) !== 0)
            return
        if (path === root.objectPath) {
            if (msg.interface === root.iface)
                root.handleServiceSignal(msg.member, data)
            else if (msg.interface === root.objectManagerIface)
                root.handleObjectManager(msg.member, data)
            else if (msg.interface === root.propertiesIface && msg.member === "PropertiesChanged")
                root.handleServicePropertiesChanged(data)
            return
        }

        if (msg.interface === root.propertiesIface && msg.member === "PropertiesChanged")
            root.handlePropertiesChanged(path, data)
        else if (msg.interface === root.deviceIface)
            root.handleDeviceSignal(path, msg.member, data)
    }

    // `newOwner` is empty when the daemon left the session bus. A restarting
    // daemon starts with an empty trust store, so the mirror is dropped and
    // rebuilt from the next initial sync.
    function handleDaemonOwner(newOwner) {
        root.synced = false
        root.lastRejectReason = ""
        root.devices = []
        root.notifications = []
        root.actionError = null
        root.clipboardTimestamp = 0
        // Clicks aimed at the previous owner are meaningless now.
        root.dismissQueue = []
        // Snapshots started against the previous owner are worthless now.
        root.devicesEpoch = root.devicesEpoch + 1
        root.notificationsEpoch = root.notificationsEpoch + 1
        requestTimeout.stop()
        unpairTimeout.stop()
        if (newOwner === "") {
            root.available = false
            root.devicesDirty = false
            root.notificationsDirty = false
            return
        }
        root.refresh()
    }

    // Service object signals: the pairing prompt is service-wide.
    function handleServiceSignal(member, data) {
        switch (member) {
        case "PairingRequested":
            if (data.length < 2)
                return
            root.available = true
            const known = root.deviceById(String(data[0]))
            const isNew = known === null || known.request !== true
            root.patch(String(data[0]), {
                "request": true
            }, String(data[1]))
            // Backend window is 30 s; a decision shows up as `Paired` on the
            // device object (accept) or as `PairingRejected`. The timer only
            // drops a request whose outcome signal was missed.
            requestTimeout.restart()
            // One toast per request: the daemon may repeat the signal.
            if (isNew)
                root.pairingRequest(String(data[0]), String(data[1]))
            break
        case "PairingRejected":
            root.lastRejectReason = data.length > 1 ? String(data[1]) : ""
            root.patch(String(data[0]), {
                "request": false
            })
            break
        }
    }

    // `PropertiesChanged(iface, changed, invalidated)` on the service object.
    // Today it only carries `DeviceName` (the name announced to peers).
    function handleServicePropertiesChanged(data) {
        if (data.length < 2 || String(data[0]) !== root.iface)
            return
        const changed = data[1]
        if (changed === null || typeof changed !== "object")
            return
        if ("DeviceName" in changed) {
            const name = root.propValue(changed, "DeviceName")
            root.daemonName = typeof name === "string" ? name : ""
            root.deviceNameError = ""
        }
    }

    // ObjectManager on the service path: devices appear and disappear with
    // their object (registration is automatic for discovered devices).
    function handleObjectManager(member, data) {
        if (member === "InterfacesAdded") {
            if (data.length < 2)
                return
            const path = String(data[0])
            const ifaces = data[1]
            if (ifaces === null || typeof ifaces !== "object")
                return
            const props = ifaces[root.deviceIface]
            if (props === undefined || props === null || typeof props !== "object")
                return
            // A table snapshot in flight may predate this object: discard it
            // instead of dropping the device.
            root.devicesEpoch = root.devicesEpoch + 1
            const previous = {}
            for (let i = 0; i < root.devices.length; i++)
                previous[root.devices[i].deviceId] = root.devices[i]
            const dev = root.deviceFromProps(path, props, previous)
            if (dev === null)
                return
            const list = root.devices.filter(d => d.deviceId !== dev.deviceId)
            list.push(dev)
            root.devices = list
            return
        }
        if (member === "InterfacesRemoved") {
            if (data.length < 2 || !Array.isArray(data[1]) || data[1].indexOf(root.deviceIface) === -1)
                return
            const dev = root.deviceByPath(String(data[0]))
            if (dev === null)
                return
            root.devicesEpoch = root.devicesEpoch + 1
            root.notificationsEpoch = root.notificationsEpoch + 1
            root.devices = root.devices.filter(d => d.deviceId !== dev.deviceId)
            root.notifications = root.notifications.filter(n => n.deviceId !== dev.deviceId)
        }
    }

    // `PropertiesChanged(iface, changed, invalidated)` on a device object.
    function handlePropertiesChanged(path, data) {
        if (data.length < 2 || String(data[0]) !== root.deviceIface)
            return
        const changed = data[1]
        if (changed === null || typeof changed !== "object")
            return
        const dev = root.deviceByPath(path)
        if (dev === null) {
            // Device object registered before our last sync (or before the
            // monitor started): re-read the table.
            root.scheduleRefresh()
            return
        }

        const fields = {}
        // Any live property change makes a table snapshot in flight stale.
        root.devicesEpoch = root.devicesEpoch + 1
        if ("DeviceName" in changed)
            fields.name = root.propValue(changed, "DeviceName") || ""
        if ("DeviceType" in changed)
            fields.type = root.propValue(changed, "DeviceType") || ""
        if ("Connected" in changed)
            fields.connected = root.propValue(changed, "Connected") === true
        // Charge as currently reported (the daemon clears it when the phone
        // goes offline) and the phone's charging state. The last reported level
        // is kept locally for the dimmed stale display.
        if ("BatteryLevel" in changed) {
            const level = root.propValue(changed, "BatteryLevel")
            const current = typeof level === "number" ? level : -1
            fields.batteryLevel = current
            if (current >= 0)
                fields.lastBatteryLevel = current
        }
        if ("IsCharging" in changed)
            fields.charging = root.propValue(changed, "IsCharging") === true
        // Connectivity report: the daemon announces and clears the map here
        // (new report, disconnect, unpair, plugin toggled).
        if ("SignalStrengths" in changed) {
            const signal = root.signalOf(changed)
            fields.signalType = signal === null ? "" : signal.type
            fields.signalLevel = signal === null ? -1 : signal.level
            // A clear keeps the cache; a new report refreshes it.
            if (signal !== null) {
                fields.lastSignalType = signal.type
                fields.lastSignalLevel = signal.level
            }
        }
        if ("Paired" in changed) {
            const paired = root.propValue(changed, "Paired") === true
            fields.paired = paired
            fields.unpairing = false
            if (paired)
                fields.request = false
            else {
                // The daemon resets the battery when the device is unpaired;
                // don't keep a value from the old pairing around.
                fields.batteryLevel = -1
                fields.lastBatteryLevel = -1
                fields.charging = false
                fields.signalType = ""
                fields.signalLevel = -1
                fields.lastSignalType = ""
                fields.lastSignalLevel = -1
                if (root.actionError !== null && root.actionError.deviceId === dev.deviceId)
                    root.actionError = null
            }
            // The daemon drops an unpaired device's notifications: a snapshot
            // in flight may still carry them.
            root.notificationsEpoch = root.notificationsEpoch + 1
            root.refreshNotifications()
        }
        if ("Plugins" in changed) {
            fields.pingEnabled = root.pluginEnabled(changed, "kdeconnect.ping")
            fields.clipboardEnabled = root.pluginEnabled(changed, "kdeconnect.clipboard")
            fields.findMyPhoneEnabled = root.pluginEnabled(changed, "kdeconnect.findmyphone.request")
            // Full map for the settings window: the switch that triggered
            // `SetPluginEnabled` updates from this change, never optimistically.
            fields.plugins = root.pluginsOf(changed)
            // Notifications may have been dropped (plugin disabled).
            root.notificationsEpoch = root.notificationsEpoch + 1
            root.refreshNotifications()
        }
        root.patch(dev.deviceId, fields)
    }

    // Device object signals; the device id comes from the path.
    function handleDeviceSignal(path, member, data) {
        const dev = root.deviceByPath(path)
        if (dev === null) {
            root.scheduleRefresh()
            return
        }
        switch (member) {
        case "PingReceived":
            // The phone pinged us: surface it (toast + popup history) and let
            // the popup keep the message.
            root.pingReceived(dev.deviceId, root.deviceLabel(dev), data.length > 0 ? String(data[0]) : "")
            break
        case "ClipboardReceived":
            // The phone clipboard changed: write it to the local clipboard and
            // toast it (without the copied text) only when it was applied.
            if (root.applyClipboard(data.length > 0 ? String(data[0]) : "", data.length > 1 ? data[1] : 0))
                root.clipboardReceived(dev.deviceId, root.deviceLabel(dev))
            break
        case "NotificationReceived":
            root.notificationsEpoch = root.notificationsEpoch + 1
            root.upsertNotification(dev.deviceId, data)
            break
        case "NotificationDismissed":
            root.notificationsEpoch = root.notificationsEpoch + 1
            root.removeNotification(dev.deviceId, data.length > 0 ? String(data[0]) : "")
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

    // A missed `Paired` change (or a failed call) must not leave the Unpair
    // button locked forever.
    function clearUnpairing(deviceId) {
        const list = root.devices.slice()
        let changed = false
        for (let i = 0; i < list.length; i++) {
            if (!list[i].unpairing)
                continue
            if (deviceId !== undefined && deviceId !== "" && list[i].deviceId !== deviceId)
                continue
            list[i] = Object.assign({}, list[i], {
                "unpairing": false
            })
            changed = true
        }
        if (changed)
            root.devices = list
    }

    Component.onCompleted: monitor.running = true

    // Persistent signal subscription. The match rules are on interfaces /
    // paths, not on the sender, so they survive a daemon restart.
    Process {
        id: monitor

        // Service signals + device signals + property/object changes in the
        // service subtree + ownership changes of the well-known name (see
        // handleDaemonOwner). `path_namespace` keeps session-wide
        // PropertiesChanged traffic out of the stream.
        command: ["busctl", "--user", "monitor", "--json=short", "--match", "interface=" + root.iface, "--match", "interface=" + root.deviceIface, "--match", "interface=" + root.propertiesIface + ",path_namespace=" + root.objectPath, "--match", "interface=" + root.objectManagerIface, "--match", "interface=org.freedesktop.DBus,member=NameOwnerChanged,arg0='" + root.busName + "'"]

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

    // Upper bound for the `Paired` change answering an `Unpair` call.
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

    // `a{oa{sa{sv}}}`: the canonical device table (paths + properties). The
    // reply is applied in `onExited`: `StdioCollector` ends its stream before
    // Quickshell emits `exited`, so the text is complete there.
    Process {
        id: devicesProcess
        property int startEpoch: 0
        property int startToken: 0

        command: ["busctl", "--user", "--json=short", "call", root.busName, root.objectPath, root.objectManagerIface, "GetManagedObjects"]

        stdout: StdioCollector {
            id: devicesOut
        }

        // The token is taken when the process really starts, not when it is
        // requested: a restart requested while a timed-out process is still
        // terminating starts afterwards, and the old exit must not match.
        onStarted: devicesProcess.startToken = root.syncToken

        onExited: function (exitCode) {
            // Replaced after a timeout: this exit belongs to no step anymore.
            if (devicesProcess.startToken !== root.syncToken)
                return
            if (exitCode === 0) {
                root.available = true
                // A signal handled while the call was in flight is newer than
                // this reply, so applying the table would undo it: re-run.
                if (devicesProcess.startEpoch === root.devicesEpoch)
                    root.applyManagedObjects(devicesOut.text)
                else
                    root.devicesDirty = true
            } else {
                // No retry (a dead daemon would spin): the monitor restart and
                // the next owner change ask for the sync again.
                root.available = false
            }
            root.snapshotDone()
        }
    }

    Process {
        id: notificationsProcess
        property int startEpoch: 0
        property int startToken: 0

        command: ["busctl", "--user", "--json=short", "call", root.busName, root.objectPath, root.iface, "ActiveNotifications"]

        stdout: StdioCollector {
            id: notificationsOut
        }

        onStarted: notificationsProcess.startToken = root.syncToken

        onExited: function (exitCode) {
            if (notificationsProcess.startToken !== root.syncToken)
                return
            if (exitCode !== 0) {
                root.snapshotDone()
                return
            }
            root.available = true
            if (notificationsProcess.startEpoch !== root.notificationsEpoch) {
                // Older than the live updates already applied: discard it (it
                // would resurrect a dismissed notification or drop a new one)
                // and ask for a fresh one.
                root.notificationsDirty = true
            } else if (root.applyNotifications(notificationsOut.text)) {
                // Only an applied snapshot counts as the initial one: a
                // discarded reply must not make the re-run toast as live.
                root.synced = true
            }
            root.snapshotDone()
        }
    }

    // A call that never reports an exit (busctl missing: a QProcess start
    // failure emits no `finished`) must not block the chain forever. The token
    // bump makes the killed process exit irrelevant; if nothing ever started
    // (no exit at all) the retry is simply attempted again on the next tick.
    Timer {
        interval: 15000
        running: root.syncing

        onTriggered: {
            console.warn("ariesconnect: snapshot timed out, retrying")
            devicesProcess.running = false
            notificationsProcess.running = false
            root.syncing = false
            // The retry bumps `syncToken`, which invalidates the killed call.
            root.refresh()
        }
    }

    // `DismissNotification` fails for unpaired devices, inactive notifications
    // and a disabled plugin. Failures are not part of `actionError`: the row
    // is the feedback and the signal removes it. An inactive id is dropped
    // locally instead (the daemon already discarded it, so its
    // `NotificationDismissed` was sent before the click and will not repeat).
    Process {
        id: dismissProcess
        property string deviceId: ""
        property string notificationId: ""

        stderr: StdioCollector {
            id: dismissStderr
        }

        onExited: function (exitCode) {
            if (exitCode !== 0) {
                const text = root.callErrorText(dismissStderr.text)
                if (text.indexOf("is not active") !== -1)
                    root.removeNotification(dismissProcess.deviceId, dismissProcess.notificationId)
                console.warn("ariesconnect: dismiss failed: " + (text !== "" ? text : "unknown error"))
            }
            // Deferred: the next call must not start while this QProcess is
            // still being torn down.
            Qt.callLater(root.pumpDismiss)
        }
    }

    // `Ping` reports "not paired" / "plugin disabled" / "no active channel" as
    // a D-Bus error: keep the message for the popup.
    Process {
        id: pingProcess
        property string deviceId: ""

        stderr: StdioCollector {
            id: pingStderr
        }

        onExited: function (exitCode) {
            if (exitCode === 0)
                return
            const text = root.callErrorText(pingStderr.text)
            root.actionError = {
                "deviceId": pingProcess.deviceId,
                "text": text !== "" ? text : "Ping failed"
            }
        }
    }

    // `FindMyPhone` fails for unpaired/disabled/offline devices; the D-Bus
    // error is surfaced in `actionError` (mirrors `Ping`).
    Process {
        id: findMyPhoneProcess
        property string deviceId: ""

        stderr: StdioCollector {
            id: findMyPhoneStderr
        }

        onExited: function (exitCode) {
            if (exitCode === 0)
                return
            const text = root.callErrorText(findMyPhoneStderr.text)
            root.actionError = {
                "deviceId": findMyPhoneProcess.deviceId,
                "text": text !== "" ? text : "Find my phone failed"
            }
        }
    }

    // Local clipboard read for `sendClipboard()`. `wl-paste` exits non-zero
    // with "Nothing is copied" when the selection has no text; that is not an
    // error worth surfacing, the row simply stays unchanged.
    Process {
        id: clipboardRead
        property string deviceId: ""

        stdout: StdioCollector {
            id: clipboardReadOut
        }

        onExited: function (exitCode) {
            if (exitCode !== 0)
                return
            // `--no-newline`: the text is sent exactly as copied.
            const text = String(clipboardReadOut.text || "")
            if (text === "")
                return
            const dev = root.deviceById(clipboardRead.deviceId)
            if (dev === null || dev.path === "")
                return
            root.clipboardTimestamp = Date.now()
            clipboardSend.deviceId = dev.deviceId
            // `--` before `call`: clipboard text may start with `-`, which
            // busctl would otherwise parse as an option.
            clipboardSend.command = ["busctl", "--user", "--", "call", root.busName, dev.path, root.deviceIface, "SendClipboard", "s", text]
            clipboardSend.running = true
        }
    }

    // `SendClipboard` fails for unpaired/disabled/offline devices or text over
    // 1 MiB: same error surface as `Ping`.
    Process {
        id: clipboardSend
        property string deviceId: ""

        stderr: StdioCollector {
            id: clipboardSendStderr
        }

        onExited: function (exitCode) {
            if (exitCode === 0)
                return
            const text = root.callErrorText(clipboardSendStderr.text)
            root.actionError = {
                "deviceId": clipboardSend.deviceId,
                "text": text !== "" ? text : "Clipboard send failed"
            }
        }
    }

    // Phone clipboard -> local clipboard. `wl-copy` forks and serves the
    // selection in the background, so the process exits immediately.
    Process {
        id: clipboardWrite

        onExited: function (exitCode) {
            if (exitCode !== 0)
                console.warn("ariesconnect: wl-copy failed, clipboard not updated")
        }
    }

    // `Unpair` answers with a `Paired` change, not a reply: a failed call
    // (daemon gone, unknown object) re-enables the button instead of waiting
    // for the timeout.
    Process {
        id: unpairProcess
        property string deviceId: ""

        onExited: function (exitCode) {
            if (exitCode !== 0)
                root.clearUnpairing(unpairProcess.deviceId)
        }
    }

    // `SetPluginEnabled` fails for plugins the daemon does not implement; the
    // switch itself updates from `PropertiesChanged(Plugins)`, so a failure
    // only needs the D-Bus message.
    Process {
        id: pluginToggle
        property string deviceId: ""
        property string pluginId: ""

        stderr: StdioCollector {
            id: pluginToggleStderr
        }

        onExited: function (exitCode) {
            if (exitCode === 0)
                return
            const text = root.callErrorText(pluginToggleStderr.text)
            root.pluginToggleError = text !== "" ? text : "Could not change the plugin state"
        }
    }

    // `DeviceName` lives on the service object, so it is not part of the
    // `GetManagedObjects()` table: read it with `Properties.Get` whenever the
    // shell syncs. busctl's JSON wraps the returned variant as
    // `{"type":"v","data":[{"type":"s","data":"<name>"}]}`.
    Process {
        id: deviceNameRead

        command: ["busctl", "--user", "--json=short", "call", root.busName, root.objectPath, root.propertiesIface, "Get", "ss", root.iface, "DeviceName"]

        stdout: StdioCollector {
            id: deviceNameReadOut
        }

        onExited: function (exitCode) {
            if (exitCode !== 0)
                return
            let reply
            try {
                reply = JSON.parse(deviceNameReadOut.text)
            } catch (e) {
                return
            }
            const data = reply.data
            if (typeof data === "string")
                root.daemonName = data
            else if (Array.isArray(data) && data.length > 0 && data[0] !== null && typeof data[0] === "object" && typeof data[0].data === "string")
                root.daemonName = data[0].data
        }
    }

    // `SetDeviceName` fails for names over 128 characters (and for a failed
    // persist); the effective value still arrives through `PropertiesChanged`.
    Process {
        id: deviceNameSet

        stderr: StdioCollector {
            id: deviceNameSetStderr
        }

        onExited: function (exitCode) {
            if (exitCode === 0)
                return
            const text = root.callErrorText(deviceNameSetStderr.text)
            root.deviceNameError = text !== "" ? text : "Could not change the device name"
        }
    }

    Process {
        id: action
    }
}
