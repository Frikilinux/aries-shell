pragma ComponentBehavior: Bound

import QtQuick
import "../theme"
import "../icon"
import "../popup"
import "../battery"

// CPU overview: package temperature, core count, global frequency and power
// profile in the header card; per-core load and usage history below; the
// remaining hardware facts as label/value rows.
//
// The power-profile pill reuses BatteryService: it is the module that owns
// the power-profiles-daemon state (label, color, cycling).
BarPopup {
    id: popup

    popupWidth: 370

    readonly property real temperature: SysInfoService.temperature
    readonly property color tempColor: Theme.temperatureColor(popup.temperature, Theme.fgColor)
    readonly property string tempText: SysInfoService.hasTemp
        ? Math.round(popup.temperature) + "\u00b0C" : "\u2014"

    function popupOpened() {
        SysInfoService.detail = true
        SysInfoService.refresh()
    }

    function popupClosed() {
        SysInfoService.detail = false
    }

    // Keybind surface (qs ipc call sysinfo toggle|open|close); one IpcHandler
    // per shell, so every popup registers itself instead of owning a handler.
    Component.onCompleted: SysInfoIpc.registerPopup(popup)
    Component.onDestruction: SysInfoIpc.unregisterPopup(popup)

    // Header: title + refresh + close
    Item {
        width: parent.width
        height: 26

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "System info"
            color: Theme.fgColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            Icon {
                glyph: "\ue01a" // arrow-clockwise (refresh)
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: SysInfoService.refresh()
                }
            }

            Icon {
                glyph: "\ue02f" // dismiss
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: popup.visible = false
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // Header card: cores + global frequency | temperature | power profile
    // ------------------------------------------------------------------
    Rectangle {
        id: headerCard
        width: parent.width
        radius: 6
        color: Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.05)
        border.width: 1
        border.color: Theme.buttonBorder
        implicitHeight: coreColumn.implicitHeight + 22

        Column {
            id: coreColumn
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Row {
                id: coreCountRow
                spacing: 5

                Text {
                    id: coreCount
                    text: SysInfoService.coresLogical > 0 ? SysInfoService.coresLogical : "\u2014"
                    color: Theme.fgColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 8
                    font.bold: true
                    font.features: { "tnum": 1 }
                }

                Text {
                    anchors.baseline: coreCount.baseline
                    text: "CORES"
                    color: Theme.fgColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 4
                    font.bold: true
                    font.letterSpacing: 1
                }
            }

            Text {
                text: SysInfoService.formatFreq(SysInfoService.freqMHz)
                color: Theme.fgColorMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
                font.features: { "tnum": 1 }
            }
        }

        Row {
            id: tempRow
            anchors.centerIn: parent
            spacing: 6

            Icon {
                anchors.baseline: tempValue.baseline
                glyph: "\ue044" // temperature
                color: popup.tempColor
                font.pixelSize: Math.round(Theme.fontSize * 1.7)
            }

            Text {
                id: tempValue
                text: popup.tempText
                color: popup.tempColor
                font.family: Theme.fontFamily
                font.pixelSize: Math.round(Theme.fontSize * 2.3)
                font.bold: true
                font.features: { "tnum": 1 }
            }
        }

        Rectangle {
            id: profilePill
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: profileText.implicitWidth + 16
            height: 22
            radius: 11
            color: Qt.rgba(BatteryService.powerProfileColor.r, BatteryService.powerProfileColor.g,
                           BatteryService.powerProfileColor.b, 0.35)
            border.width: 1
            border.color: Theme.buttonBorder

            Text {
                id: profileText
                anchors.centerIn: parent
                text: BatteryService.powerProfileLabel
                color: Theme.fgColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 4
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: BatteryService.cyclePowerProfile()
            }
        }
    }

    // ------------------------------------------------------------------
    // Charts: per-core load bars + usage history line
    // ------------------------------------------------------------------
    Row {
        id: chartsRow
        width: parent.width
        spacing: 12

        Column {
            id: coreChart
            width: Math.round((popup.contentWidth - chartsRow.spacing) * 0.42)
            spacing: 4

            Item {
                width: parent.width
                height: 14

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "PER CORE"
                    color: Theme.fgColorMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 5
                    font.letterSpacing: 1.5
                }
            }

            Rectangle {
                width: parent.width
                height: 58
                radius: 4
                color: Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.04)
                border.width: 1
                border.color: Theme.buttonBorder

                // Plain Item, NOT a Row: a Row derives its implicitWidth from
                // the delegates, whose width comes from barWidth, which reads
                // this width -> Qt discards barWidth as a binding loop (0).
                Item {
                    id: coreBars
                    readonly property int coreCount: Math.max(1, SysInfoService.coreUsage.length)
                    readonly property int gap: 2

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: baseline.top
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    anchors.bottomMargin: 5
                    height: parent.height - 16

                    Repeater {
                        model: SysInfoService.coreUsage

                        delegate: Rectangle {
                            required property int modelData
                            required property int index

                            // Computed here (like `height`): a barWidth property on
                            // coreBars gets its binding dropped as a loop -> 0.
                            width: Math.max(2, Math.floor((coreBars.width
                                - coreBars.gap * (coreBars.coreCount - 1)) / coreBars.coreCount))
                            height: Math.max(2, Math.round(coreBars.height * modelData / 100))
                            x: index * (width + coreBars.gap)
                            anchors.bottom: coreBars.bottom
                            radius: 1
                            color: Qt.rgba(Theme.accentColor.r, Theme.accentColor.g,
                                           Theme.accentColor.b, 0.5 + 0.5 * modelData / 100)
                        }
                    }
                }

                // Baseline the bars sit on
                Rectangle {
                    id: baseline
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4
                    height: 1
                    color: Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.25)
                }
            }
        }

        Column {
            id: usageChart
            width: popup.contentWidth - coreChart.width - chartsRow.spacing
            spacing: 4

            Item {
                width: parent.width
                height: 14

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "USAGE"
                    color: Theme.fgColorMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 5
                    font.letterSpacing: 1.5
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: SysInfoService.usageReady ? Math.round(SysInfoService.usage) + "%" : "\u2014"
                    color: Theme.fgColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 5
                    font.letterSpacing: 1.5
                    font.features: { "tnum": 1 }
                }
            }

            Rectangle {
                width: parent.width
                height: 58
                radius: 4
                color: Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.04)
                border.width: 1
                border.color: Theme.buttonBorder

                Canvas {
                    id: usageCanvas
                    // Repaint whenever a new sample lands (or the box resizes)
                    property var samples: SysInfoService.history
                    onSamplesChanged: usageCanvas.requestPaint()
                    onWidthChanged: usageCanvas.requestPaint()
                    onHeightChanged: usageCanvas.requestPaint()
                    Component.onCompleted: usageCanvas.requestPaint()

                    anchors.fill: parent
                    anchors.margins: 5

                    function css(c, a) {
                        return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255)
                            + "," + Math.round(c.b * 255) + "," + a + ")"
                    }

                    onPaint: {
                        const ctx = getContext("2d")
                        const w = width
                        const h = height
                        ctx.clearRect(0, 0, w, h)
                        if (w <= 0 || h <= 0)
                            return

                        // 100 / 50 / 0 % grid
                        ctx.lineWidth = 1
                        ctx.strokeStyle = usageCanvas.css(Theme.fgColor, 0.12)
                        for (let g = 0; g <= 2; g++) {
                            const y = Math.round(1 + (h - 3) * g / 2) + 0.5
                            ctx.beginPath()
                            ctx.moveTo(0, y)
                            ctx.lineTo(w, y)
                            ctx.stroke()
                        }

                        const s = usageCanvas.samples
                        if (s === undefined || s === null || s.length < 2)
                            return
                        const n = s.length
                        const dx = w / (n - 1)
                        const yOf = v => h - 1 - (Math.max(0, Math.min(100, v)) / 100) * (h - 3)

                        // Area under the curve
                        ctx.beginPath()
                        ctx.moveTo(0, h)
                        for (let i = 0; i < n; i++)
                            ctx.lineTo(i * dx, yOf(s[i]))
                        ctx.lineTo(w, h)
                        ctx.closePath()
                        ctx.fillStyle = usageCanvas.css(Theme.accentColor, 0.18)
                        ctx.fill()

                        // Curve itself
                        ctx.beginPath()
                        ctx.moveTo(0, yOf(s[0]))
                        for (let i = 1; i < n; i++)
                            ctx.lineTo(i * dx, yOf(s[i]))
                        ctx.strokeStyle = usageCanvas.css(Theme.accentColor, 0.9)
                        ctx.lineWidth = 1.5
                        ctx.lineJoin = "round"
                        ctx.lineCap = "round"
                        ctx.stroke()
                    }
                }
            }
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.popupBorderColor
    }

    // ------------------------------------------------------------------
    // Hardware facts
    // ------------------------------------------------------------------
    Column {
        width: parent.width
        spacing: 2

        Text {
            text: "CPU"
            color: Theme.fgColorMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 5
            font.letterSpacing: 1.5
        }

        Text {
            width: parent.width
            text: SysInfoService.modelName !== "" ? SysInfoService.modelName : "\u2014"
            color: Theme.fgColor
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
    }

    component InfoRow: Item {
        property string label: ""
        property string value: ""
        property string glyph: ""
        width: popup.contentWidth
        height: 20

        Icon {
            id: rowIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            // Zero width when unused so the label starts at the left edge
            width: parent.glyph !== "" ? implicitWidth : 0
            glyph: parent.glyph
            color: Theme.accentColor
            font.pixelSize: Theme.fontSize - 2
        }

        Text {
            id: rowLabel
            anchors.left: rowIcon.right
            anchors.leftMargin: parent.glyph !== "" ? 6 : 0
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label
            color: Theme.fgColor
            opacity: 0.6
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }

        Text {
            anchors.left: rowLabel.right
            anchors.leftMargin: 8
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: parent.value
            color: Theme.fgColor
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
            font.features: { "tnum": 1 }
        }
    }

    InfoRow {
        label: "Cores"
        glyph: "\ue085" // cpu
        value: SysInfoService.formatCores()
    }

    InfoRow {
        label: "Load"
        glyph: "\ue084" // chart-bars
        value: SysInfoService.formatLoad()
    }

    InfoRow {
        label: "Frequency"
        glyph: "\ue086" // gauge
        value: SysInfoService.formatFreq(SysInfoService.freqMHz)
            + (SysInfoService.freqMaxMHz > 0
                ? "   \u00b7   max " + SysInfoService.formatFreq(SysInfoService.freqMaxMHz) : "")
    }

    InfoRow {
        label: "Governor"
        glyph: "\ue071" // settings
        value: SysInfoService.governor !== ""
            ? SysInfoService.governor + (SysInfoService.energyPref !== ""
                ? " \u00b7 " + SysInfoService.energyPref : "")
            : "\u2014"
    }
}
