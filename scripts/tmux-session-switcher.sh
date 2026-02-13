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
    selected="$1"
else
    active_sessions=$(tmux list-sessions -F '#S' 2>/dev/null)

    selected=$(
        {
            fd . "${SCAN_DIRS[@]}" --type=d --max-depth=1 --absolute-path
            printf '%s\n' "${EXTRA_DIRS[@]}"
        } | sort -u \
          | sed "s|^$HOME/||" \
          | while IFS= read -r dir; do
                name=$(basename "$dir" | tr . _)
                if echo "$active_sessions" | grep -qx "$name"; then
                    echo -e "0\033[32m●\033[0m $dir"
                else
                    echo "1  $dir"
                fi
            done \
          | sort -t' ' -k1,1 \
          | cut -c2- \
          | fzf --ansi \
                --reverse \
                --border=rounded \
                --border-label=" switch " \
                --border-label-pos=3 \
                --prompt="  " \
                --pointer="▶" \
                --padding=1 \
                --color='bg:-1,gutter:-1' \
          | sed 's/^. //'
    )
    [[ -n "$selected" ]] && selected="$HOME/$selected"
fi

[[ -z "$selected" ]] && exit 1

# Session name = directory basename, dots replaced with underscores
selected_name=$(basename "$selected" | tr . _)

# Create session if it doesn't exist, then switch to it
if ! tmux has-session -t="$selected_name" 2>/dev/null; then
    tmux new-session -ds "$selected_name" -c "$selected"
fi

if [[ -n "$TMUX" ]]; then
    tmux switch-client -t "$selected_name"
else
    exec tmux attach-session -t "$selected_name"
fi
