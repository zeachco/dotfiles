#!/bin/env bash

xcode_kill() {
  sudo rm -rf $(xcode-select -print-path)
  xcode-select --install
}

function _set () {
  alias $1="echo -e \" ~ \033[0;34m$2\033[0m\" && $2"
}

_set bank "spin up ~/sbanking.yml --wait"


function refresh_web_deps() {
  session_name="banking_refresh"

  tmux new-session -d -s $session_name
  tmux split-window -h

  tmux send-keys -t $session_name:1.1 'cd ../shopify && git fetch --all && git reset --hard origin/main && update' C-m
  tmux send-keys -t $session_name:1.2 'cd ../banking && git fetch --all && git reset --hard origin/main && update' C-m

  tmux attach-session -t $session_name

  wait

  # Kill the session
  tmux kill-session -t $session_name

  cd ../web && git fetch --all && git rebase origin/main && update
}
