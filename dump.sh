#!/usr/bin/env bash
#
# dump.sh
# 把「不是 dotfile，但重現環境需要」的東西記錄進 repo：
#   - 套件清單（pacman native / AUR 分開）
#   - 啟用的 systemd services（system + user）
#   - /etc 底下的系統設定備份（需 root 還原）
#   - 自訂字型清單、GTK/icon/cursor 主題設定
#
# 隨時可重跑來更新這些紀錄；跑完記得 git add / commit。
#
# 環境變數：DOTFILES_DIR（預設 ~/dotfiles）

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
mkdir -p "$DOTFILES_DIR"
cd "$DOTFILES_DIR"

echo "寫入 $DOTFILES_DIR ..."

# --- 套件清單 -------------------------------------------------------------
# -Qqe：只列「主動安裝」的（排除被當依賴拉進來的）
# -n：官方 repo  /  -m：foreign（AUR、手動裝的）
pacman -Qqen > pkglist-native.txt
pacman -Qqem > pkglist-aur.txt
echo "  [pkg] pkglist-native.txt ($(wc -l < pkglist-native.txt) 個)"
echo "  [pkg] pkglist-aur.txt ($(wc -l < pkglist-aur.txt) 個)"

# --- 啟用的服務 -----------------------------------------------------------
systemctl list-unit-files --state=enabled --no-legend 2>/dev/null \
  | awk '{print $1}' > services-system.txt || true
systemctl --user list-unit-files --state=enabled --no-legend 2>/dev/null \
  | awk '{print $1}' > services-user.txt || true
echo "  [svc] services-system.txt / services-user.txt"

# --- /etc 系統設定備份 -----------------------------------------------------
# 鏡射絕對路徑放到 system/ 底下，例如 /etc/pacman.conf -> system/etc/pacman.conf
# 這些需要 root 才能還原，不能用 stow symlink。
mkdir -p system
backup_path() {
  local abs="$1"
  local dest="system/${abs#/}"
  if [[ -f "$abs" ]]; then
    install -Dm644 "$abs" "$dest" && echo "  [etc] $abs"
  elif [[ -d "$abs" ]]; then
    mkdir -p "$dest" && cp -a "$abs/." "$dest/" && echo "  [etc] $abs/"
  fi
}

ETC_TARGETS=(
  /etc/pacman.conf
  /etc/makepkg.conf
  /etc/mkinitcpio.conf
  /etc/locale.conf
  /etc/vconsole.conf
  /etc/environment
  /etc/sddm.conf
  /etc/sddm.conf.d
  /etc/pacman.d/hooks
)
for t in "${ETC_TARGETS[@]}"; do backup_path "$t"; done

# --- 字型清單 -------------------------------------------------------------
{ ls -1 "$HOME/.local/share/fonts" 2>/dev/null || true
  ls -1 "$HOME/.fonts" 2>/dev/null || true; } | sort -u > fonts-local.txt
echo "  [font] fonts-local.txt"

# --- 主題設定（若有 gsettings）--------------------------------------------
if command -v gsettings >/dev/null 2>&1; then
  {
    echo "gtk-theme:    $(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null || echo '?')"
    echo "icon-theme:   $(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null || echo '?')"
    echo "cursor-theme: $(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null || echo '?')"
    echo "font-name:    $(gsettings get org.gnome.desktop.interface font-name 2>/dev/null || echo '?')"
  } > theme-settings.txt
  echo "  [theme] theme-settings.txt"
fi

# --- 手動 git clone 的套件（oh-my-zsh、外掛、tpm…）--------------------------
# 掃描常見位置，把「目標路徑 + remote URL」寫進 git-packages.txt。
# 要加掃描位置就改下面兩個陣列。
GIT_REPO_DIRS=(            # 這些「本身」就是 git repo
  "$HOME/.oh-my-zsh"
  "$HOME/.fzf"
  "$HOME/.tmux/plugins/tpm"
)
GIT_REPO_PARENTS=(         # 這些目錄「底下」的子目錄若是 git repo 就記錄
  "$HOME/.oh-my-zsh/custom/plugins"
  "$HOME/.oh-my-zsh/custom/themes"
  "$HOME/.tmux/plugins"
)

emit_repo() {              # $1 = repo 絕對路徑
  local d="$1"
  [[ -d "$d/.git" ]] || return 0
  local url; url="$(git -C "$d" remote get-url origin 2>/dev/null || true)"
  [[ -z "$url" ]] && return 0
  printf '%s %s\n' "${d#"$HOME"/}" "$url"
}

{
  for d in "${GIT_REPO_DIRS[@]}"; do emit_repo "$d"; done
  shopt -s nullglob
  for parent in "${GIT_REPO_PARENTS[@]}"; do
    for child in "$parent"/*/; do emit_repo "${child%/}"; done
  done
  shopt -u nullglob
} | sort -u > git-packages.txt
echo "  [git] git-packages.txt ($(grep -cv '^[[:space:]]*$' git-packages.txt) 個)"

echo
echo "完成。記得：git add -A && git commit -m 'update system snapshot'"
