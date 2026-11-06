import QtQuick
import "../theme"
import "../icon"

Item {
    id: ariesConnect

    // Show this module only on specific outputs (monitors).
    // Set to a string ("HDMI-A-1") or array (["eDP-1"]). If undefined/null, shows on all.
    property var outputs
    // The output being rendered.
    property string output: ""

    // The popup window, exposed for shell.qml.
    property alias popup: popupWindow

    implicitWidth: indicator.implicitWidth
    implicitHeight: indicator.implicitHeight

    // Module is visible only if outputs property is unset, matches this output, or contains it
    visible: !outputs || (Array.isArray(outputs) ? outputs.includes(output) : outputs === output)

    Icon {
        id: indicator
        glyph: "\ue033" // phone
        // A pending pairing request is the only state worth an alarm color:
        // the phone waits 30 s for a decision.
        color: AriesConnectService.request !== null ? Theme.urgentColor : Theme.fgBarColor
        opacity: AriesConnectService.request !== null ? 1 : AriesConnectService.connectedCount > 0 ? 1 : AriesConnectService.pairedCount > 0 ? 0.7 : 0.4
        font.pixelSize: Math.round(Theme.iconSize * 1)
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: ariesConnect.popup.visible = !ariesConnect.popup.visible
    }

    AriesConnectPopup {
        id: popupWindow
        anchorItem: ariesConnect

        // The gear in the popup header opens the settings window. The two are
        // separate surfaces (layer-shell popup vs xdg toplevel), so close the
        // popup first; the window itself lives once in shell.qml (settings are
        // not per screen, unlike this module).
        onSettingsRequested: {
            popupWindow.visible = false
            AriesConnectService.settingsOutput = ariesConnect.output
            AriesConnectService.settingsVisible = true
        }
    }
}
