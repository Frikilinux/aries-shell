import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"

// Base popup for bar modules. Handles the shared plumbing (anchor positioning,
// themed background, scrollable content column, dismissal registry) so modules
// only declare their specific properties, functions and content. Children
// declared on an instance are laid out in the content column.
//
// Popups are layer-shell surfaces (not xdg popups): a `PanelWindow` on the
// overlay layer with namespace "aries-popup". This lets niri shadow them via
// a layer rule (niri renders no compositor shadows for xdg popups) and avoids
// the `popups {}` blocks, which only apply to real xdg popups. Position rides
// on the layer-shell margins (anchored to the screen's top-left).
PanelWindow {
    id: popup

    // Bar item the popup is anchored to
    required property Item anchorItem

    // Separation between the popup and the bar / the screen edge
    property int popupGap: 3

    // Popup dimensions
    property int popupWidth: 340
    property int maxContentHeight: 540

    // Background appearance, shared with the bar (colors.bg + colors.opacity)
    property color winColor: Theme.bgColor
    property real winOpacity: Theme.bgOpacity

    // Instances add their content here (laid out in the scrollable column)
    default property alias content: column.data

    // Width available to the content column
    readonly property real contentWidth: column.width

    // The bar window containing the anchor item. Layer-shell margins position
    // the popup relative to the screen, and the bar sits at the screen's
    // top-left edge, so bar coordinates == screen coordinates.
    readonly property var barWindow: popup.anchorItem ? popup.anchorItem.QsWindow.window : null

    // Largest x (screen/bar coordinates) that keeps the popup off the screen edge.
    // Centring uses `implicitWidth` (the desired, final width), never `width`:
    // a freshly-created layer-shell window reports width 0 until the compositor
    // sends its first configure, which arrives asynchronously after `visible`
    // flips true (WlrLayershell.trySetWidth is a no-op that only re-schedules
    // a polish, so the size only comes from the compositor's configure).
    readonly property real maxX: popup.barWindow
        ? popup.barWindow.width - popup.implicitWidth - popup.popupGap
        : Infinity

    screen: popup.barWindow ? popup.barWindow.screen : null

    // Anchor the layer surface to the screen's top-left; the computed x/y ride
    // on the layer-shell margins (set imperatively in refreshItemPos — the
    // `margins` value type can't be constructed in a binding).
    anchors {
        top: true
        left: true
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "aries-popup"
    // Accept keys while the popup is open (e.g. the Wi-Fi password prompt).
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    visible: false
    color: "transparent"
    implicitWidth: popupWidth
    implicitHeight: Math.min(column.implicitHeight + 24, maxContentHeight)

    // Override in instances to run extra logic when shown / hidden.
    function popupOpened() {}
    function popupClosed() {}

    onVisibleChanged: {
        if (visible) {
            popup.refreshItemPos()
            Popups.open(popup)
            popup.popupOpened()
        } else {
            Popups.close(popup)
            popup.popupClosed()
        }
    }

    // On explicit show, recentre once the compositor's first configure lands:
    // the window is recreated on every hide and reports width 0 until then.
    onWidthChanged: {
        if (popup.visible)
            popup.refreshItemPos()
    }

    function refreshItemPos() {
        const win = popup.barWindow
        if (win === null)
            return
        const rect = win.itemRect(popup.anchorItem)
        // Centred on the anchor item horizontally; vertical offset is just
        // `popupGap` from the screen's top edge (top-anchored layer surface).
        const mx = Math.max(0, Math.min(rect.x + rect.width / 2 - popup.implicitWidth / 2, popup.maxX))
        if (popup.margins.left !== mx)
            popup.margins.left = mx
        const my = popup.popupGap
        if (popup.margins.top !== my)
            popup.margins.top = my
    }

    Shortcut {
        sequence: "Escape"
        onActivated: popup.visible = false
    }

    // Themed popup background (rounded corners + border)
    Rectangle {
        anchors.fill: parent
        radius: Theme.popupRadius
        color: Qt.rgba(popup.winColor.r, popup.winColor.g, popup.winColor.b, popup.winOpacity)
        border.width: Theme.popupBorderWidth
        border.color: Theme.popupBorderColor
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: 12
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: column
            width: flick.width
            spacing: 6
        }
    }
}
