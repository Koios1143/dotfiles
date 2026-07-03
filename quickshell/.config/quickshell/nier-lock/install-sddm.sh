#!/usr/bin/env bash
#
# Install the modified nier-automata theme into the system SDDM themes dir so the
# login screen matches the lock screen. Run with sudo:
#
#     sudo bash install-sddm.sh
#
# It backs up the current theme first (once), copies the new theme + assets
# (svgs/, YoRHa_logo/) over it, strips helper scripts, and fixes ownership.

set -euo pipefail

SRC="/home/koios/dotfiles/quickshell/.config/quickshell/nier-lock/themes/nier-automata"
DST="/usr/share/sddm/themes/nier-automata"
BAK="${DST}.bak"

[ "$(id -u)" -eq 0 ] || { echo "Please run with sudo: sudo bash $0" >&2; exit 1; }
[ -d "$SRC" ] || { echo "source theme not found: $SRC" >&2; exit 1; }
[ -f "$SRC/Main.qml" ] || { echo "source Main.qml missing" >&2; exit 1; }

# Backup once (don't clobber an existing good backup on re-run)
if [ -d "$DST" ] && [ ! -e "$BAK" ]; then
    cp -a "$DST" "$BAK"
    echo "Backed up current theme -> $BAK"
elif [ -e "$BAK" ]; then
    echo "Backup already exists ($BAK), leaving it untouched."
fi

mkdir -p "$DST"
# Merge new theme contents over the existing dir
cp -a "$SRC/." "$DST/"
# Helper scripts shouldn't live in the deployed theme
rm -f "$DST/regenerate.sh" "$DST/install-sddm.sh"
# System theme should be root-owned and world-readable
chown -R root:root "$DST"
chmod -R a+rX "$DST"

echo "SDDM theme 'nier-automata' updated from $SRC"
echo "Test without logging out:  sddm-greeter-qt6 --test-mode --theme $DST"
echo "Revert if needed:          sudo rm -rf $DST && sudo mv $BAK $DST"
