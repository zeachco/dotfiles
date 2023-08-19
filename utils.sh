#!/bin/env bash

DOT_DIR=~/dotfiles
PROFILE_TARGET=~/.zshrc

# colors
FAIL="\033[0;31m"
PASS="\033[0;32m"
WARN="\033[0;33m"
INFO="\033[0;34m"
NORM="\033[0m"

function install_profile {
  echo -e "${INFO}check ${NORM}$1 dependencies..."
  sh "$DOT_DIR/$1/setup.sh"


  local variant=$1
  local profile_filename="$HOME/.zsh_$variant"

  local hook="[[ -f $profile_filename ]] && source $profile_filename # zeachco-dotfiles $variant"

  cp "$DOT_DIR/$variant/profile.sh" "$profile_filename"

  echo -e "${INFO}link ${NORM}$profile_filename"
  echo "$hook" >> $PROFILE_TARGET
}

function clean_imports {
  cp -f $PROFILE_TARGET "$PROFILE_TARGET.backup"
  sed '/zeachco-dotfiles/d' "$PROFILE_TARGET.backup" > $PROFILE_TARGET
}

function print_needs {
  echo -e "${WARN}missing ${NORM}$1"
}

function print_exists {
  echo -e "${PASS}found ${NORM}$1"
}

function exists {
  if command -v "$1" >/dev/null 2>&1
  then
    print_exists $1
    return 0
  else
    print_needs $1
    return 1
  fi
}

function needs {
  if ! command -v "$1" >/dev/null 2>&1
  then
    print_needs $1
    return 0
  else
    print_exists $1
    return 1
  fi
}

function install() {
  local name="$1"
  local pkg_name="${2:-$1}"

  if needs $name
  then
    echo -e "${WARN}installing ${NORM}$pkg_name..."
    if command -v apt &> /dev/null
    then
        sudo apt install -y $pkg_name
    else
        if command -v pacman &> /dev/null
        then
            sudo pacman -S $pkg_name --noconfirm
        else
            echo -e "${FAIL} I don't know how to install $pkg_name ${NORM}"
        fi
    fi
  fi
}

function script_install() {
  local name="$1"
  local exec="$2"

  if needs $name
  then
    echo -e "${WARN}installing ${NORM}$name..."
    echo -e "${INFO}running ${NORM}$exec"
    eval "$exec"
  fi
}
