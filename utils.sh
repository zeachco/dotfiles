#!/usr/bin/env bash

DOT_DIR="$HOME/dotfiles"
USER_SOURCE_FILE=~/.profile

# colors
FAIL="\033[0;31m"
PASS="\033[0;32m"
WARN="\033[0;33m"
INFO="\033[0;34m"
NORM="\033[0m"

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
touch $USER_SOURCE_FILE

INSTALLED_PROFILES=()

function install_profile {
  variant="$1"
  profile_path="variants/$variant"

  echo -e "${INFO}check ${NORM}$variant dependencies..."
  $SHELL "$DOT_DIR/$profile_path/setup.sh"

  profile_filename="$HOME/.dotfiles_$variant"

  # Write to a temp file and mv over the old one so a shell opened mid-update
  # always sources either the old or the new profile, never nothing.
  tmp_profile="$(mktemp "$profile_filename.XXXXXX")"
  cp "$DOT_DIR/$profile_path/profile.sh" "$tmp_profile"
  mv -f "$tmp_profile" "$profile_filename"

  echo -e "${INFO}link ${NORM}$profile_filename"
  INSTALLED_PROFILES+=("$variant")
}

# Remove profiles and source hooks that this run did not install. Runs last so
# the previous profiles stay sourceable for the whole update.
function clean_imports {
  for old_file in "$HOME"/.dotfiles_*; do
    [[ -f "$old_file" ]] || continue
    variant="${old_file##*/.dotfiles_}"
    keep=false
    for installed in "${INSTALLED_PROFILES[@]}"; do
      [[ "$installed" == "$variant" ]] && keep=true
    done
    if [[ $keep == false ]]; then
      echo -e "${WARN}removing old ${NORM}$old_file"
      rm -f "$old_file"
    fi
  done

  cp -f "$USER_SOURCE_FILE" "$USER_SOURCE_FILE.backup"
  tmp_source="$(mktemp "$USER_SOURCE_FILE.XXXXXX")"
  sed '/zeachco-dotfiles/d' "$USER_SOURCE_FILE.backup" >"$tmp_source"
  for variant in "${INSTALLED_PROFILES[@]}"; do
    profile_filename="$HOME/.dotfiles_$variant"
    echo "[[ -f $profile_filename ]] && source $profile_filename # zeachco-dotfiles $variant" >>"$tmp_source"
  done
  mv -f "$tmp_source" "$USER_SOURCE_FILE"
}

function prehook {
  os="$1"
  init_script="$DOT_DIR/$os/init.sh"

  if [[ -f "$init_script" ]]; then
    echo -e "${INFO}running prehook for ${NORM}$os..."
    $SHELL "$init_script"
  else
    echo -e "${WARN}no prehook found for ${NORM}$os"
  fi
}

function print_needs {
  echo -e "${WARN}missing ${NORM}$1"
}

function print_exists {
  echo -e "${PASS}found ${NORM}$1"
}

# `exists`/`needs` print only the "missing" line on purpose: they run once per package on
# every dotfiles_update, so a "found" line each would bury the output that matters.
function exists {
  if command -v "$1" >/dev/null 2>&1; then
    return 0
  else
    print_needs $1
    return 1
  fi
}

function needs {
  if ! command -v "$1" >/dev/null 2>&1; then
    print_needs $1
    return 0
  else
    return 1
  fi
}

# NixOS: packages are installed into the user's `nix profile` (imperative, so the
# shared `install`/`install_pkg` calls keep working). System-level state (login
# shell, fonts, services) is declarative and lives in variants/nixos/dotfiles.nix.
function is_nixos() {
  [[ -f /etc/NixOS ]] || grep -q '^ID=nixos' /etc/os-release 2>/dev/null
}

# `nix profile` needs the nix-command + flakes experimental features. A stock
# NixOS install has them off, and the shared profile runs before the nixos
# variant writes them to ~/.config/nix/nix.conf, so pass the flag explicitly.
function nix_cmd() {
  nix --extra-experimental-features "nix-command flakes" "$@"
}

# `nix profile list` prints one "Name: <pkg>" line per entry (nix >= 2.20); older
# versions print the flake attribute, which ends in ".<pkg>".
function nix_profile_has() {
  nix_cmd profile list 2>/dev/null | grep -qE "^Name: +$1\$|nixpkgs#$1\$|\.$1\$"
}

# nix >= 2.26 renamed `nix profile install` to `add` and warns on the old name.
function nix_profile_install() {
  if nix_cmd profile add --help >/dev/null 2>&1; then
    nix_cmd profile add "nixpkgs#$1"
  else
    nix_cmd profile install "nixpkgs#$1"
  fi
}

# The one place that knows each manager's install verb: callers decide *whether*, this
# decides *how*. Private to utils.sh. Bash 3.2 / macOS / zsh: this file is sourced by the
# llamacpp installers and by the zsh profiles, so no arrays, no ${var,,}, no mapfile.
function _pkg_install() {
  local pkg_name="$1"

  # Check for Termux environment first
  if [[ -n "${TERMUX_VERSION:-}" ]] || [[ "${PREFIX:-}" == *"com.termux"* ]]; then
    pkg install -y "$pkg_name"
  elif is_nixos; then
    nix_profile_install "$pkg_name"
  elif command -v apt &>/dev/null; then
    sudo apt install -y "$pkg_name"
  elif command -v pacman &>/dev/null; then
    pacman_wait_lock
    sudo pacman -S "$pkg_name" --needed --noconfirm
  elif command -v brew &>/dev/null; then
    brew install "$pkg_name"
  else
    echo -e "${FAIL} I don't know how to install $pkg_name ${NORM}"
  fi
}

function install() {
  name="$1"
  pkg_name="${2:-$1}"

  if needs "$name"; then
    echo -e "${WARN}installing ${NORM}$pkg_name..."
    sleep 1
    _pkg_install "$pkg_name"
  fi
}

# Same as `install` but asks the package manager whether the package is present instead
# of looking for a command of the same name. Needed for anything that ships no binary
# (headers, libraries, plugins): `command -v vulkan-headers` can never succeed, so
# `install vulkan-headers` re-ran pacman on every dotfiles_update.
# The ladder below only asks "is it already there?" and returns 0 when it is; every other
# case falls through to the one shared install path. Unknown manager reports and stops.
function install_pkg() {
  pkg_name="$1"

  if [[ -n "${TERMUX_VERSION:-}" ]] || [[ "${PREFIX:-}" == *"com.termux"* ]]; then
    dpkg-query -W -f='${Status}' "$pkg_name" 2>/dev/null | grep -q "ok installed" && return 0
  elif is_nixos; then
    nix_profile_has "$pkg_name" && return 0
  elif command -v apt &>/dev/null; then
    dpkg-query -W -f='${Status}' "$pkg_name" 2>/dev/null | grep -q "ok installed" && return 0
  elif command -v pacman &>/dev/null; then
    pacman -Q "$pkg_name" &>/dev/null && return 0
  elif command -v brew &>/dev/null; then
    brew list "$pkg_name" &>/dev/null && return 0
  else
    echo -e "${FAIL} I don't know how to install $pkg_name ${NORM}"
    return 0
  fi

  print_needs "$pkg_name"
  echo -e "${WARN}installing ${NORM}$pkg_name..."
  _pkg_install "$pkg_name"
}

function script_install() {
  name="$1"
  exec="$2"

  if needs $name; then
    echo -e "${WARN}installing ${NORM}$name..."
    echo -e "${INFO}running ${NORM}$exec"
    eval "$exec"
  fi
}

# Create a Python venv under ~/.local/share for a bin/ runtime that needs an
# interpreter the OS does not ship. The local speech runtimes (`say`, `listen`)
# pin torch==2.5.1+cpu, whose last wheels are cp312, while Arch only ever ships
# the current Python -- so the interpreter comes from a version manager instead:
# mise (already this user's) or uv (which can fetch its own).
# Idempotent: once the venv interpreter exists the caller decides what is missing.
#   install_python_venv <name> <version>   ->  ~/.local/share/<name>/bin/python
function install_python_venv() {
  name="$1"
  version="$2"
  venv="$HOME/.local/share/$name"

  if [[ -x "$venv/bin/python" ]]; then
    return 0
  fi

  echo -e "${WARN}creating ${NORM}$venv (python$version)..."
  if command -v mise >/dev/null 2>&1; then
    mise x "python@$version" -- python -m venv "$venv"
  elif command -v uv >/dev/null 2>&1; then
    # --seed keeps pip in the venv; uv omits it by default
    uv venv --python "$version" --seed "$venv"
  elif command -v "python$version" >/dev/null 2>&1; then
    "python$version" -m venv "$venv"
  else
    echo -e "${FAIL}no way to get python$version: install mise or uv first${NORM}"
    return 1
  fi
}

function ensure_current_theme() {
  local package="$1"
  local current_theme="$DOT_DIR/themes/current"
  local default_theme="$DOT_DIR/themes/catppuccin-latte"

  if [[ ! -d "$current_theme" ]]; then
    mkdir -p "$DOT_DIR/themes"
    cp -R "$default_theme" "$current_theme"
  fi

  case "$package" in
  nvim)
    local colorscheme
    colorscheme=$(sed -n 's/^[[:space:]]*colorscheme = "\([^"]*\)".*/\1/p' "$current_theme/neovim.lua" | tail -n 1)
    if [[ -n "$colorscheme" ]]; then
      [[ -f "$DOT_DIR/configs/nvim/.config/nvim/theme-light" ]] || printf '%s\n' "$colorscheme" >"$DOT_DIR/configs/nvim/.config/nvim/theme-light"
      [[ -f "$DOT_DIR/configs/nvim/.config/nvim/theme-dark" ]] || printf '%s\n' "$colorscheme" >"$DOT_DIR/configs/nvim/.config/nvim/theme-dark"
    fi
    ;;
  esac
}

# Make $1 a real directory before stowing the package that owns it. When a
# target is missing, Stow "folds" it: one link to the package directory instead
# of a directory of links. That is wrong for the harness homes (~/.claude,
# ~/.codex, ~/.pi/agent hold sessions and credentials) and for their skills
# directories: Claude Code writes .trash/ and synced/ there, Codex its .system/
# bundle, omarchy links its own skills in, railway installs use-railway per box.
# With the directory in place Stow links each tracked entry on its own (one
# link per shared skill) and the machine-local ones stay beside them, out of
# the repo. A folded link left by an earlier layout is replaced; anything
# gitignored that landed in the repo through it has to be moved out by hand.
function unfold_dir() {
  local dir=$1
  [[ -L "$dir" ]] && rm -f "$dir"
  mkdir -p "$dir"
}

function stow_link() {
  local pkg=$1

  install stow
  ensure_current_theme "$pkg"

  echo -e "${INFO}stowing ${NORM}$pkg..."
  cd "$DOT_DIR/configs"
  # Remove any regular files that would conflict with stow symlinks
  stow --target="$HOME" --simulate --restow "$pkg" 2>&1 |
    sed -n \
      -e 's/.*cannot stow.*target \([^ ]*\) since.*/\1/p' \
      -e 's/.*existing target is not owned by stow: \(.*\)/\1/p' \
      -e 's/.*existing target is stowed to a different package: \([^ ]*\) =>.*/\1/p' |
    while read -r target; do
      if [[ -n "$target" ]]; then
        if [[ -L "$HOME/$target" || -f "$HOME/$target" ]]; then
          rm -f "$HOME/$target"
        elif [[ -d "$HOME/$target" ]]; then
          rm -rf "$HOME/$target"
        fi
      fi
    done
  # Use regular stow since we've already removed conflicts
  stow --target="$HOME" "$pkg" 2>&1 || stow --target="$HOME" --restow "$pkg"
}

# Alacritty live-reloads its config (live_config_reload defaults to true), and a
# dotfiles run rewrites that config underneath any running terminal. The churn is
# unavoidable: ~/.config/alacritty/look.toml is owned by *two* Stow packages --
# the shared `alacritty` one (window padding only) and the per-OS
# `alacritty-<os>` one (which is where the Nerd Font family is set) -- so
# stow_link deletes and relinks it on every run. Alacritty debounces the whole
# burst of Stow events into a single reload, which can land while look.toml
# still points at the fontless shared copy. The terminal then falls back to
# Menlo, every Nerd Font glyph turns into a box in nvim's file tree, and it
# stays that way until Alacritty is restarted -- the later os.toml rewrite is
# inside the same debounce window and does not wake the watcher again.
#
# Bumping the mtimes once everything has settled forces one final reload against
# the correct files. Called at the end of a variant's setup, after the last write.
function nudge_alacritty_reload() {
  local dir="$HOME/.config/alacritty"
  [[ -d "$dir" ]] || return 0
  # find rather than a glob: these setup scripts are run through $SHELL, so on a
  # zsh box an unmatched *.toml would abort the function instead of expanding to
  # nothing. touch follows the Stow symlinks and bumps the repo file's mtime,
  # which is what Alacritty's watcher is looking at.
  find "$dir" -maxdepth 1 -name '*.toml' -exec touch {} + 2>/dev/null
  echo -e "${INFO}reloaded ${NORM}alacritty config"
  return 0
}

# ---- pi's startup model, per box ----------------------------------------------------
# pi has ONE global settings.json (~/.pi/agent/settings.json, Stow-linked to the tracked
# configs/pi copy), but its startup model differs per box: the Mac's own router does not
# serve Qwen3.8-Flash-Next, so a Mac opens on the Strix Halo box (oli-llms.local), which
# models.json registers as the `llamacpp-remote` provider, while the LLM box opens on its
# own `llamacpp`. Like Claude Code's "model" key, `defaultProvider`/`defaultModel` are
# machine state inside an otherwise tracked file, so a clean filter strips them in git
# (filter.pi-settings, registered in variants/shared/setup.sh) and each variant states its
# own pick here. pi rewrites this same file itself (/model -> Ctrl+S, /settings, its
# package list), so patching it in place is normal; the variant re-applies the pick on
# every run, which is also what restores it after a `git checkout` clobbers the file.
#
# Idempotent, and it never invents a value: empty args fail instead of writing nulls.
# Writes the repo path, which is the live file's Stow symlink target, so the link itself is
# never replaced by a copy.
function pi_set_default_model() {
  local provider="${1:-}" model="${2:-}"
  local file="$DOT_DIR/configs/pi/.pi/agent/settings.json"

  if [[ -z "$provider" || -z "$model" ]]; then
    echo -e "${FAIL}pi_set_default_model: need a provider and a model${NORM}"
    return 1
  fi
  if [[ ! -f "$file" ]]; then
    echo -e "${FAIL}no pi settings.json at $file${NORM}"
    return 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo -e "${FAIL}jq is required to set pi's default model${NORM}"
    return 1
  fi

  if [[ "$(jq -r '[.defaultProvider, .defaultModel] | @tsv' "$file" 2>/dev/null)" == "$provider"$'\t'"$model" ]]; then
    echo -e "${INFO}pi default${NORM}  $provider/$model"
    return 0
  fi

  # Soft check only: models.json is machine state and a provider can legitimately be
  # empty for a moment (llamacpp-discover empties one whose port refuses connections),
  # and a default that is not resident still resolves once the router answers.
  local models="$DOT_DIR/configs/pi/.pi/agent/models.json"
  if [[ -f "$models" ]] && ! jq -e --arg p "$provider" '.providers[$p] // empty' "$models" >/dev/null 2>&1; then
    echo -e "${WARN}pi has no '$provider' provider in models.json; the default will not resolve until it does${NORM}"
  fi

  local tmp status=1
  tmp="$(mktemp)"
  # jq keeps existing key order, so the two keys stay where they were.
  if jq --arg p "$provider" --arg m "$model" \
       '.defaultProvider = $p | .defaultModel = $m' "$file" >"$tmp"; then
    # printf, not cp: jq always terminates its output, and the file has no trailing
    # newline -- copying jq's would churn the file (and the diff) on every run.
    printf '%s' "$(cat "$tmp")" >"$file" && status=0
  fi
  rm -f "$tmp"

  if (( status == 0 )); then
    echo -e "${INFO}set ${NORM}pi default model $provider/$model"
  else
    echo -e "${FAIL}could not write $file${NORM}"
  fi
  return "$status"
}

# ---- OS detection shared by setup.sh and bin/dotfiles-job --------------------------
# Prints the variant name (osx | nixos | archlinux | termux) or nothing for a Linux
# with no OS-specific profile. Same rules as the big picture in docs/ARCHITECTURE.md.
function dotfiles_variant {
  # ${var:-} because bin/dotfiles-job runs under set -u.
  if [[ -n "${TERMUX_VERSION:-}" ]] || [[ "${PREFIX:-}" == *"com.termux"* ]]; then
    echo termux
    return
  fi
  case "$(uname -s)" in
  Darwin*) echo osx ;;
  Linux*)
    if [[ -f /etc/NixOS ]] || grep -q '^ID=nixos' /etc/os-release 2>/dev/null; then
      echo nixos
    elif [[ -f /etc/arch-release ]] || command -v pacman &>/dev/null; then
      echo archlinux
    fi
    ;;
  esac
}

# ---- system update ----------------------------------------------------------------
# Full OS package upgrade. One function so the Arch variant and the parallel
# `sysupdate` job (bin/dotfiles-job) run exactly the same thing.
function system_update {
  echo -e "${WARN}updating system packages...${NORM}"
  if command -v omarchy &>/dev/null; then
    # Omarchy handles its own privilege escalation; -y runs unattended like --noconfirm
    omarchy update -y
  elif command -v pacman &>/dev/null; then
    sudo pacman -Syu --noconfirm
  else
    echo -e "${INFO}no system update step for this OS${NORM}"
  fi
}

# pacman takes one database lock. When the sysupdate job runs next to the profile
# job (herdr_fan_out) every `install` would otherwise die with "unable to lock
# database", so wait for the lock to clear first. A stale lock from a crashed pacman
# is reported, not removed -- that is a decision for a human.
function pacman_wait_lock {
  local lock=/var/lib/pacman/db.lck waited=0
  while [[ -e "$lock" ]]; do
    if ((waited == 0)); then
      echo -e "${INFO}waiting ${NORM}for pacman ($lock held by another process)..."
    fi
    sleep 5
    waited=$((waited + 5))
    if ((waited >= 3600)); then
      echo -e "${FAIL}$lock still held after 1h; remove it by hand if pacman is not running${NORM}"
      return 1
    fi
  done
}

# ---- parallel update inside Herdr ----------------------------------------------------
# When setup.sh runs in a Herdr pane, the long steps run side by side, one Herdr
# workspace each (bin/dotfiles-job): the system update, the llama.cpp rebuild, the
# model download (local-LLM boxes only) and the profile installation. Each job writes
# <rc-dir>/<job>.rc when it exits; this polls those files, prints a summary, closes the
# workspaces of the jobs that passed and leaves a failed one open so its output can be read.
# Returns non-zero when any job failed, and 1 immediately when a workspace disappears
# (closed by hand).
#
# The model download is the one step that needs a human yes, and a question printed inside
# an unfocused workspace is a question nobody sees -- it would just time out after
# LOS_FETCH_TIMEOUT (5 min) and close, leaving "done models" as the only trace. So
# herdr_fan_out asks about models itself, in the pane the operator is watching
# (`bin/llamacpp-fetch-missing --ask`), and only launches the workspace when the answer is
# yes, with LOS_FETCH_YES=1 in the command string (the pane's environment comes from the
# Herdr server, so nothing exported here reaches it). Declined = no workspace at all.
#
# Opt out with DOTFILES_PARALLEL=0. Never recurses: the profile job runs setup.sh
# with DOTFILES_JOB set, which herdr_fan_out_available refuses.
function herdr_fan_out_available {
  [[ "${DOTFILES_PARALLEL:-1}" != "0" ]] || return 1
  [[ -z "${DOTFILES_JOB:-}" ]] || return 1
  [[ "${HERDR_ENV:-}" = 1 ]] || return 1
  command -v herdr &>/dev/null && command -v jq &>/dev/null || return 1
  herdr status server &>/dev/null
}

# The models job only makes sense where llamacpp/shared/_hw-gate.sh says local models
# run at all; elsewhere it would open a workspace just to say so. Sourced in a
# subshell so the gate's helpers do not leak into the profile.
function herdr_models_job_wanted {
  (
    . "$DOT_DIR/llamacpp/shared/_hw-gate.sh"
    is_ryzen_ai_max || is_apple_silicon
  )
}

# Open a workspace for one job and start bin/dotfiles-job in it. Records the ids in the
# caller's ws_of/pane_of (dynamic scope: the arrays are declared in herdr_fan_out, which is
# the only caller). $3 is an env prefix for the command -- the only way to hand a variable
# to a pane, since the pane inherits the Herdr server's environment, not this shell's.
function herdr_start_job {
  local job="$1" rc_dir="$2" prefix="${3:-}" result ws pane
  result=$(herdr workspace create --cwd "$DOT_DIR" --label "dotfiles: $job" --no-focus) || {
    echo -e "${FAIL}herdr workspace create failed for $job${NORM}"
    return 1
  }
  ws=$(echo "$result" | jq -r '.result.workspace.workspace_id')
  pane=$(echo "$result" | jq -r '.result.root_pane.pane_id')
  ws_of[$job]="$ws"
  pane_of[$job]="$pane"
  herdr pane run "$pane" "${prefix}bash '$DOT_DIR/bin/dotfiles-job' $job '$rc_dir'" >/dev/null || {
    echo -e "${FAIL}herdr pane run failed for $job${NORM}"
    return 1
  }
  echo -e "  ${INFO}$job${NORM} -> workspace $ws"
}

function herdr_fan_out {
  local variant jobs=() job rc_dir ask_rc env_prefix
  variant="$(dotfiles_variant)"
  [[ "$variant" == archlinux ]] && jobs+=(sysupdate)
  [[ -n "$variant" && -f "$DOT_DIR/llamacpp/$variant/setup.sh" ]] && jobs+=(llamacpp)
  jobs+=(profile)

  rc_dir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-update.XXXXXX")"
  declare -A ws_of pane_of
  echo -e "${INFO}herdr ${NORM}running in parallel: ${jobs[*]}"
  for job in "${jobs[@]}"; do
    herdr_start_job "$job" "$rc_dir" || return 1
  done

  # Asked after the jobs above are running, so a slow answer never delays them; the model
  # download itself is the longest step anyway. Exit codes: 0 fetch, 10 declined or
  # unanswered, anything else = the plan pass failed (see the script's header).
  if [[ "${DOTFILES_SKIP_MODELS:-}" != 1 ]] && herdr_models_job_wanted; then
    echo -e "${INFO}models ${NORM}checking ~/models..."
    bash "$DOT_DIR/bin/llamacpp-fetch-missing" --ask --select-out "$rc_dir/models.select"
    ask_rc=$?
    case "$ask_rc" in
      0) jobs+=(models) ;;
      10) echo -e "  ${WARN}models${NORM} not downloading (declined or no answer); retry with: bash $DOT_DIR/bin/llamacpp-fetch-missing" ;;
      *) echo -e "  ${WARN}models${NORM} could not check ~/models (rc $ask_rc); not downloading" ;;
    esac
  fi
  if [[ " ${jobs[*]} " == *" models "* ]]; then
    env_prefix="LOS_FETCH_YES=1 "
    # Only when the picker actually wrote rows: a LOS_FETCH_SELECT that points at nothing
    # selects zero files, which would fetch nothing and call it a success.
    [[ -s "$rc_dir/models.select" ]] && env_prefix="${env_prefix}LOS_FETCH_SELECT='$rc_dir/models.select' "
    herdr_start_job models "$rc_dir" "$env_prefix" || return 1
  fi

  local pending=("${jobs[@]}") still=() failed=()
  while ((${#pending[@]})); do
    still=()
    for job in "${pending[@]}"; do
      if [[ -f "$rc_dir/$job.rc" ]]; then
        rc=$(<"$rc_dir/$job.rc")
        if [[ "$rc" == 0 ]]; then
          echo -e "${PASS}done ${NORM}$job"
          # A successful models job closes right away, and it is the one job whose output
          # says what actually landed -- print the tail before the pane goes.
          [[ "$job" == models ]] &&
            herdr pane read "${pane_of[$job]}" --source recent-unwrapped --lines 6 2>/dev/null | sed 's/^/    /'
          herdr workspace close "${ws_of[$job]}" >/dev/null
        else
          echo -e "${FAIL}failed ${NORM}$job (rc $rc), workspace ${ws_of[$job]} left open:"
          herdr pane read "${pane_of[$job]}" --source recent-unwrapped --lines 15 2>/dev/null | sed 's/^/    /'
          echo
          failed+=("$job")
        fi
      elif ! herdr workspace get "${ws_of[$job]}" &>/dev/null; then
        echo -e "${FAIL}workspace for $job was closed before it finished${NORM}"
        failed+=("$job")
      else
        still+=("$job")
      fi
    done
    pending=("${still[@]}")
    ((${#pending[@]})) && sleep 3
  done
  rm -rf "$rc_dir"

  if ((${#failed[@]})); then
    echo -e "${FAIL}update finished with failures: ${failed[*]}${NORM}"
    return 1
  fi
  echo -e "${PASS}all parallel jobs done${NORM}"
}
