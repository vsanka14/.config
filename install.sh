#!/bin/bash
# install.sh - rdev dotfiles setup
# Installs latest Neovim, CLI tools, and configures shell for development
set -e

echo "=== rdev Dotfiles Setup ==="
echo ""

# Determine script directory (where dotfiles are cloned)
DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "Dotfiles directory: $DOTFILES_DIR"
echo ""

# Create local bin directory
mkdir -p ~/.local/bin

# -----------------------------------------------------------------------------
# 1. Install Neovim (latest stable via AppImage)
# -----------------------------------------------------------------------------
echo "[1/6] Installing Neovim..."
rm -rf ~/.local/nvim-appimage ~/.local/bin/nvim

NVIM_URL="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.appimage"
curl -fLo /tmp/nvim.appimage "$NVIM_URL" || { echo "Failed to download Neovim"; exit 1; }

# Verify download size (should be ~10MB+)
SIZE=$(stat -c%s /tmp/nvim.appimage 2>/dev/null || stat -f%z /tmp/nvim.appimage)
if [ "$SIZE" -lt 1000000 ]; then
    echo "Download failed - file too small ($SIZE bytes)"
    cat /tmp/nvim.appimage
    exit 1
fi

chmod +x /tmp/nvim.appimage
cd /tmp && ./nvim.appimage --appimage-extract > /dev/null 2>&1
mv /tmp/squashfs-root ~/.local/nvim-appimage
ln -sf ~/.local/nvim-appimage/usr/bin/nvim ~/.local/bin/nvim
rm /tmp/nvim.appimage
echo "  Neovim installed: $(~/.local/bin/nvim --version | head -1)"
echo ""

# -----------------------------------------------------------------------------
# 2. Install system packages via dnf
# -----------------------------------------------------------------------------
echo "[2/6] Installing system dependencies..."
# Try different package names for compatibility across distros
sudo dnf install -y git ripgrep zsh curl tar gzip || true
sudo dnf install -y fd-find || sudo dnf install -y fd || true
sudo dnf install -y util-linux-user || true
echo ""

# -----------------------------------------------------------------------------
# 3. Install user-local CLI tools (lazygit, glow, eza)
# -----------------------------------------------------------------------------
echo "[3/6] Installing CLI tools..."

# lazygit
if [ -x ~/.local/bin/lazygit ]; then
    echo "  lazygit already installed, skipping..."
else
    echo "  Installing lazygit..."
    LAZYGIT_VERSION=$(curl -s https://api.github.com/repos/jesseduffield/lazygit/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
    curl -Lo /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
    tar xzf /tmp/lazygit.tar.gz -C ~/.local/bin lazygit
    rm /tmp/lazygit.tar.gz
fi

# glow
if [ -x ~/.local/bin/glow ]; then
    echo "  glow already installed, skipping..."
else
    echo "  Installing glow..."
    GLOW_VERSION=$(curl -s https://api.github.com/repos/charmbracelet/glow/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
    curl -Lo /tmp/glow.tar.gz "https://github.com/charmbracelet/glow/releases/latest/download/glow_${GLOW_VERSION}_Linux_x86_64.tar.gz"
    tar xzf /tmp/glow.tar.gz -C ~/.local/bin glow
    rm /tmp/glow.tar.gz
fi

# eza
if [ -x ~/.local/bin/eza ]; then
    echo "  eza already installed, skipping..."
else
    echo "  Installing eza..."
    curl -Lo /tmp/eza.tar.gz "https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-gnu.tar.gz"
    tar xzf /tmp/eza.tar.gz -C ~/.local/bin
    rm /tmp/eza.tar.gz
fi

# opencode
if [ -x ~/.local/bin/opencode ]; then
    echo "  opencode already installed, skipping..."
else
    echo "  Installing opencode..."
    curl -fsSL https://opencode.ai/install | bash -s -- --dest ~/.local/bin
fi

# cursor cli
if command -v cursor &> /dev/null; then
    echo "  cursor already installed, skipping..."
else
    echo "  Installing cursor..."
    curl -fsSL https://cursor.com/install | bash
fi
echo ""

# -----------------------------------------------------------------------------
# 4. Install Node.js via nvm
# -----------------------------------------------------------------------------
echo "[4/6] Installing Node.js..."
if [ -d "$HOME/.nvm" ]; then
    echo "  nvm already installed, skipping..."
else
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
fi

# Load nvm for this session
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Install LTS Node.js if not already installed
if command -v node &> /dev/null; then
    echo "  Node.js already installed: $(node --version)"
else
    nvm install --lts
    echo "  Node.js installed: $(node --version)"
fi
echo ""

# -----------------------------------------------------------------------------
# 5. Install zsh plugins
# -----------------------------------------------------------------------------
echo "[5/6] Installing zsh plugins..."
mkdir -p ~/.local/share

if [ -d ~/.local/share/zsh-autosuggestions ]; then
    echo "  zsh-autosuggestions already installed, skipping..."
else
    git clone https://github.com/zsh-users/zsh-autosuggestions ~/.local/share/zsh-autosuggestions
fi

if [ -d ~/.local/share/zsh-syntax-highlighting ]; then
    echo "  zsh-syntax-highlighting already installed, skipping..."
else
    git clone https://github.com/zsh-users/zsh-syntax-highlighting ~/.local/share/zsh-syntax-highlighting
fi
echo ""

# -----------------------------------------------------------------------------
# 6. Setup shell configuration
# -----------------------------------------------------------------------------
echo "[6/6] Configuring shell..."

# Setup .zshrc to source our config
if [ -f ~/.zshrc ] && grep -q "source.*\.config/zshrc" ~/.zshrc; then
    echo "  .zshrc already configured, skipping..."
else
    echo "  Configuring .zshrc..."
    echo "source ~/.config/zshrc" > ~/.zshrc
fi

# Setup .bash_profile to auto-switch to zsh
if [ -f ~/.bash_profile ] && grep -q "exec zsh" ~/.bash_profile; then
    echo "  .bash_profile already configured, skipping..."
else
    echo "  Configuring .bash_profile to launch zsh..."
    echo "exec zsh" >> ~/.bash_profile
fi
echo ""

echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Start a new shell session (zsh will launch automatically)"
echo "  2. Open nvim - plugins will install automatically on first launch"
echo "  3. Run ':Copilot auth' in nvim to authenticate GitHub Copilot"
echo ""
