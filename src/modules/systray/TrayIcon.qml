import QtQuick
import QtQuick.Effects
import "../theme"

// Renders one system tray icon. Quickshell's SystemTray service already
// resolves each `item.icon` to a loadable source: `image://icon/<name>` for
// icons pulled from the active icon theme, `image://qspixmap/<id>` for icons
// supplied by the application itself, or a `file://` URL. Passing it straight
// to an Image is all it takes to "apply the icon theme".
//
// When `colorize` is on, the icon is painted with the bar foreground color
// via a MultiEffect layer: the alpha (shape) is preserved, the RGB is flattened
// to one color (a silhouette). That is the correct treatment for monochrome
// theme SVGs (Qt does not resolve `currentColor`); for app-provided pixmaps it
// turns the icon into a solid fg glyph, which callers enable/disable through
// the `recolorPixmaps` policy (see TrayItem — the recolor decision lives there,
// including the id exclusion list).

Item {
    id: root

    // Icon source reported by the tray item
    property string name: ""
    // Displayed size of the icon in px
    property int iconSize: Theme.iconSize
    // Flatten the icon to the bar foreground (alpha preserved). Whether it is
    // appropriate for this icon (theme vs app pixmap) is decided by the caller.
    property bool colorize: false

    // True once the icon rendered successfully
    readonly property bool resolved: iconImage.status === Image.Ready

    implicitWidth: root.iconSize
    implicitHeight: root.iconSize

    Image {
        id: iconImage
        anchors.centerIn: parent
        width: root.iconSize
        height: root.iconSize
        fillMode: Image.PreserveAspectFit
        // Smooth (linear) filtering while scaling. Default is already true in
        // Qt 6; set explicitly to document intent (false = nearest neighbor).
        smooth: true
        sourceSize.width: Math.ceil(root.iconSize * Screen.devicePixelRatio)
        sourceSize.height: Math.ceil(root.iconSize * Screen.devicePixelRatio)
        source: root.name

        // Paint the icon with the bar foreground. The layer (FBO + one shader
        // pass) only exists when colorizing, so non-tinted sources render at
        // their base cost.
        layer.enabled: root.colorize
        layer.effect: MultiEffect {
            colorization: 1.0
            colorizationColor: Theme.fgBarColor
        }
    }
}
