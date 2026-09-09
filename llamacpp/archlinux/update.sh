#!/usr/bin/env bash
#
# Keep ~/dev/llama.cpp current and its build in sync with the checkout.
#
# Runs from llamacpp/archlinux/setup.sh, so `dotfiles_update` picks up new
# llama.cpp architectures without a manual rebuild. Also runnable directly:
#
#   bash ~/dotfiles/llamacpp/archlinux/update.sh          # pull + build if stale
#   LLAMACPP_BUILD_FORCE=1 bash .../update.sh             # build even if current
#   LLAMACPP_REF=some-branch bash .../update.sh           # track something else
#   LLAMACPP_SKIP_UPDATE=1 bash .../update.sh             # skip entirely
#
# WHY THIS EXISTS -- 2026-09-08. Qwen3.8-Flash-Next could not load:
#   E llama_model_load: error loading model: unknown model architecture: 'qwen4exp'
# The source had qwen4exp support; the BUILD did not. build/ held a half-finished
# rebuild -- libggml-base/libggml-cpu relinked to 0.22.0 on Aug 27, while
# libllama.so and llama-server were still the Aug 19 artifacts from six days before
# qwen4exp landed. Nothing reported that: `git log` looked current, the router
# started fine, and every pre-existing model kept working. Only a model needing a
# NEW arch surfaced it.
#
# So the staleness check is a stamp file written ONLY after a build exits 0, never
# an mtime comparison. An interrupted or failed build leaves the stamp stale and the
# next run retries -- which is exactly the case mtime got wrong.

set -uo pipefail

LLAMA_DIR="${LLAMA_CPP_DIR:-$HOME/dev/llama.cpp}"
BUILD_DIR="${LLAMA_CPP_BUILD:-$LLAMA_DIR/build}"
REF="${LLAMACPP_REF:-master}"
STAMP="$BUILD_DIR/.dotfiles-build-commit"

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
# Only the Strix Halo box builds llama.cpp from source. Every other machine that runs
# this repo -- laptops, the M4, Termux -- either has no llama.cpp checkout or has no
# business spending 32 cores on a Vulkan rebuild during a routine `dotfiles_update`.
#
# Two signals, both required. The CPU match is deliberately "RYZEN AI MAX" rather than
# the exact "MAX+ 395 w/ Radeon 8060S" string so a 385 or a BIOS that reformats the
# model name still matches; omarchy pins it to this desktop rather than a bare Arch
# server that happens to share the silicon.
is_strix_halo_omarchy() {
  [[ -d /usr/share/omarchy ]] || return 1
  grep -qi "ryzen ai max" /proc/cpuinfo 2>/dev/null || return 1
  return 0
}

if ! is_strix_halo_omarchy; then
  # Silent on purpose: this is the common case on every other machine, and a warning
  # on each dotfiles_update would train you to ignore this script's output.
  exit 0
fi

command -v git >/dev/null 2>&1 || { warn "git not available, skipping"; exit 0; }
[[ -d "$LLAMA_DIR/.git" ]] || { say "no checkout at $LLAMA_DIR, skipping (see ryzen-llm-setup.md)"; exit 0; }

# ---- serialize ----------------------------------------------------------------------
# A login shell and a manual run can collide; two concurrent cmake builds in one
# directory corrupt object files rather than merely racing.
#
# The lock lives OUTSIDE the checkout. Putting it in the repo root made this script
# fail its own "working tree is dirty" check on the very next run -- the lock showed up
# as an untracked file, so it pulled nothing and built nothing, silently.
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/dotfiles-llamacpp-update.lock"
exec 9>"$LOCK_FILE" 2>/dev/null || true
if command -v flock >/dev/null 2>&1; then
  flock -n 9 || { warn "another update is already running, skipping"; exit 0; }
fi

cd "$LLAMA_DIR" || exit 0

# ---- never clobber local work -------------------------------------------------------
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  warn "working tree at $LLAMA_DIR is dirty -- not pulling, not building"
  warn "  commit/stash there, or set LLAMACPP_SKIP_UPDATE=1 to silence this"
  exit 0
fi

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"

# ---- fast-forward -------------------------------------------------------------------
# Only when we are actually on the tracked ref. A deliberate PR-branch checkout (which
# is how the qwen4exp situation above started) keeps its source untouched but still gets
# its BINARY rebuilt below, so a pinned branch is never silently served by a stale build.
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
if [[ -n "${LLAMACPP_BUILD_FORCE:-}" ]]; then
  NEEDS_BUILD=1; REASON="LLAMACPP_BUILD_FORCE set"
elif [[ ! -x "$BUILD_DIR/bin/llama-server" ]]; then
  NEEDS_BUILD=1; REASON="llama-server is not built yet"
elif [[ "$BUILT_SHA" == none ]]; then
  # No stamp: either a build predating this script, or one that never finished. Both
  # are unproven, so rebuild. Costs nothing when the tree really is current -- make
  # has nothing to do and the run is a few seconds.
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
# Vulkan only, matching ryzen-llm-setup.md; GGML_HIP stays OFF (Phase 4 uses a separate
# build-hip/ tree). ccache is installed on this box but was never wired into the build
# -- 0 hits out of 54 lookups -- which is most of why a routine rebuild was expensive
# enough to put off. Setting the launcher on an existing cache is a re-configure, not a
# wipe: the Vulkan shader outputs in build/ survive.
CMAKE_ARGS=(
  -S "$LLAMA_DIR" -B "$BUILD_DIR"
  -DCMAKE_BUILD_TYPE=Release
  -DGGML_VULKAN=ON
  -DGGML_HIP=OFF
)
if command -v ccache >/dev/null 2>&1; then
  CMAKE_ARGS+=(-DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache)
fi

if ! cmake "${CMAKE_ARGS[@]}" >/dev/null; then
  bad "cmake configure failed -- build/ left as-is, stamp untouched"
  exit 1
fi

# ---- build --------------------------------------------------------------------------
# Half the cores, same "leave headroom" reasoning as the router's CPUQuota in
# install.sh: this can run while the routers are serving.
JOBS="${LLAMACPP_BUILD_JOBS:-$(( $(nproc) / 2 ))}"
((JOBS < 1)) && JOBS=1
say "building with -j$JOBS (this takes a while)..."

if ! cmake --build "$BUILD_DIR" -j"$JOBS"; then
  bad "build FAILED -- stamp left at '$BUILT_SHA', next run will retry"
  bad "  the routers keep running the previous binary, which is the safe outcome"
  exit 1
fi

# Only now is the build proven. Anything that dies before this line leaves the stamp
# stale, which is the whole point.
echo "$HEAD_SHA" > "$STAMP"
good "built $(git rev-parse --short "$HEAD_SHA")"

# ---- report, never restart ----------------------------------------------------------
# Deliberately does NOT restart the routers: a restart drops in-flight generation, and
# a long prompt ingest can be minutes of work. But do not stay quiet about it either --
# an un-restarted router is the exact state that hid the qwen4exp problem.
#
# Worth knowing while it is pending: the router forks a child per model, so once
# libllama.so is replaced a NEWLY autoloaded child runs the new code under a parent
# still mapped to the old. Restart at the next natural break rather than sitting on it.
RESTART_NEEDED=()
for unit in llama-router.service llama-router-cheap.service; do
  if systemctl --user is-active --quiet "$unit" 2>/dev/null; then
    RESTART_NEEDED+=("$unit")
  fi
done

if ((${#RESTART_NEEDED[@]} > 0)); then
  echo
  warn "these are still running the PREVIOUS binary -- restart when idle:"
  for unit in "${RESTART_NEEDED[@]}"; do
    warn "  systemctl --user restart $unit"
  done
fi
