#!/bin/bash
set -e

echo "Setting up dotfiles for dev container..."

# Ensure the .config directory exists
mkdir -p ~/.config/tmux

# Create symlink for tmux config in .config directory
# This ensures the reload command in tmux.conf works correctly
ln -sf ~/dotfiles/tmux/tmux.conf ~/.config/tmux/tmux.conf

# Also create/update ~/.tmux.conf to source the config
# This ensures tmux finds the config on startup
echo "source-file ~/dotfiles/tmux/tmux.conf" > ~/.tmux.conf

echo "Tmux config installed successfully!"
echo "The config will be loaded automatically when you start tmux."
echo "To reload in an existing tmux session: prefix + r"
