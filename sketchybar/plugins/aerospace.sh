#!/bin/bash

# Colors
ACCENT_COLOR=0xff00ffff
FG_MUTED=0xff565f89
ITEM_BG_COLOR=0xff24283b

# Get focused workspace from aerospace
FOCUSED_WORKSPACE=$(aerospace list-workspaces --focused)

# Extract space number from item name (space.1 -> 1)
SPACE_NUM=${NAME#space.}

if [ "$SPACE_NUM" = "$FOCUSED_WORKSPACE" ]; then
    sketchybar --set $NAME \
        icon.color=$ACCENT_COLOR \
        background.drawing=on \
        background.color=$ITEM_BG_COLOR
else
    sketchybar --set $NAME \
        icon.color=$FG_MUTED \
        background.drawing=off
fi
