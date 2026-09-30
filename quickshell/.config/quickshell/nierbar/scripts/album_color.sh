#!/usr/bin/env bash
# Pick a single accent colour from the currently playing track's art. Rather
# than a Material-You "most vivid seed" (which grabs the punchiest pixel and can
# ignore what actually dominates the cover), this takes the *dominant* colour:
# quantise the art down so near-identical shades merge, drop white/black/greys,
# then keep the most-populous colourful bucket. A dark result is lifted so it
# still reads on the near-black bar. Prints "#rrggbb", nothing on failure.
#
# Usage: album_color.sh <art-url>   (file:// | bare path | http(s) URL)
set -euo pipefail

url="${1:-}"
[ -z "$url" ] && exit 0

tmp=""
cleanup() { [ -n "$tmp" ] && rm -f "$tmp"; }
trap cleanup EXIT

case "$url" in
  http://* | https://*)
    tmp="$(mktemp --suffix=.art)"
    curl -fsL --max-time 8 "$url" -o "$tmp" 2>/dev/null || exit 0
    src="$tmp"
    ;;
  file://*)
    src="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.argv[1][7:]))' "$url")"
    ;;
  *)
    src="$url"
    ;;
esac
[ -f "$src" ] || exit 0

# Quantise to 8 colours (merges the many near-identical shades of the dominant
# hue), then for each bucket compute saturation; keep colourful, non-near-black
# buckets and pick the one covering the most pixels. Lift very dark winners so a
# deep dominant (e.g. maroon) is still visible as a stroke on the dark bar.
magick "$src" -resize 200x200 -colors 8 -depth 8 -format %c histogram:info:- 2>/dev/null | awk '
  match($0, /#[0-9A-Fa-f]{6}/) {
    cnt = $1 + 0
    hex = substr($0, RSTART, 7)
    r = strtonum("0x" substr(hex, 2, 2))
    g = strtonum("0x" substr(hex, 4, 2))
    b = strtonum("0x" substr(hex, 6, 2))
    mx = (r > g ? (r > b ? r : b) : (g > b ? g : b))
    mn = (r < g ? (r < b ? r : b) : (g < b ? g : b))
    sat = (mx == 0 ? 0 : (mx - mn) / mx)
    if (sat > 0.30 && mx > 40 && cnt > best) { best = cnt; br = r; bg = g; bb = b; bmx = mx }
  }
  END {
    if (best == 0) exit 0                       # no colourful bucket -> keep theme colour
    if (bmx < 150) { f = 150 / bmx; br *= f; bg *= f; bb *= f }   # lift if too dark
    if (br > 255) br = 255; if (bg > 255) bg = 255; if (bb > 255) bb = 255
    printf "#%02x%02x%02x\n", br, bg, bb
  }
'
