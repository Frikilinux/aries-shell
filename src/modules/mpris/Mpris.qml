import QtQuick
import Quickshell.Services.Mpris
import "../theme"
import "../icon"
import "../config"

Item {
    id: mpris

    // Show this module only on specific outputs (monitors).
    // Set to a string ("HDMI-A-1") or array (["eDP-1"]). If undefined/null, shows on all.
    property var outputs
    // The output being rendered.
    property string output: ""

    // Icon style used by this module's bar icon. Defaults to Theme.iconStyle.
    property string iconStyle: Theme.iconStyle

    // Max width (px) for each text label so they truncate instead of overflowing
    property int maxLabelWidth: Config.settings.modules.mpris.maxLabelWidth

    // playerctld is a proxy that reports a broken/no-active-player state
    // (GetAll fails with com.github.altdesktop.playerctld.NoActivePlayer) when
    // nothing is being controlled, so it must not be treated as an active player.
    readonly property var players: Mpris.players.values.filter(
        p => !p.dbusName.startsWith("org.mpris.MediaPlayer2.playerctld"))
    readonly property var activePlayer: {
        if (players.length === 0)
            return null
        for (let i = 0; i < players.length; i++) {
            if (players[i].isPlaying)
                return players[i]
        }
        return players[0]
    }
    readonly property bool hasPlayer: activePlayer !== null
    readonly property bool isPlaying: hasPlayer && activePlayer.isPlaying

    implicitWidth: mpris.hasPlayer ? trackRow.implicitWidth : idleIcon.implicitWidth
    implicitHeight: mpris.hasPlayer ? trackRow.implicitHeight : idleIcon.implicitHeight

    // Module is visible only if outputs property is unset, matches this output, or contains it
    visible: !outputs || (Array.isArray(outputs) ? outputs.includes(output) : outputs === output)

    // Idle: Arch logo when there is no active player
    Icon {
        id: idleIcon
        visible: !mpris.hasPlayer
        anchors.centerIn: parent
        glyph: "\ue074" // mdi-arch
        style: mpris.iconStyle
        color: Theme.fgBarColor
        opacity: 0.5
    }

    // Track title + artist. Dimmed (atenuada) while paused/not playing.
    Row {
        id: trackRow
        visible: mpris.hasPlayer
        opacity: mpris.isPlaying ? 1 : 0.5
        spacing: 7
        anchors.verticalCenter: parent.verticalCenter

        Text {
            id: titleText
            anchors.verticalCenter: parent.verticalCenter
            visible: mpris.activePlayer !== null
            text: mpris.activePlayer ? mpris.activePlayer.trackTitle : ""
            color: Theme.fgBarColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
            font.styleName: Theme.fontStyleName
            maximumLineCount: 1
            elide: Text.ElideRight
            width: Math.min(implicitWidth, mpris.maxLabelWidth)
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: mpris.activePlayer !== null && mpris.activePlayer.trackArtist !== ""
            text: mpris.activePlayer ? mpris.activePlayer.trackArtist : ""
            color: Theme.accentColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 3
            font.styleName: Theme.fontStyleName
            maximumLineCount: 1
            elide: Text.ElideRight
            width: Math.min(implicitWidth, mpris.maxLabelWidth)
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            // Only open the popup when an active player exists
            if (mpris.hasPlayer)
                popup.visible = !popup.visible
        }
    }

    // Close the popup if the active player disappears while it is open
    onHasPlayerChanged: {
        if (!mpris.hasPlayer)
            popup.visible = false
    }

    MprisPopup {
        id: popup
        anchorItem: mpris
    }
}
