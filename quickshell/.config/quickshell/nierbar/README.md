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
[right] volume brightness network cpu gpu ram battery bluetooth keyboard
```

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
| Bluetooth | state | none | open bluetooth manager fallback |
| Keyboard | keyboard label | none | none |

## Customization

Edit these files:

- `style/Theme.qml`: colors, sizes, font, compactness
- `components/WorkspaceStrip.qml`: `workspaceCount`
- `components/SystemCluster.qml`: command fallbacks and status item behavior
- `scripts/system_state.sh`: metrics backend

## Notes

The bar intentionally avoids SSID / WiFi signal text in the visible bar. Network only displays one icon: WiFi, wired, or disconnected.


## fix2 note
For Quickshell 0.3.0, `Variants` uses `model: Quickshell.screens` rather than `variants:`.
