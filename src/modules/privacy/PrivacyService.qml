pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Privacy backend: watches every Pipewire node to tell whether an application
// is currently capturing the microphone or sharing the screen.
//
// How detection works:
//  * `Pipewire.nodes` carries every node on the system; nodes are unbound by
//    default, so the PwObjectTracker below binds them all, keeping their
//    `properties` maps available.
//  * Classification is by the node's `media.class` string property, NOT by
//    quickshell's `type` flags: quickshell does not parse video stream
//    classes (they arrive as `Untracked` with `isStream=false` — verified
//    live), while media.class always tells the truth:
//      Stream/Input/Audio        -> mic capture (or output capture, below)
//      Stream/Output|Input/Video -> screen share, either side of it: the
//                                   compositor's cast source (niri pushes
//                                   `niri-screen-cast-src`, Stream/Output/
//                                   Video) and the client consuming it
//                                   (Vesktop `webrtc-consume-stream`,
//                                   Stream/Input/Video).
//    Note the segment order: media.class = Stream/<dir>/<kind>.
//  * Audio input streams capturing other apps' output (`stream.capture.sink`
//    = true, what sharing portals do with sound) count as screen share.
//  * Monitor streams (`stream.monitor`, e.g. pavucontrol's level meters) are
//    not privacy relevant and are filtered out.
//
// Presence-based: a stream existing counts as a capture even while its
// consumer is idle (Discord left open shares the mic). That matches
// GNOME-style privacy indicators.
// NOTE: results are refreshed by the Timer below, not by bindings — quickshell
// pipewire node-model reactivity does not re-trigger dependent bindings when
// streams appear (verified live: a single binding evaluation keeps the scan
// result frozen), so a 500ms re-scan is the reliable refresh path.
Singleton {
    id: root

    // Imperative scan results; the pill UI reads these.
    property bool hasMic: false
    property bool hasScreen: false
    // Exposed names for consumers + overall pill visibility flag.
    readonly property bool micInUse: root.hasMic
    readonly property bool screenInUse: root.hasScreen
    readonly property bool anyInUse: root.micInUse || root.screenInUse

    // Binds every node: only bound nodes expose their full `properties` map.
    PwObjectTracker {
        objects: Pipewire.nodes.values
    }

    // Scan every pipewire node and classify captures.
    function detect() {
        const result = { mic: false, screen: false }
        const nodes = Pipewire.nodes.values
        for (let i = 0; i < nodes.length; i++) {
            const n = nodes[i]
            if (!n)
                continue
            const props = n.properties || {}

            // Monitor streams are level meters listening to a sink, not captures.
            if (props["stream.monitor"] === "true")
                continue

            const mc = "" + (props["media.class"] || "")
            if (mc.indexOf("Stream/") !== 0)
                continue // hardware devices and aux nodes never leak privacy
            const parts = mc.split("/")
            const dir = parts[1]       // Input | Output | Duplex
            const kind = parts[2]      // Audio | Video

            if (kind === "Video") {
                // Either side of a screen cast: the compositor grabbing the
                // screen (Output) or the client consuming it (Input).
                result.screen = true
            } else if (kind === "Audio" && dir === "Input") {
                if (props["stream.capture.sink"] === "true")
                    result.screen = true // capturing other apps' output (share audio)
                else
                    result.mic = true // real microphone capture
            }
            // Audio play/bridge streams never leak privacy.
        }
        return result
    }

    // Periodic re-scan; the only reliable refresh (see note above).
    Timer {
        interval: 500
        running: Pipewire.ready
        repeat: true
        onTriggered: {
            const r = root.detect()
            root.hasMic = r.mic
            root.hasScreen = r.screen
        }
    }
}
