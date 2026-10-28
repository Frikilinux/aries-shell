pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Privacy backend: watches every Pipewire node to tell whether an application
// is currently capturing the microphone, the camera or sharing the screen, and
// which applications those are (listed by the privacy popup).
//
// How detection works:
//  * `Pipewire.nodes` carries every node on the system; nodes are unbound by
//    default, so the PwObjectTracker below binds them all, keeping their
//    `properties` maps available.
//  * Classification is by the node's `media.class` string property, NOT by
//    quickshell's `type` flags: quickshell does not parse video stream
//    classes (they arrive as `Untracked` with `isStream=false` — verified
//    live), while media.class always tells the truth:
//      Stream/Input/Audio   -> mic capture (or output capture, below)
//      Stream/Output/Video  -> screen share, compositor side: niri pushes
//                              `niri-screen-cast-src` when a cast starts.
//      Stream/Input/Video   -> a video capture stream, either side of it: the
//                              client consuming a screen cast
//                              (`webrtc-consume-stream`) or an application
//                              reading the camera.
//    Note the segment order: media.class = Stream/<dir>/<kind>, exactly three
//    segments — four-segment classes like the bluez SCO capture
//    (`Stream/Input/Audio/Internal`, created just by connecting a bluetooth
//    hands-free) are backend plumbing and are skipped.
//  * Camera vs screen-share client: `Pipewire.links` connects producer nodes
//    to consuming streams. A `Stream/Input/Video` fed by a
//    `Stream/Output/Video` cast source is a screen-share client; any other
//    video capture stream is the camera (`PwNode` exposes no node state, so
//    links are the reliable discriminator).
//  * Not every camera user shows up in PipeWire: Electron apps (Vesktop),
//    browsers and cheese open `/dev/video*` directly over V4L2, and PipeWire
//    never sees a node for those. So the camera is ALSO detected by polling
//    the processes holding a /dev/video* device (`fuser`), taking their
//    /proc/<pid>/comm as the app name.
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

    // Imperative scan results; the pill UI and popup read these.
    property bool hasMic: false
    property bool hasScreen: false
    // Camera comes from two sources: PipeWire video capture streams
    // (pipewireCamera*) and apps holding a /dev/video* device open directly
    // (v4l2Apps, most Electron apps / browsers / cheese capture that way).
    property bool pipewireCamera: false
    property var pipewireCameraApps: []
    property var v4l2Apps: []
    // Owning application per capture, deduped display names (popup list).
    property var micApps: []
    property var screenApps: []

    readonly property var cameraApps: root.mergeNames(root.pipewireCameraApps, root.v4l2Apps)
    readonly property bool hasCamera: root.pipewireCamera || root.v4l2Apps.length > 0

    // Exposed flags for consumers + overall pill visibility flag.
    readonly property bool micInUse: root.hasMic
    readonly property bool screenInUse: root.hasScreen
    readonly property bool cameraInUse: root.hasCamera
    readonly property bool anyInUse: root.micInUse || root.screenInUse || root.cameraInUse

    // Binds every node: only bound nodes expose their full `properties` map.
    PwObjectTracker {
        objects: Pipewire.nodes.values
    }

    // Display name of the application owning a stream node.
    function appName(node) {
        const props = node.properties || {}
        return "" + (props["application.name"] || props["node.description"] || props["node.name"] || "")
    }

    // Append unless empty or already listed.
    function addUnique(list, name) {
        if (name !== "" && list.indexOf(name) < 0)
            list.push(name)
    }

    // Merge two name lists into one sorted, deduped list.
    function mergeNames(a, b) {
        const out = []
        for (let i = 0; i < a.length; i++)
            root.addUnique(out, a[i])
        for (let i = 0; i < b.length; i++)
            root.addUnique(out, b[i])
        out.sort()
        return out
    }

    // Scan every pipewire node (and link) and classify captures.
    function detect() {
        const nodes = Pipewire.nodes.values
        const links = Pipewire.links.values
        const result = {
            mic: false,
            screen: false,
            camera: false,
            micApps: [],
            cameraApps: [],
            screenApps: []
        }

        // Video stream node ids fed by a cast source: those are screen-share
        // clients, never camera captures.
        const fedByCast = ({})
        for (let i = 0; i < links.length; i++) {
            const link = links[i]
            if (!link || !link.source || !link.target)
                continue
            const sourceClass = "" + ((link.source.properties || {})["media.class"] || "")
            if (sourceClass === "Stream/Output/Video")
                fedByCast[link.target.id] = true
        }

        // App names of the cast sources, for the case where the consuming
        // stream is not linked yet (or the cast has no separate client node).
        const castSources = []

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
            // Qualified classes with a 4th segment are backend plumbing, not
            // app captures: a bluetooth hands-free (HFP) connection makes the
            // bluez backend create `Stream/Input/Audio/Internal` (the SCO
            // capture feeding the link), which lights the mic up otherwise.
            if (parts.length !== 3)
                continue
            const dir = parts[1]       // Input | Output | Duplex
            const kind = parts[2]      // Audio | Video

            if (kind === "Video") {
                if (dir === "Output") {
                    // Compositor grabbing the screen: something is shared.
                    result.screen = true
                    castSources.push(root.appName(n))
                } else if (dir === "Input") {
                    if (fedByCast[n.id] === true) {
                        // Client consuming the cast = the sharing app.
                        result.screen = true
                        root.addUnique(result.screenApps, root.appName(n))
                    } else {
                        // Not fed by a cast source: the camera is being read.
                        result.camera = true
                        root.addUnique(result.cameraApps, root.appName(n))
                    }
                }
            } else if (kind === "Audio" && dir === "Input") {
                if (props["stream.capture.sink"] === "true") {
                    // Capturing other apps' output (share audio): part of a
                    // screen share, not a microphone capture.
                    result.screen = true
                    root.addUnique(result.screenApps, root.appName(n))
                } else {
                    result.mic = true
                    root.addUnique(result.micApps, root.appName(n))
                }
            }
            // Audio play/bridge streams never leak privacy.
        }

        // Cast up but no identified client (consumer not linked yet): fall
        // back to the cast source's app name, then to a generic label.
        if (result.screen && result.screenApps.length === 0) {
            for (let i = 0; i < castSources.length; i++)
                root.addUnique(result.screenApps, castSources[i])
            if (result.screenApps.length === 0)
                result.screenApps.push("Screen cast")
        }

        result.micApps.sort()
        result.cameraApps.sort()
        result.screenApps.sort()
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
            root.pipewireCamera = r.camera
            root.micApps = r.micApps
            root.pipewireCameraApps = r.cameraApps
            root.screenApps = r.screenApps
        }
    }

    // Direct V4L2 camera users: PipeWire creates no node for apps that open
    // /dev/video* themselves (Vesktop, browsers...), so ask fuser which
    // processes hold a device and name them by /proc/<pid>/comm.
    Process {
        id: v4l2Scan
        command: ["sh", "-c", "for dev in /dev/video*; do fuser \"$dev\" 2>/dev/null; done | tr ' ' '\\n' | grep -E '^[0-9]+$' | sort -u | while read -r pid; do cat \"/proc/$pid/comm\" 2>/dev/null; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                const lines = text.split("\n")
                for (let i = 0; i < lines.length; i++)
                    root.addUnique(out, lines[i].trim())
                root.v4l2Apps = out
            }
        }
    }

    Timer {
        interval: 1000
        running: Pipewire.ready
        repeat: true
        onTriggered: {
            if (!v4l2Scan.running)
                v4l2Scan.running = true
        }
    }
}
