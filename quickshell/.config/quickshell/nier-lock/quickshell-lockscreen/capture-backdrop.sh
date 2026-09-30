#!/usr/bin/env bash
#
# Grab the desktop for the opening transition to flood over, one PNG per
# output, named after the output. Sourced by lock.sh and preview.sh.
#
# Sets QS_LOCK_BACKDROP_DIR and installs a trap that wipes the directory when
# the caller exits. Everything lands in XDG_RUNTIME_DIR - tmpfs, 0700, gone on
# reboot - and the files are 0600, because a screenshot of an unlocked desktop
# is exactly as sensitive as the desktop was.
#
# Costs one grim per output (~110ms at 1920x1200) before the lock can appear.
# If grim is missing or fails, QS_LOCK_BACKDROP_DIR stays empty and the
# transition simply floods over black.

QS_LOCK_BACKDROP_DIR=""

_qs_wipe_backdrop() {
    [ -n "$QS_LOCK_BACKDROP_DIR" ] && rm -rf -- "$QS_LOCK_BACKDROP_DIR"
    QS_LOCK_BACKDROP_DIR=""
}

if command -v grim >/dev/null 2>&1; then
    QS_LOCK_BACKDROP_DIR="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/qylock-shot.XXXXXX")" || QS_LOCK_BACKDROP_DIR=""
fi

if [ -n "$QS_LOCK_BACKDROP_DIR" ]; then
    trap '_qs_wipe_backdrop' EXIT INT TERM HUP

    _qs_oldumask="$(umask)"
    umask 077
    _qs_captured=0
    _qs_last=""

    if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        for _qs_out in $(hyprctl monitors -j 2>/dev/null | jq -r '.[].name' 2>/dev/null); do
            if grim -o "$_qs_out" "$QS_LOCK_BACKDROP_DIR/$_qs_out.png" 2>/dev/null; then
                _qs_captured=$((_qs_captured + 1))
                _qs_last="$QS_LOCK_BACKDROP_DIR/$_qs_out.png"
            fi
        done
    fi

    # _all.png is what a surface falls back to when it can't find its own
    # output's capture. On one screen that's the same picture, so hardlink it
    # rather than paying for a second grim; with several there is no sensible
    # single fallback, so leave it out.
    if [ "$_qs_captured" -eq 0 ]; then
        grim "$QS_LOCK_BACKDROP_DIR/_all.png" 2>/dev/null || true
    elif [ "$_qs_captured" -eq 1 ]; then
        ln "$_qs_last" "$QS_LOCK_BACKDROP_DIR/_all.png" 2>/dev/null || true
    fi

    umask "$_qs_oldumask"
    unset _qs_oldumask _qs_captured _qs_last _qs_out
    export QS_LOCK_BACKDROP_DIR
fi
