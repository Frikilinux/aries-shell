import QtQuick
import Quickshell
import "../theme"
import "../icon"

// A single row of a tray context menu (owned by TrayMenu). Renders one
// QsMenuEntry: separator, optional icon, label, check/radio indicator and
// submenu chevron. Hover highlights the row, forwards activations to the
// owning menu and reports itself so the menu can track keyboard focus.
Item {
    id: row

    required property var modelData
    readonly property var entry: modelData

    // The TrayMenu this row belongs to (focus + activation callbacks)
    required property var menu
    // Whether this row holds the keyboard focus
    property bool focused: false

    // Row metrics and text metrics (label width is computed via FontMetrics so
    // the row can size itself before its visual children exist)
    property int rowHeight: 34
    property int separatorHeight: 9
    property int sidePadding: 10
    property int iconSize: 16
    property int maxLabelWidth: 280

    FontMetrics {
        id: fm
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 2
    }

    readonly property real labelWidth: Math.min(row.maxLabelWidth, fm.advanceWidth(row.entry.text))

    readonly property bool rowSeparator: row.entry.isSeparator
    readonly property bool rowEnabled: row.entry.enabled
    readonly property bool hasIcon: !row.rowSeparator && row.entry.icon !== ""
    readonly property bool isCheckable: !row.rowSeparator
        && row.entry.buttonType !== QsMenuButtonType.None
    readonly property bool showsChevron: !row.rowSeparator && row.entry.hasChildren
    readonly property bool hasTrailing: row.isCheckable || row.showsChevron
    readonly property real leadingWidth: row.hasIcon ? row.iconSize + 8 : 0
    readonly property real trailingWidth: row.hasTrailing ? row.iconSize + 8 : 0

    height: row.rowSeparator ? row.separatorHeight : row.rowHeight

    implicitWidth: row.rowSeparator
        ? 40
        : row.sidePadding * 2 + row.leadingWidth + row.labelWidth + row.trailingWidth

    // Separator line
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: row.sidePadding + 4
        anchors.rightMargin: row.sidePadding + 4
        height: 1
        radius: 0.5
        color: Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.18)
        visible: row.rowSeparator
    }

    // Clickable content (hidden for separators)
    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        visible: !row.rowSeparator
        radius: Theme.popupRadius - 5
        color: row.rowEnabled && (rowMouse.containsMouse || row.focused)
            ? Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.12)
            : "transparent"

        Row {
            anchors.fill: parent
            anchors.leftMargin: row.sidePadding
            anchors.rightMargin: row.sidePadding
            spacing: 8

            Image {
                width: row.iconSize
                height: row.iconSize
                anchors.verticalCenter: parent.verticalCenter
                visible: row.hasIcon
                source: row.entry.icon
                sourceSize.width: row.iconSize * Screen.devicePixelRatio
                sourceSize.height: row.iconSize * Screen.devicePixelRatio
                fillMode: Image.PreserveAspectFit
            }

            Text {
                id: label
                width: Math.max(0, parent.width - row.leadingWidth - row.trailingWidth)
                anchors.verticalCenter: parent.verticalCenter
                text: row.entry.text
                color: row.rowEnabled
                    ? Theme.fgColor
                    : Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.4)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
                elide: Text.ElideRight
            }

            // Check/radio indicator or submenu chevron at the trailing edge
            Item {
                width: row.trailingWidth
                height: parent.height
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.centerIn: parent
                    visible: row.isCheckable && !row.showsChevron
                    width: row.iconSize - 2
                    height: row.iconSize - 2
                    radius: row.entry.buttonType === QsMenuButtonType.RadioButton
                        ? (row.iconSize - 2) / 2
                        : 4
                    color: row.entry.checkState !== Qt.Unchecked
                        ? Theme.accentColor
                        : "transparent"
                    border.width: 1
                    border.color: row.entry.checkState !== Qt.Unchecked
                        ? Theme.accentColor
                        : Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.4)
                }

                Icon {
                    anchors.centerIn: parent
                    visible: row.showsChevron
                    glyph: "\ue02c" // chevron-right
                    font.pixelSize: row.iconSize - 1
                }
            }
        }
    }

    MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: row.rowEnabled && !row.rowSeparator ? Qt.PointingHandCursor : Qt.ArrowCursor
        onEntered: row.menu.rowHovered(row)
        onClicked: row.menu.rowClicked(row)
    }
}