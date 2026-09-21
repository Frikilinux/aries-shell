pragma Singleton

import QtQuick
import Quickshell
import "../config"

Singleton {
    // Font used for all bar text. Values come from the user config
    // (Config.settings.font), so editing the JSON live-updates the bar.
    property string fontFamily: Config.settings.font.family
    property string fontStyleName: Config.settings.font.styleName // e.g. "Bold", "Medium", "Regular".
    property int fontSize: Config.settings.font.size
    // Custom icon font (self-assembled from SVGs), shipped inside src/
    FontLoader {
        id: iconFontLoader
        // Quickshell does not resolve relative FontLoader paths (they become
        // qrc:/qs-blackhole); use an absolute file path from the shell dir.
        source: Quickshell.shellDir + "/assets/iconfont.ttf"
    }
    readonly property string iconFont: iconFontLoader.name

    property string iconStyle: "solid" // Unused with IconFont (single style); kept for config compat
    readonly property int iconSize: 18

    // Uniform gap between bar modules and between the icons inside a module
    readonly property int spacing: Config.settings.bar.spacing

    // Colors theme for the bar and modules (from the user config)
    readonly property color bgBarColor: Config.settings.colors.bgBarColor
    readonly property color fgBarColor: Config.settings.colors.fgBarColor
    readonly property color bgColor: Config.settings.colors.bgColor
    readonly property color bgColorMuted: Config.settings.colors.bgColorMuted
    readonly property color fgColor: Config.settings.colors.fgColor
    readonly property color fgColorMuted: Config.settings.colors.fgColorMuted
    // Shared background opacity of the bar/popups (colors.opacity)
    readonly property real bgOpacity: Config.settings.colors.bgOpacity
    readonly property color accentColor: Config.settings.colors.accent
    readonly property color urgentColor: Config.settings.colors.urgent
    readonly property color popupBorderColor: Config.settings.colors.popupBorder

    // Button/pill colors (used by e.g. the bluetooth device flags)
    readonly property color buttonBgColor: Config.settings.colors.buttonBgColor
    readonly property color buttonBorder: Config.settings.colors.buttonBorder
    readonly property color buttonPrimaryBgColor: Config.settings.colors.buttonPrimaryBgColor
    readonly property color buttonChipBgColor: Config.settings.colors.buttonChipBgColor

    // Popup appearance
    readonly property int popupRadius: Config.settings.colors.popupRadius
    readonly property int popupBorderWidth: Config.settings.colors.popupBorderWidth

}
