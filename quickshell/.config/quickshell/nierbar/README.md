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

## Notes

The bar intentionally avoids SSID / WiFi signal text in the visible bar. Network only displays one icon: WiFi, wired, or disconnected.

`shell.qml` starts with `//@ pragma UseQApplication`. This is required for system
tray items to display their native context menus (right click); without it
Quickshell logs `Cannot display PlatformMenuEntry ...`. Changing this pragma
needs a full quickshell restart — a hot reload does not pick it up.


## fix2 note
For Quickshell 0.3.0, `Variants` uses `model: Quickshell.screens` rather than `variants:`.
