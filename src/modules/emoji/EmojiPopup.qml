pragma ComponentBehavior: Bound

import QtQuick
import "../theme"
import "../icon"
import "../popup"

// Emoji picker popup. A search box on top (substring match over the emoji
// name and keywords) plus a grid; an empty query puts the recently used
// emojis first (deduped, EmojiService). Up/Down/Left/Right/PageUp/PageDown
// move the selection, Enter or a click inserts it: the popup closes, waits
// for the compositor to hand keyboard focus back to the target window (see
// EmojiService's typeTimer) and then `wtype` types the emoji as a keyboard
// input into whatever surface has focus — i.e. the text entry the popup was
// opened over.
BarPopup {
    id: popup

    // Screen this popup belongs to (provided by the `Variants` delegate in
    // shell.qml). Overriding `screen` makes this an anchorless overlay.
    required property var modelData
    screen: modelData

    // Grid geometry: everything derives from the config
    // (modules.emoji.tileSize / columns / rows, clamped in EmojiService).
    // cellSize adds breathing room (hover ring) around the emoji tile; the
    // popup width fits `columns` cells plus the content padding and the
    // height fits `rows` cells plus the search row (capped by the screen, in
    // which case the grid flicks).
    readonly property int cellSize: EmojiService.tileSize + 16
    readonly property int gridColumns: EmojiService.columns
    readonly property int gridHeight: EmojiService.rows * popup.cellSize
    popupWidth: popup.gridColumns * popup.cellSize + popup.contentPadding * 2
    maxContentHeight: popup.screen ? Math.min(popup.gridHeight + 64, Math.round(popup.screen.height) - 96) : popup.gridHeight + 64

    // The picker opens centred on the screen, not under a bar icon (niri does
    // not expose the caret position, and tiled windows have no reported
    // geometry, so "near the focused window" means the focused output).
    centered: true

    // Keyboard-first popup: keep Exclusive focus while open (no flick), so
    // typing works even with the pointer off the surface.
    holdKeyboardFocus: true

    readonly property var results: EmojiService.results

    // Keyboard-selected cell (0 = first).
    property int selected: 0

    function popupOpened() {
        EmojiService.query = ""
        searchField.text = ""
        popup.selected = 0
        Qt.callLater(() => searchField.forceActiveFocus())
    }

    function popupClosed() {
        searchField.text = ""
        EmojiService.query = ""
        popup.selected = 0
    }

    // Move the selection by `step`, wrapping around.
    function moveSelection(step) {
        const n = popup.results.length
        if (n === 0)
            return
        popup.selected = (popup.selected + step + n) % n
        resultsGrid.positionViewAtIndex(popup.selected, GridView.Contain)
    }

    // Insert the selected (or clicked) emoji and close the popup. The insert
    // itself is two-phase (see queueForTyping): the popup must be gone before
    // the typed characters are sent, or wtype would deliver them right back
    // into the search field.
    function activateSelected() {
        const n = popup.results.length
        if (n === 0)
            return
        const rec = popup.results[Math.max(0, Math.min(popup.selected, n - 1))]
        popup.visible = false
        EmojiService.queueForTyping(rec.c)
    }

    // Register with the IPC control surface so a keybind can open/close this
    // popup (see EmojiIpc.qml).
    Component.onCompleted: EmojiIpc.registerPopup(popup)
    Component.onDestruction: EmojiIpc.unregisterPopup(popup)

    // Search box (magnifier icon + editable query).
    Rectangle {
        width: popup.contentWidth
        height: 34
        radius: 6
        color: Qt.rgba(0, 0, 0, 0.25)
        border.width: 1
        border.color: searchField.activeFocus ? Theme.accentColor : Theme.borderColorRest

        Icon {
            id: searchIcon
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            glyph: EmojiService.glyph
            color: Theme.fgColorMuted
            font.pixelSize: Theme.fontSize - 2
        }

        Text {
            anchors.left: searchIcon.right
            anchors.leftMargin: 8
            anchors.right: recentsHint.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            visible: searchField.text === ""
            text: "Search emojis…"
            color: Theme.fgColorMuted
            opacity: 0.5
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }

        Text {
            id: recentsHint
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            visible: searchField.text === ""
            text: "Recent first"
            color: Theme.fgColorMuted
            opacity: 0.4
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 4
        }

        TextInput {
            id: searchField
            anchors.left: searchIcon.right
            anchors.leftMargin: 8
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.fgColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
            selectByMouse: true
            clip: true

            onTextEdited: {
                EmojiService.query = text
                popup.selected = 0
                resultsGrid.positionViewAtBeginning()
            }
            onAccepted: popup.activateSelected()

            Keys.onDownPressed: event => {
                popup.moveSelection(popup.gridColumns)
                event.accepted = true
            }
            Keys.onUpPressed: event => {
                popup.moveSelection(-popup.gridColumns)
                event.accepted = true
            }
            Keys.onRightPressed: event => {
                popup.moveSelection(1)
                event.accepted = true
            }
            Keys.onLeftPressed: event => {
                popup.moveSelection(-1)
                event.accepted = true
            }
            Keys.onPressed: event => {
                if (event.key === Qt.Key_PageDown) {
                    popup.moveSelection(popup.gridColumns * 5)
                    event.accepted = true
                } else if (event.key === Qt.Key_PageUp) {
                    popup.moveSelection(-popup.gridColumns * 5)
                    event.accepted = true
                }
            }
        }
    }

    // Emoji grid (virtualised: only visible cells exist at a time), wrapped
    // in a content-width item so the leftover partial column is centred, not
    // left-hugging. The grid is re-created with a fresh model on every open;
    // contentY is reset by onCountChanged so the popup always starts at the
    // top (recents first).
    Item {
        width: popup.contentWidth
        height: resultsGrid.height

        GridView {
            id: resultsGrid
            anchors.horizontalCenter: parent.horizontalCenter

            width: popup.gridColumns * popup.cellSize
            height: Math.min(popup.results.length * popup.cellSize, popup.gridHeight)
            implicitHeight: height
            model: popup.results
            cellWidth: popup.cellSize
            cellHeight: popup.cellSize
            currentIndex: popup.selected
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            onCountChanged: {
                contentY = 0
                returnToBounds()
                if (popup.selected >= count)
                    popup.selected = Math.max(0, count - 1)
            }

            delegate: Item {
                id: cell
                required property var modelData
                required property int index

                readonly property bool isSelected: cell.index === popup.selected

                width: resultsGrid.cellWidth
                height: resultsGrid.cellHeight

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: 6
                    color: cell.isSelected || cellMouse.containsMouse ? Theme.bgColorHover : "transparent"
                }

                Text {
                    anchors.centerIn: parent
                    text: cell.modelData.c
                    // Colour emoji: `font.family` accepts a comma-separated
                    // fallback list in Qt 6, so the emoji-capable family rides
                    // on the theme font (Apple Color Emoji is the colour
                    // source on most Arch setups; monochrome fallback if
                    // missing).
                    font.family: Theme.fontFamily + ", Apple Color Emoji"
                    font.pixelSize: EmojiService.tileSize
                }

                MouseArea {
                    id: cellMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // Hover is visual only: it must NOT move the keyboard
                    // selection, otherwise Enter would insert whatever sits
                    // under the pointer.
                    onClicked: {
                        popup.selected = cell.index
                        popup.activateSelected()
                    }
                }
            }
        }
    }

    // Empty state.
    Text {
        width: popup.contentWidth
        text: "No matching emojis"
        color: Theme.fgColorMuted
        horizontalAlignment: Text.AlignHCenter
        visible: popup.results.length === 0
        topPadding: 12
        bottomPadding: 12
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
    }
}
