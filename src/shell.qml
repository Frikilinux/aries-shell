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
import "modules/wallpaper"

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
                            iconStyle: "light"
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
    // ignores input, so a separate bottom-layer scrim does the popup dismissal
    // on empty-desktop clicks. Screens filtered via Config.outputs("wallpaper").
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

    // Independent admin window (hidden by default)
    // FloatingWindow {
    //     id: controlCenter
    //     visible: false
    //     width: 400
    //     height: 500

    //     ControlCenterContent {}
    // }
}
