#!/usr/bin/env bash
#
# install_0c_ime.sh
# 靈犀注音（0c-ime）用自己的 fork 加上本機修正，不走官網自動更新的版本：
#   - clone fork 到 ~/0c-ime（已存在就不重 clone），確認 fork 與 upstream（0c-biggo/0c-ime）兩個 remote 都在
#   - 切到 BRANCH（預設 fcitx5-discard-on-im-switch：切換輸入法時丟掉未選字的組字）
#   - 加 --install：在 repo 裡跑 make upgrade PULL=0（測試建置、備份現有安裝、只重啟需要換版的引擎／外殼）
#
# 第一次安裝（還沒有 ~/.local/bin/0c-server、字典與模型）請先裝官網套件 https://0c.biggo.com，
# 之後再跑 --install 換成 fork 的版本。fcitx5 的設定（profile 用 zuin、AltTriggerKeys）由 fcitx5/ 這個 stow package 管。
#
# 環境變數：ZC_DIR（預設 ~/0c-ime）、BRANCH

set -euo pipefail

ZC_DIR="${ZC_DIR:-$HOME/0c-ime}"
BRANCH="${BRANCH:-fcitx5-discard-on-im-switch}"
FORK=git@github.com:Koios1143/0c-ime.git
UPSTREAM=https://github.com/0c-biggo/0c-ime.git
INSTALL=0

for a in "$@"; do
  case "$a" in
    --install) INSTALL=1 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "未知參數：$a" >&2; exit 1 ;;
  esac
done

if [[ ! -d "$ZC_DIR/.git" ]]; then
  echo "[clone] $ZC_DIR  <-  $FORK"
  git clone "$FORK" "$ZC_DIR"
fi

# 已有的 remote 不改名：用 URL 找，缺哪個才補（新 clone 時 origin 是 fork，補上 upstream）。
remote_for() { git -C "$ZC_DIR" remote -v | awk -v u="$1" '$2 == u { print $1; exit }'; }
[[ -n "$(remote_for "$FORK")" ]] || { git -C "$ZC_DIR" remote add fork "$FORK"; echo "[remote] fork = $FORK"; }
[[ -n "$(remote_for "$UPSTREAM")" ]] || { git -C "$ZC_DIR" remote add upstream "$UPSTREAM"; echo "[remote] upstream = $UPSTREAM"; }
fork_remote="$(remote_for "$FORK")"

git -C "$ZC_DIR" fetch --quiet "$fork_remote"
git -C "$ZC_DIR" fetch --quiet "$(remote_for "$UPSTREAM")"
if [[ "$(git -C "$ZC_DIR" branch --show-current)" != "$BRANCH" ]]; then
  if git -C "$ZC_DIR" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git -C "$ZC_DIR" switch "$BRANCH"
  else
    git -C "$ZC_DIR" switch -c "$BRANCH" --track "$fork_remote/$BRANCH"
  fi
fi
echo "[branch] $BRANCH ($(git -C "$ZC_DIR" rev-parse --short HEAD))"

if [[ "$INSTALL" -eq 1 ]]; then
  if [[ ! -x "$HOME/.local/bin/0c-server" ]]; then
    echo "還沒有安裝靈犀注音：先裝官網套件 https://0c.biggo.com，再跑 $0 --install" >&2
    exit 1
  fi
  make -C "$ZC_DIR" upgrade PULL=0
else
  echo "（未加 --install，只準備 repo；要換成這個版本請加 --install）"
fi
