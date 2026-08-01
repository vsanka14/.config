#!/bin/bash

if [ "$SENDER" = "front_app_switched" ] && [ -n "$INFO" ]; then
    APP_NAME=$INFO
else
    APP_NAME=$(aerospace list-windows --focused --format '%{app-name}' 2>/dev/null)
fi

if [ -z "$APP_NAME" ]; then
    sketchybar --set "$NAME" drawing=off
    exit 0
fi

sketchybar --set "$NAME" \
    drawing=on \
    label="$APP_NAME" \
    "icon.background.image=app.$APP_NAME"
