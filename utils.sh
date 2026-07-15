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

function install_profile {
  variant="$1"
  profile_path="variants/$variant"

  echo -e "${INFO}check ${NORM}$variant dependencies..."
  $SHELL "$DOT_DIR/$profile_path/setup.sh"

  profile_filename="$HOME/.dotfiles_$variant"

  hook="[[ -f $profile_filename ]] && source $profile_filename # zeachco-dotfiles $variant"

  cp "$DOT_DIR/$profile_path/profile.sh" "$profile_filename"

  echo -e "${INFO}link ${NORM}$profile_filename"
  echo "$hook" >>$USER_SOURCE_FILE
}

function clean_imports {
  cp -f $USER_SOURCE_FILE "$USER_SOURCE_FILE.backup"
  sed '/zeachco-dotfiles/d' "$USER_SOURCE_FILE.backup" >$USER_SOURCE_FILE
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

function exists {
  if command -v "$1" >/dev/null 2>&1; then
    # print_exists $1
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
    # print_exists $1
    return 1
  fi
}

function install() {
  name="$1"
  pkg_name="${2:-$1}"

  if needs $name; then
    echo -e "${WARN}installing ${NORM}$pkg_name..."
    sleep 1
    # Check for Termux environment first
    if [[ -n "$TERMUX_VERSION" ]] || [[ "$PREFIX" == *"com.termux"* ]]; then
      pkg install -y $pkg_name
    elif command -v apt &>/dev/null; then
      sudo apt install -y $pkg_name
    elif command -v pacman &>/dev/null; then
      sudo pacman -S $pkg_name --noconfirm
    elif command -v brew &>/dev/null; then
      brew install $pkg_name
    else
      echo -e "${FAIL} I don't know how to install $pkg_name ${NORM}"
    fi
  fi
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

function ensure_current_theme() {
  local package="$1"
  local current_theme="$DOT_DIR/themes/current"
  local default_theme="$DOT_DIR/themes/catppuccin-latte"

  if [[ ! -d "$current_theme" ]]; then
    mkdir -p "$DOT_DIR/themes"
    cp -R "$default_theme" "$current_theme"
  fi

  case "$package" in
  zellij | zellij-omarchy)
    local zellij_theme_dir="$DOT_DIR/configs/$package/.config/zellij/themes"
    mkdir -p "$zellij_theme_dir"
    if [[ ! -f "$zellij_theme_dir/current.kdl" ]]; then
      sed 's/themes {$/themes {\n  current {/; /^  [a-z-]* {$/d' \
        "$current_theme/zellij.kdl" >"$zellij_theme_dir/current.kdl"
    fi
    ;;
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
