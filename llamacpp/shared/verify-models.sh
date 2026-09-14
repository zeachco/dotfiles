#!/usr/bin/env bash
# Integrity verification for downloaded GGUF models. SOURCE OF TRUTH is HuggingFace's
# per-object SHA-256, recorded at fetch time by _fetch-lib.sh into a .provenance sidecar.
#
# PORTABILITY: same bash 3.2 / BSD userland constraints as _fetch-lib.sh -- no
# associative arrays, no mapfile, no ${var,,}, no globstar, no `sed -i` without an arg.
#
# WHY NOT THE OBVIOUS TOOLS (all four verified empirically 2026-09-14, see notes):
#
#  1. `llama-gguf-hash --sha256` is NOT the file's checksum. It hashes TENSOR PAYLOADS
#     only, so it can never be compared against HuggingFace. On a 0-tensor file it
#     happily prints the SHA-256 of the empty string:
#       ggml-vocab-gemma-4.gguf -> gguf-hash e3b0c442...b855 (empty-string digest)
#                                  real file 58b1ba0b...bb65
#     It is still useful, but only as a LOCAL manifest for bitrot (see --offline).
#
#  2. `llama-gguf <f> r` does not validate real models. examples/gguf/gguf.cpp:225
#     compares every element against `100 + i` -- the synthetic pattern that
#     `llama-gguf w` writes. It is a round-trip unit test; on a real model it is noise.
#
#  3. Both llama.cpp gguf tools CRASH on a malformed header rather than erroring out:
#     llama-gguf aborts via GGML_ASSERT (SIGABRT), llama-gguf-hash segfaults (SIGSEGV).
#     Each crash lands a core in systemd-coredump and fires a desktop crash
#     notification. So the header is parsed HERE, in the shell, and the llama.cpp
#     tools are only ever run on a file whose header already parsed clean.
#
#  4. The `etag` on the final CDN 200 is the XET hash, not SHA-256 -- a decoy that
#     looks exactly like the real thing. Only `x-linked-etag`, returned on the
#     huggingface.co 302, is the SHA-256. _fetch-lib.sh reads the right one.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

HF="${HF:-https://huggingface.co}"
MODE=quick
ROOT=""
FAILED=0
CHECKED=0
SKIPPED=0

LLAMA_BIN="${LLAMA_BIN:-$HOME/dev/llama.cpp/build/bin}"

usage() {
  cat <<'EOF'
usage: verify-models.sh [MODE] [--dir DIR] [FILE...]

Modes (pick one; default --quick):
  --quick     Header parse + size against recorded provenance.   Seconds. No full read.
  --full      Adds SHA-256 of every byte vs the upstream digest.  Authoritative. Slow.
  --offline   Like --full but never touches the network; compares against the
              .provenance sidecar only. Use for scheduled bitrot sweeps.
  --load      Functional test: actually load each model and generate a few tokens.

Options:
  --dir DIR   Root to scan (default: ~/models, or $LOS_MODELS_DIR).
  -h, --help  This message.

Exit status is non-zero if any model fails.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --quick)   MODE=quick ;;
    --full)    MODE=full ;;
    --offline) MODE=offline ;;
    --load)    MODE=load ;;
    # Guarded: a bare trailing --dir would otherwise trip `set -u` with an
    # "unbound variable" abort instead of a usage message.
    --dir)     [ $# -ge 2 ] || { echo "--dir needs a directory" >&2; exit 2; }
               ROOT="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    --*)       echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)         break ;;
  esac
  shift
done

[ -n "$ROOT" ] || ROOT="${LOS_MODELS_DIR:-$HOME/models}"

# --- helpers -------------------------------------------------------------------

# BSD shasum vs GNU sha256sum. Both print "<hash>  <path>".
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# Parse the GGUF header WITHOUT the llama.cpp tools, which crash on bad input (note 3).
# Layout: magic[4] "GGUF" | version u32 | n_tensors u64 | n_kv u64, all little-endian.
# Echoes "version n_tensors n_kv" and returns non-zero on anything malformed.
gguf_header() {
  local f="$1" magic version n_tensors n_kv size
  size=$(wc -c <"$f" | tr -d ' ')
  [ "$size" -ge 24 ] || { echo "file shorter than a GGUF header ($size bytes)"; return 1; }

  magic=$(od -A n -c -N 4 "$f" | tr -d ' \n')
  [ "$magic" = "GGUF" ] || { echo "bad magic '$magic', expected GGUF"; return 1; }

  version=$(od -A n -t u4 -j 4  -N 4 "$f" | tr -d ' \n')
  n_tensors=$(od -A n -t u8 -j 8  -N 8 "$f" | tr -d ' \n')
  n_kv=$(od -A n -t u8 -j 16 -N 8 "$f" | tr -d ' \n')

  # v1/v2 predate the current alignment and string encoding; llama.cpp will refuse them.
  case "$version" in
    3) ;;
    1|2) echo "GGUF version $version is obsolete (llama.cpp expects 3)"; return 1 ;;
    *)   echo "implausible GGUF version '$version'"; return 1 ;;
  esac

  # A model with no tensors is a vocab-only file, never something the router can serve.
  [ "$n_tensors" -gt 0 ] 2>/dev/null || { echo "0 tensors (vocab-only or truncated)"; return 1; }
  [ "$n_kv" -gt 0 ] 2>/dev/null      || { echo "0 metadata keys"; return 1; }

  echo "$version $n_tensors $n_kv"
}

# Look up a recorded fetch. Sidecar is TSV: file<TAB>repo<TAB>remote_path<TAB>sha256<TAB>size
# Keyed on (directory, filename) because a basename alone is AMBIGUOUS: mmproj-F16.gguf
# ships from three different repos in fetch-models.sh, and mmproj-BF16.gguf from three
# more on the Mac. Resolving by basename would compare a gemma projector against qwen's.
provenance_line() {
  local dir="$1" base="$2" sidecar="$1/.provenance"
  [ -f "$sidecar" ] || return 1
  awk -F '\t' -v b="$base" '$1 == b { print; found = 1; exit } END { exit !found }' "$sidecar"
}

# Authoritative upstream digest. Reads x-linked-etag off the huggingface.co 302, NOT the
# etag on the CDN 200 (note 4). Falls back to the tree API, whose .lfs.oid is the same
# value -- verified byte-identical for GLM-4.7-Flash-UD-Q4_K_XL.gguf on 2026-09-14.
remote_sha256() {
  local repo="$1" file="$2" sha
  sha=$(curl -sIL --fail --max-time 30 "$HF/$repo/resolve/main/$file" 2>/dev/null \
    | tr -d '\r' \
    | awk 'tolower($1) == "x-linked-etag:" { gsub(/"/, "", $2); print $2; exit }')
  if [ -z "$sha" ] && command -v jq >/dev/null 2>&1; then
    sha=$(curl -fsS --max-time 30 "$HF/api/models/$repo/tree/main" 2>/dev/null \
      | jq -r --arg p "$file" '.[] | select(.path == $p) | .lfs.oid // empty' 2>/dev/null)
  fi
  [ -n "$sha" ] && echo "$sha"
}

pass() { echo "  OK      $1"; }
fail() { echo "  FAIL    $1" >&2; FAILED=$((FAILED + 1)); }
skip() { echo "  skip    $1"; SKIPPED=$((SKIPPED + 1)); }

# --- per-file verification -----------------------------------------------------

verify_file() {
  local f="$1"
  local dir base hdr line repo remote_path want_sha want_size have_size have_sha
  dir="$(dirname "$f")"
  base="${f##*/}"
  CHECKED=$((CHECKED + 1))

  echo "$f"

  # Layer 1: structure. Cheap, offline, and it gates every tool run below.
  if ! hdr=$(gguf_header "$f"); then
    fail "$hdr"
    return 1
  fi
  set -- $hdr
  pass "GGUF v$1, $2 tensors, $3 metadata keys"

  have_size=$(wc -c <"$f" | tr -d ' ')

  # Layer 2: provenance. Without it there is nothing to compare against.
  if ! line=$(provenance_line "$dir" "$base"); then
    skip "no provenance record -- re-fetch to capture one, or verify by hand"
    return 0
  fi
  repo=$(echo "$line" | cut -f2)
  remote_path=$(echo "$line" | cut -f3)
  want_sha=$(echo "$line" | cut -f4)
  want_size=$(echo "$line" | cut -f5)

  if [ -n "$want_size" ] && [ "$want_size" != "$have_size" ]; then
    fail "size $have_size != upstream $want_size ($repo)"
    return 1
  fi
  pass "size $have_size matches $repo"

  [ "$MODE" = quick ] && return 0
  [ "$MODE" = load ]  && return 0

  # Layer 3: bytes. The only check that actually proves the download is intact --
  # a resumed curl can land the right SIZE with wrong CONTENT, which is precisely
  # the failure size comparison cannot see.
  if [ "$MODE" = full ]; then
    local upstream
    upstream=$(remote_sha256 "$repo" "$remote_path")
    if [ -z "$upstream" ]; then
      echo "  warn    upstream digest unreachable; using recorded value"
    elif [ "$upstream" != "$want_sha" ]; then
      echo "  warn    upstream digest changed since fetch ($want_sha -> $upstream);"
      echo "          the repo was re-uploaded. Comparing against the CURRENT upstream."
      want_sha="$upstream"
    fi
  fi

  [ -n "$want_sha" ] || { skip "no recorded digest"; return 0; }

  have_sha=$(sha256_of "$f")
  if [ "$have_sha" != "$want_sha" ]; then
    fail "sha256 mismatch"
    echo "          have $have_sha" >&2
    echo "          want $want_sha" >&2
    return 1
  fi
  pass "sha256 $have_sha"
}

# --- functional load test ------------------------------------------------------
#
# The checks above prove the bytes are what upstream shipped. They do NOT prove the
# model runs on THIS build against THIS backend -- a valid GGUF using an op the local
# Vulkan backend lacks passes every byte check and still fails at load.
load_test() {
  local f="$1"
  local base="${f##*/}"
  echo "$f"

  # Not every .gguf is a standalone model. Projectors, MTP/EAGLE3 draft heads and
  # individual shards are loaded BY a model, never as one, so a load failure here
  # would be a false alarm. The byte checks above already cover them.
  case "$base" in
    mmproj*|mtp-*|eagle3-*|*-of-*)
      skip "not a standalone model (projector/draft/shard); byte checks still apply"
      return 0 ;;
  esac

  # llama-completion over llama-cli: no chat template required, so a base model
  # without one is not reported as broken. -st on llama-cli is the fallback
  # (-no-cnv was REMOVED from this build; using it fails with "invalid argument").
  local bin args rc out
  if [ -x "$LLAMA_BIN/llama-completion" ]; then
    bin="$LLAMA_BIN/llama-completion"; args="--no-warmup"
  elif [ -x "$LLAMA_BIN/llama-cli" ]; then
    bin="$LLAMA_BIN/llama-cli"; args="-st --no-warmup"
  else
    skip "no llama-completion or llama-cli under $LLAMA_BIN"
    return 0
  fi

  CHECKED=$((CHECKED + 1))
  out=$("$bin" -m "$f" -ngl 999 $args -p "The capital of France is" -n 8 --temp 0 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "failed to load/generate (exit $rc)"
    echo "$out" | tail -6 | sed 's/^/          /' >&2
    return 1
  fi
  pass "loaded and generated on the local backend"
}

# --- main ----------------------------------------------------------------------

if [ ! -d "$ROOT" ]; then
  echo "no such directory: $ROOT" >&2
  exit 2
fi

echo "Verifying GGUF models under $ROOT (mode: $MODE)"
echo

# find rather than globstar (bash 3.2). Shards and projectors are verified like any
# other file: a corrupt mmproj breaks vision just as thoroughly as a corrupt model.
TMP_LIST="${TMPDIR:-/tmp}/verify-models.$$"
if [ $# -gt 0 ]; then
  printf '%s\n' "$@" >"$TMP_LIST"
else
  find "$ROOT" -type f -name '*.gguf' 2>/dev/null | sort >"$TMP_LIST"
fi

if [ ! -s "$TMP_LIST" ]; then
  echo "No .gguf files found under $ROOT." >&2
  echo "If the routers are advertising models anyway, they are reading NAMES from the" >&2
  echo "preset .ini files, not from disk -- see llamacpp/archlinux/light.ini." >&2
  rm -f "$TMP_LIST"
  exit 1
fi

while IFS= read -r f; do
  [ -f "$f" ] || { echo "$f"; fail "not a regular file"; continue; }
  if [ "$MODE" = load ]; then
    load_test "$f"
  else
    verify_file "$f"
  fi
  echo
done <"$TMP_LIST"
rm -f "$TMP_LIST"

echo "---"
echo "checked $CHECKED, failed $FAILED, skipped $SKIPPED"
if [ "$FAILED" -gt 0 ]; then
  echo
  echo "Re-fetch a corrupt model by deleting it and re-running the fetch script:" >&2
  echo "  rm <file> && bash $SCRIPT_DIR/../archlinux/fetch-models.sh" >&2
  exit 1
fi
exit 0
