import QtQuick
import "../theme"
import "../icon"
import "../config"

// Bar indicator for active privacy-sensitive captures (microphone / screen
// share via Pipewire). Each active capture shows its icon; with no captures
// the module is hidden completely (no gap in the bar).
Item {
    id: privacy

    // Show this module only on specific outputs (monitors).
    // Set to a string ("HDMI-A-1") or array (["eDP-1"]). If undefined/null, shows on all.
    property var outputs
    // The output being rendered.
    property string output: ""

    readonly property bool mic: PrivacyService.micInUse
    readonly property bool share: PrivacyService.screenInUse
    // At least one capture active.
    readonly property bool any: privacy.mic || privacy.share
    // Number of icons shown (the pill width derives from it via the Row).
    readonly property int iconCount: (privacy.mic ? 1 : 0) + (privacy.share ? 1 : 0)

    // Pill: icons row + `Theme.pillPadding` padding per side; height fits the icons.
    readonly property int animationTime: Config.settings.bar.animation
    implicitWidth: privacy.any ? row.implicitWidth + Theme.pillPadding * 2 + Theme.iconInset * 2 : 1
    implicitHeight: privacy.any ? row.implicitHeight + Theme.pillPadding * 2 : 1

    // Module is visible only while something is captured and if outputs is
    // unset, matches this output, or contains it.
    visible: privacy.any && (!outputs || (Array.isArray(outputs) ? outputs.includes(output) : outputs === output))

    // Pill container behind the icons; same palette as the notifications pill
    // (Chip colors), but plain button background — captures are shown with the
    // critical urgency color as the "you are being watched" signal.
    Rectangle {
        id: container
        anchors.centerIn: parent
        width: row.implicitWidth + Theme.pillPadding * 2
        height: row.implicitHeight + Theme.pillPadding * 2
        radius: height / 2
        visible: privacy.any
        color: Theme.bgPrivacy
        // border.width: 0
        opacity: Theme.bgOpacity
        // border.color: Theme.buttonBorder
        Behavior on width {
            NumberAnimation {
                duration: privacy.animationTime
            }
        }
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

        // Screen share in use.
        Icon {
            visible: privacy.share
            glyph: "\ue08b" // screen-share
            color: Theme.fgPrivacy
        }
    }
}
