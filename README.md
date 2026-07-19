# dotfiles

A Nier-style Arch Linux with Hyprland configured by GNU Stow.

> [!CAUTION]
> This is a personal project (for quick env recovery), not only serve for whole scene setting
> If you only want the cool tools with customized theme, you may refer to quickshell and hypr (and maybe also other files) for more details

## Project Structure

```
dotfiles/
├── hypr/      .config/hypr/...
├── quickshell/    .config/quickshell/...
├── yazi/      .config/yazi/...
├── ...
├── system/    etc/...                 ← /etc settings backup（need recovery with with root permission，instead of symlink）
├── pkglist-native.txt                 ← official packages
├── pkglist-aur.txt                    ← AUR packages
├── services-system.txt                ← activated systemd services
├── services-user.txt
├── fonts-local.txt
├── theme-settings.txt
├── migrate-to-stow.sh                 ← Add exists packages' configs into manage
├── dump.sh                            ← Update packages / services / etc snapshots
└── bootstrap.sh                       ← Recovery on new machine
```

> Some folder may be deprecated, e.g. waybar

> Note: Stow
> run `stwo hypr` under project root will create symlink to `~/.config/hypr`
> the path inside the package folder need to be related to $HOME

## About the theme

> I love quickshell lol

- status bar: quickshell
- app launcher: quickshell
- paste history: quickshell
- power menu: quickshell
- login menu and lockscreen: SDDM + quickshell (modified from qylock nier theme)
- file manager: dolphin (still in progress)

> TODO: Add some screenshots

### shortcuts

| keybind | functionality |
| ------- | ------------- |
| `SUPER` + `Q` | Open Terminal |
| `SUPER` + `G` | Next new window will be center, float, with window size 800x600 |
| `SUPER` + `C` | Close window |
| `SUPER` + `M` | Logout |
| `SUPER` + `L` | Lock system |
| `SUPER` + `E` | Open file manager |
| `SUPER` + `V` | Float window |
| `SUPER` + `R` | Open app launcher |
| `ALT` + `Space` | Open calculator |
| `SUPER` + `P` | Pseudo Window |
| `SUPER` + `J` | Toggle Split |
| `SUPER` + `F` | Fullscreen window (with margin and top-level panels) |
| `SUPER` + `SHIFT` + `F` | Fullscreen window |
| `SUPER` + `CTRL` + `F` | Fullscreen window but without hovering floating windows |
| `SUPER` + arrow | Change active window |
| `ALT` + `TAB` | Move focus to next window (cycle) |
| `ALT` + `SHIFT` + `TAB` | Move focus to previous window (cycle) |
| `SUPER` + number | Switch to workspace [1-10] |
| `SUPER` + `S` | Toggle to special workspace |
| `SUPER` + `SHIFT` + `S` | Move to special workspace magic |
| `SUPER` + mouse scroll | Scroll trough workspace |
| `SUPER` + Mouse Left | Drag window |
| `SUPER` + Mouse Right | Resize window |
| `SUPER` + `ALT` + Mouse Left | Resize window |
| `SUPER` + `+`/`-` | Resize floating window |
| `SUPER` + `SHIFT` + arrow | Resize window |
| `SUPER` + `CTRL` + arrow | Move active window |
| `XF86AudioRaiseVolume` | Raise volume 5% |
| `XF86AudioLowerVolume` | Lower volume 5% |
| `XF86AudioMute` | Mute audio output |
| `XF86AudioMicMute` | Mute microphone |
| `XF86MonBrightnessUp` | Increase Brightness 5% |
| `XF86MonBrightnessDown` | Lower Brightness 5% |
| `XF86AudioNext` | Play next |
| `XF86AudioPause` | Pause |
| `XF86AudioPlay` | Play |
| `XF86AudioPrev` | Play previous |
| `Print` | Screenshot selected area |
| `ALT` + `SHITF` + `F` | Screenshot selected are |
| `SUPER` + `Print` | Screenshot whole monitor |
| `ALT` + `Print` | Screenshot active window |
| `SUPER` + `Escape` | Open power menu |
| `SUPER` + `SHIFT` + `C` | Color picker |
| `SUPER` + `SHIFT` + `V` | Open clipboard history |
| `XF86Launch1` | Open Acer Predactor Scene (DAMX), Acer Predactor only |


## Quick Start (How to manage your own configuations)

```bash
mkdir -p ~/dotfiles
cd ~/dotfiles
git init
cp /path/to/.gitignore .

cp /path/to/{migrate-to-stow.sh,dump.sh,bootstrap.sh} .
chmod +x *.sh

# 1) dry-run first to check what will be process and if there's anything excluded
./migrate-to-stow.sh

# 2) After checking, run with apply flag to actually perform operations
./migrate-to-stow.sh --apply

# 3) dump will record the packages (from pacman and paru), services status, /etc snapshot...
./dump.sh

# 4) Then you can manage with git now
git add -A
git commit -m "initial dotfiles"
git remote add origin <你的 github repo>
git push -u origin main
```

## Daily Usages

config files are already symlinked, so directly edit files like `~/.config/hypr/hyprland.conf` actually  modified the files in the repo

After that, simple add and commit those modifications

```bash
cd ~/dotfiles && git add -A && git commit -m "..." && git push
```

If you installed (or uninstalled) some packages, or if you open (or close) some services, run `./dump.sh` can update the snapshot.

### Add new config files to managed by Stow

If you have some new packages that also have config files needed to be manage, run the following commands

```bash
# Add current config files into PACKAGES in migrate-to-stow.sh, then run the following command
./migrate-to-stow.sh --apply
# Or you may perform the operation manually with following commands
mkdir -p ~/dotfiles/<pkg>/.config
mv ~/.config/<pkg> ~/dotfiles/<pkg>/.config/<pkg>
stow <pkg>
```

## Recovery on new machine

```bash
git clone <Your repo> ~/dotfiles
cd ~/dotfiles
./bootstrap.sh # Install packages and stow
# Or also adjust the services' status
./bootstrap.sh --enable-services
```

As for the system configuration (such as /etc and fonts), you need to configure manually.

## Note

- On new machine if some conflicts occurs, that means the config file already exists, you need to backup or remove to stow again
- Some footnotes and comments are in Mandarin, I'll turn them into English in future
- The reason why I choose quickshell instead of wofi, rofi, waybar, ... is simply because quickshell provides maximum flexibility

## Acknowledgement

- [Hyprland](https://github.com/hyprwm/hyprland) and [quickshell](https://github.com/quickshell-mirror/quickshell) makes these modifications possible
- [Qylock](https://github.com/Darkkal44/qylock): The login menu, lockscreen and power menu are essentially modified from the theme `NieR: Automata`
- [NieR-Cursors](https://github.com/Beinsezii/NieR-Cursors): We also apply this cursor in this theme
- [Game UI Database](https://www.gameuidatabase.com/gameData.php?id=150&autoload=80452): Give me many inspiration about original NieR UI/UX design
- [Figma - Nier Automata HomePage](https://www.figma.com/community/file/1173051414761468493/nier-automata-homepage): Give me some materials
- [Game font library](https://www.gamefontlibrary.com/games/nier%3A-automata): Provide the NieR font

