#!/bin/bash

# Dotfiles install script
# Idempotent - safe to run multiple times

set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "This script is intended for macOS only."
    exit 1
fi

echo ""
echo "=========================================="
echo "  Dotfiles Setup"
echo "=========================================="
echo ""

# 1. Homebrew
info "Checking Homebrew..."
if ! command -v brew &> /dev/null; then
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    success "Homebrew installed"
else
    success "Homebrew already installed"
fi

# 2. Homebrew packages
info "Installing CLI tools..."
brew install neovim tmux eza fzf yazi fd lazygit \
    jandedobbeleer/oh-my-posh/oh-my-posh \
    zsh-autosuggestions zsh-syntax-highlighting \
    || true
success "CLI tools installed"

info "Installing Sketchybar..."
brew tap FelixKratz/formulae 2>/dev/null || true
brew install sketchybar || true
success "Sketchybar installed"

info "Installing GUI apps..."
brew install --cask wezterm nikitabobko/tap/aerospace karabiner-elements || true
success "GUI apps installed"

info "Installing font..."
brew install --cask font-jetbrains-mono-nerd-font || true
success "Font installed"

# 3. NVM and Node.js
info "Checking NVM..."
export NVM_DIR="$HOME/.nvm"
if [[ ! -d "$NVM_DIR" ]]; then
    info "Installing NVM..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash
    success "NVM installed"
else
    success "NVM already installed"
fi

# Load NVM and install Node
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
if command -v nvm &> /dev/null; then
    info "Installing Node.js LTS..."
    nvm install --lts || true
    success "Node.js installed"
fi

# 4. Bun (optional)
info "Checking Bun..."
if ! command -v bun &> /dev/null; then
    info "Installing Bun..."
    curl -fsSL https://bun.sh/install | bash
    success "Bun installed"
else
    success "Bun already installed"
fi

# 5. Symlinks and directories
info "Creating symlinks and directories..."
ln -sf ~/.config/zshrc ~/.zshrc
mkdir -p ~/.local/bin ~/code ~/documents/docs
success "Symlinks and directories created"

# 6. Fix ts symlink (in case it points to old path)
info "Fixing bin symlinks..."
if [[ -L ~/.config/bin/ts ]]; then
    rm ~/.config/bin/ts
fi
ln -sf ~/.config/scripts/tmux-session-switcher.sh ~/.config/bin/ts
success "Bin symlinks fixed"

# 7. Git config
info "Configuring git..."
git config --global core.excludesfile ~/.config/git/ignore
success "Git configured"

# 8. Neovim plugins
info "Installing Neovim plugins..."
nvim --headless "+Lazy! sync" +qa 2>/dev/null || true
success "Neovim plugins installed"

# 9. Yazi plugin
info "Installing Yazi git plugin..."
ya pkg add yazi-rs/plugins:git 2>/dev/null || true
success "Yazi plugin installed"

# 10. Start services
info "Starting services..."
brew services start sketchybar 2>/dev/null || true
open -a AeroSpace 2>/dev/null || true
success "Services started"

echo ""
echo "=========================================="
echo "  Setup Complete!"
echo "=========================================="
echo ""
echo "Manual steps required:"
echo "  1. Restart terminal or run: source ~/.zshrc"
echo "  2. Grant Karabiner permissions:"
echo "     System Settings → Privacy & Security → Input Monitoring"
echo "     System Settings → Privacy & Security → Accessibility"
echo "  3. Hide macOS menu bar:"
echo "     System Settings → Control Center → 'Automatically hide and show the menu bar' → Always"
echo ""
