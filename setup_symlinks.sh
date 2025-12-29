#!/bin/bash

# Script to setup dotfiles symlinks
# This removes the original ~/.zshrc and creates a symlink to the dotfiles version

echo "Setting up dotfiles symlinks..."

# Remove the original .zshrc
if [ -f ~/.zshrc ]; then
    echo "Removing original ~/.zshrc"
    rm ~/.zshrc
else
    echo "No existing ~/.zshrc found"
fi

# Create symlink to dotfiles version
echo "Creating symlink: ~/.zshrc -> ~/.config/zshrc"
ln -s ~/.config/zshrc ~/.zshrc

# Verify the symlink was created
if [ -L ~/.zshrc ]; then
    echo "✅ Symlink created successfully"
    ls -la ~/.zshrc
else
    echo "❌ Failed to create symlink"
    exit 1
fi

echo "🎉 Dotfiles setup complete!"