# Execute

## Direct Installation (Recommended)

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/zeachco/dotfiles/main/setup.sh)
```

## Or clone and run manually

```sh
git clone git@github.com:zeachco/dotfiles.git ~/dotfiles && bash ~/dotfiles/setup.sh
```

For ubuntu, it also installs [omakub](https://omakub.org/) it's just too good to ignore, other OS manually installs the good parts of omakub that I want there like zellij, nvim, sh utils configs

# Supports

- linux debian/arch based (with apt-get such as Ubuntu)
- linux debian/arch based (with pacman such as Manjaroo)
- maxos (with xcode)
- spin cloud debian-based server
- extensible by profile

# Includes

## Programing languages

Uses [mise](https://mise.jdx.dev/) and [devbox](https://www.jetify.com/devbox) to control all envs for python, node, rust, go, etc...

## Tools

- git config (auto config with email / name / rebase merge mode and vim editor)
- git aliases (ie `gco` and `git co` for git checkout) git aliases print the real command
- lunarvim (text editor)
- neovim (text editor)
- ligature nerd fonts
- fzf (fast file searching)
- tmux (multi session and space management terminal)
- g++ compiler

## bash functions

- ipp - public ip print
- ipl - local ip print
