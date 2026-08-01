#!/bin/bash

detect_profile() {
    local monitors
    monitors=$(aerospace list-monitors --format '%{monitor-name}' 2>/dev/null) || return 1

    if printf '%s\n' "$monitors" | grep -Fxq "DELL S2725QC"; then
        printf 'external\n'
    else
        printf 'laptop\n'
    fi
}

if [ "$1" = "--profile" ]; then
    detect_profile
    exit
fi

PROFILE=$(detect_profile) || exit 0
STATE_FILE="/tmp/sketchybar-display-profile-${UID}"
PREVIOUS_PROFILE=$(cat "$STATE_FILE" 2>/dev/null)

if [ "$PROFILE" != "$PREVIOUS_PROFILE" ]; then
    printf '%s\n' "$PROFILE" > "$STATE_FILE"
    sketchybar --reload
fi
