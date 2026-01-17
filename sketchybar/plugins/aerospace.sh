#!/bin/bash

# Colors (Tokyo Night Moon) - different color per workspace
declare -A WORKSPACE_COLORS=(
    [1]=0xffc3e88d    # Browser/Chrome - green
    [2]=0xffc099ff    # Terminal - purple/violet
    [3]=0xffffc777    # Slack - yellow/orange (warm)
    [4]=0xff89ddff    # Outlook - light blue/cyan
    [5]=0xffff757f    # Misc - red/coral
)
FG_MUTED=0xff636da6               # Moon muted
ITEM_BG_COLOR=0xcc1e2030          # Moon background

# Get focused workspace from aerospace
FOCUSED_WORKSPACE=$(aerospace list-workspaces --focused)

# Extract space number from item name (space.1 -> 1)
SPACE_NUM=${NAME#space.}

if [ "$SPACE_NUM" = "$FOCUSED_WORKSPACE" ]; then
    # Pop up instantly, then animate back down (bounce effect)
    sketchybar --set $NAME icon.y_offset=3 \
        --animate tanh 20 --set $NAME \
        icon.color=${WORKSPACE_COLORS[$SPACE_NUM]} \
        icon.y_offset=0 \
        background.drawing=on \
        background.color=$ITEM_BG_COLOR
else
    sketchybar --animate tanh 15 --set $NAME \
        icon.color=$FG_MUTED \
        icon.y_offset=0 \
        background.drawing=off
fi
