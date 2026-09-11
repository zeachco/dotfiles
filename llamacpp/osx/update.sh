#!/usr/bin/env bash
#
# Keep ~/dev/llama.cpp current and its Metal build in sync with the checkout.
#
# The macOS counterpart of llamacpp/archlinux/update.sh -- same contract, same env
# vars, same stamp-file staleness rule. Runs from llamacpp/osx/setup.sh, so
# `dotfiles_update` picks up new llama.cpp architectures without a manual rebuild.
# Also runnable directly:
#
#   bash ~/dotfiles/llamacpp/osx/update.sh                # clone/pull + build if stale
#   LLAMACPP_BUILD_FORCE=1 bash .../update.sh             # build even if current
#   LLAMACPP_REF=some-branch bash .../update.sh           # track something else
#   LLAMACPP_SKIP_UPDATE=1 bash .../update.sh             # skip entirely
#
# WHY A SOURCE BUILD ON A MAC THAT ALREADY HAS THE BREW FORMULA. The formula lags
# master by weeks, and the failure mode is the one documented in the Arch updater:
# a model needing a NEW architecture cannot load, while every pre-existing model
# keeps working and nothing in the logs points at the binary's age. The Arch box
# solved that by tracking master; this makes the Mac behave the same way, so a model
# that runs on one runs on the other. brew's llama.cpp stays installed as the
# fallback the router falls back to when there is no build here (see setup.sh).
#
# This one DOES clone, where the Arch updater refuses to. On the Strix Halo box the
# checkout is a documented prerequisite with a hand-tuned Vulkan build behind it
# (ryzen-llm-setup.md); here there is nothing to preserve and nothing to get wrong,
# so a missing checkout is just a first run.
#
# INVOKE THIS WITH `bash`, NOT `$SHELL`: ${BASH_SOURCE[0]} below is unset under zsh
# and SCRIPT_DIR would silently resolve to the CALLER's cwd.
#
# PORTABILITY: macOS ships bash 3.2.57 with no Homebrew bash -- no associative
# arrays, no mapfile, no ${var,,}, no globstar. And no flock(1), hence the mkdir lock.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"

LLAMA_DIR="${LLAMA_CPP_DIR:-$HOME/dev/llama.cpp}"
BUILD_DIR="${LLAMA_CPP_BUILD:-$LLAMA_DIR/build}"
REF="${LLAMACPP_REF:-master}"
STAMP="$BUILD_DIR/.dotfiles-build-commit"
REPO="${LLAMACPP_REPO:-https://github.com/ggml-org/llama.cpp.git}"

FAIL="\033[0;31m"
PASS="\033[0;32m"
WARN="\033[0;33m"
INFO="\033[0;34m"
NORM="\033[0m"

say()  { echo -e "${INFO}llama.cpp:${NORM} $*"; }
warn() { echo -e "${WARN}llama.cpp:${NORM} $*"; }
bad()  { echo -e "${FAIL}llama.cpp:${NORM} $*"; }
good() { echo -e "${PASS}llama.cpp:${NORM} $*"; }

[[ -n "${LLAMACPP_SKIP_UPDATE:-}" ]] && { say "skipped (LLAMACPP_SKIP_UPDATE set)"; exit 0; }

# ---- hardware gate ------------------------------------------------------------------
# Apple Silicon only: an Intel Mac builds this with GGML_METAL=OFF and gets a CPU-only
# binary it has no use for. _hw_sysctl comes from here too -- /usr/sbin is not on PATH
# inside a devbox shell, and those are auto-entered on cd.
. "$SCRIPT_DIR/../shared/_hw-gate.sh"

if ! is_apple_silicon; then
  # Silent, like the Arch gate: a warning on every dotfiles_update on every other
  # machine just trains you to ignore this script.
  exit 0
fi

# ---- preflight ----------------------------------------------------------------------
# Fail here, loudly, with the fix, before spending any CPU or disk. Xcode's Command
# Line Tools carry both clang and the Metal toolchain; without them cmake's compiler
# probe fails with a wall of output that says nothing about the actual cause.
MISSING=""
command -v git >/dev/null 2>&1 || MISSING="$MISSING git"
command -v cmake >/dev/null 2>&1 || MISSING="$MISSING cmake"
if [[ -n "$MISSING" ]]; then
  bad "cannot build: missing$MISSING"
  bad "  brew install$MISSING"
  bad "  (llamacpp/osx/setup.sh installs these; re-run dotfiles_update after)"
  exit 1
fi
if ! xcode-select -p >/dev/null 2>&1; then
  bad "cannot build: Xcode Command Line Tools are not installed"
  bad "  xcode-select --install"
  exit 1
fi

# ---- serialize ----------------------------------------------------------------------
# A login shell and a manual run can collide; two concurrent cmake builds in one
# directory corrupt object files rather than merely racing.
#
# mkdir, not flock: macOS has no flock(1). mkdir is atomic on every filesystem that
# matters here. The lock lives OUTSIDE the checkout -- the Arch version learned that
# the hard way, where a lock file in the repo root made the script fail its own
# "working tree is dirty" check on the next run and silently stop building.
LOCK_DIR="${TMPDIR:-/tmp}/dotfiles-llamacpp-update.lock"
take_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo $$ >"$LOCK_DIR/pid"
    trap 'rm -rf "$LOCK_DIR"' EXIT
    return 0
  fi
  # Held, or orphaned by a crash/reboot. A live owner wins; a dead one is cleared,
  # otherwise one killed build would block every future run with no way to tell.
  local owner
  owner="$(cat "$LOCK_DIR/pid" 2>/dev/null || echo)"
  if [[ -n "$owner" ]] && kill -0 "$owner" 2>/dev/null; then
    warn "another update is already running (pid $owner), skipping"
    return 1
  fi
  warn "clearing a stale lock (pid ${owner:-unknown} is gone)"
  rm -rf "$LOCK_DIR"
  mkdir "$LOCK_DIR" 2>/dev/null || { warn "cannot take the lock, skipping"; return 1; }
  echo $$ >"$LOCK_DIR/pid"
  trap 'rm -rf "$LOCK_DIR"' EXIT
  return 0
}
take_lock || exit 0

# ---- clone or fast-forward ----------------------------------------------------------
if [[ ! -d "$LLAMA_DIR/.git" ]]; then
  if [[ -e "$LLAMA_DIR" ]]; then
    bad "$LLAMA_DIR exists but is not a git checkout -- leaving it alone"
    exit 1
  fi
  say "cloning $REPO -> $LLAMA_DIR (first run: ~1 GB of history, then a full build)"
  mkdir -p "$(dirname "$LLAMA_DIR")" || exit 1
  # A full clone, NOT --depth 1: the staleness report below uses `git rev-list --count`
  # and short SHAs, and a shallow clone cannot fast-forward across a force-push.
  if ! git clone --quiet "$REPO" "$LLAMA_DIR"; then
    bad "clone failed -- nothing installed, the brew fallback still serves the router"
    exit 1
  fi
fi

cd "$LLAMA_DIR" || exit 0

# ---- never clobber local work -------------------------------------------------------
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  warn "working tree at $LLAMA_DIR is dirty -- not pulling, not building"
  warn "  commit/stash there, or set LLAMACPP_SKIP_UPDATE=1 to silence this"
  exit 0
fi

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"

# Only pull when we are actually on the tracked ref. A deliberate PR-branch checkout
# keeps its source untouched but still gets its BINARY rebuilt below, so a pinned
# branch is never silently served by a stale build.
if [[ "$CURRENT_BRANCH" != "$REF" ]]; then
  warn "on branch '$CURRENT_BRANCH', not '$REF' -- skipping pull, will still build if stale"
  warn "  \`git -C $LLAMA_DIR checkout $REF\` to resume tracking, or set LLAMACPP_REF"
else
  say "fetching origin..."
  if ! git fetch origin --quiet 2>/dev/null; then
    warn "fetch failed (offline?) -- continuing with the local checkout"
  fi
  BEFORE="$(git rev-parse HEAD)"
  # --ff-only: a diverged local branch is reported, never rewritten.
  if git merge --ff-only "origin/$REF" --quiet 2>/dev/null; then
    AFTER="$(git rev-parse HEAD)"
    if [[ "$BEFORE" != "$AFTER" ]]; then
      say "$REF $(git rev-parse --short "$BEFORE") -> $(git rev-parse --short "$AFTER") ($(git rev-list --count "$BEFORE..$AFTER") commits)"
    fi
  else
    warn "cannot fast-forward $CURRENT_BRANCH onto origin/$REF -- diverged, leaving it alone"
  fi
fi

HEAD_SHA="$(git rev-parse HEAD)"
BUILT_SHA="$(cat "$STAMP" 2>/dev/null || echo none)"

# ---- decide whether to build --------------------------------------------------------
NEEDS_BUILD=0
REASON=""
if [[ -n "${LLAMACPP_BUILD_FORCE:-}" ]]; then
  NEEDS_BUILD=1; REASON="LLAMACPP_BUILD_FORCE set"
elif [[ ! -x "$BUILD_DIR/bin/llama-server" ]]; then
  NEEDS_BUILD=1; REASON="llama-server is not built yet"
elif [[ "$BUILT_SHA" == none ]]; then
  # No stamp: either a build predating this script, or one that never finished. Both
  # are unproven, so rebuild -- which costs seconds when the tree really is current.
  NEEDS_BUILD=1; REASON="no build stamp -- provenance unknown"
elif [[ "$BUILT_SHA" != "$HEAD_SHA" ]]; then
  NEEDS_BUILD=1; REASON="built $(git rev-parse --short "$BUILT_SHA" 2>/dev/null || echo "$BUILT_SHA"), HEAD is $(git rev-parse --short "$HEAD_SHA")"
fi

if ((NEEDS_BUILD == 0)); then
  good "build is current at $(git rev-parse --short "$HEAD_SHA")"
  exit 0
fi

say "rebuilding: $REASON"

# ---- configure ----------------------------------------------------------------------
# Metal is the default on Apple Silicon, but it is stated explicitly so a cmake
# default change cannot quietly produce a CPU-only build -- the exact class of silent
# regression this script exists to catch.
#
# GGML_METAL_EMBED_LIBRARY=ON compiles the shaders into the binary instead of shipping
# a default.metallib next to it. That removes a runtime file dependency: the launchd
# agent runs with cwd=~/models and a bare PATH, and a metallib looked up relative to
# the binary is the kind of thing that breaks only after the build directory moves.
#
# Tests off (nothing here runs them, and they are a meaningful share of the build).
# Examples/tools left at their defaults ON: llama-bench, llama-cli and the rest of
# tools/ are used by hand and by bin/llamacpp-audit.
CMAKE_ARGS=(
  -S "$LLAMA_DIR" -B "$BUILD_DIR"
  -DCMAKE_BUILD_TYPE=Release
  -DGGML_METAL=ON
  -DGGML_METAL_EMBED_LIBRARY=ON
  -DLLAMA_BUILD_TESTS=OFF
)
if command -v ccache >/dev/null 2>&1; then
  CMAKE_ARGS+=(-DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache)
fi

if ! cmake "${CMAKE_ARGS[@]}" >/dev/null; then
  bad "cmake configure failed -- build/ left as-is, stamp untouched"
  exit 1
fi

# ---- build --------------------------------------------------------------------------
# Half the cores: this can run while the router is serving, and the plist gives the
# router ProcessType=Interactive precisely so it is not starved.
NCPU="$(_hw_sysctl hw.ncpu)"
[[ -n "$NCPU" ]] || NCPU=2
JOBS="${LLAMACPP_BUILD_JOBS:-$((NCPU / 2))}"
((JOBS < 1)) && JOBS=1
say "building with -j$JOBS (first build takes a few minutes)..."

# Full output to a log; the terminal gets progress plus, on failure, the lines that
# matter. At -j7 a single `fatal error:` scrolls past inside hundreds of interleaved
# progress lines -- on the Arch box both build failures were reported as "build
# FAILED" with no visible cause.
BUILD_LOG="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles-llamacpp-build.log"
mkdir -p "$(dirname "$BUILD_LOG")"
cmake --build "$BUILD_DIR" -j"$JOBS" 2>&1 | tee "$BUILD_LOG" | grep -E '^\[ *[0-9]+%\]|error|Error|\*\*\*'
if [[ "${PIPESTATUS[0]}" != 0 ]]; then
  bad "build FAILED -- stamp left at '$BUILT_SHA', next run will retry"
  bad "  full log: $BUILD_LOG -- first errors:"
  grep -n -E 'error:|Error [0-9]|undefined reference' "$BUILD_LOG" | head -8 | sed 's/^/    /'
  bad "  the router keeps running the previous binary, which is the safe outcome"
  exit 1
fi

# Only now is the build proven. Anything that dies before this line leaves the stamp
# stale, which is the whole point.
echo "$HEAD_SHA" >"$STAMP"
good "built $(git rev-parse --short "$HEAD_SHA")"

# ---- report, never restart ----------------------------------------------------------
# Deliberately does NOT restart the router: a restart drops in-flight generation, and
# a long prompt ingest can be minutes of work. But do not stay quiet either -- an
# un-restarted router is the exact state that hid the stale-build problem on Arch.
#
# The router forks a child per model, so once the dylibs are replaced a NEWLY
# autoloaded child runs the new code under a parent still mapped to the old.
if launchctl print "gui/$(id -u)/com.zeachco.llama-router" >/dev/null 2>&1; then
  echo
  warn "the router is still running the PREVIOUS binary -- restart when idle:"
  warn "  los-restart"
fi
