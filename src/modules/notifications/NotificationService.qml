pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "../config"

// Notification backend: the single org.freedesktop.Notifications server for the
// whole shell, plus the in-memory history and its on-disk cache.
//
// Design notes:
//  * One server instance only. A singleton guarantees a single D-Bus name owner
//    no matter how many surfaces (toasts, bar badge, history popup) read it.
//  * `entries` is the persistent history, newest first. Each entry is a
//    NotificationEntry QtObject holding a *snapshot* of the notification fields,
//    so the record stays valid after the live server object is destroyed.
//  * The live Notification is kept alive only while a toast is on screen
//    (`tracked = true`); once hidden the snapshot remains and the server object
//    is dismissed to free memory.
//  * Persistence is debounced and capped; no polling anywhere.
Singleton {
    id: root

    readonly property var cfg: Config.settings.modules.notifications
    readonly property int maxVisible: root.cfg.maxVisible
    readonly property int maxHistory: root.cfg.maxHistory
    readonly property bool persistEnabled: root.cfg.persist

    // History, newest first. Items are NotificationEntry objects.
    property var entries: []
    // Bumped whenever an entry's non-model property changes (popup, unread...),
    // so bindings reading those properties re-evaluate.
    property int revision: 0

    // Number of notifications received since the history was last opened.
    property int unread: 0

    // True while any unread entry is critical. Derived from the per-entry
    // `unread` flag so it clears the moment the entry is read or removed.
    readonly property bool unreadCritical: {
        root.revision
        for (let i = 0; i < root.entries.length; i++) {
            const e = root.entries[i]
            if (e.unread && e.urgency === NotificationUrgency.Critical)
                return true
        }
        return false
    }

    // True once the on-disk cache has been read (or confirmed absent).
    property bool loaded: false

    // Do Not Disturb, sourced from the user config (live-updating).
    readonly property bool dnd: Config.settings.modules.notifications.dnd

    // Toasts currently on screen, newest first.
    readonly property var popups: {
        root.revision
        return root.entries.filter(e => e.popup)
    }

    // ---------------------------------------------------------------- paths
    readonly property string cacheDir: {
        const xdg = Quickshell.env("XDG_CACHE_HOME")
        const home = Quickshell.env("HOME")
        const base = xdg ? ("" + xdg) : ((home ? "" + home : "") + "/.cache")
        return base + "/aries"
    }
    readonly property string historyPath: root.cacheDir + "/notifications.json"

    // Maps a live server notification id to its entry id. Persisted entries have
    // no server object, so they are absent here.
    property var byServerId: ({})
    // Monotonic local id generator (avoids clashing with server ids on reload).
    property int entrySeq: 0

    // ------------------------------------------------------------------ API
    function bump() {
        root.revision++
    }

    function entryById(id) {
        for (let i = 0; i < root.entries.length; i++) {
            if (root.entries[i].entryId === id)
                return root.entries[i]
        }
        return null
    }

    function markRead() {
        let changed = root.unread !== 0
        for (let i = 0; i < root.entries.length; i++) {
            if (root.entries[i].unread) {
                root.entries[i].unread = false
                changed = true
            }
        }
        if (changed) {
            root.unread = 0
            root.bump()
        }
    }

    // Compact relative timestamp ("now", "5m", "3h", "2d").
    function formatTime(ts) {
        const diff = Date.now() - ts
        const m = Math.floor(diff / 60000)
        if (m < 1)
            return "now"
        if (m < 60)
            return m + "m"
        const h = Math.floor(m / 60)
        if (h < 24)
            return h + "h"
        return Math.floor(h / 24) + "d"
    }

    function setDnd(value) {
        if (root.dnd === value)
            return
        Config.update(s => { s.modules.notifications.dnd = value })
        Config.save()
        root.bump()
    }

    function toggleDnd() {
        root.setDnd(!root.dnd)
    }

    // Hide a toast but keep the record in history.
    function dismissEntry(id) {
        const entry = root.entryById(id)
        if (entry === null)
            return
        if (entry.isTransient) {
            root.removeEntry(id)
            return
        }
        root._hideEntry(entry)
        root.schedulePersist()
        root.bump()
    }

    // Auto-expire a toast (timer fired).
    function timeoutEntry(id) {
        const entry = root.entryById(id)
        if (entry === null)
            return
        if (entry.isTransient) {
            root.removeEntry(id)
            return
        }
        root._hideEntry(entry)
        root.schedulePersist()
        root.bump()
    }

    // Permanently delete an entry from history (and dismiss it server-side).
    function removeEntry(id) {
        const entry = root.entryById(id)
        if (entry === null)
            return
        // Detach from the model before dismissing so the Retainable.dropped
        // handler sees the entry as gone and does not recurse.
        root._stopTimer(entry)
        root.entries = root.entries.filter(e => e.entryId !== id)
        root._untrack(entry)
        if (entry.notification)
            entry.notification.dismiss()
        entry.destroy()
        root.schedulePersist()
        root.bump()
    }

    function clearHistory() {
        const list = root.entries.slice()
        root.entries = []
        root.byServerId = ({})
        for (let i = 0; i < list.length; i++) {
            const e = list[i]
            root._stopTimer(e)
            if (e.notification)
                e.notification.dismiss()
            e.destroy()
        }
        root.schedulePersist()
        root.bump()
    }

    // Hover pause for a toast (dunst-style: hovering holds the notification).
    function pauseEntry(id) {
        const entry = root.entryById(id)
        if (entry !== null && entry.timer)
            entry.timer.stop()
    }

    function resumeEntry(id) {
        const entry = root.entryById(id)
        if (entry !== null && entry.popup && entry.timer)
            entry.timer.restart()
    }

    // Invoke an action button on a live toast, then hide it.
    function invokeAction(id, identifier) {
        const entry = root.entryById(id)
        if (entry === null)
            return
        if (entry.notification) {
            const acts = entry.notification.actions || []
            for (let i = 0; i < acts.length; i++) {
                if (acts[i].identifier === identifier) {
                    acts[i].invoke()
                    break
                }
            }
        }
        root.dismissEntry(id)
    }

    // ------------------------------------------------------- server handler
    function handleNotification(notification) {
        const sid = notification.id
        let entry = null
        if (root.byServerId[sid] !== undefined)
            entry = root.entryById(root.byServerId[sid])

        if (entry === null) {
            entry = entryComp.createObject(root, {
                entryId: ++root.entrySeq,
                time: Date.now(),
            })
            root.byServerId[sid] = entry.entryId
            root.entries = [entry].concat(root.entries)
        } else {
            entry.time = Date.now()
            root._moveToTop(entry)
        }

        entry.notification = notification
        entry.isTransient = notification.hints ? (notification.hints.transient === true) : false
        entry.appName = notification.appName || ""
        entry.appIcon = notification.appIcon || ""
        entry.image = notification.image || ""
        entry.summary = notification.summary || ""
        entry.body = notification.body || ""
        entry.desktopEntry = notification.desktopEntry || ""
        entry.urgency = notification.urgency
        entry.actions = root._actionsOf(notification)
        // A (re)delivered notification is unread again.
        entry.unread = true

        if (!root.dnd) {
            // Keep the live object alive while it is on screen.
            notification.tracked = true
            entry.popup = true
            root._startTimer(entry, notification.expireTimeout)
        } else {
            // Do Not Disturb: only the snapshot is kept. Leaving the live object
            // untracked lets the server release it immediately.
            entry.popup = false
        }

        root._enforceVisible()
        root.unread = root.unread + 1
        root._trimHistory()
        root.schedulePersist()
        root.bump()
    }

    // Called by an entry's Retainable connection when the server drops it
    // (client closed it, or we dismissed it).
    function onEntryDropped(entry) {
        if (root.entryById(entry.entryId) === null)
            return
        root._untrack(entry)
        if (entry.isTransient) {
            root.removeEntry(entry.entryId)
            return
        }
        if (entry.popup) {
            root._stopTimer(entry)
            entry.popup = false
        }
        root.schedulePersist()
        root.bump()
    }

    // -------------------------------------------------------- internal helpers
    function _actionsOf(notification) {
        const out = []
        const acts = notification.actions || []
        for (let i = 0; i < acts.length; i++)
            out.push({ identifier: acts[i].identifier, text: acts[i].text })
        return out
    }

    function _moveToTop(entry) {
        const next = root.entries.filter(e => e.entryId !== entry.entryId)
        next.unshift(entry)
        root.entries = next
    }

    function _untrack(entry) {
        if (entry.notification) {
            const sid = entry.notification.id
            if (root.byServerId[sid] === entry.entryId)
                delete root.byServerId[sid]
        }
    }

    function _hideEntry(entry) {
        root._stopTimer(entry)
        entry.popup = false
        if (entry.notification) {
            root._untrack(entry)
            entry.notification.dismiss()
        }
    }

    function _timeoutFor(urgency) {
        const t = root.cfg.timeout
        if (urgency === NotificationUrgency.Low)
            return t.low
        if (urgency === NotificationUrgency.Critical)
            return t.critical
        return t.normal
    }

    // `expireTimeout`: -1 = server decides (per urgency), 0 = never, >0 = client.
    function _startTimer(entry, expireTimeout) {
        root._stopTimer(entry)
        let interval = 0
        if (expireTimeout === 0)
            interval = 0
        else if (expireTimeout > 0)
            interval = expireTimeout
        else
            interval = root._timeoutFor(entry.urgency)
        if (interval <= 0)
            return
        entry.timer = timerComp.createObject(root, {
            entryId: entry.entryId,
            interval: interval,
        })
    }

    function _stopTimer(entry) {
        if (entry.timer) {
            entry.timer.stop()
            entry.timer.destroy()
            entry.timer = null
        }
    }

    // Keep the visible stack bounded: the oldest toasts slide out (their record
    // stays in history).
    function _enforceVisible() {
        const shown = root.entries.filter(e => e.popup)
        for (let i = root.maxVisible; i < shown.length; i++)
            root._hideEntry(shown[i])
    }

    function _trimHistory() {
        if (root.entries.length <= root.maxHistory)
            return
        const kept = root.entries.slice(0, root.maxHistory)
        const dropped = root.entries.slice(root.maxHistory)
        root.entries = kept
        for (let i = 0; i < dropped.length; i++) {
            const e = dropped[i]
            root._stopTimer(e)
            if (e.notification)
                e.notification.dismiss()
            e.destroy()
        }
    }

    // ---------------------------------------------------------- persistence
    function schedulePersist() {
        if (!root.persistEnabled || !root.loaded)
            return
        persistTimer.restart()
    }

    function writeHistory() {
        if (!root.loaded)
            return
        const data = []
        const list = root.entries.filter(e => !e.isTransient)
        for (let i = 0; i < list.length && i < root.maxHistory; i++)
            data.push(root._toJSON(list[i]))
        historyFile.setText(JSON.stringify(data, null, 2))
    }

    function _toJSON(entry) {
        return {
            appName: entry.appName,
            appIcon: entry.appIcon,
            // Inline image-data URLs (image://qsimage/<id>) use a per-process
            // sequential id and cannot be restored, so don't persist them.
            image: entry.image.startsWith("image://qsimage/") ? "" : entry.image,
            summary: entry.summary,
            body: entry.body,
            desktopEntry: entry.desktopEntry,
            urgency: entry.urgency,
            time: entry.time,
            actions: entry.actions,
        }
    }

    function loadHistory() {
        historyFile.path = root.historyPath
        historyFile.reload()
    }

    function onHistoryLoaded() {
        let parsed = []
        try {
            parsed = JSON.parse(historyFile.text())
        } catch (e) {
            parsed = []
        }
        if (!Array.isArray(parsed))
            parsed = []

        const list = []
        for (let i = 0; i < parsed.length && i < root.maxHistory; i++) {
            const d = parsed[i]
            const entry = entryComp.createObject(root, {
                entryId: ++root.entrySeq,
                time: d.time !== undefined ? d.time : 0,
            })
            entry.appName = d.appName || ""
            entry.appIcon = d.appIcon || ""
            entry.image = d.image || ""
            entry.summary = d.summary || ""
            entry.body = d.body || ""
            entry.desktopEntry = d.desktopEntry || ""
            entry.urgency = d.urgency !== undefined ? d.urgency : NotificationUrgency.Normal
            entry.actions = d.actions || []
            entry.isTransient = false
            entry.popup = false
            list.push(entry)
        }

        // Anything received before the (async) cache read stays on top.
        root.entries = root.entries.concat(list)
        root.loaded = true
        root.bump()
    }

    function onHistoryLoadFailed(error) {
        // Missing file is the normal first run: stay empty and let the first
        // debounced write create it.
        root.loaded = true
        root.bump()
    }

    // ------------------------------------------------------------- backing
    NotificationServer {
        id: server
        keepOnReload: false
        bodySupported: true
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: function (notification) {
            root.handleNotification(notification)
        }
    }

    // Create the cache directory before the first read/write.
    Process {
        id: boot
        command: ["/bin/sh", "-c", "mkdir -p \"$1\"", "sh", root.cacheDir]
        running: true
        onExited: {
            if (root.persistEnabled) {
                root.loadHistory()
            } else {
                root.loaded = true
                root.bump()
            }
        }
    }

    FileView {
        id: historyFile
        atomicWrites: true
        onLoaded: root.onHistoryLoaded()
        onLoadFailed: function (error) { root.onHistoryLoadFailed(error) }
    }

    // Coalesces bursts of notifications into a single disk write.
    Timer {
        id: persistTimer
        interval: 1000
        onTriggered: root.writeHistory()
    }

    // One notification record. Holds a snapshot plus, while live, the server
    // Notification object.
    component NotificationEntry: QtObject {
        id: entry

        required property int entryId
        property Notification notification: null
        property bool popup: false
        property bool isTransient: false
        property double time: 0
        property Timer timer: null

        property string appName: ""
        property string appIcon: ""
        // Image sent by the client (`image-path`/`image-data`, e.g. `notify-send -i`).
        property string image: ""
        property string summary: ""
        property string body: ""
        property string desktopEntry: ""
        property int urgency: NotificationUrgency.Normal
        property var actions: []
        // Whether this entry arrived since the history was last opened.
        property bool unread: false

        readonly property Connections serverConn: Connections {
            target: entry.notification !== null ? entry.notification.Retainable : null
            function onDropped() { root.onEntryDropped(entry) }
            function onAboutToDestroy() { entry.notification = null }
        }
    }

    // Per-notification auto-dismiss timer, destroyed right after firing.
    component EntryTimer: Timer {
        id: timer
        required property int entryId
        running: true
        onTriggered: {
            root.timeoutEntry(timer.entryId)
            timer.destroy()
        }
    }

    Component {
        id: entryComp
        NotificationEntry {}
    }

    Component {
        id: timerComp
        EntryTimer {}
    }
}
