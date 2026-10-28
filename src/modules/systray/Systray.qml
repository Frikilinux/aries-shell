pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.SystemTray
import "../theme"
import "../config"

// System tray: shows the registered StatusNotifierItem icons in a row.
// Icons are resolved against the active icon theme by IconResolver.
// Left click activates, right click opens the context menu (TrayItem).

Item {
    id: systray

    // Show this module only on specific outputs (monitors).
    // Set to a string ("HDMI-A-1") or array (["eDP-1"]). If undefined/null, shows on all.
    property var outputs
    // The output being rendered.
    property string output: ""
    // Displayed size of each tray icon in px (propagated to TrayItem/TrayIcon).
    property int iconSize: Theme.iconSize
    // Recolor theme (monochrome) icons to the bar foreground via a per-icon
    // MultiEffect layer. Turn off to skip the extra FBO + shader per icon (the
    // icons then keep their own theme color).
    property bool recolor: Config.settings.modules.systray.recolor
    // Also recolor app-provided icons (pixmaps: `image://qspixmap/`, `file://`)
    // to the bar foreground. Off by default: flattening a full-color brand icon
    // to a silhouette is a strong visual change. Not applied to ids listed in
    // `pixmapsNoRecolor` (see below).
    property bool recolorPixmaps: Config.settings.modules.systray.recolorPixmaps
    // Tray item ids (SystemTrayItem.id, e.g. "telegram" — the same string shown
    // by `niri msg layers`/tray listings) whose app icons must never be
    // recolored, even with `recolorPixmaps` on. For icons that look wrong
    // flattened to one color.
    property var pixmapsNoRecolor: Config.settings.modules.systray.pixmapsNoRecolor
    // Gap between consecutive icons.
    property int spacing: Theme.spacing

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    // Module is visible only if outputs property is unset, matches this output, or contains it
    visible: !outputs || (Array.isArray(outputs) ? outputs.includes(output) : outputs === output)

    Row {
        id: row
        // +4: tray pixmaps usually carry transparent padding around the glyph;
        // without the extra gap tray icons sit tighter than bar icons.
        spacing: Math.round(systray.spacing + 4)

        Repeater {
            model: SystemTray.items

            delegate: TrayItem {
                required property var modelData
                item: modelData
                iconSize: systray.iconSize
                recolor: systray.recolor
                recolorPixmaps: systray.recolorPixmaps
                pixmapsNoRecolor: systray.pixmapsNoRecolor
            }
        }
    }
}
