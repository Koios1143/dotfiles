#!/usr/bin/env bash
#
# Preview the lock screen APPEARANCE only — does NOT lock the session and
# never asks for a password.
#
# How it works: lock_shell.qml only creates a real WlSessionLock on the
# Wayland code path. By forcing the X11 / testing path we get a normal,
# closable window instead. PAM auth only fires if you actually type and
# submit a password, so previewing never prompts for one.
#
# Usage:  ./preview.sh [theme-name]        (defaults to nier-automata)
# Close:  Ctrl+C in this terminal, or your compositor's close-window keybind.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Library paths (same as lock.sh)
export QML2_IMPORT_PATH="$DIR/imports:$QML2_IMPORT_PATH"
export QML_XHR_ALLOW_FILE_READ=1

# Force the windowed, non-locking path in lock_shell.qml:
#   QS_TESTING=1        -> 1280x720 windowed & closable (X11 branch)
#   XDG_SESSION_TYPE=x11 -> isWayland=false, so WlSessionLock is NEVER created
export QS_TESTING=1
export XDG_SESSION_TYPE=x11

# Theme selection
export QS_THEME="${1:-nier-automata}"

# Self-contained themes dir (sibling ../themes), same resolution as lock.sh
if [ -d "$DIR/../themes" ] && [ ! -d "$DIR/themes_link" ]; then
    export QS_THEME_PATH="$DIR/../themes/$QS_THEME"
else
    export QS_THEME_PATH="$DIR/themes_link/$QS_THEME"
fi

echo "Previewing theme: $QS_THEME  (windowed, no lock, no password)"
echo "Theme path: $QS_THEME_PATH"
echo "Close with Ctrl+C or your window-close keybind."

quickshell -p "$DIR/lock_shell.qml"
