#!/usr/bin/env bash
source "$HOME/dotfiles/utils.sh"

configureGitIdentity() {
  echo "Email for git config: "
  read git_email
  echo "Full name for git config: "
  read git_name
  git config --global --replace-all user.email $git_email
  git config --global --replace-all user.name $git_name
}

foundEmail=$(git config --list | grep email)

if [[ $foundEmail != *"@"* ]]; then
  configureGitIdentity
fi

git config --global --replace-all credential.helper cache
git config --global --replace-all color.ui auto
git config --global --replace-all alias.b "branch -a"
git config --global --replace-all alias.aaa "add . --all && commit --amend --no-edit"
git config --global --replace-all alias.rbi "rebase upstream/master -i"
git config --global --replace-all alias.aa "add -A"
git config --global --replace-all alias.d "diff"
git config --global --replace-all alias.s "status"
git config --global --replace-all alias.co "checkout"
git config --global --replace-all alias.cp "cherry-pick"
git config --global --replace-all alias.ci "commit"
git config --global --replace-all alias.rb "rebase -i"
git config --global --replace-all alias.p "pull"
git config --global --replace-all alias.pp "push"
git config --global --replace-all alias.fa "fetch --all"
git config --global --replace-all alias.fu "fetch upstream"
git config --global --replace-all alias.rh "reset --hard"
git config --global --replace-all alias.mt "mergetool"
git config --global --replace-all core.editor "nvim"
git config --global --replace-all push.default "tracking"
git config --global --replace-all alias.l "log --oneline --graph"
git config --global --replace-all pull.rebase true
git config --global --replace-all init.defaultBranch main

# script_install deno "curl -fsSL https://deno.land/x/install/install.sh | $SHELL"
#script_install pyenv "curl https://pyenv.run | $SHELL"
# script_install fzf "git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf && ~/.fzf/install --completion --key-bindings --update-rc"
# script_install lvim "$SHELL <(curl -s https://raw.githubusercontent.com/lunarvim/lunarvim/master/utils/installer/install.sh) --no-install-dependencies && sudo ln -s ~/.local/bin/lvim /usr/bin/lvim"
# script_install rustc "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | $SHELL"
# script_install bun "curl -fsSL https://bun.sh/install | $SHELL"

install fastfetch
install_pkg ripgrep # binary is rg; install_pkg queries the PM, so the
# already-installed case is a silent skip instead of a re-run of apt/pacman
install fd                    # fast find
install gh                    # github-cli
install jq                    # json parser
install eza                   # list tree for ls
install lazygit
install fzf
install tmux
install ngrep

# Bash has built-in vi editing through Readline, so zsh-vi-mode is only
# relevant when Zsh is the user's login shell.
if [[ ${SHELL##*/} == "zsh" ]]; then
  if [[ ! -f "$(brew --prefix 2>/dev/null)/opt/zsh-vi-mode/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh" ]] && \
     [[ ! -f "/usr/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh" ]] && \
     [[ ! -f ~/.zsh-vi-mode/zsh-vi-mode.plugin.zsh ]]; then
    install zsh-vi-mode
  else
    print_exists zsh-vi-mode
  fi
fi
# Claude Code and opencode come from mise when needed (omarchy picks them up
# on first `claude` invocation); no curl installer here.

# Local text-to-speech behind `say`/`converse`. The runtime lives outside the repo
# (~/.local/share) and pulls ~200 MB of CPU-only torch wheels, so it is installed
# once and skipped on every later dotfiles_update. Python 3.11 specifically: torch
# 2.5.1+cpu stops at cp312 and Arch ships only the current Python, hence mise/uv.
KOKORO_VENV="$HOME/.local/share/kokoro-tts"
if install_python_venv kokoro-tts 3.11; then
  kokoro_fresh=0
  if "$KOKORO_VENV/bin/python" -c 'import kokoro, soundfile' >/dev/null 2>&1; then
    print_exists "kokoro-tts"
  else
    echo -e "${WARN}installing ${NORM}kokoro-tts (torch, kokoro, soundfile)..."
    "$KOKORO_VENV/bin/pip" install 'torch==2.5.1+cpu' --index-url https://download.pytorch.org/whl/cpu
    # kokoro leaves transformers unpinned; 5.x calls torch.accelerator (torch>=2.6)
    # and breaks against the pinned torch 2.5.1+cpu, so stay on the 4.x line.
    "$KOKORO_VENV/bin/pip" install kokoro soundfile 'transformers<4.50'
    kokoro_fresh=1
  fi

  # `bin/say` exports HF_HUB_OFFLINE=1, so the Kokoro model, the af_heart voice
  # and spaCy's en_core_web_sm must already be cached or the first run fails
  # offline. Warm after a fresh install or a cleared HF cache; cached is ~8 s.
  if { [ "$kokoro_fresh" = 1 ] || [ ! -d "$HOME/.cache/huggingface/hub/models--hexgrad--Kokoro-82M" ]; } &&
     "$KOKORO_VENV/bin/python" -c 'import kokoro' >/dev/null 2>&1; then
    echo -e "${WARN}downloading ${NORM}Kokoro-82M model and voice..."
    "$KOKORO_VENV/bin/python" -c '
from kokoro import KPipeline
pipeline = KPipeline(lang_code="a", repo_id="hexgrad/Kokoro-82M")
for _ in pipeline("ok", voice="af_heart"):
    pass
'
  fi
fi

stow_link alacritty
stow_link tmux

# pi (coding agent) — cross-platform config. Stow the config, then ensure the
# packages declared in its settings.json (configs/pi/.pi/agent/settings.json) are
# downloaded, since pi does not fetch user-level packages from that list on its own.
#
# models.json is git-ignored machine state: each box serves different models, and `los`
# sync-models drops whatever the local router does not serve. Seed it from the tracked
# template BEFORE stow, or there is no file for stow to link and pi comes up with no
# llamacpp providers at all -- which sync cannot repair, since it fills in models but
# never creates a provider. Only when absent: an existing one is this machine's state.
if [[ ! -f "$DOT_DIR/configs/pi/.pi/agent/models.json" ]]; then
  cp "$DOT_DIR/configs/pi/.pi/agent/models.seed.json" \
     "$DOT_DIR/configs/pi/.pi/agent/models.json"
  echo -e "${INFO}seeded ${NORM}pi models.json (run 'los' -> sync-models to fill it in)"
fi

# models-store.json is also machine-local pi cache. Keep a tracked seed so a fresh
# clone has the model catalog available before pi rebuilds or updates its cache.
if [[ ! -f "$DOT_DIR/configs/pi/.pi/agent/models-store.json" ]]; then
  cp "$DOT_DIR/configs/pi/.pi/agent/models-store.seed.json" \
     "$DOT_DIR/configs/pi/.pi/agent/models-store.json"
  echo -e "${INFO}seeded ${NORM}pi models-store.json"
fi
unfold_dir "$HOME/.pi/agent/skills"
stow_link pi
"$DOT_DIR/configs/pi/setup.sh"

# Claude Code and Codex. Both packages carry the shared agent skills (skills/,
# linked one skill at a time into the harness's own skills directory -- see
# unfold_dir), and Claude's one carries settings.json. Everything else under
# ~/.claude and ~/.codex is state the harness rewrites itself (sessions,
# credentials, project trust, Codex's config.toml), so it stays untracked.
unfold_dir "$HOME/.claude/skills"
stow_link claude
unfold_dir "$HOME/.codex/skills"
stow_link codex

# Herdr's config is Stow-linked on macOS (configs/herdr) but not on other
# platforms, and its server writes to the file either way (onboarding state,
# channel; `herdr update` regenerates it wholesale), so the live file is
# machine state and git-ignored. Seed it from configs/herdr/config.seed.toml
# only when absent, then patch the keymap and theme in place: the keymap has
# one source for every platform, configs/herdr/keys.toml, and ensure-keys
# copies its [keys] table into the live config.
if [[ ! -f "$DOT_DIR/configs/herdr/.config/herdr/config.toml" ]]; then
  cp "$DOT_DIR/configs/herdr/config.seed.toml" \
     "$DOT_DIR/configs/herdr/.config/herdr/config.toml"
  echo -e "${INFO}seeded ${NORM}herdr config.toml"
fi
# Older setups registered a clean filter for that file; drop it.
git -C "$DOT_DIR" config --remove-section filter.herdr-config 2>/dev/null || true
git -C "$DOT_DIR" config --remove-section filter.herdr-theme 2>/dev/null || true

# opencode.json is git-ignored for the same reason: llamacpp-sync rewrites its llamacpp*
# and openrouter model lists. Seed the hand-maintained parts with empty model lists, only
# when absent; the sync fills the models in afterwards.
if [[ ! -f "$DOT_DIR/configs/opencode/.config/opencode/opencode.json" ]]; then
  cp "$DOT_DIR/configs/opencode/.config/opencode/opencode.seed.json" \
     "$DOT_DIR/configs/opencode/.config/opencode/opencode.json"
  echo -e "${INFO}seeded ${NORM}opencode.json (run 'llamacpp-sync' to fill in the models)"
fi

# Claude Code reads a single settings.json too, and three of its keys are machine
# state: "theme" (bin/theme-switch flips it with the terminal theme), "hooks"
# (the herdr integration registers its SessionStart hook there with an absolute
# path -- for pi and opencode it drops a gitignored file instead) and "model"
# (the default /model picks, which differ per box). Same remedy: a clean filter
# strips them in git, the working copy keeps them.
git -C "$DOT_DIR" config filter.claude-settings.clean "jq 'del(.theme, .hooks, .model)'"

if command -v herdr &>/dev/null; then
  "$DOT_DIR/bin/herdr-config" ensure-keys
  "$DOT_DIR/bin/herdr-config" sync-theme
fi

# # not using OMZSH
# if [ -d "$HOME/.oh-my-zsh" ] && [ -f "$HOME/.zshrc" ]; then
#     print_exists "Oh My Zsh"
# else
#     print_needs "Oh My Zsh"
#   sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
# fi

# backup .zshrc
if [ "$SHELL" = "/bin/zsh" ] || [ "$SHELL" = "/usr/bin/zsh" ]; then
  cp ~/.zshrc ~/.zshrc.backup
  # replace theme; the temp file lives next to ~/.zshrc so the mv is atomic
  # (a CWD-relative temp would land wherever setup was started from)
  tmp_zshrc="$(mktemp ~/.zshrc.XXXXXX)"
  awk '/ZSH_THEME=/ {sub(/=.*/, "=\"amuse\"")} 1' ~/.zshrc >"$tmp_zshrc" && mv -f "$tmp_zshrc" ~/.zshrc
else
  cp ~/.bashrc ~/.bashrc.backup
fi

# projets's dev folder
{
  mkdir ~/dev >/dev/null 2>&1 && echo -e "${WARN}create ${NORM}~/dev folder"
} || {
  echo -e "${PASS}found ${NORM}~/dev folder"
}

bash "$DOT_DIR/llamacpp/shared/clone.sh" ||
  echo -e "${FAIL}llama.cpp clone failed${NORM}"
