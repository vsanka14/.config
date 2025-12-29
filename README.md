# Dotfiles

My personal dotfiles configuration for development environment setup.

## Contents

- `.gitconfig` - Git configuration
- `zshrc` - Zsh shell configuration with colorized bordered path prompt
- `wezterm/` - WezTerm terminal configuration
- `nvim/` - Neovim configuration
- `setup_symlinks.sh` - Script to create symlinks for dotfiles
- Other dotfiles for shell and tool configurations

## Installation

To use these dotfiles on a new machine:

```bash
cd ~
git clone https://github.com/YOUR_USERNAME/dotfiles.git .config
cd .config

# Option 1: Use the setup script (recommended)
./setup_symlinks.sh

# Option 2: Create symlinks manually
ln -s ~/.config/zshrc ~/.zshrc
ln -s ~/.config/.gitconfig ~/.gitconfig
# Add other symlinks as needed
```

### Zsh Configuration Features

The `zshrc` includes:
- **Bordered path prompt**: Yellow path with black background and side borders
- **Color separation**: Cyan command prompt for clear visual distinction
- **Eza aliases**: Colorful file listings with icons
- **NVM and Bun**: Node.js version managers pre-configured

## Note

This repository is intended for personal use. Some configurations may be specific to my workflow and preferences.

## License

MIT
