# Shared HuggingFace download helper for fetch-models*.sh. SOURCED, not executed.
#
# PORTABILITY: macOS ships bash 3.2.57 with no Homebrew bash available, so nothing in
# here may use associative arrays, ${var,,}, mapfile/readarray or globstar. It is easy
# to write bash 5 on the Linux box and break the Mac silently. Same for userland:
# BSD awk has no IGNORECASE, BSD sed has no -i without an argument.

HF="${HF:-https://huggingface.co}"
FETCH_FAILURES=0

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
  local remote local_size

  mkdir -p "$dest"

  # HF sets x-linked-size for LFS objects, which is the true object size;
  # content-length on the redirect chain is the fallback. tolower($1) rather than
  # gawk's IGNORECASE, which BSD awk does not have.
  remote="$(curl -sIL --fail --max-time 30 "$url" 2>/dev/null \
    | tr -d '\r' \
    | awk 'tolower($1) == "x-linked-size:" { x = $2 }
           tolower($1) == "content-length:" { c = $2 }
           END { if (x != "") print x; else print c }')"

  if [ -f "$out" ] && [ -n "$remote" ]; then
    local_size="$(wc -c <"$out" | tr -d ' ')"
    if [ "$local_size" = "$remote" ]; then
      echo "==> $repo :: ${file##*/} (complete, skipping)"
      return 0
    fi
  fi

  # Announce an in-place OVERWRITE distinctly from a first download. A local file
  # whose size differs from upstream is a stale or foreign build (a different quant
  # revision, or one that came out of ollama's blob store), and curl -o rewrites the
  # SAME inode rather than replacing it -- so if a llama-server child still has that
  # file mapped, its weights change underneath it. Fully GPU-offloaded models (-ngl
  # 999) release the mapping after load and are unaffected, but a CPU-resident or
  # partially-offloaded one is not. Unload the model first if this line appears:
  #   curl -s -X POST localhost:8080/models/unload -H 'content-type: application/json' \
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
}

# List what a repo actually ships. A wrong filename is the single biggest source of a
# wasted multi-GB run, and --fail on a 404 is the only signal you get.
hf_ls() {
  curl -fsS "$HF/api/models/$1" | jq -r '.siblings[].rfilename'
}

# Call at the end of a fetch script so a 404'd filename cannot exit 0.
fetch_report() {
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
#     file would still let the projector be replaced: ~/models/light/qwen3.8 holds an
#     ollama-derived mmproj-F16.gguf of 931146016 bytes where unsloth ships 927607488,
#     so fetch() would see a size mismatch and overwrite a working projector, leaving an
#     ollama model paired with an unsloth one.
#
# The case that needs it: ~/models/light/qwen3.8 is an ollama-derived plain Q4_K_M named
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
    echo "==> $repo :: $dest (already has ${f##*/}, skipping directory)"
    return 0
  done

  for file in "$@"; do
    fetch "$repo" "$file" "$dest" || return 1
  done
}
