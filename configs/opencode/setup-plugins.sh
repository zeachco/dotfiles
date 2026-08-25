#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
plugin_dir=$(cd -- "$script_dir/.config/opencode/plugins" && pwd -P)
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"

server_plugin="file://$plugin_dir/llamacpp-model-sync.ts"
tui_plugin="file://$plugin_dir/tokens-per-sec.tsx"

update_plugin_list() {
  local config_file="$1"
  local plugin_uri="$2"
  local plugin_name="$3"
  local target_file temporary

  mkdir -p "$(dirname -- "$config_file")"
  if [[ ! -f "$config_file" ]]; then
    printf '{}\n' >"$config_file"
  fi

  target_file=$(realpath "$config_file")
  temporary=$(mktemp "${target_file}.tmp.XXXXXX")
  if jq --arg plugin "$plugin_uri" --arg suffix "/$plugin_name" '
    .plugin = ((.plugin // [])
      | map(select(type != "string" or (endswith($suffix) | not)))
      | . + [$plugin])
  ' "$target_file" >"$temporary"; then
    chmod --reference="$target_file" "$temporary"
    mv "$temporary" "$target_file"
  else
    rm -f "$temporary"
    return 1
  fi
}

update_plugin_list "$config_dir/opencode.json" "$server_plugin" "llamacpp-model-sync.ts"
update_plugin_list "$config_dir/tui.json" "$tui_plugin" "tokens-per-sec.tsx"

printf 'Configured OpenCode plugins:\n  %s\n  %s\n' "$server_plugin" "$tui_plugin"
