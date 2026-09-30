# nierintro

The NieR:Automata menu-open transition, reproduced in QML: a diagonal lattice
carves the screen, beige triangles flood it, two ruler rails wipe in, and the
caller's UI builds on the same beat.

Reconstructed frame-by-frame from `~/Videos/triangle_transformation.mp4`
(1920x1080, 23.976fps). Nothing here is random at runtime — the triangle order
is baked, so every run is identical and no run can draw an ugly distribution.

## Files

| | |
|---|---|
| `NierIntro.qml` | the transition itself (lattice, triangles, vignette, rails) |
| `NierBackdrop.qml` | optional: chromatic aberration + defocus on whatever is underneath |
| `fillorder.js` | the baked 9x17 triangle fill order |
| `assets/vignette.png` | the vignette ramp, lifted off the footage |
| `assets/ca.frag[.qsb]` | the distortion shader (recompile with `qsb`, see below) |
| `Preview.qml` | live preview with a stand-in menu |
| `Capture.qml` | deterministic frame dumper, for diffing against the footage |

## Use

```qml
import QtQuick
import "path/to/nierintro"

Item {
    NierBackdrop {                       // optional
        anchors.fill: parent
        amount: intro.latticeProgress
        Image { anchors.fill: parent; source: wallpaperOrScreenshot }
    }

    NierIntro { id: intro; anchors.fill: parent }

    // your UI, on the transition's beat
    Row {
        Repeater {
            model: tabs
            delegate: Tab { visible: index < intro.tabsShown }
        }
    }
    Item { opacity: intro.bodyProgress; /* title, list, footer */ }

    Component.onCompleted: { intro.prepare(); intro.start() }
}
```

`prepare()` pays the one-off cost of shader pipelines, FBOs and the first
Canvas paint (~90ms cold). Call it as early as you can; if you don't, `start()`
absorbs it by discarding the first tick rather than beginning mid-stall.

Outputs for the caller: `tabsShown` (0..`tabCount`, one more per frame),
`bodyProgress` (0..1), `fillStep`, `latticeProgress`, `railProgress`,
`finished()`.

## Geometry

9 rows of `cell = height / 9`. For row `r` and slot `s`, with `xc = cell * s`:

- `(r + s)` even -> apex up: `(xc, yt) (xc - cell, yb) (xc + cell, yb)`
- `(r + s)` odd  -> apex down: `(xc - cell, yt) (xc + cell, yt) (xc, yb)`

clipped to the width, which makes `s = 0` and `s = 16` the half shapes at the
edges. At 16:9 that is 17 slots per row, 153 shapes, 144 whole-triangle areas.
Sides are 45 degrees (half-base = height), not equilateral. Non-16:9 screens get
`round(width / cell)` slots and the order table wraps.

## Timeline

`t = 0` is the frame the HUD is cleared; source frame numbers in brackets.

| phase | t | source |
|---|---|---|
| lattice carves the screen | 0 - 292ms | n=20..26 |
| triangles flood in, 9 steps of 41.7ms | 292 - 626ms | n=27..35 |
| rails wipe in, eased out | 542 - 792ms | n=33..39 |
| tabs pop in, one per frame | 917 - 1168ms | n=42..48 |
| title / list / footer fade | 1168 - 1293ms | n=48..51 |

The rails start while the last few triangles are still landing — that overlap is
in the footage, not a mistake. Top rail wipes right-to-left, bottom rail
left-to-right; the lattice's two horizontals, which sit on the same two lines,
go the opposite way.

The glyph-scramble the game uses on its text is deliberately not implemented;
`bodyProgress` is a plain fade instead.

## Verifying against the footage

Needs a GPU scene graph — `QT_QPA_PLATFORM=offscreen` silently falls back to the
software renderer, which draws nothing for `ShaderEffect`. A headless weston
works:

```sh
weston --backend=headless --renderer=gl --width=1920 --height=1080 \
       --socket=wayland-cap &

# frame-aligned with the source (writes Q020.png .. Q052.png)
WAYLAND_DISPLAY=wayland-cap QT_QPA_PLATFORM=wayland \
  qml6 Capture.qml -- /tmp/shots /tmp/ref/R020.png

# or the whole transition at 60fps (writes C0000.png ..)
WAYLAND_DISPLAY=wayland-cap QT_QPA_PLATFORM=wayland \
  qml6 Capture.qml -- /tmp/smooth /tmp/ref/R020.png 60
```

Reference frames come out of the footage with:

```sh
ffmpeg -i ~/Videos/triangle_transformation.mp4 \
       -vf "select='between(n,18,56)'" -fps_mode passthrough -start_number 18 \
       /tmp/ref/R%03d.png
```

Comparing the beige masks of the two gives 96.6%..99.0% pixel agreement per
frame across the fill; the residual is 1px antialiased edges and the source's
h264 noise, with no whole triangle out of place.

## Rebuilding the shader

```sh
/usr/lib/qt6/bin/qsb --glsl "150,330" --hlsl 50 --msl 12 \
  -o assets/ca.frag.qsb assets/ca.frag
```

## Importing it from a quickshell config

Quickshell refuses module paths outside the config folder, and a QML module
name cannot contain a dash. So each consumer gets a symlink next to its
`shell.qml` and imports it by name:

```sh
ln -s ../nierintro powermenu/nierintro
```

```qml
import "nierintro"
```

## Wired up in

`../powermenu/` — the window is transparent and the transition floods the live
desktop, so no screenshot is needed. `showRails` is off there because the menu
has its own top and bottom bars; those wipe on `railProgress` instead, and the
panels start once the bars have landed rather than on the tab beat, since the
menu has no tab row to fill that gap with.

`NierBackdrop` is not used there: with a transparent window there is nothing
local to distort. Feeding it a `grim` screenshot would buy the chromatic
aberration and defocus at the cost of ~100ms before the window can appear.

`../nier-lock/` — the lock surface is opaque (the compositor blanks whatever is
behind an `ext-session-lock` surface), so there is nothing to show through and
the transition needs a real picture: `quickshell-lockscreen/capture-backdrop.sh`
grabs one PNG per output with `grim` before quickshell starts, and
`NierBackdrop` distorts it. Captures live in `$XDG_RUNTIME_DIR` (tmpfs, 0700,
files 0600) and are wiped when the lock exits. Cost is one grim per output,
~110ms at 1920x1200, before the lock can appear.

The theme has the same seven-tab row the game does, so it gets the full beat:
bars on the rail wipe, tabs one per frame off `tabsShown`, then the panels at
`bodyProgress`. `themes/nier-automata/Main.qml` is shared with SDDM, so it only
gained three opt-in properties - `transparentBackground`, `externalIntro`,
`tabsShown` - all defaulting to the old behaviour.

Two ordering traps worth knowing if you wire up another consumer:

- A loaded component's `Component.onCompleted` runs **before** the `Loader`'s
  `onLoaded`, so setting `externalIntro` there is too late and the theme starts
  its own reveal. Pass it through `Loader.setSource(url, {...})` instead.
- `visible: false` + `layer.enabled: true` yields an empty texture, because an
  invisible item never updates its layer. Use a `ShaderEffectSource` with
  `hideSource: true`, which is what `NierBackdrop` does.
