import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../popup"

// Context menu for a system tray item. Like BarPopup, it is a layer-shell
// surface (not an xdg popup): a `PanelWindow` on the overlay layer with the
// "z-shell-popup" namespace, so niri gives it the same compositor shadow and
// rounded-corner geometry as the bar popups. The root instance drops below the
// bar centered on its tray icon; submenu instances fly out beside the row that
// opened them. Displayed content is the QsMenuEntry tree from the item's DBus
// menu (separators, icons, check/radio toggles, nested submenus). Only the root
// menu registers with Popups, so closing it cascades to all its children.
PanelWindow {
    id: root

    // QsMenuHandle whose children to display: the tray item's DBusMenuHandle
    // for the root, a submenu DBusMenuItem for each nested level.
    property var menuHandle: null
    // Item this menu is anchored to (the tray icon for the root, a MenuRow
    // otherwise).
    property Item anchorItem: null
    // The menu this one was opened from (null for the root menu).
    property var parentMenu: null
    // True when this popup is a submenu that opens beside its anchor row.
    property bool flyout: false

    // Sizing and spacing
    property int menuGap: 3
    property int minWidth: 220
    property int maxWidth: 340
    property int maxHeight: 500
    property int contentMargin: 8

    // Background appearance, shared with the bar and popups
    property color winColor: Theme.bgColor
    property real winOpacity: Theme.bgOpacity

    // Currently highlighted row (matched by object identity, not index)
    property var focusedRow: null
    // Lazily created submenu (one per menu level)
    property var childMenu: null

    // The bar window for this menu. Submenus resolve it through their parent,
    // so `barWindow` is always the pie bar (whose width == screen width), never
    // a menu window.
    readonly property var barWindow: root.parentMenu
        ? root.parentMenu.barWindow
        : (root.anchorItem ? root.anchorItem.QsWindow.window : null)

    // Pixels reserved by the bar's exclusive zone at the top of the output.
    // Layer-shell margins are measured from the *available* area (below the
    // bar), so they are offset against this when mapping between bar/window and
    // screen coordinates.
    readonly property int topInset: root.barWindow ? root.barWindow.height : 0

    screen: root.barWindow ? root.barWindow.screen : null

    // Anchor the layer surface to the output's top-left; the computed x/y ride
    // on the layer-shell margins (set imperatively in refreshItemPos — the
    // `margins` value type can't be constructed in a binding).
    anchors {
        top: true
        left: true
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "z-shell-popup"
    // OnDemand at rest; briefly flicked to Exclusive on show to grab keyboard
    // focus (replacing PopupWindow's grabFocus, which layer surfaces lack).
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    color: "transparent"
    visible: false

    implicitWidth: Math.min(root.maxWidth, Math.max(root.minWidth,
        column.implicitWidth + root.contentMargin * 2))
    implicitHeight: Math.min(root.maxHeight, column.implicitHeight + root.contentMargin * 2)

    // On explicit show, reposition once the compositor's first configure lands:
    // the window is recreated on every hide and reports width 0 until then.
    onWidthChanged: {
        if (root.visible)
            root.refreshItemPos()
    }
    onHeightChanged: {
        if (root.visible)
            root.refreshItemPos()
    }

    function refreshItemPos() {
        const win = root.barWindow
        if (win === null)
            return
        const mw = root.implicitWidth
        const mh = root.implicitHeight
        const g = root.menuGap
        const maxX = Math.max(0, win.width - mw - g)
        let mx
        let my
        if (root.flyout) {
            // Submenu: fly out to the side of its row. The row's rect is mapped
            // into the parent menu window, then to screen coords via the
            // parent's margins. Margins are in the layer-shell "available area"
            // (below the bar's exclusive zone), and the parent's own margins are
            // measured the same way, so they add directly (no `topInset`).
            const r = root.parentMenu.itemRect(root.anchorItem)
            const ax = root.parentMenu.margins.left + r.x
            const ay = root.parentMenu.margins.top + r.y
            // Open to the right of the row, flip to the left if it would
            // overflow the screen edge.
            mx = ax + r.width + g
            if (mx + mw > win.width)
                mx = ax - mw - g
            mx = Math.max(0, Math.min(mx, maxX))
            // Keep the submenu inside the available area (any other top layer
            // surfaces, e.g. waybar, only reserve more, which niri clamps).
            const availH = win.screen.height - root.topInset
            my = Math.max(0, Math.min(ay, availH - mh - g))
        } else {
            // Root: drop below the bar, centered on the tray icon.
            const rect = win.itemRect(root.anchorItem)
            mx = Math.max(0, Math.min(rect.x + rect.width / 2 - mw / 2, maxX))
            my = g
        }
        if (root.margins.left !== mx)
            root.margins.left = mx
        if (root.margins.top !== my)
            root.margins.top = my
    }

    // Grab keyboard focus for the 90ms flick, mirroring PopupWindow's
    // grabFocus so the arrow keys work right after a menu opens.
    function grabKeys() {
        root.WlrLayershell.keyboardFocus = WlrKeyboardFocus.Exclusive
        keyGrabTimer.restart()
    }

    Timer {
        id: keyGrabTimer
        interval: 90
        repeat: false
        onTriggered: root.WlrLayershell.keyboardFocus = WlrKeyboardFocus.OnDemand
    }

    onVisibleChanged: {
        if (root.visible) {
            root.refreshItemPos()
            if (root.parentMenu === null)
                Popups.open(root)
            root.focusedRow = root.rowAt(root.findNext(-1, 1))
            root.grabKeys()
        } else {
            if (root.childMenu)
                root.childMenu.visible = false
            if (root.parentMenu === null) {
                Popups.close(root)
            } else if (root.parentMenu.visible) {
                // Submenu closed: give keyboard focus back to its parent.
                root.parentMenu.grabKeys()
            }
        }
    }

    // Themed popup background (rounded corners + border, same as BarPopup)
    Rectangle {
        anchors.fill: parent
        radius: Theme.popupRadius
        color: Qt.rgba(root.winColor.r, root.winColor.g, root.winColor.b, root.winOpacity)
        border.width: Theme.popupBorderWidth
        border.color: Theme.popupBorderColor
    }

    // Clicking the popup backdrop (anywhere not on a row) dismisses this menu
    MouseArea {
        anchors.fill: parent
        onClicked: root.visible = false
    }

    // Menu item model: children of the attached handle
    QsMenuOpener {
        id: opener
        menu: root.menuHandle
    }

    // Transparent focus item for keyboard navigation
    Item {
        id: keyHandler
        focus: root.visible

        Keys.onUpPressed: root.moveFocus(-1)
        Keys.onDownPressed: root.moveFocus(1)
        Keys.onReturnPressed: root.activateFocused()
        Keys.onEnterPressed: root.activateFocused()
        Keys.onSpacePressed: root.activateFocused()
        Keys.onRightPressed: root.focusRight()
        Keys.onLeftPressed: if (root.flyout) root.visible = false
        Keys.onEscapePressed: root.visible = false
        Keys.onTabPressed: (event) => {
            root.moveFocus(event.modifiers & Qt.ShiftModifier ? -1 : 1)
            event.accepted = true
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: root.contentMargin
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: column
            width: flick.width
            spacing: 2

            Repeater {
                id: rowsRepeater
                model: opener.children

                delegate: MenuRow {
                    id: rowItem
                    width: column.width
                    menu: root
                    focused: rowItem === root.focusedRow
                }
            }
        }
    }

    // Open/repoint the child submenu anchored to `row`
    function openSubmenu(row) {
        if (row === null || !row.rowEnabled)
            return
        if (root.childMenu) {
            if (root.childMenu.visible && root.childMenu.anchorItem === row)
                return
            root.childMenu.visible = false
        } else {
            const comp = Qt.createComponent("TrayMenu.qml")
            if (comp.status !== Component.Ready) {
                console.error("TrayMenu: failed to load submenu component:", comp.errorString())
                return
            }
            root.childMenu = comp.createObject(root, {
                menuHandle: row.entry,
                anchorItem: row,
                flyout: true
            })
            if (root.childMenu === null)
                return
        }
        root.childMenu.parentMenu = root
        root.childMenu.menuHandle = row.entry
        root.childMenu.anchorItem = row
        root.childMenu.flyout = true
        root.childMenu.visible = true
    }

    function rowAt(i) {
        return i >= 0 && i < rowsRepeater.count ? rowsRepeater.itemAt(i) : null
    }

    function isSelectable(row) {
        return row !== null && !row.rowSeparator && row.rowEnabled
    }

    // Index of the next selectable row after `from` in the given direction
    function findNext(from, step) {
        const count = rowsRepeater.count
        if (count === 0)
            return -1
        let i = from
        for (let n = 0; n < count; n++) {
            i = (i + step + count) % count
            if (root.isSelectable(root.rowAt(i)))
                return i
        }
        return -1
    }

    function moveFocus(step) {
        const count = rowsRepeater.count
        if (count === 0)
            return
        let from = -1
        for (let i = 0; i < count; i++) {
            if (rowsRepeater.itemAt(i) === root.focusedRow) {
                from = i
                break
            }
        }
        if (from < 0)
            from = step > 0 ? -1 : count
        root.focusedRow = root.rowAt(root.findNext(from, step))
    }

    function activateFocused() {
        root.rowClicked(root.focusedRow)
    }

    function focusRight() {
        const row = root.focusedRow
        if (row !== null && row.entry.hasChildren)
            root.openSubmenu(row)
    }

    // Mouse hover on a row: track it as the focused row and switch the open
    // submenu to match the hovered row.
    function rowHovered(row) {
        if (row === null || row.rowSeparator)
            return
        root.focusedRow = row
        if (root.childMenu && root.childMenu.visible && root.childMenu.anchorItem !== row)
            root.childMenu.visible = false
        if (row.entry.hasChildren && row.rowEnabled)
            root.openSubmenu(row)
    }

    // Activation: submenu rows open the submenu, leaf rows trigger the entry
    // and dismiss the whole menu tree.
    function rowClicked(row) {
        if (row === null || row.rowSeparator || !row.rowEnabled)
            return
        if (row.entry.hasChildren) {
            root.openSubmenu(row)
        } else {
            row.entry.triggered()
            root.closeTree()
        }
    }

    // Hide the root menu (cascading through every open submenu)
    function closeTree() {
        let menu = root
        while (menu.parentMenu)
            menu = menu.parentMenu
        menu.visible = false
    }
}