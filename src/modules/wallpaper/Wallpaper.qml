import QtQuick
import Quickshell
import Quickshell.Wayland
import "../config"

// Desktop wallpaper. Per screen, an invisible Item root owns a single
// background-layer surface. niri's existing layer-rule `^wallpaper$` +
// `place-within-backdrop` ALSO moves this surface into the Overview backdrop.
// Backdrop surfaces ignore ALL input, so popup dismissal does NOT live here —
// that's `modules/popup/PopupScrim.qml` (top layer, above windows, below the
// popups).
Item {
    id: root

    required property var modelData

    // Screen filter (shell.qml passes Config.outputs(..., "wallpaper", ...)):
    // undefined/"*" = every screen, name/array = restricted set.
    property var outputs: undefined

    // Wallpaper is drawn on this screen only when it's in the outputs list AND
    // a path is configured (empty path -> surface hidden, back to niri bg color).
    readonly property bool wallVisible: root.onScreen && Config.settings.modules.wallpaper.path !== ""

    readonly property bool onScreen: {
        const o = root.outputs
        if (o === undefined || o === null || o === "*")
            return true
        const list = Array.isArray(o) ? o : [o]
        return list.indexOf(root.modelData.name) !== -1
    }

    // Crop alignment for the configured fillMode ("position" config key).
    readonly property int hAlign: {
        const p = Config.settings.modules.wallpaper.position
        if (p.indexOf("right") !== -1) return Qt.AlignRight
        if (p.indexOf("left") !== -1) return Qt.AlignLeft
        return Qt.AlignHCenter
    }
    readonly property int vAlign: {
        const p = Config.settings.modules.wallpaper.position
        if (p.indexOf("bottom") !== -1) return Qt.AlignBottom
        if (p.indexOf("top") !== -1) return Qt.AlignTop
        return Qt.AlignVCenter
    }

    // QML never expands `~`; make the common `~/.config/...` form work.
    function expandPath(p) {
        if (p.indexOf("~/") === 0)
            return Quickshell.env("HOME") + p.slice(1)
        return p
    }

    // Set a new wallpaper (persist to config + live-apply).
    function set(path) {
        Config.update(s => { s.modules.wallpaper.path = path })
        Config.save()
    }

    PanelWindow {
        id: wall
        screen: root.modelData

        color: "transparent"
        visible: root.wallVisible

        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "wallpaper"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        // Ignore other surfaces' exclusive zones (the bar) -> surface is
        // full-output. niri's `place-within-backdrop` only honors surfaces with
        // exclusive_zone == DontCare (-1); a plain exclusiveZone 0 gets
        // work-area sized, cloned per overview card and slides on workspace
        // switch instead of becoming the fixed backdrop.
        exclusionMode: ExclusionMode.Ignore

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Image {
            anchors.fill: parent
            source: root.expandPath(Config.settings.modules.wallpaper.path)
            visible: root.wallVisible
            smooth: true
            mipmap: true
            // Decode at the output size instead of the file's natural size: a
            // 4K photo no longer costs full-res RAM. With PreserveAspectCrop Qt
            // scales to the optimal crop size, keeping the aspect ratio intact.
            // Bound to the stable screen size so it doesn't reload from a
            // transient 0x0 at surface creation.
            sourceSize.width: root.modelData.width
            sourceSize.height: root.modelData.height
            fillMode: {
                switch (Config.settings.modules.wallpaper.fillMode) {
                case "stretch": return Image.Stretch
                case "fit": return Image.PreserveAspectFit
                default: return Image.PreserveAspectCrop
                }
            }
            horizontalAlignment: root.hAlign
            verticalAlignment: root.vAlign
        }

        // Optional dimming overlay (contrast for workspaces/text over a bright image).
        Rectangle {
            anchors.fill: parent
            visible: root.wallVisible
            color: "#000000"
            opacity: Config.settings.modules.wallpaper.dim
        }
    }
}
