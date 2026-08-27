#!/bin/sh

# ==============================================================================
# AI UTILITIES (local llama.cpp models)
# ==============================================================================

# Our JIRA tickets follow the format ${JIRA_PREFIX}<number>, e.g. PED-1234
JIRA_PREFIX="PED-"

# Trace helper: set DEBUG=true to dump inputs/outputs of the AI tools to stderr
_ai_debug() {
  [ "$DEBUG" = "true" ] || return 0
  printf '[debug] %s\n' "$@" >&2
}

# Base URL of the local llama.cpp router. Every host in this repo binds :8080 --
# `los` (variants/shared/_llama.sh) on Linux, the com.zeachco.llama-router launchd
# agent on macOS. Resolved at call time, not at source time: variants/osx/profile.sh
# defines LOS_URL and there is no guaranteed source order between the two files.
_ai_url() {
  printf '%s' "${AI_LLAMA_URL:-${LOS_URL:-http://127.0.0.1:8080}}"
}

# Map a model name onto an id the router actually serves.
# The same model is named differently per host: the macOS router serves gemma out
# of a directory (`gemma-4-E2B-it`) while the Linux one names it after the HF repo
# (`gemma-4-E2B-it-GGUF`). Match the request against GET /v1/models -- exact id
# first, then a case-insensitive substring -- so one default works on both boxes.
# Falls back to the name as given, letting the server report the miss itself.
_ai_resolve_model() {
  local want="$1" ids match
  ids=$(curl -fsS --max-time 5 "$(_ai_url)/v1/models" 2>/dev/null |
    grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' |
    sed -E 's/.*"([^"]*)"$/\1/')
  if [ -z "$ids" ]; then
    _ai_debug "resolve: no answer from $(_ai_url)/v1/models, using '$want' as-is"
    printf '%s' "$want"
    return 0
  fi
  if printf '%s\n' "$ids" | grep -qxF "$want"; then
    printf '%s' "$want"
    return 0
  fi
  match=$(printf '%s\n' "$ids" | grep -i -m 1 -F "$want")
  if [ -n "$match" ]; then
    _ai_debug "resolve: '$want' -> '$match'"
    printf '%s' "$match"
    return 0
  fi
  _ai_debug "resolve: '$want' matches none of: $(printf '%s' "$ids" | tr '\n' ' ')"
  printf '%s' "$want"
}

# One-shot chat completion against the router: prompt on stdin, answer on stdout.
# Usage: printf '%s' "$prompt" | _ai_complete "$model" "$timeout_secs"
# curl's --max-time bounds the whole exchange, so a wedged server can never leave
# a caller hanging: several summarize runs queue on the router whenever a batch of
# tabs is named at once.
# jq builds the body because the prompt is arbitrary text (PR descriptions, commit
# messages) that must be JSON-escaped, never interpolated into a string.
_ai_complete() {
  local model="$1" timeout="${2:-60}" max_tokens="${3:-512}"
  if ! command -v jq >/dev/null 2>&1; then
    echo "_ai_complete: jq is required to talk to the llama.cpp router" >&2
    return 1
  fi
  # temperature is deliberately not 0: summarize retries a too-long answer, and
  # greedy decoding would hand back the exact same line every attempt.
  #
  # enable_thinking=false is what makes a one-line answer cheap: gemma 4's
  # template reasons by default and llama.cpp puts that in reasoning_content, so
  # a thinking run burns ~320 tokens to fill `content` instead of ~10. Templates
  # that do not know the kwarg simply ignore it, and max_tokens stays generous
  # enough for one of those to think its way to an answer anyway.
  jq -Rs --arg model "$model" --argjson max_tokens "$max_tokens" \
    '{model: $model, max_tokens: $max_tokens, temperature: 0.7, stream: false,
      chat_template_kwargs: {enable_thinking: false},
      messages: [{role: "user", content: .}]}' |
    curl -fsS --max-time "$timeout" \
      -H 'Content-Type: application/json' \
      --data-binary @- \
      "$(_ai_url)/v1/chat/completions" 2>/dev/null |
    jq -r '.choices[0].message.content // ""'
}

# Run any command (aliases included) with debug tracing: `debug wt <url>`
# NOTE: `DEBUG=true wt ...` does NOT work — the _set aliases expand to
# `use '...' && <fn>`, so the prefix assignment only applies to `use`.
debug() {
  DEBUG=true eval "$*"
}

# Summarize a work description (JIRA ticket, GitHub PR, or commit messages)
# into a short agent-workflow tab name.
# Usage: gh pr view 123 --json body -q .body | summarize --len=30 --retries=3 [--model=gemma-4-E2B-it]
# --kind=pr|commits tailors the prompt to the input (PR title+body vs commit
# messages); anything else keeps the generic wording. --hint=... strongly
# steers the title toward a specific aspect of the work.
# Prints only the summary (exit 0), or a failure message at the end (exit 1).
# Runs on the local llama.cpp router (AI_LLAMA_URL, default http://127.0.0.1:8080)
# against the cheapest model on the box: gemma 4 E2B, overridable with
# SUMMARIZE_MODEL. The name is resolved against GET /v1/models, so the host's own
# id for it ("gemma-4-E2B-it" or "gemma-4-E2B-it-GGUF") is picked automatically.
# Each model call is bounded by --timeout= seconds (SUMMARIZE_TIMEOUT).
summarize() {
  local max_length=80 retries=3 content="" kind="" hint=""
  local model="${SUMMARIZE_MODEL:-gemma-4-E2B-it}"
  local timeout="${SUMMARIZE_TIMEOUT:-60}"

  for arg in "$@"; do
    case "$arg" in
    --len=*) max_length="${arg#*=}" ;;
    --retries=*) retries="${arg#*=}" ;;
    --model=*) model="${arg#*=}" ;;
    --kind=*) kind="${arg#*=}" ;;
    --hint=*) hint="${arg#*=}" ;;
    --timeout=*) timeout="${arg#*=}" ;;
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

  model=$(_ai_resolve_model "$model")

  _ai_debug "summarize: model=$model len=$max_length retries=$retries timeout=${timeout}s" \
    "summarize: input (${#content} chars) >>>" "$content" "<<<"

  # tailor the first prompt line to what the caller is actually feeding in
  local intro
  case "$kind" in
  pr) intro="A GitHub pull request title and body follow.
The title usually starts with a conventional commit prefix like
\"fix(scripts): \" or \"feat(bar): PED-1234: \": drop that prefix and the
ticket id entirely, they must never appear in your answer.
Answer with a short English description of the work in 4-5 words." ;;
  commits) intro="Git commit messages from a work-in-progress branch follow." ;;
  *) intro="A description of development work follows: a JIRA ticket, a GitHub
PR description, or git commit messages." ;;
  esac

  local guidance=""
  if [ -n "$hint" ]; then
    guidance=$(printf '\nNaming guidance (prioritize this strongly): %s\n' "$hint")
  fi

  local attempt=0 prompt raw result length
  while true; do
    prompt=$(cat <<EOF
${intro}
Titles often follow the conventional commit format like
"feat(project_a): PED-1234: some work on X"; ignore the type prefix and
ticket id and describe the work itself.
Summarize it all in a few words to generate the tab name of an agent workflow.
Answer with a single line of at most ${max_length} characters.
${guidance}

IMPORTANT: Your entire response must be the tab title alone, nothing else.
No introduction, no explanation, no comments, no quotes, and no label
in front of it. Never wrap the title in an English sentence.

${content}
EOF
    )
    raw=$(printf '%s\n' "$prompt" | _ai_complete "$model" "$timeout")
    if [ -z "$raw" ]; then
      echo "summarize: '$model' produced nothing within ${timeout}s" >&2
    fi
    # drop a reasoning block first (harmless for gemma, needed as soon as
    # SUMMARIZE_MODEL points at a thinking model), then keep the first non-empty
    # line and strip wrapping quotes/punctuation
    result=$(printf '%s\n' "$raw" |
      sed -E '/<think>/,/<\/think>/d' |
      sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' |
      grep -m 1 . |
      sed -E 's/^["'"'"'`]+//; s/["'"'"'`.:;,!]+$//')
    # small models love prefixing labels despite instructions; strip them
    result=$(printf '%s\n' "$result" | awk '{
      if (match(tolower($0), /^(tab )?(title|summary|name|answer|response|agent workflow( name)?)[ \t]*:[ \t]*/))
        $0 = substr($0, RLENGTH + 1)
      print
    }')
    # small models also echo the conventional-commit prefix and ticket id from
    # the source title despite the instructions; strip them off the front
    result=$(printf '%s\n' "$result" |
      sed -E 's/^[a-zA-Z]+(\([^)]*\))?!?:[[:space:]]*//' |
      sed -E "s/^${JIRA_PREFIX}[0-9]+:?[[:space:]]*//" |
      sed -E 's/^[[:space:]]+//')
    # trim quotes once more: stripping a label or a commit prefix above can
    # expose the opening quote of a `Title: "some work"` style answer, which
    # the first pass could not see
    result=$(printf '%s\n' "$result" |
      sed -E 's/^["'"'"'`]+//; s/["'"'"'`.:;,!]+$//; s/^[[:space:]]+//; s/[[:space:]]+$//')
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

# Print the first existing main/master ref (origin preferred), or return 1.
_git_base_ref() {
  local _try
  for _try in origin/main origin/master main master; do
    if git rev-parse --verify --quiet "$_try" >/dev/null 2>&1; then
      printf '%s\n' "$_try"
      return 0
    fi
  done
  return 1
}

# Rename a zellij tab to "#<pr-number>: <summary>" from the current branch's
# PR (title + body through the model), or to "wip: <summary>" from the branch's
# commit subjects since main/master when no PR exists.
# Options:
#   --tab-id=N  the tab to rename. ALWAYS pass this when running unattended:
#               `zellij action` talks to the session, not to the pane it was
#               launched from, so the fallback below resolves the tab that is
#               focused *right now* — which is the wrong one as soon as anything
#               else (all_my_prs) opens another tab while this pane boots.
#   --pr=N      the PR number this tab belongs to, when the caller already knows
#               it. Keeps the "#N: " prefix even if `gh pr view` comes up empty,
#               so the tab stays matchable by all_my_prs' dedup check.
# Any remaining argument is a short prompt steering the summary:
# `tab_autoname "focus on auth"`.
tab_autoname() {
  if [ -z "$ZELLIJ" ]; then
    echo "Error: Not in a zellij session"
    return 1
  fi
  _git_check_repo || return 1

  local tab_id="" known_pr="" hint="" arg
  for arg in "$@"; do
    case "$arg" in
    --tab-id=*) tab_id="${arg#*=}" ;;
    --pr=*) known_pr="${arg#*=}" ;;
    *) hint="${hint:+$hint }$arg" ;;
    esac
  done

  if [ -z "$tab_id" ]; then
    # interactive use only: with no id given, the tab this was typed in is the
    # one focused at this instant
    tab_id=$(zellij action current-tab-info 2>/dev/null | sed -n 's/^id: //p')
  fi
  if [ -z "$tab_id" ]; then
    echo "Error: could not get the current tab id"
    return 1
  fi
  _ai_debug "tab-autoname: renaming tab id $tab_id (pr=${known_pr:-unknown})"

  local branch=$(git branch --show-current)
  if [ -z "$branch" ]; then
    echo "Error: not on a branch (detached HEAD?)"
    return 1
  fi

  # PR of the current branch first; commit subjects since main/master when
  # there is none
  local kind prefix desc fallback="$branch" out
  out=$(gh pr view --json title,number,body \
    --jq '(.number|tostring), .title, (.body // "")' 2>/dev/null)
  if [ -n "$out" ]; then
    kind="pr"
    prefix="#$(printf '%s\n' "$out" | head -n 1): "
    # the fallback is the raw PR title: drop its conventional-commit prefix
    # and ticket id too, so a model miss still yields "#123: <the work>"
    fallback=$(printf '%s\n' "$out" | sed -n '2p' |
      sed -E 's/^[a-zA-Z]+(\([^)]*\))?!?:[[:space:]]*//' |
      sed -E "s/^${JIRA_PREFIX}[0-9]+:?[[:space:]]*//")
    desc=$(printf '%s\n' "$out" | tail -n +2)
    _ai_debug "tab-autoname: using PR title+body for ${prefix%: }"
  else
    kind="commits"
    # a caller that knows the PR number keeps the tab keyed on it, so the dedup
    # check in all_my_prs still matches when `gh pr view` finds nothing here
    if [ -n "$known_pr" ]; then
      prefix="#${known_pr}: "
    else
      prefix="wip: "
    fi
    local base
    if base=$(_git_base_ref); then
      # keep the model input small: subjects only, newest first, capped
      desc=$(git log --format='%s' "${base}..HEAD" 2>/dev/null | head -n 30)
      [ -n "$desc" ] && _ai_debug "tab-autoname: using commit subjects since $base"
    fi
    # no commits of its own: give the model at least the branch name
    [ -n "$desc" ] || desc="$branch"
  fi

  # the model fills whatever room the prefix leaves in the 40-char tab name
  local len=$((40 - ${#prefix})) short
  if [ "$DEBUG" = "true" ]; then
    # keep summarize's stderr (retries + its own debug dumps) visible
    short=$(printf '%s' "$desc" | summarize --len="$len" --kind="$kind" --hint="$hint")
  else
    short=$(printf '%s' "$desc" | summarize --len="$len" --kind="$kind" --hint="$hint" 2>/dev/null)
  fi
  if [ -z "$short" ]; then
    # model couldn't fit the cap: hard-truncate the PR title / branch name
    echo "No usable summary from the model, falling back to '$fallback'"
    short=$(printf '%s' "$fallback" | cut -c 1-"$len")
  fi

  local new_name="${prefix}${short}"
  # rename by stable tab id, never by focus: this runs in a throwaway pane and
  # the focused tab has very likely moved on by now
  if zellij action rename-tab-by-id "$tab_id" "$new_name" >/dev/null 2>&1; then
    echo "Tab renamed to '$new_name'"
  else
    echo "Error: failed to rename tab id $tab_id"
    return 1
  fi
}
