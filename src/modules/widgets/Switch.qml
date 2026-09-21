import QtQuick
import "../theme"

Item {
    id: root

    property bool checked: false
    property bool enabled: true
    property color activeColor: Theme.accentColor
    property color trackColor: Theme.fgColor

    signal toggled()

    implicitWidth: 34
    implicitHeight: 18
    opacity: enabled ? 1 : 0.4

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? root.activeColor : "transparent"
        border.width: 1
        border.color: root.checked ? root.activeColor : root.trackColor
        opacity: root.checked ? 1 : 0.5

        Rectangle {
            width: parent.height - 4
            height: width
            radius: width / 2
            y: 2
            x: root.checked ? parent.width - width - 2 : 2
            color: root.checked ? Theme.bgColor : root.trackColor

            Behavior on x {
                NumberAnimation {
                    duration: 120
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
