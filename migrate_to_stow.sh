#!/usr/bin/env bash
#
# migrate-to-stow.sh
# 把 $HOME 裡現有的 config 搬進 GNU Stow 結構，並建立 symlink。
#
# 流程（每個套件）：
#   1. 把 ~/REL（例如 ~/.config/hypr）整個 mv 進 $DOTFILES_DIR/<pkg>/REL
#   2. stow <pkg> → 在 ~ 底下建立 symlink 指回 repo
#
# 預設是 DRY-RUN：只印出「會做什麼」，不動到任何檔案。
# 確認無誤後，加上 --apply 才會真的搬移 + stow。
#
# 用法：
#   ./migrate-to-stow.sh            # dry-run，先看計畫
#   ./migrate-to-stow.sh --apply    # 真正執行
#
# 環境變數：
#   DOTFILES_DIR  （預設 ~/dotfiles）

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
DRY_RUN=1

# ---------------------------------------------------------------------------
# 要納管的路徑，相對於 $HOME。
# 每一個都會變成獨立的 Stow「套件」，名稱取自 basename（去掉開頭的點）。
#
# 注意：
#  - ~/.config/hypr 會「整個」搬進去，所以 hyprland.conf / hyprlock.conf /
#    hyprpaper.conf 只要在 hypr 資料夾裡，就會一起被搬，不用另外列。
#  - 不存在的路徑會自動跳過，可以放心多列。
#  - 跑完後 script 會掃描 ~/.config，把「存在但沒列到」的資料夾印出來提醒你。
# ---------------------------------------------------------------------------
PACKAGES=(
  ".config/hypr"
  ".config/waybar"
  ".config/swaync"
  ".config/mpv"
  ".config/kitty"
  ".zshrc"
  ".p10k.zsh"
  ".bashrc"
  ".vimrc"
  ".config/fcitx"
  ".config/fcitx5"
  ".config/fontconfig"
  ".config/gthumb"
  ".config/hyprshell"
  ".config/pulse"
  ".config/qylock"
  ".config/wlogout"
  ".config/Thunar"
  ".config/quickshell"
  ".config/qtvirtualkeyboard"
  ".config/qalculate"
  ".config/yazi"
  ".config/fastfetch"
)

# ---------------------------------------------------------------------------

for arg in "$@"; do
  case "$arg" in
    --apply) DRY_RUN=0 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "未知參數：$arg" >&2; exit 1 ;;
  esac
done

if [[ "$DRY_RUN" -eq 0 ]] && ! command -v stow >/dev/null 2>&1; then
  echo "找不到 stow，請先安裝：sudo pacman -S stow" >&2
  exit 1
fi

mkdir -p "$DOTFILES_DIR"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "=== DRY-RUN（不會動到任何檔案）。確認後請加 --apply ==="
else
  echo "=== APPLY 模式：真的會搬移檔案並 stow ==="
fi
echo "Dotfiles repo: $DOTFILES_DIR"
echo

# 由相對路徑算出套件名稱：basename 去掉一個開頭的點
pkg_name() {
  local base; base="$(basename "$1")"
  printf '%s' "${base#.}"
}

migrate_one() {
  local rel="$1"
  local src="$HOME/$rel"
  local pkg; pkg="$(pkg_name "$rel")"
  local dest="$DOTFILES_DIR/$pkg/$rel"
  local destdir; destdir="$(dirname "$dest")"

  echo "• $rel  (套件: $pkg)"

  # 已經是指向 dotfiles 的 symlink → 表示之前處理過了
  if [[ -L "$src" ]]; then
    local tgt; tgt="$(readlink -f "$src" 2>/dev/null || true)"
    if [[ "$tgt" == "$DOTFILES_DIR"/* ]]; then
      echo "    [skip] 已經 symlink 進 dotfiles"
      return 0
    fi
  fi

  if [[ ! -e "$src" ]]; then
    echo "    [skip] 不存在，略過"
    return 0
  fi

  if [[ -e "$dest" ]]; then
    echo "    [warn] repo 裡已存在 $dest，為避免覆蓋而略過"
    return 0
  fi

  echo "    [move] $src"
  echo "        -> $dest"
  echo "    [stow] $pkg"

  if [[ "$DRY_RUN" -eq 0 ]]; then
    mkdir -p "$destdir"
    mv "$src" "$dest"
    if stow -d "$DOTFILES_DIR" -t "$HOME" "$pkg"; then
      echo "    [ok] 已建立 symlink"
    else
      echo "    [error] stow 失敗！檔案已在 repo（$dest），但 symlink 未建立。" >&2
      echo "            可手動修正後再執行：stow -d $DOTFILES_DIR -t $HOME $pkg" >&2
    fi
  fi
  echo
}

for rel in "${PACKAGES[@]}"; do
  migrate_one "$rel"
done

# ---------------------------------------------------------------------------
# 掃描 ~/.config，提醒哪些資料夾存在但沒被列入 PACKAGES
# ---------------------------------------------------------------------------
echo "--- 掃描 ~/.config 中尚未納管的資料夾 ---"
listed=()
for rel in "${PACKAGES[@]}"; do
  [[ "$rel" == .config/* ]] && listed+=("${rel#.config/}")
done

shopt -s nullglob
for d in "$HOME/.config"/*/; do
  name="$(basename "${d%/}")"
  # 已經 symlink 進 dotfiles 的就跳過
  if [[ -L "${d%/}" ]]; then
    tgt="$(readlink -f "${d%/}" 2>/dev/null || true)"
    [[ "$tgt" == "$DOTFILES_DIR"/* ]] && continue
  fi
  found=0
  for l in "${listed[@]:-}"; do [[ "$l" == "$name" ]] && { found=1; break; }; done
  [[ "$found" -eq 0 ]] && echo "    [unlisted] .config/$name"
done
shopt -u nullglob

echo
echo "完成。若這是第一次 dry-run，檢視上面計畫沒問題後："
echo "    ./migrate-to-stow.sh --apply"
