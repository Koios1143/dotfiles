#!/usr/bin/env bash
#
# bootstrap.sh
# 在「新機器」上還原整套環境。流程：
#   1. 裝 stow / git / base-devel
#   2. 裝官方 repo 套件（pkglist-native.txt）
#   3. 裝 AUR helper（paru，若沒有）
#   4. 裝 AUR 套件（pkglist-aur.txt）
#   5. stow 所有套件資料夾 → 建立 symlink
#   6. 安裝手動 git clone 的套件（oh-my-zsh、外掛、tpm… → git-packages.txt）
#   7. （可選）啟用記錄到的 systemd services
#
# /etc 的系統設定不會自動還原（需 root，且可能需要手動調整）；
# 它們備份在 system/ 底下，請自行檢視後 sudo cp 回去。
#
# 用法：
#   git clone <你的 repo> ~/dotfiles && cd ~/dotfiles
#   ./bootstrap.sh                    # 裝套件 + stow + git 套件
#   ./bootstrap.sh --enable-services  # 同時啟用服務
#
# 環境變數：DOTFILES_DIR（預設 ~/dotfiles）、AUR_HELPER（預設 paru）

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
AUR_HELPER="${AUR_HELPER:-paru}"
ENABLE_SERVICES=0

for arg in "$@"; do
  case "$arg" in
    --enable-services) ENABLE_SERVICES=1 ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "未知參數：$arg" >&2; exit 1 ;;
  esac
done

cd "$DOTFILES_DIR"

echo "=== 1/7 基本工具 ==="
sudo pacman -S --needed --noconfirm stow git base-devel

echo "=== 2/7 官方 repo 套件 ==="
if [[ -f pkglist-native.txt ]]; then
  xargs -r -a pkglist-native.txt sudo pacman -S --needed --noconfirm
else
  echo "  找不到 pkglist-native.txt，略過"
fi

echo "=== 3/7 AUR helper ($AUR_HELPER) ==="
if ! command -v "$AUR_HELPER" >/dev/null 2>&1; then
  echo "  安裝 paru-bin ..."
  tmp="$(mktemp -d)"
  git clone https://aur.archlinux.org/paru.git "$tmp/paru"
  ( cd "$tmp/paru" && makepkg -si --noconfirm && sudo pacman -S --noconfirm /tmp/paru/paru-debug-*.pkg.tar.zst)
  rm -rf "$tmp"
else
  echo "  已存在，略過"
fi

echo "=== 4/7 AUR 套件 ==="
if [[ -f pkglist-aur.txt ]]; then
  xargs -r -a pkglist-aur.txt "$AUR_HELPER" -S --needed --noconfirm
else
  echo "  找不到 pkglist-aur.txt，略過"
fi

echo "=== 5/7 stow 套件 ==="
shopt -s nullglob
for d in */; do
  name="${d%/}"
  case "$name" in
    .git|system|scripts) continue ;;
  esac
  if stow -d "$DOTFILES_DIR" -t "$HOME" "$name" 2>/dev/null; then
    echo "  [stow] $name"
  else
    echo "  [conflict] $name —— 目標已有檔案，請手動處理："
    echo "             先備份/刪除衝突檔，再 stow -d $DOTFILES_DIR -t $HOME $name"
  fi
done
shopt -u nullglob

echo "=== 6/7 手動 git 套件 ==="
# 在 stow 之後跑：此時 .zshrc 等 symlink 已就位，
# 用純 git clone 不會碰到 .zshrc，所以順序安全。
if [[ -x ./install-git-packages.sh ]]; then
  ./install-git-packages.sh
else
  echo "  找不到 install-git-packages.sh，略過"
fi

echo "=== 7/7 services ==="
if [[ "$ENABLE_SERVICES" -eq 1 ]]; then
  if [[ -f services-system.txt ]]; then
    while read -r unit; do
      [[ -z "$unit" ]] && continue
      sudo systemctl enable "$unit" 2>/dev/null && echo "  [enable] $unit" || echo "  [skip] $unit"
    done < services-system.txt
  fi
  if [[ -f services-user.txt ]]; then
    while read -r unit; do
      [[ -z "$unit" ]] && continue
      systemctl --user enable "$unit" 2>/dev/null && echo "  [enable --user] $unit" || echo "  [skip] $unit"
    done < services-user.txt
  fi
else
  echo "  （未加 --enable-services，略過。清單見 services-system.txt / services-user.txt）"
fi

echo
echo "完成！後續手動項目："
echo "  • /etc 系統設定備份在 system/，檢視後再 sudo cp 回對應位置"
echo "  • 自訂字型已透過 fonts/ 這個 stow package symlink 到 ~/.local/share/fonts，執行 fc-cache -f 更新快取"
echo "  • tpm 裝好後，在 tmux 內按 prefix + I 安裝外掛；p10k 首次啟動會跑設定精靈"
echo "  • git-packages.extra.txt 裡若有需額外安裝的工具（如 qylock），clone 後依其說明再跑安裝腳本"
echo "  • 重新登入 / 重開機讓 services 與 session 生效"
