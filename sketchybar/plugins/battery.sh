#!/bin/bash

# Colors (Tokyo Night Moon)
COLOR_TEAL=0xff4fd6be     # Full (>75%) - darker green/teal
COLOR_GREEN=0xffc3e88d    # Good (50-75%)
COLOR_YELLOW=0xffffc777   # Medium (25-50%)
COLOR_RED=0xffff757f      # Low (<25%)
COLOR_CYAN=0xff86e1fc     # Charging

BATT_INFO=$(pmset -g batt)
PERCENTAGE=$(echo "$BATT_INFO" | grep -Eo "\d+%" | cut -d% -f1)
CHARGING=$(echo "$BATT_INFO" | grep -q "AC Power" && echo "true" || echo "false")

if [ "$PERCENTAGE" = "" ]; then
    exit 0
fi

# Select icon and color based on charging state and battery level
if [ "$CHARGING" = "true" ]; then
    ICON="󰂄"
    COLOR=$COLOR_CYAN
elif [ "$PERCENTAGE" -ge 100 ]; then
    ICON="󰁹"
    COLOR=$COLOR_TEAL
elif [ "$PERCENTAGE" -ge 75 ]; then
    ICON="󰂀"
    COLOR=$COLOR_TEAL
elif [ "$PERCENTAGE" -ge 50 ]; then
    ICON="󰁾"
    COLOR=$COLOR_GREEN
elif [ "$PERCENTAGE" -ge 25 ]; then
    ICON="󰁼"
    COLOR=$COLOR_YELLOW
elif [ "$PERCENTAGE" -ge 10 ]; then
    ICON="󰁻"
    COLOR=$COLOR_RED
else
    ICON="󰂃"
    COLOR=$COLOR_RED
fi

sketchybar --set $NAME icon="$ICON" icon.color=$COLOR label="${PERCENTAGE}%"
