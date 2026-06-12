#!/bin/bash

# SketchyBar Animations Configuration
# Animation curves: linear, quadratic, tanh, sin, exp, circ
# Duration is in frames at 60Hz (e.g., 30 = 0.5 seconds)

# Animation helper function
animate_item() {
  local item="$1"
  local curve="${2:-tanh}"
  local duration="${3:-20}"

  sketchybar --animate "$curve" "$duration" --set "$item" "${@:4}"
}

# Animate bar appearance on startup
animate_bar_startup() {
  sketchybar --animate sin 30 \
    --bar y_offset=10 \
    --animate sin 30 \
    --bar y_offset=0
}

# Smooth transition for workspace changes
animate_workspace_change() {
  sketchybar --animate tanh 15 \
    --set aerospace_workspace \
      background.color=0x60ffffff \
      label.y_offset=2 \
    --animate tanh 15 \
    --set aerospace_workspace \
      background.color=0x40ffffff \
      label.y_offset=0
}

# Pulse animation for volume changes
animate_volume_change() {
  sketchybar --animate exp 10 \
    --set volume \
      icon.y_offset=2 \
    --animate exp 10 \
    --set volume \
      icon.y_offset=0
}

# Smooth transition for app switching
animate_app_switch() {
  sketchybar --animate tanh 20 \
    --set front_app \
      label.color=0x80ffffff \
      label.y_offset=1 \
    --animate tanh 20 \
    --set front_app \
      label.color=0xffffffff \
      label.y_offset=0
}

# Battery alert animation (for low battery)
animate_battery_alert() {
  sketchybar --animate sin 15 \
    --set battery \
      icon.color=0xffff0000 \
      icon.y_offset=2 \
    --animate sin 15 \
    --set battery \
      icon.color=0xffffffff \
      icon.y_offset=0
}

# Smooth fade-in for new items
animate_item_fadein() {
  local item="$1"
  sketchybar --animate tanh 25 \
    --set "$item" \
      icon.color=0x00ffffff \
      label.color=0x00ffffff \
    --animate tanh 25 \
    --set "$item" \
      icon.color=0xffffffff \
      label.color=0xffffffff
}

# Export functions for use in plugins
export -f animate_item
export -f animate_workspace_change
export -f animate_volume_change
export -f animate_app_switch
export -f animate_battery_alert
export -f animate_item_fadein
