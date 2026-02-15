# Add local bin to PATH (for user-installed binaries like nvim, lazygit, etc.)
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.config/bin:$PATH"

# Increase Node.js memory limit for large TypeScript projects
export NODE_OPTIONS="--max-old-space-size=8192"

# Enable vi mode in zsh
bindkey -v
export KEYTIMEOUT=1
# Fix backspace not working after re-entering insert mode from normal mode
bindkey -M viins '^?' backward-delete-char

# Vi mode cursor shape indicator
# Block cursor for normal mode, beam cursor for insert mode
function zle-keymap-select {
  if [[ $KEYMAP == vicmd ]] || [[ $1 == 'block' ]]; then
    echo -ne '\e[2 q'  # block cursor
  elif [[ $KEYMAP == main ]] || [[ $KEYMAP == viins ]] || [[ $1 == 'beam' ]]; then
    echo -ne '\e[6 q'  # beam cursor
  fi
}
zle -N zle-keymap-select

function zle-line-init {
  echo -ne '\e[6 q'  # beam cursor on new prompt
}
zle -N zle-line-init

# Set nvim as the default editor
export EDITOR='nvim'
export VISUAL='nvim'

# Enable edit-command-line widget
autoload -Uz edit-command-line
zle -N edit-command-line

# Bind Ctrl+X Ctrl+E to edit command in nvim (standard emacs binding)
bindkey '^X^E' edit-command-line

# Bind v in vi command mode to edit command in nvim (vi-style)
bindkey -M vicmd 'v' edit-command-line

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# Eza aliases for colorful file listings with icons (fallback to regular ls)
if command -v eza &> /dev/null; then
  alias ls='eza --icons --color=always'
  alias ll='eza -lh --icons --color=always --git'
  alias la='eza -lah --icons --color=always --git'
  alias lt='eza --tree --level=2 --icons --color=always'
  alias tree='eza --tree --icons --color=always'
else
  alias ll='ls -lh --color=auto'
  alias la='ls -lah --color=auto'
fi

# Oh My Posh prompt (tonybaloney theme - customized for tokyonight)
eval "$(oh-my-posh init zsh --config ~/.config/ohmyposh-theme.json)"

# Tokyo Night fzf theme (from tokyonight.nvim extras)
[ -f ~/.local/share/nvim/lazy/tokyonight.nvim/extras/fzf/tokyonight_night.sh ] && \
  source ~/.local/share/nvim/lazy/tokyonight.nvim/extras/fzf/tokyonight_night.sh

# Zsh plugins (works on both macOS and Linux)
for plugin_dir in /opt/homebrew/share ~/.local/share; do
  [ -f "$plugin_dir/zsh-autosuggestions/zsh-autosuggestions.zsh" ] && source "$plugin_dir/zsh-autosuggestions/zsh-autosuggestions.zsh"
  [ -f "$plugin_dir/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ] && source "$plugin_dir/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
done

## Yazi config
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	command yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd"
	rm -f -- "$tmp"
}
