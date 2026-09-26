import QtQuick
import "../theme"

// Renders one system tray icon. Quickshell's SystemTray service already
// resolves each `item.icon` to a loadable source: `image://icon/<name>` for
// icons pulled from the active icon theme, `image://qspixmap/<id>` for icons
// supplied by the application itself, or a `file://` URL. Passing it straight
// to an Image is all it takes to "apply the icon theme".

Item {
    id: root

    // Icon source reported by the tray item
    property string name: ""
    // Displayed size of the icon in px
    property int iconSize: 10

    // True once the icon rendered successfully
    readonly property bool resolved: iconImage.status === Image.Ready

    implicitWidth: root.iconSize
    implicitHeight: root.iconSize

    Image {
        id: iconImage
        width: root.iconSize
        height: root.iconSize
        fillMode: Image.PreserveAspectFit
        smooth: true
        // antialiasing: true
        sourceSize.width: Math.ceil(root.iconSize * Screen.devicePixelRatio)
        sourceSize.height: Math.ceil(root.iconSize * Screen.devicePixelRatio)
        source: root.name
    }
}
