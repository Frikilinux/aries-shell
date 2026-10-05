import QtQuick
import QtQuick.Effects
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

    // Height is driven by the art panel: the square cover spans the whole
    // window, the info column rides inside the content padding. Only text
    // taller than the cover (very long titles) grows the window.
    implicitHeight: Math.min(Math.max(popup.artSize, textCol.implicitHeight + popup.contentPadding * 2), popup.maxContentHeight)

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

    // Fanart backdrop (TheAudioDB): the current artist's cached fanart when the
    // shared service has one, else the album art as before. "" = no backdrop.
    readonly property string backdropSource: FanartService.source !== ""
        ? FanartService.source
        : (popup.hasArt ? popup.player.trackArtUrl : "")
    readonly property bool hasBackdrop: popup.backdropSource !== ""
    // Fanart reads better anchored to the top (subjects), so bias its crop up;
    // the album fallback stays vertically centred.
    readonly property bool backdropIsFanart: FanartService.source !== ""

    // Keep the shared fanart service pointed at the current track's artists.
    // Bindings (not plain assignments) because every screen's popup sets the
    // same singleton properties; the service picks album artist or the first.
    Binding {
        target: FanartService
        property: "albumArtist"
        value: popup.player ? popup.player.trackAlbumArtist : ""
    }
    Binding {
        target: FanartService
        property: "trackArtist"
        value: popup.player ? popup.player.trackArtist : ""
    }

    // The blurred backdrop replaces the base fill (winOpacity below), so the
    // popup keeps exactly the transparency of every other popup
    // (colors.bgOpacity). The base Rectangle keeps drawing its border when
    // there is no backdrop; with one the border is redrawn in the overlay layer
    // (above the backdrop), otherwise it would be buried under it.
    winOpacity: popup.hasBackdrop ? 0 : Theme.bgOpacity

    // Layers painted above the base background and below the content column:
    // the blurred backdrop (artist fanart, else album art) across the whole
    // window, then the sharp album art panel flush against the left border.
    background: [
        ClippingRectangle {
            visible: popup.hasBackdrop
            anchors.fill: parent
            radius: Theme.popupRadius
            // Fallback fill while the image is still loading (or if it fails).
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
                source: popup.backdropSource
                fillMode: Image.PreserveAspectCrop
                // Show the upper part of the fanart instead of its centre.
                verticalAlignment: popup.backdropIsFanart ? Image.AlignTop : Image.AlignVCenter
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
                    blur: 0.8
                    blurMax: 40
                }
            }

            // Dark tint: keeps the light theme text readable over pale artwork.
            Rectangle {
                anchors.fill: parent
                // color: "#b3151b23"
                color: Qt.rgba(Theme.bgBarColor.r, Theme.bgBarColor.g, Theme.bgBarColor.b, 0.75)
            }
        },

        // Sharp album art: square (artSize x artSize) and flush with the
        // popup's left/top borders (zero padding -> left corners follow the
        // window radius), cut straight on the right where the info column
        // starts. The window is exactly as tall as this panel.
        ClippingRectangle {
            id: card
            visible: popup.hasPlayer
            anchors.left: parent.left
            anchors.top: parent.top
            width: popup.artSize
            height: popup.artSize
            // Nested radius: zero padding from the window edge -> the left
            // corners follow the window radius; the right side stays straight.
            radius: Theme.popupRadius
            topRightRadius: 0
            bottomRightRadius: 0
            // ClippingRectangle paints white by default; keep it transparent so
            // the no-art placeholder shows the popup background through it.
            color: "transparent"

            // Album art (sharp copy; decode capped at display size * dpr)
            Image {
                visible: popup.hasArt
                anchors.fill: parent
                source: popup.hasArt ? popup.player.trackArtUrl : ""
                // Keep the whole cover (no crop): fill the container on one axis
                // and centre it on the other (bands show the blurred backdrop).
                fillMode: Image.PreserveAspectFit
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
    ]

    // Corner badge + border over the content (border only while the backdrop
    // hides the base one).
    overlay: [
        Rectangle {
            visible: popup.hasBackdrop
            anchors.fill: parent
            radius: Theme.popupRadius
            color: "transparent"
            border.width: Theme.popupBorderWidth
            border.color: Theme.popupBorderColor
        },
        // Aries mark in the top-right corner (branding; replaces the player's
        // app icon).
        Icon {
            visible: popup.hasPlayer
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 14
            glyph: "\ue083" // aries-ram
            font.pixelSize: 22
            opacity: 0.4
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

    // Track info + controls: info column to the right of the sharp art panel
    // (backdrop layer, square + flush at the popup's left border), filling the
    // window's inner height so it stays bottom-aligned on the content padding.
    Item {
        id: infoRow
        visible: popup.hasPlayer
        width: popup.contentWidth
        height: popup.implicitHeight - popup.contentPadding * 2

        Column {
            id: textCol
            anchors.bottom: parent.bottom
            x: popup.artSize + popup.artGap - popup.contentPadding
            width: parent.width - popup.artSize - popup.artGap + popup.contentPadding
            // spacing: 1

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
                height: controlsRow.height + 5

                Row {
                    id: controlsRow
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    spacing: 25
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
                        font.pixelSize: Theme.iconSize + 10
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
