# Migration Guide

Detailed guide for setting up these dotfiles on a new machine.

## Prerequisites

- macOS
- SSH key added to GitHub ([guide](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account))

## Quick Start

```bash
git clone git@github.com:vsanka14/.config.git ~/.config
cd ~/.config
./install.sh
```

## What the Install Script Does

1. Installs Homebrew (if not present)
2. Installs CLI tools: neovim, tmux, eza, fzf, yazi, fd, lazygit, oh-my-posh, zsh plugins
3. Installs Sketchybar (status bar)
4. Installs GUI apps: WezTerm, AeroSpace, Karabiner-Elements
5. Installs JetBrainsMono Nerd Font
6. Installs NVM and Node.js LTS
7. Installs Bun runtime
8. Creates symlinks (`~/.zshrc` → `~/.config/zshrc`)
9. Creates directories (`~/.local/bin`, `~/code`, `~/documents/docs`)
10. Configures git global ignore
11. Installs Neovim plugins via lazy.nvim
12. Installs Yazi git plugin
13. Starts Sketchybar and AeroSpace

## Manual Steps After Install

### 1. Restart Terminal

```bash
source ~/.zshrc
```

Or simply close and reopen your terminal.

### 2. Grant Karabiner Permissions

Karabiner needs accessibility permissions to remap keys:

1. Open **System Settings**
2. Go to **Privacy & Security → Input Monitoring**
3. Enable **Karabiner-Elements** and **karabiner_grabber**
4. Go to **Privacy & Security → Accessibility**
5. Enable **Karabiner-Elements** and **karabiner_grabber**

### 3. Hide macOS Menu Bar

To show only Sketchybar (and hide the default menu bar):

1. Open **System Settings**
2. Go to **Control Center**
3. Set **"Automatically hide and show the menu bar"** to **Always**

## Multi-Machine Setup (Work/Personal)

To maintain configs across multiple machines with minor differences:

1. Keep `main` branch as the shared base (pushed from work laptop)
2. Create a `personal` branch for personal machine customizations
3. Merge `main` into `personal` periodically to sync changes

```bash
# On personal machine, create branch for customizations
git checkout -b personal

# Make your changes (e.g., different workspaces in aerospace.toml)
git add .
git commit -m "Personal machine tweaks"
git push -u origin personal

# Later, to pull updates from main:
git fetch origin
git merge origin/main
```

## Troubleshooting

### Windows overlap Sketchybar

AeroSpace isn't leaving enough room at the top for Sketchybar.

**Fix:** Increase `outer.top` in `aerospace/aerospace.toml`:

```toml
[gaps]
outer.top = 40  # At least 32 (sketchybar height) + padding
```

Then reload: `aerospace reload-config` or press `ctrl+shift+r`.

### `ts` command not working

The symlink may point to an old user path from a different machine.

**Fix:**

```bash
rm ~/.config/bin/ts
ln -s ~/.config/scripts/tmux-session-switcher.sh ~/.config/bin/ts
```

### Git push fails with "could not read Username"

You're using HTTPS remote but credentials aren't configured.

**Fix:** Switch to SSH:

```bash
git remote set-url origin git@github.com:vsanka14/.config.git
```

Make sure your SSH key is added to GitHub at https://github.com/settings/keys

### AeroSpace not running

**Fix:**

```bash
open -a AeroSpace
```

To verify it's running:

```bash
pgrep -x AeroSpace && echo "Running" || echo "Not running"
```

### Sketchybar not showing

**Fix:**

```bash
brew services start sketchybar
```

Or reload config:

```bash
sketchybar --reload
```

### Neovim theme files not found (tmux/wezterm)

Tmux and WezTerm source theme files from the tokyonight.nvim plugin directory. These are created when Neovim plugins are installed.

**Fix:** Launch Neovim and wait for plugins to install:

```bash
nvim
# Wait for lazy.nvim to finish, then quit
```

### Oh My Posh prompt not showing correctly

Missing Nerd Font or font not set in terminal.

**Fix:**

1. Ensure font is installed: `brew install --cask font-jetbrains-mono-nerd-font`
2. In WezTerm, the font is already configured in `wezterm/wezterm.lua`
3. If using another terminal, set the font to "JetBrainsMono Nerd Font"
