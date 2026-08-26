#!/usr/bin/env bash
#
# Install the llama.cpp router as a launchd USER AGENT.
#
# Mirrors framework-ryzen/setup.sh: guard, render the artifact, cmp -s it against
# what is already installed, and exit 0 BEFORE touching the running service when
# nothing changed. Re-running on every `dotfiles_update` is a no-op.
#
# INVOKE THIS WITH `bash`, NOT `$SHELL`. utils.sh runs variants/*/setup.sh as
# `$SHELL <script>` and $SHELL is /bin/zsh here, so the shebang is ignored. Under zsh
# with `set -u`, ${BASH_SOURCE[0]} is unset: the SCRIPT_DIR idiom below prints a
# diagnostic and then silently resolves to the CALLER's cwd instead of aborting.
# (The same latent bug exists in framework-ryzen/setup.sh as called from setup.sh.)
#
# macOS ships bash 3.2.57 and there is no Homebrew bash: no `declare -A`, no
# `mapfile`, no `${var,,}`, no globstar.

set -euo pipefail

LABEL="com.zeachco.llama-router"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/$LABEL.plist"
AGENT_DIR="$HOME/Library/LaunchAgents"
INSTALLED="$AGENT_DIR/$LABEL.plist"
DOMAIN="gui/$(id -u)"
DOT_DIR="${DOT_DIR:-$HOME/dotfiles}"

# ---- guards: never render a plist pointing at a binary that is not there ----------
if ! command -v brew >/dev/null 2>&1; then
  echo "llama router skipped: brew is not installed"
  exit 0
fi
BREW="$(brew --prefix)"

# llama.cpp v0.3.0 ships a multi-tool `llama` AND per-subcommand `llama-*` binaries
# (its brew test asserts on both). Prefer the explicit server binary and fall back to
# the subcommand form, so a future rename degrades instead of producing a plist whose
# argv[0] does not exist -- launchd reports that as posix_spawn error 2 in
# `launchctl print` and writes nothing at all to the log file.
SUBCOMMAND=""
if [[ -x "$BREW/opt/llama.cpp/bin/llama-server" ]]; then
  LLAMA_SERVER="$BREW/opt/llama.cpp/bin/llama-server"
elif [[ -x "$BREW/opt/llama.cpp/bin/llama" ]]; then
  echo "llama router: llama-server not found, using the 'llama server' subcommand"
  LLAMA_SERVER="$BREW/opt/llama.cpp/bin/llama"
  SUBCOMMAND="server"
else
  echo "llama router skipped: llama.cpp is not installed (brew install llama.cpp)"
  exit 0
fi

# ---- directories the plist depends on --------------------------------------------
# WorkingDirectory and the log directory must both exist or launchd refuses to spawn
# and the failure is invisible (the log file is never created).
# ~/models-drafts is a SIBLING of ~/models on purpose: a drafts/ subdirectory inside
# --models-dir would be scanned as one multi-shard model.
mkdir -p \
  "$HOME/models" \
  "$HOME/models-drafts" \
  "$HOME/.cache/llama.cpp-router" \
  "$HOME/Library/Logs/llama-router" \
  "$AGENT_DIR"

# ---- raise the Metal wired limit -------------------------------------------------
# Needs root, so it is gated on its own idempotence check: only shell out to sudo when
# the daemon or the live sysctl is actually out of date. A no-op update must not
# prompt for a password.
WIRED_INSTALLER="$SCRIPT_DIR/install-wired-limit.sh"
WIRED_PLIST="$SCRIPT_DIR/com.zeachco.iogpu-limit.plist"
WIRED_INSTALLED="/Library/LaunchDaemons/com.zeachco.iogpu-limit.plist"
WIRED_MB="$(sed -n 's/.*iogpu\.wired_limit_mb=\([0-9]*\).*/\1/p' "$WIRED_PLIST" | head -1)"

if [[ -f "$WIRED_INSTALLED" ]] \
  && cmp -s "$WIRED_PLIST" "$WIRED_INSTALLED" \
  && [[ "$(sysctl -n iogpu.wired_limit_mb)" == "$WIRED_MB" ]]; then
  echo "llama router: iogpu.wired_limit_mb already at ${WIRED_MB} MiB"
elif sudo -n true 2>/dev/null; then
  echo "llama router: raising iogpu.wired_limit_mb to ${WIRED_MB} MiB"
  sudo -n bash "$WIRED_INSTALLER" || echo "llama router: wired-limit install failed, continuing"
elif [[ -t 0 ]]; then
  echo "llama router: raising iogpu.wired_limit_mb to ${WIRED_MB} MiB (needs sudo)"
  sudo bash "$WIRED_INSTALLER" || echo "llama router: wired-limit install failed, continuing"
else
  # Never block an unattended `dotfiles_update` on a password prompt. The router runs
  # fine at the ~36 GiB default cap; it just cannot hold all three models with
  # generous contexts. Print the one command and carry on.
  echo "llama router: iogpu.wired_limit_mb needs raising to ${WIRED_MB} MiB but sudo"
  echo "              would prompt and stdin is not a tty. Run manually:"
  echo "              sudo bash $WIRED_INSTALLER"
fi

# ---- render ----------------------------------------------------------------------
RENDERED="$(mktemp -t llama-router-plist)"
trap 'rm -f "$RENDERED"' EXIT

# Explicit if/else rather than `[[ -n x ]] && y`: under `set -e`, a false test as the
# last command of an && list exits the script.
if [[ -n "$SUBCOMMAND" ]]; then
  SUBCOMMAND_EXPR="s|<string>@SUBCOMMAND@</string>|<string>$SUBCOMMAND</string>|"
else
  SUBCOMMAND_EXPR="/<string>@SUBCOMMAND@<\/string>/d"
fi

sed \
  -e "s|@LLAMA_SERVER@|$LLAMA_SERVER|g" \
  -e "$SUBCOMMAND_EXPR" \
  -e "s|@HOME@|$HOME|g" \
  -e "s|@BREW@|$BREW|g" \
  -e "s|@DOT_DIR@|$DOT_DIR|g" \
  "$TEMPLATE" >"$RENDERED"

# Catch a malformed template before it becomes a job launchd silently declines.
if ! plutil -lint "$RENDERED" >/dev/null; then
  echo "llama router: rendered plist failed plutil -lint" >&2
  exit 1
fi
# The comment block documents the @TOKEN@ names, so only flag tokens that survived
# inside an element -- a leftover in argv is what actually breaks the job.
if grep -q '<string>@[A-Z_]*@' "$RENDERED"; then
  echo "llama router: unsubstituted token left in the plist:" >&2
  grep -n '<string>@[A-Z_]*@' "$RENDERED" >&2
  exit 1
fi

# ---- idempotence: bail out before touching the running service -------------------
# Both conditions matter: an identical file that is NOT loaded (first run after a
# manual bootout, or a fresh login) still needs bootstrapping.
if [[ -f "$INSTALLED" ]] \
  && cmp -s "$RENDERED" "$INSTALLED" \
  && launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
  echo "llama router: agent is already installed and loaded"
  exit 0
fi

# ---- teardown of the current and any legacy label ---------------------------------
# bootout on a label that was never loaded exits 113 ("Could not find specified
# service") and prints to stderr. That is the expected first-run path, not an error.
for legacy in "$LABEL" com.zeachco.llamacpp-router llama-router; do
  launchctl bootout "$DOMAIN/$legacy" 2>/dev/null || true
  if [[ "$legacy" != "$LABEL" ]]; then
    rm -f "$AGENT_DIR/$legacy.plist"
  fi
done

install -m 644 "$RENDERED" "$INSTALLED"

# `bootstrap` is the modern replacement for the deprecated `load`; it reads the file
# from disk, so the install above has to happen first. RunAtLoad already starts it;
# kickstart -k makes the restart-on-change path explicit and idempotent whether or not
# the job happened to be running.
launchctl bootstrap "$DOMAIN" "$INSTALLED"
launchctl kickstart -k "$DOMAIN/$LABEL"

echo "llama router: bootstrapped $LABEL -> http://0.0.0.0:8080 (LAN: http://$(scutil --get LocalHostName).local:8080)"
echo "llama router: logs at ~/Library/Logs/llama-router/router.log -- launchd does NOT"
echo "              rotate these; add /etc/newsyslog.d/llama-router.conf if it grows"

if [[ -z "$(ls -A "$HOME/models" 2>/dev/null || true)" ]]; then
  echo "llama router: ~/models is empty. Fetch the model set (~29 GB, not automatic):"
  echo "              bash $DOT_DIR/configs/llama/fetch-models-osx.sh"
fi
