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
# paru / paru-debug 是 AUR helper 本身，重現環境時另外裝，這裡排除掉
pacman -Qqem | grep -vxE 'paru(-debug)?' > pkglist-aur.txt
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

# --- /usr/share 系統資料備份（主題等，需 root 還原）------------------------
# 跟 /etc 同樣是「複製快照」，但 /usr/share 底下常是整個目錄，可能夾帶
# .git / *.bak / demo.gif 這類不該進 repo 的雜物，所以複製後再 find 剪掉。
# 這些登入前就以 root 執行（SDDM / Plymouth），沒有 ~/.local/share 等價位置，
# 只能走快照路線；有使用者層等價的（icon/主題/.desktop）請改放 ~ 底下用 stow。
backup_share() {
  local abs="$1"
  local dest="system/${abs#/}"
  if [[ -f "$abs" ]]; then
    install -Dm644 "$abs" "$dest" && echo "  [usr] $abs"
  elif [[ -d "$abs" ]]; then
    rm -rf "$dest"
    mkdir -p "$(dirname "$dest")"
    cp -a "$abs" "$dest"
    # 剪掉巢狀 git repo、備份檔、示範動畫等不需要進 repo 的東西
    find "$dest" -depth \( -name .git -o -name '*.bak' -o -name demo.gif \) \
      -exec rm -rf {} + 2>/dev/null || true
    echo "  [usr] $abs/"
  fi
}

SHARE_TARGETS=(
  /usr/share/sddm/themes/nier-automata
  # 之後要納管再取消註解 / 新增：
  # /usr/share/wayland-sessions/hyprland-old.desktop
  # /usr/share/plymouth/themes/nier   # 129M git repo，建議推自己的 remote 用 git-packages.txt 而非快照
)
for t in "${SHARE_TARGETS[@]}"; do backup_share "$t"; done

# --- 自訂字型檔 -----------------------------------------------------------
# NieR 等手動放進去的字型不屬於任何套件，重灌時裝不回來，所以把「檔案本身」
# 納管。走 stow：檔案放在 fonts/.local/share/fonts/，bootstrap 會 symlink 回
# ~/.local/share/fonts。
# 只複製「真實檔案」；已被 stow 成 symlink 的（代表已在 repo 內）會被 -type f
# 過濾掉，不會自我覆蓋。
FONT_PKG="fonts/.local/share/fonts"
mkdir -p "$FONT_PKG"
for src in "$HOME/.local/share/fonts" "$HOME/.fonts"; do
  [[ -d "$src" ]] || continue
  find "$src" -maxdepth 1 -type f \
    \( -iname '*.otf' -o -iname '*.ttf' -o -iname '*.ttc' -o -iname '*.pcf' -o -iname '*.pcf.gz' \) -print0 \
    | while IFS= read -r -d '' f; do install -Dm644 "$f" "$FONT_PKG/$(basename "$f")"; done
done
# 同時留一份人可讀的清單方便檢視
ls -1 "$FONT_PKG" 2>/dev/null | sort -u > fonts-local.txt
echo "  [font] fonts/ ($(ls -1 "$FONT_PKG" 2>/dev/null | wc -l) 個字型檔) + fonts-local.txt"

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
# LC_ALL=C：用「位元組順序」排序，空白(0x20) < 斜線(0x2f)，
# 所以像 ".oh-my-zsh <url>" 一定排在其子目錄 ".oh-my-zsh/custom/... <url>" 前面
# ——父 repo 先 clone，子目錄（外掛 / 主題）才有地方放，還原順序才正確。
} | LC_ALL=C sort -u > git-packages.txt
echo "  [git] git-packages.txt ($(grep -cv '^[[:space:]]*$' git-packages.txt) 個)"

echo
echo "完成。記得：git add -A && git commit -m 'update system snapshot'"
