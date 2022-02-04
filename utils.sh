#!/bin/env bash

DOT_DIR=~/dotfiles

function _add_zsh_variant {
  variant=$1
  profile_filename="$HOME/.zsh_$variant"
  cp "$DOT_DIR/$variant/profile.sh" "$profile_filename"
  echo "# Read the $variant profile" >> ~/.zshrc
  echo "[[ -f $profile_filename  ]] && source $profile_filename" >> ~/.zshrc
}