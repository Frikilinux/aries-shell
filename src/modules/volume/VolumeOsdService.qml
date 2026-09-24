pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "../config"

// State of the volume OSD. Follows PipeWire's default sink and flips `shown`
// whenever its volume/mute changes (bar scroll, wpctl, an app...). The OSD
// window(s) only render this state and hide after `osd.timeout` ms.
Singleton {
    id: root

    // The default audio output (PipeWire's default sink, managed by WirePlumber)
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool ready: sink !== null && sink.ready && sink.audio !== null
    readonly property real volume: ready ? sink.audio.volume : 0
    readonly property bool muted: ready && sink.audio.muted

    readonly property bool osdEnabled: Config.settings.modules.volume.osd.enabled

    // Short display name of the output: node.nick ("HDMI 3") when set, else
    // the description minus the ALSA controller prefix ("HDMI / DisplayPort 3
    // Output"), else the internal node name.
    readonly property string deviceName: {
        const s = root.sink
        if (s === null)
            return ""
        const nick = s.nickname || ""
        if (nick !== "")
            return nick
        const desc = s.description || ""
        if (desc !== "") {
            const i = desc.indexOf(" Controller ")
            return i !== -1 ? desc.substring(i + 12) : desc
        }
        return s.name || ""
    }

    // Percent text value (volume can exceed 1.0 when set externally)
    readonly property int percent: Math.round(root.volume * 100)

    // Same glyph steps as the bar icon (see Volume.qml)
    readonly property string glyph: root.muted ? "\ue03f"                 // speaker-mute
        : root.volume >= 0.75 ? "\ue076"                                  // speaker3
        : root.volume >= 0.50 ? "\ue03c"                                  // speaker2
        : root.volume >= 0.25 ? "\ue03b"                                  // speaker1
        : root.volume >= 0.01 ? "\ue03a"                                  // speaker0
        : "\ue040"                                                        // speaker-off

    // OSD visibility; every change restarts the hide timer
    property bool shown: false

    // Session-restore sets the sink volume right after login: ignore changes
    // during the first 2 s so the OSD never flashes at boot.
    Timer {
        id: graceTimer
        running: true
        interval: 2000
    }

    function show() {
        if (!root.osdEnabled || graceTimer.running)
            return
        root.shown = true
        hideTimer.restart()
    }

    function hide() {
        hideTimer.stop()
        root.shown = false
    }

    // Keeps the default sink bound: live volume/mute updates arrive only
    // while the node is tracked (same requirement as the bar's Volume module).
    PwObjectTracker {
        objects: [root.sink]
    }

    Connections {
        target: root.ready ? root.sink.audio : null

        function onVolumesChanged() { root.show() }
        function onMutedChanged() { root.show() }
    }

    Timer {
        id: hideTimer
        interval: Math.max(100, Config.settings.modules.volume.osd.timeout)
        onTriggered: root.shown = false
    }
}
