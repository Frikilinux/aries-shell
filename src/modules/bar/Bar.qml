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

    // The bar is an always-visible surface, so normally it must NOT take
    // keyboard focus: Exclusive would steal the focused app's input, and even
    // OnDemand grants focus on hover (the documented `qt.qpa.wayland.textinput`
    // race). The bar only needs pointer input (click/scroll); keyboard focus
    // for popups is handled by each popup itself (see BarPopup.grabKeys()).
    //
    // Bound exception: while a popup is open, OnDemand hands the keyboard to
    // whichever shell surface the pointer rests on — hovering the bar keeps
    // the central Esc-to-close Shortcut (Popups.qml) armed, same as hovering
    // the popup itself. With a popup open the scrim covers every other point
    // of the screen the same way, so no window can be hovered meanwhile; once
    // it closes the binding reverts to None and hovering the bar steals
    // nothing (a keypress goes to the focused app instead of into the bar).
    WlrLayershell.keyboardFocus: Popups.current !== null
        ? WlrKeyboardFocus.OnDemand
        : WlrKeyboardFocus.None

    // Compositor blur behind the bar (colors.blur, ext-background-effect-v1).
    // `null` removes the blur, so the toggle live-updates on config re-apply.
    // Uses the full window geometry: the bar is a plain rect (no rounding).
    BackgroundEffect.blurRegion: Theme.blur ? blurRegion : null

    Region { id: blurRegion; item: bar.contentItem }

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
    // Popups.qml (active whenever any Quickshell surface holds keyboard focus),
    // so it is not repeated here: with a popup open the popup (own focus), the
    // scrim and this bar (OnDemand above) all route keyboard here. Without an
    // open popup the bar is None again and Esc stays with the focused app.

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
