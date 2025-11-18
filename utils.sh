#!/usr/bin/env bash

DOT_DIR="$HOME/dotfiles"
USER_SOURCE_FILE=~/.profile

# colors
FAIL="\033[0;31m"
PASS="\033[0;32m"
WARN="\033[0;33m"
INFO="\033[0;34m"
NORM="\033[0m"

# Profile target
if [[ $SHELL == *bash* ]]; then
    if [[ -f ~/.bashrc ]]; then         USER_SOURCE_FILE=~/.bashrc
        elif [[ -f ~/.bash_profile ]]; then USER_SOURCE_FILE=~/.bash_profile
        elif [[ -f ~/.bash_login ]]; then   USER_SOURCE_FILE=~/.bash_login
        elif [[ -f ~/.profile ]]; then      USER_SOURCE_FILE=~/.profile
    fi
    elif [[ $SHELL == *zsh* ]]; then      USER_SOURCE_FILE=~/.zshrc
fi
touch $USER_SOURCE_FILE

function install_profile {
    echo -e "${INFO}check ${NORM}$1 dependencies..."
    $SHELL "$DOT_DIR/$1/setup.sh"

    variant=$1
    profile_filename="$HOME/.dotfiles_$variant"

    hook="[[ -f $profile_filename ]] && source $profile_filename # zeachco-dotfiles $variant"

    cp "$DOT_DIR/$variant/profile.sh" "$profile_filename"

    echo -e "${INFO}link ${NORM}$profile_filename"
    echo "$hook" >> $USER_SOURCE_FILE
}

function clean_imports {
    cp -f $USER_SOURCE_FILE "$USER_SOURCE_FILE.backup"
    sed '/zeachco-dotfiles/d' "$USER_SOURCE_FILE.backup" > $USER_SOURCE_FILE
}

function print_needs {
    echo -e "${WARN}missing ${NORM}$1"
}

function print_exists {
    echo -e "${PASS}found ${NORM}$1"
}

function exists {
    if command -v "$1" >/dev/null 2>&1
    then
        print_exists $1
        return 0
    else
        print_needs $1
        return 1
    fi
}

function needs {
    if ! command -v "$1" >/dev/null 2>&1
    then
        print_needs $1
        return 0
    else
        print_exists $1
        return 1
    fi
}

function install() {
    name="$1"
    pkg_name="${2:-$1}"

    if needs $name
    then
        echo -e "${WARN}installing ${NORM}$pkg_name..."
        sleep 1
        # Check for Termux environment first
        if [[ -n "$TERMUX_VERSION" ]] || [[ "$PREFIX" == *"com.termux"* ]]; then
            pkg install -y $pkg_name
        elif command -v apt &> /dev/null
        then
            sudo apt install -y $pkg_name
        elif command -v pacman &> /dev/null
        then
            sudo pacman -S $pkg_name --noconfirm
        elif command -v brew &> /dev/null
        then
            brew install $pkg_name
        else
            echo -e "${FAIL} I don't know how to install $pkg_name ${NORM}"
        fi
    fi
}

function script_install() {
    name="$1"
    exec="$2"

    if needs $name
    then
        echo -e "${WARN}installing ${NORM}$name..."
        echo -e "${INFO}running ${NORM}$exec"
        eval "$exec"
    fi
}
