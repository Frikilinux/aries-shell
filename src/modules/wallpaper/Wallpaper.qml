import QtQuick
import Quickshell
import Quickshell.Wayland
import "../config"
import "../popup"

// Desktop wallpaper + empty-desktop click-catcher, combined into one module so
// a single Variants block serves both (invisible Item root owning the two
// windows). Two layer-shell surfaces per screen:
//
//  * wallpaper (Background layer, ns "wallpaper"): renders the configured image
//    behind windows. niri's existing layer-rule `^wallpaper$` +
//    `place-within-backdrop` ALSO moves this surface into the Overview backdrop.
//    Backdrop surfaces ignore ALL input, so popup dismissal can never live here
//    — that's what the scrim surface is for.
//
//  * scrim (Top layer, ns "aries-scrim"): transparent full-screen layer shown
//    only while a popup/tray menu is open. It sits ABOVE windows but BELOW the
//    Overlay-layer popups, so while a popup is open hover never reaches a
//    window (focus-follows-mouse can't retarget focus), a click outside the
//    popup closes it, and the popups themselves stay fully interactive. The bar
//    strip is left uncovered, so the bar keeps its own clicks. Its unique
//    namespace lets niri's layer-rules skip the global blur/shadow for it.
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

    // ---------------------------------------------------------------- wallpaper
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

    // ------------------------------------------------------------------- scrim
    // Transparent layer surface shown while a bar popup or tray menu is open
    // (`Popups.current != null`): it covers the whole screen below the bar, so
    // a click anywhere outside the popup dismisses it AND hover never reaches a
    // window underneath. niri's focus-follows-mouse fires WindowFocusChanged on
    // plain hover (and already focuses windows before any click), so popups must
    // NOT dismiss on focus change — only on actual input; covering the windows
    // is also what keeps the mouse from retargeting focus while a popup is open.
    // Top layer puts it above windows but below the Overlay-layer popups/menus
    // (which therefore keep receiving input). The bar strip is excluded
    // geometrically, so the two Top surfaces never overlap and the bar keeps its
    // clicks; that also makes the stacking order between them irrelevant.
    // Keyboard stays None; popups manage their own focus.
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
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
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