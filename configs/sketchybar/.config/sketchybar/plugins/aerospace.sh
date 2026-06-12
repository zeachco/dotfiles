#!/bin/sh

# Get the currently focused aerospace workspace
WORKSPACE=$(aerospace list-workspaces --focused)

sketchybar --set "$NAME" label="$WORKSPACE"
