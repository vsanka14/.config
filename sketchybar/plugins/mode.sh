#!/bin/bash

if [ "$MODE" = "resize" ]; then
    sketchybar --set mode_indicator drawing=on
else
    sketchybar --set mode_indicator drawing=off
fi
