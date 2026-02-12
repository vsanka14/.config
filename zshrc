# Add local bin to PATH (for user-installed binaries like nvim, lazygit, etc.)
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.config/bin:$PATH"

# Increase Node.js memory limit for large TypeScript projects
export NODE_OPTIONS="--max-old-space-size=8192"

# Enable vi mode in zsh
bindkey -v

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

# Cool file and directory colors
export LS_COLORS='di=1;34:ln=1;36:so=1;35:pi=1;33:ex=1;32:bd=1;33:cd=1;33:*.tar=1;31:*.tgz=1;31:*.zip=1;31:*.gz=1;31:*.bz2=1;31:*.rar=1;31:*.jar=1;31:*.jpg=1;35:*.jpeg=1;35:*.gif=1;35:*.bmp=1;35:*.png=1;35:*.svg=1;35:*.mov=1;35:*.mpg=1;35:*.mkv=1;35:*.webm=1;35:*.avi=1;35:*.aac=1;36:*.mp3=1;36:*.flac=1;36:*.ogg=1;36:*.js=1;33:*.jsx=1;33:*.ts=1;33:*.tsx=1;33:*.json=1;33:*.py=1;32:*.rb=1;32:*.go=1;32:*.rs=1;32:*.sh=1;32:*.md=1;37:*.txt=1;37'

export LSCOLORS='ExGxFxdaCxDaDahbadacec'

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

# Oh My Posh prompt (tonybaloney theme - customized)
eval "$(oh-my-posh init zsh --config ~/.config/ohmyposh-theme.json)"

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
