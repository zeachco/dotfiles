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

  echo "==> $repo :: ${file##*/}"
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
