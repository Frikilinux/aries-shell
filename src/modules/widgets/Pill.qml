import QtQuick
import "../theme"

// Rounded pill drawn behind a module's content (e.g. the notifications unread
// badge, the privacy capture icons). Height wraps the content exactly (no
// vertical padding); the content sits `hPadding` from the left/right edges.
// The item is wider than the pill by `Theme.iconInset` per side so the pill
// edge aligns with the ink edge of bare icon modules (see Theme.iconInset):
// that transparent inset is part of the module, not of the pill.
Item {
    id: root

    // Size of the content the pill wraps; set by the using module.
    property real contentWidth: 0
    property real contentHeight: 0
    // Space between the content and the pill's left/right edges.
    property int hPadding: Theme.pillPadding
    // Pill look (defaults: plain fill, no border).
    property color fillColor: Theme.buttonBgColor
    property real fillOpacity: 1.0
    property color borderColor: "transparent"
    property int borderWidth: 0
    // >0 animates width changes (content growing/shrinking) over this many ms.
    property int animationTime: 0

    implicitWidth: root.contentWidth + root.hPadding * 2 + Theme.iconInset * 2
    implicitHeight: root.contentHeight
    width: implicitWidth
    height: implicitHeight

    // Width rides on the item (not the inner rect) so consumers reading
    // `width` to size themselves follow the animation.
    Behavior on width {
        enabled: root.animationTime > 0
        NumberAnimation {
            duration: root.animationTime
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.fillColor
        opacity: root.fillOpacity
        border.width: root.borderWidth
        border.color: root.borderColor
    }
}
