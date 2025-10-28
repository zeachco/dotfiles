#!/bin/sh

# Source utils.sh for shared functions
source "$HOME/dotfiles/utils.sh"

os() {
  fastfetch
}

# Arch Linux specific aliases and functions using utils.sh

# Enhanced install function for Arch Linux
pac_install() {
    if command -v yay &> /dev/null && yay -Ss "$1" | grep -q "^aur/"; then
        echo -e "${WARN}installing ${NORM}$1 (from AUR)..."
        yay -S "$1" --noconfirm
    else
        install "$1"
    fi
}

# Pacman shortcuts using utils.sh patterns
pacup() {
    echo -e "${WARN}updating system packages...${NORM}"
    sudo pacman -Syu --noconfirm
}

pacin() {
    pac_install "$1"
}

pacrm() {
    if exists "$1"; then
        echo -e "${WARN}removing ${NORM}$1 and dependencies..."
        sudo pacman -Rns "$1" --noconfirm
    else
        echo -e "${FAIL}package ${NORM}$1 not installed"
    fi
}

pacss() {
    pacman -Ss "$1"
}

pacsi() {
    pacman -Si "$1"
}

pacqi() {
    pacman -Qi "$1"
}

pacql() {
    pacman -Ql "$1"
}

pacqo() {
    pacman -Qo "$1"
}

pacclean() {
    echo -e "${WARN}cleaning package cache...${NORM}"
    sudo pacman -Sc --noconfirm
}

pacorph() {
    echo "Orphaned packages:"
    pacman -Qdtq
}

# Yay (AUR) shortcuts
yayup() {
    if command -v yay &> /dev/null; then
        echo -e "${WARN}updating system including AUR...${NORM}"
        yay -Syu --noconfirm
    else
        echo -e "${FAIL}yay not installed${NORM}"
    fi
}

yayin() {
    if command -v yay &> /dev/null; then
        echo -e "${WARN}installing ${NORM}$1 (from AUR)..."
        yay -S "$1" --noconfirm
    else
        echo -e "${FAIL}yay not installed${NORM}"
    fi
}

yayss() {
    if command -v yay &> /dev/null; then
        yay -Ss "$1"
    else
        echo -e "${FAIL}yay not installed${NORM}"
    fi
}

yayrm() {
    if command -v yay &> /dev/null; then
        if exists "$1"; then
            echo -e "${WARN}removing ${NORM}$1 and dependencies..."
            yay -Rns "$1" --noconfirm
        else
            echo -e "${FAIL}package ${NORM}$1 not installed"
        fi
    else
        echo -e "${FAIL}yay not installed${NORM}"
    fi
}

# System maintenance
alias journalctl-errors='journalctl -p 3 -xb'  # Show system errors
alias systemctl-list='systemctl list-units --type=service --state=running'

# System info using utils.sh colors
sysinfo() {
    echo -e "${INFO}=== System Information ===${NORM}"
    echo "Kernel: $(uname -r)"
    echo "Uptime: $(uptime -p)"
    echo "Packages: $(pacman -Q | wc -l) installed"
    echo "Disk usage:"
    df -h / | tail -1
    echo "Memory usage:"
    free -h | grep "^Mem:"
}

# Package management functions using utils.sh
pactree() {
    # Show dependency tree for a package
    if pacman -Qi "$1" &>/dev/null; then
        echo -e "${INFO}Dependencies for ${NORM}$1:"
        pacman -Qi "$1" | grep -E "(Depends|Required|Optional)" | cut -d: -f2 | tr -d ' ' | tr ',' '\n' | grep -v '^$' | sort -u
    else
        echo -e "${FAIL}package ${NORM}$1 not installed"
    fi
}

pacbig() {
    # Show largest installed packages
    echo -e "${INFO}Largest installed packages:${NORM}"
    pacman -Qi | awk '/^Name/{name=$3} /^Installed Size/{print $4$5, name}' | sort -h | tail -20
}

pacown() {
    # Find which package owns a file
    if [[ -z "$1" ]]; then
        echo -e "${FAIL}usage: pacown <file>${NORM}"
        return 1
    fi

    result=$(pacman -Qo "$1" 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        echo -e "${PASS}$result${NORM}"
    else
        echo -e "${FAIL}file ${NORM}$1${FAIL} not owned by any package${NORM}"
    fi
}

pacfiles() {
    # List all files installed by a package
    if [[ -z "$1" ]]; then
        echo -e "${FAIL}usage: pacfiles <package>${NORM}"
        return 1
    fi

    if pacman -Ql "$1" &>/dev/null; then
        echo -e "${INFO}Files installed by ${NORM}$1:"
        pacman -Ql "$1"
    else
        echo -e "${FAIL}package ${NORM}$1${FAIL} not installed${NORM}"
    fi
}

# AUR helper function using utils.sh
yayt() {
    # Install package with yay, falling back to pacman
    if [[ -z "$1" ]]; then
        echo -e "${FAIL}usage: yayt <package>${NORM}"
        return 1
    fi

    if command -v yay &> /dev/null && yay -Ss "$1" 2>/dev/null | grep -q "^aur/"; then
        echo -e "${WARN}installing ${NORM}$1${WARN} from AUR...${NORM}"
        yay -S "$1" --noconfirm
    else
        pac_install "$1"
    fi
}



# Mirror management using utils.sh
mirrorup() {
    # Update pacman mirrors (requires reflector)
    if command -v reflector &> /dev/null; then
        echo -e "${WARN}updating pacman mirrors...${NORM}"
        sudo reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
        echo -e "${PASS}mirrorlist updated${NORM}"
    else
        echo -e "${FAIL}reflector not installed${NORM}. Install with: pac_install reflector"
    fi
}

# Caps lock remap (X11 only, not Wayland)
if [ "$XDG_SESSION_TYPE" != "wayland" ] && [ -z "$WAYLAND_DISPLAY" ]; then
    setxkbmap -option caps:escape 2>/dev/null || true
fi

# WiFi info using utils.sh colors
wifi() {
    iwconfig 2>/dev/null | grep -A 5 wlan || echo -e "${WARN}no wireless interface found${NORM}"
    echo "IP addresses:"
    ip addr show | grep inet | grep -v inet6 | grep -v 127.0.0.1
}

# KDE restart (if using KDE) using utils.sh colors
kde_restart() {
    echo -e "${WARN}restarting display manager...${NORM}"
    sudo systemctl restart sddm 2>/dev/null || sudo systemctl restart lightdm 2>/dev/null || echo -e "${FAIL}display manager restart failed${NORM}"
}

# Interactive package installer using fzf and utils.sh
paci() {
    if ! command -v fzf &> /dev/null; then
        echo -e "${FAIL}fzf not installed${NORM}. Install with: pac_install fzf"
        return 1
    fi

    package="$(
        pacman -Sl | awk '{print $2}' |
        fzf -m --prompt="Select packages to install: " \
            --preview "pacman -Si {} 2>/dev/null || yay -Si {} 2>/dev/null" \
            --preview-window 'top:75%' |
        tr "\n" " "
    )"
    [[ $package ]] && read -n1 -p "Install ${package}? [y/N]: " install
    [[ "$install" == "y" ]] && pac_install $package
}

# AUR package installer using fzf and utils.sh
yayi() {
    if ! command -v yay &> /dev/null; then
        echo -e "${FAIL}yay not installed${NORM}. Install yay first."
        return 1
    fi

    if ! command -v fzf &> /dev/null; then
        echo -e "${FAIL}fzf not installed${NORM}. Install with: pac_install fzf"
        return 1
    fi

    package="$(
        yay -Sl | awk '{print $2}' |
        fzf -m --prompt="Select AUR packages to install: " \
            --preview "yay -Si {} 2>/dev/null" \
            --preview-window 'top:75%' |
        tr "\n" " "
    )"
    [[ $package ]] && read -n1 -p "Install ${package}? [y/N]: " install
    [[ "$install" == "y" ]] && yayin $package
}
