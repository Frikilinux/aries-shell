pragma ComponentBehavior: Bound

import QtQuick
import "../theme"
import "../icon"
import "../popup"

// Capture viewer: a bar popup listing the applications currently using the
// microphone, the camera or the screen (fed by PrivacyService's per-category
// scan, so it always matches what the pill shows).
BarPopup {
    id: popup

    popupWidth: 320
    maxContentHeight: 420

    // Small icon button used in the header (close).
    component HeaderButton: Icon {
        id: button
        property color tint: Theme.fgColor

        color: tint
        font.pixelSize: Theme.fontSize + 1

        signal clicked

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }

    // One capture category: glyph + label, then one row per capturing app.
    component Section: Column {
        id: section
        required property string glyph
        required property string title
        required property var apps

        width: popup.contentWidth
        spacing: 4
        visible: section.apps.length > 0

        Row {
            spacing: 8

            Icon {
                glyph: section.glyph
                color: Theme.fgPrivacy
                font.pixelSize: Theme.iconSize + 2
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: section.title
                color: Theme.fgColorMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }
        }

        Repeater {
            model: section.apps

            delegate: Text {
                required property string modelData

                width: section.width
                leftPadding: 8
                text: modelData
                color: Theme.fgColor
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
            }
        }
    }

    // Header: title + close.
    Item {
        width: popup.contentWidth
        height: 26

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Privacy"
            color: Theme.fgColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
        }

        HeaderButton {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            glyph: "\ue02f" // dismiss
            tint: Theme.fgColor
            onClicked: popup.visible = false
        }
    }

    // Separator.
    Rectangle {
        width: popup.contentWidth
        height: 1
        color: Theme.borderColorRest
    }

    // Empty state (no capture while the popup is open).
    Text {
        width: popup.contentWidth
        text: "No active captures"
        color: Theme.fgColorMuted
        horizontalAlignment: Text.AlignHCenter
        visible: !PrivacyService.anyInUse
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
        topPadding: 12
        bottomPadding: 12
    }

    Section {
        glyph: "\ue08a" // microphone
        title: "Microphone"
        apps: PrivacyService.micApps
    }

    Section {
        glyph: "\ue08c" // webcam
        title: "Camera"
        apps: PrivacyService.cameraApps
    }

    Section {
        glyph: "\ue08b" // screen-share
        title: "Screen share"
        apps: PrivacyService.screenApps
    }
}
