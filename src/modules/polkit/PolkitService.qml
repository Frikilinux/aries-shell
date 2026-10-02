pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Polkit

// Single Polkit authentication agent for the whole shell.
//
// Quickshell's `PolkitAgent` registers itself with the system polkit daemon as
// soon as it is instantiated (implying exactly one instance per process), so it
// lives here instead of being scattered across surfaces. The dialog surface(s)
// in this module only render the exposed state and forward user input.
//
// The agent auto-registers; incoming requests populate `flow` and flip
// `active`. If authentication is needed but no UI exists, requests would hang
// forever, which is why the agent and the dialog ship together.
Singleton {
    id: root

    // The active authentication flow, or null when idle. Owned by the agent.
    readonly property var flow: agent.flow
    // True while a request is in progress (bound to `flow !== null`).
    readonly property bool active: agent.isActive
    // Whether the daemon accepted our registration (for diagnostics/UI).
    readonly property bool registered: agent.isRegistered

    // Submit a response (typically the password) to the current flow.
    function submit(value) {
        if (agent.flow !== null)
            agent.flow.submit(value)
    }

    // Cancel the current request from the user side (Esc / Cancel / close).
    function cancel() {
        if (agent.flow !== null)
            agent.flow.cancelAuthenticationRequest()
    }

    PolkitAgent {
        id: agent
    }
}
