import QtQuick
import Quickshell.Wayland
import "../theme"
import "../config"

Item {
    id: root

    // Show this module only on specific outputs (monitors).
    // Set to a string ("HDMI-A-1") or array (["eDP-1"]). If undefined/null, shows on all.
    property var outputs
    // The output being rendered.
    required property string output

    // Display-name overrides per appId (see AppNames.qml)
    AppNames { id: appNames }

    // Max width (px) the label before it truncates instead of overflowing
    property int maxLabelWidth: Config.settings.modules.activeWindow.maxLabelWidth

    // The toplevel currently focused on this module's screen (null if none)
    readonly property var focusedToplevel: root._focusedToplevel

    // Name shown for the focused window. Uses the displayName override for the
    // appId when one is configured (AppNames.qml); otherwise capitalizes the
    // appId, falling back to the window title when the app has no appId
    // (e.g. some XWayland clients).
    readonly property string label: {
        if (!root.focusedToplevel)
            return ""
        const appId = root.focusedToplevel.appId || root.focusedToplevel.title
        return root.capitalize(appNames.displayName(appId))
    }

    // Internal: the toplevel chosen by updateFocused()
    property var _focusedToplevel: null

    implicitWidth: textLabel.implicitWidth
    implicitHeight: textLabel.implicitHeight

    // Module is visible only if outputs property is unset, matches this output, or contains it
    visible: !outputs || (Array.isArray(outputs) ? outputs.includes(output) : outputs === output)

    Text {
        id: textLabel
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        color: Theme.fgBarColor
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.styleName: "Bold"
        maximumLineCount: 1
        elide: Text.ElideRight
        width: Math.min(implicitWidth, root.maxLabelWidth)
    }

    // Watch every open toplevel. The delegate only reacts to the one that is
    // focused AND on this screen; it updates the module's _focusedToplevel.
    Repeater {
        id: watch
        model: ToplevelManager.toplevels

        delegate: Item {
            id: del
            required property var modelData

            readonly property var toplevel: modelData
            readonly property bool onScreen: toplevel.screens.some(s => !!s && s.name === root.output)
            readonly property bool isFocused: toplevel.activated && onScreen

            // Re-evaluate whenever focus, screens, or the model change
            onIsFocusedChanged: root.updateFocused()
            onOnScreenChanged: root.updateFocused()
            Component.onCompleted: root.updateFocused()

            Connections {
                target: toplevel
                function onActivatedChanged() { root.updateFocused() }
                function onScreensChanged() { root.updateFocused() }
                function onClosed() { root.clearFocused(del) }
            }
        }
    }

    // Pick the first toplevel that is focused on this screen (there should be
    // only one, but guard against duplicates). Called on every relevant change.
    function updateFocused() {
        for (let i = 0; i < watch.count; i++) {
            const d = watch.itemAt(i)
            if (d && d.isFocused) {
                if (root._focusedToplevel !== d.toplevel)
                    root._focusedToplevel = d.toplevel
                return
            }
        }
        root._focusedToplevel = null
    }

    // A watched toplevel was closed (window/menu exited): forget it if it was
    // the one being shown, then re-evaluate with the remaining toplevels.
    function clearFocused(del) {
        if (root._focusedToplevel === del.toplevel)
            root.updateFocused()
    }

    // Upper-case the first letter of the name and of each segment split by
    // separators (".", "-", "_", "/", " "), e.g. "org.wezfurlong.wezterm" ->
    // "Org.Wezfurlong.Wezterm", "firefox" -> "Firefox".
    function capitalize(name) {
        if (!name)
            return name
        return name.replace(/(^|[.\-_\/ ])([a-zA-Z0-9])/g, (m, sep, ch) => sep + ch.toUpperCase())
    }
}