pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// TheAudioDB artist fanart for the Mpris popup backdrop.
//
// The lookup key is the player's album artist, falling back to the first of
// the track's artists (Quickshell joins xesam:artist with ", " and some
// players pack several artists into one entry with ";"). The key is looked up
// once per artist: the resolved fanart URL is kept in `urlCache`, so the same
// artist (or any artist already seen this session) never triggers another API
// query. The image itself is downloaded once per artist *name* into
// `<cache>/aries/fanart/<slug>.jpg` and reused while the name is unchanged.
//
// `source` is a file:// URL once a cached download is ready, "" otherwise (no
// artist, no fanart, or still resolving) so callers fall back to album art.
Singleton {
    id: root

    // TheAudioDB public test key and free user (documented for development use).
    readonly property string apiKey: "123"

    // Artist inputs pushed by the popup.
    property string albumArtist: ""
    property string trackArtist: ""

    // Artist to look up: album artist wins, else the first track artist.
    readonly property string lookupArtist: {
        const album = ("" + root.albumArtist).trim()
        if (album !== "")
            return album
        return ("" + root.trackArtist).split(/[,;]/)[0].trim()
    }

    // Local fanart file (file:// URL), "" when there is none for the lookup.
    readonly property string source: {
        const key = root.keyFor(root.lookupArtist)
        return (key !== "" && key === root.readyKey)
            ? "file://" + root.fileFor(root.lookupArtist)
            : ""
    }

    // Artist key whose fanart file is confirmed present and ready to show.
    property string readyKey: ""

    // artist key -> fanart URL ("" = already queried, no fanart). In-memory:
    // avoids repeat API hits for the same or previously seen artists.
    property var urlCache: ({})
    // Only one query/download runs at a time; a change while busy is picked up
    // by `pump()` when the current step finishes.
    property bool busy: false
    // Artist key the in-flight step belongs to.
    property string busyKey: ""

    readonly property string cacheDir: {
        const xdg = Quickshell.env("XDG_CACHE_HOME")
        const home = Quickshell.env("HOME")
        const base = xdg ? ("" + xdg) : ((home ? "" + home : "") + "/.cache")
        return base + "/aries/fanart"
    }

    function keyFor(name) {
        return ("" + name).trim().toLowerCase()
    }

    function fileFor(name) {
        const slug = root.keyFor(name).replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
        return root.cacheDir + "/" + (slug === "" ? "unknown" : slug) + ".jpg"
    }

    // Resolve whatever the current artist needs: query the API, download the
    // image, or nothing (ready / no fanart). Safe to call at any time.
    function pump() {
        const key = root.keyFor(root.lookupArtist)
        if (key === "" || root.busy || key === root.readyKey)
            return
        if (root.urlCache[key] === undefined) {
            root.busy = true
            root.busyKey = key
            query.command = ["curl", "-sfL", "--connect-timeout", "5", "--max-time", "15",
                "https://www.theaudiodb.com/api/v1/json/" + root.apiKey + "/search.php?s="
                    + encodeURIComponent(root.lookupArtist)]
            query.running = true
            return
        }
        if (root.urlCache[key] !== "")
            root.fetch(key, root.urlCache[key])
    }

    // Download `url` into the artist's cache file; a present file is reused
    // (no re-download while the name is unchanged).
    function fetch(key, url) {
        root.busy = true
        root.busyKey = key
        downloader.command = ["/bin/sh", "-c",
            "d=\"$1\"; f=\"$2\"; u=\"$3\"; mkdir -p \"$d\"; "
                + "[ -s \"$f\" ] && exit 0; "
                + "curl -sfL --connect-timeout 5 --max-time 20 -o \"$f\" \"$u\" || rm -f \"$f\"; "
                + "[ -s \"$f\" ]",
            "sh", root.cacheDir, root.fileFor(key), url]
        downloader.running = true
    }

    function onQueryFinished(text) {
        let url = ""
        if (text !== "") {
            try {
                const d = JSON.parse(text)
                if (d && d.artists && d.artists.length > 0 && d.artists[0].strArtistFanart)
                    url = d.artists[0].strArtistFanart
            } catch (e) {
                url = ""
            }
        }
        root.urlCache[root.busyKey] = url
        root.busy = false
        root.pump()
    }

    function onDownloadFinished(ok) {
        if (ok && root.busyKey === root.keyFor(root.lookupArtist))
            root.readyKey = root.busyKey
        root.busy = false
        root.pump()
    }

    onLookupArtistChanged: root.pump()

    Process {
        id: query
        stdout: StdioCollector {
            onStreamFinished: root.onQueryFinished(text)
        }
        // Fallback for a failed run that produced no stream callback.
        onExited: function (exitCode, exitStatus) {
            if (root.busy && exitCode !== 0)
                root.onQueryFinished("")
        }
    }

    Process {
        id: downloader
        stdout: StdioCollector {}
        onExited: function (exitCode, exitStatus) {
            root.onDownloadFinished(exitCode === 0)
        }
    }
}
