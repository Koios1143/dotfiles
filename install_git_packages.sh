#!/usr/bin/env bash
#
# install-git-packages.sh
# 安裝手動 git clone 的套件，來源有兩個清單：
#   git-packages.txt        ← dump.sh 自動掃描產生（會被覆蓋，勿手改）
#   git-packages.extra.txt  ← 手動維護（dump.sh 不會動），放掃描抓不到的東西
# 格式（兩檔相同）：<目標路徑，相對 $HOME>  <git URL>
#
# 已存在的目錄預設略過；加 --update 會對既有的做 git pull --ff-only。
#
# 環境變數：DOTFILES_DIR（預設 ~/dotfiles）

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
MANIFESTS=( "$DOTFILES_DIR/git-packages.txt" "$DOTFILES_DIR/git-packages.extra.txt" )
UPDATE=0

for a in "$@"; do
  case "$a" in
    --update) UPDATE=1 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "未知參數：$a" >&2; exit 1 ;;
  esac
done

install_one() {
  local dest="$1" url="$2"
  [[ -z "${dest:-}" || "${dest:0:1}" == "#" ]] && return 0
  [[ -z "${url:-}" ]] && { echo "[warn] 略過缺少 URL 的行：$dest"; return 0; }
  local target="$HOME/$dest"
  if [[ -d "$target/.git" ]]; then
    if [[ "$UPDATE" -eq 1 ]]; then
      echo "[pull]  $dest"
      git -C "$target" pull --ff-only || echo "        pull 失敗（本地可能有改動），略過"
    else
      echo "[skip]  $dest 已存在"
    fi
  else
    echo "[clone] $dest  <-  $url"
    mkdir -p "$(dirname "$target")"
    git clone --depth=1 "$url" "$target"
  fi
}

found=0
for mf in "${MANIFESTS[@]}"; do
  [[ -f "$mf" ]] || continue
  found=1
  echo "--- $(basename "$mf") ---"
  while read -r dest url _rest; do
    install_one "$dest" "$url"
  done < "$mf"
done

[[ "$found" -eq 0 ]] && { echo "找不到任何 git-packages 清單，略過。"; exit 0; }
echo "完成。"
