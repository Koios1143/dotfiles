#!/bin/sh
# wl-paste --watch hook: store the incoming clipboard (on stdin) into cliphist,
# then record a timestamp for the newly-stored top entry (cliphist has no times).
cliphist store
dir="${XDG_CACHE_HOME:-$HOME/.cache}/cliphist"
id=$(cliphist list 2>/dev/null | head -n1 | cut -f1)
[ -n "$id" ] && printf '%s\t%s\n' "$id" "$(date +%s)" >> "$dir/stamps"
