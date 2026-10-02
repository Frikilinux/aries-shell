import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../icon"
import "../config"
import "../niri"
import "../widgets"

// Graphical polkit authentication dialog.
//
// One overlay surface per screen, created in shell.qml via `Variants` and
// filtered by `Config.outputs("polkit")` (default: all screens). It renders
// PolkitService's active flow (the requesting action, message, PAM prompts and
// errors) and submits the typed response back to the agent. This replaces
// external agents such as polkit-gnome / polkit-kde with a native, themed
// prompt.
//
// Requests are triggered by the system (e.g. `pkexec`, `systemctl`), with no
// click on the bar, so the surface is deliberately modal: it sits on the
// overlay layer (above windows and full-screen windows) and takes exclusive
// keyboard focus while visible. It is shown only on the focused output, so a
// prompt triggered while looking at one monitor does not appear on another.
// Esc, the close button and Cancel all cancel the request (fail closed).
PanelWindow {
    id: dialog

    required property var modelData
    // Screen filter (undefined/"*" = all screens), same rule as the bar modules.
    property var outputs

    readonly property var cfg: Config.settings.modules.polkit
    // The active authentication flow (null when idle), owned by PolkitService.
    readonly property var flow: PolkitService.flow

    readonly property bool onScreen: {
        const o = dialog.outputs
        if (o === undefined || o === null || o === "*")
            return true
        const list = Array.isArray(o) ? o : [o]
        return list.indexOf(modelData.name) !== -1
    }

    // Show only on the focused output. Unknown focus (niri unavailable) falls
    // back to showing rather than hiding, so an auth prompt can never be lost.
    readonly property bool focused: {
        const out = Niri.focusedOutput
        return out === "" || (dialog.screen !== null && dialog.screen.name === out)
    }

    screen: modelData
    visible: dialog.onScreen && PolkitService.active && dialog.focused
    color: "transparent"
    // A modal overlay must never reserve screen space for windows.
    exclusionMode: ExclusionMode.Ignore

    // Anchored top-left; the centred position rides on the layer-shell margins
    // (margins is a value type, so writes are imperative and equality-guarded).
    anchors {
        top: true
        left: true
    }

    WlrLayershell.layer: WlrLayer.Overlay
    // Same ns as the bar popups -> inherits niri's shadow / corner-radius rule.
    WlrLayershell.namespace: "aries-popup"
    // Take the keyboard while the prompt is up so the password can be typed
    // immediately; release it (None) as soon as the dialog hides.
    WlrLayershell.keyboardFocus: dialog.visible
        ? WlrKeyboardFocus.Exclusive
        : WlrKeyboardFocus.None

    readonly property int dialogWidth: 380
    implicitWidth: dialogWidth
    implicitHeight: body.implicitHeight + 24

    // Resolve one axis: "center" (or anything non-numeric) centres the dialog,
    // a number is a pixel offset from the screen's top/left edge.
    function axisPos(value, size, span) {
        if (value === "center")
            return Math.round((span - size) / 2)
        const n = Number(value)
        if (isNaN(n))
            return Math.round((span - size) / 2)
        return Math.round(n)
    }

    // Uses implicit size: width/height stay 0 until the first configure lands.
    function refreshPos() {
        if (!dialog.visible || dialog.screen === null)
            return
        const mx = Math.max(0, Math.min(
            dialog.axisPos(dialog.cfg.x, dialog.implicitWidth, dialog.screen.width),
            dialog.screen.width - dialog.implicitWidth))
        if (dialog.margins.left !== mx)
            dialog.margins.left = mx
        const my = Math.max(0, Math.min(
            dialog.axisPos(dialog.cfg.y, dialog.implicitHeight, dialog.screen.height),
            dialog.screen.height - dialog.implicitHeight))
        if (dialog.margins.top !== my)
            dialog.margins.top = my
    }

    onVisibleChanged: {
        dialog.refreshPos()
        if (dialog.visible)
            Qt.callLater(() => dialog.focusField())
    }
    onWidthChanged: dialog.refreshPos()
    onHeightChanged: dialog.refreshPos()

    // Live config edits (x/y changed while the dialog is up).
    Connections {
        target: Config
        function onRevisionChanged() { dialog.refreshPos() }
    }

    // Clear and refocus whenever the flow asks for a new response: the first
    // prompt, and every retry after a wrong password (a fresh PAM session).
    Connections {
        target: dialog.flow
        function onIsResponseRequiredChanged() {
            if (dialog.flow && dialog.flow.isResponseRequired) {
                field.text = ""
                Qt.callLater(() => dialog.focusField())
            }
        }
    }

    Shortcut {
        sequence: "Escape"
        onActivated: dialog.cancel()
    }

    function focusField() {
        if (field)
            field.forceActiveFocus()
    }

    function submit() {
        if (dialog.flow === null)
            return
        dialog.flow.submit(field.text)
        field.text = ""
        Qt.callLater(() => dialog.focusField())
    }

    function cancel() {
        if (dialog.flow !== null)
            dialog.flow.cancelAuthenticationRequest()
    }

    // Themed background (the window itself stays transparent).
    Rectangle {
        anchors.fill: parent
        radius: Theme.popupRadius
        color: Qt.rgba(Theme.bgColor.r, Theme.bgColor.g, Theme.bgColor.b, Theme.bgOpacity)
        border.width: Theme.popupBorderWidth
        border.color: Theme.popupBorderColor
    }

    Column {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 10

        // Header: shield, title, dismiss.
        Row {
            width: parent.width
            spacing: 8

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                glyph: "\ue081" // shield
                color: Theme.accentColor
                font.pixelSize: Theme.fontSize + 3
            }

            Text {
                width: parent.width - (Theme.fontSize + 3) - 18 - 2 * parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                text: "Authentication Required"
                color: Theme.fgColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
                font.bold: true
                elide: Text.ElideRight
            }

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                horizontalAlignment: Text.AlignHCenter
                glyph: "\ue02f" // dismiss
                color: Theme.fgColorMuted

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: dialog.cancel()
                }
            }
        }

        // What is being authorized.
        Text {
            width: parent.width
            visible: text !== ""
            text: dialog.flow ? dialog.flow.message : ""
            wrapMode: Text.Wrap
            color: Theme.fgColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
        }

        // Machine-readable action id (anti-spoofing: the real requested action).
        Text {
            width: parent.width
            visible: text !== ""
            text: dialog.flow ? dialog.flow.actionId : ""
            elide: Text.ElideRight
            color: Theme.fgColorMuted
            opacity: 0.7
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 4
        }

        // Supplementary info / PAM errors.
        Text {
            width: parent.width
            visible: text !== ""
            text: dialog.flow ? dialog.flow.supplementaryMessage : ""
            wrapMode: Text.Wrap
            color: (dialog.flow && dialog.flow.supplementaryIsError)
                ? Theme.urgentColor
                : Theme.fgColorMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
        }

        // Identity picker, only when the request allows more than one.
        Row {
            width: parent.width
            spacing: 6
            visible: dialog.flow ? dialog.flow.identities.length > 1 : false

            Repeater {
                model: dialog.flow ? dialog.flow.identities : []

                delegate: Chip {
                    required property var modelData
                    text: modelData.displayName || modelData.string
                    active: PolkitService.flow && PolkitService.flow.selectedIdentity === modelData
                    onClicked: PolkitService.flow.selectedIdentity = modelData
                }
            }
        }

        // Prompt label from PAM (typically "Password:").
        Text {
            width: parent.width
            visible: dialog.flow ? dialog.flow.isResponseRequired : false
            text: (dialog.flow && dialog.flow.inputPrompt !== "")
                ? dialog.flow.inputPrompt
                : "Password"
            elide: Text.ElideRight
            color: Theme.fgColorMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 3
        }

        // Response field (hidden for info-only turns until a response is asked).
        Rectangle {
            width: parent.width
            height: 34
            radius: 4
            visible: dialog.flow ? dialog.flow.isResponseRequired : false
            color: Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.06)
            border.width: 1
            border.color: (dialog.flow && dialog.flow.failed)
                ? Theme.urgentColor
                : Theme.buttonBorder

            Text {
                anchors.fill: parent
                anchors.leftMargin: 10
                verticalAlignment: Text.AlignVCenter
                visible: field.text === ""
                text: "Password"
                color: Theme.fgColorMuted
                opacity: 0.5
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }

            TextInput {
                id: field
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                // PAM decides whether the response may be shown (e.g. a
                // non-secret answer); passwords stay masked.
                echoMode: (dialog.flow && dialog.flow.responseVisible)
                    ? TextInput.Normal
                    : TextInput.Password
                color: Theme.fgColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
                selectByMouse: true
                onAccepted: dialog.submit()
            }
        }

        // Failure feedback (stays visible across retries, like the reference).
        Text {
            width: parent.width
            visible: dialog.flow ? dialog.flow.failed : false
            text: "Authentication failed. Please try again."
            wrapMode: Text.Wrap
            color: Theme.urgentColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 3
        }

        // Actions, right-aligned.
        Item {
            width: parent.width
            height: 30

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                DialogButton {
                    label: "Cancel"
                    onClicked: dialog.cancel()
                }

                DialogButton {
                    label: "Authenticate"
                    primary: true
                    enabled: field.text.length > 0
                    onClicked: dialog.submit()
                }
            }
        }
    }

    // Local button: primary (filled) vs secondary (outlined). Uses the built-in
    // Item.enabled (disables the MouseArea via inheritance) for the disabled
    // state.
    component DialogButton: Rectangle {
        id: button

        property string label: ""
        property bool primary: false

        signal clicked()

        implicitWidth: Math.max(74, buttonLabel.implicitWidth + 24)
        implicitHeight: 30
        radius: 4
        color: button.primary ? Theme.buttonPrimaryBgColor : Theme.buttonBgColor
        border.width: button.primary ? 0 : 1
        border.color: Theme.buttonBorder
        opacity: button.enabled ? 1 : 0.5

        Text {
            id: buttonLabel
            anchors.centerIn: parent
            text: button.label
            color: Theme.fgColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 3
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: button.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: button.clicked()
        }
    }
}
