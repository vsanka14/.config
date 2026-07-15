#!/bin/bash

case "$MODE" in
    resize)
        sketchybar --set mode_indicator drawing=on icon="󰩨" icon.color=0xffff757f
        ;;
    open)
        sketchybar --set mode_indicator drawing=on icon="󰀻" icon.color=0xff82aaff
        ;;
    *)
        sketchybar --set mode_indicator drawing=off
        ;;
esac
