import QtQuick
import "../theme"
import "../icon"

// Bar indicator: shows the unread notification count and opens the history
// popup on click. Middle-click toggles Do-Not-Disturb. While DND is on the icon
// becomes the bell-off glyph.
Item {
    id: notifications

    // Show this module only on specific outputs (monitors).
    // Set to a string ("HDMI-A-1") or array (["eDP-1"]). If undefined/null, shows on all.
    property var outputs
    // The output being rendered.
    property string output: ""

    // The popup window, exposed so shell.qml can configure it (e.g. popup.iconStyle)
    property alias popup: historyPopup
    // Icon style used by this module's bar icon. Defaults to Theme.iconStyle.
    property string iconStyle: Theme.iconStyle

    readonly property bool dndOn: NotificationService.dnd
    readonly property int unread: NotificationService.unread
    // An unread critical notification outranks DND: it is the only visible
    // signal when toasts are suppressed (DND) or simply not looked at yet.
    readonly property bool critical: NotificationService.unreadCritical

    // Icon only: the unread count rides on a badge overlaid on the corner.
    implicitWidth: indicator.implicitWidth
    implicitHeight: indicator.implicitHeight

    // Module is visible only if outputs property is unset, matches this output, or contains it
    visible: !outputs || (Array.isArray(outputs) ? outputs.includes(output) : outputs === output)

    Icon {
        id: indicator
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        // bell-urgent for unread critical, bell-off while DND is on, bell otherwise
        glyph: notifications.critical ? "\ue07b" : (notifications.dndOn ? "\ue07a" : "\ue07c")
        color: notifications.critical ? Theme.urgencyCriticalColor : Theme.fgBarColor
        opacity: (notifications.unread > 0 || notifications.dndOn) ? 1 : 0.6
    }

    // Unread count: circular badge pinned to the icon's top-left corner. It grows
    // into a pill for multi-digit counts.
    Rectangle {
        id: badge
        anchors.left: indicator.left
        anchors.top: indicator.top
        anchors.leftMargin: -3
        anchors.topMargin: -3
        width: Math.max(13, badgeText.implicitWidth + 6)
        height: 13
        radius: height / 2
        visible: notifications.unread > 0
        color: Theme.accentColor
        border.color: Theme.bgBarColor

        Text {
            id: badgeText
            anchors.centerIn: parent
            text: notifications.unread > 99 ? "99+" : String(notifications.unread)
            color: Theme.bgBarColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 8
            font.bold: true
            font.features: ({ "tnum": 1 })
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function (mouse) {
            if (mouse.button === Qt.MiddleButton)
                NotificationService.toggleDnd()
            else
                historyPopup.visible = !historyPopup.visible
        }
    }

    NotificationHistory {
        id: historyPopup
        anchorItem: notifications
        iconStyle: notifications.iconStyle
    }
}
