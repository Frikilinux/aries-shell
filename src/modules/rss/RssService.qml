pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Shared RSS state for the bar indicator and its popup.
//
// Fetches a user-configured list of feed URLs with curl (same pattern as
// WeatherService, one Process per feed since Quickshell 0.3.2 has no native
// HTTP client). Each response is parsed by a small JS parser supporting RSS
// 2.0 (<item>) and Atom (<entry>): only title + link + date are extracted.
//
// Parsed items are merged into `items` (deduped by link, sorted newest first)
// and truncated to the retention window (`maxAgeDays`, e.g. last 15 days from
// each refresh) plus items of feeds that are no longer configured, so the set
// stays bounded forever. There is no read state anywhere: the bar icon
// appears while any news exists and the popup just opens links.
//
// The merged set is cached in memory plus on disk (`XDG_CACHE_HOME/aries/`):
// after a cold start the cache fills the store, and fetching only happens
// once `refreshInterval` has elapsed (or when the feed list changed).
//
// Fetch cycle: parallel Processes (one per feed), each with its own
// StdioCollector. Events from a reused single Process arrive out of order
// (the collector's streamFinished fires after onExited: items would commit
// while `activeFeed`/the queue cursor already moved on), so a per-feed object
// keeps parse/exit bookkeeping separate and the cycle ends only when every
// feed reports both.
Singleton {
    id: root

    readonly property var cfg: Config.settings.modules.rss
    // Feed URLs (user config); a plain string is accepted and wrapped.
    readonly property var feeds: Array.isArray(root.cfg.feeds) ? root.cfg.feeds : []
    // Feed list key (scalar string) so change signals fire on content changes
    // only: Config settings objects are rebuilt on every load and a naive
    // var-based change handler invalidates the cache on each boot.
    readonly property string feedKey: root.feeds.map(function (f) { return "" + f }).join("\n")
    // Feed key of what the store/cache currently represents (bookkept below).
    property string cachedFeedKey: ""
    // Minimum time between fetch cycles (milliseconds).
    readonly property int refreshInterval: root.cfg.refreshInterval * 60000
    // Retention window (days): items older than this are dropped every cycle.
    readonly property int maxAgeDays: root.cfg.maxAgeDays
    // Per-feed cap shown in the popup (the store keeps everything in window).
    readonly property int maxPerFeed: root.cfg.maxPerFeed

    // All news of the retention window, newest first. Each entry:
    // { title, link, time (Date.now() ms), source (host label), feed (url) }
    property var items: []
    // Parse-merge accumulation for the cycle in progress; committed on end.
    property var pendingItems: []
    property bool failed: false
    property bool fetching: false

    // Timestamp (Date.now()) of the last completed fetch cycle; 0 = never.
    // double, not int: QML ints are 32-bit and truncate epoch milliseconds.
    property double lastFetch: 0

    readonly property bool stale: root.lastFetch === 0
        || (Date.now() - root.lastFetch) >= root.refreshInterval
    readonly property bool hasNews: root.items.length > 0

    // Popup view: up to `maxPerFeed` items per feed, dates interleaved. `items`
    // is already sorted, so picking the first entries per feed is enough (the
    // feed url is the key, so two feeds on the same host keep separate caps;
    // cache entries lacking it fall back to the derived host label).
    readonly property var displayed: {
        const shown = {}
        const out = []
        for (let i = 0; i < root.items.length; i++) {
            const it = root.items[i]
            const key = it.feed !== undefined ? "" + it.feed : "" + it.source
            if ((shown[key] ?? 0) < root.maxPerFeed) {
                shown[key] = (shown[key] ?? 0) + 1
                out.push(it)
            }
        }
        return out
    }

    // Bar glyph.
    readonly property string iconGlyph: "\ue089" // rss

    // ---------------------------------------------------------------- paths
    readonly property string cacheDir: {
        const xdg = Quickshell.env("XDG_CACHE_HOME")
        const home = Quickshell.env("HOME")
        const base = xdg ? ("" + xdg) : ((home ? "" + home : "") + "/.cache")
        return base + "/aries"
    }
    readonly property string cachePath: root.cacheDir + "/rss.json"

    // ------------------------------------------------------------------ API
    // Refetch every feed (in parallel) only when the cache is stale.
    function refresh() {
        if (root.fetching || !root.stale || root.feeds.length === 0)
            return
        // A prior cycle's processes are long done by now (finishFetch also
        // clears the list); destroy defensively in case something remains.
        for (let i = 0; i < root.fetchObjects.length; i++)
            root.fetchObjects[i].destroy()
        root.fetchObjects = []
        root.feedStates = {}
        root.failed = false
        root.fetching = true
        root.pendingItems = []
        for (let i = 0; i < root.feeds.length; i++) {
            const url = "" + root.feeds[i]
            root.feedStates[url] = { parsed: false, exited: false }
            const proc = fetchComp.createObject(root, {
                feedUrl: url,
                service: root,
                command: ["curl", "-sSfL", "--connect-timeout", "5", "--max-time", "15", url]
            })
            root.fetchObjects.push(proc)
            proc.running = true
        }
    }

    // Force a refetch on the next refresh() by expiring the cache.
    function invalidate() {
        root.lastFetch = 0
    }

    // Collector drained: parse exactly this feed's own text (ownership of
    // `text` belongs to the per-feed object, no shared cursor).
    function onFeedParsed(url, text) {
        const state = root.feedStates[url]
        if (state === undefined || state.parsed)
            return
        state.parsed = true
        root.parseFeed(text, url)
        root.maybeFinishFetch()
    }

    function onFeedExited(url, exitCode) {
        const state = root.feedStates[url]
        if (state === undefined || state.exited)
            return
        state.exited = true
        if (exitCode !== 0)
            root.failed = true // one feed down; the others still commit
        root.maybeFinishFetch()
    }

    function maybeFinishFetch() {
        for (const url in root.feedStates) {
            const state = root.feedStates[url]
            if (!state.parsed || !state.exited)
                return // still draining (zero-output feeds included)
        }
        root.finishFetch()
    }

    function finishFetch() {
        root.fetching = false
        root.lastFetch = Date.now()
        root.cachedFeedKey = root.feedKey
        root.commit()
        root.saveCache()
        root.fetchObjects = []
        root.feedStates = {}
    }

    // Merge cycle results into the store, then drop anything outside the
    // retention window or belonging to a feed that is no longer configured.
    function commit() {
        const byLink = {}
        for (let i = 0; i < root.items.length; i++)
            byLink[root.items[i].link] = root.items[i]
        for (let i = 0; i < root.pendingItems.length; i++)
            byLink[root.pendingItems[i].link] = root.pendingItems[i]
        const oldest = Date.now() - root.maxAgeDays * 86400000
        const current = {}
        const labels = {}
        for (let i = 0; i < root.feeds.length; i++) {
            current["" + root.feeds[i]] = true
            labels[root.feedLabel(root.feeds[i])] = true
        }
        const merged = []
        for (const link in byLink) {
            const it = byLink[link]
            // Items without a `feed` url (older cache files) match on the
            // derived source label instead; they age out with the window.
            if (it.time >= oldest && (it.feed !== undefined ? !!current[it.feed] : !!labels[it.source]))
                merged.push(it)
        }
        merged.sort(function (a, b) { return b.time - a.time })
        root.items = merged
        root.pendingItems = []
    }

    // Feed URL -> host for the popup's meta line ("example.org").
    function feedLabel(url) {
        const host = ("" + url).replace(/^[a-z][a-z0-9+.-]*:\/\//i, "")
            .replace(/^www\./i, "").split(/[/?#]/)[0]
        return host !== "" ? host : ("" + url)
    }

    // Date -> relative "now" / "3m" / "3h" / "2d".
    function formatRelative(time) {
        const diff = Math.max(0, Date.now() - time)
        const minutes = Math.floor(diff / 60000)
        if (minutes < 1)
            return "now"
        if (minutes < 60)
            return minutes + "m"
        const hours = Math.floor(minutes / 60)
        if (hours < 24)
            return hours + "h"
        return Math.floor(hours / 24) + "d"
    }

    // -------------------------------------------------------------- parsing
    // URLs from either RSS 2.0 (<item>) or Atom (<entry>) text.
    function parseFeed(text, url) {
        if (!text)
            return
        const label = root.feedLabel(url)
        const blocks = ("" + text).match(/<(item|entry)\b[\s\S]*?<\/\1>/gi)
        if (blocks === null)
            return
        for (let i = 0; i < blocks.length; i++) {
            const block = blocks[i]
            const title = root.stripTags(root.extractTag(block, "title"))
            if (title === "")
                continue
            const feedLink = root.extractLink(block)
            const dateStr = (root.extractTag(block, "pubDate")
                || root.extractTag(block, "published")
                || root.extractTag(block, "updated")
                || root.extractTag(block, "date"))
            // Unparseable dates fall back to fetch time so retention keeps
            // them exactly `maxAgeDays`, not forever.
            root.pendingItems.push({
                title: title,
                link: feedLink !== "" ? feedLink : url,
                time: root.parseFeedDate(dateStr) || Date.now(),
                source: label,
                feed: "" + url
            })
        }
    }

    // First <tag>…</tag> inner text of `src` (`<media:title` does not match).
    function extractTag(src, tag) {
        const m = new RegExp("<" + tag + "\\b[^>]*>([\\s\\S]*?)<\\/" + tag + "\\s*>", "i").exec(src)
        return m !== null ? m[1] : ""
    }

    // Item link across the formats: Atom <link href> (preferring rel=alternate
    // over self/server links), RSS <link>text</link>, then permalink <guid>.
    function extractLink(block) {
        let m = /<link\b[^>]*\brel=["']alternate["'][^>]*\bhref=["']([^"']+)["']/i.exec(block)
        if (m === null)
            m = /<link\b[^>]*\bhref=["']([^"']+)["']/i.exec(block)
        if (m !== null && m[1])
            return root.decodeEntities(m[1].trim())
        m = /<link\b[^>]*>([\s\S]*?)<\/link>/i.exec(block)
        if (m !== null) {
            const text = root.decodeEntities(root.stripTags(m[1]).trim())
            if (text !== "")
                return text
        }
        m = /<guid[^>]*\bisPermaLink=["']?true[^>]*>([\s\S]*?)<\/guid>/i.exec(block)
        return m !== null ? root.decodeEntities(root.stripTags(m[1]).trim()) : ""
    }

    // CDATA wrappers -> plain text, strip XML/HTML tags, decode entities.
    function stripTags(s) {
        let out = ("" + s).replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
        out = out.replace(/<[^>]*>/g, "")
        return root.decodeEntities(out).trim()
    }

    // Numeric and the common named XML entities. `&amp;` last so double
    // encodings like "&amp;lt;" unescape only one level.
    function decodeEntities(s) {
        let out = ("" + s).replace(/&#x([0-9A-Fa-f]+);/g, function (_, hex) {
            return String.fromCodePoint(parseInt(hex, 16))
        })
        out = out.replace(/&#(\d+);/g, function (_, num) {
            return String.fromCodePoint(parseInt(num, 10))
        })
        out = out.replace(/&(lt|gt|quot|apos|nbsp);/g, function (_, ent) {
            switch (ent) {
            case "lt": return "<"
            case "gt": return ">"
            case "quot": return "\""
            case "apos": return "'"
            case "nbsp": return " "
            }
            return ent
        })
        return out.replace(/&amp;/g, "&")
    }

    // ISO 8601 (Atom) and RFC 822 (RSS) dates -> epoch ms; 0 on failure. V4's
    // Date.parse does not handle RFC 822, so that format is parsed manually.
    function parseFeedDate(str) {
        const MONTHS = { jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5, jul: 6, aug: 7, sep: 8, oct: 9, nov: 10, dec: 11 }
        // Zone abbreviations -> UTC offset in minutes (east of UTC = positive)
        const ZONES = { ut: 0, gmt: 0, utc: 0, z: 0, edt: -240, est: -300, cdt: -300, cst: -360, mdt: -420, mst: -420, pdt: -480, pst: -480, ist: +330, bst: +60, met: +60, cet: +60, cest: +120, jst: +540, kst: +540 }
        const s = ("" + str).trim()
        if (s === "")
            return 0
        let t = Date.parse(s) // ISO 8601
        if (!isNaN(t))
            return t
        // RFC 822: "Wed, 21 Oct 2026 11:35:00 +0200"
        const m = /(\d{1,2})\s+([A-Za-z]{3})[a-z]*\.?\s+(\d{2,4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(?:(?:([+-])(\d{2}):?(\d{2}))|([A-Za-z]{1,5}))?/.exec(s)
        if (m === null)
            return 0
        const month = MONTHS[("" + m[2]).slice(0, 3).toLowerCase()]
        if (month === undefined)
            return 0
        let year = parseInt(m[3], 10)
        if (year < 100)
            year += year < 70 ? 2000 : 1900
        const hour = parseInt(m[4], 10)
        const min = parseInt(m[5], 10)
        const secs = m[6] !== undefined ? parseInt(m[6], 10) : 0
        let zoff = null // zone offset in minutes (east of UTC = positive)
        if (m[9] !== undefined) {
            zoff = (parseInt(m[8], 10) * 60 + parseInt(m[9], 10)) * (m[7] === "+" ? 1 : -1)
        } else if (m[10] !== undefined) {
            const zone = ("" + m[10]).slice(0, 4).toLowerCase()
            if (zone in ZONES)
                zoff = ZONES[zone]
        }
        const utc = Date.UTC(year, month, parseInt(m[1], 10), hour, min, secs)
        return zoff !== null ? utc - zoff * 60000 : new Date(year, month, parseInt(m[1], 10), hour, min, secs).getTime()
    }

    // ------------------------------------------------------------ cache I/O
    // True once the on-disk cache has been read (or confirmed absent); gates
    // saves the same way NotificationService gates writeHistory ("Cannot write
    // file, as no path has been specified" otherwise, since saves may fire
    // while the config/settings are still updating at boot).
    property bool loaded: false
    // Boot sequencing: the cache is only read once the cache dir exists and
    // the user config is up, so the feed comparison below sees the FINAL feed
    // list, never the boot defaults (Config's own read is async as well).
    property bool dirReady: false
    readonly property bool cacheLoadable: root.dirReady && Config.ready

    // Single decision point for "use cache vs refetch": runs whenever either
    // side completes (config read / cache read); the last one to land does the
    // actual scheduling, so ordinary orderings converge, and an existing cache
    // for the SAME feed list survives boots without a gratuitous refresh.
    function maybeRefresh() {
        if (!root.loaded || root.fetching)
            return // wait for the cache read (or absence) before deciding
        if (root.feedKey === "")
            return // no user config yet: nothing to fetch or compare
        if (root.feedKey !== root.cachedFeedKey)
            root.invalidate()
        root.refresh()
    }

    function loadCache() {
        cacheFile.path = root.cachePath
        cacheFile.reload()
    }

    // Per-feed per-cycle bookkeeping (see refresh()).
    property var feedStates: {}
    property var fetchObjects: []

    Component {
        id: fetchComp

        Process {
            id: proc

            required property string feedUrl
            // The singleton whose fetch cycle this feed belongs to (Bound
            // pragma: outer ids are not visible inside nested components).
            property var service: null

            stdout: StdioCollector {
                onStreamFinished: proc.service.onFeedParsed(proc.feedUrl, text)
            }

            onExited: function (exitCode, exitStatus) {
                proc.service.onFeedExited(proc.feedUrl, exitCode)
            }
        }
    }

    function onCacheLoaded() {
        // An in-flight fetch cycle owns the store: don't clobber it.
        if (root.fetching) {
            root.loaded = true
            return
        }
        try {
            const d = JSON.parse(cacheFile.text())
            if (d && Array.isArray(d.items)) {
                root.items = d.items.filter(function (it) {
                    return it && it.title && it.link && it.time !== undefined
                })
                if (d.lastFetch !== undefined)
                    root.lastFetch = d.lastFetch
            }
            // What the file represents; a different current feed list triggers
            // the invalidate+refresh inside maybeRefresh.
            if (typeof d.feedKey === "string")
                root.cachedFeedKey = d.feedKey
        } catch (e) {
            root.items = []
            root.lastFetch = 0
        }
        root.loaded = true
        root.maybeRefresh()
    }

    function onCacheLoadFailed(error) {
        // Missing file on first run / broken JSON: start empty and fetch.
        root.loaded = true
        root.maybeRefresh()
    }

    function saveCache() {
        if (!root.loaded)
            return
        cacheFile.setText(JSON.stringify({
            feedKey: root.feedKey,
            lastFetch: root.lastFetch,
            items: root.items
        }, null, 2))
    }

    onFeedKeyChanged: root.maybeRefresh()
    onCacheLoadableChanged: if (root.cacheLoadable) root.loadCache()

    onMaxAgeDaysChanged: { root.commit(); root.saveCache() }

    // Boot: create the cache dir (single Process, matches Config/Notifications).
    // The cache file loads afterwards via cacheLoadable (Config ready), and
    // maybeRefresh then schedules the first fetch.
    Process {
        id: boot

        command: ["/bin/sh", "-c", "mkdir -p \"$1\"", "sh", root.cacheDir]
        running: true
        onExited: root.dirReady = true
    }

    FileView {
        id: cacheFile

        atomicWrites: true
        onLoaded: root.onCacheLoaded()
        onLoadFailed: function (error) { root.onCacheLoadFailed(error) }
    }

    Timer {
        id: refreshTimer

        interval: root.refreshInterval
        repeat: true
        running: root.feeds.length > 0
        onTriggered: root.refresh()
    }
}
