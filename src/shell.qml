//@ pragma IconTheme Zoticons
//@ pragma UseQApplication
// Log rules CANNOT be set in-config: LogManager::init runs before pragma
// parsing, so any `Env QT_LOGGING_RULES` pragma arrives too late (a no-op),
// and quoted values are discarded by the rule parser anyway. Pass rules at
// launch instead (verified qs 0.3.1):
//   qs -p <path> --log-rules 'quickshell.dbus.properties.warning=false;quickshell.service.sni.watcher.warning=false'
// Mutes playerctld NoActivePlayer noise + tray apps that register an SNI
// item and leave the bus ("Ignoring invalid StatusNotifierItem registration").

pragma ComponentBehavior: Bound

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
                    id: barRoot
                    // Modules are added to the left / center / right zones.
                    left: [
                        Launcher {
                            output: barRoot.modelData.name
                            outputs: Config.outputs(Config.revision, "launcher", barRoot.modelData.name)
                        },
                        Workspaces {
                            output: barRoot.modelData.name
                            outputs: Config.outputs(Config.revision, "workspaces", barRoot.modelData.name)
                        },
                        ActiveWindow {
                            output: barRoot.modelData.name
                            outputs: Config.outputs(Config.revision, "activeWindow", barRoot.modelData.name)
                        }
                    ]

                    // MPRIS media player (track info while playing, music icon when idle)
                    center: Mpris {
                        output: barRoot.modelData.name
                        outputs: Config.outputs(Config.revision, "mpris", barRoot.modelData.name)
                    }

                    right: [
                        Notifications {
                            output: barRoot.modelData.name
                            outputs: Config.outputs(Config.revision, "notifications", barRoot.modelData.name)
                        },
                        Offpeak {
                            output: barRoot.modelData.name
                            outputs: Config.outputs(Config.revision, "offpeak", barRoot.modelData.name)
                        },
                        Systray {
                            output: barRoot.modelData.name
                            outputs: Config.outputs(Config.revision, "systray", barRoot.modelData.name)
                        },
                        Bluetooth {
                            output: barRoot.modelData.name
                            outputs: Config.outputs(Config.revision, "bluetooth", barRoot.modelData.name)
                        },
                        Network {
                            output: barRoot.modelData.name
                            outputs: Config.outputs(Config.revision, "network", barRoot.modelData.name)
                        },
                        Volume {
                            output: barRoot.modelData.name
                            outputs: Config.outputs(Config.revision, "volume", barRoot.modelData.name)
                        },
                        Battery {
                            output: barRoot.modelData.name
                            outputs: Config.outputs(Config.revision, "battery", barRoot.modelData.name)
                        },
                        Clock {
                            output: barRoot.modelData.name
                            outputs: Config.outputs(Config.revision, "clock", barRoot.modelData.name)
                        },
                        Weather {
                            output: barRoot.modelData.name
                            outputs: Config.outputs(Config.revision, "weather", barRoot.modelData.name)
                        },
                        Power {
                            output: barRoot.modelData.name
                            outputs: Config.outputs(Config.revision, "power", barRoot.modelData.name)
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
            id: wallpaperRoot
            outputs: Config.outputs(Config.revision, "wallpaper", wallpaperRoot.modelData.name)
        }
    }

    // Volume OSD: transient overlay while the default sink's volume/mute
    // changes. One surface per screen, filtered like the bar's volume module.
    Variants {
        model: Quickshell.screens
        VolumeOsd {
            id: volumeOsdRoot
            outputs: Config.outputs(Config.revision, "volume", volumeOsdRoot.modelData.name)
        }
    }

    // Notification toasts: one overlay surface per screen showing the current
    // notification stack (newest on top). Independent from bar popups.
    Variants {
        model: Quickshell.screens
        NotificationToast {
            id: toastRoot
            outputs: Config.outputs(Config.revision, "notifications", toastRoot.modelData.name)
        }
    }

    // Polkit authentication dialog: built lazily, only while a request is
    // active (so no per-screen surface exists at idle). Reading PolkitService
    // in `active` also instantiates the agent singleton at startup.
    Variants {
        model: Quickshell.screens
        Loader {
            id: polkitLoader
            required property var modelData
            active: PolkitService.active
            sourceComponent: Component {
                Polkit {
                    modelData: polkitLoader.modelData
                    outputs: Config.outputs(Config.revision, "polkit", polkitLoader.modelData.name)
                }
            }
        }
    }

    // Launcher popup: built lazily on first use (LauncherIpc.enabled), then kept
    // so the surfaces persist. One centred overlay per screen, independent of
    // the bar icon, so a keybind opens it on the focused output.
    Variants {
        model: Quickshell.screens
        Loader {
            id: launcherLoader
            required property var modelData
            active: LauncherIpc.enabled
            sourceComponent: Component {
                LauncherPopup {
                    modelData: launcherLoader.modelData
                }
            }
        }
    }
}
