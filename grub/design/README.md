# YoRHa Boot Manager — design source

Imported from the Claude Design project **"GRUB Boot menu 設計稿"**
(`https://claude.ai/design/p/79f970ca-c930-4d90-a7c1-8ccf7035801d`) via the `DesignSync` MCP.

## Files

| File | What it is |
| --- | --- |
| `YoRHa Boot Manager.dc.html` | The base page — a `.dc` component (template + `DCLogic` class). Source of truth for layout, colors, spacing. |
| `YoRHa Boot Manager - Centered.dc.html` | The `centered` variant's page. Identical to the base except for the four edits listed below. |
| `support.js` | Generated `dc-runtime` needed to render the `.dc.html` in a browser. Do not edit. |
| `uploads/yorha.svg` | YoRHa emblem, `fill: #cfc8ba`, viewBox `6 21 197 232`. |

Not imported: the *YoRHa Boot Manager - Key Art* page, and the binary reference
sketches (`uploads/draw-*.png`, `uploads/keyart-*.png`, `uploads/圖片*.png`).
Fetch them from the project if needed.

## Centered vs base

The Centered page differs from the base page in exactly four places:

1. the countdown's `<svg>` (track circle + `stroke-dashoffset` progress arc) is
   deleted, leaving only the digits and the `SEC` caption in the 16cqh box;
2. the section title row goes from `marginTop: 12cqh; paddingLeft: 1cqh` to
   `marginTop: auto; justifyContent: center`;
3. the menu block gains `alignSelf: center`;
4. the `DEFAULT TARGET` strip gains `alignSelf: center` and `marginBottom: auto`.

Edits 2 and 4 add two `auto` margins to the flex column, which together with the
footer rule's existing `marginTop: auto` makes three — flexbox splits the free
space equally between them, so the menu group lands one third of the way down
the space below the header, not at its centre.

Preview locally: `python3 -m http.server` inside this directory, then open
`YoRHa Boot Manager.dc.html`. The runtime expects `window.React` / `window.ReactDOM`, so the
in-browser preview only works where those are provided — otherwise read it as a spec.

## Design spec (for the GRUB theme)

Reference resolution 1920×1080; all sizes in the design are `cqh` (percent of viewport height),
so they scale to any resolution.

Palette:

- background `#0c0a08` (page `#08070a`), plus a radial warm wash `rgba(70,58,44,0.20)` at 30%/40%
- foreground / body text `#cfc8ba`, used at opacity 0.26–0.92 for hierarchy
- highlight / selected `#f2ead9`, timer digits `#f3ecdd`, timer ring `#efe6d4`
- unselected menu entry text = foreground at `dimOpacity` (default 0.5)

Type: IBM Plex Mono (weights 200/300/400) for everything; Chakra Petch 400 for the countdown
digits. Wide letter-spacing throughout (0.08em body → 0.34em small caps labels).

Layout:

- 1px inset frame at 3cqh with deliberate gaps, plus 2.4cqh corner brackets at 2.2cqh
- header: emblem (10.6cqh tall, opacity 0.62) + `VER.<version>` / `SYSTEM BOOT MANAGER` /
  `YoRHa BOOT CONTROL INTERFACE`
- countdown: 16cqh ring top-right at 4.2cqh, `stroke-dasharray` 289.03 (= 2πr, r=46), depleting
  clockwise; center shows zero-padded seconds + `SEC`
- menu: `/// SELECT BOOT TARGET` header, then 4 entries — 58cqh wide, 7cqh tall, 1cqh gap.
  Selected entry gets a 1px `rgba(230,220,200,0.75)` box with 2px corner ticks, a faint
  left-to-right gradient fill, a glow, and a filled rotated-45° diamond bullet. Unselected
  entries are text + hollow diamond only.
- `DEFAULT TARGET / <label>` strip under the menu
- footer: `YORHA SYSTEMS // BOOT CONTROL v<version>` left; keycap legend right —
  ENTER=CONFIRM, ↑↓=SELECT, E=OPTIONS, C=CMD-LINE, ESC=BACK
- decoration: dotted grid (5.2cqh major / 1.3cqh minor), CRT scanlines at 0.55 opacity,
  fractal-noise film grain at 0.035, `+` registration marks, vertical tick strips,
  `YRH-001` / `E-11.02.4-4.3-R` / `SYS-BOOT-CTRL` / `EID_22-107-FA` panel labels

Menu entries in the mock: `Arch Linux`, `Advanced options for Arch Linux`,
`Windows Boot Manager`, `UEFI Firmware Settings`.
