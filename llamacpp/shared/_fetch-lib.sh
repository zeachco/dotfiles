# Shared HuggingFace download helper for fetch-models*.sh. SOURCED, not executed.
#
# PORTABILITY: macOS ships bash 3.2.57 with no Homebrew bash available, so nothing in
# here may use associative arrays, ${var,,}, mapfile/readarray or globstar. It is easy
# to write bash 5 on the Linux box and break the Mac silently. Same for userland:
# BSD awk has no IGNORECASE, BSD sed has no -i without an argument.

HF="${HF:-https://huggingface.co}"
FETCH_FAILURES=0

# PLAN MODE (LOS_FETCH_PLAN=<file>): nothing is downloaded, verified, linked or reloaded.
# fetch() still runs its size pre-check and appends every file that is missing or
# differs from upstream to the plan file as "<repo>\t<file>\t<dest>\t<bytes>", so a
# fetch script run twice -- once in plan mode, once for real -- yields a "what would be
# downloaded" list first. bin/llamacpp-fetch-missing builds its confirmation prompt
# from that list. fetch_dir_model's directory guard applies in plan mode too, so a
# legacy quant on disk never shows up as "missing".
FETCH_PLAN="${LOS_FETCH_PLAN:-}"

# SELECT MODE (LOS_FETCH_SELECT=<file>): only the files listed in it, one "<repo>\t<file>"
# per line exactly as the plan wrote them, are fetched; every other fetch() call is a
# silent skip. bin/llamacpp-fetch-missing writes it from an fzf multi-selection over the
# plan on a box with no models yet, so a first install downloads what was picked and
# nothing else. Plan mode and select mode are never active together.
FETCH_SELECT="${LOS_FETCH_SELECT:-}"
fetch_selected() { # repo file
  [ -n "$FETCH_SELECT" ] || return 0
  grep -qxF "$(printf '%s\t%s' "$1" "$2")" "$FETCH_SELECT" 2>/dev/null
}

# fetch <repo> <file> <destdir>
#
# Resumable AND idempotent. The idempotence guard is the point: plain `curl -C -` on
# an already-complete file sends `Range: bytes=<size>-`, the CDN answers 416, and
# --fail turns that into a non-zero exit -- so without a size pre-check a second run
# reports every finished model as FAILED. Compare sizes first and skip.
fetch() {
  local repo="$1" file="$2" dest="$3"
  local out="$dest/${file##*/}"
  local url="$HF/$repo/resolve/main/$file"
  local remote local_size remote_meta remote_sha

  fetch_selected "$repo" "$file" || return 0

  # HF sets x-linked-size for LFS objects, which is the true object size;
  # content-length on the redirect chain is the fallback. tolower($1) rather than
  # gawk's IGNORECASE, which BSD awk does not have.
  #
  # x-linked-etag comes off the SAME HEAD and is the object's SHA-256 -- the only
  # thing that can later prove the bytes on disk are the bytes upstream shipped.
  # It is emitted ONLY on the huggingface.co 302. Do not reach for the `etag` on the
  # final CDN 200: that is the xet hash, identical in shape (64 hex chars) and
  # completely different in value, so mixing them up fails silently forever.
  # Verified 2026-09-14 against unsloth/gemma-4-E2B-it-GGUF: x-linked-etag and the
  # tree API's .lfs.oid both equal `sha256sum` of the downloaded file; the CDN etag
  # does not. Emitted as "<size>\t<sha256>" so one HEAD yields both.
  remote_meta="$(curl -sIL --fail --max-time 30 "$url" 2>/dev/null \
    | tr -d '\r' \
    | awk 'tolower($1) == "x-linked-size:" { x = $2 }
           tolower($1) == "content-length:" { c = $2 }
           tolower($1) == "x-linked-etag:"  { e = $2; gsub(/"/, "", e) }
           END { if (x != "") printf "%s", x; else printf "%s", c
                 printf "\t%s\n", e }')"
  remote="${remote_meta%%$'\t'*}"
  remote_sha="${remote_meta#*$'\t'}"

  if [ -f "$out" ] && [ -n "$remote" ]; then
    local_size="$(wc -c <"$out" | tr -d ' ')"
    if [ "$local_size" = "$remote" ]; then
      [ -n "$FETCH_PLAN" ] || echo "==> $repo :: ${file##*/} (complete, skipping)"
      # Backfill on the skip path too, so re-running a fetch gives models that were
      # already on disk a provenance record without re-downloading them.
      record_provenance "$dest" "${file##*/}" "$repo" "$file" "$remote_sha" "$remote"
      return 0
    fi
  fi

  if [ -n "$FETCH_PLAN" ]; then
    # A HEAD that failed leaves $remote empty; the real run will report that as a
    # failure, so plan it as a download of unknown size rather than hiding it.
    printf '%s\t%s\t%s\t%s\n' "$repo" "$file" "$dest" "${remote:-0}" >>"$FETCH_PLAN"
    return 0
  fi

  mkdir -p "$dest"

  # Announce an in-place OVERWRITE distinctly from a first download. A local file
  # whose size differs from upstream is a stale or foreign build (a different quant
  # revision, or one that came out of a retired daemon's blob store), and curl -o rewrites the
  # SAME inode rather than replacing it -- so if a llama-server child still has that
  # file mapped, its weights change underneath it. Fully GPU-offloaded models (-ngl
  # 999) release the mapping after load and are unaffected, but a CPU-resident or
  # partially-offloaded one is not. Unload the model first if this line appears:
  #   curl -s -X POST localhost:7070/models/unload -H 'content-type: application/json' \
  #     -d '{"model":"<id>"}'
  if [ -f "$out" ]; then
    echo "==> $repo :: ${file##*/} (OVERWRITING in place: local $local_size != remote $remote)"
  else
    echo "==> $repo :: ${file##*/}"
  fi
  if ! curl -L --fail --retry 10 --retry-delay 5 --retry-all-errors -C - \
    --progress-bar -o "$out" "$url"; then
    echo "FAILED: $repo/$file" >&2
    FETCH_FAILURES=$((FETCH_FAILURES + 1))
    return 1
  fi
  record_provenance "$dest" "${file##*/}" "$repo" "$file" "$remote_sha" "$remote"
}

# record_provenance <destdir> <basename> <repo> <remote_path> <sha256> <size>
#
# Appends to <destdir>/.provenance, the TSV that verify-models.sh checks against:
#   basename <TAB> repo <TAB> remote_path <TAB> sha256 <TAB> size
#
# Keyed on basename WITHIN a directory, never globally: mmproj-F16.gguf ships from
# three different repos in fetch-models.sh (gemma-4-E2B, gemma-4-E4B, gemma-4-26B) and
# mmproj-BF16.gguf from three more on the Mac, so a global basename index would check a
# gemma projector against qwen's digest and report a bogus mismatch.
#
# Rewrite-then-rename rather than >> so a re-download replaces its old row instead of
# leaving two rows for one file. awk (not grep -v) because a basename may contain
# regex metacharacters -- `gpt-oss-120b-MXFP4.gguf` has dots that would match anything.
record_provenance() {
  local dest="$1" base="$2" repo="$3" path="$4" sha="$5" size="$6"
  # No digest means the HEAD failed or the object is not LFS-backed. Record nothing
  # rather than a row that would later read as "verified" against an empty digest.
  [ -n "$sha" ] || return 0
  local sidecar="$dest/.provenance" tmp="$dest/.provenance.$$"
  if [ -f "$sidecar" ]; then
    awk -F '\t' -v b="$base" '$1 != b' "$sidecar" >"$tmp" || return 0
  else
    : >"$tmp"
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$base" "$repo" "$path" "$sha" "$size" >>"$tmp"
  mv "$tmp" "$sidecar"
}

# List what a repo actually ships. A wrong filename is the single biggest source of a
# wasted multi-GB run, and --fail on a 404 is the only signal you get.
hf_ls() {
  curl -fsS "$HF/api/models/$1" | jq -r '.siblings[].rfilename'
}

# Call at the end of a fetch script so a 404'd filename cannot exit 0.
fetch_report() {
  [ -z "$FETCH_PLAN" ] || return 0
  if [ "$FETCH_FAILURES" -gt 0 ]; then
    echo "$FETCH_FAILURES download(s) failed. Check filenames with: hf_ls <repo>" >&2
    return 1
  fi
  return 0
}

# fetch_dir_model <repo> <destdir> <file> [file...]
#
# Fetches a whole subdirectory model ATOMICALLY: all its files, or none. Skips the
# directory entirely if it already holds a main GGUF under ANY filename.
#
# Two reasons it cannot be a plain fetch() per file:
#
#  1. For a subdirectory model the id is the DIRECTORY name, and scan_subdir() in
#     llama.cpp's common/preset.cpp assigns model_file from whichever
#     non-mmproj/non-draft/non-shard GGUF it iterates LAST. Two model files in one
#     directory therefore make that id resolve nondeterministically. fetch()'s per-file
#     size pre-check cannot see a differently-named sibling.
#  2. A model and its projector must come from the SAME source. Guarding only the model
#     file would still let the projector be replaced: ~/models/llama/qwen3.8 holds a
#     legacy mmproj-F16.gguf of 931146016 bytes where unsloth ships 927607488,
#     so fetch() would see a size mismatch and overwrite a working projector, leaving a
#     legacy model paired with an unsloth one.
#
# The case that needs it: ~/models/llama/qwen3.8 is a legacy plain Q4_K_M named
# qwen3.8-Q4_K_M.gguf, predating this recipe, which yields Qwen3.8-27B-UD-Q4_K_M.gguf.
# Same model, different quant. A fresh machine gets the unsloth pair; this one keeps
# what it has. The id is `qwen3.8` either way, because it is the directory name.
#
# Glob loop rather than `find -print -quit`: bash 3.2 / BSD userland (see PORTABILITY).
fetch_dir_model() {
  local repo="$1" dest="$2"
  shift 2
  local f file

  for f in "$dest"/*.gguf; do
    [ -f "$f" ] || continue                       # unmatched glob expands to itself
    case "${f##*/}" in
      mmproj*)  continue ;;                       # projector, not the model
      *-of-*)   continue ;;                       # shard of a split model, not the model
    esac
    [ -n "$FETCH_PLAN" ] || echo "==> $repo :: $dest (already has ${f##*/}, skipping directory)"
    return 0
  done

  for file in "$@"; do
    fetch "$repo" "$file" "$dest" || return 1
  done
}

# provenance_move <srcdir> <dstdir> <basename>
#
# For scripts that download into a STAGING directory and then mv a single file out
# (fetch-initial-models.sh does this for GLM): the file moves, its .provenance row
# does not. Carry the row along so verify-models.sh can still find it.
provenance_move() {
  local src="$1" dst="$2" base="$3" line
  line="$(awk -F '\t' -v b="$base" '$1 == b { print; exit }' "$src/.provenance" 2>/dev/null)"
  [ -n "$line" ] || return 0
  record_provenance "$dst" "$base" \
    "$(echo "$line" | cut -f2)" "$(echo "$line" | cut -f3)" \
    "$(echo "$line" | cut -f4)" "$(echo "$line" | cut -f5)"
  awk -F '\t' -v b="$base" '$1 != b' "$src/.provenance" >"$src/.provenance.$$" &&
    mv "$src/.provenance.$$" "$src/.provenance"
}

# fetch_verify <dir> [dir...]
#
# Full SHA-256 verification of everything under each dir against the digests recorded
# at fetch time. Runs at the END of a fetch, when the read is worth its cost: this is
# the only check that catches a `curl -C -` resume landing the right SIZE with the
# wrong BYTES, which the size pre-check in fetch() cannot see and which then fails at
# load as if the model were at fault (llamacpp-audit's GLM-at-1.10-of-16.32-GiB case
# was the truncated flavour of this; the same-size flavour has no other detector).
# A failure counts as a fetch failure, so fetch_report exits non-zero.
fetch_verify() {
  local verify dir
  [ -z "$FETCH_PLAN" ] || return 0
  verify="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/verify-models.sh"
  for dir in "$@"; do
    [ -d "$dir" ] || continue
    # -type f, matching verify-models.sh: a symlinked model is verified at its target,
    # and counting the link here would turn an empty verify run into a false failure.
    [ -n "$(find "$dir" -type f -name '*.gguf' -print 2>/dev/null | head -1)" ] || continue
    echo
    echo "==> verifying $dir against upstream digests"
    if ! bash "$verify" --full --dir "$dir"; then
      echo "VERIFY FAILED under $dir -- delete the file(s) named above and re-run this script" >&2
      FETCH_FAILURES=$((FETCH_FAILURES + 1))
    fi
  done
}

# routers_reload <port> [port...]
#
# Ask the running router to rescan --models-dir instead of restarting it: a restart
# drops in-flight generation, a reload (server-models.cpp, GET /v1/models?reload=1)
# only adds what is new and drops what is gone. An unreachable router is reported, not
# treated as an error -- on a first install it may not be up yet.
routers_reload() {
  local p
  [ -z "$FETCH_PLAN" ] || return 0
  for p in "$@"; do
    if curl -sf -m 5 "http://127.0.0.1:$p/v1/models?reload=1" >/dev/null 2>&1; then
      echo "==> router :$p reloaded its model list"
    else
      echo "==> router :$p not reachable; it will pick the models up when it starts"
    fi
  done
}
