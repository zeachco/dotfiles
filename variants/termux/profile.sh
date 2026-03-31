#!/bin/sh

export EDITOR="nvim"
export SUDO_EDITOR="$EDITOR"

DOT_DIR="$HOME/dotfiles"
dotfiles_update() {
    cd $DOT_DIR || exit 1
    git fetch
    git reset --hard origin/main
    cd - || exit 1

    $SHELL "$DOT_DIR/setup.sh"
}

alias update_dotfiles="dotfiles_update"

gcommits() {
    if [ -z "$1" ];
    then git log --format="%C(auto)%h (%s, %ad)" -n 20 | cat;
    else git log --format="%H" -n $1 | cat;
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
_set gpft "git push --follow-tags"
_set v "nvim"
_set e "nvim"
_set pr "gh pr checkout $1"
_set lg "lazygit"

# Termux-specific aliases
_set termux-setup "termux-setup-storage"
_set pkg-update "pkg update && pkg upgrade"
_set pkg-search "pkg search"
_set pkg-info "pkg show"

killport() {
  if [ -z "$1" ]; then
    echo "Usage: killport <port_number>"
    return 1
  fi
  
  # Find processes using the port using ss command (more reliable on Android)
  if command -v ss >/dev/null 2>&1; then
    pids=$(ss -tlnp | grep ":$1 " | sed 's/.*pid=\([0-9]*\).*/\1/' | sort -u)
  else
    # Fallback: search through /proc for listening processes
    pids=$(grep -l ":$(printf '%04X' $1) " /proc/net/tcp* 2>/dev/null | xargs cat | awk '{print $10}' | cut -d: -f1 | sort -u)
  fi
  
  if [ -n "$pids" ]; then
    echo "Killing processes on port $1: $pids"
    echo "$pids" | xargs kill -9 2>/dev/null
  else
    echo "No processes found listening on port $1"
  fi
}

killname() {
    for pid in $(ps -e | grep "$1" | awk '{print $1}'); do
        process_name=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
        echo "Are you sure you want to kill process $pid ($process_name)? [y/N]"
        read response
        if echo "$response" | grep -q '^[yY]\([eE][sS]\)\?$'; then
            kill -9 "$pid"
            echo "Killed process $pid ($process_name)"
        else
            echo "Skipped process $pid ($process_name)"
        fi
    done
}

ipp () {
    # Get external IP address
    curl -s ifconfig.me || curl -s icanhazip.com || curl -s ipecho.net/plain
}

ipl () {
    # Get local IP address - Android/Termux compatible
    if command -v ifconfig >/dev/null 2>&1; then
        ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}'
    else
        # Fallback method
        hostname -I 2>/dev/null | awk '{print $1}' || echo "Unable to determine local IP"
    fi
}

# Termux-specific functions
termux-backup() {
    echo "Creating backup of Termux configuration..."
    tar -czf ~/termux-backup-$(date +%Y%m%d).tar.gz ~/.termux ~/dotfiles ~/.config
    echo "Backup created: ~/termux-backup-$(date +%Y%m%d).tar.gz"
}

# Android-specific battery info
battery() {
    if command -v termux-battery-status >/dev/null 2>&1; then
        # Pretty format the JSON output
        termux-battery-status | jq -r '"Battery: \(.percentage)% (\(.status)) - Health: \(.health) - Temp: \(.temperature)°C"' 2>/dev/null || termux-battery-status
    else
        echo "termux-api not installed. Install with: pkg install termux-api"
        echo "Also install Termux:API app from F-Droid for full functionality"
    fi
}

# Notification function for Android
notify() {
    if command -v termux-notification >/dev/null 2>&1; then
        # Check if Termux:API app is properly installed
        if termux-notification --title "Terminal" --content "$1" 2>/dev/null; then
            echo "Notification sent: $1"
        else
            echo "Install Termux:API app from F-Droid for notifications"
            echo "Message: $1"
        fi
    else
        echo "termux-api not installed. Install with: pkg install termux-api"
        echo "Message: $1"
    fi
}

# Enhanced cd with devbox check (Android compatible)
cd() {
  builtin cd "$@" || return
  check_for_devbox
}

check_for_devbox() {
  if [ -f "devbox.json" ]; then
    if [ -n "$DEVBOX_WORKING_DIR" ] && [ "$DEVBOX_WORKING_DIR" != "$(pwd)" ]; then
      echo "DEVBOX_WORKING_DIR is set to '$DEVBOX_WORKING_DIR' but the current directory is '$(pwd)'. Please exit and run the shell again from the correct directory."
    elif [ -z "$DEVBOX_WORKING_DIR" ]; then
      echo "Found devbox.json. Entering devbox shell..."
      which devbox > /dev/null || curl -fsSL https://get.jetify.com/devbox | bash
      export DEVBOX_WORKING_DIR="$(pwd)"
      devbox shell
    fi
  fi
}
