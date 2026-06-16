#!/bin/sh

# Bluetooth status and device selector
# Uses blueutil (install via: brew install blueutil)

update_bluetooth() {
  # Check if bluetooth is powered on
  if command -v blueutil >/dev/null 2>&1; then
    POWERED=$(blueutil --power)

    if [ "$POWERED" = "1" ]; then
      # Get connected devices
      CONNECTED_COUNT=$(blueutil --connected | grep -c "address:")

      if [ "$CONNECTED_COUNT" -gt 0 ]; then
        ICON="󰂯"  # Bluetooth connected icon
        LABEL="$CONNECTED_COUNT"
      else
        ICON="󰂯"  # Bluetooth on but no devices
        LABEL=""
      fi
      COLOR=0xff8be9fd  # Dracula cyan
    else
      ICON="󰂲"  # Bluetooth off icon
      LABEL=""
      COLOR=0xff6272a4  # Dracula comment (gray)
    fi
  else
    ICON="󰂲"
    LABEL="?"
    COLOR=0xffff5555  # Dracula red (error)
  fi

  sketchybar --set "$NAME" \
    icon="$ICON" \
    label="$LABEL" \
    icon.color="$COLOR"
}

# Handle click to show bluetooth device menu
bluetooth_click() {
  if command -v blueutil >/dev/null 2>&1; then
    # Get list of paired devices
    DEVICES=$(blueutil --paired --format json 2>/dev/null | \
      python3 -c "
import sys, json
try:
    devices = json.load(sys.stdin)
    for d in devices:
        name = d.get('name', 'Unknown')
        addr = d.get('address', '')
        connected = '✓' if d.get('connected', False) else ' '
        print(f'{connected} {name}|{addr}')
except:
    pass
" | head -10)

    if [ -n "$DEVICES" ]; then
      # Create menu with choose
      SELECTED=$(echo "$DEVICES" | \
        awk -F'|' '{print $1}' | \
        choose -m "Select Bluetooth Device:")

      if [ -n "$SELECTED" ]; then
        # Extract address from original line
        ADDR=$(echo "$DEVICES" | grep -F "$SELECTED" | awk -F'|' '{print $2}')

        if [ -n "$ADDR" ]; then
          # Check if already connected
          if echo "$SELECTED" | grep -q "^✓"; then
            # Disconnect
            blueutil --disconnect "$ADDR"
          else
            # Connect
            blueutil --connect "$ADDR"
          fi
          # Update the display
          sleep 0.5
          update_bluetooth
        fi
      fi
    else
      # No devices found, open System Settings
      open "x-apple.systempreferences:com.apple.BluetoothSettings"
    fi
  fi
}

case "$SENDER" in
  "routine"|"forced")
    update_bluetooth
    ;;
  "mouse.clicked")
    bluetooth_click
    ;;
esac
