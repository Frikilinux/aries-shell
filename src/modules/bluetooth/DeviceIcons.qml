import QtQuick
import "../config"

// Icon resolution for a Bluetooth device row. For a given device:
//  1. the user's override map (Config.settings.modules.bluetooth.deviceIcons),
//     keyed by address -> device name -> BlueZ `icon` hint (whole class)
//  2. the BlueZ `icon` hint mapped to the icon font (iconGlyph())
//  3. the generic bluetooth glyph
// Values are raw glyphs from the `aries-shell` icon font, e.g. "\ue030".
// Example (config.json):
//     "deviceIcons": { "4C:87:5D:11:22:33": "\ue030",
//                      "audio-headset": "\ue030" }
QtObject {
    id: root

    property var map: Config.settings.modules.bluetooth.deviceIcons

    function glyph(dev) {
        if (!dev)
            return "\ue024"
        const m = root.map || {}
        const keys = [dev.address, dev.name, dev.deviceName, dev.icon]
        for (const k of keys) {
            if (k && k !== "" && k in m)
                return m[k]
        }
        return root.iconGlyph(dev.icon)
    }

    // BlueZ `icon` hint -> icon font glyph (falls back to bluetooth).
    function iconGlyph(i) {
        if (i === "audio-headset" || i === "audio-headphones")
            return "\ue030" // headphones
        if (i === "audio-card")
            return "\ue03e" // speaker-box
        if (i === "input-mouse")
            return "\ue06a" // mouse-simple
        if (i === "input-keyboard")
            return "\ue06d" // keyboard
        if (i === "input-gaming" || i === "input-joystick")
            return "\ue073" // xbox-controller
        if (i === "input-tablet")
            return "\ue072" // tablet
        if (i === "phone")
            return "\ue033" // phone
        if (i === "camera-video")
            return "\ue047" // video-bluetooth
        if (i === "camera-photo")
            return "\ue06b" // camera
        if (i === "printer")
            return "\ue06f" // print
        if (i === "computer")
            return "\ue06e" // laptop
        if (i === "multimedia-player")
            return "\ue06c" // headphones-sound-wave
        return "\ue024" // bluetooth
    }
}
