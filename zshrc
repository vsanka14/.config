# Add local bin to PATH (for user-installed binaries like nvim, lazygit, etc.)
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.config/bin:$PATH"

# Increase Node.js memory limit for large TypeScript projects
export NODE_OPTIONS="--max-old-space-size=8192"

# Enable vim mode for command line editing
set -o vi

# Change cursor shape based on vi mode
# Beam cursor (|) for insert mode, block cursor (█) for normal mode
function zle-keymap-select {
  if [[ ${KEYMAP} == vicmd ]] || [[ $1 = 'block' ]]; then
    echo -ne '\e[1 q'  # Block cursor for normal mode
  elif [[ ${KEYMAP} == main ]] || [[ ${KEYMAP} == viins ]] || [[ ${KEYMAP} = '' ]] || [[ $1 = 'beam' ]]; then
    echo -ne '\e[5 q'  # Beam cursor for insert mode
  fi
}
zle -N zle-keymap-select

# Start with beam cursor on new prompt
function zle-line-init {
  echo -ne "\e[5 q"  # Beam cursor
}
zle -N zle-line-init

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

# Set terminal title when not in tmux (for WezTerm tab detection)
# Works with tmux.conf set-titles to display session name in tabs
precmd() {
  if [[ -z "$TMUX" ]]; then
    print -Pn "\e]0;%~\a"  # Set title to current directory
  fi
}

# Set terminal title before command execution (for rdev ssh detection)
preexec() {
  # Check if this is an rdev ssh command
  if [[ "$1" =~ ^rdev[[:space:]]+ssh[[:space:]]+([^[:space:]]+) ]]; then
    local rdev_name="${match[1]}"
    # Set title in format that wezterm will recognize
    print -Pn "\e]0;[rdev: $rdev_name]\a"
  fi
}

# Zsh plugins (works on both macOS and Linux)
for plugin_dir in /opt/homebrew/share ~/.local/share; do
  [ -f "$plugin_dir/zsh-autosuggestions/zsh-autosuggestions.zsh" ] && source "$plugin_dir/zsh-autosuggestions/zsh-autosuggestions.zsh"
  [ -f "$plugin_dir/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ] && source "$plugin_dir/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
done
