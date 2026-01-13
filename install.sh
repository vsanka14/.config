#!/bin/bash

DOTFILES_DIR="$HOME/dotfiles"
CONFIG_DIR="$HOME/.config"
TMUX_SOURCE="$DOTFILES_DIR/tmux/tmux.conf"
TMUX_TARGET="$CONFIG_DIR/tmux/tmux.conf"

echo "Setting up tmux config..."

# Check source exists
if [ ! -f "$TMUX_SOURCE" ]; then
    echo "ERROR: Source not found: $TMUX_SOURCE"
    exit 1
fi

# Create target directory
mkdir -p "$CONFIG_DIR/tmux"

# Remove existing config
[ -e "$TMUX_TARGET" ] && rm -f "$TMUX_TARGET"

# Create symlink
ln -s "$TMUX_SOURCE" "$TMUX_TARGET"
echo "Symlink created: $TMUX_TARGET -> $TMUX_SOURCE"

# Reload tmux if running (optional)
if command -v tmux &> /dev/null && tmux list-sessions &> /dev/null; then
    if tmux source-file "$TMUX_TARGET" 2>&1; then
        echo "Tmux config reloaded"
    else
        echo "WARNING: Failed to reload tmux (non-fatal)"
    fi
fi

echo "Done!"
