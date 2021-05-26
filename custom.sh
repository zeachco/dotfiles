#!/bin/bash
# alias wtest="yarn sewing-kit test --no-graphql"
# https://github.com/Shopify/sewing-kit/blob/master/docs/commands.md

function gcommits() {
  if [ -z $1 ];
  then git log --format="%C(auto)%h (%s, %ad)" -n 20 | cat;
  else git log --format="%H" -n $1 | cat;
  fi
}

_wrap gba "git branch -a"
_wrap gpaa "git add . --all && git commit --amend --no-edit && git push origin --force-with-lease"
_wrap grbi "git rebase upstream/master -i"
_wrap gph "git push heroku master"
_wrap gaa "git add -A"
_wrap gd "git diff"
_wrap gs "git status"
_wrap gco "git checkout"
_wrap gcp "git cherry-pick"
_wrap gci "git commit"
_wrap gcia "git commit --amend --no-edit"
_wrap grb "git rebase -i"
_wrap gp "git pull"
_wrap gpp "git push origin"
_wrap gfa "git fetch --all"
_wrap gfu "git fetch upstream"
_wrap grh "git reset --hard"
_wrap gmt "git mergetool"
_wrap gl "git log --oneline --graph"
_wrap shipit "npm run deploy"
_wrap gpft "git push --follow-tags"
_wrap npmv "npm version $1 && git push --follow-tags && npm publish"
_wrap gif "~/scripts/gif"
_wrap hosts "sudo vim /etc/hosts && sudo /etc/init.d/dns-clean restart && sudo /etc/init.d/networking restart"
_wrap amisafe "ps auxwww | grep sshd"
_wrap empty-trash "rm -rf ~/.local/share/Trash/*"
_wrap v "nvim"