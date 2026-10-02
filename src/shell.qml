//@ pragma IconTheme Zoticons
//@ pragma UseQApplication
// Log rules CANNOT be set in-config: LogManager::init runs before pragma
// parsing, so any `Env QT_LOGGING_RULES` pragma arrives too late (a no-op),
// and quoted values are discarded by the rule parser anyway. Pass rules at
// launch instead (verified qs 0.3.1):
//   qs -p <path> --log-rules 'quickshell.dbus.properties.warning=false;quickshell.service.sni.watcher.warning=false'
// Mutes playerctld NoActivePlayer noise + tray apps that register an SNI
// item and leave the bus ("Ignoring invalid StatusNotifierItem registration").

import QtQuick
import Quickshell
import "modules/bar"
import "modules/config"
import "modules/clock"
import "modules/workspaces"
import "modules/activewindow"
import "modules/mpris"
import "modules/network"
import "modules/bluetooth"
import "modules/battery"
import "modules/power"
import "modules/systray"
import "modules/volume"
import "modules/weather"
import "modules/offpeak"
import "modules/notifications"
import "modules/wallpaper"
import "modules/launcher"
import "modules/polkit"

ShellRoot {
    // The bar (one per screen). Built once the user config has been read so
    // the bar never flashes with default values; modules are placed and shown
    // per the config (Config.outputs resolves "primary" and "*").
    Loader {
        active: Config.ready
        sourceComponent: Component {
            Variants {
                model: Quickshell.screens
                Bar {
                    // Modules are added to the left / center / right zones.
                    left: [
                        Launcher {
                            output: modelData.name
                            outputs: Config.outputs(Config.revision, "launcher", modelData.name)
                        },
                        Workspaces {
                            output: modelData.name
                            outputs: Config.outputs(Config.revision, "workspaces", modelData.name)
                        },
                        ActiveWindow {
                            output: modelData.name
                            outputs: Config.outputs(Config.revision, "activeWindow", modelData.name)
                        }
                    ]

                    // MPRIS media player (track info while playing, music icon when idle)
                    center: Mpris {
                        output: modelData.name
                        outputs: Config.outputs(Config.revision, "mpris", modelData.name)
                    }

                    right: [
                        Notifications {
                            output: modelData.name
                            outputs: Config.outputs(Config.revision, "notifications", modelData.name)
                        },
                        Offpeak {
                            output: modelData.name
                            outputs: Config.outputs(Config.revision, "offpeak", modelData.name)
                        },
                        Systray {
                            output: modelData.name
                            outputs: Config.outputs(Config.revision, "systray", modelData.name)
                        },
                        Bluetooth {
                            output: modelData.name
                            outputs: Config.outputs(Config.revision, "bluetooth", modelData.name)
                        },
                        Network {
                            output: modelData.name
                            outputs: Config.outputs(Config.revision, "network", modelData.name)
                        },
                        Volume {
                            output: modelData.name
                            outputs: Config.outputs(Config.revision, "volume", modelData.name)
                        },
                        Battery {
                            output: modelData.name
                            outputs: Config.outputs(Config.revision, "battery", modelData.name)
                        },
                        Clock {
                            output: modelData.name
                            outputs: Config.outputs(Config.revision, "clock", modelData.name)
                        },
                        Weather {
                            output: modelData.name
                            outputs: Config.outputs(Config.revision, "weather", modelData.name)
                        },
                        Power {
                            output: modelData.name
                            outputs: Config.outputs(Config.revision, "power", modelData.name)
                        }
                    ]
                }
            }
        }
    }

    // Desktop wallpaper + transparent click-catcher (one module, two surfaces):
    // the background-layer wallpaper also lives in niri's Overview backdrop and
    // ignores input, so a separate top-layer scrim (below the popups, above the
    // windows) does the popup dismissal on outside clicks. Screens filtered via
    // Config.outputs("wallpaper").
    Variants {
        model: Quickshell.screens
        Wallpaper {
            outputs: Config.outputs(Config.revision, "wallpaper", modelData.name)
        }
    }

    // Volume OSD: transient overlay while the default sink's volume/mute
    // changes. One surface per screen, filtered like the bar's volume module.
    Variants {
        model: Quickshell.screens
        VolumeOsd {
            outputs: Config.outputs(Config.revision, "volume", modelData.name)
        }
    }

    // Notification toasts: one overlay surface per screen showing the current
    // notification stack (newest on top). Independent from bar popups.
    Variants {
        model: Quickshell.screens
        NotificationToast {
            outputs: Config.outputs(Config.revision, "notifications", modelData.name)
        }
    }

    // Polkit authentication dialog: one overlay surface per screen, shown while
    // an administrative action is waiting for a response. The agent itself
    // lives in the PolkitService singleton (modules/polkit).
    Variants {
        model: Quickshell.screens
        Polkit {
            outputs: Config.outputs(Config.revision, "polkit", modelData.name)
        }
    }

    // Launcher popup: one centred overlay per screen, independent of the bar
    // icon, so a keybind opens it on the focused output (not on every monitor
    // or only the primary one). The bar icon toggles its own output's popup.
    Variants {
        model: Quickshell.screens
        LauncherPopup {
            // screen is bound to modelData inside LauncherPopup.
        }
    }
}
