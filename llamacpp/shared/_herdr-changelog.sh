# Open a Herdr tab with the changelog of what a llama.cpp fast-forward pulled in. SOURCED, not executed.
#
# Called by llamacpp/<variant>/update.sh right after `git merge --ff-only` moved HEAD.
# The update's own output is a one-liner ("master abc1234 -> def5678 (37 commits)"),
# which says nothing about WHAT changed -- and the thing that usually matters (a new
# architecture, a changed server flag, a Vulkan regression) is only visible in the
# commits. So the commit log lands in its own tab, pager and all, where it can be read
# while the build runs. Nothing here is fatal: no Herdr, no tab.
#
# Subjects, not patches. `git log --patch` over a 200-commit pull is thousands of diff
# hunks of kernel and shader code, and none of it is readable as a summary -- while the
# llama.cpp commit subjects already carry the area ("server :", "ggml-cuda :") and the PR
# number, which is the changelog. Upstream ships no CHANGELOG file, and its GitHub
# releases are generated from these same subjects, so there is nothing richer to fetch
# (and no API quota to burn on it). `LLAMACPP_DIFF_PATCH=1` gets the old `--stat --patch`
# back for when a regression really does need the hunks.
#
# No decorations: upstream tags every single commit with a build number (b12211), so a
# `%d` per line would be one "tag: bNNNNN" of noise after every subject.
#
# Where the tab goes:
#   - under `dotfiles_update` (DOTFILES_JOB set) the updater runs in a throwaway
#     "dotfiles: llamacpp" workspace that herdr_fan_out closes on success, so a tab in
#     there would vanish with it. The changelog gets its own workspace instead.
#   - run by hand inside Herdr, a tab next to the one you typed in.
#
# PORTABILITY: macOS bash 3.2 -- no associative arrays, no mapfile.

# Usage: llamacpp_herdr_changelog_tab <repo-dir> <before-sha> <after-sha>
llamacpp_herdr_changelog_tab() {
  local dir="$1" before="$2" after="$3" label cmd workspace_id result pane
  [[ "${HERDR_ENV:-}" = 1 ]] || return 0
  command -v herdr >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || return 0
  herdr status server >/dev/null 2>&1 || return 0

  label="llama.cpp $(git -C "$dir" rev-parse --short "$before")..$(git -C "$dir" rev-parse --short "$after")"
  # Oldest first so it reads like a changelog; --no-merges drops the "Merge branch
  # 'master' of github.com:..." lines that would otherwise pad the list by ~10%.
  if [[ -n "${LLAMACPP_DIFF_PATCH:-}" ]]; then
    cmd="git -C '$dir' log --reverse --stat --patch '$before..$after'"
  else
    cmd="git -C '$dir' log --reverse --no-merges --date=short --pretty=format:'%h %ad %s' '$before..$after'"
  fi

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
  echo -e "${INFO}llama.cpp:${NORM} changelog opened in Herdr tab '$label'"
}
