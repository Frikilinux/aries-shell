import QtQuick
import "../theme"

// Small toggle switch. The track is filled in both states (dimmed gray when
// off, accent when on) with a light knob that slides, so the on/off state reads
// clearly on both light and dark surfaces. Uses the built-in Item.enabled for
// the disabled state (disables the MouseArea via inheritance, 40% opacity).
//
// Geometry comes from `trackWidth` / `trackHeight` / `knobInset`, so a surface
// can opt into the larger libadwaita size (46x26, 3px inset) without a second
// widget; the bar popups keep the compact 38x20 default.
Item {
    id: root

    property bool checked: false
    property color activeColor: Theme.accentColor
    property color trackColor: Theme.fgColorMuted
    property color knobOnColor: Theme.fgColorEmphasis
    property color knobOffColor: Theme.fgColor

    // Compact by default; settings windows pass the libadwaita metrics.
    property int trackWidth: 38
    property int trackHeight: 20
    property int knobInset: 2

    signal toggled

    implicitWidth: trackWidth
    implicitHeight: trackHeight
    opacity: enabled ? 1 : 0.4

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        // Filled in both states, no border: the off state is a dimmed track
        // instead of an outline, as in libadwaita.
        color: root.checked ? root.activeColor : Qt.alpha(root.trackColor, 0.22)

        Behavior on color {
            ColorAnimation {
                duration: 140
                easing.type: Easing.OutCubic
            }
        }

        // Knob.
        Rectangle {
            id: knob
            width: parent.height - root.knobInset * 2
            height: width
            radius: width / 2
            y: root.knobInset
            x: root.checked ? parent.width - width - root.knobInset : root.knobInset
            color: root.checked ? root.knobOnColor : root.knobOffColor

            Behavior on x {
                NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on color {
                ColorAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.toggled()
    }
}
