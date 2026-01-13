#!/bin/bash

# Install script for dotfiles in dev container
# This script is designed to be run from /dotfiles

set -e

DOTFILES_DIR="/dotfiles"
CONFIG_DIR="$HOME/.config"

echo "Setting up tmux configuration..."

# Create .config directory if it doesn't exist
mkdir -p "$CONFIG_DIR/tmux"

# Create symlink to tmux config
if [ -L "$CONFIG_DIR/tmux/tmux.conf" ] || [ -f "$CONFIG_DIR/tmux/tmux.conf" ]; then
    echo "Removing existing tmux config..."
    rm -f "$CONFIG_DIR/tmux/tmux.conf"
fi

echo "Creating symlink to tmux config..."
ln -s "$DOTFILES_DIR/tmux/tmux.conf" "$CONFIG_DIR/tmux/tmux.conf"

# Reload tmux config if tmux is running
if command -v tmux &> /dev/null && tmux list-sessions &> /dev/null; then
    echo "Reloading tmux configuration..."
    tmux source-file "$CONFIG_DIR/tmux/tmux.conf"
    echo "Tmux config reloaded!"
else
    echo "Tmux is not running. Config will be loaded on next tmux start."
fi

echo "Dotfiles installation complete!"
