#!/bin/env bash

alias wtest="yarn test --no-graphql"
alias c="bin/rails c"

onboarding() {
  rake business_platform:profile_assessment_platform_tophat:setup_sp_$1
}

git-update() {
    stop && git fetch --all && git rebase origin/master && update && start
}

ssb() {
    STORYBOOK_FOCUS=app/org-admin/Internal/sections/OrganizationIdentity/**/*.stories.@(mdx|tsx)
    yarn storybook
}
