#!/bin/env bash

alias wtest="yarn test --no-graphql"
alias c="bin/rails c"

git-update() {
    stop && git fetch --all && git rebase origin/master && update && start
}

ssb() {
    STORYBOOK_FOCUS=app/org-admin/Internal/sections/OrganizationIdentity/**/*.stories.@(mdx|tsx)
    yarn storybook
}
