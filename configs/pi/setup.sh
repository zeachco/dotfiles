#!/usr/bin/env bash
# Ensure the pi packages declared in the stowed settings.json are downloaded.
#
# settings.json is the single source of truth for *which* packages pi loads:
#   configs/pi/.pi/agent/settings.json  ->  ~/.pi/agent/settings.json
# pi does NOT fetch user-level packages merely from that list — `pi install`
# performs the download. So a fresh machine needs one `pi install` per package
# before they load. This script runs `pi install` for every package declared in
# settings.json so that "clone dotfiles + run setup" always yields a working pi.
#
# `pi install` re-runs a full `npm install` even when the package is already
# present, so packages found under ~/.pi/agent/npm/node_modules are skipped.
# Delete that directory (or run `pi install <pkg>` by hand) to force a refresh.
set -uo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
settings="$script_dir/.pi/agent/settings.json"

if ! command -v pi >/dev/null 2>&1; then
  echo "pi not found; skipping pi package install"
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found; skipping pi package install"
  exit 0
fi
if [[ ! -f "$settings" ]]; then
  echo "no pi settings.json at $settings; skipping"
  exit 0
fi

echo "Ensuring pi packages from $settings ..."
mapfile -t packages < <(jq -r '.packages[]? | select(type=="string")' "$settings" 2>/dev/null)

if (( ${#packages[@]} == 0 )); then
  echo "no pi packages declared in settings.json"
  exit 0
fi

npm_root="${HOME}/.pi/agent/npm/node_modules"
status=0
for pkg in "${packages[@]}"; do
  [[ -n "$pkg" ]] || continue
  if [[ "$pkg" == npm:* && -d "$npm_root/${pkg#npm:}" ]]; then
    echo "present ${pkg}"
    continue
  fi
  pi install "$pkg" || status=1
done

if (( status == 0 )); then
  echo "pi packages ready"
fi
exit "$status"
