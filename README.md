# Dotfiles

macOS development environment with a consistent Tokyo Night theme.

## Tools

- **Terminal:** WezTerm
- **Editor:** Neovim (AstroNvim)
- **Multiplexer:** Tmux
- **Shell:** Zsh + Oh My Posh
- **Window Manager:** AeroSpace
- **Status Bar:** Sketchybar
- **File Manager:** Yazi

## Setup

```bash
ln -s ~/.config/zshrc ~/.zshrc
```

## Dependencies

```bash
brew install neovim tmux eza fzf yazi jandedobbeleer/oh-my-posh/oh-my-posh
brew install --cask wezterm nikitabobko/tap/aerospace
brew tap FelixKratz/formulae && brew install sketchybar
```
