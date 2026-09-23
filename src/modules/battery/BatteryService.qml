pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// Shared battery state for the bar indicator and its popup.
//
// Charge data comes from UPower (Quickshell.Services.UPower). Charge limits are
// not exposed by UPower (the D-Bus properties are read-only in 1.91), so they
// are read straight from sysfs and written with pkexec (the polkit agent shows
// the usual authentication dialog).
Singleton {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property bool present: device !== null && device.isPresent && device.ready

    // Quickshell reports `percentage` as a 0..1 fraction; expose 0..100.
    // changeRate is in Watts
    readonly property real percentage: present ? device.percentage * 100 : 0
    readonly property int state: present ? device.state : UPowerDeviceState.Unknown
    readonly property real changeRate: present ? device.changeRate : 0
    readonly property real timeToEmpty: present ? device.timeToEmpty : 0
    readonly property real timeToFull: present ? device.timeToFull : 0
    readonly property real energy: present ? device.energy : 0
    readonly property real energyCapacity: present ? device.energyCapacity : 0
    readonly property real healthPercentage: present && device.healthSupported ? device.healthPercentage : -1

    readonly property bool charging: state === UPowerDeviceState.Charging
    readonly property bool discharging: state === UPowerDeviceState.Discharging
    readonly property bool full: state === UPowerDeviceState.FullyCharged

    // Charger connected (charging, full, waiting at a limit, or AC online)
    readonly property bool pluggedIn: present && (!UPower.onBattery
        || state === UPowerDeviceState.Charging
        || state === UPowerDeviceState.FullyCharged
        || state === UPowerDeviceState.PendingCharge)

    // sysfs node for charge thresholds, e.g. BAT0 -> /sys/class/power_supply/BAT0
    readonly property string batteryName: {
        const path = device !== null && device.nativePath ? device.nativePath : ""
        if (path === "")
            return "BAT0"
        const parts = path.split("/")
        return parts[parts.length - 1]
    }
    readonly property string sysfsDir: "/sys/class/power_supply/" + batteryName

    // charge_control_{start,end}_threshold, or -1 when unsupported
    property int startThreshold: -1
    property int endThreshold: -1
    readonly property bool thresholdSupported: endThreshold >= 0
    readonly property bool limitActive: thresholdSupported && endThreshold > 0 && endThreshold < 100
    // Plugged in and no longer charging because the end threshold was reached
    readonly property bool atLimit: thresholdSupported && pluggedIn && !charging
        && percentage >= endThreshold

    property string applyError: ""
    readonly property bool applying: applyProcess.running

    // Requested thresholds, used to verify the write once it lands
    property int pendingStart: -1
    property int pendingEnd: -1

    function refresh() {
        thresholdReader.running = true
    }

    function parseThresholds(text) {
        const parts = text.trim().split(/\s+/)
        const start = parseInt(parts[0], 10)
        const end = parseInt(parts[1], 10)
        root.startThreshold = isNaN(start) ? -1 : start
        root.endThreshold = isNaN(end) ? -1 : end
        // Verify a pending apply by reading the values back: Dell firmware
        // silently reverts thresholds that break its start <= end - 5 rule.
        if (root.pendingEnd >= 0) {
            if (root.startThreshold === root.pendingStart && root.endThreshold === root.pendingEnd) {
                root.applyError = ""
            } else {
                root.applyError = "Hardware rejected the thresholds: got "
                    + root.startThreshold + "-" + root.endThreshold + "%, expected "
                    + root.pendingStart + "-" + root.pendingEnd + "%"
            }
            root.pendingStart = -1
            root.pendingEnd = -1
        }
    }

    // Apply a charge profile by writing the start/end thresholds as root.
    // The shell script receives the paths/values as positional arguments so
    // they are never interpreted by the shell. Firmware requires start to be at
    // least 5% below end, so when raising the profile the end threshold must be
    // written first (and when lowering it, the start first); otherwise the
    // intermediate state is invalid and gets reverted.
    function applyProfile(percent) {
        if (!root.thresholdSupported)
            return
        root.applyError = ""
        const start = percent >= 100 ? 95 : Math.max(50, percent - 5)
        root.pendingStart = start
        root.pendingEnd = percent
        const script = "d=\"$1\"; s=\"$2\"; e=\"$3\"; "
            + "ce=$(cat \"$d/charge_control_end_threshold\" 2>/dev/null || echo 0); "
            + "if [ \"$e\" -ge \"$ce\" ]; then "
            + "printf '%s\\n' \"$e\" > \"$d/charge_control_end_threshold\"; "
            + "printf '%s\\n' \"$s\" > \"$d/charge_control_start_threshold\"; "
            + "else "
            + "printf '%s\\n' \"$s\" > \"$d/charge_control_start_threshold\"; "
            + "printf '%s\\n' \"$e\" > \"$d/charge_control_end_threshold\"; "
            + "fi"
        applyProcess.command = ["pkexec", "/bin/sh", "-c", script, "sh",
            root.sysfsDir, String(start), String(percent)]
        applyProcess.running = true
    }

    function handleApplyExit(code) {
        if (code === 0) {
            root.applyError = ""
            root.refresh()
        } else if (code === 126 || code === 127) {
            root.pendingStart = -1
            root.pendingEnd = -1
            root.applyError = "Authentication cancelled or not authorized"
        } else {
            root.pendingStart = -1
            root.pendingEnd = -1
            root.applyError = "Could not apply charge limit (code " + code + ")"
        }
    }

    // ------------------------------------------------------------------
    // power-profiles-daemon profile, native via the PowerProfiles
    // singleton (no CLI). Button colors: red / blue / green.
    // ------------------------------------------------------------------
    readonly property string powerProfileLabel: {
        switch (PowerProfiles.profile) {
        case PowerProfile.Performance:
            return "Performance"
        case PowerProfile.PowerSaver:
            return "Power saver"
        default:
            return "Balanced"
        }
    }

    readonly property color powerProfileColor: {
        switch (PowerProfiles.profile) {
        case PowerProfile.Performance:
            return "#d64545"
        case PowerProfile.PowerSaver:
            return "#3fae62"
        default:
            return "#3d7fd6"
        }
    }

    // Performance -> Balanced -> Power saver -> Performance. Performance is
    // skipped when the daemon does not expose it (`hasPerformanceProfile`).
    function cyclePowerProfile() {
        switch (PowerProfiles.profile) {
        case PowerProfile.Performance:
            PowerProfiles.profile = PowerProfile.Balanced
            break
        case PowerProfile.Balanced:
            PowerProfiles.profile = PowerProfile.PowerSaver
            break
        default:
            PowerProfiles.profile = PowerProfiles.hasPerformanceProfile
                ? PowerProfile.Performance : PowerProfile.Balanced
        }
    }

    // Battery level icons: index 0..10 (battery0 empty -> battery10 full)
    readonly property var batteryGlyphs: [
        "\ue000", "\ue002", "\ue003", "\ue004", "\ue005", "\ue006",
        "\ue007", "\ue008", "\ue009", "\ue00a", "\ue001"
    ]
    // Charging battery icons: index 0..10 (battery-charge0 -> battery-charge10)
    readonly property var chargeGlyphs: [
        "\ue00b", "\ue00d", "\ue00f", "\ue010", "\ue011", "\ue012",
        "\ue013", "\ue014", "\ue015", "\ue016", "\ue00c"
    ]

    // Battery icon for a 0..100 percentage, rounded to the nearest 10% step.
    // When charging, the matching battery-with-bolt variant is returned.
    function batteryGlyph(percent, charging) {
        const level = Math.max(0, Math.min(10, Math.round(percent / 10)))
        return charging ? root.chargeGlyphs[level] : root.batteryGlyphs[level]
    }

    readonly property string stateText: {
        switch (state) {
        case UPowerDeviceState.Charging:
            return "Charging"
        case UPowerDeviceState.Discharging:
            return "Discharging"
        case UPowerDeviceState.FullyCharged:
            return "Full"
        case UPowerDeviceState.Empty:
            return "Empty"
        case UPowerDeviceState.PendingCharge:
            return "Charge pending"
        case UPowerDeviceState.PendingDischarge:
            return "Discharge pending"
        default:
            return "Unknown"
        }
    }

    Component.onCompleted: refresh()
    onBatteryNameChanged: refresh()

    Process {
        id: thresholdReader
        command: ["/bin/sh", "-c",
            "printf '%s %s' "
                + "\"$(cat \"$1/charge_control_start_threshold\" 2>/dev/null || echo -1)\" "
                + "\"$(cat \"$1/charge_control_end_threshold\" 2>/dev/null || echo -1)\"",
            "sh", root.sysfsDir]
        stdout: StdioCollector {
            onStreamFinished: root.parseThresholds(text)
        }
    }

    Process {
        id: applyProcess
        onExited: function (exitCode, exitStatus) {
            root.handleApplyExit(exitCode)
        }
    }
}
