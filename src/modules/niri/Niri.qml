pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../popup"

Singleton {
    id: root

    // Raw workspace list, kept in sync with niri's event stream.
    // Fields: id, idx, name, output, is_urgent, is_active, is_focused, active_window_id
    property var workspaces: []

    // Window id -> { workspaceId, urgent }. Used to derive a workspace's
    // urgency when a window changes its urgency (WindowUrgencyChanged).
    property var windowIndex: ({})

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

    // Quit niri (ends the compositor session)
    function quit() {
        send({ Action: { Quit: {} } })
    }

    function indexWindow(win) {
        root.windowIndex[win.id] = { workspaceId: win.workspace_id, urgent: win.is_urgent }
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
            // A toplevel window got focused (e.g. clicked): dismiss the open
            // popup/menu. Requires focus-follows-mouse OFF — with it on, the
            // event fires on plain hover and would close popups while the user
            // just moves the pointer (windows are also pre-focused by it, so
            // window clicks produce no new event anyway).
            const id = ev.WindowFocusChanged.id
            if (id !== null)
                Popups.closeAll()
        }
    }
}
