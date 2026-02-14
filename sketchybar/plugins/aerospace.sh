#!/bin/bash

# Colors (Tokyo Night Moon) - different color per workspace
# 1=browser, 2=terminal, 3=misc
declare -A WORKSPACE_COLORS=(
    [1]=0xffc3e88d    # Browser - green
    [2]=0xffc099ff    # Terminal - purple/violet
    [3]=0xffffc777    # Misc - yellow/orange
)
FG_MUTED=0xff636da6               # Moon muted
ITEM_BG_COLOR=0xcc1e2030          # Moon background

# Get focused workspace from aerospace
FOCUSED_WORKSPACE=$(aerospace list-workspaces --focused)

# Update all spaces based on current focus
# Background changes are instant (before --animate), icon changes are animated
for i in 1 2 3; do
    if [ "$i" = "$FOCUSED_WORKSPACE" ]; then
        # Focused space: instant background, animate icon bounce
        sketchybar --set space.$i \
            icon.y_offset=3 \
            background.drawing=on \
            background.color=$ITEM_BG_COLOR \
            --animate tanh 20 --set space.$i \
            icon.color=${WORKSPACE_COLORS[$i]} \
            icon.y_offset=0
    else
        # Non-focused: instant background off, animate icon
        sketchybar --set space.$i \
            background.drawing=off \
            --animate tanh 15 --set space.$i \
            icon.color=$FG_MUTED \
            icon.y_offset=0
    fi
done
