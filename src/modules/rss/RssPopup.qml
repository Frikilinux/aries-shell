pragma ComponentBehavior: Bound

import QtQuick
import "../theme"
import "../icon"
import "../popup"

BarPopup {
    id: popup

    popupWidth: 420

    // One news row: title (2 lines) + source · relative date. Clicking opens
    // the article's site and closes the popup; there is no read state.
    component NewsRow: Item {
        id: row
        required property var modelData

        width: popup.contentWidth
        height: title.implicitHeight + meta.implicitHeight + 14

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: over.containsMouse
                ? Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.06)
                : "transparent"
        }

        Column {
            id: textColumn
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            spacing: 2

            Text {
                id: title
                width: parent.width
                text: row.modelData.title
                color: Theme.fgColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
                elide: Text.ElideRight
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                maximumLineCount: 2
            }

            Text {
                id: meta
                text: row.modelData.source + " · " + RssService.formatRelative(row.modelData.time)
                color: Theme.fgColorMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
                elide: Text.ElideRight
            }
        }

        MouseArea {
            id: over
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                Qt.openUrlExternally(row.modelData.link)
                popup.visible = false
            }
        }
    }

    function popupOpened() {
        RssService.refresh()
    }

    // Header: title + refresh + close
    Item {
        width: parent.width
        height: 26

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: RssService.hasNews ? "News" : "RSS"
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
                    onClicked: {
                        RssService.invalidate()
                        RssService.refresh()
                    }
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

    // Status / empty state line (hidden while the popup has entries)
    Text {
        width: popup.contentWidth
        visible: RssService.displayed.length === 0
        horizontalAlignment: Text.AlignHCenter
        text: RssService.fetching ? "Fetching feeds\u2026"
            : RssService.failed ? "Feeds unreachable"
            : "No news"
        color: Theme.fgColorMuted
        opacity: RssService.failed ? 1 : 0.6
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
    }

    // Separator (only above a non-empty list)
    Rectangle {
        visible: RssService.displayed.length > 0
        width: popup.contentWidth
        height: 1
        color: Theme.popupBorderColor
    }

    Repeater {
        model: RssService.displayed
        delegate: NewsRow {}
    }
}
