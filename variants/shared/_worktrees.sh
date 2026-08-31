#!/bin/sh

# ==============================================================================
# HERDR & WORKTREE UTILITIES
# ==============================================================================

# Open a Herdr workspace (devbox shell + editor) on a branch's worktree.
# Usage: herdr_branch_repo <branch|PR url|JIRA url> [tab_label] [--pr=N]
# --pr=N names the tab "#N: <branch>" from the start and hands the number to
# tab_autoname, so the tab is identifiable before the async rename lands.
herdr_branch_repo() {
  if [ -z "$HERDR_ENV" ]; then
    echo "Error: Not in a Herdr session"
    return 1
  fi

  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: Not in a git repository"
    return 1
  fi

  local branch_name="" tab_label="" pr_number="" arg
  for arg in "$@"; do
    case "$arg" in
    --pr=*) pr_number="${arg#*=}" ;;
    *)
      if [ -z "$branch_name" ]; then
        branch_name="$arg"
      else
        tab_label="$arg"
      fi
      ;;
    esac
  done
  branch_name="${branch_name:-main}"

  local tab_prefix=""
  case "$branch_name" in
    https://github.com/*/*/pull/*)
      branch_name="${branch_name%/}"
      branch_name="${branch_name##*/}"
      tab_prefix="pr-${branch_name}"
      ;;
    https://*.atlassian.net/browse/*)
      branch_name="${branch_name%/}"
      branch_name="${branch_name##*/}"
      tab_prefix="jira-${branch_name}"
      ;;
    *)
      if echo "$branch_name" | grep -qE "^${JIRA_PREFIX:-[A-Z]+-}[0-9]+$"; then
        tab_prefix="jira-${branch_name}"
      fi
      ;;
  esac

  local repo_root=$(git rev-parse --show-toplevel)
  local repo_name=$(basename "$repo_root")
  local tab_name="${repo_name}:${branch_name}"
  if [ -n "$tab_label" ]; then
    tab_name="${repo_name}:${tab_label}"
  elif [ -n "$pr_number" ]; then
    # key the tab on the PR number immediately: all_my_prs dedups on it, so it
    # must not depend on the async tab_autoname rename having landed
    tab_name="#${pr_number}: ${branch_name}"
  elif [ -n "$tab_prefix" ]; then
    tab_name="$tab_prefix"
  fi
  local worktree_base="$HOME/worktrees/$repo_name"
  local worktree_path="$worktree_base/$branch_name"

  # Let Herdr own the Git worktree: `worktree create`/`open` runs `git
  # worktree add` (or checks out the existing one) and opens a fresh
  # workspace/tab/pane for it in a single call, so there is no more tab or
  # pane juggling to do by hand here.
  local result
  if [ "$branch_name" = "main" ] || [ "$branch_name" = "master" ]; then
    # For main/master, just open the repo root directly
    result=$(herdr workspace create --cwd "$repo_root" --label "$tab_name" --focus)
  elif [ -d "$worktree_path" ]; then
    echo "Worktree already exists at: $worktree_path"
    # --path and --branch are mutually exclusive here; the path is what we know
    result=$(herdr worktree open --cwd "$repo_root" --path "$worktree_path" --label "$tab_name" --focus)
  else
    mkdir -p "$worktree_base"
    echo "Creating worktree for $branch_name..."
    result=$(herdr worktree create --cwd "$repo_root" --branch "$branch_name" --path "$worktree_path" --label "$tab_name" --focus)
  fi
  if [ $? -ne 0 ]; then
    echo "Error: Failed to open the worktree in Herdr"
    return 1
  fi

  local target_path tab_id root_pane already_open
  target_path=$(echo "$result" | jq -r '.result.worktree.path // empty')
  target_path="${target_path:-$repo_root}"
  tab_id=$(echo "$result" | jq -r '.result.tab.tab_id // empty')
  root_pane=$(echo "$result" | jq -r '.result.root_pane.pane_id // empty')
  if [ -z "$tab_id" ] || [ -z "$root_pane" ]; then
    echo "Error: unexpected response from herdr"
    return 1
  fi

  # Herdr already had this worktree open and handed back its existing tab. Its
  # answer beats any label match: a tab renamed by tab_autoname before its PR
  # existed carries neither "#<number>: " nor "<repo>:<branch>". Stop here —
  # running the pane command again would cd and restart the editor on top of
  # whatever is running in that pane. Return 2 so callers can count it apart.
  already_open=$(echo "$result" | jq -r '.result.already_open // false')
  if [ "$already_open" = "true" ]; then
    echo "Already open in tab id $tab_id at $target_path"
    return 2
  fi

  # Devbox shell in the root pane, then the editor in the same pane once the
  # shell exits.
  herdr pane run "$root_pane" "cd \"$target_path\" && ds && e ."

  # Auto-name the tab from its own PR/commits when no explicit name was
  # given, in a second pane split below that closes itself once done, so the
  # slow gh/model calls never hold up the devbox shell or the editor. The tab
  # id has to be passed in: that pane cannot work out on its own which tab it
  # lives in, it would only ever see whichever tab is focused.
  if [ -z "$tab_label" ] && [ "$branch_name" != "main" ] && [ "$branch_name" != "master" ]; then
    local autoname_pane autoname_cmd
    autoname_pane=$(herdr pane split "$root_pane" --direction down --cwd "$target_path" --no-focus | jq -r '.result.pane.pane_id // empty')
    if [ -n "$autoname_pane" ]; then
      autoname_cmd="tab_autoname --tab-id=$tab_id"
      [ -n "$pr_number" ] && autoname_cmd="$autoname_cmd --pr=$pr_number"
      herdr pane run "$autoname_pane" "$autoname_cmd; exit"
    fi
  fi

  echo "Tab '$tab_name' (id $tab_id) ready at $target_path"
}
_set wt "herdr_branch_repo"

# Fetch all my open PRs for this repo and create a Herdr workspace (wt)
# for each one, using the PR's actual branch for the worktree
all_my_prs() {
  if [ -z "$HERDR_ENV" ]; then
    echo "Error: Not in a Herdr session"
    return 1
  fi
  _git_check_repo || return 1

  local repo_name
  repo_name=$(basename "$(git rev-parse --show-toplevel)")

  echo "Fetching your open PRs..."
  local prs
  prs=$(gh pr list --author "@me" --state open --json number,headRefName \
    --jq '.[] | (.number|tostring) + " " + .headRefName' </dev/null)
  if [ $? -ne 0 ]; then
    echo "Error: failed to list PRs (is gh authenticated?)"
    return 1
  fi
  if [ -z "$prs" ]; then
    echo "No open PRs found."
    return 0
  fi

  local open_tabs
  open_tabs=$(herdr tab list 2>/dev/null | jq -r '.result.tabs[].label')

  # make sure the PR branches are known locally before creating worktrees
  git fetch origin --quiet </dev/null 2>/dev/null

  # the PR list is fed in on fd 3, not stdin: anything in the loop that reads
  # stdin (a gh prompt, git asking for credentials) would otherwise swallow the
  # remaining lines and those PRs would silently never get a workspace
  local count=0 skipped=0 failed=0 number branch
  while read -r number branch <&3; do
    [ -z "$branch" ] && continue
    echo ""
    echo "=== PR #${number} (${branch}) ==="

    # Match every name a tab for this PR can carry. "#<number>: ..." is given
    # at creation time and preserved by tab_autoname; "<repo>:<branch>" covers
    # tabs opened before PR-numbered names, or whose autoname never landed.
    # Both are deterministic — dedup must not depend on the async rename.
    if printf '%s\n' "$open_tabs" | grep -q "^#${number}\([^0-9]\|$\)"; then
      echo "Skipping: a tab starting with '#${number}' is already open."
      skipped=$((skipped + 1))
      continue
    fi
    if printf '%s\n' "$open_tabs" | grep -qxF "${repo_name}:${branch}"; then
      echo "Skipping: a tab named '${repo_name}:${branch}' is already open."
      skipped=$((skipped + 1))
      continue
    fi

    herdr_branch_repo "$branch" --pr="$number"
    case $? in
    0)
      count=$((count + 1))
      # keep the snapshot in step, in case the same PR shows up twice
      open_tabs=$(printf '%s\n#%s: %s' "$open_tabs" "$number" "$branch")
      ;;
    2)
      skipped=$((skipped + 1))
      ;;
    *)
      echo "Error: failed to open a workspace for PR #${number}"
      failed=$((failed + 1))
      ;;
    esac
  done 3<<EOF
$prs
EOF

  echo ""
  echo "Opened $count workspace(s); skipped $skipped already-open PR(s)."
  if [ "$failed" -gt 0 ]; then
    echo "Failed on $failed PR(s)."
  fi
  return 0
}
_set allprs "all_my_prs"

zellij_branch_repo_delete() {
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: Not in a git repository"
    return 1
  fi

  local repo_root=$(git rev-parse --show-toplevel)
  local main_root=$(git -C "$repo_root" worktree list --porcelain | head -n 1 | awk '{print $2}')

  if [ "$repo_root" = "$main_root" ]; then
    echo "Error: Not in a worktree (you're in the main repo)"
    return 1
  fi

  local branch_name=$(git branch --show-current)

  # Move to main repo root before removing the worktree
  cd "$main_root" || return 1

  echo "Removing worktree at $repo_root..."
  git worktree remove "$repo_root" --force

  if [ $? -ne 0 ]; then
    echo "Error: Failed to remove worktree"
    return 1
  fi

  # Delete the branch
  if [ -n "$branch_name" ] && git show-ref --verify --quiet "refs/heads/$branch_name"; then
    echo "Deleting branch $branch_name..."
    git branch -D "$branch_name"
  fi

  echo "Worktree removed. Closing tab in 2 seconds..."
}
_set wtd "zellij_branch_repo_delete"

# ==============================================================================
# JIRA WORKTREE UTILITIES
# ==============================================================================
# Utilities for working with JIRA tickets and GitHub PRs in git worktrees

# Check if URL is a GitHub PR
_is_github_pr_url() {
  echo "$1" | grep -qE '^https?://github\.com/.+/.+/pull/[0-9]+/?'
}

# Extract ticket identifier from URL or return as-is
# Supports JIRA URLs and GitHub PR URLs
_extract_ticket() {
  local input="$1"

  case "$input" in
    http://*|https://*)
      # Check if it's a GitHub PR URL
      if _is_github_pr_url "$input"; then
        # Return PR number prefixed with 'pr-'
        echo "$input" | grep -oE 'pull/[0-9]+' | sed 's/pull/pr/'
      else
        # Extract JIRA ticket number from URL
        local ticket=$(echo "$input" | grep -oE '[A-Z]+-[0-9]+' | head -n 1)
        if [ -z "$ticket" ]; then
          echo ""
          return 1
        fi
        echo "$ticket"
      fi
      ;;
    *)
      # Return as-is (plain ticket number)
      echo "$input"
      ;;
  esac
}

# Validate JIRA ticket format
_validate_jira_ticket() {
  local ticket="$1"
  if ! echo "$ticket" | grep -qE '^[A-Z]+-[0-9]+$'; then
    echo "Error: Invalid JIRA ticket format: $ticket"
    echo "Expected format: PROJECT-123 (e.g., PED-1234)"
    return 1
  fi
}

# Check if in git repository
_git_check_repo() {
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: Not in a git repository"
    return 1
  fi
}

# Get repository root and name
# Returns: "repo_root|repo_name"
_git_get_repo_info() {
  local repo_root=$(git rev-parse --show-toplevel)
  local repo_name=$(basename "$repo_root")
  echo "$repo_root|$repo_name"
}

# Check if worktree exists and prompt for deletion
# Args: worktree_path, branch_name, repo_root
# Returns: 0 to proceed, 1 to abort
_worktree_check_exists() {
  local worktree_path="$1"
  local branch_name="$2"
  local repo_root="$3"

  if [ -d "$worktree_path" ]; then
    echo "Worktree already exists at: $worktree_path"
    printf "Do you want to delete it and start fresh? [y/N] "
    read response

    if echo "$response" | grep -qE '^[yY]([eE][sS])?$'; then
      echo "Removing existing worktree..."
      cd "$repo_root" || return 1
      git worktree remove "$worktree_path" --force

      # Also delete the branch if it exists
      if git show-ref --verify --quiet "refs/heads/$branch_name"; then
        echo "Deleting branch $branch_name..."
        git branch -D "$branch_name"
      fi

      echo "Creating new worktree..."
      return 0
    else
      echo "Keeping existing worktree. Exiting..."
      return 1
    fi
  fi

  return 0
}

# Create new worktree
# Args: branch_name, worktree_path
_worktree_create() {
  local branch_name="$1"
  local worktree_path="$2"

  echo "Creating worktree for $branch_name..."
  git worktree add -b "$branch_name" "$worktree_path"

  if [ $? -ne 0 ]; then
    echo "Error: Failed to create worktree"
    return 1
  fi
}

# Initialize worktree from main branch
# Args: worktree_path
_worktree_init() {
  local worktree_path="$1"

  cd "$worktree_path" || return 1
  echo "Initializing worktree from clean main branch..."
  git fetch origin
  git reset --hard origin/main
}

# Setup zellij pane with commands
# Args: worktree_path, commands...
_zellij_pane_init() {
  local worktree_path="$1"
  shift

  zellij action write-chars "cd \"$worktree_path\""
  zellij action write 13  # Enter key

  zellij action write-chars "git fetch origin && git reset --hard origin/main"
  zellij action write 13  # Enter key

  # Execute remaining commands
  for cmd in "$@"; do
    zellij action write-chars "$cmd"
    zellij action write 13  # Enter key
  done
}

# Setup zellij workspace for development work
# Args: worktree_path, tab_name, right_pane_cmd
_zellij_setup_workspace() {
  local worktree_path="$1"
  local tab_name="$2"
  local right_pane_cmd="$3"

  echo "Creating zellij workspace: $tab_name"
  zellij action new-tab --name "$tab_name"

  # Split pane vertically (50/50)
  zellij action new-pane --direction right

  # Setup left pane (nvim)
  zellij action move-focus left
  _zellij_pane_init "$worktree_path" "nvim ."

  # Setup right pane (custom command)
  zellij action move-focus right
  _zellij_pane_init "$worktree_path" "$right_pane_cmd"

  # Focus back to left pane
  zellij action move-focus left

  echo "Workspace ready!"
  echo "Left pane: nvim | Right pane: $right_pane_cmd"
}

# Checkout GitHub PR branch
# Args: pr_url
_github_pr_checkout() {
  local pr_url="$1"

  echo "Checking out GitHub PR..."
  gh pr checkout "$pr_url"

  if [ $? -ne 0 ]; then
    echo "Error: Failed to checkout PR"
    return 1
  fi
}

# Main function: Start work on JIRA ticket or GitHub PR
# Args: input (JIRA ticket/URL or GitHub PR URL), keyword (optional)
jira_claude() {
  local input="$1"
  local keyword="${2:-}"

  if [ -z "$input" ]; then
    echo "Error: JIRA ticket, JIRA URL, GitHub PR URL, or pr-NNN required"
    echo "Usage: jira_claude <JIRA_NUMBER|JIRA_URL|GITHUB_PR_URL|pr-NNN> [keyword]"
    echo "Examples:"
    echo "  jira_claude PED-1234"
    echo "  jira_claude https://stay22.atlassian.net/browse/PED-1234"
    echo "  jira_claude https://github.com/owner/repo/pull/123"
    echo "  jira_claude pr-123"
    echo "  jira_claude PED-1234 my-work-namespace"
    return 1
  fi

  # Check if in git repository
  _git_check_repo || return 1

  # Get repository info
  local repo_info=$(_git_get_repo_info)
  local repo_root=$(echo "$repo_info" | cut -d'|' -f1)
  local repo_name=$(echo "$repo_info" | cut -d'|' -f2)

  # Check if it's a GitHub PR URL or pr-NNN shorthand
  local is_pr=false
  local pr_ref="$input"

  if _is_github_pr_url "$input"; then
    is_pr=true
  elif echo "$input" | grep -qiE '^pr-[0-9]+$'; then
    is_pr=true
    pr_ref=$(echo "$input" | grep -oE '[0-9]+')
  fi

  if [ "$is_pr" = true ]; then
    echo "Detected GitHub PR"

    # Checkout the PR branch
    cd "$repo_root" || return 1
    _github_pr_checkout "$pr_ref" || return 1

    local branch_name=$(git branch --show-current)
    local tab_name="${repo_name}:${branch_name}"

    if [ -n "$ZELLIJ" ]; then
      # Setup zellij workspace with just nvim (no Claude)
      _zellij_setup_workspace "$repo_root" "$tab_name" "echo 'Ready to work on PR'"
    else
      echo "Opening editor..."
      nvim .
    fi

    return 0
  fi

  # Extract and validate JIRA ticket
  local ticket=$(_extract_ticket "$input")
  if [ -z "$ticket" ]; then
    echo "Error: Could not extract ticket from: $input"
    return 1
  fi

  echo "Extracted ticket: $ticket"
  _validate_jira_ticket "$ticket" || return 1

  # Build branch name and worktree path
  local branch_name="$ticket"
  if [ -n "$keyword" ]; then
    branch_name="${ticket}-${keyword}"
  fi

  local worktree_base="$HOME/worktrees/$repo_name"
  local worktree_path="$worktree_base/$branch_name"

  # Create worktree base directory
  mkdir -p "$worktree_base"

  # Check if worktree exists
  _worktree_check_exists "$worktree_path" "$branch_name" "$repo_root" || return 0

  # Create new worktree
  _worktree_create "$branch_name" "$worktree_path" || return 1

  # Build tab name with repo prefix
  local tab_name="${repo_name}:${branch_name}"

  # Build claude code prompt
  local cc_prompt="Please fetch the details for JIRA ticket ${ticket} and create a plan to implement it. If you see a devbox.json files, you might want to execute \`devbox shell\` before running any project related commands like using node, installing dependencies, etc"

  # Setup workspace
  if [ -n "$ZELLIJ" ]; then
    _zellij_setup_workspace "$worktree_path" "$tab_name" "cc '$cc_prompt'"
  else
    echo "Not in a zellij session."
    _worktree_init "$worktree_path" || return 1

    echo "Starting Claude Code to plan work for $ticket..."
    claude --permission-mode auto "$cc_prompt"
  fi
}
_set jc "jira_claude"

# Clean up all worktrees for current repository
worktree_delete_all() {
  # Check if in git repository
  _git_check_repo || return 1

  # Get repository info
  local repo_info=$(_git_get_repo_info)
  local repo_root=$(echo "$repo_info" | cut -d'|' -f1)
  local repo_name=$(echo "$repo_info" | cut -d'|' -f2)
  local worktree_base="$HOME/worktrees/$repo_name"

  echo "Repository: $repo_name"
  echo "Worktree directory: $worktree_base"
  echo ""

  # List all worktrees for this repo
  echo "Current worktrees:"
  git worktree list

  echo ""
  printf "Do you want to remove all worktrees and update the main repo? [y/N] "
  read response

  if ! echo "$response" | grep -qE '^[yY]([eE][sS])?$'; then
    echo "Cancelled."
    return 0
  fi

  # Change to repo root
  cd "$repo_root" || return 1

  # Remove all worktrees except the main one
  echo "Removing worktrees..."
  git worktree list --porcelain | grep "^worktree" | awk '{print $2}' | while read -r worktree; do
    # Skip the main worktree (the repo root)
    if [ "$worktree" != "$repo_root" ]; then
      echo "Removing: $worktree"
      git worktree remove "$worktree" --force 2>/dev/null || true
    fi
  done

  # Clean up worktree directory if it exists
  if [ -d "$worktree_base" ]; then
    echo "Removing worktree directory: $worktree_base"
    sudo rm -rf "$worktree_base"
  fi

  # Prune stale worktree references
  echo "Pruning stale worktree references..."
  git worktree prune

  # Delete all local branches that match JIRA ticket pattern (PROJECT-NUMBER)
  echo "Cleaning up JIRA ticket branches..."
  git branch | grep -E '^\s*[A-Z]+-[0-9]+' | xargs -r git branch -D 2>/dev/null || true

  # Update the main repository
  echo "Updating main repository..."
  git fetch --all --prune

  # If on main/master, reset to origin
  local current_branch=$(git branch --show-current)
  if [ "$current_branch" = "main" ] || [ "$current_branch" = "master" ]; then
    echo "Resetting $current_branch to origin/$current_branch..."
    git reset --hard "origin/$current_branch"
  else
    echo "On branch $current_branch - not resetting (switch to main/master to reset)"
  fi

  echo ""
  echo "Cleanup complete!"
  echo "Remaining worktrees:"
  git worktree list
}
_set wtda "worktree_delete_all"

alias wtl='git worktree list'
