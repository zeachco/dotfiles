# Open a Herdr tab showing what a llama.cpp fast-forward pulled in. SOURCED, not executed.
#
# Called by llamacpp/<variant>/update.sh right after `git merge --ff-only` moved HEAD.
# The update's own output is a one-liner ("master abc1234 -> def5678 (37 commits)"),
# which says nothing about WHAT changed -- and the thing that usually matters (a new
# architecture, a changed server flag, a Vulkan regression) is only visible in the
# commits. So the commit log with per-commit patches lands in its own tab, pager and
# all, where it can be read while the build runs. Nothing here is fatal: no Herdr,
# no tab.
#
# Where the tab goes:
#   - under `dotfiles_update` (DOTFILES_JOB set) the updater runs in a throwaway
#     "dotfiles: llamacpp" workspace that herdr_fan_out closes on success, so a tab in
#     there would vanish with it. The diff gets its own workspace instead.
#   - run by hand inside Herdr, a tab next to the one you typed in.
#
# PORTABILITY: macOS bash 3.2 -- no associative arrays, no mapfile.

# Usage: llamacpp_herdr_diff_tab <repo-dir> <before-sha> <after-sha>
llamacpp_herdr_diff_tab() {
  local dir="$1" before="$2" after="$3" label cmd workspace_id result pane
  [[ "${HERDR_ENV:-}" = 1 ]] || return 0
  command -v herdr >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || return 0
  herdr status server >/dev/null 2>&1 || return 0

  label="llama.cpp $(git -C "$dir" rev-parse --short "$before")..$(git -C "$dir" rev-parse --short "$after")"
  # Oldest first so it reads like a changelog; --stat gives the file summary before
  # each patch so a 2000-line shader commit can be skipped in the pager.
  cmd="git -C '$dir' log --reverse --stat --patch '$before..$after'"

  if [[ -n "${DOTFILES_JOB:-}" ]]; then
    result=$(herdr workspace create --cwd "$dir" --label "$label" --no-focus 2>/dev/null) || return 0
  else
    workspace_id="${HERDR_WORKSPACE_ID:-}"
    if [[ -z "$workspace_id" && -n "${HERDR_TAB_ID:-}" ]]; then
      workspace_id=$(herdr tab get "$HERDR_TAB_ID" 2>/dev/null | jq -r '.result.tab.workspace_id // empty')
    fi
    if [[ -n "$workspace_id" ]]; then
      result=$(herdr tab create --workspace "$workspace_id" --cwd "$dir" --label "$label" --no-focus 2>/dev/null) || return 0
    else
      result=$(herdr workspace create --cwd "$dir" --label "$label" --no-focus 2>/dev/null) || return 0
    fi
  fi
  pane=$(echo "$result" | jq -r '.result.root_pane.pane_id // empty' 2>/dev/null)
  [[ -n "$pane" ]] || return 0
  herdr pane run "$pane" "$cmd" >/dev/null 2>&1 || return 0
  echo -e "${INFO}llama.cpp:${NORM} commit diff opened in Herdr tab '$label'"
}
