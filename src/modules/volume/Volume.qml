import QtQuick
import Quickshell.Services.Pipewire
import "../theme"
import "../icon"
import "../config"

Item {
    id: volume

    // Show this module only on specific outputs (monitors).
    // Set to a string ("HDMI-A-1") or array (["eDP-1"]). If undefined/null, shows on all.
    property var outputs
    // The output being rendered.
    property string output: ""

    // Icon style used by this module's bar icon. Defaults to Theme.iconStyle.
    property string iconStyle: Theme.iconStyle

    // Volume delta (0..1 fraction) applied per wheel step (from the user config)
    property real scrollStep: Config.settings.modules.volume.scrollStep
    // Set true when the system uses natural (inverted) scrolling so the module
    // behaves identically: scrolling "up" raises the volume, "down" lowers it.
    property bool naturalScroll: Config.settings.modules.volume.naturalScroll

    // The default audio output (PipeWire's default sink, managed by WirePlumber)
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool ready: sink !== null && sink.ready && sink.audio !== null
    readonly property real percent: ready ? sink.audio.volume : 0
    readonly property bool muted: ready && sink.audio.muted

    // Fades the icon (no volume-xmark glyph used)
    readonly property string glyph: volume.muted ? "\ue03f"                // speaker-mute
        : volume.percent >= 0.75 ? "\ue076"                                // speaker3
        : volume.percent >= 0.50 ? "\ue03c"                                // speaker2
        : volume.percent >= 0.25 ? "\ue03b"                                // speaker1
        : volume.percent >= 0.01 ? "\ue03a"                                // speaker0
        : "\ue040"                                                         // speaker-off

    implicitWidth: indicator.implicitWidth
    implicitHeight: indicator.implicitHeight

    // Module is visible only if outputs property is unset, matches this output, or contains it
    visible: !outputs || (Array.isArray(outputs) ? outputs.includes(output) : outputs === output)

    // Required: PwNodeAudio.muted / volume writes only work while the node is
    // bound. The tracker keeps the default sink alive and its audio controls valid.
    PwObjectTracker {
        objects: [volume.sink]
    }

    Icon {
        id: indicator
        glyph: volume.glyph
        style: volume.iconStyle
        color: Theme.fgBarColor
        opacity: volume.muted ? 0.5 : 1
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onClicked: {
            if (volume.ready)
                volume.sink.audio.muted = !volume.sink.audio.muted
        }
        onWheel: (wheel) => volume.adjust(wheel.angleDelta.y)
    }

    // Apply a wheel delta: positive raises the volume, negative lowers it.
    // angleDelta.y is in 1/8-degree units (120 = one notch); smooth scrolling
    // emits smaller deltas, so the step is scaled proportionally.
    function adjust(delta) {
        if (!volume.ready || delta === 0)
            return
        var dir = delta > 0 ? 1 : -1
        if (volume.naturalScroll)
            dir = -dir
        var audio = volume.sink.audio
        audio.volume = Math.max(0, Math.min(1, audio.volume + dir * volume.scrollStep))
        if (audio.volume > 0)
            audio.muted = false
    }
}