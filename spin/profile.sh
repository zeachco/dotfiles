#!/bin/env bash

alias wtest="yarn test --no-graphql"
alias c="bin/rails c"

# Usage: onboarding [country_product]
onboarding() {
  rake business_platform:profile_assessment_platform_tophat:setup_$1
}

# Usage: ssb [section]
# Short for "start storybook"
ssb() {
    local section=${1:-"Banking"}
    STORYBOOK_FOCUS=app/org-admin/Internal/sections/$section/**/*.stories.@(mdx|tsx)
    yarn storybook
}

# Usage: web_rebase_update [core_branch] [banking_branch]
function web_rebase_update() {
  local core_branch=${1:-"main"}
  local banking_branch=${2:-"main"}
  local session_name="web_rebase_update"

  tmux new-session -d -s $session_name
  tmux split-window -h
  tmux split-window -h

  tmux send-keys -t $session_name:1.1 "cd ../shopify && git fetch --all && stop && git reset --hard origin/$core_branch && update && exit 0" C-m
  tmux send-keys -t $session_name:1.2 "cd ../banking && git fetch --all && stop && git reset --hard origin/$banking_branch && update && exit 0" C-m
  tmux send-keys -t $session_name:1.3 "cd ../web && git fetch --all && stop && git rebase origin/main && exit 0" C-m

  tmux attach-session -t $session_name

  wait

  tmux kill-session -t $session_name
  cd ../web && update
}
