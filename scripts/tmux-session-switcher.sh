#!/bin/bash

# --- Subcommands: go / status ---
case "$1" in
    go)
        sessions=$(tmux list-sessions -F '#S' 2>/dev/null | sort)
        n="$2"
        [[ "$n" =~ ^[0-9]+$ ]] || exit 1
        target=$(echo "$sessions" | sed -n "${n}p")
        [[ -n "$target" ]] && tmux switch-client -t "$target"
        exit 0
        ;;
    status)
        sessions=$(tmux list-sessions -F '#S' 2>/dev/null | sort)
        current="$2"
        count=$(echo "$sessions" | grep -c .)
        if [[ "$count" -le 1 ]]; then
            echo ""
            exit 0
        fi
        parts=()
        for ((i = 1; i <= count; i++)); do
            name=$(echo "$sessions" | sed -n "${i}p")
            if [[ "$name" == "$current" ]]; then
                parts+=("#[fg=#7aa2f7]●")
            else
                parts+=("#[fg=#414868]●")
            fi
        done
        echo "${parts[*]} "
        exit 0
        ;;
    sessions)
        sessions=$(tmux list-sessions -F '#S' 2>/dev/null | sort)
        count=$(echo "$sessions" | grep -c .)
        [[ "$count" -eq 0 ]] && exit 0
        current=$(tmux display-message -p '#S')

        target=$(
            echo "$sessions" \
              | nl -ba -w1 -s $'\t' \
              | while IFS=$'\t' read -r pos name; do
                    if [[ "$name" == "$current" ]]; then
                        echo -e "\033[33m${pos}\033[0m\t\033[34m${name}\033[0m\t\033[32m●\033[0m"
                    else
                        echo -e "\033[33m${pos}\033[0m\t${name}\t"
                    fi
                done \
              | fzf --ansi \
                    --reverse \
                    --border=rounded \
                    --border-label=" sessions " \
                    --border-label-pos=3 \
                    --prompt="  " \
                    --pointer="▶" \
                    --padding=1 \
                    --color='bg:-1,gutter:-1' \
                    --delimiter='\t' --with-nth=1.. \
              | cut -f2
        )
        [[ -n "$target" ]] && tmux switch-client -t "$target"
        exit 0
        ;;
esac

# --- FZF session switcher (default) ---

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
    active_sessions=$(tmux list-sessions -F '#S' 2>/dev/null | sort)

    selected=$(
        {
            fd . "${SCAN_DIRS[@]}" --type=d --max-depth=1 --absolute-path
            printf '%s\n' "${EXTRA_DIRS[@]}"
        } | sort -u \
          | sed "s|^$HOME/||" \
          | while IFS= read -r dir; do
                name=$(basename "$dir" | tr . _)
                pos=$(echo "$active_sessions" | grep -nx "$name" | cut -d: -f1)
                if [[ -n "$pos" ]]; then
                    echo -e "0\033[32m●\033[0m \033[33m${pos}\033[0m\t$dir"
                else
                    echo -e "1   \t$dir"
                fi
            done \
          | sort -t' ' -k1,1 -k3,3 \
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
                --delimiter='\t' --with-nth=1.. \
          | sed 's/.*\t//'
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
