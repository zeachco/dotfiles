#!/bin/sh

# ==============================================================================
# AI UTILITIES (local ollama models)
# ==============================================================================

# Our JIRA tickets follow the format ${JIRA_PREFIX}<number>, e.g. PED-1234
JIRA_PREFIX="PED-"

# Trace helper: set DEBUG=true to dump inputs/outputs of the AI tools to stderr
_ai_debug() {
  [ "$DEBUG" = "true" ] || return 0
  printf '[debug] %s\n' "$@" >&2
}

# Run any command (aliases included) with debug tracing: `debug wt <url>`
# NOTE: `DEBUG=true wt ...` does NOT work — the _set aliases expand to
# `use '...' && <fn>`, so the prefix assignment only applies to `use`.
debug() {
  DEBUG=true eval "$*"
}

# Summarize a JIRA ticket or GitHub PR description into a short agent-workflow tab name.
# Usage: gh pr view 123 --json body -q .body | summarize --len=30 --retries=3 [--model=tinyllama]
# Prints only the summary (exit 0), or a failure message at the end (exit 1).
# Default model is overridable with SUMMARIZE_MODEL (ollama pulls it on first use).
summarize() {
  local max_length=80 retries=3 content=""
  local model="${SUMMARIZE_MODEL:-oamazonasgabriel/qwen3.5-0.8b:q8-8gbGPU}"

  for arg in "$@"; do
    case "$arg" in
    --len=*) max_length="${arg#*=}" ;;
    --retries=*) retries="${arg#*=}" ;;
    --model=*) model="${arg#*=}" ;;
    --*)
      echo "summarize: unknown option '$arg'" >&2
      return 1
      ;;
    *) content="$content $arg" ;;
    esac
  done

  if [ -z "$content" ]; then
    content=$(cat)
  fi
  if [ -z "$content" ]; then
    echo "summarize: no content provided (pipe it in or pass it as arguments)" >&2
    return 1
  fi
  # keep small models focused: they lose the instructions on very long inputs
  content=$(printf '%s' "$content" | head -c 2000)

  _ai_debug "summarize: model=$model len=$max_length retries=$retries" \
    "summarize: input (${#content} chars) >>>" "$content" "<<<"

  local esc=$(printf '\033')
  local attempt=0 prompt raw result length
  while true; do
    prompt=$(cat <<EOF
A JIRA ticket description or a GitHub PR description follows.
Summarize it all in a few words to generate the tab name of an agent workflow.
Answer with a single line of at most ${max_length} characters.

IMPORTANT: Your entire response must be the tab title alone, nothing else.
No introduction, no explanation, no comments, no quotes, and no label
in front of it. Never wrap the title in an English sentence.

${content}
EOF
    )
    raw=$(printf '%s\n' "$prompt" | ollama run --hidethinking --nowordwrap "$model" 2>/dev/null)
    # strip ANSI escapes, keep the first non-empty line, drop wrapping quotes/punctuation
    result=$(printf '%s\n' "$raw" |
      sed -E "s/${esc}\[[0-9;?]*[a-zA-Z]//g" |
      sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' |
      grep -m 1 . |
      sed -E 's/^["'"'"'`]+//; s/["'"'"'`.:;,!]+$//')
    # small models love prefixing labels despite instructions; strip them
    result=$(printf '%s\n' "$result" | awk '{
      if (match(tolower($0), /^(tab )?(title|summary|name|answer|response|agent workflow( name)?)[ \t]*:[ \t]*/))
        $0 = substr($0, RLENGTH + 1)
      print
    }')
    length=${#result}

    _ai_debug "summarize: attempt $((attempt + 1)) raw output (${#raw} chars) >>>" "$raw" "<<<" \
      "summarize: attempt $((attempt + 1)) cleaned ($length chars): $result"

    # reject degenerate answers (small models sometimes emit 1-2 chars)
    if [ "$length" -ge 4 ] && [ "$length" -le "$max_length" ]; then
      echo "$result"
      return 0
    fi

    attempt=$((attempt + 1))
    if [ "$attempt" -gt "$retries" ]; then
      echo "summarize: got $length chars (max $max_length), giving up after $attempt attempt(s)" >&2
      return 1
    fi
    echo "summarize: got $length chars (max $max_length), retrying ($attempt/$retries)..." >&2
    sleep 1
  done
}
