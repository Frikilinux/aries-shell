#!/usr/bin/env python3
"""Open the xdg-desktop-portal file chooser and print the selection.

Usage:
    portal-picker.py files [--title TITLE]
    portal-picker.py directory [--title TITLE]

Prints one absolute path per line on stdout and exits 0. Exits 1 when the
dialog is cancelled, no portal is available, or nothing was selected.

This runs as a short-lived helper spawned by the QML side (see
AriesConnectService.qml). It uses Gio so the portal connection stays alive
while the user picks and the Response signal is delivered to us directly.
"""

import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

PORTAL_BUS = "org.freedesktop.portal.Desktop"
PORTAL_PATH = "/org/freedesktop/portal/desktop"
PORTAL_IFACE = "org.freedesktop.portal.FileChooser"
REQUEST_IFACE = "org.freedesktop.portal.Request"


def build_options(directory: bool) -> "GLib.Variant":
    options = {
        "multiple": GLib.Variant("b", not directory),
        "directory": GLib.Variant("b", directory),
        "modal": GLib.Variant("b", True),
    }
    return GLib.Variant("a{sv}", options)


def main(argv: list[str]) -> int:
    mode = "files"
    title = "Share files"
    rest = argv[1:]
    i = 0
    while i < len(rest):
        arg = rest[i]
        if arg == "--title" and i + 1 < len(rest):
            title = rest[i + 1]
            i += 2
            continue
        if arg in ("files", "directory"):
            mode = arg
            title = "Select a folder" if mode == "directory" else "Share files"
        i += 1

    directory = mode == "directory"

    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    except GLib.Error as err:
        print(f"portal unavailable: {err.message}", file=sys.stderr)
        return 1

    try:
        args = GLib.Variant.new_tuple(
            GLib.Variant("s", ""),
            GLib.Variant("s", title),
            build_options(directory),
        )
        reply = bus.call_sync(
            PORTAL_BUS,
            PORTAL_PATH,
            PORTAL_IFACE,
            "OpenFile",
            args,
            GLib.VariantType.new("(o)"),
            Gio.DBusCallFlags.NONE,
            -1,
            None,
        )
    except GLib.Error as err:
        print(f"cannot open the file chooser: {err.message}", file=sys.stderr)
        return 1

    handle = reply.unpack()[0]
    state = {"response": 1, "uris": [], "loop": GLib.MainLoop()}

    def on_response(_conn, _sender, path, _iface, _member, params, _data):
        if path != handle:
            return
        response, results = params.unpack()
        state["response"] = response
        uris = results.get("uris")
        if uris is not None:
            state["uris"] = list(uris)
        state["loop"].quit()

    # The dialog takes human time, so subscribing after the call is safe: the
    # response cannot arrive before the user interacts.
    subscription = bus.signal_subscribe(
        PORTAL_BUS,
        REQUEST_IFACE,
        "Response",
        handle,
        None,
        Gio.DBusSignalFlags.NONE,
        on_response,
        None,
    )

    state["loop"].run()
    bus.signal_unsubscribe(subscription)

    if state["response"] != 0 or not state["uris"]:
        return 1

    count = 0
    for uri in state["uris"]:
        local = Gio.File.new_for_uri(uri).get_path()
        if local:
            print(local)
            count += 1
    return 0 if count > 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
