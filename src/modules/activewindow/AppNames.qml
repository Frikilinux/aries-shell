import QtQuick
import Quickshell
import "../config"

// Display-name resolution for the ActiveWindow module. For a given appId:
//  1. the user's override map (Config.settings.modules.activeWindow.appNames)
//  2. the app's .desktop Name via DesktopEntries.heuristicLookup()
//  3. the appId itself
// Callers apply their own formatting (ActiveWindow capitalizes the result).
// Example:
//     "org.wezfurlong.wezterm": "Wezterm"
//     "com.google.Chrome": "Chrome"
QtObject {
    id: root

    property var map: Config.settings.modules.activeWindow.appNames

    function displayName(appId) {
        if (!appId)
            return appId
        if (appId in root.map)
            return root.map[appId]
        const entry = DesktopEntries.heuristicLookup(appId)
        if (entry && entry.name)
            return entry.name
        return appId
    }
}
