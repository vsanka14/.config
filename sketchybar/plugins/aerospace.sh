#!/bin/bash

# Colors (Tokyo Night Moon) - different color per workspace
WORKSPACE_COLORS=(
    [1]=0xffc3e88d    # Browser/Chrome - green
    [2]=0xffc099ff    # Terminal - purple/violet
    [3]=0xffffc777    # Slack - yellow/orange (warm)
    [4]=0xff89ddff    # Outlook - light blue/cyan
    [5]=0xffff757f    # Misc - red/coral
)
FG_MUTED=0xff636da6               # Moon muted
ITEM_BG_COLOR=0xcc1e2030          # Moon background
BOUNCE_HEIGHT=5
BOUNCE_REBOUND=-2
BOUNCE_SETTLE=1
# Durations are 60 Hz-equivalent frame counts. They track each leg's integer
# travel distance so small offsets keep moving instead of repeating frames.
BOUNCE_UP_DURATION=5
BOUNCE_DOWN_DURATION=7
BOUNCE_SETTLE_DURATION=3
BOUNCE_FINISH_DURATION=2

# Workspace-change events already provide this value. Query Aerospace only for
# forced updates such as SketchyBar startup and reload.
FOCUSED_WORKSPACE=${FOCUSED_WORKSPACE:-$(aerospace list-workspaces --focused)}

background_args=()
animation_args=(--animate sin "$BOUNCE_UP_DURATION")

# Build one update so workspace items share a single, uninterrupted animation
# queue instead of racing across separate SketchyBar processes.
for i in 1 2 3 4 5; do
    if [ "$i" = "$FOCUSED_WORKSPACE" ]; then
        background_args+=(
            --set "space.$i"
            background.drawing=on
            "background.color=$ITEM_BG_COLOR"
        )
        animation_args+=(
            --set "space.$i"
            "icon.color=${WORKSPACE_COLORS[$i]}"
            "icon.y_offset=$BOUNCE_HEIGHT"
        )
    else
        background_args+=(--set "space.$i" background.drawing=off)
        animation_args+=(
            --set "space.$i"
            "icon.color=$FG_MUTED"
            icon.y_offset=0
        )
    fi
done

animation_args+=(
    --animate sin "$BOUNCE_DOWN_DURATION"
    --set "space.$FOCUSED_WORKSPACE" "icon.y_offset=$BOUNCE_REBOUND"
    --animate sin "$BOUNCE_SETTLE_DURATION"
    --set "space.$FOCUSED_WORKSPACE" "icon.y_offset=$BOUNCE_SETTLE"
    --animate sin "$BOUNCE_FINISH_DURATION"
    --set "space.$FOCUSED_WORKSPACE" icon.y_offset=0
)

# Keep immediate state separate, then submit every animated property/keyframe
# together. A later animated write to the same property cancels its active queue.
sketchybar "${background_args[@]}"
sketchybar "${animation_args[@]}"
