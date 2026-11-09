pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../icon"
import "../battery"
import "../widgets"

// Plugin settings for `aries-connect`, styled like a libadwaita preferences
// window: a header bar, a light sidebar with the general daemon info and the
// paired devices, and a dark content pane that shows either the daemon summary
// or the selected device (big icon, connection info and one switch per plugin).
//
// A switch never writes its own state: clicking calls `SetPluginEnabled` and
// the new value arrives through `PropertiesChanged(Plugins)`, so the UI only
// shows what the daemon confirmed. Failures are shown under the plugin group.
FloatingWindow {
    id: window

    // Recognisable title for a niri window rule (float + corner radius).
    title: "Aries Connect Settings"
    visible: false
    color: "transparent"

    // Size hint for the window system; the compositor may resize it (the
    // window is a normal resizable toplevel).
    implicitWidth: 840
    implicitHeight: 760
    // Resizable: the compositor may resize between these bounds (no maximum).
    minimumSize: Qt.size(640, 420)

    // Compositor blur behind the window (colors.blur, ext-background-effect-v1),
    // matching the rounded surface. Themed by the same `bar.blur` toggle as the
    // bar and the layer-shell popups; `null` removes it when off.
    BackgroundEffect.blurRegion: Theme.blur ? blurRegion : null

    Region {
        id: blurRegion
        item: window.contentItem
        radius: Theme.popupRadius
    }

    // "" = the general (daemon) page; otherwise the selected device id.
    property string selectedDeviceId: ""

    // Rounded surface radius shared by the groups and by the first/last row
    // hover fills, which must follow the card's corners.
    readonly property int groupRadius: 12

    // Same list/order as the popup: paired only, connected first, then name.
    readonly property var pairedList: {
        const list = AriesConnectService.devices.filter(d => d.paired === true && !d.request)
        list.sort((a, b) => {
            const ca = a.connected ? 0 : 1
            const cb = b.connected ? 0 : 1
            if (ca !== cb)
                return ca - cb
            return AriesConnectService.deviceLabel(a).localeCompare(AriesConnectService.deviceLabel(b))
        })
        return list
    }

    // The selected device while it still exists; a device unpaired with the
    // window open falls back to the general page instead of a ghost.
    readonly property bool showingDevice: window.selectedDeviceId !== "" && window.pairedList.some(d => d.deviceId === window.selectedDeviceId)
    readonly property var selectedDevice: window.showingDevice ? AriesConnectService.deviceById(window.selectedDeviceId) : null

    // Device glyph: tablets and laptops get their own, phones/unknown the phone.
    function deviceGlyph(type) {
        const t = String(type || "").toLowerCase()
        if (t === "tablet")
            return "\ue072"
        // tablet
        if (t === "desktop" || t === "laptop")
            return "\ue06e"
        // laptop
        return "\ue033"
        // phone
    }

    function batteryText(dev) {
        if (dev === null || dev === undefined)
            return "—"
        const level = dev.batteryLevel >= 0 ? dev.batteryLevel : dev.lastBatteryLevel
        if (!(level >= 0))
            return "—"
        return Math.round(level) + "%" + (dev.charging === true ? " · charging" : "")
    }

    function signalText(dev) {
        if (dev === null || dev === undefined)
            return "—"
        const live = dev.signalType !== ""
        const type = live ? dev.signalType : (dev.lastSignalType || "")
        const level = live ? dev.signalLevel : (typeof dev.lastSignalLevel === "number" ? dev.lastSignalLevel : -1)
        const generation = AriesConnectService.signalLabel(type)
        if (generation === "" && !(level >= 0))
            return "—"
        return (generation !== "" ? generation : "—") + (level >= 0 ? " · " + (Math.round(level) + 1) + "/5" : "")
    }

    // Re-sync on open: the daemon may have restarted (or the phone re-paired)
    // while the window was closed.
    onVisibleChanged: {
        if (visible) {
            AriesConnectService.pluginToggleError = ""
            AriesConnectService.deviceNameError = ""
            AriesConnectService.downloadDirError = ""
            AriesConnectService.refresh()
        }
    }

    FocusScope {
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: AriesConnectService.settingsVisible = false

        // Drag region: the top 40px strip (full width) lets the user click and
        // drag to move the window. Interactive controls (close/refresh) sit
        // above it and keep their own clicks.
        MouseArea {
            id: dragArea
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 40
            cursorShape: Qt.ArrowCursor
            onPressed: function (mouse) {
                window.startSystemMove()
                mouse.accepted = true
            }
        }

        // Full-height split: light sidebar (left) + dark content (right), flush
        // to the window edges. Each half paints its own rounded outer corners;
        // a border overlay frames the result.
        Row {
            anchors.fill: parent
            spacing: 0

            // Light sidebar: circular close + app title, general info, daemon
            // name and the device list.
            Rectangle {
                id: sidebar
                width: 300
                height: parent.height
                topLeftRadius: Theme.popupRadius
                bottomLeftRadius: Theme.popupRadius
                color: Qt.alpha(Theme.bgColorSecondary, Theme.bgOpacity)

                Item {
                    id: sidebarTop
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 52

                    Rectangle {
                        id: closeButton
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.fontSize + 6
                        height: Theme.fontSize + 6
                        radius: height / 2
                        color: closeMouse.containsMouse ? Qt.alpha(Theme.fgColor, 0.16) : Qt.alpha(Theme.fgColor, 0.10)

                        Icon {
                            anchors.centerIn: parent
                            glyph: "\ue02f" // dismiss
                            color: Theme.fgColor
                            font.pixelSize: Theme.fontSize - 3
                        }

                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: AriesConnectService.settingsVisible = false
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "Aries Connect"
                        color: Theme.fgColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }
                }

                Flickable {
                    id: sidebarFlick
                    anchors.top: sidebarTop.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 14
                    contentWidth: width
                    contentHeight: sidebarColumn.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: sidebarColumn
                        width: sidebarFlick.width
                        spacing: 16

                        Column {
                            width: parent.width
                            spacing: 3

                            Text {
                                width: parent.width
                                text: "Settings"
                                color: Theme.fgColor
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize + 5
                                font.bold: true
                            }

                            Text {
                                width: parent.width
                                text: "General Aries Connect Settings"
                                color: Theme.fgColorMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                                wrapMode: Text.Wrap
                            }
                        }

                        Rectangle {
                            id: generalNav
                            width: parent.width
                            height: 44
                            radius: 9
                            color: window.showingDevice ? (navMouse.containsMouse ? Qt.alpha(Theme.fgColor, 0.10) : Qt.alpha(Theme.fgColor, 0.05)) : Qt.alpha(Theme.accentColor, 0.18)
                            // color: Qt.alpha(Theme.fgColor, 0.05)
                            // border.width: window.showingDevice ? 0 : 1
                            // border.color: Theme.accentColor

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Aries Connect"
                                color: Theme.fgColor
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                font.bold: true
                            }

                            MouseArea {
                                id: navMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: window.selectedDeviceId = ""
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: 6

                            Text {
                                width: parent.width
                                text: "Daemon"
                                color: Theme.fgColor
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize + 1
                                font.bold: true
                            }

                            Row {
                                width: parent.width
                                spacing: 8

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: AriesConnectService.available ? Theme.accentColor : Theme.fgColorMuted
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: AriesConnectService.daemonLabel
                                    color: Theme.fgColor
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 1
                                    elide: Text.ElideRight
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: AriesConnectService.available ? "Running" : "Not running"
                                    color: AriesConnectService.available ? Theme.accentColor : Theme.fgColorMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 3
                                }
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: 3

                            Text {
                                width: parent.width
                                text: "Devices"
                                color: Theme.fgColor
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize + 1
                                font.bold: true
                            }

                            Text {
                                width: parent.width
                                text: "All the devices you've paired with"
                                color: Theme.fgColorMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                                wrapMode: Text.Wrap
                            }
                        }

                        Rectangle {
                            width: parent.width
                            implicitHeight: deviceList.implicitHeight
                            radius: window.groupRadius
                            color: Qt.alpha(Theme.fgColor, 0.05)
                            border.width: 1
                            border.color: Qt.alpha(Theme.borderColorRest, 0.6)

                            Column {
                                id: deviceList
                                width: parent.width

                                Repeater {
                                    model: window.pairedList

                                    delegate: DeviceListRow {}
                                }

                                Text {
                                    visible: window.pairedList.length === 0
                                    width: parent.width - 24
                                    height: visible ? 52 : 0
                                    x: 12
                                    verticalAlignment: Text.AlignVCenter
                                    text: "No paired devices"
                                    color: Theme.fgColorMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 1
                                }
                            }
                        }
                    }
                }
            }

            // Dark content pane: page header (title + refresh) and the page.
            Rectangle {
                id: contentPane
                width: parent.width - sidebar.width
                height: parent.height
                topRightRadius: Theme.popupRadius
                bottomRightRadius: Theme.popupRadius
                color: Qt.rgba(Theme.bgBarColor.r, Theme.bgBarColor.g, Theme.bgBarColor.b, Theme.bgOpacity)

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 1
                    color: Qt.alpha(Theme.borderColorRest, 0.6)
                }

                Item {
                    id: contentHeader
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 52

                    Text {
                        anchors.centerIn: parent
                        text: window.showingDevice ? "Device" : "Settings"
                        color: Theme.fgColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }

                    Rectangle {
                        id: refreshButton
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30
                        height: 30
                        radius: 8
                        color: refreshMouse.containsMouse ? Qt.alpha(Theme.fgColor, 0.08) : "transparent"

                        Icon {
                            anchors.centerIn: parent
                            glyph: "\ue01a" // arrow-clockwise
                            color: Theme.fgColorMuted
                            font.pixelSize: 16
                        }

                        MouseArea {
                            id: refreshMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: AriesConnectService.refresh()
                        }
                    }
                }

                // Flush with the header: the page carries its own 24px top pad
                // (`pageTopPad`), so a scrolled row disappears right at the
                // header edge instead of 24px below it.
                Flickable {
                    id: contentFlick
                    readonly property int pageTopPad: 24

                    anchors.top: contentHeader.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 24
                    anchors.rightMargin: 24
                    anchors.bottomMargin: 24
                    contentWidth: width
                    contentHeight: Math.max(pageLoader.height + pageTopPad, height)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Loader {
                        id: pageLoader
                        width: Math.min(contentFlick.width, 520)
                        x: (contentFlick.width - width) / 2
                        y: contentFlick.pageTopPad
                        sourceComponent: window.showingDevice ? devicePage : generalPage
                    }
                }

                // Soft edge under the header while the page is scrolled, so the
                // cut-off row reads as "scrolled under" and not as a glitch.
                Rectangle {
                    anchors.top: contentHeader.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 6
                    visible: contentFlick.contentY > 0.5

                    gradient: Gradient {
                        GradientStop {
                            position: 0
                            color: Qt.alpha(Theme.bgBarColor, 0.6)
                        }

                        GradientStop {
                            position: 1
                            color: "transparent"
                        }
                    }
                }
            }
        }

        // Frame the rounded window on top of both halves.
        Rectangle {
            anchors.fill: parent
            radius: Theme.popupRadius
            color: "transparent"
            border.width: Theme.popupBorderWidth
            border.color: Theme.borderColorRest
        }
    }

    // Section title + subtitle (libadwaita "heading").
    component SectionHeader: Column {
        property string title: ""
        property string subtitle: ""
        width: parent.width
        spacing: 4

        Text {
            width: parent.width
            text: parent.title
            color: Theme.fgColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 1
            font.bold: true
            wrapMode: Text.Wrap
        }

        Text {
            width: parent.width
            visible: parent.subtitle !== ""
            text: parent.subtitle
            color: Theme.fgColorMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
            wrapMode: Text.Wrap
        }
    }

    // Grouped rows on a rounded card, libadwaita style: one surface for the
    // whole group, a dark 1px hairline between rows, no border and no gaps.
    component Group: Rectangle {
        id: group
        default property alias content: groupColumn.data
        width: parent.width
        implicitHeight: groupColumn.implicitHeight
        radius: window.groupRadius
        color: Qt.alpha(Theme.bgColorSecondary, Theme.bgOpacity)

        Column {
            id: groupColumn
            width: parent.width
            spacing: 0
        }
    }

    // Label on the left, plain value on the right.
    component ValueRow: Item {
        id: valueRow
        property string label: ""
        property string value: ""
        property bool last: false
        width: parent.width
        height: 54

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.right: valueText.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: valueRow.label
            color: Theme.fgColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            elide: Text.ElideRight
        }

        Text {
            id: valueText
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: valueRow.value
            color: Theme.fgColorMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        Rectangle {
            visible: !valueRow.last
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 16
            height: 1
            color: Qt.alpha(Theme.bgBarColor, 0.85)
        }
    }

    // Editable two-line row (libadwaita): a small muted label on top, the
    // value below, and a pencil on the right. Pressing the pencil turns the
    // value into an inline text field; Enter/focus loss commits, Escape
    // cancels. The row highlights on hover (`first` / `last` keep the fill
    // inside the group's rounded corners).
    component EditableRow: Item {
        id: editableRow
        property string label: ""
        property string value: ""
        property bool first: false
        property bool last: false
        property bool editing: false
        signal committed(string value)

        width: parent.width
        height: 62

        function beginEdit() {
            if (editableRow.editing)
                return
            editor.text = editableRow.value
            editableRow.editing = true
            Qt.callLater(function () {
                editor.forceActiveFocus()
                editor.selectAll()
            })
        }

        // Leaving edit mode: `commit` emits the typed value, otherwise the
        // previous one stays (Escape). The focus-out handler and Enter both
        // funnel here, so the `editing` guard avoids a double emit.
        function finishEdit(commit) {
            if (!editableRow.editing)
                return
            const text = editor.text
            editableRow.editing = false
            if (commit)
                editableRow.committed(text)
        }

        Rectangle {
            anchors.fill: parent
            topLeftRadius: editableRow.first ? window.groupRadius : 0
            topRightRadius: editableRow.first ? window.groupRadius : 0
            bottomLeftRadius: editableRow.last ? window.groupRadius : 0
            bottomRightRadius: editableRow.last ? window.groupRadius : 0
            color: rowHover.hovered && !editableRow.editing ? Qt.alpha(Theme.fgColor, 0.045) : "transparent"

            Behavior on color {
                ColorAnimation {
                    duration: 120
                    easing.type: Easing.OutCubic
                }
            }
        }

        HoverHandler {
            id: rowHover
        }

        // Click anywhere on the row to start editing (the pencil is only the
        // affordance, not the only target). No cursor change on hover: GTK
        // keeps the plain arrow on this kind of row.
        MouseArea {
            anchors.fill: parent
            onClicked: editableRow.beginEdit()
        }

        Text {
            id: editableLabel
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.top: parent.top
            anchors.topMargin: 8
            text: editableRow.label
            color: Theme.fgColorMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 4
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.right: editButton.left
            anchors.rightMargin: 8
            anchors.top: editableLabel.bottom
            anchors.topMargin: 2
            text: editableRow.value
            color: Theme.fgColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            elide: Text.ElideRight
            visible: !editableRow.editing
        }

        // Pencil: purely decorative affordance (no box, no hover, no action —
        // the whole row is the click target). Hidden while editing.
        Item {
            id: editButton
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            height: 28
            visible: !editableRow.editing

            Icon {
                anchors.centerIn: parent
                glyph: "\ue097" // edit (pencil)
                color: Theme.fgColorMuted
                font.pixelSize: 16
            }
        }

        // Editing frame: the accent border wraps the whole row (label
        // included), like a libadwaita entry.
        Rectangle {
            anchors.fill: parent
            visible: editableRow.editing
            radius: 6
            color: "transparent"
            border.width: 2
            border.color: Theme.accentColor
        }

        TextInput {
            id: editor
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.top: editableLabel.bottom
            anchors.topMargin: 2
            height: 24
            color: Theme.fgColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            selectByMouse: true
            clip: true
            visible: editableRow.editing

            onAccepted: editableRow.finishEdit(true)
            Keys.onEscapePressed: editableRow.finishEdit(false)

            onActiveFocusChanged: {
                if (!activeFocus && editableRow.editing)
                    editableRow.finishEdit(true)
            }
        }

        Rectangle {
            visible: !editableRow.last && !editableRow.editing
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 16
            height: 1
            color: Qt.alpha(Theme.bgBarColor, 0.85)
        }
    }

    // Two-line path row (libadwaita): small label on top, the path below, a
    // pencil that starts inline editing and a folder button that opens the
    // platform directory picker (xdg-desktop-portal). Clicking anywhere on the
    // row edits the text; the folder button stays available while editing.
    // Committing emits `picked` (an empty value clears the override).
    component DirectoryRow: Item {
        id: directoryRow
        property string label: ""
        property string value: ""
        property bool first: false
        property bool last: false
        property bool editing: false
        signal picked(string path)

        width: parent.width
        height: 62

        function beginEdit() {
            if (directoryRow.editing)
                return
            editor.text = directoryRow.value
            directoryRow.editing = true
            Qt.callLater(function () {
                editor.forceActiveFocus()
                editor.selectAll()
            })
        }

        function finishEdit(commit) {
            if (!directoryRow.editing)
                return
            const text = editor.text
            directoryRow.editing = false
            if (commit)
                directoryRow.picked(text)
        }

        // Opens the picker: leave edit mode without committing, so the typed
        // text cannot race with the picked path (focus-out would commit it).
        function openPicker() {
            directoryRow.editing = false
            AriesConnectService.pickDirectory(function (paths) {
                if (paths.length > 0)
                    directoryRow.picked(paths[0])
            })
        }

        Rectangle {
            anchors.fill: parent
            topLeftRadius: directoryRow.first ? window.groupRadius : 0
            topRightRadius: directoryRow.first ? window.groupRadius : 0
            bottomLeftRadius: directoryRow.last ? window.groupRadius : 0
            bottomRightRadius: directoryRow.last ? window.groupRadius : 0
            color: rowHover.hovered && !directoryRow.editing ? Qt.alpha(Theme.fgColor, 0.045) : "transparent"

            Behavior on color {
                ColorAnimation {
                    duration: 120
                    easing.type: Easing.OutCubic
                }
            }
        }

        HoverHandler {
            id: rowHover
        }

        // Click anywhere on the row to edit the path by hand. Plain arrow, no
        // cursor change on hover (matches the rest of the settings rows).
        MouseArea {
            anchors.fill: parent
            onClicked: directoryRow.beginEdit()
        }

        Text {
            id: directoryLabel
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.top: parent.top
            anchors.topMargin: 8
            text: directoryRow.label
            color: Theme.fgColorMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 4
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.right: editButton.left
            anchors.rightMargin: 8
            anchors.top: directoryLabel.bottom
            anchors.topMargin: 2
            text: directoryRow.value !== "" ? directoryRow.value : "Not set"
            color: directoryRow.value !== "" ? Theme.fgColor : Theme.fgColorMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            elide: Text.ElideMiddle
            visible: !directoryRow.editing
        }

        // Pencil: decorative affordance for the inline editor (bare glyph, no
        // box, no hover, no action). Hidden while editing.
        Item {
            id: editButton
            anchors.right: folderButton.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            height: 28
            visible: !directoryRow.editing

            Icon {
                anchors.centerIn: parent
                glyph: "\ue097" // edit (pencil)
                color: Theme.fgColorMuted
                font.pixelSize: 16
            }
        }

        // Folder: opens the platform directory picker, so it is the only icon
        // with a hover circle. Stays visible while editing.
        Item {
            id: folderButton
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            height: 28

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: folderMouse.containsMouse ? Qt.alpha(Theme.fgColor, 0.10) : "transparent"

                Behavior on color {
                    ColorAnimation {
                        duration: 100
                        easing.type: Easing.OutCubic
                    }
                }
            }

            Icon {
                anchors.centerIn: parent
                glyph: "\ue09a" // folder
                color: Theme.fgColor
                font.pixelSize: 16
            }

            MouseArea {
                id: folderMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: directoryRow.openPicker()
            }
        }

        // Editing frame: the accent border wraps the whole row.
        Rectangle {
            anchors.fill: parent
            visible: directoryRow.editing
            radius: 6
            color: "transparent"
            border.width: 2
            border.color: Theme.accentColor
        }

        TextInput {
            id: editor
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.right: folderButton.left
            anchors.rightMargin: 8
            anchors.top: directoryLabel.bottom
            anchors.topMargin: 2
            height: 24
            color: Theme.fgColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            selectByMouse: true
            clip: true
            visible: directoryRow.editing

            onAccepted: directoryRow.finishEdit(true)
            Keys.onEscapePressed: directoryRow.finishEdit(false)

            onActiveFocusChanged: {
                if (!activeFocus && directoryRow.editing)
                    directoryRow.finishEdit(true)
            }
        }

        Rectangle {
            visible: !directoryRow.last && !directoryRow.editing
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 16
            height: 1
            color: Qt.alpha(Theme.bgBarColor, 0.85)
        }
    }

    // Label on the left, status dot + value on the right.
    component StatusRow: Item {
        id: statusRow
        property string label: ""
        property string value: ""
        property color dotColor: "transparent"
        property bool last: false
        width: parent.width
        height: 54

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.right: statusValue.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: statusRow.label
            color: Theme.fgColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            elide: Text.ElideRight
        }

        Row {
            id: statusValue
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: statusRow.dotColor !== "transparent"
                width: 8
                height: 8
                radius: 4
                color: statusRow.dotColor
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: statusRow.value
                color: Theme.fgColorMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
        }

        Rectangle {
            visible: !statusRow.last
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 16
            height: 1
            color: Qt.alpha(Theme.bgBarColor, 0.85)
        }
    }

    // Plugin row: icon, label and switch.
    component SwitchRow: Item {
        id: switchRow
        required property var modelData
        required property int index
        property string glyph: ""
        property string label: ""
        property bool checked: false
        property bool first: false
        property bool last: false
        signal toggled

        width: parent.width
        height: 54

        Rectangle {
            anchors.fill: parent
            topLeftRadius: switchRow.first ? window.groupRadius : 0
            topRightRadius: switchRow.first ? window.groupRadius : 0
            bottomLeftRadius: switchRow.last ? window.groupRadius : 0
            bottomRightRadius: switchRow.last ? window.groupRadius : 0
            color: rowHover.hovered ? Qt.alpha(Theme.fgColor, 0.045) : "transparent"

            Behavior on color {
                ColorAnimation {
                    duration: 120
                    easing.type: Easing.OutCubic
                }
            }
        }

        HoverHandler {
            id: rowHover
        }

        Icon {
            id: rowIcon
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            width: 20
            horizontalAlignment: Text.AlignHCenter
            glyph: switchRow.glyph
            color: Theme.fgColorMuted
            font.pixelSize: 17
        }

        Text {
            anchors.left: rowIcon.right
            anchors.leftMargin: 12
            anchors.right: rowSwitch.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: switchRow.label
            color: Theme.fgColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            elide: Text.ElideRight
        }

        // libadwaita switch: 46x26 with a 20px knob (3px inset).
        Switch {
            id: rowSwitch
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            trackWidth: 46
            trackHeight: 26
            knobInset: 3
            checked: switchRow.checked
            onToggled: switchRow.toggled()
        }

        Rectangle {
            visible: !switchRow.last
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 48
            height: 1
            color: Qt.alpha(Theme.bgBarColor, 0.85)
        }
    }

    // One device row in the sidebar: name + status icons.
    component DeviceListRow: Item {
        id: deviceRow
        required property var modelData
        required property int index
        readonly property bool selected: window.showingDevice && window.selectedDeviceId === deviceRow.modelData.deviceId
        readonly property int battery: modelData.batteryLevel >= 0 ? modelData.batteryLevel : modelData.lastBatteryLevel

        width: parent.width
        height: 52

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: 8
            color: deviceRow.selected ? Qt.alpha(Theme.accentColor, 0.18) : deviceMouse.containsMouse ? Qt.alpha(Theme.fgColor, 0.05) : "transparent"
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.right: statusIcons.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: AriesConnectService.deviceLabel(deviceRow.modelData)
            color: Theme.fgColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
            elide: Text.ElideRight
        }

        Row {
            id: statusIcons
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                visible: deviceRow.battery >= 0
                glyph: BatteryService.batteryLevelGlyph(deviceRow.battery, deviceRow.modelData.charging === true)
                color: Theme.fgColorMuted
                font.pixelSize: 16
            }

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                glyph: "\ue029" // checkmark-circle
                color: deviceRow.modelData.connected === true ? Theme.accentColor : Theme.fgColorMuted
                opacity: deviceRow.modelData.connected === true ? 1 : 0.5
                font.pixelSize: 15
            }
        }

        Rectangle {
            visible: deviceRow.index < window.pairedList.length - 1
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 12
            height: 1
            color: Qt.alpha(Theme.fgColor, 0.08)
        }

        MouseArea {
            id: deviceMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: window.selectedDeviceId = deviceRow.modelData.deviceId
        }
    }

    // General page: daemon summary.
    Component {
        id: generalPage

        Column {
            spacing: 18

            Item {
                width: parent.width
                height: bigGear.implicitHeight + 6 + generalTitle.implicitHeight

                Icon {
                    id: bigGear
                    anchors.horizontalCenter: parent.horizontalCenter
                    glyph: "\ue071" // settings
                    color: Theme.fgColor
                    font.pixelSize: 100
                }

                Text {
                    id: generalTitle
                    anchors.top: bigGear.bottom
                    anchors.topMargin: 10
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Aries Connect"
                    color: Theme.fgColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 6
                    font.bold: true
                }
            }

            SectionHeader {
                title: "Daemon"
                subtitle: "Information about the running daemon."
            }

            Group {
                EditableRow {
                    label: "Name"
                    value: AriesConnectService.daemonLabel
                    first: true

                    onCommitted: function (name) {
                        AriesConnectService.setDeviceName(name)
                    }
                }

                StatusRow {
                    label: "Status"
                    value: AriesConnectService.available ? "Running" : "Not running"
                    dotColor: AriesConnectService.available ? Theme.accentColor : Theme.fgColorMuted
                }

                ValueRow {
                    label: "Paired devices"
                    value: String(AriesConnectService.pairedCount)
                }

                ValueRow {
                    label: "Connected"
                    value: String(AriesConnectService.connectedCount)
                    last: true
                }
            }

            Text {
                visible: AriesConnectService.deviceNameError !== ""
                width: parent.width
                text: AriesConnectService.deviceNameError
                color: Theme.urgencyCriticalColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
                wrapMode: Text.Wrap
            }

            SectionHeader {
                title: "Devices"
                subtitle: "Select a device in the sidebar to configure its plugins."
            }
        }
    }

    // Device page: big icon + name, connection info and plugin switches.
    Component {
        id: devicePage

        Column {
            id: deviceColumn
            readonly property var device: window.selectedDevice
            readonly property var pluginRows: AriesConnectService.pluginList(device !== null ? device.deviceId : "")
            spacing: 18

            Item {
                width: parent.width
                height: bigDeviceIcon.implicitHeight + 6 + deviceTitle.implicitHeight

                Icon {
                    id: bigDeviceIcon
                    anchors.horizontalCenter: parent.horizontalCenter
                    glyph: window.deviceGlyph(deviceColumn.device !== null ? deviceColumn.device.type : "")
                    color: Theme.fgColor
                    font.pixelSize: 100
                }

                Text {
                    id: deviceTitle
                    anchors.top: bigDeviceIcon.bottom
                    anchors.topMargin: 10
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: deviceColumn.device !== null ? AriesConnectService.deviceLabel(deviceColumn.device) : ""
                    color: Theme.fgColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 6
                    font.bold: true
                    elide: Text.ElideRight
                }
            }

            SectionHeader {
                title: "Connection"
                subtitle: "State reported by the phone."
            }

            Group {
                StatusRow {
                    label: "Status"
                    value: deviceColumn.device !== null && deviceColumn.device.connected ? "Connected" : "Offline"
                    dotColor: deviceColumn.device !== null && deviceColumn.device.connected ? Theme.accentColor : Theme.fgColorMuted
                }

                ValueRow {
                    label: "Paired"
                    value: deviceColumn.device !== null && deviceColumn.device.paired ? "Yes" : "No"
                }

                ValueRow {
                    label: "Battery"
                    value: window.batteryText(deviceColumn.device)
                }

                ValueRow {
                    label: "Signal"
                    value: window.signalText(deviceColumn.device)
                    last: true
                }
            }

            SectionHeader {
                title: "Sharing"
                subtitle: "Where files shared by this device are saved."
            }

            Group {
                DirectoryRow {
                    label: "Download folder"
                    value: deviceColumn.device !== null ? (deviceColumn.device.downloadDir || "") : ""
                    first: true
                    last: true

                    onPicked: function (dir) {
                        if (deviceColumn.device !== null)
                            AriesConnectService.setDownloadDir(deviceColumn.device.deviceId, dir)
                    }
                }
            }

            Text {
                visible: AriesConnectService.downloadDirError !== ""
                width: parent.width
                text: AriesConnectService.downloadDirError
                color: Theme.urgencyCriticalColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
                wrapMode: Text.Wrap
            }

            SectionHeader {
                title: "Plugins"
                subtitle: "Enable or disable plugins for this device."
            }

            Group {
                Repeater {
                    model: deviceColumn.pluginRows

                    delegate: SwitchRow {
                        glyph: modelData.icon
                        label: modelData.label
                        checked: modelData.enabled
                        first: index === 0
                        last: index === deviceColumn.pluginRows.length - 1
                        onToggled: AriesConnectService.setPluginEnabled(window.selectedDeviceId, modelData.id, !modelData.enabled)
                    }
                }
            }

            Text {
                visible: AriesConnectService.pluginToggleError !== ""
                width: parent.width
                text: AriesConnectService.pluginToggleError
                color: Theme.urgencyCriticalColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
                wrapMode: Text.Wrap
            }
        }
    }
}
