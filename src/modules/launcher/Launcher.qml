import QtQuick
import "../theme"
import "../icon"

// Bar indicator: a grid icon that toggles the application launcher popup.
// The popup itself is an independent per-screen overlay (created in shell.qml)
// so it can open on whichever output is focused; the icon only controls its own
// output.
Item {
    id: launcher

    // Show this module only on specific outputs (monitors).
    // Set to a string ("HDMI-A-1") or array (["eDP-1"]). If undefined/null, shows on all.
    property var outputs
    // The output being rendered.
    property string output: ""

    implicitWidth: indicator.implicitWidth
    implicitHeight: indicator.implicitHeight

    // Module is visible only if outputs property is unset, matches this output, or contains it
    visible: !outputs || (Array.isArray(outputs) ? outputs.includes(output) : outputs === output)

    Icon {
        id: indicator
        glyph: LauncherService.glyph // apps
        color: Theme.fgBarColor
        font.pixelSize: Theme.iconSize
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        // Toggle the launcher popup that belongs to this bar's output.
        onClicked: LauncherIpc.toggleOutput(launcher.output)
    }
}
