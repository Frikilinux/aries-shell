import QtQuick
import "../theme"

// libadwaita radio indicator. Draws only: the owning row (or a MouseArea)
// drives `checked` from real state, so the dot never disagrees with the
// backend. Mirrors Switch.qml: compact 18px by default for the bar popups,
// windows can opt into the libadwaita 24px metrics (dot 10) and the softer
// 15% ring libadwaita uses on solid cards.
Item {
    id: root

    property bool checked: false
    property int diameter: 18
    property int dotSize: 8
    // Popups sit on a translucent layer over the wallpaper -> stronger ring
    // than libadwaita's `fg 15%` card value.
    property color ringColor: Qt.alpha(Theme.fgColor, 0.45)
    property color dotColor: Theme.fgColorEmphasis

    implicitWidth: diameter
    implicitHeight: diameter

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        // Checked is a filled accent disc; off is a plain muted ring.
        color: root.checked ? Theme.accentColor : "transparent"
        border.width: root.checked ? 0 : 2
        border.color: root.ringColor

        Behavior on color {
            ColorAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            visible: root.checked
            anchors.centerIn: parent
            width: root.dotSize
            height: width
            radius: width / 2
            color: root.dotColor
        }
    }
}
