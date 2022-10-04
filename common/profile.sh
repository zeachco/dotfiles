#/bin/env bash

DOT_DIR=~/dotfiles
function dotfiles_update {
    cd $DOT_DIR
    git fetch
    git reset --hard origin/main
    cd -
    zsh "$DOT_DIR/setup.sh"
}

function gcommits() {
  if [ -z $1 ];
  then git log --format="%C(auto)%h (%s, %ad)" -n 20 | cat;
  else git log --format="%H" -n $1 | cat;
  fi
}

function _wrap () {
  alias $1="echo \" ~ $2\" && $2"
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
_wrap grho 'git reset --hard origin/$(git branch --show-current)'
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
_wrap e "lvim"

# Kill all processes that match the given name. ie: `killname webpack` will kill all running webpack instances
killname() {
  sudo kill -9 $(ps -e | grep $1 | awk '{print $1}')
}

ipp () {
  dig +short myip.opendns.com @resolver1.opendns.com
}

ipl () {
  ifconfig | grep broadcast | awk '{print $2}'
}

node_admin() {
  # allows node to run on admin ports such as 80 and 443
  sudo setcap 'cap_net_bind_service=+ep' `which node`
  echo "Changing max notify watcher from $(cat /proc/sys/fs/inotify/max_user_watches) to 524288 (max value)"
  echo "fs.inotify.max_user_watches=524288" | sudo tee -a  /etc/sysctl.conf
}

clone () {
  git clone git@github.com:$1.git
}

tableflip() {
  echo "(╯°□°)╯︵ ┻━┻";
  spin destroy --all
  spin login
  spin up business-platform --wait
  spin code
  say "`node -e "n=new Date,f=t=>Math.abs(Math.round((t)/60000)),e=new Date(n.toLocaleString().split(', ')[0]+', 17:00:00'),o=console.log('code is open.'+n>e?'You are over '+f(n-e)+' minutes, just go home':'You have '+f(e-n)+' minutes left today')"`"
}

neofetch
