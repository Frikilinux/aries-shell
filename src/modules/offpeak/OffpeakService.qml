pragma Singleton

import QtQuick
import Quickshell

// DeepSeek API off-peak schedule, shared by the bar indicator and its popup.
//
// Peak (standard price) is weekdays only: 01:00-04:00 and 06:00-10:00 UTC, and
// Saturdays/Sundays are entirely off-peak. The schedule is anchored to UTC;
// every displayed time (ranges, next switch, timeline) is local.
Singleton {
    id: root

    // Peak window boundaries, in minutes since 00:00 UTC (01:00, 04:00, 06:00, 10:00).
    readonly property var peakMinutes: [60, 240, 360, 600]

    // Second precision drives the countdown / timeline marker.
    SystemClock {
        id: clockSec
        enabled: true
        precision: SystemClock.Seconds
    }

    // Minute precision drives the schedule (window list), so the Repeater
    // doesn't rebuild every second.
    SystemClock {
        id: clockMin
        enabled: true
        precision: SystemClock.Minutes
    }

    readonly property date now: clockSec.date
    readonly property date nowMinute: clockMin.date

    // Peak during 01:00-04:00 and 06:00-10:00 UTC on weekdays only.
    function isPeak(date) {
        const day = date.getUTCDay() // 0 = Sunday, 6 = Saturday
        if (day === 0 || day === 6)
            return false
        const minutes = date.getUTCHours() * 60 + date.getUTCMinutes()
        return (minutes >= 60 && minutes < 240) || (minutes >= 360 && minutes < 600)
    }

    readonly property bool peak: root.isPeak(root.now)
    readonly property string statusLabel: root.peak ? "PEAK · STANDARD PRICE" : "OFF-PEAK · HALF PRICE"

    // Every state-change instant (epoch ms) around now; weekends contribute none.
    function transitions() {
        const current = root.nowMinute
        const dayStart = Date.UTC(current.getUTCFullYear(), current.getUTCMonth(), current.getUTCDate())
        const list = []
        for (let i = -9; i <= 8; i++) {
            const base = dayStart + i * 86400000
            const dow = new Date(base).getUTCDay()
            if (dow === 0 || dow === 6)
                continue
            for (let j = 0; j < root.peakMinutes.length; j++)
                list.push(base + root.peakMinutes[j] * 60000)
        }
        list.sort((a, b) => a - b)
        return list
    }

    // Epoch ms of the next off-peak/peak switch.
    function nextTransition() {
        const list = root.transitions()
        const t = root.nowMinute.getTime()
        for (let i = 0; i < list.length; i++) {
            if (list[i] > t)
                return list[i]
        }
        return t
    }

    readonly property real remainingMs: Math.max(0, root.nextTransition() - root.now.getTime())

    // Merged off-peak/peak windows, starting with the current one.
    function windows(count) {
        const list = root.transitions()
        const t = root.nowMinute.getTime()
        let idx = 0
        while (idx < list.length && list[idx] <= t)
            idx++
        const out = []
        for (let k = 0; k < count; k++) {
            const start = list[idx - 1 + k]
            const end = list[idx + k]
            if (start === undefined || end === undefined)
                break
            out.push({ start: start, end: end, peak: root.isPeak(new Date((start + end) / 2)) })
        }
        return out
    }

    function pad(n) {
        return n < 10 ? "0" + n : "" + n
    }

    function hhmm(date) {
        return root.pad(date.getHours()) + ":" + root.pad(date.getMinutes())
    }

    function dayName(date) {
        return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][date.getDay()]
    }

    // "01:00 – 04:00" within one local day, else "Mon 10:00 – Tue 01:00".
    function formatRange(startMs, endMs) {
        const s = new Date(startMs)
        const e = new Date(endMs)
        const sameDay = s.getFullYear() === e.getFullYear()
            && s.getMonth() === e.getMonth()
            && s.getDate() === e.getDate()
        if (sameDay)
            return root.hhmm(s) + " – " + root.hhmm(e)
        return root.dayName(s) + " " + root.hhmm(s) + " – " + root.dayName(e) + " " + root.hhmm(e)
    }

    // "H:MM:SS" countdown.
    function formatClock(ms) {
        const total = Math.max(0, Math.floor(ms / 1000))
        const hours = Math.floor(total / 3600)
        const minutes = Math.floor((total % 3600) / 60)
        const seconds = total % 60
        return hours + " : " + root.pad(minutes) + " : " + root.pad(seconds)
    }

    // "3h" / "2h 53m" / "2d 14h".
    function formatDuration(ms) {
        const totalMinutes = Math.max(0, Math.floor(ms / 60000))
        const days = Math.floor(totalMinutes / 1440)
        const hours = Math.floor((totalMinutes % 1440) / 60)
        const minutes = totalMinutes % 60
        if (days > 0)
            return days + "d " + hours + "h"
        if (hours > 0 && minutes > 0)
            return hours + "h " + minutes + "m"
        if (hours > 0)
            return hours + "h"
        return minutes + "m"
    }

    // "Peak starts Tue, 01:00" (local) for the next switch.
    readonly property string nextLabel: {
        const next = new Date(root.nextTransition())
        const target = root.isPeak(next) ? "Peak" : "Off-peak"
        return target + " starts " + root.dayName(next) + ", " + root.hhmm(next)
    }

    // Fraction of the current local day (0..1), for the timeline marker.
    readonly property real nowFraction: (root.now.getHours() * 60
        + root.now.getMinutes()) / 1440

    // Whether the given local hour (0..23) of the current day is peak.
    function hourPeak(hour) {
        const current = root.nowMinute
        const t = new Date(current.getFullYear(), current.getMonth(), current.getDate(),
            hour).getTime()
        return root.isPeak(new Date(t))
    }
}
