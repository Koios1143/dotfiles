#!/usr/bin/env bash
#
# build.sh
# 產生 YoRHa Boot Manager GRUB 主題。
#
# 流程：
#   1. 確認 grub-mkfont / python3 + pycairo + pygobject 在
#   2. 抓 vendor 字型（IBM Plex Mono、Chakra Petch，只抓一次）
#   3. 對每個解析度算出 theme.txt + background.png + 9-slice 選單框 + .pf2
#
# 有兩個版型，對應 Claude Design 上的兩個 page：
#   yorha           基本款：選單靠左、右上角有圓形倒數
#   yorha-centered  Centered：選單置中、倒數只剩數字沒有圓框
#
# 產物在 dist/<版型>/<寬x高>/，另外每個解析度會輸出
# dist/<版型>/preview-<寬x高>.png ——那是「用 GRUB 自己的排版算式」
# 合成的模擬圖，用來檢查版面，不是主題的一部分。
#
# 用法：
#   ./build.sh                       兩個版型 × 全部 10 個解析度
#   ./build.sh 1920x1080 2560x1440   只產生指定解析度（仍是兩個版型）
#   ./build.sh --variant centered 1920x1080   只產生 centered
#   ./build.sh --rows 4 1920x1080    選單保留 4 列（預設 5，可 3–6）
#   ./build.sh --menu-width 76 …     選單加寬（預設 58cqh，項目名稱太長時用）
#   ./build.sh --no-grain            不烤入底片顆粒（背景圖會小很多）
#
# 其他旗標直接轉給 yorha_theme.py，看 ./yorha_theme.py --help。
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here"

for cmd in grub-mkfont python3; do
  command -v "$cmd" >/dev/null || {
    echo "缺 $cmd。grub-mkfont 來自 grub 套件。" >&2
    exit 1
  }
done

if ! python3 - <<'EOF'
import cairo, gi
gi.require_version("PangoCairo", "1.0")
gi.require_version("Rsvg", "2.0")
from gi.repository import PangoCairo, Rsvg
EOF
then
  echo "缺 python 繪圖相依：sudo pacman -S --needed python-cairo python-gobject librsvg" >&2
  exit 1
fi

./fetch-fonts.sh

exec python3 yorha_theme.py "$@"
