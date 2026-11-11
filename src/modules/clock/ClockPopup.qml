pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../theme"
import "../icon"
import "../popup"
import "../widgets"

// Calendar popup: upcoming events from GNOME Calendar (Evolution Data Server).
BarPopup {
    id: popup

    popupWidth: 340
    maxContentHeight: 420

    function popupOpened() {
        CalendarService.refresh(false)
    }

    // Events enriched with a day label for sectioning.
    readonly property var viewEvents: {
        const out = []
        const list = CalendarService.events || []
        for (let i = 0; i < list.length; i++) {
            const e = list[i]
            const d = new Date(e.start * 1000)
            out.push(Object.assign({}, e, {
                day: Qt.formatDate(d, "ddd d MMM"),
                time: e.allDay ? "All day" : Qt.formatTime(d, "HH:mm")
            }))
        }
        return out
    }

    // Fixed header
    header: Item {
        width: parent.width
        height: 33

        Item {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 26

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Calendar"
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
                    glyph: "\ue01a" // refresh
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: CalendarService.refresh(true)
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

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Theme.borderColorRest
        }
    }

    // Loading state
    Text {
        width: popup.contentWidth
        text: "Loading…"
        color: Theme.fgColorMuted
        horizontalAlignment: Text.AlignHCenter
        visible: CalendarService.loading && popup.viewEvents.length === 0
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
        topPadding: 12
        bottomPadding: 12
    }

    // Error state
    Text {
        width: popup.contentWidth
        text: "Calendar unavailable"
        color: Theme.fgColorMuted
        horizontalAlignment: Text.AlignHCenter
        visible: CalendarService.failed && popup.viewEvents.length === 0
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
        topPadding: 12
        bottomPadding: 12
    }

    // Empty state
    Text {
        width: popup.contentWidth
        text: "No upcoming events"
        color: Theme.fgColorMuted
        horizontalAlignment: Text.AlignHCenter
        visible: !CalendarService.loading && !CalendarService.failed && popup.viewEvents.length === 0
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
        topPadding: 12
        bottomPadding: 12
    }

    ListView {
        id: eventList
        width: popup.contentWidth
        height: contentHeight
        model: popup.viewEvents
        spacing: 2
        clip: true

        section.property: "day"
        section.criteria: ViewSection.FullString
        section.delegate: Item {
            width: eventList.width
            height: 22

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: eventList.section
                color: Theme.fgColorMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
                font.bold: true
                font.letterSpacing: 1
            }
        }

        delegate: Item {
            id: eventRow
            required property var modelData
            width: eventList.width
            height: 34

            Rectangle {
                anchors.fill: parent
                radius: 4
                color: Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.04)
            }

            Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 8

                Text {
                    width: 52
                    text: eventRow.modelData.time
                    color: Theme.accentColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                    font.bold: true
                    font.features: ({
                            "tnum": 1
                        })
                }

                Column {
                    width: parent.width - 60
                    spacing: 0

                    Text {
                        width: parent.width
                        text: eventRow.modelData.summary !== "" ? eventRow.modelData.summary : "(No title)"
                        color: Theme.fgColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Text {
                        width: parent.width
                        text: eventRow.modelData.calendar
                        color: Theme.fgColorMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 4
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        visible: text !== ""
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (eventRow.modelData.uid !== "")
                        Quickshell.execDetached(["gnome-calendar", "-u", eventRow.modelData.uid])
                }
            }
        }
    }
}
