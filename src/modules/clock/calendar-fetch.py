#!/usr/bin/env python3
import datetime
import json
import sys

import gi
gi.require_version("EDataServer", "1.2")
gi.require_version("ECal", "2.0")
gi.require_version("ICalGLib", "4.0")
from gi.repository import ECal, EDataServer, ICalGLib


def iso(ts):
    return datetime.datetime.utcfromtimestamp(ts).isoformat() + "Z"


def emit_event(out, uid, summary, start, end, all_day, calendar):
    out.append({
        "uid": uid or "",
        "summary": summary or "",
        "start": int(start),
        "end": int(end),
        "allDay": bool(all_day),
        "calendar": calendar or "",
    })


def process_component(out, comp, source_name, range_start, range_end, max_events):
    ical = comp.get_icalcomponent()
    uid = ical.get_uid() or ""
    summary = ical.get_summary() or ""
    dtstart = ical.get_dtstart()
    dtend = ical.get_dtend()
    if dtstart is None:
        return
    all_day = bool(dtstart.is_date())
    tz = ICalGLib.Timezone.get_utc_timezone()
    start_ts = int(dtstart.as_timet_with_zone(tz))
    if dtend is not None:
        end_ts = int(dtend.as_timet_with_zone(tz))
    else:
        end_ts = start_ts + (86400 if all_day else 3600)

    # Recurring event: expand instances inside the requested range.
    rrule_prop = ical.get_first_property(ICalGLib.PropertyKind.RRULE_PROPERTY)
    if rrule_prop is not None:
        def cb(_comp, span, _data):
            s = int(span.get_start())
            e = int(span.get_end())
            if s < range_start or s >= range_end:
                return True
            emit_event(out, uid, summary, s, e, all_day, source_name)
            return len(out) < max_events
        try:
            ical.foreach_recurrence(
                ICalGLib.Time.new_from_timet_with_zone(range_start, tz),
                ICalGLib.Time.new_from_timet_with_zone(range_end, tz),
                cb,
                None,
            )
            return
        except Exception:
            pass

    if start_ts < range_start or start_ts >= range_end:
        return
    emit_event(out, uid, summary, start_ts, end_ts, all_day, source_name)


def main():
    days = 7
    max_events = 50
    if len(sys.argv) > 1:
        try:
            days = max(1, int(sys.argv[1]))
        except ValueError:
            pass
    if len(sys.argv) > 2:
        try:
            max_events = max(1, int(sys.argv[2]))
        except ValueError:
            pass

    now = datetime.datetime.now(datetime.timezone.utc)
    range_start_dt = now.replace(hour=0, minute=0, second=0, microsecond=0)
    range_end_dt = range_start_dt + datetime.timedelta(days=days)
    range_start = int(range_start_dt.timestamp())
    range_end = int(range_end_dt.timestamp())

    query = '(occur-in-time-range? (make-time "%s") (make-time "%s"))' % (
        range_start_dt.strftime("%Y%m%dT%H%M%SZ"),
        range_end_dt.strftime("%Y%m%dT%H%M%SZ"),
    )

    registry = EDataServer.SourceRegistry.new_sync(None)
    sources = registry.list_sources(EDataServer.SOURCE_EXTENSION_CALENDAR)

    import threading

    results = []
    lock = threading.Lock()

    def fetch_source(source):
        if not source.get_enabled():
            return
        name = source.get_display_name() or source.get_uid()
        try:
            client = ECal.Client.connect_sync(source, ECal.ClientSourceType.EVENTS, 2, None)
        except Exception:
            return
        try:
            ok, comps = client.get_object_list_as_comps_sync(query, None)
        except Exception:
            return
        if not ok or not comps:
            return
        local = []
        for comp in comps:
            if len(local) >= max_events:
                break
            try:
                process_component(local, comp, name, range_start, range_end, max_events)
            except Exception:
                continue
        with lock:
            results.extend(local)

    threads = []
    for source in sources:
        t = threading.Thread(target=fetch_source, args=(source,), daemon=True)
        t.start()
        threads.append(t)
    for t in threads:
        t.join(timeout=3)

    results.sort(key=lambda e: e["start"])
    results = results[:max_events]
    print(json.dumps(results))


if __name__ == "__main__":
    main()
