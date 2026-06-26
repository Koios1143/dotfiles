#!/usr/bin/env bash
set -euo pipefail
src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dst="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/nierbar"
mkdir -p "$dst"
rsync -a --delete "$src/" "$dst/"
echo "Installed to $dst"
echo "Run: quickshell -c $dst/shell.qml"
