# YoRHa wlogout theme

NieR:Automata `SYSTEM`-menu styling for wlogout — six custom glyphs
(lock / logout / suspend / hibernate / shutdown / reboot), each with an
inverted "selected" variant so the highlighted tile flips ink↔light like
the in-game menu.

## Install

```sh
# back up any existing config first
mkdir -p ~/.config/wlogout
cp -r layout style.css icons ~/.config/wlogout/
```

Launch with a 3-wide grid (2 rows of 3):

```sh
wlogout -b 3
```

Bind it in `~/.config/hypr/hyprland.conf`:

```
bind = $mainMod, Escape, exec, wlogout -b 3
```

## Notes

- **Actions** in `layout` assume Hyprland (`hyprlock`, `hyprctl dispatch exit`).
  Swap `hyprlock` for `swaylock` etc. if you use a different locker.
- **Authentic frame:** for the dotted-domino border, drop your
  `YoRHa_bg1.png` into `icons/` and uncomment the three `background-image`
  lines under `window {}` in `style.css`.
- **Font:** best match is `Jost*` (AUR: `ttf-jost` / `otf-jost`). Falls back
  to Quicksand → Century Gothic → generic sans if absent.
- `padding-top` and `background-size` in `style.css` are the two knobs to
  tune glyph/label spacing for your resolution.
- Icons are plain SVG (`#454138` ink, `#d8d1bc` light) — recolour freely.
```
