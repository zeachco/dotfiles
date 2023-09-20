#!/bin/env bash

# When xcode needs to be reinstalled or is corrupted
xcode_reinstall() {
  sudo rm -rf $(xcode-select -print-path)
  xcode-select --install
}

# alias with command print
_set () {
  alias $1="echo -e \" ~ \033[0;34m$2\033[0m\" && $2"
}

_set bank "spin up ~/sbanking.yml --wait"

tableflip() {
    echo "(╯°□°)╯︵ ┻━┻";
    spin destroy --all
    spin login
    bank
    spin code
    say "`node -e "n=new Date,f=t=>Math.abs(Math.round((t)/60000)),e=new Date(n.toLocaleString().split(', ')[0]+', 17:00:00'),o=console.log('code is open.'+n>e?'You are over '+f(n-e)+' minutes, just go home':'You have '+f(e-n)+' minutes left today')"`"
}
