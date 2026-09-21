pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Shared power-action state for the bar indicator and its popup.
//
// Availability is detected from the kernel's sleep states in /sys/power/state
// (suspend = "mem", hibernate = "disk"); shutdown and restart are always
// available. Actions are executed with systemctl (logind allows a logged-in
// user to power off/reboot/suspend/hibernate without extra privileges).
Singleton {
    id: root

    // Whether sleep (suspend to RAM) and hibernate (suspend to disk) work
    property bool canSuspend: false
    property bool canHibernate: false

    function refresh() {
        stateReader.running = true
    }

    function parsePowerState(text) {
        const states = text.trim().split(/\s+/)
        root.canSuspend = states.includes("mem")
        root.canHibernate = states.includes("disk")
    }

    // action: "shutdown", "restart", "sleep" or "hibernate"
    function execute(action) {
        const targets = {
            "shutdown": "poweroff",
            "restart": "reboot",
            "sleep": "suspend",
            "hibernate": "hibernate"
        }
        const target = targets[action]
        if (target === undefined)
            return
        powerProcess.command = ["systemctl", target]
        powerProcess.running = true
    }

    Component.onCompleted: refresh()

    Process {
        id: stateReader
        command: ["/bin/cat", "/sys/power/state"]
        stdout: StdioCollector {
            onStreamFinished: root.parsePowerState(text)
        }
    }

    Process {
        id: powerProcess
    }
}