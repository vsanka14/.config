#!/bin/bash

# Colors (Tokyo Night Moon) - different color per workspace
# 1=browser, 2=terminal, 3=misc
WORKSPACE_COLORS=(
    [1]=0xffc3e88d    # Browser - green
    [2]=0xffc099ff    # Terminal - purple/violet
    [3]=0xffffc777    # Misc - yellow/orange
)
FG_MUTED=0xff636da6               # Moon muted
ITEM_BG_COLOR=0xcc1e2030          # Moon background
ITEM_BG_CLEAR=0x001e2030          # Same color, fully transparent

# sketchybarrc passes the profile's pill height; 40 is the laptop value.
SPACE_BG_HEIGHT=${SPACE_BG_HEIGHT:-40}

# Bounce keyframes, played in order on one animation queue. Each column is:
# curve, duration, focused icon offset, neighbor icon offset, and focused
# background height relative to SPACE_BG_HEIGHT.
# Durations are 60 Hz-equivalent frame counts and track each leg's integer
# travel distance so small offsets keep moving instead of repeating frames.
# tanh launches (hop and rebound) start fast and ease out; sin legs ease in and
# out so landings stay soft. Neighbor offsets can add a ripple when the focused
# icon lands; keep them at 0 for no ripple.
BOUNCE_CURVES=(tanh sin tanh sin)
BOUNCE_DURATIONS=(7 9 4 3)
BOUNCE_FOCUSED=(8 -2 2 0)  # hop, dip, rebound, rest
BOUNCE_NEIGHBOR=(0 0 0 0)
# The pill pops in from BG_POP_START, overshoots during the hop, squashes when
# the icon lands, and springs back to full height. A pill that loses focus
# shrinks back to BG_POP_START while it fades out.
BG_POP_START=-22
BOUNCE_BG=(5 -10 3 0)       # overshoot, squash, spring, rest

# Workspace-change events already provide this value. Query Aerospace only for
# forced updates such as SketchyBar startup and reload.
FOCUSED_WORKSPACE=${FOCUSED_WORKSPACE:-$(aerospace list-workspaces --focused)}

# The focused pill restarts its pop from a small, opaque pill so the growth is
# visible (a fade-in hides it). All pills stay drawn; unfocused pills are
# transparent so they can fade instead of snapping off.
background_args=()
for i in 1 2 3; do
    background_args+=(--set "space.$i" background.drawing=on)
done
background_args+=(
    --set "space.$FOCUSED_WORKSPACE"
    "background.height=$((SPACE_BG_HEIGHT + BG_POP_START))"
    "background.color=$ITEM_BG_COLOR"
)

# Build one update so workspace items share a single, uninterrupted animation
# queue instead of racing across separate SketchyBar processes.
animation_args=()
for k in 0 1 2 3; do
    animation_args+=(--animate "${BOUNCE_CURVES[$k]}" "${BOUNCE_DURATIONS[$k]}")
    for i in 1 2 3; do
        if [ "$i" = "$FOCUSED_WORKSPACE" ]; then
            animation_args+=(
                --set "space.$i"
                "icon.y_offset=${BOUNCE_FOCUSED[$k]}"
                "background.height=$((SPACE_BG_HEIGHT + BOUNCE_BG[k]))"
            )
            if [ "$k" = 0 ]; then
                animation_args+=("icon.color=${WORKSPACE_COLORS[$i]}")
            fi
        elif [ "$i" = "$((FOCUSED_WORKSPACE - 1))" ] ||
            [ "$i" = "$((FOCUSED_WORKSPACE + 1))" ]; then
            animation_args+=(--set "space.$i" "icon.y_offset=${BOUNCE_NEIGHBOR[$k]}")
        elif [ "$k" = 0 ]; then
            animation_args+=(--set "space.$i" icon.y_offset=0)
        fi
        if [ "$k" = 0 ] && [ "$i" != "$FOCUSED_WORKSPACE" ]; then
            animation_args+=(
                "icon.color=$FG_MUTED"
                "background.color=$ITEM_BG_CLEAR"
                "background.height=$((SPACE_BG_HEIGHT + BG_POP_START))"
            )
        fi
    done
done

# Keep immediate state separate, then submit every animated property/keyframe
# together. A later animated write to the same property cancels its active queue.
sketchybar "${background_args[@]}"
sketchybar "${animation_args[@]}"
