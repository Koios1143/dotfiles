# nierbar — Quickshell 0.3.0 / Hyprland 0.55.4

A compact NieR:Automata-inspired top HUD for Arch Linux, written in Quickshell/QML.

Target tested/design assumptions:

- Quickshell: 0.3.0
- Hyprland: 0.55.4
- Qt 6
- Workspace integration: `Quickshell.Hyprland`
- Focused window/system metrics: small script backends

## Install

```bash
mkdir -p ~/.config/quickshell
cp -r nierbar ~/.config/quickshell/nierbar
chmod +x ~/.config/quickshell/nierbar/scripts/*.sh
```

Run with the named config:

```bash
quickshell -c nierbar
```

Or run by explicit QML path:

```bash
quickshell -p ~/.config/quickshell/nierbar/shell.qml
```

Note: `quickshell -c ~/.config/quickshell/nierbar/shell.qml` is not valid. `-c` expects a config name under XDG config paths; use `-p` for a direct path.

## Dependencies

Required / expected:

```bash
sudo pacman -S quickshell hyprland qt6-declarative jq python
```

Useful optional dependencies:

```bash
sudo pacman -S wireplumber brightnessctl networkmanager bluez-utils pavucontrol
```

For the music effect (see below):

```bash
sudo pacman -S cava imagemagick playerctl
```

For GPU usage:

- NVIDIA: `nvidia-smi`
- AMD: `rocm-smi` if available; otherwise GPU may show `--%`

## Layout

```text
[left]  workspaces + focused window
[center] time / date, absolute centered
[right] volume brightness cpu gpu ram battery power network bluetooth [system tray]
```

The system tray (`components/SystemTray.qml`) sits at the far right and only
appears when at least one StatusNotifierItem app is registered; its leading
divider hides with it.

The clock is anchored with `anchors.horizontalCenter`, so it stays centered regardless of left/right content width.

## Interaction policy

| Component | Hover | Scroll | Left click |
|---|---|---|---|
| Workspace | none | switch workspace | jump to workspace |
| Focused window | full title only when truncated | none | none |
| Time | none | none | none |
| Volume | volume / muted | adjust volume | open pavucontrol/pwvucontrol |
| Brightness | percentage | adjust brightness | none |
| Network | connection type | none | open NetworkManager editor / nmtui |
| CPU/GPU/RAM | usage | none | open monitor fallback |
| Battery | percentage + remaining time | none | open power settings fallback |
| Power profile | current profile | none | cycle performance/balanced/power-saver |
| Bluetooth | state | none | open bluetooth manager fallback |
| System tray | per-item tooltip | scroll forwarded to item | activate item (menu-only items open their menu) |

System tray items also respond to middle click (secondary activate) and right
click (open the item's context menu).

## Customization

Edit these files:

- `style/Theme.qml`: colors, sizes, font, compactness
- `components/WorkspaceStrip.qml`: `workspaceCount`
- `components/SystemCluster.qml`: command fallbacks and status item behavior
- `components/SystemTray.qml`: which tray applets show — `hidden` (blocklist of
  SNI ids) and `allowed` (if non-empty, allow-list only those ids). Ids are
  case-sensitive; find one by hovering (tooltip) or `busctl --user get-property
  <svc> <path> org.kde.StatusNotifierItem Id`. Network/bluetooth are hidden by
  default since they already have dedicated bar items.
- `scripts/system_state.sh`: metrics backend

## Music effect

An opt-in mode that turns the clock's two side decorations into a live audio
visualiser. When enabled **and** an MPRIS player is actually playing, `cava`
taps the default sink's monitor and each side becomes a row of bars fed by that
spectrum. The bars grow **symmetrically up and down from the centre line**
(mirror style, not the usual upward-only), and bar order is mirrored left/right
so the lowest band sits nearest the clock on both sides. The bars are **tinted
with the track art's dominant colour** (via `scripts/album_color.sh`: quantise
so near-identical shades merge, drop white/black/greys, keep the most-populous
colourful bucket, lift if too dark). When the effect is off or playback stops,
the sides cross-fade back to their calm breathing `◇` ticks and `cava` is stopped.

The HUD frame is **not** affected by music — it keeps its idle breath in every
mode, and its four corner accent ticks pulse in/out on that same breath.

Everything audio-related is gated on both the toggle *and* live playback, so
`cava` stays unspawned while it's off or paused.

### Toggle

Bound to `SUPER + W` in Hyprland, which calls:

```bash
qs -c nierbar ipc call musicEffect toggle   # also: on / off
```

### Tuning

- `services/MusicEffectService.qml`: `vizGain` (bar magnitude scaling).
- `scripts/cava.conf`: `bars` (must match `AudioViz.count` in `CenterClock.qml`),
  `framerate`, input source.
- `scripts/album_color.sh`: quantise count, saturation threshold, dark-lift.
- `components/CenterClock.qml`: `AudioViz` bar `width` / `spacing` / `height`,
  and the breathing tick's size in `BreatheTick`.
- `components/Bar.qml`: corner-tick swing (`const c2 = 4 + 4 * frame.breath`).

Implementation: `MusicEffectService` (created once in `shell.qml`, shared by
every screen) owns the MPRIS watch, the `cava` stream (exposed as a `bars`
array), the dominant-colour extraction (`accentColor`), and the shared idle
`breath`. `CenterClock.qml` swaps its side ticks for `AudioViz` (bars tinted with
`accentColor`) while active; `Bar.qml` reads `breath` for the frame + corner ticks.

## Enterprise WiFi (802.1X)

Networks that nmcli reports as `WPA2 802.1X` / `WPA3 802.1X` (eduroam and most
campus SSIDs) need an account as well as a password, so the network popup shows
a separate panel for them with **Account**, **Password**, and an **EAP method**
picker (PEAP or TTLS, both paired with MSCHAPv2 — the combination essentially
every campus uses). Plain WPA networks keep the old password-only prompt; the
popup picks the right panel from the scanned security string.

`nmcli device wifi connect` can only carry a pre-shared key, so the enterprise
path goes through `scripts/wifi_enterprise.sh`, which creates (or updates) a
full NetworkManager profile named after the SSID and then activates it. The
credentials are passed in the environment rather than argv, because
`/proc/<pid>/cmdline` is world-readable while `/proc/<pid>/environ` is not:

```
NIERBAR_EAP_IDENTITY=<account> NIERBAR_EAP_PASSWORD=<password> \
  scripts/wifi_enterprise.sh connect <ssid> [eap] [phase2]
```

`NIERBAR_EAP_ANON` (anonymous outer identity) and `NIERBAR_EAP_CA` (CA cert
path) are also honoured but have no UI yet.

The password is stored in NetworkManager (`802-1x.password-flags 0`), so
reconnects and autoconnect work without asking again.

**Server certificate is not validated** unless `NIERBAR_EAP_CA` points at a CA
pem. That is the usual situation on campus networks that never publish one —
NetworkManager logs a warning and connects anyway. Set it when you do have the
certificate:

```
nmcli connection modify <ssid> 802-1x.ca-cert /path/to/ca.pem
```

If authentication fails, the account may need a realm suffix
(`user@example.edu` instead of `user`); watch the handshake with
`journalctl -fu NetworkManager -u wpa_supplicant`.


## Notes

The bar intentionally avoids SSID / WiFi signal text in the visible bar. Network only displays one icon: WiFi, wired, or disconnected.

`shell.qml` starts with `//@ pragma UseQApplication`. This is required for system
tray items to display their native context menus (right click); without it
Quickshell logs `Cannot display PlatformMenuEntry ...`. Changing this pragma
needs a full quickshell restart — a hot reload does not pick it up.


## fix2 note
For Quickshell 0.3.0, `Variants` uses `model: Quickshell.screens` rather than `variants:`.
