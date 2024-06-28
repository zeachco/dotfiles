#!/bin/env sh
source ~/dotfiles/utils.sh

script_install omakub "wget -qO- https://omakub.org/install | $SHELL"

install neofetch

# tools
install unzip
install tmux
install ifconfig net-tools
install dig dnsutils
install curl
install htop
install g++
install make
install gh github-cli
install peek
script_install ollama "curl -fsS https://ollama.com/install.sh | $SHELL"
mise up