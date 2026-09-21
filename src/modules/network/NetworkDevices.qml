pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking

// Shared network-interface ordering used by the bar module and its popup:
//   0 ethernet internal  ·  1 ethernet external
//   2 wifi internal      ·  3 wifi external
// Groups are then sorted by name. External = attached over USB, detected from
// /sys/class/net/<iface>/device/subsystem.
Singleton {
    id: root

    readonly property var devices: Networking.devices.values

    // iface -> true when the interface hangs off USB
    property var externalMap: ({})

    function isExternal(dev) {
        return root.externalMap[dev.name] === true
    }

    function rank(dev) {
        const external = root.isExternal(dev) ? 1 : 0
        if (dev.type === DeviceType.Wired)
            return external
        return 2 + external
    }

    readonly property var ordered: {
        const list = root.devices.filter(
            x => x.type === DeviceType.Wifi || x.type === DeviceType.Wired)
        list.sort((a, b) => {
            const ra = root.rank(a)
            const rb = root.rank(b)
            if (ra !== rb)
                return ra - rb
            return String(a.name).localeCompare(String(b.name))
        })
        return list
    }

    readonly property var wifiDevices: ordered.filter(x => x.type === DeviceType.Wifi)
    readonly property var wiredDevices: ordered.filter(x => x.type === DeviceType.Wired)

    readonly property string deviceNames: devices.map(d => d.name).sort().join(",")
    // Only re-scan the bus when the set of interfaces changes.
    onDeviceNamesChanged: if (busProcess) busProcess.running = true

    Process {
        id: busProcess
        command: ["/bin/sh", "-c",
            "for i in /sys/class/net/*; do "
            + "iface=${i##*/}; "
            + "bus=$(readlink -f \"$i/device/subsystem\" 2>/dev/null); "
            + "case \"$bus\" in */usb) echo \"$iface 1\";; *) echo \"$iface 0\";; esac; "
            + "done"]
        stdout: StdioCollector {
            onStreamFinished: root.parseExternal(text)
        }
        Component.onCompleted: running = true
    }

    function parseExternal(text) {
        const map = {}
        const lines = String(text).split("\n")
        for (let i = 0; i < lines.length; i++) {
            const p = lines[i].trim().split(/\s+/)
            if (p.length === 2 && p[0] !== "")
                map[p[0]] = p[1] === "1"
        }
        root.externalMap = map
    }
}
