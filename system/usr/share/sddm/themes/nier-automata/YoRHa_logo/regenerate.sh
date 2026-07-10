#!/usr/bin/env bash
#
# Regenerate the YoRHa emblem SVG frames from the source live-wallpaper video.
#
# The original frames were cropped too tightly on the left, which clipped the
# left spike into a flat edge. This script re-extracts every frame from the
# source video with a correct, symmetric crop (axis x≈614 in the 1920x1080
# frame) that leaves margin on all sides and stops short of the "YoRHa" text.
#
# Pipeline per frame:  ffmpeg crop -> grayscale threshold -> potrace -> SVG
#
# Requires: ffmpeg, imagemagick (magick), potrace
# Usage:    ./regenerate.sh [path-to-source.mp4]

set -euo pipefail

SRC="${1:-$HOME/Pictures/wallpapers/Yorha NieR Automata Live Wallpaper.mp4}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # output dir (this folder)
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Emblem crop in the 1920x1080 source (W:H:X:Y). Emblem union across all frames
# is abs x[498,730] y[386,665]; axis x≈614. "Y" text starts at abs x≈738.
CROP="244:305:492:373"
THRESH="50%"      # luminance split: dark emblem -> black, light bg/grid -> white
TURD="2"          # potrace despeckle (drop specks <= N px)

[ -f "$SRC" ] || { echo "source video not found: $SRC" >&2; exit 1; }

echo "Extracting + tracing frames from: $SRC"
ffmpeg -v error -y -i "$SRC" -vf "crop=$CROP" "$TMP/f_%04d.png"

count=0
for f in "$TMP"/f_*.png; do
    n="$(basename "$f" .png | sed 's/^f_//')"
    magick "$f" -colorspace Gray -threshold "$THRESH" "$TMP/bw.pbm"
    potrace -s --turdsize "$TURD" -o "$DIR/frame_$n.svg" "$TMP/bw.pbm"
    count=$((count + 1))
done

echo "Regenerated $count frames into $DIR"
