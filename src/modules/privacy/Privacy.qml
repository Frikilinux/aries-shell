import QtQuick
import "../theme"
import "../icon"
import "../config"
import "../widgets"

// Bar indicator for active privacy-sensitive captures (microphone, camera,
// screen share via Pipewire). Each active capture shows its icon; with no
// captures the module is hidden completely (no gap in the bar). Clicking the
// pill opens a popup listing the applications making the captures.
Item {
    id: privacy

    // Show this module only on specific outputs (monitors).
    // Set to a string ("HDMI-A-1") or array (["eDP-1"]). If undefined/null, shows on all.
    property var outputs
    // The output being rendered.
    property string output: ""

    // The captures popup, exposed for shell.qml.
    property alias popup: capturesPopup

    readonly property bool mic: PrivacyService.micInUse
    readonly property bool camera: PrivacyService.cameraInUse
    readonly property bool share: PrivacyService.screenInUse
    // At least one capture active.
    readonly property bool any: privacy.mic || privacy.camera || privacy.share
    // Number of icons shown (the pill width derives from it via the Row).
    readonly property int iconCount: (privacy.mic ? 1 : 0) + (privacy.camera ? 1 : 0) + (privacy.share ? 1 : 0)

    // Pill: icons row + `Theme.pillPadding` padding per side; height fits the icons.
    readonly property int animationTime: Config.settings.bar.animation
    implicitWidth: privacy.any ? container.width : 1
    implicitHeight: privacy.any ? container.height : 1

    // Module is visible only while something is captured and if outputs is
    // unset, matches this output, or contains it.
    visible: privacy.any && (!outputs || (Array.isArray(outputs) ? outputs.includes(output) : outputs === output))

    // No captures left while the popup is open: the anchor disappears with
    // the module, so close it instead of leaving it floating with no pill.
    onVisibleChanged: {
        if (!privacy.visible)
            capturesPopup.visible = false;
    }

    // Pill behind the capture icons (see widgets/Pill.qml), same ink-edge
    // alignment as the notifications pill.
    Pill {
        id: container
        anchors.centerIn: parent
        visible: privacy.any
        contentWidth: row.implicitWidth
        contentHeight: row.implicitHeight
        fillColor: Theme.bgPrivacy
        fillOpacity: Theme.bgOpacity
        animationTime: privacy.animationTime
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.innerGap

        // Microphone in use.
        Icon {
            visible: privacy.mic
            glyph: "\ue08a" // microphone
            color: Theme.fgPrivacy
        }

        // Camera in use.
        Icon {
            visible: privacy.camera
            glyph: "\ue08c" // webcam
            color: Theme.fgPrivacy
        }

        // Screen share in use.
        Icon {
            visible: privacy.share
            glyph: "\ue08b" // screen-share
            color: Theme.fgPrivacy
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: capturesPopup.visible = !capturesPopup.visible
    }

    PrivacyPopup {
        id: capturesPopup
        anchorItem: privacy
    }
}
