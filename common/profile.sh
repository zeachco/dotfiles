#!/bin/env sh

DOT_DIR=~/dotfiles
function dotfiles_update {
    cd $DOT_DIR
    git fetch
    git reset --hard origin/main
    cd -

    $SHELL "$DOT_DIR/setup.sh"
}

alias update_dotfiles="dotfiles_update"

function gcommits() {
    if [ -z $1 ];
    then git log --format="%C(auto)%h (%s, %ad)" -n 20 | cat;
    else git log --format="%H" -n $1 | cat;
    fi
}

# alias with command print
function _set () {
    alias $1="echo -e \" ~ \033[0;34m$2\033[0m\" && $2"
}

_set ll "ls -al"
_set p "pnpm"
_set gba "git branch -a"
_set gpaa "git add . --all && git commit --amend --no-edit && git push origin --force-with-lease"
_set grbi "git rebase upstream/master -i"
_set gph "git push heroku master"
_set gaa "git add -A"
_set gd "git diff"
_set gs "git status"
_set gco "git checkout"
_set gcp "git cherry-pick"
_set gci "git commit"
_set gcia "git commit --amend --no-edit"
_set grb "git rebase -i"
_set gp "git pull"
_set gpp "git push"
_set gfa "git fetch --all"
_set gfu "git fetch upstream"
_set grh "git reset --hard"
_set grho 'git reset --hard origin/$(git branch --show-current)'
_set gmt "git mergetool"
_set gl "git log --oneline --graph"
_set shipit "npm run deploy"
_set gpft "git push --follow-tags"
_set npmv "npm version $1 && git push --follow-tags && npm publish"
_set gif "~/scripts/gif"
_set hosts "sudo vim /etc/hosts && sudo /etc/init.d/dns-clean restart && sudo /etc/init.d/networking restart"
_set amisafe "ps auxwww | grep sshd"
_set empty-trash "rm -rf ~/.local/share/Trash/*"
_set v "nvim"
_set e "nvim"
_set os "neofetch"
_set pr "gh pr checkout $1"

killname() {
    for pid in $(ps -e | grep $1 | awk '{print $1}'); do
        process_name=$(ps -p $pid -o comm=)
        echo "Are you sure you want to kill process $pid ($process_name)? [y/N]"
        read response
        if [[ $response =~ ^([yY][eE][sS]|[yY])$ ]]; then
            sudo kill -9 $pid
            echo "Killed process $pid ($process_name)"
        else
            echo "Skipped process $pid ($process_name)"
        fi
    done
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

alias clone="bun ~/dotfiles/advanced/clone.ts"

git_test() {
    DEFAULT_FILTER="test.ts"
    DEFAULT_RUNNER="yarn jest --watch"
    FILTER="${1:-$DEFAULT_FILTER}"
    RUNNER="${2:-$DEFAULT_RUNNER}"
    git diff origin/main --name-only | grep $FILTER |  fzf -m | xargs $RUNNER
}
_set gt "git_test"

power() {
  upower -i /org/freedesktop/UPower/devices/battery_BAT0 | grep 'state\|percentage'
}

denode() {
  deno run -A --unstable npm:$1
}

codeai() {
    file=$1
    prompt=$2
    echo "starting AI analysis for $file..."
    fullprompt="file: '$file':\n \`\`\`\n$(cat $file)\n\n\`\`\`\n\nplease rewrite its content to satisfy the following: $prompt\n\n"
    echo "$fullprompt" | ollama run codellama:13b > $file & echo "to stop: \n kill $!";
}

speakai() {
    prompt=$1
    echo "starting AI..."
    echo "$prompt" | ollama run mistral | espeak -s150 -g4 -p55 -a 200 & echo "to stop: \n kill $!";
}

if [[ $SHELL == *zsh* ]]; then
  bindkey '[C' forward-word
  bindkey '[D' backward-word
fi

ai() {
  model=${1:-"tinyllama"}
  echo "Using model $model"
  ollama run $model
}

pie_score() {
    echo "Generate a PIE score by listing 3 score for Physical, Intellectual and Emotional, each line starts with the name of the score followed by 'is <score>, because <make up a casual reason matching the category>'" | ollama run mistral
}

