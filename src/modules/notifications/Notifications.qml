import QtQuick
import "../theme"
import "../icon"
import "../config"
import "../widgets"

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

    // The popup window, exposed for shell.qml.
    property alias popup: historyPopup

    readonly property bool dndOn: NotificationService.dnd
    readonly property int unread: NotificationService.unread
    // An unread critical notification outranks DND: it is the only visible
    // signal when toasts are suppressed (DND) or simply not looked at yet.
    readonly property bool critical: NotificationService.unreadCritical

    // The pill only appears while there is an unread count to show; with DND on
    // and nothing unread the module shows the bare dimmed bell-off icon.
    readonly property bool counted: notifications.unread > 0
    readonly property int animationTime: Config.settings.bar.animation

    implicitWidth: notifications.counted ? container.width : indicator.implicitWidth
    implicitHeight: notifications.counted ? container.height : Math.max(indicator.implicitHeight, 1)

    // Module is visible only if outputs property is unset, matches this output, or contains it
    visible: (notifications.counted || notifications.dndOn) && (!outputs || (Array.isArray(outputs) ? outputs.includes(output) : outputs === output))

    // Pill behind the icon + count pair (see widgets/Pill.qml). Its edge is
    // inset by Theme.iconInset per side so it aligns with the ink edge of
    // bare icon modules and the external gap to neighbours matches
    // module-to-module spacing.
    Pill {
        id: container
        anchors.centerIn: parent
        visible: notifications.counted
        contentWidth: indicator.implicitWidth + countText.implicitWidth + Theme.innerGap
        contentHeight: Math.max(indicator.implicitHeight, countText.implicitHeight)
        fillColor: notifications.critical ? Theme.urgencyCriticalColor : Theme.buttonBorder
        fillOpacity: 0.4
        borderColor: notifications.critical ? Theme.urgencyCriticalColor : Theme.buttonBorder
        borderWidth: 1
        animationTime: notifications.animationTime
    }

    Icon {
        id: indicator
        anchors.left: parent.left
        anchors.leftMargin: notifications.counted ? Theme.iconInset + Theme.pillPadding : 0
        anchors.verticalCenter: parent.verticalCenter
        // bell-urgent for unread critical, bell-off while DND is on, bell otherwise
        glyph: notifications.critical ? "\ue07b" : (notifications.dndOn ? "\ue07a" : (notifications.unread ? "\ue07c" : ""))
        color: Theme.fgBarColor
        opacity: (notifications.counted || notifications.dndOn) ? 1 : 0.6
    }

    // Unread count on the right side of the icon, inside the pill.
    Text {
        id: countText
        anchors.left: indicator.right
        anchors.leftMargin: Theme.innerGap
        anchors.verticalCenter: parent.verticalCenter
        visible: notifications.counted
        text: notifications.unread > 99 ? "99+" : String(notifications.unread)
        color: Theme.fgBarColor
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 4
        font.bold: true
        font.features: ({
                "tnum": 1
            })
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function (mouse) {
            if (mouse.button === Qt.MiddleButton)
                NotificationService.toggleDnd();
            else
                historyPopup.visible = !historyPopup.visible;
        }
    }

    NotificationHistory {
        id: historyPopup
        anchorItem: notifications
    }
}
