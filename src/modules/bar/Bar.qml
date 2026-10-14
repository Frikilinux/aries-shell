pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../popup"
import "../config"

PanelWindow {
    id: bar

    required property var modelData

    readonly property color bgColor: Theme.bgBarColor
    property real bgOpacity: Theme.bgOpacity
    property real spacing: Config.settings.bar.spacing

    // Wayland layer-shell namespace reported by compositors (e.g. niri msg layers)
    WlrLayershell.namespace: "aries"

    // The bar is an always-visible surface, so it must NOT take keyboard focus:
    // with OnDemand the compositor grants focus on hover, which steals it from
    // the focused app (and triggers Qt's `qt.qpa.wayland.textinput` race
    // warning). The bar only needs pointer input (click/scroll); keyboard focus
    // for popups is handled by each popup itself (see BarPopup.grabKeys()).
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Zones where modules are added (from shell.qml or any Bar instance)
    property alias left: leftRow.data
    property alias center: centerRow.data
    property alias right: rightRow.data

    screen: modelData
    color: Qt.rgba(bar.bgColor.r, bar.bgColor.g, bar.bgColor.b, bar.bgOpacity)

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Config.settings.bar.height

    // A Row that vertically centers its children within the bar. A plain Row
    // top-aligns children of differing heights, so anchor each one.
    component Zone: Row {
        spacing: bar.spacing

        Component.onCompleted: {
            for (let i = 0; i < children.length; i++)
                children[i].anchors.verticalCenter = verticalCenter
        }
    }

    // Clicking empty space (or a module without its own handler) dismisses popups
    MouseArea {
        anchors.fill: parent
        onClicked: Popups.closeAll()
    }

    // Escape-to-close is handled centrally by a single ApplicationShortcut in
    // Popups.qml (active whenever any Quickshell window has focus), so it is
    // not repeated here. The bar itself never holds keyboard focus.

    Zone {
        id: leftRow
        anchors.left: parent.left
        anchors.leftMargin: bar.spacing
        anchors.verticalCenter: parent.verticalCenter
    }

    Zone {
        id: centerRow
        anchors.centerIn: parent
    }

    Zone {
        id: rightRow
        anchors.right: parent.right
        anchors.rightMargin: bar.spacing
        anchors.verticalCenter: parent.verticalCenter
    }
}
