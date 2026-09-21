import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Widgets
import "../theme"
import "../icon"
import "../popup"

BarPopup {
    id: popup

    // Icon style used by this popup's icons. Defaults to Theme.iconStyle.
    property string iconStyle: Theme.iconStyle

    property int artSize: 180

    // Best player: prefer playing, then paused, then any available. playerctld
    // is filtered out (it errors with NoActivePlayer when nothing is controlled).
    readonly property var player: {
        const players = Mpris.players.values.filter(
            p => !p.dbusName.startsWith("org.mpris.MediaPlayer2.playerctld"))
        if (players.length === 0)
            return null
        for (let i = 0; i < players.length; i++) {
            if (players[i].isPlaying)
                return players[i]
        }
        return players[0]
    }
    readonly property bool hasPlayer: player !== null
    readonly property bool isPlaying: hasPlayer && player.isPlaying

    // No player available
    Text {
        visible: !popup.hasPlayer
        width: parent.width
        text: "No active player"
        color: Theme.fgColor
        opacity: 0.6
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    // Album art
    ClippingRectangle {
        visible: popup.hasPlayer && popup.player.trackArtUrl !== ""
        width: popup.artSize
        height: popup.artSize
        anchors.horizontalCenter: parent.horizontalCenter
        radius: 8

        Image {
            width: parent.width
            height: parent.height
            source: popup.hasPlayer ? popup.player.trackArtUrl : ""
            fillMode: Image.PreserveAspectFit
            cache: true
        }
    }

    // Placeholder when no art
    Rectangle {
        visible: popup.hasPlayer && popup.player.trackArtUrl === ""
        width: popup.artSize
        height: popup.artSize
        anchors.horizontalCenter: parent.horizontalCenter
        radius: 8
        color: Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.08)
        border.width: 1
        border.color: Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.15)

        Icon {
            anchors.centerIn: parent
            glyph: "\ue06c" // headphones-sound-wave (no album art)
            style: popup.iconStyle
            font.pixelSize: 36
            color: Theme.fgColor
            opacity: 0.4
        }
    }

    // Track info
    Column {
        visible: popup.hasPlayer
        width: parent.width
        spacing: 2

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: popup.player ? popup.player.trackTitle : ""
            color: Theme.fgColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 1
            font.bold: true
            maximumLineCount: 2
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        }

        Text {
            visible: popup.player && popup.player.trackArtist !== ""
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: popup.player ? popup.player.trackArtist : ""
            color: Theme.accentColor
            // color: Qt.rgba(Theme.accentColor.r, Theme.accentColor.g, Theme.accentColor.b, 0.7)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            maximumLineCount: 1
            elide: Text.ElideRight
        }

        Text {
            visible: popup.player && popup.player.trackAlbum !== ""
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: popup.player ? popup.player.trackAlbum : ""
            color: Theme.fgColor
            opacity: 0.5
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
            maximumLineCount: 1
            elide: Text.ElideRight
        }
    }

    // Separator
    // Rectangle {
    //     visible: popup.hasPlayer
    //     width: parent.width
    //     height: 1
    //     color: Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.15)
    // }

    // Playback controls
    Row {
        visible: popup.hasPlayer
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 20

        // Shuffle
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            enabled: popup.player && popup.player.shuffleSupported
            glyph: "\ue021" // arrow-shuffle
            style: popup.iconStyle
            color: popup.player && popup.player.shuffle ? Theme.accentColor : Theme.fgColor
            opacity: enabled ? (popup.player && popup.player.shuffle ? 1 : 0.5) : 0.35
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (popup.player && popup.player.shuffleSupported)
                        popup.player.shuffle = !popup.player.shuffle
                }
            }
        }

        // Previous (dimmed and inert when there is no track before the current one)
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            glyph: "\ue036" // previous
            style: popup.iconStyle
            color: Theme.fgColor
            enabled: popup.player && popup.player.canGoPrevious
            opacity: enabled ? 1 : 0.35
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: popup.player.previous()
            }
        }

        // Play / Pause
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            enabled: popup.player && popup.player.canTogglePlaying
            glyph: popup.isPlaying ? "\ue032" : "\ue034" // pause : play
            style: popup.iconStyle
            color: Theme.fgColor
            font.pixelSize: Theme.iconSize + 6
            opacity: enabled ? 1 : 0.35
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: popup.player.togglePlaying()
            }
        }

        // Next
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            enabled: popup.player && popup.player.canGoNext
            glyph: "\ue031" // next
            style: popup.iconStyle
            color: Theme.fgColor
            opacity: enabled ? 1 : 0.35
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: popup.player.next()
            }
        }

        // Loop (none -> playlist -> track -> none)
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            enabled: popup.player && popup.player.loopSupported
            glyph: popup.player && popup.player.loopState === MprisLoopState.Track
                ? "\ue01e" // arrow-repeat1 (repeat-1)
                : "\ue01f" // arrow-repeat-all (repeat)
            style: popup.iconStyle
            color: popup.player && popup.player.loopState !== MprisLoopState.None
                ? Theme.accentColor : Theme.fgColor
            opacity: enabled ? (popup.player && popup.player.loopState !== MprisLoopState.None ? 1 : 0.5) : 0.35
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (!popup.player || !popup.player.loopSupported)
                        return
                    const s = popup.player.loopState
                    if (s === MprisLoopState.None)
                        popup.player.loopState = MprisLoopState.Playlist
                    else if (s === MprisLoopState.Playlist)
                        popup.player.loopState = MprisLoopState.Track
                    else
                        popup.player.loopState = MprisLoopState.None
                }
            }
        }
    }

    // Player identity footer
    Text {
        visible: popup.hasPlayer && popup.player.identity !== ""
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: popup.player ? popup.player.identity : ""
        color: Theme.fgColor
        opacity: 0.4
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 2
    }
}
