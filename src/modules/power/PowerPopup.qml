import QtQuick
import "../theme"
import "../icon"
import "../popup"
import "../niri"

BarPopup {
    id: popup

    // Icon style used by this popup's icons. Defaults to Theme.iconStyle.
    property string iconStyle: Theme.iconStyle

    // tileWidth is the minimum; tiles grow to fit the widest action label.
    property int tileWidth: 84
    property int tileHeight: 62
    property int tileSpacing: 8
    // Horizontal padding inside a tile so labels don't touch its edges/border
    property int tilePadding: 8
    property int confirmSeconds: 10

    // Destructive action awaiting confirmation, "" when idle
    property string pendingAction: ""
    property int countdown: confirmSeconds
    readonly property int confirmTotal: confirmSeconds

    // Confirmation panel: both buttons share the width of the longest label
    // (+ padding), keeping the panel as narrow as the buttons allow.
    property int buttonPadding: 14
    property int buttonSpacing: 8
    property int buttonHeight: 32

    // Actions available on this system: shutdown/restart always, sleep and
    // hibernate only when the kernel advertises them in /sys/power/state,
    // logout only when there is a niri session to quit.
    readonly property var actions: {
        const list = ["shutdown", "restart"]
        if (PowerService.canHibernate)
            list.push("hibernate")
        if (PowerService.canSuspend)
            list.push("sleep")
        if (Niri.available)
            list.push("logout")
        return list
    }
    readonly property int actionCount: actions.length

    // Keyboard navigation state: index of the focused item within the current
    // view (the action tile row, or the confirm panel's Cancel / "Now" buttons)
    property int rowFocus: 0
    readonly property bool confirmVisible: popup.pendingAction !== ""
    readonly property int tileFocused: popup.confirmVisible ? -1 : popup.rowFocus
    readonly property int confirmIndex: popup.confirmVisible ? popup.rowFocus : -1

    // Tile currently selected by the keyboard (matched by action name, not index)
    readonly property string focusedAction: popup.tileFocused >= 0 ? popup.actions[popup.tileFocused] : ""

    // Action tiles: all share the width of the widest label (+ padding) so no
    // label is elided; `tileWidth` acts as the minimum.
    FontMetrics {
        id: tileLabelMetrics
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 2
    }

    readonly property string longestActionLabel: {
        let best = ""
        let bestWidth = -1
        for (const a of popup.actions) {
            const label = popup.actionLabel(a)
            const width = tileLabelMetrics.advanceWidth(label)
            if (width > bestWidth) {
                bestWidth = width
                best = label
            }
        }
        return best
    }

    readonly property real tileDisplayWidth: Math.max(tileWidth,
        Math.ceil(tileLabelMetrics.advanceWidth(popup.longestActionLabel)) + 2 * tilePadding)

    // Label of the confirming action, used to size both buttons.
    readonly property string confirmLabel: popup.pendingAction === "shutdown"
        ? "Shut Down Now" : "Restart Now"

    // Buttons take the width of the widest rendered label (Text.implicitWidth,
    // the exact width used for eliding) plus padding, so the label is never
    // cut. Both buttons end up equal.
    readonly property real confirmButtonWidth: Math.ceil(Math.max(
        cancelButton.labelWidth, confirmButton.labelWidth)) + 2 * popup.buttonPadding
    readonly property real confirmButtonsWidth: 2 * popup.confirmButtonWidth
        + popup.buttonSpacing

    // Wide on the action tile row; on the confirmation panel narrowed to the
    // buttons (or the countdown line, whichever needs more room).
    popupWidth: popup.confirmVisible
        ? Math.round(Math.max(popup.confirmButtonsWidth, countdownText.implicitWidth)) + 24
        : actionCount * (tileDisplayWidth + tileSpacing) - tileSpacing + 24

    function actionLabel(action) {
        switch (action) {
        case "shutdown":
            return "Shut Down"
        case "restart":
            return "Restart"
        case "sleep":
            return "Sleep"
        case "hibernate":
            return "Hibernate"
        case "logout":
            return "Log Out"
        }
        return ""
    }

    function actionGlyph(action) {
        switch (action) {
        case "shutdown":
            return "\ue035" // power
        case "restart":
            return "\ue01a" // arrow-clockwise (rotate)
        case "sleep":
            return "\ue051" // weather-moon
        case "hibernate":
            return "\ue05c" // weather-snowflake
        case "logout":
            return "\ue037" // sign-out
        }
        return "\ue035"
    }

    function beginConfirm(action) {
        if (action === "shutdown" || action === "restart") {
            popup.pendingAction = action
            popup.rowFocus = 0
            popup.countdown = popup.confirmSeconds
            confirmTimer.restart()
        } else {
            if (action === "logout")
                Niri.quit()
            else
                PowerService.execute(action)
            popup.visible = false
        }
    }

    function cancelPending() {
        confirmTimer.stop()
        popup.pendingAction = ""
        popup.countdown = popup.confirmSeconds
    }

    function confirmPending() {
        confirmTimer.stop()
        const act = popup.pendingAction
        popup.pendingAction = ""
        if (act !== "")
            PowerService.execute(act)
        popup.visible = false
    }

    // Move keyboard focus to the neighbouring tile/button (wraps around)
    function moveFocus(step) {
        const count = popup.confirmVisible ? 2 : popup.actionCount
        popup.rowFocus = (popup.rowFocus + step + count) % count
    }

    // Activate the keyboard-focused control
    function activateFocused() {
        if (popup.confirmVisible) {
            if (popup.rowFocus === 0)
                popup.cancelPending()
            else
                popup.confirmPending()
        } else {
            popup.beginConfirm(popup.actions[popup.rowFocus])
        }
    }

    function popupOpened() {
        PowerService.refresh()
        popup.rowFocus = 0
    }

    function popupClosed() {
        cancelPending()
        popup.rowFocus = 0
    }

    Timer {
        id: confirmTimer
        interval: 1000
        repeat: true
        onTriggered: {
            popup.countdown = Math.max(0, popup.countdown - 1)
            if (popup.countdown <= 0)
                popup.confirmPending()
        }
    }

    // Transparent focus item: arrows/tab move the selection, enter/space
    // activates it. Kept focused while the popup is open so keys land here
    // regardless of where the mouse click that opened it happened. It lives in
    // the content Column (zero-size is fine: it only needs keyboard focus).
    Item {
        id: keyHandler
        focus: popup.visible

        Keys.onLeftPressed: popup.moveFocus(-1)
        Keys.onUpPressed: popup.moveFocus(-1)
        Keys.onRightPressed: popup.moveFocus(1)
        Keys.onDownPressed: popup.moveFocus(1)
        Keys.onTabPressed: event => {
            popup.moveFocus(event.modifiers & Qt.ShiftModifier ? -1 : 1)
            event.accepted = true
        }
        Keys.onReturnPressed: popup.activateFocused()
        Keys.onEnterPressed: popup.activateFocused()
        Keys.onSpacePressed: popup.activateFocused()
    }

    // Horizontal action tiles
    Row {
        visible: popup.pendingAction === ""
        width: popup.contentWidth
        spacing: popup.tileSpacing

        Repeater {
            model: popup.actions

            delegate: Rectangle {
                id: tile
                required property string modelData

                readonly property bool focused: tile.modelData === popup.focusedAction

                width: popup.tileDisplayWidth
                height: popup.tileHeight
                radius: 6
                color: tileMouse.containsMouse || tile.focused
                    ? Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.12)
                    : "transparent"
                border.width: tile.focused ? 1 : 0
                border.color: Theme.accentColor

                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: popup.tilePadding
                    anchors.rightMargin: popup.tilePadding
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        glyph: popup.actionGlyph(tile.modelData)
                        style: popup.iconStyle
                        font.pixelSize: Theme.iconSize + 8
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: popup.actionLabel(tile.modelData)
                        color: Theme.fgColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: tileMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: popup.beginConfirm(tile.modelData)
                }
            }
        }
    }

    // Confirmation panel (shutdown / restart)
    Column {
        visible: popup.pendingAction !== ""
        width: popup.contentWidth
        spacing: 8

        Text {
            id: countdownText
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: popup.pendingAction === "shutdown"
                ? "Shut down in " + popup.countdown + "s\u2026"
                : "Restart in " + popup.countdown + "s\u2026"
            color: Theme.fgColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
            font.features: ({ "tnum": 1 })
        }

        // Countdown progress bar
        Rectangle {
            width: parent.width
            height: 3
            radius: 1.5
            color: Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.15)

            Rectangle {
                width: parent.width * popup.countdown / popup.confirmTotal
                height: parent.height
                radius: 1.5
                color: Theme.accentColor

                Behavior on width {
                    NumberAnimation {
                        duration: 150
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: popup.buttonHeight

            Row {
                id: confirmButtons
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                height: popup.buttonHeight
                spacing: popup.buttonSpacing

                // Cancel
                Rectangle {
                    id: cancelButton
                    readonly property real labelWidth: cancelText.implicitWidth

                    width: popup.confirmButtonWidth
                    height: parent.height
                    radius: 6
                    color: cancelMouse.containsMouse || popup.confirmIndex === 0
                        ? Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.18)
                        : Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.08)
                    border.width: 1
                    border.color: popup.confirmIndex === 0
                        ? Theme.accentColor
                        : Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.25)

                    Text {
                        id: cancelText
                        anchors.centerIn: parent
                        text: "Cancel"
                        color: Theme.fgColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }

                    MouseArea {
                        id: cancelMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: popup.cancelPending()
                    }
                }

                // Confirm now
                Rectangle {
                    id: confirmButton
                    readonly property real labelWidth: confirmText.implicitWidth

                    width: popup.confirmButtonWidth
                    height: parent.height
                    radius: 6
                    color: Theme.accentColor
                    opacity: confirmMouse.containsMouse || popup.confirmIndex === 1 ? 0.9 : 1
                    border.width: popup.confirmIndex === 1 ? 1 : 0
                    border.color: Theme.fgColor

                    Text {
                        id: confirmText
                        anchors.centerIn: parent
                        text: popup.confirmLabel
                        color: Theme.fgColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        font.bold: true
                    }

                    MouseArea {
                        id: confirmMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: popup.confirmPending()
                    }
                }
            }
        }
    }
}
