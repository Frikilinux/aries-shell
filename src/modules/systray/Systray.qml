import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import "../theme"

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
    // Gap between consecutive icons.
    property int spacing: Theme.spacing

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    // Module is visible only if outputs property is unset, matches this output, or contains it
    visible: !outputs || (Array.isArray(outputs) ? outputs.includes(output) : outputs === output)

    Row {
        id: row
        spacing: Math.round(systray.spacing + 4)

        Repeater {
            model: SystemTray.items

            delegate: TrayItem {
                required property var modelData
                item: modelData
                iconSize: systray.iconSize
            }
        }
    }
}
