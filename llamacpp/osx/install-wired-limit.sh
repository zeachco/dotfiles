#!/usr/bin/env bash
#
# Install com.zeachco.iogpu-limit, the root LaunchDaemon that raises the Metal
# wired-memory cap to 42 GiB at boot. Root only -- mirrors
# framework-ryzen/install-root.sh.
#
# Called by install.sh in this directory via sudo, and only when something actually
# changed, so a no-op `dotfiles_update` never prompts for a password.
#
# macOS ships bash 3.2.57 and there is no Homebrew bash: no `declare -A`, no
# `mapfile`, no `${var,,}`, no globstar.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "install-wired-limit.sh must run as root" >&2
  exit 1
fi

LABEL="com.zeachco.iogpu-limit"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SOURCE="$SCRIPT_DIR/$LABEL.plist"
INSTALLED="/Library/LaunchDaemons/$LABEL.plist"

if [[ ! -f "$SOURCE" ]]; then
  echo "$SOURCE is missing" >&2
  exit 1
fi

# The value the daemon sets. Parsed out of the plist rather than duplicated, so the
# two can never drift.
WANT_MB="$(sed -n 's/.*iogpu\.wired_limit_mb=\([0-9]*\).*/\1/p' "$SOURCE" | head -1)"
if [[ -z "$WANT_MB" ]]; then
  echo "could not read iogpu.wired_limit_mb out of $SOURCE" >&2
  exit 1
fi

# Idempotence: bail out before bootout/bootstrap when the daemon is already current
# AND the live sysctl already matches. Both halves matter -- an installed daemon says
# nothing about this boot if someone reset the sysctl by hand.
if [[ -f "$INSTALLED" ]] \
  && cmp -s "$SOURCE" "$INSTALLED" \
  && [[ "$(sysctl -n iogpu.wired_limit_mb)" == "$WANT_MB" ]]; then
  echo "iogpu limit: daemon and live sysctl are already at ${WANT_MB} MiB"
  exit 0
fi

# bootout on a label that was never loaded exits 113 ("Could not find specified
# service") and prints to stderr. That is the expected first-run path, not an error.
launchctl bootout "system/$LABEL" 2>/dev/null || true

install -m 644 -o root -g wheel "$SOURCE" "$INSTALLED"
launchctl bootstrap system "$INSTALLED"

# RunAtLoad fires on bootstrap, but apply it directly too so the current boot gets the
# new cap without a reboot.
sysctl -w "iogpu.wired_limit_mb=$WANT_MB" >/dev/null

echo "iogpu limit: iogpu.wired_limit_mb = $(sysctl -n iogpu.wired_limit_mb) (persisted via $LABEL)"
