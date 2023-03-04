#!/bin/env bash

DOT_DIR=~/dotfiles
PROFILE_TARGET=~/.zshrc

function _add_zsh_variant {
  local variant=$1
  local profile_filename="$HOME/.zsh_$variant"

  local filename="example.txt"
  local line="[[ -f $profile_filename ]] && source $profile_filename # zeachco-dotfiles $variant"

  cp "$DOT_DIR/$variant/profile.sh" "$profile_filename"

  if grep -Fxq "$line" "$profile_filename"; then
    echo "The line '$line' already exists in $profile_filename."
  else
    echo "The line '$line' does not exist in $profile_filename."
    echo "\n[[ -f $profile_filename  ]] && source $profile_filename # zeachco-dotfiles $variant" >> $PROFILE_TARGET
  fi
}

function install_profile {
    echo "Installing $1 dependencies..."
    zsh "$DOT_DIR/$1/setup.sh"
    echo "done."
}

function clean_imports {
  cp -f $PROFILE_TARGET "$PROFILE_TARGET.backup"
  sed '/zeachco-dotfiles/d' "$PROFILE_TARGET.backup" > $PROFILE_TARGET
}
