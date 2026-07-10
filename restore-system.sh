#!/usr/bin/env bash
#
# restore-system.sh
# 把 dump.sh 存進 repo 的系統設定（system/ 底下的 /etc、/usr/share 快照）
# 逐檔跟「現行系統」比對後，經你確認才 sudo 寫回。
#
# 為什麼要逐檔確認：這些檔（mkinitcpio.conf、pacman.conf、SDDM 主題…）需要
# root 才能還原，盲目蓋回舊版可能開不了機或改壞系統。所以預設「互動模式」：
# 每個有差異的檔先給你看 diff，再問要不要套用。
#
# 用法：
#   ./restore-system.sh              互動：逐檔顯示 diff → 問 y/n
#   ./restore-system.sh --dry-run    只顯示差異，絕不寫入
#   ./restore-system.sh --yes        不問，直接套用所有有差異的檔（危險）
#
# 互動時每個檔可按：
#   y  套用這一個   n  略過這一個   a  以下全部套用   q  結束
#
# 旗標：--dry-run 只看不寫；--yes/-y 全部自動套用；-h/--help 顯示說明。
# 環境變數：DOTFILES_DIR（預設 ~/dotfiles）

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
SYSTEM_DIR="$DOTFILES_DIR/system"
DRY_RUN=0
ASSUME_YES=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --yes|-y)  ASSUME_YES=1 ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    -*) echo "未知旗標：$arg" >&2; exit 1 ;;
    *)  echo "未知參數：$arg" >&2; exit 1 ;;
  esac
done

if [[ ! -d "$SYSTEM_DIR" ]]; then
  echo "找不到 $SYSTEM_DIR，先跑 ./dump.sh 產生系統快照。" >&2
  exit 1
fi

# 收集 system/ 底下所有檔（用 NUL 分隔避免空白/特殊字元問題）
mapfile -d '' -t REPO_FILES < <(find "$SYSTEM_DIR" -type f -print0 | sort -z)
if [[ ${#REPO_FILES[@]} -eq 0 ]]; then
  echo "$SYSTEM_DIR 底下沒有檔案，無事可做。"
  exit 0
fi

# 先確認差異數量；有要寫入時才提前取得 sudo（--dry-run 不需要）
if [[ "$DRY_RUN" -eq 0 ]]; then
  echo "接下來可能會用 sudo 寫入系統檔，先驗證權限 ..."
  sudo -v
fi

n_same=0 n_apply=0 n_skip=0
declare -a APPLIED=()

apply_all=0
[[ "$ASSUME_YES" -eq 1 ]] && apply_all=1

for repo in "${REPO_FILES[@]}"; do
  rel="${repo#"$SYSTEM_DIR"/}"     # 例：etc/mkinitcpio.conf
  target="/$rel"                    # 例：/etc/mkinitcpio.conf

  # 完全相同 → 靜默跳過
  if [[ -f "$target" ]] && cmp -s "$repo" "$target"; then
    n_same=$((n_same + 1))
    continue
  fi

  echo
  echo "──────────────────────────────────────────────────────────"
  if [[ ! -e "$target" ]]; then
    echo "  ● $target  （系統上不存在，將新建）"
  else
    echo "  ● $target  （內容有差異）"
    # git diff --no-index：文字檔有彩色 diff，二進位檔自動印 'Binary files differ'
    git -c core.quotepath=false --no-pager diff --no-index --color=auto \
        --src-prefix="現行/" --dst-prefix="repo/" \
        "$target" "$repo" || true
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    n_skip=$((n_skip + 1))
    continue
  fi

  reply="y"
  if [[ "$apply_all" -eq 0 ]]; then
    printf "  套用？[y]是 / [n]否 / [a]以下全部 / [q]結束： "
    read -r reply || reply="q"
    case "$reply" in
      a|A) apply_all=1; reply="y" ;;
      q|Q) echo "  已結束。"; break ;;
    esac
  fi

  if [[ "$reply" == "y" || "$reply" == "Y" ]]; then
    # 保留現行檔的權限；若是新檔則預設 644
    if [[ -e "$target" ]]; then mode="$(stat -c %a "$target")"; else mode=644; fi
    sudo install -D -o root -g root -m "$mode" "$repo" "$target"
    echo "  ✓ 已還原 $target (mode $mode)"
    APPLIED+=("$target")
    n_apply=$((n_apply + 1))
  else
    echo "  – 略過 $target"
    n_skip=$((n_skip + 1))
  fi
done

echo
echo "──────────────────────────────────────────────────────────"
echo "完成：相同跳過 $n_same、還原 $n_apply、略過 $n_skip"

# 依還原到的檔案給後續動作提醒
if [[ ${#APPLIED[@]} -gt 0 ]]; then
  echo
  echo "後續動作提醒："
  for f in "${APPLIED[@]}"; do
    case "$f" in
      /etc/mkinitcpio.conf) echo "  • 改了 mkinitcpio.conf → 需重建 initramfs：sudo mkinitcpio -P" ;;
      /usr/share/sddm/themes/*) echo "  • 改了 SDDM 主題 → 重啟 sddm 生效：sudo systemctl restart sddm（會登出）" ;;
      /etc/locale.conf) echo "  • 改了 locale.conf → 重新登入或重開機生效" ;;
      /etc/environment) echo "  • 改了 environment → 重新登入生效" ;;
    esac
  done | sort -u
fi
