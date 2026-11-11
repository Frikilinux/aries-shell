pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Reads the user's GNOME Calendar (Evolution Data Server) events via a small
// Python helper and exposes them to the clock popup. The helper is only run
// when the cache is stale, so opening the popup stays cheap.
Singleton {
    id: root

    readonly property int days: Config.settings.modules.clock.calendarDays
    readonly property int maxEvents: Config.settings.modules.clock.calendarMaxEvents
    readonly property int refreshInterval: 60000

    property var events: []
    property bool loading: false
    property bool failed: false
    property int lastFetch: 0

    readonly property bool stale: root.lastFetch === 0 || (Date.now() - root.lastFetch) >= root.refreshInterval

    function refresh(force) {
        if (root.loading)
            return
        if (!force && !root.stale)
            return
        root.failed = false
        root.loading = true
        fetchProcess.command = ["python3", Quickshell.shellDir + "/modules/clock/calendar-fetch.py", String(root.days), String(root.maxEvents)]
        fetchProcess.running = true
    }

    function invalidate() {
        root.lastFetch = 0
    }

    Process {
        id: fetchProcess
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "") {
                    root.failed = true
                    root.events = []
                } else {
                    try {
                        const parsed = JSON.parse(text)
                        if (Array.isArray(parsed))
                            root.events = parsed
                        else
                            root.failed = true
                    } catch (e) {
                        root.failed = true
                        root.events = []
                    }
                }
                root.loading = false
                if (!root.failed)
                    root.lastFetch = Date.now()
            }
        }
        onExited: function (exitCode, exitStatus) {
            if (exitCode !== 0) {
                root.failed = true
                root.events = []
                root.loading = false
            }
        }
    }

    Component.onCompleted: root.refresh(true)
}
