#!/bin/sh

# ==============================================================================
# WORK MODE
# ==============================================================================

# Toggle work mode: Google Chrome as the default browser and Slack running.
# Off swaps the default back to Chromium and closes Slack.
# Usage: work [0|false|off]
work() {
  local enabled=true
  case "${1:-}" in
  0 | false | off) enabled=false ;;
  esac

  if [ ! -d /usr/share/omarchy ]; then
    echo "work: not implemented on this OS (Omarchy only for now)" >&2
    return 1
  fi

  # Interactive shells export BROWSER=omarchy-launch-browser, which makes
  # xdg-settings refuse; that launcher reads this default anyway.
  if [ "$enabled" = true ]; then
    env -u BROWSER xdg-settings set default-web-browser google-chrome.desktop || return 1
    pgrep -x slack >/dev/null || (setsid uwsm-app -- slack >/dev/null 2>&1 </dev/null &)
    echo "work: on (Google Chrome, Slack started)"
  else
    env -u BROWSER xdg-settings set default-web-browser chromium.desktop || return 1
    pkill -x slack
    echo "work: off (Chromium, Slack closed)"
  fi
}
