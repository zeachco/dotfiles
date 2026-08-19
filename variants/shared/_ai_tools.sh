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

# Summarize a work description (JIRA ticket, GitHub PR, or commit messages)
# into a short agent-workflow tab name.
# Usage: gh pr view 123 --json body -q .body | summarize --len=30 --retries=3 [--model=tinyllama]
# --kind=pr|commits tailors the prompt to the input (PR title+body vs commit
# messages); anything else keeps the generic wording. --hint=... strongly
# steers the title toward a specific aspect of the work.
# Prints only the summary (exit 0), or a failure message at the end (exit 1).
# Default model is overridable with SUMMARIZE_MODEL (ollama pulls it on first use).
summarize() {
  local max_length=80 retries=3 content="" kind="" hint=""
  local model="${SUMMARIZE_MODEL:-mistral}"

  for arg in "$@"; do
    case "$arg" in
    --len=*) max_length="${arg#*=}" ;;
    --retries=*) retries="${arg#*=}" ;;
    --model=*) model="${arg#*=}" ;;
    --kind=*) kind="${arg#*=}" ;;
    --hint=*) hint="${arg#*=}" ;;
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

  # tailor the first prompt line to what the caller is actually feeding in
  local intro
  case "$kind" in
  pr) intro="A GitHub pull request title and body follow." ;;
  commits) intro="Git commit messages from a work-in-progress branch follow." ;;
  *) intro="A description of development work follows: a JIRA ticket, a GitHub
PR description, or git commit messages." ;;
  esac

  local guidance=""
  if [ -n "$hint" ]; then
    guidance=$(printf '\nNaming guidance (prioritize this strongly): %s\n' "$hint")
  fi

  local esc=$(printf '\033')
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

# Rename the current zellij tab to "#<pr-number>: <summary>" from the current
# branch's PR (title + body through the model), or to "wip: <summary>" from
# the branch's commit subjects since main/master when no PR exists. An optional
# short prompt strongly guides the summary: `tab_autoname "focus on auth"`.
# The tab id is captured first so the rename targets the tab this was typed in,
# even if focus moved elsewhere during the slow gh/model calls.
tab_autoname() {
  if [ -z "$ZELLIJ" ]; then
    echo "Error: Not in a zellij session"
    return 1
  fi
  _git_check_repo || return 1

  local tab_id
  tab_id=$(zellij action current-tab-info 2>/dev/null | sed -n 's/^id: //p')
  if [ -z "$tab_id" ]; then
    echo "Error: could not get the current tab id"
    return 1
  fi
  _ai_debug "tab-autoname: renaming tab id $tab_id"

  local branch=$(git branch --show-current)
  if [ -z "$branch" ]; then
    echo "Error: not on a branch (detached HEAD?)"
    return 1
  fi

  # PR of the current branch first; commit subjects since main/master when
  # there is none
  local hint="$*" kind prefix desc fallback="$branch" out
  out=$(gh pr view --json title,number,body \
    --jq '(.number|tostring), .title, (.body // "")' 2>/dev/null)
  if [ -n "$out" ]; then
    kind="pr"
    prefix="#$(printf '%s\n' "$out" | head -n 1): "
    fallback=$(printf '%s\n' "$out" | sed -n '2p')
    desc=$(printf '%s\n' "$out" | tail -n +2)
    _ai_debug "tab-autoname: using PR title+body for ${prefix%: }"
  else
    kind="commits"
    prefix="wip: "
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
  # rename by the saved ID so it targets the tab this command was typed in
  if zellij action rename-tab --tab-id "$tab_id" "$new_name" >/dev/null 2>&1; then
    echo "Tab renamed to '$new_name'"
  else
    echo "Error: failed to rename tab"
    return 1
  fi
}
