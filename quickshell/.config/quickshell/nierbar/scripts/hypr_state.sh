#!/usr/bin/env bash
set -euo pipefail

active="$(hyprctl activewindow -j 2>/dev/null || echo '{}')"

python3 - <<'PY' "$active"
import json, sys
try:
    win = json.loads(sys.argv[1])
except Exception:
    win = {}

title = win.get("title") or "Desktop"
klass = win.get("class") or ""
print(json.dumps({"title": title, "class": klass}, ensure_ascii=False))
PY
