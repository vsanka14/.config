#!/bin/bash

sketchybar \
    --set calendar label="$(date '+%a %b %d')" \
    --set "$NAME" label="$(date '+%I:%M %p')"
