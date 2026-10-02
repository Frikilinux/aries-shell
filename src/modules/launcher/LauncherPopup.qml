pragma ComponentBehavior: Bound

import QtQuick
import "../theme"
import "../icon"
import "../popup"

// Application launcher popup. A search box on top (fuzzy match over the app
// name, description and categories) plus a ranked result list. The best match
// is selected by default; Up/Down move the selection, Enter launches it.
BarPopup {
    id: popup

    // Screen this popup belongs to (provided by the `Variants` delegate in
    // shell.qml). Overriding `screen` makes this an anchorless overlay.
    required property var modelData
    screen: modelData

    popupWidth: 460
    maxContentHeight: 520

    // The launcher opens centred on the screen, not under a bar icon.
    centered: true

    readonly property var results: LauncherService.results

    // Keyboard-selected result (0 = best match).
    property int selected: 0
    readonly property int rowHeight: 42
    readonly property int listMaxHeight: 360

    function popupOpened() {
        LauncherService.query = ""
        searchField.text = ""
        popup.selected = 0
        Qt.callLater(() => searchField.forceActiveFocus())
    }

    function popupClosed() {
        searchField.text = ""
        LauncherService.query = ""
        popup.selected = 0
    }

    // Move the selection by `step`, wrapping around.
    function moveSelection(step) {
        const n = popup.results.length
        if (n === 0)
            return
        popup.selected = (popup.selected + step + n) % n
        resultsView.positionViewAtIndex(popup.selected, ListView.Contain)
    }

    // Launch the selected result and close the popup.
    function activateSelected() {
        const n = popup.results.length
        if (n === 0)
            return
        const rec = popup.results[Math.max(0, Math.min(popup.selected, n - 1))]
        popup.visible = false
        LauncherService.launch(rec.entry)
    }

    // Register with the IPC control surface so a keybind can open/close this
    // popup (see LauncherIpc.qml).
    Component.onCompleted: LauncherIpc.registerPopup(popup)
    Component.onDestruction: LauncherIpc.unregisterPopup(popup)

    // Search box (grid icon + editable query).
    Rectangle {
        width: popup.contentWidth
        height: 34
        radius: 6
        color: Qt.rgba(0, 0, 0, 0.25)
        border.width: 1
        border.color: searchField.activeFocus ? Theme.accentColor : Theme.buttonBorder

        Icon {
            id: searchIcon
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            glyph: LauncherService.glyph
            color: Theme.fgColorMuted
            font.pixelSize: Theme.fontSize - 2
        }

        Text {
            anchors.left: searchIcon.right
            anchors.leftMargin: 8
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            visible: searchField.text === ""
            text: "Search applications\u2026"
            color: Theme.fgColorMuted
            opacity: 0.5
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
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
                LauncherService.query = text
                popup.selected = 0
                resultsView.positionViewAtBeginning()
            }
            onAccepted: popup.activateSelected()

            Keys.onDownPressed: event => {
                popup.moveSelection(1)
                event.accepted = true
            }
            Keys.onUpPressed: event => {
                popup.moveSelection(-1)
                event.accepted = true
            }
            Keys.onEscapePressed: event => {
                popup.visible = false
                event.accepted = true
            }
        }
    }

    // Separator.
    Rectangle {
        width: popup.contentWidth
        height: 1
        color: Theme.popupBorderColor
    }

    // Ranked results.
    ListView {
        id: resultsView
        width: popup.contentWidth
        height: Math.min(popup.results.length * popup.rowHeight, popup.listMaxHeight)
        implicitHeight: height
        model: popup.results
        currentIndex: popup.selected
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        onCountChanged: {
            if (popup.selected >= count)
                popup.selected = Math.max(0, count - 1)
        }

        delegate: Item {
            id: row
            required property var modelData
            required property int index

            readonly property bool isSelected: row.index === popup.selected

            width: resultsView.width
            height: popup.rowHeight

            Rectangle {
                anchors.fill: parent
                radius: 6
                color: row.isSelected
                    ? Qt.rgba(Theme.accentColor.r, Theme.accentColor.g, Theme.accentColor.b, 0.22)
                    : (rowMouse.containsMouse
                        ? Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.08)
                        : "transparent")
            }

            Item {
                id: iconBox
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 22
                height: 22

                Image {
                    id: appIcon
                    anchors.fill: parent
                    source: LauncherService.iconSource(row.modelData.entry)
                    sourceSize.width: 22
                    sourceSize.height: 22
                    fillMode: Image.PreserveAspectFit
                    visible: status === Image.Ready
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 4
                    color: Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.12)
                    visible: appIcon.status !== Image.Ready

                    Text {
                        anchors.centerIn: parent
                        text: row.modelData.name ? row.modelData.name.charAt(0).toUpperCase() : "?"
                        color: Theme.fgColorMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 6
                        font.bold: true
                    }
                }
            }

            Column {
                anchors.left: iconBox.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                    width: parent.width
                    text: LauncherService.highlight(
                        row.modelData.name,
                        row.modelData.nameHits,
                        Theme.accentColor.toString())
                    textFormat: Text.StyledText
                    color: Theme.fgColor
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    font.bold: true
                }

                Text {
                    width: parent.width
                    text: LauncherService.highlight(
                        row.modelData.subtitle,
                        row.modelData.subHits,
                        Theme.accentColor.toString())
                    textFormat: Text.StyledText
                    visible: row.modelData.subtitle !== ""
                    color: Theme.fgColorMuted
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 3
                }
            }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: popup.selected = row.index
                onClicked: {
                    popup.selected = row.index
                    popup.activateSelected()
                }
            }
        }
    }

    // Empty state.
    Text {
        width: popup.contentWidth
        text: "No matching applications"
        color: Theme.fgColorMuted
        horizontalAlignment: Text.AlignHCenter
        visible: popup.results.length === 0
        topPadding: 12
        bottomPadding: 12
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
    }
}
