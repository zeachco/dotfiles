#!/bin/sh

# Get the currently focused aerospace workspace
WORKSPACE=$(aerospace list-workspaces --focused)

# Animate workspace change with tanh curve for smooth transition
sketchybar --animate tanh 15 \
  --set "$NAME" \
    label="$WORKSPACE" \
    background.color=0x60ffffff \
    label.y_offset=2 \
  --animate tanh 15 \
  --set "$NAME" \
    background.color=0x40ffffff \
    label.y_offset=0
