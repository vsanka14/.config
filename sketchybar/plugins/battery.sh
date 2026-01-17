#!/bin/bash

BATT_INFO=$(pmset -g batt)
PERCENTAGE=$(echo "$BATT_INFO" | grep -Eo "\d+%" | cut -d% -f1)
CHARGING=$(echo "$BATT_INFO" | grep -q "AC Power" && echo "true" || echo "false")

if [ "$PERCENTAGE" = "" ]; then
    exit 0
fi

# Select icon based on charging state and battery level
if [ "$CHARGING" = "true" ]; then
    ICON="󰂄"  # Charging icon
elif [ "$PERCENTAGE" -ge 100 ]; then
    ICON="󰁹"  # Full
elif [ "$PERCENTAGE" -ge 75 ]; then
    ICON="󰂀"  # High
elif [ "$PERCENTAGE" -ge 50 ]; then
    ICON="󰁾"  # Medium
elif [ "$PERCENTAGE" -ge 25 ]; then
    ICON="󰁼"  # Low
elif [ "$PERCENTAGE" -ge 10 ]; then
    ICON="󰁻"  # Critical low
else
    ICON="󰂃"  # Alert
fi

sketchybar --set $NAME icon="$ICON" label="${PERCENTAGE}%"
