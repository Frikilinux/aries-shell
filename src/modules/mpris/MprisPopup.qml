import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Widgets
import "../theme"
import "../icon"
import "../popup"

BarPopup {
    id: popup

    popupWidth: 475
    property int artSize: 180
    readonly property int artGap: 18

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
    readonly property bool hasArt: hasPlayer && player.trackArtUrl !== ""

    // The blurred album backdrop replaces the base fill (winOpacity below), so
    // the popup keeps exactly the transparency of every other popup
    // (colors.bgOpacity). The base Rectangle keeps drawing its border when
    // there is no art; with art the border is redrawn in the overlay layer
    // (above the backdrop), otherwise it would be buried under it.
    winOpacity: popup.hasArt ? 0 : Theme.bgOpacity

    // App badge for the top-right corner: the player's .desktop entry icon
    // (replaces the old identity name footer). "" = hidden (no entry/icon).
    // The `entries` read is deliberate: heuristicLookup has no change
    // notification and DesktopEntries scans asynchronously *after* the config
    // loads, so reading the list first makes the lookup re-run when the scan
    // lands (a lookup-only binding would cache null forever).
    readonly property string appIcon: {
        const entries = DesktopEntries.applications.values
        if (!popup.hasPlayer || popup.player.desktopEntry === "" || entries.length === 0)
            return ""
        const entry = DesktopEntries.heuristicLookup(popup.player.desktopEntry)
        if (!entry || entry.icon === "")
            return ""
        const path = Quickshell.iconPath(entry.icon, true)
        return path !== "" ? path : entry.icon
    }

    // Blurred, darkened album art spanning the whole popup window (painted
    // above the base background, below the content column).
    background: ClippingRectangle {
        visible: popup.hasArt
        anchors.fill: parent
        radius: Theme.popupRadius
        // Fallback fill while the art is still loading (or if it fails).
        color: Theme.bgColor
        opacity: Theme.bgOpacity

        // Oversized by 60px so the blur's transparent edge bleed (half of
        // blurMax) stays outside the rounded clip.
        Image {
            id: bgArt
            x: -30
            y: -30
            width: parent.width + 60
            height: parent.height + 60
            source: popup.hasArt ? popup.player.trackArtUrl : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            // Decode at popup size, not the art's natural resolution: the
            // backdrop is blurred, so full-size pixels would be wasted RAM.
            sourceSize.width: popup.popupWidth * Screen.devicePixelRatio
            sourceSize.height: popup.popupWidth * Screen.devicePixelRatio
            // Render into a layer so MultiEffect consumes the item itself
            // (no double paint) instead of being stacked over a sharp image.
            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 1.0
                blurMax: 40
            }
        }

        // Dark tint: keeps the light theme text readable over pale artwork.
        Rectangle {
            anchors.fill: parent
            color: "#66000000"
        }
    }

    // Corner badge + border over the content (border only while the backdrop
    // hides the base one).
    overlay: [
        Rectangle {
            visible: popup.hasArt
            anchors.fill: parent
            radius: Theme.popupRadius
            color: "transparent"
            border.width: Theme.popupBorderWidth
            border.color: Theme.popupBorderColor
        },
        Image {
            visible: popup.appIcon !== ""
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 14
            width: 22
            height: 22
            source: popup.appIcon
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            sourceSize.width: 48
            sourceSize.height: 48
        }
    ]

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

    // Track info + controls: sharp album card on the left, info column on the
    // right; both bottom-aligned (block flush at the bottom of the popup).
    Item {
        id: infoRow
        visible: popup.hasPlayer
        width: popup.contentWidth
        height: Math.max(card.height, textCol.implicitHeight)
        readonly property int imageRadius: Theme.popupRadius - popup.contentPadding

        ClippingRectangle {
            id: card
            anchors.bottom: parent.bottom
            width: popup.artSize
            height: popup.artSize
            // Nested radius: parent (window) radius - padding from it,
            // 13 - 12 = 1 -> concentric with the window corner.
            // radius: Theme.popupRadius - popup.contentPadding
            radius: infoRow.imageRadius >= 6 ? infoRow.imageRadius : 6
            // ClippingRectangle paints white by default; keep it transparent so
            // the no-art placeholder shows the popup background through it.
            color: "transparent"

            // Album art (sharp copy; decode capped at display size * dpr)
            Image {
                visible: popup.hasArt
                anchors.fill: parent
                source: popup.hasArt ? popup.player.trackArtUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: popup.artSize * Screen.devicePixelRatio
                sourceSize.height: popup.artSize * Screen.devicePixelRatio
                cache: true
            }

            // Placeholder when no art
            Rectangle {
                visible: !popup.hasArt
                anchors.fill: parent
                color: Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.08)
                border.width: 1
                border.color: Qt.rgba(Theme.fgColor.r, Theme.fgColor.g, Theme.fgColor.b, 0.15)

                Icon {
                    anchors.centerIn: parent
                    glyph: "\ue06c" // headphones-sound-wave (no album art)
                    font.pixelSize: 36
                    color: Theme.fgColor
                    opacity: 0.4
                }
            }
        }

        Column {
            id: textCol
            anchors.bottom: parent.bottom
            x: popup.artSize + popup.artGap
            width: parent.width - popup.artSize - popup.artGap
            spacing: 3

            Text {
                visible: popup.hasPlayer
                width: textCol.width
                text: "NOW PLAYING"
                color: Theme.fgColor
                opacity: 0.6
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 5
                font.letterSpacing: 1.5
            }

            Text {
                visible: popup.hasPlayer
                width: textCol.width
                text: popup.player ? popup.player.trackTitle : ""
                color: Theme.fgColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 1
                font.bold: true
                maximumLineCount: 2
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                elide: Text.ElideRight
            }

            Text {
                visible: popup.player && popup.player.trackArtist !== ""
                width: textCol.width
                text: popup.player ? popup.player.trackArtist : ""
                color: Theme.accentColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                maximumLineCount: 1
                elide: Text.ElideRight
            }

            Text {
                visible: popup.player && popup.player.trackAlbum !== ""
                width: textCol.width
                text: popup.player ? popup.player.trackAlbum : ""
                color: Theme.fgColor
                opacity: 0.5
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
                maximumLineCount: 1
                elide: Text.ElideRight
            }

            // Playback controls share the info column (centred on it,
            // 10px of extra air above them)
            Item {
                width: textCol.width
                height: controlsRow.height + 10

                Row {
                    id: controlsRow
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    spacing: 20
                    // Shuffle
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        enabled: popup.player && popup.player.shuffleSupported
                        glyph: "\ue021" // arrow-shuffle
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
            }
        }
    }
}
