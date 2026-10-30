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
        height: title.implicitHeight + metaRow.height + 14

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: over.containsMouse
                ? Theme.bgColorHover
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

            // Meta line: the feed url label (host) in the accent color, the
            // relative date stays muted. Source elides left; the date stays
            // fully visible (pinned right).
            Item {
                id: metaRow
                width: parent.width
                height: Math.max(sourceLabel.implicitHeight, dateLabel.implicitHeight)

                Text {
                    id: sourceLabel
                    anchors.left: parent.left
                    anchors.right: dateLabel.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.source
                    color: Theme.accentColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 3
                    elide: Text.ElideRight
                }

                Text {
                    id: dateLabel
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: " · " + RssService.formatRelative(row.modelData.time)
                    color: Theme.fgColorMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 3
                    elide: Text.ElideRight
                }
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
        color: Theme.borderColorRest
    }

    Repeater {
        model: RssService.displayed
        delegate: NewsRow {}
    }

    // Scroll hints (in the overlay layer, above the content): a soft bg fade
    // plus a chevron whenever hidden news sits above/below. The row fades and
    // the chevron is not interactive-blocking: plain Items don't grab mouse
    // events, so row clicks still land underneath; the chevron itself is
    // click-to-scroll (half a page per tap).
    overlay: [
        Item {
            id: topHint
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 22
            visible: popup.contentScrolls && !popup.scrollAtTop

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: popup.contentPadding
                anchors.rightMargin: popup.contentPadding
                anchors.topMargin: 2
                height: parent.height - 2
                radius: 6
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(popup.winColor.r, popup.winColor.g, popup.winColor.b, 0.8) }
                    GradientStop { position: 1.0; color: Qt.rgba(popup.winColor.r, popup.winColor.g, popup.winColor.b, 0.0) }
                }
            }

            Icon {
                anchors.centerIn: parent
                glyph: "\ue02d" // chevron-up
                color: Theme.fgColorMuted
                font.pixelSize: Theme.iconSize - 2
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: popup.contentFlick.flick(0, popup.height)
            }
        },

        Item {
            id: bottomHint
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 22
            visible: popup.contentScrolls && !popup.scrollAtBottom

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: popup.contentPadding
                anchors.rightMargin: popup.contentPadding
                anchors.bottomMargin: 2
                height: parent.height - 2
                radius: 6
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(popup.winColor.r, popup.winColor.g, popup.winColor.b, 0.0) }
                    GradientStop { position: 1.0; color: Qt.rgba(popup.winColor.r, popup.winColor.g, popup.winColor.b, 0.8) }
                }
            }

            Icon {
                anchors.centerIn: parent
                glyph: "\ue02a" // chevron-down
                color: Theme.fgColorMuted
                font.pixelSize: Theme.iconSize - 2
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: popup.contentFlick.flick(0, -popup.height)
            }
        }
    ]
}
