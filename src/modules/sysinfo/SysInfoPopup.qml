pragma ComponentBehavior: Bound

import QtQuick
import "../theme"
import "../icon"
import "../popup"

// CPU overview: three circular gauges (package temperature, total load and
// average frequency) up top; per-core load and usage history below; the
// remaining hardware facts as label/value rows.
BarPopup {
    id: popup

    popupWidth: 370

    readonly property real temperature: SysInfoService.temperature
    readonly property color tempColor: Theme.temperatureColor(popup.temperature, Theme.fgColor)

    // Gauge readings (display strings + 0..1 ring progress)
    readonly property string tempValue: SysInfoService.hasTemp
        ? Math.round(popup.temperature) : "\u2014"
    readonly property real tempRatio: SysInfoService.hasTemp
        ? Math.max(0, Math.min(1, popup.temperature / Math.max(1, SysInfoService.critTemp))) : 0

    readonly property string loadValue: SysInfoService.usageReady
        ? Math.round(SysInfoService.usage) : "\u2014"
    readonly property real loadRatio: SysInfoService.usageReady
        ? SysInfoService.usage / 100 : 0

    readonly property string freqValue: SysInfoService.hasFreq
        ? (SysInfoService.freqMHz / 1000).toFixed(1) : "\u2014"
    readonly property real freqScale: SysInfoService.maxFreqMHz > 0 ? SysInfoService.maxFreqMHz
        : (SysInfoService.freqMaxMHz > 0 ? SysInfoService.freqMaxMHz : 5000)
    readonly property real freqRatio: SysInfoService.hasFreq
        ? Math.max(0, Math.min(1, SysInfoService.freqMHz / Math.max(1, popup.freqScale))) : 0

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
    // Circular gauge (temperature / load / frequency)
    // ------------------------------------------------------------------
    component CircleGauge: Item {
        id: gauge

        required property string label
        required property string valueText
        required property string unitText
        required property real ratio
        required property color ringColor
        property color valueColor: Theme.fgColor

        readonly property int ringSize: Math.min(88, Math.max(48, gauge.width - 8))
        implicitHeight: ringSize + labelText.implicitHeight + 7

        function css(c, a) {
            return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255)
                + "," + Math.round(c.b * 255) + "," + a + ")"
        }

        Item {
            id: ringBox
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: gauge.ringSize
            height: gauge.ringSize

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.04)
                border.width: 1
                border.color: Theme.borderColorRest
            }

            Canvas {
                id: ringCanvas
                anchors.fill: parent
                antialiasing: true

                property real frac: Math.max(0, Math.min(1, gauge.ratio))
                onFracChanged: ringCanvas.requestPaint()
                onWidthChanged: ringCanvas.requestPaint()
                onHeightChanged: ringCanvas.requestPaint()
                Component.onCompleted: ringCanvas.requestPaint()

                onPaint: {
                    const ctx = getContext("2d")
                    const w = ringCanvas.width
                    const h = ringCanvas.height
                    ctx.clearRect(0, 0, w, h)
                    if (w <= 0 || h <= 0)
                        return

                    const lw = Math.max(3, Math.round(Math.min(w, h) * 0.08))
                    const r = (Math.min(w, h) - lw) / 2
                    const cx = w / 2
                    const cy = h / 2

                    ctx.lineWidth = lw
                    ctx.lineCap = "round"

                    // Full track ring
                    ctx.beginPath()
                    ctx.arc(cx, cy, r, 0, Math.PI * 2)
                    ctx.strokeStyle = gauge.css(Theme.fgColor, 0.12)
                    ctx.stroke()

                    // Value arc, clockwise from the top
                    if (ringCanvas.frac > 0) {
                        ctx.beginPath()
                        ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * ringCanvas.frac)
                        ctx.strokeStyle = gauge.css(gauge.ringColor, 1)
                        ctx.stroke()
                    }
                }
            }

            Row {
                anchors.centerIn: parent
                spacing: 2

                Text {
                    id: gaugeValue
                    text: gauge.valueText
                    color: gauge.valueColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 5
                    font.bold: true
                    font.features: { "tnum": 1 }
                }

                Text {
                    anchors.baseline: gaugeValue.baseline
                    text: gauge.unitText
                    visible: gauge.unitText !== ""
                    color: Theme.fgColorMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 5
                }
            }
        }

        Text {
            id: labelText
            anchors.top: ringBox.bottom
            anchors.topMargin: 5
            anchors.horizontalCenter: parent.horizontalCenter
            text: gauge.label
            color: Theme.fgColorMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 5
            font.letterSpacing: 1.5
        }
    }

    // ------------------------------------------------------------------
    // Gauges: temperature | load | frequency
    // ------------------------------------------------------------------
    Row {
        width: parent.width
        spacing: 4

        CircleGauge {
            width: (parent.width - parent.spacing * 2) / 3
            label: "TEMP"
            valueText: popup.tempValue
            unitText: "\u00b0C"
            ratio: popup.tempRatio
            ringColor: Theme.accentColor
            valueColor: popup.tempColor
        }

        CircleGauge {
            width: (parent.width - parent.spacing * 2) / 3
            label: "LOAD"
            valueText: popup.loadValue
            unitText: "%"
            ratio: popup.loadRatio
            ringColor: Theme.accentColor
        }

        CircleGauge {
            width: (parent.width - parent.spacing * 2) / 3
            label: "FREQ"
            valueText: popup.freqValue
            unitText: "GHz"
            ratio: popup.freqRatio
            ringColor: Theme.accentColor
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

            Text {
                text: "PER CORE"
                color: Theme.fgColorMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 5
                font.letterSpacing: 1.5
            }

            Rectangle {
                width: parent.width
                height: 58
                radius: 4
                color: Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.04)
                border.width: 1
                border.color: Theme.borderColorRest

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

            Text {
                text: "USAGE"
                color: Theme.fgColorMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 5
                font.letterSpacing: 1.5
            }

            Rectangle {
                width: parent.width
                height: 58
                radius: 4
                color: Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.04)
                border.width: 1
                border.color: Theme.borderColorRest

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
        color: Theme.borderColorRest
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

}
