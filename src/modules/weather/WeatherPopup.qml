import QtQuick
import "../theme"
import "../icon"
import "../popup"

BarPopup {
    id: popup

    popupWidth: 320

    // Icon style used by this popup's icons. Defaults to Theme.iconStyle.
    property string iconStyle: Theme.iconStyle

    // One label/value line in the details list
    component DetailRow: Item {
        required property string label
        required property string value

        width: popup.contentWidth
        height: 22

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label
            color: Theme.fgColor
            opacity: 0.6
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }

        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: parent.value
            color: Theme.fgColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.features: ({ "tnum": 1 })
        }
    }

    // Single day in the 3-day forecast row
    component DayTile: Rectangle {
        required property var modelData

        width: (popup.contentWidth - 12) / 3
        height: 90
        radius: 6
        color: Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.06)

        Column {
            anchors.fill: parent
            anchors.margins: 4
            // anchors.topMargin: 8
            // anchors.bottomMargin: 8
            // anchors.leftMargin: 4
            // anchors.rightMargin: 4
            spacing: 4

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: WeatherService.formatDay(parent.parent.modelData.dt)
                color: Theme.fgColorMuted
                // opacity: 0.6
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }

            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                glyph: WeatherService.iconGlyphFor(parent.parent.modelData.weather[0].icon)
                style: popup.iconStyle
                font.pixelSize: Math.round( Theme.iconSize * 2 )
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: Math.round(parent.parent.modelData.temp.min) + "° / "
                    + Math.round(parent.parent.modelData.temp.max) + "°"
                color: Theme.fgColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
                font.features: ({ "tnum": 1 })
            }
        }
    }

    function popupOpened() {
        WeatherService.refresh()
    }

    // Header: title + refresh + close
    Item {
        width: parent.width
        height: 26

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Weather"
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
                style: popup.iconStyle
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: WeatherService.refresh()
                }
            }

            Icon {
                glyph: "\ue02f" // dismiss
                style: popup.iconStyle
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: popup.visible = false
                }
            }
        }
    }

    // Current conditions: big icon + temperature + description
    Item {
        width: popup.contentWidth
        height: Math.max(bigIcon.implicitHeight, tempCol.implicitHeight)

        Icon {
            id: bigIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            glyph: WeatherService.failed ? "\ue049" : WeatherService.iconGlyph
            style: popup.iconStyle
            font.pixelSize: Math.round(Theme.iconSize * 3)
            opacity: WeatherService.available ? 1 : 0.4
        }

        Column {
            id: tempCol
            anchors.left: bigIcon.right
            anchors.leftMargin: 12
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                width: parent.width
                text: WeatherService.available ? WeatherService.temp + "°C" : "\u2014"
                color: Theme.fgColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 6
                font.bold: true
                font.features: ({ "tnum": 1 })
            }

            Row {
                width: parent.width
                spacing: 8

                Text {
                    width: parent.width - parent.spacing - feelsLikeText.implicitWidth
                    text: WeatherService.available
                        ? WeatherService.description
                        : WeatherService.failed ? "Weather unavailable" : "Fetching weather\u2026"
                    color: Theme.fgColor
                    opacity: 0.7
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    elide: Text.ElideRight
                }

                Text {
                    id: feelsLikeText
                    text: WeatherService.available ? "Feels like " + WeatherService.feelsLike + "°C" : ""
                    color: Theme.fgColor
                    opacity: 0.6
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    font.features: ({ "tnum": 1 })
                }
            }
        }
    }

    // Separator
    Rectangle {
        width: popup.contentWidth
        height: 1
        color: Theme.popupBorderColor
    }

    DetailRow {
        label: "Min / Max"
        value: WeatherService.available
            ? WeatherService.tempMin + "° / " + WeatherService.tempMax + "°"
            : "\u2014"
    }

    DetailRow {
        label: "Humidity"
        value: WeatherService.available ? WeatherService.humidity + "%" : "\u2014"
    }

    DetailRow {
        label: "Wind"
        value: WeatherService.available
            ? Math.round(WeatherService.windSpeed * 3.6) + " km/h " + WeatherService.windDirection(WeatherService.windDeg)
            : "\u2014"
    }

    // 3-day forecast section
    Row {
        visible: WeatherService.forecastDays.length > 0
        width: popup.contentWidth
        spacing: 6

        Repeater {
            model: WeatherService.forecastDays
            delegate: DayTile {}
        }
    }
}
