#!/usr/bin/env bash
# Install dotfiles on an rdev (or any Linux-like env) by symlinking the
# XDG-style subdirs in this repo into ~/.config and pointing zsh at them.
#
# Run by `rdev create` automatically after the repo is cloned to
# /home/coder/dotfiles. Safe to re-run; existing real files are moved aside
# to a timestamped backup dir, existing symlinks are replaced.
#
# Constraint reminder (go/rdev-dotfiles): no external network calls from here.

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config"

if [ "$DOTFILES_DIR" = "$CONFIG_DIR" ]; then
  echo "Dotfiles dir is already $CONFIG_DIR — nothing to symlink."
  exit 0
fi

mkdir -p "$CONFIG_DIR"

BACKUP_DIR=""
ensure_backup_dir() {
  if [ -z "$BACKUP_DIR" ]; then
    BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    echo "  (backups -> $BACKUP_DIR)"
  fi
}

link() {
  local src="$1" dest="$2"

  if [ ! -e "$src" ]; then
    echo "  skip $dest (source missing: $src)"
    return
  fi

  if [ -L "$dest" ]; then
    [ "$(readlink "$dest")" = "$src" ] && { echo "  ok   $dest"; return; }
    rm "$dest"
  elif [ -e "$dest" ]; then
    ensure_backup_dir
    mv "$dest" "$BACKUP_DIR/"
  fi

  ln -s "$src" "$dest"
  echo "  link $dest -> $src"
}

# XDG configs we want active on rdev.
# macOS-only dirs (aerospace, karabiner, kitty, sketchybar) are intentionally
# omitted; configstore / yarn / jgit / github-copilot are ephemeral state.
link "$DOTFILES_DIR/zsh"  "$CONFIG_DIR/zsh"
link "$DOTFILES_DIR/tmux" "$CONFIG_DIR/tmux"
link "$DOTFILES_DIR/nvim" "$CONFIG_DIR/nvim"
link "$DOTFILES_DIR/git"  "$CONFIG_DIR/git"
link "$DOTFILES_DIR/yazi" "$CONFIG_DIR/yazi"
link "$DOTFILES_DIR/bin"  "$CONFIG_DIR/bin"

# tmux < 3.1 doesn't read ~/.config/tmux/tmux.conf; mirror to ~/.tmux.conf so
# older tmux on the rdev still picks up the config.
link "$DOTFILES_DIR/tmux/tmux.conf" "$HOME/.tmux.conf"

# zsh on this setup keeps its rc files in ~/.config/zsh — that only works if
# ZDOTDIR is exported before zsh reads any rc file, which means ~/.zshenv.
ZSHENV="$HOME/.zshenv"
ZDOTDIR_LINE='export ZDOTDIR="$HOME/.config/zsh"'
if [ ! -e "$ZSHENV" ] || ! grep -qF "$ZDOTDIR_LINE" "$ZSHENV"; then
  printf '%s\n' "$ZDOTDIR_LINE" >> "$ZSHENV"
  echo "  set  ZDOTDIR in $ZSHENV"
fi

# Drop interactive bash into zsh automatically. We don't chsh because (a) the
# rdev user often can't and (b) bash is still useful for non-interactive use
# (rdev init scripts, build wrappers, etc.) — those won't have $PS1 set.
BASHRC="$HOME/.bashrc"
AUTO_ZSH_MARKER='# dotfiles-auto-zsh'
if [ ! -e "$BASHRC" ] || ! grep -qF "$AUTO_ZSH_MARKER" "$BASHRC"; then
  {
    printf '\n%s\n' "$AUTO_ZSH_MARKER"
    printf '%s\n' \
      'if [ -z "$ZSH_VERSION" ] && [ -n "$PS1" ] && command -v zsh >/dev/null 2>&1; then' \
      '  exec zsh' \
      'fi'
  } >> "$BASHRC"
  echo "  set  zsh auto-switch in $BASHRC"
fi

echo "dotfiles installed."
