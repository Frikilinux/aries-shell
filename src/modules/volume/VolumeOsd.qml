import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../icon"
import "../config"

// Transient volume OSD: one layer-shell surface per screen, created in
// shell.qml via `Variants` and filtered by `Config.outputs("volume")` (so it
// shows where the bar's volume module lives). Renders VolumeOsdService's
// state (default sink volume/mute + its short name) and auto-hides.
//
// Position comes from Config `volume.osd.x` / `volume.osd.y`: "center" or a
// pixel offset from the screen's top-left edge, per axis.
PanelWindow {
    id: osd

    required property var modelData
    // Screen filter (undefined/"*" = all screens), same rule as the bar module
    property var outputs

    // OSD settings (user config, live-updating)
    readonly property var osdCfg: Config.settings.modules.volume.osd
    // Window width (content gets 12px padding on each side)
    readonly property int osdWidth: 300

    screen: modelData

    readonly property bool onScreen: {
        const o = osd.outputs
        if (o === undefined || o === null || o === "*")
            return true
        const list = Array.isArray(o) ? o : [o]
        return list.indexOf(modelData.name) !== -1
    }

    visible: osd.onScreen && osd.osdCfg.enabled && VolumeOsdService.shown

    color: "transparent"
    // A transient overlay must never reserve screen space for windows
    exclusionMode: ExclusionMode.Ignore

    implicitWidth: osdWidth
    implicitHeight: body.implicitHeight + 24

    anchors {
        top: true
        left: true
    }

    WlrLayershell.layer: WlrLayer.Overlay
    // Same ns as bar popups -> inherits niri's shadow / corner-radius rule
    WlrLayershell.namespace: "aries-popup"
    // Purely informational: never takes keyboard focus
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Resolve one axis: "center" (or anything non-numeric) centers the OSD,
    // a number is a pixel offset from the screen's top/left edge.
    function axisPos(value, size, span) {
        if (value === "center")
            return Math.round((span - size) / 2)
        const n = Number(value)
        if (isNaN(n))
            return Math.round((span - size) / 2)
        return Math.round(n)
    }

    // Position rides on the layer-shell margins (anchored top-left), like
    // BarPopup: imperative, equality-guarded writes (margins is a value type).
    // Uses implicit size: width/height stay 0 until the first configure lands.
    function refreshPos() {
        if (!osd.visible || osd.screen === null)
            return
        const mx = Math.max(0, Math.min(
            osd.axisPos(osd.osdCfg.x, osd.implicitWidth, osd.screen.width),
            osd.screen.width - osd.implicitWidth))
        if (osd.margins.left !== mx)
            osd.margins.left = mx
        const my = Math.max(0, Math.min(
            osd.axisPos(osd.osdCfg.y, osd.implicitHeight, osd.screen.height),
            osd.screen.height - osd.implicitHeight))
        if (osd.margins.top !== my)
            osd.margins.top = my
    }

    onVisibleChanged: osd.refreshPos()
    // The compositor's first configure (real size) arrives after `visible`
    onWidthChanged: osd.refreshPos()
    onHeightChanged: osd.refreshPos()

    // Live config edits (x/y changed while the OSD is up)
    Connections {
        target: Config
        function onRevisionChanged() { osd.refreshPos() }
    }

    // Themed background (window itself stays transparent)
    Rectangle {
        anchors.fill: parent
        radius: Theme.popupRadius
        color: Qt.rgba(Theme.bgColor.r, Theme.bgColor.g, Theme.bgColor.b, Theme.bgOpacity)
        border.width: Theme.popupBorderWidth
        border.color: Theme.popupBorderColor
    }

    // Click anywhere dismisses the OSD early
    MouseArea {
        anchors.fill: parent
        onClicked: VolumeOsdService.hide()
    }

    Column {
        id: body
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.top: parent.top
        anchors.topMargin: 12
        width: osd.osdWidth - 24
        spacing: 6

        // Line 1: output short name + percent
        Row {
            width: parent.width
            spacing: 8

            Text {
                // width: parent.width - percentText.implicitWidth - parent.spacing
                width: parent.width - parent.spacing
                text: VolumeOsdService.deviceName
                elide: Text.ElideRight
                maximumLineCount: 1
                color: Theme.fgColor
                opacity: 0.6
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
            }

            // Text {
            //     id: percentText
            //     text: VolumeOsdService.percent + "%"
            //     color: Theme.fgColor
            //     opacity: VolumeOsdService.muted ? 0.5 : 1
            //     font.family: Theme.fontFamily
            //     font.pixelSize: Theme.fontSize - 2
            //     font.bold: true
            //     font.features: { "tnum": 1 }
            // }
        }

        // Line 2: volume glyph + progress bar
        Row {
            width: parent.width
            spacing: 10

            Icon {
                id: osdIcon
                glyph: VolumeOsdService.glyph
                color: Theme.fgColor
                opacity: VolumeOsdService.muted ? 0.5 : 1
                font.pixelSize: 24
            }

            Item {
                width: parent.width - osdIcon.width - parent.spacing
                height: 24

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 6
                    radius: 3
                    color: Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.15)

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        // Fill is clamped to 1.0; the % text shows the raw value
                        width: parent.width * Math.max(0, Math.min(1, VolumeOsdService.volume))
                        height: parent.height
                        radius: 3
                        color: Theme.accentColor
                        opacity: VolumeOsdService.muted ? 0.4 : 1

                        Behavior on width {
                            NumberAnimation { duration: 120 }
                        }
                    }
                }
            }
        }
    }
}
