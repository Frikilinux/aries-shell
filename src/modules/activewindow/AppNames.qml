import QtQuick
import "../config"

// Display-name overrides for the ActiveWindow module, sourced from the user
// config (Config.settings.modules.activeWindow.appNames). Map each appId (as
// reported by Toplevel.appId) to the text shown in the bar. Names not in the
// map fall back to the capitalized appId.
// Example:
//     "org.wezfurlong.wezterm": "Wezterm"
//     "com.google.Chrome": "Chrome"
QtObject {
    id: root

    property var map: Config.settings.modules.activeWindow.appNames

    function displayName(appId) {
        if (appId && appId in root.map)
            return root.map[appId]
        return appId
    }
}
