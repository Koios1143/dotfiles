# dotfiles

Arch Linux + Hyprland 環境設定，用 GNU Stow 管理。

## 結構

```
dotfiles/
├── hypr/      .config/hypr/...        ← 每個 app 一個「套件」
├── waybar/    .config/waybar/...         套件內部鏡射 home 的路徑
├── wofi/      .config/wofi/...
├── ...
├── system/    etc/...                 ← /etc 設定備份（需 root 還原，非 symlink）
├── pkglist-native.txt                 ← 官方 repo 套件
├── pkglist-aur.txt                    ← AUR 套件
├── services-system.txt                ← 啟用的 systemd services
├── services-user.txt
├── fonts-local.txt
├── theme-settings.txt
├── migrate-to-stow.sh                 ← 首次把現有 config 搬進來
├── dump.sh                            ← 更新套件/服務/etc 快照
└── bootstrap.sh                       ← 新機器一鍵還原
```

Stow 的運作：在 `dotfiles/` 裡執行 `stow hypr`，會把 `hypr/.config/hypr`
symlink 到 `~/.config/hypr`。所以套件資料夾內的路徑要「相對 $HOME 鏡射」。

## 首次設定

```bash
mkdir -p ~/dotfiles
cd ~/dotfiles
git init
cp /path/to/.gitignore .          # 先放好 .gitignore 再開始，避免誤傳 secrets

# 把 script 放進來
cp /path/to/{migrate-to-stow.sh,dump.sh,bootstrap.sh} .
chmod +x *.sh

# 1) 先 dry-run，檢視會搬哪些東西、有沒有漏掉的 .config 資料夾
./migrate-to-stow.sh

# 2) 確認 PACKAGES 清單（編輯 migrate-to-stow.sh 頂端），再正式執行
./migrate-to-stow.sh --apply

# 3) 記錄套件、服務、/etc 等快照
./dump.sh

# 4) 上 git
git add -A
git commit -m "initial dotfiles"
git remote add origin <你的 github repo>
git push -u origin main
```

## 日常使用

config 已經是 symlink，所以照常編輯 `~/.config/hypr/hyprland.conf` 等檔案，
其實就是在改 repo 裡的檔。改完只要：

```bash
cd ~/dotfiles && git add -A && git commit -m "..." && git push
```

裝了新套件、開了新服務之後，重跑 `./dump.sh` 更新快照即可。

### 新增一個套件

```bash
# 把現有 config 加進 migrate-to-stow.sh 的 PACKAGES，再：
./migrate-to-stow.sh --apply
# 或手動：
mkdir -p ~/dotfiles/<pkg>/.config
mv ~/.config/<pkg> ~/dotfiles/<pkg>/.config/<pkg>
stow <pkg>
```

## 在新機器上還原

```bash
git clone <你的 repo> ~/dotfiles
cd ~/dotfiles
./bootstrap.sh                    # 裝套件 + stow
# 或一併啟用服務：
./bootstrap.sh --enable-services
```

之後手動處理 `system/`（/etc 設定）與字型，細節見 bootstrap 結尾提示。

## 注意

- **Secrets 不進 repo**：SSH/GPG key、token 等已被 `.gitignore` 排除；
  仍建議 push 前 `git status` 確認一次。
- **/etc 設定**需 root，採「備份+手動還原」而非 symlink。
- 新機器 stow 若遇到 `conflict`，表示該位置已有預設檔，備份或刪除後再 stow。
