#!/bin/env bash
source ~/dotfiles/utils.sh

_add_zsh_variant spin

code-server --install-extension eamodio.gitlens
code-server --install-extension fbosch.battery-indicator
code-server --install-extension rid9.datetime