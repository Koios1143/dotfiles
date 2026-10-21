#!/usr/bin/env bash
# Toggle region screen recording to GIF.
# 1st press: select a region with slurp and start recording.
# 2nd press: stop recording, convert to GIF, copy it to the clipboard, delete the mp4.

set -u

tmp="${XDG_RUNTIME_DIR:-/tmp}/gif-record.mp4"
outdir="$HOME/Pictures/gifs"
fps=30
max_width=1280

if pkill -INT -f "wl-screenrec .*$tmp"; then
    exit 0
fi

geometry=$(slurp) || exit 0
rm -f "$tmp"

notify-send -a gif-record -t 2000 "GIF 錄影中" "再按 Super+Shift+R 停止"
wl-screenrec -g "$geometry" -f "$tmp"

if [[ ! -s "$tmp" ]]; then
    notify-send -a gif-record -u critical "GIF 錄影失敗" "沒有錄到任何畫面"
    rm -f "$tmp"
    exit 1
fi

mkdir -p "$outdir"
out="$outdir/$(date +%Y-%m-%d_%H-%M-%S).gif"
notify-send -a gif-record -t 2000 "GIF 轉換中…"

# Two-pass palette: generate an optimal 256-color palette, then dither with it.
ffmpeg -loglevel error -y -i "$tmp" -vf \
    "fps=$fps,scale='min(iw,$max_width)':-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" \
    -loop 0 "$out"
status=$?
rm -f "$tmp"

if (( status != 0 )); then
    notify-send -a gif-record -u critical "GIF 轉換失敗"
    exit 1
fi

wl-copy -t image/gif < "$out"
notify-send -a gif-record "GIF 已儲存" "$out ($(du -h "$out" | cut -f1))，已複製到剪貼簿"
