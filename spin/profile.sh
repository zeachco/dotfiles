#!/bin/env bash

vscode_setup() {
    code-server --install-extension eamodio.gitlens
    code-server --install-extension fbosch.battery-indicator
    code-server --install-extension rid9.datetime
}

alias wtest="yarn test --no-graphql"
alias c="bin/rails c"