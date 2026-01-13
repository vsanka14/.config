#!/bin/bash

# Dotfiles installation script for dev containers
# This script should be run after cloning the dotfiles repo

set -e  # Exit on error

# Determine the dotfiles directory
# This assumes the script is in the root of the dotfiles repo
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "📦 Installing dotfiles from: $DOTFILES_DIR"

# ============================================
# TMUX Configuration
# ============================================
echo "🖥️  Setting up tmux configuration..."

# Create .config/tmux directory if it doesn't exist
mkdir -p ~/.config/tmux

# Remove existing tmux config if it's a file (not a symlink)
if [ -f ~/.config/tmux/tmux.conf ] && [ ! -L ~/.config/tmux/tmux.conf ]; then
    echo "  ⚠️  Backing up existing tmux.conf to tmux.conf.backup"
    mv ~/.config/tmux/tmux.conf ~/.config/tmux/tmux.conf.backup
fi

# Create symlink for tmux config
if [ -L ~/.config/tmux/tmux.conf ]; then
    echo "  ✓ Symlink already exists, removing old one"
    rm ~/.config/tmux/tmux.conf
fi

ln -s "$DOTFILES_DIR/tmux/tmux.conf" ~/.config/tmux/tmux.conf
echo "  ✓ Created symlink: ~/.config/tmux/tmux.conf -> $DOTFILES_DIR/tmux/tmux.conf"

# Also create a symlink at the traditional location for compatibility
if [ -f ~/.tmux.conf ] && [ ! -L ~/.tmux.conf ]; then
    echo "  ⚠️  Backing up existing ~/.tmux.conf to ~/.tmux.conf.backup"
    mv ~/.tmux.conf ~/.tmux.conf.backup
fi

if [ -L ~/.tmux.conf ]; then
    rm ~/.tmux.conf
fi

ln -s "$DOTFILES_DIR/tmux/tmux.conf" ~/.tmux.conf
echo "  ✓ Created symlink: ~/.tmux.conf -> $DOTFILES_DIR/tmux/tmux.conf"

# ============================================
# Add more configurations here as needed
# ============================================
# Example for other tools:
# echo "🔧 Setting up other configs..."
# ln -sf "$DOTFILES_DIR/nvim" ~/.config/nvim
# ln -sf "$DOTFILES_DIR/zsh/.zshrc" ~/.zshrc

echo ""
echo "✅ Dotfiles installation complete!"
echo ""
echo "📝 Next steps:"
echo "  - Start a new tmux session: tmux"
echo "  - Or reload tmux config: tmux source-file ~/.config/tmux/tmux.conf"
