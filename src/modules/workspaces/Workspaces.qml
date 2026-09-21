import QtQuick
import "../theme"
import "../niri"

Item {
    id: workspaces

    // Show this module only on specific outputs.
    // Set to a string ("HDMI-A-1") or array (["eDP-1"]). If undefined/null, shows on all.
    property var outputs

    // Output (monitor) whose workspaces are shown, e.g. "eDP-1"
    required property string output

    // Appearance
    property color activeColor: Theme.accentColor
    property color urgentColor: Theme.urgentColor
    property color occupiedColor: Theme.fgBarColor
    property color emptyColor: Theme.fgBarColor
    property int dotWidth: 18
    property int dotHeight: 10
    property int activeWidth: 32
    property int borderWidth: 1
    property real radius: 10
    property int dotSpacing: Theme.spacing

    // Workspaces of this output, ordered by their index
    readonly property var items: {
        if (!output)
            return []
        const list = Niri.workspaces.filter(ws => ws.output === output)
        list.sort((a, b) => a.idx - b.idx)
        return list
    }

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    // Module is visible only if outputs property is unset, matches this output, or contains it
    visible: !outputs || (Array.isArray(outputs) ? outputs.includes(output) : outputs === output)

    Row {
        id: row
        spacing: workspaces.dotSpacing

        Repeater {
            model: workspaces.items

            delegate: Rectangle {
                required property var modelData

                readonly property bool current: modelData.is_active
                readonly property bool urgent: modelData.is_urgent
                readonly property bool occupied: modelData.active_window_id !== null
                // Focused wins over urgency, which wins over occupied/empty
                readonly property color stateColor: current ? workspaces.activeColor
                    : urgent ? workspaces.urgentColor
                    : occupied ? workspaces.occupiedColor
                    : workspaces.emptyColor

                width: current ? workspaces.activeWidth : workspaces.dotWidth
                height: workspaces.dotHeight
                radius: workspaces.radius
                // Focused, urgent and occupied are filled, empty is an outline
                color: (current || urgent || occupied) ? stateColor : "transparent"
                border.width: workspaces.borderWidth
                border.color: stateColor

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Niri.focusWorkspace(modelData.id)
                }
            }
        }
    }
}
