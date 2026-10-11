pragma ComponentBehavior: Bound

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
    property color emptyColor: Qt.rgba(Theme.fgBarColor.r, Theme.fgBarColor.g, Theme.fgBarColor.b, 0.3)
    property int dotWidth: 7
    property int dotHeight: 12
    // property int activeWidth: 6
    property int activeHeight: 17
    property int borderWidth: 1
    property real radius: 10
    property int dotSpacing: 5
    // Transition when a dot changes shape (current) or state color
    property int animDuration: 100

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
            // Index-based model: niri replaces the workspace object whenever it
            // changes (withFields copies it), so a Repeater over the objects
            // destroys+recreates those delegates on every focus switch and no
            // transition could ever run. The count only changes when ws are
            // added/removed, so delegates (and their Behaviors) survive.
            model: workspaces.items.length

            delegate: Rectangle {
                id: wsDot
                required property int index

                readonly property var ws: workspaces.items[wsDot.index]
                readonly property bool current: ws ? ws.is_active : false
                readonly property bool urgent: ws ? ws.is_urgent : false
                readonly property bool occupied: ws ? ws.active_window_id !== null : false
                // Focused wins over urgency, which wins over occupied/empty
                readonly property color stateColor: current ? workspaces.activeColor
                    : urgent ? workspaces.urgentColor
                    : occupied ? workspaces.occupiedColor
                    : workspaces.emptyColor

                width: workspaces.dotWidth
                height: current ? workspaces.activeHeight : workspaces.dotHeight
                // Row only manages x; center taller/shorter dots on the cross axis.
                // The line must be explicit: `parent` alone fails (no Item->AnchorLine cast).
                anchors.verticalCenter: parent.verticalCenter
                radius: workspaces.radius
                // Focused, urgent and occupied are filled, empty is an outline
                color: (current || urgent || occupied) ? stateColor : workspaces.emptyColor
                // border.width: workspaces.borderWidth
                // border.color: stateColor

                // Transition on shape and color changes (animDuration ms)
                Behavior on width {
                    NumberAnimation { duration: workspaces.animDuration }
                }
                Behavior on height {
                    NumberAnimation { duration: workspaces.animDuration }
                }
                Behavior on color {
                    ColorAnimation { duration: workspaces.animDuration }
                }
                // Behavior on border.color {
                //     ColorAnimation { duration: workspaces.animDuration }
                // }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (wsDot.ws) Niri.focusWorkspace(wsDot.ws.id)
                }
            }
        }
    }
}
