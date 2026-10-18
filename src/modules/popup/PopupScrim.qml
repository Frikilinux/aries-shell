import QtQuick
import Quickshell
import Quickshell.Wayland
import "../config"

// Transparent click-catcher shown while a popup/tray menu is open (`Popups.current
// !== null`), one surface per screen. Lives next to the popup machinery it serves
// (Popups.qml / BarPopup.qml); it used to be inline in Wallpaper.qml, which only
// hosted it because it needed a per-screen window.
//
// The layer sandwich is the whole point: this scrim sits on the Top layer, i.e.
// ABOVE normal windows but BELOW the Overlay-layer popups/menus, so while a
// popup is open an outside click always lands on the scrim (-> closeAll) and
// hover never reaches a window underneath. That second part is what keeps niri's
// focus-follows-mouse from retargeting focus on plain hover — which is why
// popups must NOT be dismissed on WindowFocusChanged (see Niri.qml); covering
// the windows IS the fix. Fullscreen windows render above Top, so they can't be
// covered (same limitation the bar has).
//
// The bar strip is left uncovered (geometry below), so the bar keeps its own
// clicks while two Top surfaces that never overlap don't care about stacking.
//
// Focus note: OnDemand (not None) means the surface holds Wayland keyboard
// focus while the pointer is over it, so hovering the SCRIM (outside the popup)
// routes keyboard to the shell and the central ApplicationShortcut in Popups.qml
// closes the popups with Esc — mirroring what happens when hovering the popup
// itself. While a popup is already open the user isn't typing into an app, so
// nothing is being stolen.
Item {
    id: root

    required property var modelData

    PanelWindow {
        id: scrim
        screen: root.modelData

        color: "transparent"
        // Cover EVERY screen while a popup/menu is open. Limiting this to the
        // popup's own screen left the other outputs uncovered, so moving the
        // pointer onto a window there hit focus-follows-mouse (focus change ->
        // popup closed). A popup is modal, so covering all outputs is correct.
        visible: Popups.current !== null

        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "aries-scrim"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        // Never reserve space and never dodge other panels (bar included): the
        // geometry below is exact, and windows are never pushed around.
        exclusionMode: ExclusionMode.Ignore

        // Full width, from just under the bar down to the bottom edge, so the
        // bar strip stays free for its own clicks (toggle/close popups).
        anchors {
            bottom: true
            left: true
            right: true
        }
        implicitHeight: root.modelData.height - Config.settings.bar.height

        // Any click outside the popup/menu: close it.
        MouseArea {
            anchors.fill: parent
            onClicked: Popups.closeAll()
        }
    }
}
