#!/bin/sh

export EDITOR="nvim"
export SUDO_EDITOR="$EDITOR"
export PATH="/usr/local/bin:$PATH"

DOT_DIR="$HOME/dotfiles"
dotfiles_update() {
  cd $DOT_DIR || exit 1
  git fetch
  git reset --hard origin/main
  cd - || exit 1

  $SHELL "$DOT_DIR/setup.sh"

  USER_SOURCE_FILE=~/.profile

  # Profile target
  if [[ $SHELL == *bash* ]]; then
    if [[ -f ~/.bashrc ]]; then
      USER_SOURCE_FILE=~/.bashrc
    elif [[ -f ~/.bash_profile ]]; then
      USER_SOURCE_FILE=~/.bash_profile
    elif [[ -f ~/.bash_login ]]; then
      USER_SOURCE_FILE=~/.bash_login
    elif [[ -f ~/.profile ]]; then
      USER_SOURCE_FILE=~/.profile
    fi
  elif [[ $SHELL == *zsh* ]]; then
    USER_SOURCE_FILE=~/.zshrc
  fi

  source $USER_SOURCE_FILE
}

alias update_dotfiles="dotfiles_update"

gcommits() {
  if [ -z "$1" ]; then
    git log --format="%C(auto)%h (%s, %ad)" -n 20 | cat
  else
    git log --format="%H" -n $1 | cat
  fi
}

use() {
  printf "\033[0;34m( %s )\033[0m\n" "$1"
}

# alias with command print
_set() {
  alias $1="use '$2' && $2"
}

_set ll "ls -al"
_set p "pnpm"
_set gba "git branch -a"
_set gpaa "git add . --all && git commit --amend --no-edit && git push origin --force-with-lease"
_set grbi "git rebase upstream/master -i"
_set gph "git push heroku master"
_set gaa "git add -A"
_set gd "git diff"
_set gs "git status --short"
_set gco "git checkout"
_set gcp "git cherry-pick"
_set gci "git commit"
_set gcia "git commit --amend --no-edit"
_set grb "git rebase -i"
_set gp "git pull"
_set gpp "git push"
_set gfa "git fetch --all"
_set gfu "git fetch upstream"
_set grh "git reset --hard"
_set rho "git fetch origin && git reset --hard origin/\$(git branch --show-current)"
_set rhu "git fetch upstream && git reset --hard upstream/\$(git branch --show-current)"
_set gmt "git mergetool"
_set gl "git log --oneline --graph"
_set shipit "npm run deploy"
_set gpft "git push --follow-tags"
_set npmv "npm version $1 && git push --follow-tags && npm publish"
_set gif "$HOME/scripts/gif"
_set hosts "sudo vim /etc/hosts && sudo /etc/init.d/dns-clean restart && sudo /etc/init.d/networking restart"
_set amisafe "ps auxwww | grep sshd"
_set empty-trash "rm -rf ~/.local/share/Trash/*"
_set v "nvim"
_set pr "gh pr checkout $1"
_set cc "claude --dangerously-skip-permissions"
# _set cc "deno run -A --no-lock npm:@anthropic-ai/claude-code --dangerously-skip-permissions"
_set ccc "claude --dangerously-skip-permissions"
_set theirs "git checkout --theirs"
_set theme "$DOT_DIR/bin/theme-switch"
_set lt "eza --tree --level=2 --long --icons --git --git-ignore --ignore-glob='.git'"
_set lg "lazygit"
_set ld "lazydocker"
_set ds "devbox shell"

alias e="nvim"
alias v="nvim"

killport() {
  lsof -i ":$1" | grep LISTEN | awk '{print $2}' | xargs kill -9
}

killname() {
  for pid in $(ps -e | grep "$1" | awk '{print $1}'); do
    process_name=$(ps -p "$pid" -o comm=)
    echo "Are you sure you want to kill process $pid ($process_name)? [y/N]"
    read response
    if echo "$response" | grep -q '^[yY]\([eE][sS]\)\?$'; then
      sudo kill -9 "$pid"
      echo "Killed process $pid ($process_name)"
    else
      echo "Skipped process $pid ($process_name)"
    fi
  done
}

ipp() {
  dig +short myip.opendns.com @resolver1.opendns.com
}

ipl() {
  ifconfig | grep broadcast | awk '{print $2}'
}

node_admin() {
  # allows node to run on admin ports such as 80 and 443
  sudo setcap 'cap_net_bind_service=+ep' $(which node)
  echo "Changing max notify watcher from $(cat /proc/sys/fs/inotify/max_user_watches) to 524288 (max value)"
  echo "fs.inotify.max_user_watches=524288" | sudo tee -a /etc/sysctl.conf
}

alias clone="bun ~/dotfiles/advanced/clone.ts"

bwload() {
  # Declare array of supported env file templates
  local supported_files=(".env.example" "example.env" ".env.bw")
  local env_file=""

  bw sync

  # Find the first supported file that exists
  for file in "${supported_files[@]}"; do
    if [ -f "$file" ]; then
      env_file="$file"
      break
    fi
  done

  if [ -z "$env_file" ]; then
    echo "No supported env file found in current directory"
    echo "Supported files: ${supported_files[*]}"
    return 1
  fi

  # Extract item name from quotes in the found file (first quoted string found)
  item_name=$(grep -o '"[^"]*"' "$env_file" | head -n 1 | tr -d '"')

  if [ -z "$item_name" ]; then
    echo "No quoted item name found in $env_file"
    return 1
  fi

  echo "Using $env_file"
  echo "Fetching '$item_name' from Bitwarden..."
  bw get notes "$item_name" >.env

  if [ $? -eq 0 ]; then
    echo ".env file created successfully"
  else
    echo "Failed to fetch from Bitwarden. Make sure you're logged in (bw login) and unlocked (bw unlock)"
    return 1
  fi
}

git_test() {
  DEFAULT_FILTER="test.ts"
  DEFAULT_RUNNER="npx jest --watch"
  FILTER="${1:-$DEFAULT_FILTER}"
  RUNNER="${2:-$DEFAULT_RUNNER}"
  git diff origin/main --name-only | grep "$FILTER" | fzf -m | xargs "$RUNNER"
}
_set gt "git_test"

zellij_split() {
  branch_name="$1"
  tab_name="$2"

  if [ -z "$branch_name" ] || [ -z "$tab_name" ]; then
    echo "Error: branch_name and tab_name required"
    echo "Usage: zellij_split <branch_name> <tab_name>"
    return 1
  fi

  if [ -z "$ZELLIJ" ]; then
    echo "Error: Not in a zellij session"
    return 1
  fi

  # Create new tab
  zellij action new-tab --name "$tab_name"

  # Split pane vertically (50/50)
  zellij action new-pane --direction right

  # Focus left pane - will have nvim
  zellij action move-focus left

  # Focus right pane - will have shell
  zellij action move-focus right

  echo "Created tab '$tab_name' with two panes"
  echo "Left pane: ready for nvim | Right pane: shell"
}
_set wt "zellij_split"


power() {
  upower -i /org/freedesktop/UPower/devices/battery_BAT0 | grep 'state\|percentage'
}

denode() {
  deno run -A --unstable "npm:$1"
}

codeai() {
  file=$1
  prompt=$2
  echo "starting AI analysis for $file..."
  fullprompt="file: '$file':\n \`\`\`\n$(cat "$file")\n\n\`\`\`\n\nplease rewrite its content to satisfy the following: $prompt\n\n"
  echo "$fullprompt" | ollama run codellama:13b >"$file" &
  printf "to stop: \n kill %s" "$!"
}

speakai() {
  prompt=$1
  echo "starting AI..."
  echo "$prompt" | ollama run mistral | espeak -s150 -g4 -p55 -a 200 &
  printf "to stop: \n kill %s" "$!"
}

if [ "${SHELL##*/}" = "zsh" ]; then
  bindkey '[C' forward-word
  bindkey '[D' backward-word
fi

ai() {
  opencode "$@"
}

# gemini() {
#   deno run -A --no-lock npm:@google/gemini-cli "$@"
# }

pie_score() {
  echo "Generate a PIE score by listing 3 score for Physical, Intellectual and Emotional, each line starts with the name of the score followed by 'is <score>, because <make up a casual reason matching the category>'" | ollama run mistral
}

# replace normal to call hook after the command
# cd() {
#   builtin cd "$@" || return
#   check_for_devbox
# }

check_for_devbox() {
  if [[ -f "devbox.json" ]]; then

    if [[ -n "$DEVBOX_WORKING_DIR" && "$DEVBOX_WORKING_DIR" != "$(pwd)" ]]; then
      # We are already in a devbox shell but from a different path
      # Let's initialize the shell again to match the current path
      export DEVBOX_WORKING_DIR="$(pwd)"
      echo "Updating devbox shell to ($DEVBOX_WORKING_DIR)..."
      eval "$(devbox shellenv --recompute)"
    elif [[ -z "$DEVBOX_WORKING_DIR" ]]; then
      echo "Found devbox.json. Entering devbox shell..."
      which devbox >/dev/null || curl -fsSL https://get.jetify.com/devbox | bash
      export DEVBOX_WORKING_DIR="$(pwd)"
      devbox shell
      echo "You've exited devbox from!"
    fi
  fi
}

# also call on shell open for when you split your terminal on an existing devbox path
# remove this line if you find this behavior too intrusive
# check_for_devbox

# GOTCHA: on linux, nix dedamon might not be automatically starteed
# sudo systemctl enable --now nix-daemon

# Fix for terminal closing on any error
# Disable errexit mode that causes shell to exit on command errors
set +e

# Make bash completion case-sensitive
bind 'set completion-ignore-case off' 2>/dev/null || true

dockersh() {
  docker run -it --entrypoint sh "$1"
}

# ==============================================================================
# JIRA WORKTREE UTILITIES
# ==============================================================================
# Utilities for working with JIRA tickets and GitHub PRs in git worktrees

# Check if URL is a GitHub PR
_is_github_pr_url() {
  echo "$1" | grep -qE '^https?://github\.com/.+/.+/pull/[0-9]+/?'
}

# Check if URL is an Atlassian URL
_is_atlassian_url() {
  echo "$1" | grep -qE '^https?://.*\.atlassian\.net/'
}

# Extract reference from input (URL or plain identifier)
# Returns: reference (PED-1234 or pr-123)
_extract_ref() {
  local input="$1"

  case "$input" in
    http://*|https://*)
      if _is_github_pr_url "$input"; then
        echo "$input" | grep -oE 'pull/[0-9]+' | sed 's|pull/|pr-|'
      elif _is_atlassian_url "$input"; then
        local ticket=$(echo "$input" | grep -oE '[A-Z]+-[0-9]+' | head -n 1)
        if [ -z "$ticket" ]; then
          return 1
        fi
        echo "$ticket"
      else
        echo "Error: Unrecognized URL format"
        return 1
      fi
      ;;
    *)
      echo "$input"
      ;;
  esac
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

# Main function: Start work on JIRA ticket or GitHub PR
# Creates a git worktree, opens a zellij tab, and starts devbox shell
# Args: input (PED-xxxx, pr-xxxx, Atlassian URL, or GitHub PR URL), label (optional)
jira_claude() {
  local input="$1"
  local label="${2:-}"

  if [ -z "$input" ]; then
    echo "Usage: jc <PED-xxxx|pr-xxxx|ATLASSIAN_URL|GITHUB_PR_URL> [label]"
    echo "Examples:"
    echo "  jc PED-1234"
    echo "  jc PED-1234 somelabel"
    echo "  jc https://stay22.atlassian.net/browse/PED-1234"
    echo "  jc https://github.com/owner/repo/pull/123"
    echo "  jc pr-123 fix-auth"
    return 1
  fi

  _git_check_repo || return 1

  local repo_info=$(_git_get_repo_info)
  local repo_root=$(echo "$repo_info" | cut -d'|' -f1)
  local repo_name=$(echo "$repo_info" | cut -d'|' -f2)

  # Extract reference from input
  local ref=$(_extract_ref "$input")
  if [ $? -ne 0 ] || [ -z "$ref" ]; then
    echo "Error: Could not extract reference from: $input"
    return 1
  fi

  echo "Reference: $ref"

  # Build branch name
  local branch_name="$ref"
  if [ -n "$label" ]; then
    branch_name="${ref}-${label}"
  fi

  local worktree_base="$HOME/worktrees/$repo_name"
  local worktree_path="$worktree_base/$branch_name"
  local tab_name="${repo_name}:${branch_name}"

  # Delete previous worktree if it exists
  if [ -d "$worktree_path" ]; then
    echo "Removing existing worktree at: $worktree_path"
    cd "$repo_root" || return 1
    git worktree remove "$worktree_path" --force 2>/dev/null || true
    if git show-ref --verify --quiet "refs/heads/$branch_name"; then
      git branch -D "$branch_name" 2>/dev/null || true
    fi
  fi

  # Create worktree
  mkdir -p "$worktree_base"
  cd "$repo_root" || return 1

  echo "Creating worktree for $branch_name..."
  git worktree add -b "$branch_name" "$worktree_path" || {
    echo "Error: Failed to create worktree"
    return 1
  }

  # Initialize worktree from origin/main
  cd "$worktree_path" || return 1
  git fetch origin
  git reset --hard origin/main

  # For GitHub PRs, checkout the PR branch into the worktree
  if echo "$ref" | grep -qE '^pr-[0-9]+$'; then
    local pr_number=$(echo "$ref" | sed 's/pr-//')
    echo "Fetching PR #${pr_number}..."
    git fetch origin "pull/${pr_number}/head:${branch_name}" 2>/dev/null || true
    gh pr checkout "$pr_number" 2>/dev/null || true
  fi

  # Setup zellij tab
  if [ -n "$ZELLIJ" ]; then
    echo "Creating zellij tab: $tab_name"
    zellij action new-tab --name "$tab_name"

    # cd into worktree and start devbox shell
    zellij action write-chars "cd \"$worktree_path\" && ds"
    zellij action write 13  # Enter key
  else
    echo "Not in a zellij session. Worktree ready at: $worktree_path"
    echo "Run: cd $worktree_path && ds"
  fi
}
_set jc "jira_claude"

# Remove a worktree and close its zellij tab
# Args: input (PED-xxxx, pr-xxxx, Atlassian URL, or GitHub PR URL), label (optional)
jira_worktree_clean() {
  local input="$1"
  local label="${2:-}"

  if [ -z "$input" ]; then
    echo "Usage: jtc <PED-xxxx|pr-xxxx|ATLASSIAN_URL|GITHUB_PR_URL> [label]"
    echo "Examples:"
    echo "  jtc PED-1234"
    echo "  jtc PED-1234 somelabel"
    echo "  jtc pr-123"
    echo "  jtc https://stay22.atlassian.net/browse/PED-1234"
    return 1
  fi

  _git_check_repo || return 1

  local repo_info=$(_git_get_repo_info)
  local repo_root=$(echo "$repo_info" | cut -d'|' -f1)
  local repo_name=$(echo "$repo_info" | cut -d'|' -f2)

  # Extract reference
  local ref=$(_extract_ref "$input")
  if [ $? -ne 0 ] || [ -z "$ref" ]; then
    echo "Error: Could not extract reference from: $input"
    return 1
  fi

  local branch_name="$ref"
  if [ -n "$label" ]; then
    branch_name="${ref}-${label}"
  fi

  local worktree_base="$HOME/worktrees/$repo_name"
  local worktree_path="$worktree_base/$branch_name"
  local tab_name="${repo_name}:${branch_name}"

  # Close matching zellij tab if in a zellij session
  if [ -n "$ZELLIJ" ]; then
    echo "Closing zellij tab: $tab_name"
    # List tabs and find the matching one to close
    local tab_id=$(zellij action query-tab-names 2>/dev/null | grep -nF "$tab_name" | head -1 | cut -d: -f1)
    if [ -n "$tab_id" ]; then
      # tab_id is 1-indexed from grep -n, zellij uses 1-indexed
      zellij action close-tab --tab-index "$((tab_id))"
      echo "Closed zellij tab: $tab_name"
    else
      echo "No zellij tab found matching: $tab_name"
    fi
  fi

  # Remove worktree
  cd "$repo_root" || return 1
  if [ -d "$worktree_path" ]; then
    echo "Removing worktree: $worktree_path"
    git worktree remove "$worktree_path" --force 2>/dev/null || rm -rf "$worktree_path"
  else
    echo "No worktree found at: $worktree_path"
  fi

  # Delete the branch
  if git show-ref --verify --quiet "refs/heads/$branch_name"; then
    echo "Deleting branch: $branch_name"
    git branch -D "$branch_name" 2>/dev/null || true
  fi

  # Prune stale references
  git worktree prune

  echo "Cleanup complete for $branch_name"
}
_set jtc "jira_worktree_clean"


