#!/bin/env bash
alias c="bin/rails c"

# Usage: onboarding [country_product]
onboarding() {
  rake business_platform:profile_assessment_platform_tophat:setup_$1
}

# Usage: web_rebase_update [core_branch] [banking_branch] [setup command]
function web_rebase_update() {
  local spin_version=`cat /etc/spin/metadata/isospin_version`

  local core_branch=${1:-"main"}
  local banking_branch=${2:-"main"}
  local setup_cmd

  if [[ $spin_version == "2" ]]; then
    setup_cmd="dev refresh"
  else
    setup_cmd="update"
  fi
  echo "Using setup command: $setup_cmd"

  local session_name="web_rebase_update"

  tmux new-session -d -s $session_name
  tmux split-window -h
  tmux split-window -h

  tmux send-keys -t $session_name:1.1 "cd ../shopify && git fetch --all && git reset --hard origin/$core_branch && $setup_cmd && exit 0" C-m
  tmux send-keys -t $session_name:1.2 "cd ../banking && git fetch --all && git reset --hard origin/$banking_branch && $setup_cmd && exit 0" C-m
  tmux send-keys -t $session_name:1.3 "cd ../web && git fetch --all && git rebase origin/main && exit 0" C-m

  tmux attach-session -t $session_name

  wait

  tmux kill-session -t $session_name
  cd ../web && $setup_cmd --full
}
