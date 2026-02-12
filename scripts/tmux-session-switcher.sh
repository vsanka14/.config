#!/bin/bash

# Directories whose immediate subdirs are selectable projects
SCAN_DIRS=(
    "$HOME/code"
)

# Standalone directories to always include as options
EXTRA_DIRS=(
    "$HOME/.config"
    "$HOME/documents/docs"
)

if [[ $# -eq 1 ]]; then
    # Direct jump mode — argument is the target directory
    selected="$1"
else
    # Fuzzy picker mode — list subdirs + extras, pipe to fzf
    selected=$(
        {
            fd . "${SCAN_DIRS[@]}" --type=d --max-depth=1 --absolute-path
            printf '%s\n' "${EXTRA_DIRS[@]}"
        } | sort -u \
          | sed "s|^$HOME/||" \
          | fzf --height=40% --reverse --border --prompt="code> "
    )
    [[ -n "$selected" ]] && selected="$HOME/$selected"
fi

[[ -z "$selected" ]] && exit 0

# Session name = directory basename, dots replaced with underscores
selected_name=$(basename "$selected" | tr . _)

# Create session if it doesn't exist, then switch to it
if ! tmux has-session -t="$selected_name" 2>/dev/null; then
    tmux new-session -ds "$selected_name" -c "$selected"
fi

tmux switch-client -t "$selected_name"
