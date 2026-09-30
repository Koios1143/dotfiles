import QtQuick
import Quickshell
import Quickshell.Wayland
import QtMultimedia
import "./shim"
import "nierintro"


ShellRoot {
    id: shellRoot

    property string activeTheme: Quickshell.env("QS_THEME") || "nier-automata"
    property string themePath: Quickshell.env("QS_THEME_PATH") || (Quickshell.shellDir + "/themes_link/" + activeTheme)

    readonly property var sddm: sddmShim.sddm
    readonly property var config: sddmShim.config
    readonly property var userModel: sddmShim.userModel
    readonly property var sessionModel: sddmShim.sessionModel
    readonly property bool isWayland: Quickshell.env("XDG_SESSION_TYPE") === "wayland"
    property bool authenticated: false
    property bool sessionLocked: true
    property bool isTesting: Quickshell.env("QS_TESTING") === "1"

    // lock.sh drops one screenshot per output in here before we start, so the
    // opening transition has the desktop it is supposed to be eating. Empty
    // (or a failed capture) just means the transition floods over black.
    property string backdropDir: Quickshell.env("QS_LOCK_BACKDROP_DIR") || ""

    SddmShim {
        id: sddmShim
        themePath: shellRoot.themePath
    }

    Connections {
        target: sddmShim.sddm
        function onLoginSucceeded() {
            shellRoot.authenticated = true

            // Hyprland session lock fix
            if (Quickshell.env("XDG_CURRENT_DESKTOP") === "Hyprland" || Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") !== "") {
                Quickshell.execDetached(["hyprctl", "keyword", "misc:allow_session_lock_restore", "1"]);
            }
            Quickshell.execDetached(["loginctl", "unlock-session"]);

            // Dynamic exit delay
            let delay = 100;
            if (activeTheme.includes("clockwork") && sddmShim.config.enableWindup === "true") {
                delay = 500;
            }
            quitTimer.interval = delay;
            quitTimer.start()
        }
    }

    Timer {
        id: quitTimer
        interval: 3000
        onTriggered: {
            shellRoot.sessionLocked = false
            Qt.quit()
        }
    }

    Component {
        id: themeComponent
        Item {
            id: stage
            anchors.fill: parent

            // which output this surface is on; the backdrop is per-screen
            property string screenName: ""

            // Sized like the theme rather than like the surface, so the
            // transition and the menu agree even in the windowed preview.
            readonly property real stageW: Screen.width
            readonly property real stageH: Screen.height

            // ── the desktop, being eaten ─────────────────────────────────────
            NierBackdrop {
                width: stage.stageW; height: stage.stageH
                amount: intro.latticeProgress
                visible: shot.status === Image.Ready || shotAll.status === Image.Ready

                Image {
                    id: shot
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    cache: false
                    source: (shellRoot.backdropDir !== "" && stage.screenName !== "")
                            ? "file://" + shellRoot.backdropDir + "/" + stage.screenName + ".png" : ""
                }
                Image {
                    id: shotAll
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    cache: false
                    // whole-layout fallback, only once the per-output one has
                    // actually failed - probing for it unconditionally just
                    // logs a missing file on every lock
                    visible: shot.status !== Image.Ready
                    source: (shellRoot.backdropDir !== "" && shot.status === Image.Error)
                            ? "file://" + shellRoot.backdropDir + "/_all.png" : ""
                }
            }

            // ── the opening ──────────────────────────────────────────────────
            NierIntro {
                id: intro
                width: stage.stageW; height: stage.stageH
                beige: "#c0bc9e"          // must match the theme's nierBg
                ink: "#2a2820"
                showRails: false          // the theme has its own top/bottom bars
            }

            // ── the lock screen itself ───────────────────────────────────────
            Loader {
                id: themeLoader
                width: stage.stageW; height: stage.stageH

                // chrome and background decoration ride in on the rail beat;
                // the theme's own reveal then brings the panels in.
                opacity: intro.railProgress

                // Source is set in Component.onCompleted below, not bound here:
                // the theme's own Component.onCompleted runs before the Loader's
                // onLoaded, so assigning externalIntro there is too late and the
                // theme starts its reveal on its own. setSource's initial
                // properties land before the component is completed.

                onLoaded: item.forceActiveFocus()
                onStatusChanged: {
                    if (status === Loader.Error) {
                        console.error("FAILED to load theme:", source)
                    }
                }
            }

            // The theme has the same seven-tab row the game does, so it gets
            // the real beat: bars on the rail wipe, tabs one per frame, then
            // the panels. No need to pull the panels forward the way the power
            // menu has to.
            Binding {
                target: themeLoader.item
                property: "tabsShown"
                value: intro.tabsShown
                when: themeLoader.item !== null
            }

            property bool revealStarted: false
            Connections {
                target: intro
                function onBodyProgressChanged() {
                    if (!stage.revealStarted && intro.bodyProgress > 0 && themeLoader.item) {
                        stage.revealStarted = true
                        themeLoader.item.startReveal()
                    }
                }
            }

            Component.onCompleted: {
                themeLoader.setSource("file://" + shellRoot.themePath + "/Main.qml", {
                    transparentBackground: true,   // NierIntro is the background
                    externalIntro: true            // ... and drives the reveal
                })
                intro.prepare()
                intro.start()
            }
        }
    }

    Loader {
        id: waylandLoader
        active: shellRoot.isWayland
        sourceComponent: Component {
            WlSessionLock {
                id: lock
                locked: shellRoot.sessionLocked
                surface: Component {
                    WlSessionLockSurface {
                        id: lockSurface
                        color: "black"
                        
                        // Absorb unhandled gestures
                        PinchHandler { target: null }
                        WheelHandler { target: null }
                        
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.AllButtons
                            hoverEnabled: true
                            onWheel: (wheel) => { wheel.accepted = true }
                        }

                        Loader {
                            anchors.fill: parent
                            sourceComponent: themeComponent
                            onLoaded: item.screenName = lockSurface.screen ? lockSurface.screen.name : ""
                        }
                    }
                }
            }
        }
    }

    Loader {
        id: x11Loader
        active: !shellRoot.isWayland
        sourceComponent: Component {
            Variants {
                model: Quickshell.screens
                delegate: Window {
                    id: window
                    required property var modelData
                    screen: modelData
                    width: isTesting ? 1280 : screen.width
                    height: isTesting ? 720 : screen.height
                    visible: shellRoot.sessionLocked
                    visibility: isTesting ? Window.Windowed : Window.FullScreen
                    
                    onClosing: (close) => {
                        close.accepted = shellRoot.authenticated || shellRoot.isTesting;
                    }
                    
                    flags: Qt.WindowStaysOnTopHint | Qt.FramelessWindowHint | Qt.MaximizeUsingFullscreenGeometryHint
                    color: "black"

                    Loader {
                        anchors.fill: parent
                        sourceComponent: themeComponent
                        onLoaded: item.screenName = window.screen ? window.screen.name : ""
                    }
                }
            }
        }
    }
}
