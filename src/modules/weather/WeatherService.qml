pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Shared weather state for the bar indicator and its popup.
//
// Fetches OpenWeatherMap with curl: current conditions (/data/2.5/weather)
// and a 4-day daily forecast (/data/2.5/forecast/daily), the same API as the
// reference waybar script. Responses are cached in this singleton: data is
// only re-fetched once `refreshInterval` has elapsed since the last fetch.
Singleton {
    id: root

    // OpenWeatherMap request parameters (from the user config)
    property string apiKeyCurrent: Config.settings.modules.weather.apiKey
    property string apiKeyDaily: Config.settings.modules.weather.apiKeyDaily
    property string latitude: Config.settings.modules.weather.latitude
    property string longitude: Config.settings.modules.weather.longitude
    property string units: Config.settings.modules.weather.units

    // Minimum time between API fetches (milliseconds). Default: 30 minutes.
    property int refreshInterval: 1800000

    // Cached responses, kept until a later refresh overwrites them
    property var rawData: null
    property var forecastData: null
    property bool failed: false
    property bool fetching: false

    // Timestamp (Date.now()) of the last completed fetch; 0 = never fetched
    property int lastFetch: 0
    property int pendingFetches: 0

    readonly property bool available: rawData !== null
    readonly property bool hasForecast: forecastData !== null && forecastData.list !== undefined
    readonly property bool stale: root.lastFetch === 0
        || (Date.now() - root.lastFetch) >= root.refreshInterval

    // Current conditions
    readonly property int temp: available ? Math.round(rawData.main.temp) : 0
    readonly property int feelsLike: available ? Math.round(rawData.main.feels_like) : 0
    readonly property int tempMin: root.hasForecast
        ? Math.round(forecastData.list[0].temp.min)
        : available ? Math.round(rawData.main.temp_min) : 0
    readonly property int tempMax: root.hasForecast
        ? Math.round(forecastData.list[0].temp.max)
        : available ? Math.round(rawData.main.temp_max) : 0
    readonly property int humidity: available ? rawData.main.humidity : 0
    readonly property real windSpeed: available ? rawData.wind.speed : 0
    readonly property int windDeg: available ? rawData.wind.deg : 0
    readonly property string description: available ? rawData.weather[0].description.charAt(0).toUpperCase() + rawData.weather[0].description.slice(1) : ""
    readonly property string iconCode: available ? rawData.weather[0].icon : ""
    readonly property int sunrise: available ? rawData.sys.sunrise : 0
    readonly property int sunset: available ? rawData.sys.sunset : 0

    // The next 3 forecast days (today at index 0 is skipped)
    readonly property var forecastDays: root.hasForecast
        ? forecastData.list.slice(1, 4)
        : []

    readonly property string iconGlyph: root.iconGlyphFor(root.iconCode)

    readonly property string currentUrl: "https://api.openweathermap.org/data/2.5/weather"
        + "?lat=" + root.latitude
        + "&lon=" + root.longitude
        + "&units=" + root.units
        + "&appid=" + root.apiKeyCurrent

    readonly property string forecastUrl: "https://api.openweathermap.org/data/2.5/forecast/daily"
        + "?lat=" + root.latitude
        + "&lon=" + root.longitude
        + "&units=" + root.units
        + "&cnt=4"
        + "&appid=" + root.apiKeyDaily

    function iconGlyphFor(code) {
        switch (code) {
        case "01d": return "\ue05e"   // weather-sunny
        case "01n": return "\ue051"   // weather-moon
        case "02d": return "\ue053"   // weather-partly-cloudy-day
        case "02n": return "\ue054"   // weather-partly-cloudy-night
        case "03d":
        case "03n": return "\ue049"   // weather-cloudy
        case "04d":
        case "04n": return "\ue049"   // weather-cloudy
        case "09d":
        case "09n": return "\ue04a"   // weather-drizzle
        case "10d":
        case "10n": return "\ue055"   // weather-rain
        case "11d":
        case "11n": return "\ue061"   // weather-thunderstorm
        case "13d":
        case "13n": return "\ue05c"   // weather-snowflake
        case "50d":
        case "50n": return "\ue04c"   // weather-fog
        default: return "\ue049"      // weather-cloudy (unknown stand-in)
        }
    }

    // Compass initial of a wind direction in degrees
    function windDirection(deg) {
        const dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return dirs[Math.round(((deg % 360) + 360) % 360 / 45) % 8]
    }

    // Unix timestamp in seconds -> "HH:mm"
    function formatClock(ts) {
        return Qt.formatTime(new Date(ts * 1000), "HH:mm")
    }

    // Unix timestamp in seconds -> short weekday name
    function formatDay(ts) {
        return Qt.formatDate(new Date(ts * 1000), "ddd")
    }

    // Refetch both endpoints only when the cache is stale.
    function refresh() {
        if (root.fetching || !root.stale)
            return
        root.failed = false
        root.pendingFetches = 2
        root.fetching = true
        fetchCurrent.command = ["curl", "-s", "--connect-timeout", "5",
            "--max-time", "15", root.currentUrl]
        fetchForecast.command = ["curl", "-s", "--connect-timeout", "5",
            "--max-time", "15", root.forecastUrl]
        fetchCurrent.running = true
        fetchForecast.running = true
    }

    // Called once per finished process; marks the fetch complete after both.
    function processFinished() {
        root.pendingFetches = root.pendingFetches - 1
        if (root.pendingFetches <= 0) {
            root.fetching = false
            if (!root.failed)
                root.lastFetch = Date.now()
        }
    }

    function parseCurrent(text) {
        if (text === "") {
            root.failed = true
            return
        }
        try {
            const d = JSON.parse(text)
            if (Number(d.cod) !== 200) {
                root.failed = true
                return
            }
            root.rawData = d
        } catch (e) {
            root.failed = true
        }
    }

    function parseForecast(text) {
        if (text === "") {
            root.failed = true
            return
        }
        try {
            const d = JSON.parse(text)
            if (Number(d.cod) !== 200) {
                root.failed = true
                return
            }
            root.forecastData = d
        } catch (e) {
            root.failed = true
        }
    }

    // Force a refetch on the next refresh() by expiring the cache
    function invalidate() {
        root.lastFetch = 0
    }

    Component.onCompleted: refresh()
    onRefreshIntervalChanged: refreshTimer.interval = root.refreshInterval
    onLatitudeChanged: { invalidate(); root.refresh() }
    onLongitudeChanged: { invalidate(); root.refresh() }
    onUnitsChanged: { invalidate(); root.refresh() }
    onApiKeyCurrentChanged: { invalidate(); root.refresh() }
    onApiKeyDailyChanged: { invalidate(); root.refresh() }

    Timer {
        id: refreshTimer
        interval: root.refreshInterval
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    Process {
        id: fetchCurrent
        stdout: StdioCollector {
            onStreamFinished: root.parseCurrent(text)
        }
        onExited: function (exitCode, exitStatus) {
            if (exitCode !== 0)
                root.failed = true
            root.processFinished()
        }
    }

    Process {
        id: fetchForecast
        stdout: StdioCollector {
            onStreamFinished: root.parseForecast(text)
        }
        onExited: function (exitCode, exitStatus) {
            if (exitCode !== 0)
                root.failed = true
            root.processFinished()
        }
    }
}