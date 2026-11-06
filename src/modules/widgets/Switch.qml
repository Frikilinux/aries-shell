import QtQuick
import "../theme"

// Small toggle switch. Track is filled in both states (muted gray when off,
// accent when on) with a light knob that slides, so the on/off state reads
// clearly on both light and dark surfaces. Uses the built-in Item.enabled for
// the disabled state (disables the MouseArea via inheritance, 40% opacity).
Item {
    id: root

    property bool checked: false
    property color activeColor: Theme.accentColor
    property color trackColor: Theme.fgColorMuted

    signal toggled()

    implicitWidth: 38
    implicitHeight: 20
    opacity: enabled ? 1 : 0.4

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? root.activeColor : Qt.alpha(root.trackColor, 0.40)
        border.width: root.checked ? 0 : 1
        border.color: root.checked ? "transparent" : Qt.alpha(root.trackColor, 0.55)

        Behavior on color {
            ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        // Knob.
        Rectangle {
            id: knob
            width: parent.height - 4
            height: width
            radius: width / 2
            y: 2
            x: root.checked ? parent.width - width - 2 : 2
            color: Theme.fgColor

            Behavior on x {
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.toggled()
    }
}
