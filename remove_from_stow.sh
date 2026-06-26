#!/usr/bin/env bash
#
# remove-from-stow.sh
# 安全地移除一個之前用 Stow 納管的套件。三種模式：
#
#   ./remove-from-stow.sh <pkg>            (預設, --keep)
#       解除 symlink → 把真檔搬回 $HOME → 從 repo 移除。
#       這台機器還能正常使用該 app，只是不再由 dotfiles 管理。
#
#   ./remove-from-stow.sh <pkg> --purge
#       解除 symlink → 直接從 repo 刪掉（檔案就此消失，不搬回家目錄）。
#       用於「連這個 app 都不要了」。
#
#   ./remove-from-stow.sh <pkg> --unlink
#       只解除這台機器的 symlink，repo 保留（之後還能 re-stow）。
#       用於「某台機器暫時不要這份設定」。
#
# 旗標：--yes 跳過確認；-h/--help 顯示說明。
# 環境變數：DOTFILES_DIR（預設 ~/dotfiles）

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
MODE="keep"
ASSUME_YES=0
PKG=""

for arg in "$@"; do
  case "$arg" in
    --keep)   MODE="keep" ;;
    --purge)  MODE="purge" ;;
    --unlink) MODE="unlink" ;;
    --yes|-y) ASSUME_YES=1 ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    -*) echo "未知旗標：$arg" >&2; exit 1 ;;
    *) PKG="$arg" ;;
  esac
done

if [[ -z "$PKG" ]]; then
  echo "用法：$0 <pkg> [--keep|--purge|--unlink] [--yes]" >&2
  exit 1
fi

PKGDIR="$DOTFILES_DIR/$PKG"
if [[ ! -d "$PKGDIR" ]]; then
  echo "在 repo 裡找不到套件目錄：$PKGDIR" >&2
  exit 1
fi

if ! command -v stow >/dev/null 2>&1; then
  echo "找不到 stow，請先安裝：sudo pacman -S stow" >&2
  exit 1
fi

confirm() {
  [[ "$ASSUME_YES" -eq 1 ]] && return 0
  local ans
  read -r -p "$1 [y/N] " ans
  [[ "$ans" == [yY] || "$ans" == [yY][eE][sS] ]]
}

# 把套件裡的真檔逐檔搬回 $HOME（保留目錄結構，合併進現有目錄）
restore_to_home() {
  ( cd "$PKGDIR" && find . -mindepth 1 \( -type f -o -type l \) -printf '%P\0' ) \
  | while IFS= read -r -d '' rel; do
      mkdir -p "$HOME/$(dirname "$rel")"
      cp -a "$PKGDIR/$rel" "$HOME/$rel"
      echo "    restored  ~/$rel"
    done
}

echo "套件：$PKG"
echo "模式：$MODE"
echo

# 不論哪種模式，第一步都先解除這台機器的 symlink。
# 這一步很重要：必須先解除，後續搬檔才不會透過 symlink 寫回 repo 自己。
echo "[unstow] 解除 symlink ..."
stow -D -d "$DOTFILES_DIR" -t "$HOME" "$PKG" || true

case "$MODE" in
  unlink)
    echo "完成：已解除 symlink，repo 中的 $PKG 保留。"
    echo "（要在本機重新啟用：cd $DOTFILES_DIR && stow $PKG）"
    ;;

  keep)
    if ! confirm "把 $PKG 的真檔搬回 \$HOME，並從 repo 移除 $PKGDIR？"; then
      echo "已取消（symlink 已解除，repo 副本未動）。如需復原：stow $PKG"
      exit 0
    fi
    echo "[restore] 搬回家目錄 ..."
    restore_to_home
    echo "[clean] 移除 repo 副本 $PKGDIR"
    rm -rf "$PKGDIR"
    echo
    echo "完成：$PKG 已脫離 dotfiles，真檔回到 \$HOME，app 照常運作。"
    ;;

  purge)
    if ! confirm "直接從 repo 刪除 $PKGDIR？（不搬回家目錄，檔案會消失）"; then
      echo "已取消（symlink 已解除，repo 副本未動）。如需復原：stow $PKG"
      exit 0
    fi
    echo "[purge] 刪除 $PKGDIR"
    rm -rf "$PKGDIR"
    echo
    echo "完成：$PKG 已從 repo 與家目錄移除。"
    ;;
esac

echo
echo "別忘了：cd $DOTFILES_DIR && git add -A && git commit -m \"remove $PKG\""
echo "提醒：這只動 config / symlink，不會 uninstall 套件本身。"
echo "      若整個 app 都不要了，另外 sudo pacman -Rns <package> 並重跑 ./dump.sh。"
