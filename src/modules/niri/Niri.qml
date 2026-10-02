pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Raw workspace list, kept in sync with niri's event stream.
    // Fields: id, idx, name, output, is_urgent, is_active, is_focused, active_window_id
    property var workspaces: []

    // Window id -> { workspaceId, urgent }. Used to derive a workspace's
    // urgency when a window changes its urgency (WindowUrgencyChanged).
    property var windowIndex: ({})

    // Output (monitor) currently holding the focused workspace, derived from
    // the single workspace with `is_focused`. Empty when unknown (no session).
    // niri has no dedicated "focused output" event; WorkspaceActivated with
    // `focused: true` marks the newly focused workspace, which is enough.
    readonly property string focusedOutput: {
        const w = root.workspaces.find(ws => ws.is_focused)
        return w && w.output ? w.output : ""
    }

    // Whether a niri session is available (IPC socket is set)
    readonly property bool available: Quickshell.env("NIRI_SOCKET") !== ""

    // Connect to niri's IPC socket ($NIRI_SOCKET) and subscribe to the event
    // stream, which sends the full state up-front and then incremental updates.
    Socket {
        id: socket

        path: Quickshell.env("NIRI_SOCKET")
        connected: path !== ""

        parser: SplitParser {
            onRead: line => root.handleEvent(line)
        }

        onConnectionStateChanged: {
            if (connected) {
                write("\"EventStream\"\n")
                flush()
            } else {
                reconnectTimer.start()
            }
        }
    }

    Timer {
        id: reconnectTimer
        interval: 1000
        onTriggered: socket.connected = true
    }

    // One-shot connection for requests (actions), kept separate from the
    // long-lived event stream. Connects on demand and disconnects on reply.
    Socket {
        id: actionSocket

        path: Quickshell.env("NIRI_SOCKET")

        parser: SplitParser {
            onRead: line => {
                actionSocket.connected = false
                 try {
                     const reply = JSON.parse(line)
                     if (reply.Err)
                         console.warn("Niri: request failed:", reply.Err)
                 } catch (e) {
                     console.warn("Niri: Failed to parse reply:", line, e)
                 }
            }
        }

        onConnectionStateChanged: {
            if (connected) {
                write(root.pendingRequest + "\n")
                flush()
            }
        }
    }

    property string pendingRequest: ""

    function send(request) {
        if (!actionSocket.path)
            return
        root.pendingRequest = JSON.stringify(request)
        if (actionSocket.connected)
            actionSocket.write(root.pendingRequest + "\n")
        else
            actionSocket.connected = true
    }

    function focusWorkspace(id) {
        send({ Action: { FocusWorkspace: { reference: { Id: id } } } })
    }

    // Focus a window by niri id (switches to its workspace too).
    function focusWindow(id) {
        send({ Action: { FocusWindow: { id: id } } })
    }

    // Normalize a string for fuzzy app matching: lowercase, alphanumerics only.
    function normalizeApp(s) {
        return String(s === null || s === undefined ? "" : s)
            .toLowerCase().replace(/[^a-z0-9]+/g, "")
    }

    // Focus the most recently focused window whose app_id matches any candidate
    // (e.g. a notification's desktopEntry / appName). Exact normalized matches
    // win over substring ones; ties break on recency. Returns true if focused.
    function focusApp(candidates) {
        const needles = (Array.isArray(candidates) ? candidates : [candidates])
            .map(root.normalizeApp).filter(n => n.length >= 3)
        if (needles.length === 0)
            return false
        const hit = root._bestAppWindow(needles, false)
            || root._bestAppWindow(needles, true)
        if (hit === null)
            return false
        root.focusWindow(hit)
        return true
    }

    function _appMatches(appId, needles, loose) {
        if (appId === "")
            return false
        for (let i = 0; i < needles.length; i++) {
            const n = needles[i]
            if (appId === n)
                return true
            if (loose && (appId.indexOf(n) !== -1 || n.indexOf(appId) !== -1))
                return true
        }
        return false
    }

    function _bestAppWindow(needles, loose) {
        let best = null
        let bestTs = -1
        for (const id in root.windowIndex) {
            const w = root.windowIndex[id]
            if (!root._appMatches(w.appId, needles, loose))
                continue
            if (w.focusTs > bestTs) {
                bestTs = w.focusTs
                best = Number(id)
            }
        }
        return best
    }

    function _focusTimestamp(t) {
        return t ? (t.secs || 0) + (t.nanos || 0) / 1e9 : 0
    }

    // Quit niri (ends the compositor session)
    function quit() {
        send({ Action: { Quit: {} } })
    }

    function indexWindow(win) {
        root.windowIndex[win.id] = {
            workspaceId: win.workspace_id,
            urgent: win.is_urgent,
            appId: root.normalizeApp(win.app_id),
            focusTs: root._focusTimestamp(win.focus_timestamp),
        }
    }

    // A workspace is urgent if any of its windows is urgent (same rule as niri).
    function recomputeWorkspaceUrgency(workspaceId) {
        if (workspaceId === null || workspaceId === undefined)
            return
        let urgent = false
        for (const id in root.windowIndex) {
            const win = root.windowIndex[id]
            if (win.workspaceId === workspaceId && win.urgent) {
                urgent = true
                break
            }
        }
        root.workspaces = root.workspaces.map(w => w.id === workspaceId
            ? Object.assign({}, w, { is_urgent: urgent })
            : w)
    }

    function handleEvent(line) {
        let ev
         try {
             ev = JSON.parse(line)
         } catch (e) {
             console.warn("Niri: Failed to parse event:", line, e)
             return
         }

        if (ev.WorkspacesChanged) {
            root.workspaces = ev.WorkspacesChanged.workspaces
        } else if (ev.WindowsChanged) {
            root.windowIndex = ({})
            for (const win of ev.WindowsChanged.windows)
                root.indexWindow(win)
        } else if (ev.WindowOpenedOrChanged) {
            root.indexWindow(ev.WindowOpenedOrChanged.window)
        } else if (ev.WindowClosed) {
            delete root.windowIndex[ev.WindowClosed.id]
        } else if (ev.WindowUrgencyChanged) {
            const e = ev.WindowUrgencyChanged
            const win = root.windowIndex[e.id]
            if (win) {
                win.urgent = e.urgent
                root.recomputeWorkspaceUrgency(win.workspaceId)
            }
        } else if (ev.WindowFocusTimestampChanged) {
            // Keeps focus recency fresh so focusApp() picks the right window.
            const e = ev.WindowFocusTimestampChanged
            const win = root.windowIndex[e.id]
            if (win)
                win.focusTs = root._focusTimestamp(e.focus_timestamp)
        } else if (ev.WorkspaceActivated) {
            const e = ev.WorkspaceActivated
            const target = root.workspaces.find(w => w.id === e.id)
            if (target) {
                const output = target.output
                root.workspaces = root.workspaces.map(w => Object.assign({}, w, {
                    is_active: w.output === output ? w.id === e.id : w.is_active,
                    is_focused: e.focused ? w.id === e.id : w.is_focused,
                }))
            }
        } else if (ev.WorkspaceActiveWindowChanged) {
            const e = ev.WorkspaceActiveWindowChanged
            root.workspaces = root.workspaces.map(w => w.id === e.workspace_id
                ? Object.assign({}, w, { active_window_id: e.active_window_id })
                : w)
        } else if (ev.WorkspaceUrgencyChanged) {
            const e = ev.WorkspaceUrgencyChanged
            root.workspaces = root.workspaces.map(w => w.id === e.id
                ? Object.assign({}, w, { is_urgent: e.urgent })
                : w)
        } else if (ev.WindowFocusChanged) {
            // Deliberately do NOT dismiss popups on window focus changes.
            // With focus-follows-mouse enabled this event fires on plain hover
            // (and niri pre-focuses a window before the click lands), which
            // would close a popup the instant the pointer leaves it — e.g.
            // over a window on another output. Outside clicks are handled by
            // the transparent scrim layer (Wallpaper.qml), the bar's own
            // MouseArea, and Esc instead.
        }
    }
}
