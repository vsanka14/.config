#!/usr/bin/env bash
# Apply tmux configuration on an rdev (or any *nix env) by symlinking
# tmux.conf into both XDG and home-dir locations. tmux <3.1 only checks
# ~/.tmux.conf; 3.1+ also checks ~/.config/tmux/tmux.conf — covering both
# means whichever version the rdev ships with finds it.
#
# Everything else in this repo is macOS-only or managed locally — the rdev
# doesn't need it. Run automatically by `rdev create` per go/rdev-dotfiles.

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMUX_CONF="$DOTFILES_DIR/tmux/tmux.conf"

mkdir -p "$HOME/.config/tmux"
ln -sfn "$TMUX_CONF" "$HOME/.tmux.conf"
ln -sfn "$TMUX_CONF" "$HOME/.config/tmux/tmux.conf"

echo "tmux config linked."
