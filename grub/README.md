# YoRHa Boot Manager — GRUB theme

A NieR:Automata-styled GRUB boot menu, generated from the Claude Design mock in
[`design/`](design/README.md).

```
grub/
├── design/          the source designs (.dc components + emblem) — see design/README.md
├── yorha_theme.py   the generator: rasterises the design and emits theme.txt
├── build.sh         entry point (checks deps, vendors fonts, runs the generator)
├── fetch-fonts.sh   downloads IBM Plex Mono + Chakra Petch into vendor/
├── install.sh       installs one built variant+resolution into /boot/grub/themes/
├── vendor/          downloaded TTFs                        (gitignored)
└── dist/            built themes + layout previews          (gitignored)
```

`dist/` and `vendor/` are not committed — everything is reproducible from
`design/` plus the two font downloads.

## Variants

Two layouts, one per design page. They install to different directories and can
coexist; switching is just a `GRUB_THEME` change.

| Variant | Design page | Menu | Countdown | Installs to |
|---|---|---|---|---|
| `left` (default) | *YoRHa Boot Manager* | left-aligned at the 7.2cqh inset | digits inside a depleting ring | `/boot/grub/themes/yorha` |
| `centered` | *YoRHa Boot Manager - Centered* | centred in the content box | digits + `SEC` only, no ring | `/boot/grub/themes/yorha-centered` |

Everything else — palette, header, frame, decorations, footer legend, row
artwork — is identical.

The centered page also moves the vertical rhythm: it drops the fixed 12cqh gap
under the header in favour of `margin-top: auto` on the section title and
`margin-bottom: auto` on the `DEFAULT TARGET` strip. Together with the footer
rule's existing auto margin that makes three auto margins, and flexbox splits
the free space equally between them, so the menu group sits one third of the way
down the space below the header rather than dead centre. The generator
reproduces that arithmetic rather than simply centring.

With no ring to draw, the centered variant still keeps a `circular_progress`
with `num_ticks = 0` — its `center_bitmap` carries the `SEC` caption so the
caption disappears together with the digits when the countdown is cancelled.
(`check_pixmaps` insists on a `tick_bitmap` too, hence the unused 1×1 `tick.png`.)

## Build

```sh
./build.sh                              # both variants x ten resolutions, ~6 s
./build.sh 1920x1080                    # both variants, one resolution
./build.sh --variant centered 1920x1080 # just the centered one
./build.sh --rows 4 1920x1080           # reserve 4 menu rows instead of 5
```

Needs `grub` (for `grub-mkfont`), `python-cairo`, `python-gobject`, `librsvg`,
and network access on first run for the fonts. `build.sh` checks and tells you
the pacman line if something is missing. These three are usually already present
as dependencies of the desktop stack, which is why they are not in
`pkglist-native.txt` (that file only lists explicitly-installed packages).

Each build also writes `dist/<variant>/preview-<WxH>.png`. That is **not** part
of the theme — it is a simulation of the final screen composited with GRUB's own
layout arithmetic (`get_num_shown_items`, `draw_menu`, `circprog_paint`,
`label_paint` from `grub-core/gfxmenu/`), so it catches geometry mistakes before
you reboot. Menu titles and the countdown digits in the preview are drawn by
decoding the generated `.pf2` glyph bitmaps, so the aliasing you see there is
the real thing rather than a smooth Pango stand-in.

## Text rendering

PFF2 glyphs are **1 bit per pixel** — `grub-mkfont` renders with
`FT_LOAD_RENDER | FT_LOAD_MONOCHROME` and nothing in GRUB antialiases text. So
the menu titles can never look as smooth as the header, which is rasterised into
`background.png` by cairo. Same typeface (IBM Plex Mono Light in both cases),
different rasteriser.

Hinting is therefore the only lever, and the fonts are built with
`--force-autohint`. Comparing the three modes at 11 / 13 / 17 / 23 / 26 px:
Plex's own TrueType hints leave visibly uneven stems at the larger sizes, and
unhinted rendering blobs together below ~14px, while the autohinter is
consistent across the whole range.

## Install

```sh
./install.sh --list                          # what is built
./install.sh 1920x1080 --dry-run
./install.sh 1920x1080                       # the left variant
./install.sh 1920x1080 --variant centered
```

It copies `dist/<theme-name>/<WxH>/` to `/boot/grub/themes/<theme-name>`, sets
`GRUB_THEME` and `GRUB_GFXMODE` in `/etc/default/grub` (showing you the diff
first, backing up to `grub.bak`), then offers to run `grub-mkconfig`.
`--timeout N` also sets `GRUB_TIMEOUT`.

`grub-mkconfig`'s `00_header` emits a `loadfont` for every `.pf2` in the theme
directory and an `insmod png` when it sees `*.png` there, which is why all assets
sit flat in the theme root rather than in subdirectories.

## Supported resolutions

| | | |
|---|---|---|
| 1920x1080 | 1920x1200 | 2560x1440 |
| 1600x1200 | 3840x2160 | 2256x1504 |
| 1280x1024 | 1024x768  | 800x600   |
| 640x480   |           |           |

GRUB bitmap fonts and pixmaps do not scale, so **each resolution is a separate
theme** and `GRUB_GFXMODE` must match the one you installed. If the real boot
mode differs, `desktop-image-scale-method: stretch` still stretches the
background so the screen remains usable — only the type size will be off.

The design is authored entirely in `cqh` (percent of viewport height), so all
ten modes are the same layout at different scales; wider aspect ratios simply
get more empty space to the right of the menu, exactly as the mock does.

## How it maps onto GRUB

GRUB's `gfxmenu` can draw solid colours, PNG bitmaps and 9-slice styled boxes.
Nothing else. The split of work:

**Baked into `background.png`** (exact pixel size, no scaling at runtime): the
dotted grid, CRT scanlines, film grain, frame rules with their deliberate gaps,
corner brackets, tick strips, registration marks, panel codes
(`YRH-001` / `E-11.02.4-4.3-R` / `SYS-BOOT-CTRL` / `EID_22-107-FA`), the emblem,
the whole header block, the section rule, the `DEFAULT TARGET` strip, and the
footer rule with its keycap legend.

**The menu rows** are a `boot_menu` whose `item_*.png` / `sel_*.png` styled boxes
are authored as one full-size item image and then cut into 9 slices. The cut is
chosen so GRUB's reassembly is *lossless*:

- `n`/`s` are scaled to the content width and `w`/`e` to the content height —
  both authored at exactly those sizes, so the scale factor is 1;
- corner slices are never scaled by GRUB, so the 2px corner ticks stay crisp;
- the west slice is `6.8cqh` wide and carries the diamond bullet at its design
  position, which is why the bullet is pixel-exact and needs no icon files.

`build.sh` asserts this: it re-assembles the slices the way
`grub-core/gfxmenu/widget-box.c` does and fails the build if the result is not
byte-identical to the authored item.

Because GRUB adds the box's top/bottom pads to `item_height`, the emitted
`item_height` is the design's `7cqh` row *minus* those pads, and `item_spacing`
adds them back — so `(height + item_spacing - 2*pad) / (item_height +
item_spacing)` lands on exactly the requested row count.

**The countdown** is a `circular_progress` of ~200 small dots plus a `label`
bound to `__timeout__`. The component is sized backwards from GRUB's
`radius = min(w,h)/2 - tick/2 - 1` so the ring lands on the design's radius.
The number of seconds comes from `GRUB_TIMEOUT`, not from the theme —
`./install.sh <WxH> --timeout 10` sets it.

The faint ring track and the `SEC` caption are **not** baked into the
background; they are the `circular_progress`'s `center_bitmap`. Pressing any
arrow key cancels the auto-boot, and GRUB then calls
`update_timeouts(0, …)` which hides every `__timeout__` component. Anything
baked into the background would survive that and leave an empty ring with no
digits in it; putting the track in `center_bitmap` makes the whole countdown
cluster disappear as one unit. `./build.sh --preview-remaining -1` renders that
post-keypress state so it can be checked.

## Deviations from the mock

These are GRUB limitations, not oversights:

1. **No outer glow on the selected row.** A styled box may not paint outside the
   item rectangle, so the design's `0 0 1.6cqh` outer glow is dropped; the inset
   glow is approximated with a soft inward ramp.
2. **The countdown ring empties the other way round** (`left` variant only —
   `centered` has no ring). The design's arc starts at 12 o'clock and shrinks
   clockwise. `circular_progress` always ends its sweep at `start_angle`, so
   with `ticks_disappear = true` the arc is anchored at 12 o'clock and shrinks
   counter-clockwise instead. Same reading, mirrored sweep. (Making it exact
   would mean painting background-coloured dots over a baked bright ring, which
   would erase the grid lines underneath.)
3. **The seconds are not zero-padded.** `label` renders `__timeout__` through a
   `%d` template, so it shows `8`, not `08`.
4. **No per-row icons and no hover state.** GRUB has one selected row, driven by
   the keyboard; the mock's `onClick` handlers have no equivalent.
5. **Menu row count is fixed at build time** (`--rows`, default 5, max 6). GRUB
   derives how many rows fit from the component height, so the space has to be
   reserved up front. Unused rows are just empty space. If you have more entries
   than rows the list still scrolls to follow the selection
   (`make_selected_item_visible`), but the scrollbar is disabled to keep the
   design clean, so there is no visual hint that more entries exist — set
   `--rows` to at least your real entry count. Rows past the mock's four are
   paid for by shrinking the 12cqh gap between the header and the section title
   (down to a 4cqh floor), which is what caps the count at 6.
6. **Long entry titles are clipped, not ellipsised or wrapped.** The mock's
   58cqh menu fits ~33 characters at 1920x1080, and real titles like
   `Windows Boot Manager (on /dev/nvme0n1p1)` are longer. Each build prints how
   many characters fit; widen with `--menu-width` (e.g. `76` → 45 characters).
   There is plenty of empty space to the right of the menu in the design.
7. **Film grain is value noise, not `feTurbulence`.** Visually equivalent at the
   design's 0.035 opacity. `--no-grain` drops it and shrinks `background.png`
   considerably.

## theme.txt gotcha

Global properties (`name: value`, outside any component block) **must** have
quoted values — `theme_loader.c`'s `read_property()` hard-errors on a bare word
and one bad line drops the entire theme:

```
theme_loader.c:read_property:723: .../theme.txt:11:16
property value invalid; enclose literal values in quotes (").
```

The `key = value` properties *inside* a `+ component { }` block go through
`read_expression()` instead, which does accept bare words. `build.sh` now
validates the emitted theme.txt against both rules and fails the build rather
than letting an unquoted global ship.

## Previewing in grub2-theme-preview

```sh
grub2-theme-preview --resolution 1920x1080 --timeout 10 dist/yorha/1920x1080
grub2-theme-preview --resolution 1920x1080 --timeout 10 dist/yorha-centered/1920x1080
```

**Always pass `--resolution` matching the build.** Without it the VM boots at
whatever mode GRUB picks; the background gets stretched to fit while the
`boot_menu`, ring and digits stay at their absolute pixel coordinates, so
everything looks misaligned and the bottom of the screen is cut off by the QEMU
window.

**Also pass `--timeout`.** The tool appends its own `set timeout=N` *after* your
grub.cfg (`_make_grub_cfg_load_our_theme`'s `epilog_chunks`), so it always
overrides `GRUB_TIMEOUT`; its default is 30s, not whatever you installed. `-1`
disables the countdown entirely, which correctly renders as nothing at all.

Two more things the preview cannot show, because they depend on the real
machine: entries produced at runtime by `15_uki`'s `uki` command (it scans
`/EFI/Linux` on the partition GRUB was loaded from, which in the VM is the
rescue ISO), and anything else keyed off real firmware.

## Not verified

The layout is verified against GRUB's own arithmetic via `dist/preview-*.png`,
and the slice round-trip is asserted at build time. It has **not** been
boot-tested — there is no qemu/OVMF on this machine, so the first real check is
rebooting after `./install.sh`. If the theme fails to load, GRUB falls back to
the plain menu; press `c` at the menu and run `lsfonts` to confirm the three
`yorha-*` fonts were loaded.
