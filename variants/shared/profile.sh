#!/bin/sh

export EDITOR="nvim"
export SUDO_EDITOR="$EDITOR"
export PATH="/usr/local/bin:$PATH"

PATH=$PATH:/home/olivier/.cargo/bin

DOT_DIR="$HOME/dotfiles"
dotfiles_update() {
  cd $DOT_DIR || return 1
  git fetch

  # git reset --hard below throws away local work, warn before it happens.
  # Check every *tracked* file (staged + unstaged changes vs HEAD). Untracked
  # files are safe — reset --hard never touches them — so they must not gate
  # the update (status --porcelain flagged them and re-prompted forever).
  DIRTY=$(git diff --name-only HEAD)
  UNPUSHED=$(git log --oneline origin/main..HEAD 2>/dev/null)
  if [ -n "$DIRTY" ] || [ -n "$UNPUSHED" ]; then
    printf "\033[0;33mdotfiles has local work that 'git reset --hard origin/main' will destroy:\033[0m\n"
    [ -n "$DIRTY" ] && printf "\nuncommitted changes:\n%s\n" "$DIRTY"
    [ -n "$UNPUSHED" ] && printf "\nunpushed commits:\n%s\n" "$UNPUSHED"
    if [ ! -t 0 ]; then
      printf "\nnot a tty, aborting update\n"
      cd - >/dev/null || return 1
      return 1
    fi
    printf "\ndiscard it and reset to origin/main? [y/N] "
    read -r REPLY_RESET
    case "$REPLY_RESET" in
      y | Y | yes | YES) ;;
      *)
        printf "aborted, dotfiles left untouched\n"
        cd - >/dev/null || return 1
        return 1
        ;;
    esac
  fi

  git reset --hard origin/main
  cd - || return 1

  $SHELL "$DOT_DIR/setup.sh"

  # Bump mise-managed tools to their latest matching versions, then drop the
  # versions no mise config selects any more; -y skips the prompts.
  if command -v mise >/dev/null 2>&1; then
    mise upgrade -y
    mise prune -y
  fi

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
_set gpaanv "git add . --all && git commit --amend --no-edit && git push origin --force-with-lease --no-verify"
_set grbi "git rebase upstream/master -i"
_set gph "git push heroku master"
_set gaa "git add -A"
_set gs "git status --short"
_set gco "git checkout"
_set gcp "git cherry-pick"
_set gci "git commit"
_set gcia "git commit --amend --no-edit"
_set grb "git rebase -i"
_set gmf "git diff --name-only"
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
_set cc "claude --permission-mode auto"
_set ccc "claude --permission-mode auto"
_set theirs "git checkout --theirs"
_set theme "$DOT_DIR/bin/theme-switch"
_set lt "eza --tree --level=2 --long --icons --git --git-ignore --ignore-glob='.git'"
_set lg "lazygit"
_set ld "lazydocker"
_set oo "opencode"
# pr / prs / opr live in _worktrees.sh: they pick gh or glab per repo

alias e="nvim"
alias v="nvim"
alias say="$DOT_DIR/bin/say"
alias speak="$DOT_DIR/bin/say"
alias listen="$DOT_DIR/bin/listen"
alias converse="$DOT_DIR/bin/converse"
alias gpu-cap="$DOT_DIR/bin/gpu-cap"
alias llamacpp-sync="$DOT_DIR/bin/llamacpp-sync"
# Cross-checks ~/models vs the INI presets vs the client configs. Run it after adding
# or removing a model; --remote also parses every GGUF and compares it to its HF size.
alias llamacpp-audit="$DOT_DIR/bin/llamacpp-audit"
# sniff_llms lives in its own repo (github.com/zeachco/sniff_llms), cloned at ~/dev/sniff_llms
alias sniff_llms='cargo run --release --manifest-path "$HOME/dev/sniff_llms/Cargo.toml" --'
# `rr --help` → `cargo run --release -- --help` (args go to the program, not cargo)
_set rr "cargo run --release --"
_set bb "cargo build --release --no-default-features"
alias lll="los"
alias wa="work-agent"
alias secrets="bwload"
# fuzzy-search all systemd services; Enter follows the logs of the selected one (Ctrl+C quits)
deamons() {
  local svc
  svc=$(
    systemctl list-units --type=service --all --no-pager --no-legend \
      | awk '{print $1, $3}' \
      | fzf --delimiter=' ' --with-nth=1 --preview 'journalctl -u $1 -n 30 --no-pager' --preview-window=down:20 \
      | awk '{print $1}'
  )
  [ -n "$svc" ] || return
  journalctl -u "$svc" -f
}

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

iph() {
  echo "$(hostname).local"
}

ipp() {
  if command -v dig &>/dev/null; then
    dig +short myip.opendns.com @resolver1.opendns.com
  else
    curl -s https://api.ipify.org; echo
  fi
}

ipl() {
  if command -v ip &>/dev/null; then
    ip -4 route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[0-9.]+'
  elif command -v ipconfig &>/dev/null; then
    ipconfig getifaddr en0 2>/dev/null
  else
    ifconfig 2>/dev/null | grep broadcast | awk '{print $2}'
  fi
}

node_admin() {
  # allows node to run on admin ports such as 80 and 443
  sudo setcap 'cap_net_bind_service=+ep' $(which node)
  echo "Changing max notify watcher from $(cat /proc/sys/fs/inotify/max_user_watches) to 524288 (max value)"
  echo "fs.inotify.max_user_watches=524288" | sudo tee -a /etc/sysctl.conf
}

alias clone="bun ~/dotfiles/advanced/clone.ts"

# List my github + gitlab repos in fzf, cd into ~/dev/<repo> or clone it there first.
# GitLab goes through glab (`glab auth login` once); --member covers projects I
# belong to, not just the ones I own. Pages past 100 are fetched until one
# comes back short.
_gitlab_repos() {
  local page=1 out
  while :; do
    out=$(glab repo list --member --per-page 100 --page "$page" --output json \
      --jq '.[] | "gitlab.com/\(.path_with_namespace)"' </dev/null 2>/dev/null) || return
    [ -z "$out" ] && return
    printf '%s\n' "$out"
    [ "$(printf '%s\n' "$out" | wc -l)" -lt 100 ] && return
    page=$((page + 1))
  done
}

repos() {
  local url="https://gitlab.com/api/v4/projects?membership=true&simple=true&per_page=100&order_by=last_activity_at"
  local auth=()
  [ -n "$GITLAB_TOKEN" ] && auth=(-H "PRIVATE-TOKEN: $GITLAB_TOKEN")
  [ -z "$GITLAB_TOKEN" ] && url="https://gitlab.com/api/v4/users/zeachco/projects?simple=true&per_page=100"
  curl -sf --max-time 10 "${auth[@]}" "$url" | jq -r '.[] | "gitlab.com/\(.path_with_namespace)"'
}

repos() {
  local dev_dir="$HOME/dev"
  local repo
  repo=$( (gh repo list --limit 500 --json nameWithOwner -q '.[] | "github.com/\(.nameWithOwner)"' & _gitlab_repos & wait) | sort | fzf )
  [ -z "$repo" ] && return 1

  # "slug", not "path": in zsh `path` is the array tied to $PATH, so `local path=`
  # emptied PATH for the rest of the function (basename/mkdir: command not found).
  local host="${repo%%/*}" slug="${repo#*/}"
  local name
  name=$(basename "$slug")
  mkdir -p "$dev_dir"

  if [ -d "$dev_dir/$name" ]; then
    cd "$dev_dir/$name" || return 1
  else
    cd "$dev_dir" || return 1
    if [ "$host" = "github.com" ]; then
      gh repo clone "$slug" || return 1
    else
      git clone "git@$host:$slug.git" || return 1
    fi
    cd "$dev_dir/$name" || return 1
    secrets
    # fresh clone: install the toolchain and fetch the env; both are allowed to fail
    mise install
    bwload
  fi

  # auto-enter devbox shell if the repo has one
  check_for_devbox
}

bwload() {
  local supported_files=(".env.example" "example.env" ".env.bw")
  local env_file="" header="" secret_cli="" item_name="" op_item=""

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

  # The provider declaration must be in one of the first three lines. Extra words
  # between the provider and quoted item name are intentionally ignored.
  header=$(head -n 3 "$env_file" | grep -E '^[[:space:]]*#[[:space:]]*(bw|pp|op)([[:space:]]+[^\"]*)?[[:space:]]+"[^"]+"' | head -n 1)
  if [ -z "$header" ]; then
    echo "No supported secret-provider declaration found in the first 3 lines of $env_file"
    echo 'Expected: # bw "Item name", # pp "Item name", or # op "Item name"'
    return 1
  fi

  secret_cli=$(printf '%s\n' "$header" | sed -E 's/^[[:space:]]*#[[:space:]]*(bw|pp|op).*/\1/')
  item_name=$(printf '%s\n' "$header" | sed -E 's/^[^\"]*"([^\"]+)".*$/\1/')

  if [ -z "$item_name" ]; then
    echo "No quoted item name found in $env_file"
    return 1
  fi

  echo "Using $env_file"
  case "$secret_cli" in
    bw)
      command -v bw >/dev/null 2>&1 || { echo "Bitwarden CLI (bw) is not installed"; return 1; }
      echo "Fetching '$item_name' from Bitwarden..."
      bw sync || return 1
      bw get notes "$item_name" >.env
      ;;
    pp)
      command -v pass-cli >/dev/null 2>&1 || { echo "Proton Pass CLI (pass-cli) is not installed"; return 1; }
      echo "Fetching '$item_name' from Proton Pass..."
      pass-cli item view --item-title "$item_name" --field note >.env
      ;;
    op)
      command -v op >/dev/null 2>&1 || { echo "1Password CLI (op) is not installed"; return 1; }
      command -v jq >/dev/null 2>&1 || { echo "jq is required for 1Password item extraction"; return 1; }
      echo "Fetching '$item_name' from 1Password..."
      op_item=$(op item get "$item_name" --fields notesPlain --reveal --format json) || return 1
      printf '%s\n' "$op_item" | jq -er '.fields[] | select(.id == "notesPlain" or .label == "notes") | .value' >.env || return 1
      ;;
  esac

  if [ $? -eq 0 ]; then
    echo ".env file created successfully"
  else
    echo "Failed to fetch '$item_name' from $secret_cli"
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

# Source AI utilities (summarize, etc.)
[[ -f "$DOT_DIR/variants/shared/_ai_tools.sh" ]] && source "$DOT_DIR/variants/shared/_ai_tools.sh"

# Source worktree and Herdr utilities
[[ -f "$DOT_DIR/variants/shared/_worktrees.sh" ]] && source "$DOT_DIR/variants/shared/_worktrees.sh"

# Source work mode toggle (default browser + Slack)
[[ -f "$DOT_DIR/variants/shared/_work.sh" ]] && source "$DOT_DIR/variants/shared/_work.sh"

# Source media streaming utilities
[[ -f "$DOT_DIR/variants/shared/_streaming.sh" ]] && source "$DOT_DIR/variants/shared/_streaming.sh"

# Source llama.cpp utilities -- _llama.sh owns the launchers and verbs, _los_menu.sh the
# `los` fzf menu that fronts them (and calls back into los-load, so order matters).
[[ -f "$DOT_DIR/llamacpp/shared/_llama.sh" ]] && source "$DOT_DIR/llamacpp/shared/_llama.sh"
[[ -f "$DOT_DIR/llamacpp/shared/_los_menu.sh" ]] && source "$DOT_DIR/llamacpp/shared/_los_menu.sh"

power() {
  upower -i /org/freedesktop/UPower/devices/battery_BAT0 | grep 'state\|percentage'
}

denode() {
  deno run -A --unstable "npm:$1"
}

# Start Plasma Bigscreen (TV shell) on a bare console. It must NOT be launched
# from inside Hyprland: Plasma's session services (plasmashell, kded6, powerdevil)
# would attach to the running desktop and draw full-page OSDs as tiled windows.
# Usage: switch to a free console (Ctrl+Alt+F2), log in, run `bigscreen`.
bigscreen() {
  if ! command -v plasma-bigscreen-wayland >/dev/null 2>&1; then
    echo "bigscreen: Plasma Bigscreen is not installed (package: plasma-bigscreen)." >&2
    return 127
  fi
  if [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ] || [ -n "${TMUX:-}" ] ||
    ! case "$(tty 2>/dev/null)" in /dev/tty[0-9]*) true ;; *) false ;; esac; then
    cat >&2 <<'MSG'
bigscreen: run this from a bare virtual console, not a terminal inside a desktop session.
  1. Press Ctrl+Alt+F2 and log in there.
  2. Run `bigscreen`.
  3. Ctrl+Alt+F1 returns to Hyprland; Ctrl+Alt+F2 returns to Bigscreen.
Launching it inside Hyprland leaks Plasma services into the desktop. If that
already happened: systemctl --user stop plasma-core.target plasma-plasmashell plasma-kded6 plasma-powerdevil plasma-ksmserver
MSG
    return 1
  fi
  local runner=/usr/lib/plasma-dbus-run-session-if-needed
  if [ -x "$runner" ]; then
    "$runner" plasma-bigscreen-wayland
  else
    plasma-bigscreen-wayland
  fi
}

if [ "${SHELL##*/}" = "zsh" ]; then
  bindkey '[C' forward-word
  bindkey '[D' backward-word
fi

# fzf key bindings (Ctrl-R history, Ctrl-T files, Alt-C dirs) and fuzzy completion.
# `fzf --bash` / `fzf --zsh` need fzf >= 0.48; older builds just print an error, so
# the output is discarded when the flag is unsupported.
if command -v fzf >/dev/null 2>&1; then
  if [ -n "$ZSH_VERSION" ]; then
    source <(fzf --zsh 2>/dev/null)
  elif [ -n "$BASH_VERSION" ]; then
    eval "$(fzf --bash 2>/dev/null)"
  fi
fi

# `herdr update` regenerates ~/.config/herdr/config.toml and drops the [keys] table
# from configs/herdr/keys.toml, so re-apply it right after a successful update.
herdr() {
  command herdr "$@"
  local rc=$?
  if [ "$1" = update ] && [ "$rc" -eq 0 ]; then
    "$DOT_DIR/bin/herdr-config" ensure-keys
  fi
  return "$rc"
}

ai() {
  opencode "$@"
}

# gemini() {
#   deno run -A --no-lock npm:@google/gemini-cli "$@"
# }

# replace normal to call hook after the command
# cd() {
#   builtin cd "$@" || return
#   check_for_devbox
# }

# Enter a devbox shell. DEVBOX_SETUP defaults to 0 so a repo's init hook skips
# its (slow) setup: with several panes on the same worktree only one of them
# should install anything. `wt` gives every workspace a throwaway `setup...`
# tab that runs `DEVBOX_SETUP=1 devbox run` once, so the setup still happens —
# the shells it opens all enter with 0. Override by hand the same way:
# `DEVBOX_SETUP=1 ds`.
ds() {
  local setup="${DEVBOX_SETUP:-0}"
  use "devbox shell"
  DEVBOX_SETUP="$setup" devbox shell "$@"
  # Nothing to enter here, so no new shell ever reached a prompt and a pending
  # DOTFILES_INIT_CMD (see the end of this file) would be dropped. Run it here.
  [ -f devbox.json ] || _dotfiles_run_init_cmd
}

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
      # auto-entered shells (cd / new pane) never own the setup — see ds()
      DEVBOX_SETUP="${DEVBOX_SETUP:-0}" devbox shell
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
# ONE-SHOT SHELL INIT COMMAND
# ==============================================================================
# A command handed to a fresh interactive shell through the environment, run
# once when that shell reaches its first prompt. `wt` uses it to open the editor
# in its edit tab: typing `e .` into the pane instead raced the shell's (and
# devbox's) startup and was regularly swallowed, while chaining it with && would
# run it in the *outer* shell, only once the devbox shell is exited.
_dotfiles_run_init_cmd() {
  [ -n "$DOTFILES_INIT_CMD" ] || return 0
  _dotfiles_init_cmd="$DOTFILES_INIT_CMD"
  # unset before running, not after: it is exported, so any shell the command
  # starts (or one nested in this one) would otherwise run it all over again
  unset DOTFILES_INIT_CMD
  eval "$_dotfiles_init_cmd"
  unset _dotfiles_init_cmd
}

case "$-" in
*i*)
  if [ -n "$ZSH_VERSION" ]; then
    autoload -Uz add-zsh-hook
    # precmd fires before every prompt; the function no-ops after the first one
    add-zsh-hook precmd _dotfiles_run_init_cmd
  elif [ -n "$BASH_VERSION" ]; then
    PROMPT_COMMAND="_dotfiles_run_init_cmd${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
  fi
  ;;
esac
