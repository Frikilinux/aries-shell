import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../config"

// Toast stack: one overlay surface per screen that renders the notifications
// currently being shown, newest on top, as a single block. Independent from the
// bar popups (namespace "notifications", matching the niri layer rule), so it
// never participates in Popups dismissal and needs no anchor item.
PanelWindow {
    id: toast

    required property var modelData

    // Screen filter, same semantics as the bar modules (undefined/"*" = all).
    property var outputs

    readonly property var notifCfg: Config.settings.modules.notifications
    readonly property int toastWidth: 360
    // Padding between the block edge and the cards (also the inter-card gutter).
    readonly property int edgeMargin: 6
    // Outer block radius (matches niri's `geometry-corner-radius 13`).
    readonly property int panelRadius: Theme.popupRadius
    // Cards are inset by `edgeMargin`, so their radius is reduced by the same
    // amount to stay concentric with the block and look proportional to it.
    readonly property int cardRadius: Math.max(0, toast.panelRadius - toast.edgeMargin)
    // Cap the stack so a flood of notifications never fills the screen; the
    // service already bounds the number of live toasts.
    readonly property int maxHeight: toast.screen ? Math.round(toast.screen.height * 0.66) : 800

    readonly property bool onScreen: {
        const o = toast.outputs
        if (o === undefined || o === null || o === "*")
            return true
        const list = Array.isArray(o) ? o : [o]
        return list.indexOf(modelData.name) !== -1
    }

    screen: modelData

    visible: toast.onScreen && NotificationService.popups.length > 0
    color: "transparent"
    // A transient overlay must never reserve screen space.
    exclusionMode: ExclusionMode.Ignore

    // Anchored top-left like the rest of the shell; the right alignment rides on
    // the computed left margin (bar coordinates == screen coordinates).
    anchors {
        top: true
        left: true
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "notifications"
    // Purely informational: never takes keyboard focus.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    implicitWidth: toast.toastWidth
    implicitHeight: Math.min(stack.implicitHeight + toast.edgeMargin * 2, toast.maxHeight)

    // Position from Config: `position.x` is the gap to the right edge,
    // `position.y` the gap to the top edge.
    function refreshPos() {
        if (!toast.visible || toast.screen === null)
            return
        const px = Number(toast.notifCfg.position.x)
        const py = Number(toast.notifCfg.position.y)
        const x = isNaN(px) ? 6 : px
        const y = isNaN(py) ? 36 : py
        const mx = Math.max(0, toast.screen.width - toast.implicitWidth - x)
        if (toast.margins.left !== mx)
            toast.margins.left = mx
        const maxTop = Math.max(0, toast.screen.height - toast.implicitHeight)
        const my = Math.max(0, Math.min(y, maxTop))
        if (toast.margins.top !== my)
            toast.margins.top = my
    }

    onVisibleChanged: toast.refreshPos()
    onWidthChanged: toast.refreshPos()
    onHeightChanged: toast.refreshPos()

    // Live config edits (position changed while toasts are up).
    Connections {
        target: Config
        function onRevisionChanged() { toast.refreshPos() }
    }

    // Solid block background filling the whole surface: no transparent margin or
    // gap for niri's blur to bleed through (niri rounds the outer corners via
    // the `^notifications$` layer rule).
    Rectangle {
        anchors.fill: parent
        radius: toast.panelRadius
        color: Qt.rgba(Theme.bgColor.r, Theme.bgColor.g, Theme.bgColor.b, Theme.bgOpacity)
        border.width: Theme.popupBorderWidth
        border.color: Theme.popupBorderColor
    }

    Column {
        id: stack
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: toast.edgeMargin
        spacing: 6

        Repeater {
            model: NotificationService.popups
            delegate: NotificationCard {
                width: stack.width
                radius: toast.cardRadius
            }
        }
    }
}
