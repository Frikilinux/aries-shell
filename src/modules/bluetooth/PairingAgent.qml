pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Pairing confirmation (BlueZ "Confirm passkey NNNNNN (yes/no)") without a
// native Quickshell agent: Quickshell registers no org.bluez.Agent1, so BlueZ
// falls back to the *default agent* - which is why the passkey modal pops up in
// another application instead of here (agent-api: an application that does not
// register an agent uses the default one).
//
// bluetoothctl takes that role while a bluetooth popup is open:
//
//     agent DisplayYesNo
//     default-agent
//     Request confirmation
//     [agent] Confirm passkey 123456 (yes/no):    -> shown as "Pairing code"
//     [agent] Authorize service <uuid> (yes/no):  -> accepted automatically
//
// readline never closes the agent prompt with \n (the line only ends together
// with our own answer), so stdout is read as raw chunks (`splitMarker: ""`) and
// matched against a short rolling buffer instead of split into lines.
Singleton {
    id: root

    // Popups keeping the agent alive (one count per bar instance).
    property int openCount: 0
    // bluetoothctl claimed default-agent: pair() needs no waiting.
    property bool ready: false
    // Pending passkey as six digits ("" = no confirmation showing).
    property string code: ""
    // Device the confirmation belongs to (set by pair(), else last one seen).
    property string address: ""
    // pair() issued before the agent was ready.
    property var pendingDevice: null
    // Address of the last device BlueZ reported an event for.
    property string lastDevice: ""
    // Unprocessed stdout tail; short, but longer than any pattern matched.
    property string buf: ""

    readonly property bool pending: code !== ""

    // The agent is started/stopped imperatively instead of binding `running`
    // to openCount: QML re-evaluates a binding on *every* write, so a counter
    // that drops to 0 would kill bluetoothctl before the grace hold could be
    // applied (and restart it right after).
    function open() {
        stopTimer.stop()
        openCount++
        agent.running = true
    }

    function close() {
        openCount = Math.max(0, openCount - 1)
        if (openCount > 0)
            return
        pendingDevice = null
        pairTimer.stop()
        // Nothing can show a confirmation anymore: reject it right away
        // instead of leaving BlueZ waiting for an answer that never comes.
        if (pending)
            cancel()
        // Keep the agent a few more seconds anyway: BlueZ asks for profile
        // authorization right after bonding, which may still be pending.
        stopTimer.start()
    }

    // Pairing has to go through this agent: Quickshell's own pair() would fall
    // back to whatever agent happens to be the default one.
    function pair(dev) {
        address = dev.address
        if (ready) {
            dev.pair()
            return
        }
        pendingDevice = dev
        pairTimer.restart()
    }

    function accept() {
        answer("yes")
    }

    function cancel() {
        answer("no")
    }

    function answer(reply) {
        if (!pending)
            return
        agent.write(reply + "\n")
        code = ""
    }

    function reset() {
        code = ""
        address = ""
        buf = ""
    }

    // One raw stdout chunk: strip the escapes, act on the events we know and
    // consume them, so the retained tail can never trigger them a second time.
    function feed(chunk) {
        var s = (buf + chunk).replace(/\u001b\[[0-9;]*[A-Za-z]/g, "").replace(/\r/g, "\n")

        if (!ready && s.indexOf("Default agent request successful") !== -1) {
            ready = true
            s = s.replace("Default agent request successful", "")
        }

        // Pairing started elsewhere: attribute it to the last device reported.
        if (s.indexOf("Request confirmation") !== -1 && address === "")
            address = lastDevice

        // Bonding finished or the request died: nothing left to confirm.
        if (/Bonded: yes|Paired: yes|Request canceled|org\.bluez\.Error/.test(s)) {
            code = ""
            address = ""
        }

        var m = s.match(/Confirm passkey ([0-9]{6}) \(yes\/no\):/)
        if (m) {
            s = s.replace(m[0], "")
            // With no popup open there is nobody to show it on (grace hold
            // after close); leaving it unanswered gets it canceled on teardown.
            if (openCount > 0 && code === "")
                code = m[1]
        }

        // Profile authorization right after bonding, plus any dialog we do not
        // recognise: a passkey is always handled above first, so this can never
        // accept a numeric comparison behind the user's back.
        if (code === "" && /(?:Authorize service [0-9a-fA-F-]+ )?\(yes\/no\):/.test(s)) {
            agent.write("yes\n")
            s = s.replace(/(?:Authorize service [0-9a-fA-F-]+ )?\(yes\/no\):/, "")
        }

        var d = s.match(/Device ((?:[0-9A-F]{2}:){5}[0-9A-F]{2})/g)
        if (d)
            lastDevice = d[d.length - 1].slice(7)

        buf = s.slice(-256)
    }

    // A pair() issued before the agent was ready fires as soon as it is, or
    // anyway after a few seconds, so a click never goes unnoticed.
    onReadyChanged: {
        if (ready && pendingDevice !== null) {
            var dev = pendingDevice
            pendingDevice = null
            pairTimer.stop()
            dev.pair()
        }
    }

    Timer {
        id: pairTimer
        interval: 4000
        onTriggered: {
            if (root.pendingDevice !== null) {
                var dev = root.pendingDevice
                root.pendingDevice = null
                dev.pair()
            }
        }
    }

    // Grace hold: the agent outlives the last popup long enough to authorize
    // the profiles of a pairing accepted just before it closed.
    Timer {
        id: stopTimer
        interval: 6000
        onTriggered: {
            if (root.openCount > 0)
                return
            agent.running = false
        }
    }

    Process {
        id: agent
        command: ["bluetoothctl"]
        stdinEnabled: true

        stdout: SplitParser {
            splitMarker: ""
            onRead: data => root.feed(data)
        }

        onStarted: {
            agent.write("agent DisplayYesNo\n")
            agent.write("default-agent\n")
        }

        onRunningChanged: {
            root.ready = false
            if (!agent.running)
                root.reset()
        }
    }
}
