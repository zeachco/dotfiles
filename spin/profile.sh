#!/bin/env bash

alias wtest="yarn test --no-graphql"
alias c="bin/rails c"

onboarding() {
  rake business_platform:profile_assessment_platform_tophat:setup_$1
}

spin_reset_project() {
    local branch=${1:-"main"}
    stop && git fetch --all && git rebase origin/$branch && update && start
}

ssb() {
    STORYBOOK_FOCUS=app/org-admin/Internal/sections/OrganizationIdentity/**/*.stories.@(mdx|tsx)
    yarn storybook
}
