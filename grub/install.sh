#!/usr/bin/env bash
#
# install.sh
# 把 build.sh 產生的某一個解析度裝到 /boot/grub/themes/yorha，
# 並更新 /etc/default/grub 的 GRUB_THEME / GRUB_GFXMODE。
#
# 為什麼要指定解析度：GRUB 主題的字型是點陣（.pf2）、選單框是點陣圖，
# 沒有「跟著螢幕縮放」這回事。所以每個解析度是一份獨立的主題，
# 而 GRUB_GFXMODE 必須設成同一個值，畫面才會 1:1 對齊。
# （若實際開機模式不同，GRUB 會把背景圖 stretch 過去，仍可看，只是字級不對。）
#
# 這支 script 會動到開機設定，所以預設「先給你看 diff 再問」。
#
# 有兩個版型（對應 Claude Design 上的兩個 page）：
#   left      基本款：選單靠左、右上角有圓形倒數  → /boot/grub/themes/yorha
#   centered  Centered：選單置中、倒數沒有圓框      → /boot/grub/themes/yorha-centered
# 兩者裝在不同目錄，可以並存，換 GRUB_THEME 就能切。
#
# 用法：
#   ./install.sh --list                          列出已 build 好的版型／解析度
#   ./install.sh 1920x1080                       安裝 left（會問確認）
#   ./install.sh 1920x1080 --variant centered    安裝 centered
#   ./install.sh 1920x1080 --dry-run             只顯示會做什麼，絕不寫入
#   ./install.sh 1920x1080 --yes                 不問，直接做（含跑 grub-mkconfig）
#   ./install.sh 1920x1080 --no-mkconfig         裝檔＋改設定，但不重生 grub.cfg
#   ./install.sh 1920x1080 --timeout 10          順便把 GRUB_TIMEOUT 設成 10 秒
#
# 倒數秒數來自 GRUB_TIMEOUT，不是主題設定；主題只負責畫出來。
# 另外：一按方向鍵，GRUB 就取消自動開機並隱藏整個倒數（這是 GRUB 的行為）。
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dist="$here/dist"
theme_root="/boot/grub/themes"
default_grub="/etc/default/grub"
grub_cfg="/boot/grub/grub.cfg"

mode=""
variant="left"
dry_run=0
assume_yes=0
run_mkconfig=1
timeout=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout) timeout="${2:?--timeout 要接秒數}"; shift ;;
    --variant) variant="${2:?--variant 要接 left 或 centered}"; shift ;;
    --list)
      found=0
      for d in "$dist"/*/*/; do
        [[ -f "$d/theme.txt" ]] || continue
        res="$(basename "$d")"
        name="$(basename "$(dirname "$d")")"
        printf '  %-16s %s\n' "$name" "$res"
        found=1
      done
      [[ "$found" -eq 1 ]] || echo "  還沒 build，先跑 ./build.sh"
      exit 0
      ;;
    --dry-run) dry_run=1 ;;
    --yes|-y) assume_yes=1 ;;
    --no-mkconfig) run_mkconfig=0 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    -*) echo "未知旗標：$1" >&2; exit 1 ;;
    *) mode="$1" ;;
  esac
  shift
done

case "$variant" in
  left)     theme_name="yorha" ;;
  centered) theme_name="yorha-centered" ;;
  *) echo "--variant 只能是 left 或 centered，收到：$variant" >&2; exit 1 ;;
esac
theme_dir="$theme_root/$theme_name"

[[ -n "$mode" ]] || { echo "要指定解析度，例如 ./install.sh 1920x1080（--list 看有哪些）" >&2; exit 1; }

src="$dist/$theme_name/$mode"
[[ -f "$src/theme.txt" ]] || {
  echo "找不到 $src/theme.txt —— 先跑 ./build.sh --variant $variant $mode" >&2
  exit 1
}

run() {
  if [[ "$dry_run" -eq 1 ]]; then
    printf '  [dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

confirm() {
  [[ "$assume_yes" -eq 1 || "$dry_run" -eq 1 ]] && return 0
  read -rp "$1 [y/N] " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

# --- 1. 檔案 --------------------------------------------------------------
echo "=== 1/3 安裝主題檔到 $theme_dir ==="
echo "  來源 $src（$(du -sh "$src" | cut -f1)）"
if [[ -d "$theme_dir" ]]; then
  echo "  $theme_dir 已存在，會整個換掉（先刪再複製，避免留下舊解析度的圖）"
fi
if confirm "  要複製嗎？"; then
  run sudo mkdir -p "$theme_root"
  run sudo rm -rf "$theme_dir"
  run sudo cp -r "$src" "$theme_dir"
  run sudo sh -c "printf '%s %s\n' '$variant' '$mode' > '$theme_dir/.built-from'"
  # /boot 由 root 讀，GRUB 也只需要讀權限
  run sudo chmod -R a+rX "$theme_dir"
else
  echo "  略過檔案安裝。"
fi

# --- 2. /etc/default/grub ------------------------------------------------
echo "=== 2/3 更新 $default_grub ==="
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
cp "$default_grub" "$tmp"

set_key() {
  local key="$1" val="$2"
  if grep -qE "^[#[:space:]]*${key}=" "$tmp"; then
    # 取代第一個（不管原本有沒有被註解掉），其餘的註解起來以免後面覆寫
    awk -v k="$key" -v v="$val" '
      $0 ~ "^[#[:space:]]*"k"=" {
        if (!done) { print k"="v; done=1 }
        else { print "#"$0 }
        next
      }
      { print }
    ' "$tmp" > "$tmp.new" && mv "$tmp.new" "$tmp"
  else
    printf '%s=%s\n' "$key" "$val" >> "$tmp"
  fi
}

set_key GRUB_THEME "\"$theme_dir/theme.txt\""
set_key GRUB_GFXMODE "${mode}x32,${mode},auto"
if [[ -n "$timeout" ]]; then
  # 倒數圈是吃 GRUB_TIMEOUT 的，主題本身沒有秒數設定。
  set_key GRUB_TIMEOUT "$timeout"
fi

if grep -qE '^GRUB_TERMINAL_OUTPUT=.*console' "$tmp"; then
  echo "  !! GRUB_TERMINAL_OUTPUT 設成 console，gfxterm 不會啟用，主題不會出現。"
  echo "     請把那一行註解掉再重跑。"
fi

if diff -u "$default_grub" "$tmp" > /dev/null; then
  echo "  已經是想要的內容，不用改。"
else
  diff -u "$default_grub" "$tmp" || true
  if confirm "  要套用這個 diff 嗎？（原檔會備份成 ${default_grub}.bak）"; then
    run sudo cp "$default_grub" "${default_grub}.bak"
    run sudo cp "$tmp" "$default_grub"
  else
    echo "  略過設定更新。"
    run_mkconfig=0
  fi
fi

# --- 3. grub.cfg ---------------------------------------------------------
echo "=== 3/3 重生 $grub_cfg ==="
if [[ "$run_mkconfig" -eq 0 ]]; then
  echo "  略過（記得自己跑：sudo grub-mkconfig -o $grub_cfg）"
  exit 0
fi
echo "  grub-mkconfig 會為主題目錄裡的每個 .pf2 產生 loadfont，並 insmod png。"
if confirm "  要現在跑 grub-mkconfig 嗎？"; then
  run sudo grub-mkconfig -o "$grub_cfg"
  if [[ "$dry_run" -eq 0 ]]; then
    echo
    echo "  檢查產出的 grub.cfg 有沒有載到主題："
    sudo grep -E "loadfont|set theme|insmod (png|gfxmenu)" "$grub_cfg" | sed 's/^/    /'
  fi
else
  echo "  略過。記得自己跑：sudo grub-mkconfig -o $grub_cfg"
fi
