# Dotfiles

Work dotfiles for development environment setup.

## Contents

- `nvim/` - Neovim configuration (AstroNvim-based)
- `wezterm/` - WezTerm terminal configuration
- `zshrc` - Zsh shell configuration
- `.gitconfig` - Git configuration
- `install.sh` - Installation script

## Installation

```bash
git clone git@github.com:vsankar_LinkedIn/dotfiles.git ~/.config
cd ~/.config
./install.sh
```

## Manual Symlinks

```bash
ln -s ~/.config/zshrc ~/.zshrc
ln -s ~/.config/.gitconfig ~/.gitconfig
```
