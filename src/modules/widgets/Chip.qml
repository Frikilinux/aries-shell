import QtQuick
import "../theme"

// Small rounded button, used for boolean device flags (e.g. trusted / blocked).
// Inactive uses the plain button colors; active switches to the primary fill.
// Set `interactive: false` for read-only status badges.
Item {
    id: root

    property string text: ""
    property bool active: false
    property bool interactive: true

    signal clicked()

    implicitWidth: label.implicitWidth + 16
    implicitHeight: 20
    width: implicitWidth
    height: implicitHeight

    Rectangle {
        anchors.fill: parent
        radius: 4
        color: root.active ? Theme.buttonChipBgColor : Theme.buttonBgColor
        border.width: 1
        border.color: Theme.buttonBorder

        Text {
            id: label
            anchors.centerIn: parent
            text: root.text
            color: root.active ? Theme.fgColor : Theme.fgColorMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 4
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.interactive
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }
}
