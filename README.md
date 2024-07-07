# Execute

For ubuntu, use [omakub](https://omakub.org/) instead, it's just better

```sh
wget -qO- https://omakub.org/install | bash
```

For arch, mac or any other debian forks

```sh
git clone git@github.com:zeachco/dotfiles.git ~/dotfiles && bash ~/dotfiles/setup.sh
```

# Supports

- linux debian/arch based (with apt-get such as Ubuntu)
- linux debian/arch based (with pacman such as Manjaroo)
- maxos (with xcode)
- spin cloud debian-based server
- extensible by profile

# Includes

## Programing languages

- pyenv - Python environment manager
- nvm - Node environment manager
- rust
- deno
- bun

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
- clone - github shorhand to clone ie: `clone zeachco/dotfiles`
- neofetch - print detailed os information for support help and forums
- ai [ollama model] - starts an AI model locally, default to tinyllama
