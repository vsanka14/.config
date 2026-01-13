#!/bin/bash

DOTFILES_DIR="$HOME/dotfiles"
TMUX_CONFIG="$DOTFILES_DIR/tmux/tmux.conf"

echo "Setting up tmux config..."

# Create symlink to tmux config (tmux loads ~/.tmux.conf automatically)
if [ -f "$TMUX_CONFIG" ]; then
    ln -sf "$TMUX_CONFIG" "$HOME/.tmux.conf"
    echo "Symlinked $TMUX_CONFIG -> ~/.tmux.conf"
else
    echo "Warning: tmux config not found at $TMUX_CONFIG"
fi

echo "Done! Tmux will load the config automatically when it starts."
