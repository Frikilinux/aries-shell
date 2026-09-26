import QtQuick
import QtQuick.Effects
import "../theme"

// Renders one system tray icon. Quickshell's SystemTray service already
// resolves each `item.icon` to a loadable source: `image://icon/<name>` for
// icons pulled from the active icon theme, `image://qspixmap/<id>` for icons
// supplied by the application itself, or a `file://` URL. Passing it straight
// to an Image is all it takes to "apply the icon theme".
//
// Theme icons are monochrome SVGs (Qt does not resolve `currentColor`), so
// they are painted with the bar foreground color via a MultiEffect layer. Icons
// the application supplies itself keep their own colors.

Item {
    id: root

    // Icon source reported by the tray item
    property string name: ""
    // Displayed size of the icon in px
    property int iconSize: Theme.iconSize

    // Theme-provided icons (`image://icon/`) are recolored to the bar
    // foreground; app-provided pixmaps/documents are left untouched.
    readonly property bool themed: root.name.startsWith("image://icon/")

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

        // Paint monochrome theme icons with the bar foreground. Only enabled
        // for themed icons, so app-supplied pixmaps keep their own colors.
        layer.enabled: root.themed
        layer.effect: MultiEffect {
            colorization: 1.0
            colorizationColor: Theme.fgBarColor
        }
    }
}
