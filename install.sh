#!/bin/bash

DOTFILES_DIR="$HOME/dotfiles"
TMUX_SOURCE="$DOTFILES_DIR/tmux/tmux.conf"

echo "Setting up tmux config..."

tmux source-file "$TMUX_SOURCE"

echo "Done!"
