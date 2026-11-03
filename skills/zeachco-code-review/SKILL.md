---
name: zeachco-code-review
description: >
  Review code in Zeachco's style: readable, simple, precise, fast, resilient, and
  pleasant to change. Use for pull-request and diff reviews. Builds on the review
  threads already on the PR instead of repeating them, proposes a simpler shape (code
  or pseudo code) when the surrounding code is messy, even outside the diff, and hands
  every finding to a devil's-advocate sub-agent before posting. Nits and questions are
  the exception: a nit needs a real cost, a question needs context the code cannot supply.
---

# Code review runbook

Review for the code that should exist, not only whether the diff works: easy to
understand, hard to misuse, fast enough in real conditions, resilient, cheap to change.

## 1. Establish the frame

Before commenting, know the problem being solved, the intended vs existing behavior,
what is affected (apps, APIs, data, environments), and the lifecycle: new code,
migration, refactor, temporary bridge, legacy scheduled for removal, or a deliberately
blackboxed component. Do not impose architectural preferences without this frame.

Then read what is already on the PR so the review adds to it:

```bash
gh api "repos/$OWNER/$REPO/pulls/$N/comments" --paginate \
  --jq '.[] | "\(.path):\(.line // .original_line) \(.user.login): \(.body | split("\n")[0])"'
gh api "repos/$OWNER/$REPO/issues/$N/comments" --paginate \
  --jq '.[] | "\(.user.login): \(.body | split("\n")[0])"'
gh api "repos/$OWNER/$REPO/pulls/$N/reviews" \
  --jq '.[] | select(.body != "") | "\(.user.login): \(.body | split("\n")[0])"'
```

Keep the list of (file, line, concern) already raised. New comments go where nobody has
looked; something to add to an existing thread is a reply there, not a new comment.

## 2. Review in this order

**Correctness and precision.** Names, types, interfaces, schemas, defaults, boundaries
exact? Correct for empty, null, malformed, duplicate, stale, partial input? Errors
handled intentionally? Timeout, retry, ordering, idempotency, concurrency right?
Compatibility preserved where it must be?

**Readability and simplicity.** Understandable at first reading? Names say intent, not
history? Control flow obvious, not hidden behind indirection or state? Each abstraction
earning its place? Comments explain *why*? Prefer the smallest design that makes
behavior obvious; avoid both needless abstraction and needless duplication.

Look beyond the diff. When the surrounding code is chaotic (tangled conditionals, state
threaded through helpers, one function that validates, looks up, filters and formats),
name a simpler shape and sketch it (§4). A mess without an alternative is not actionable.

**Performance.** Unnecessary work, calls, allocations, logging, bundle size, latency,
cost? Behavior at realistic scale, not fixture scale? Caching, batching, retry limits
correct, not merely present? Any loop, fallback, poll or observer that can go unbounded?
Ask for a measurement when it matters; do not accept "should be fine".

**Resilience and operability.** What happens when a dependency or config is missing or
misbehaves? Diagnosable through logs/metrics without leaking secrets or adding noise?
Safe rollout, flag, migration order, rollback? Any silent data loss or corrupted state?
Credentials, permissions, validation, destructive operations safe?

**Maintainability.** Does this make the next change faster and safer, or add a special
case? Does it leave a clearer boundary, smaller module, better test? Workarounds named
with an exit path? Unrelated cleanup obscuring the change? Should refactor, migration,
infra and behavior changes be split?

## 3. Lifecycle exceptions

Relax the bar deliberately, and say why, when:

- **Superseded soon:** minimum safe change, document the debt, add none.
- **Blackboxed or isolated:** protect the boundary and contract; leave internals alone.
- **Legacy scheduled for removal:** minimize blast radius, improve the removal path
  rather than polishing the dead end.

## 4. Make useful comments

Every finding carries: location, problem, consequence (who, under what condition),
smallest improvement, and its kind (§6). Separate correctness from preference. Praise is
rare: only for something not commonly seen in the field. No list of style opinions once
the real risks are covered.

Nits and questions are rare. Resolve them yourself first:

- **question**: only for intent that the code, tests, PR description, commits, linked
  issue and existing threads cannot settle. If the answer is implied, do not ask. If you
  ask, say what you checked. Never disguise a preference or an unsure finding as a
  question: it survives §5 as what it is, or it is dropped.
- **nit**: only when leaving it costs something concrete (a misleading name, a stale
  usage line that will be copied, a typo in a visible string). Formatting, ordering and
  wording that reads fine are never posted. More than one nit per review means some go.
- A nit or question as the sole comment on a sound PR: post nothing.

Useful forms:

- "Can we make this direct? I have to go through `<abstraction>` to understand `<behavior>`."
- "What happens when `<edge case>`? Please add a test or explain the fallback." (only
  when the code and tests do not already answer it)
- "This adds `<cost>` per `<item>`; can we measure or bound it?"
- "Can we split the refactor from the behavior change so rollback and review stay clear?"
- "I would prefer `<cleaner design>`, but given `<lifecycle>` the smaller change is
  right. Please record the follow-up."
- For chaotic code, offer the shape, not just the complaint. A few lines that show the
  direction, not compiling code:

  "I think this is clearer extracted and composed, roughly:

  ```ts
  const result = await pipe(input, validate, applySettings, format)
  ```

  Would that fit here, or is there a constraint I'm not seeing?"

  In this PR when small and inside the changed code, otherwise a recorded follow-up.
  It is a `preference`, never `blocking`; a question only when a real constraint may
  exist that you could not find. §3 applies: no shape proposals on code leaving soon.

## 5. Challenge every finding before posting

A finding is a claim, and its author is the wrong person to check it. Every finding,
blocking through nit, questions and thread replies included, goes to a fresh sub-agent
(Claude Code `Agent`, pi `agent`, Codex/opencode task tool) whose only job is to
disprove it. Launch one per finding, all at once. The brief is self-contained: where the
code is, the finding as it would be posted, the instruction to disprove it, the output
contract. Do not pass your reasoning: handed the argument, an agent confirms it; handed
the claim and the code, it looks for what the claim missed.

```
You are the devil's advocate for one code-review finding. Your job is to prove it wrong.

Repo: <absolute path>, PR #<N>, head <SHA> (read the PR head: `git show <SHA>:<path>`,
`gh pr diff <N>`, `gh pr view <N>`).

Finding, as it would be posted:
  <path>:<line>
  <kind>(ai-review): <problem / consequence / smallest improvement>

Assume the finding is wrong and look for what makes it so: a guard, type, default,
caller contract, test, migration order, config, or documented intent the reviewer
missed. Read the surrounding code, callers, tests and PR description; use git
log/blame when history matters. Argue only from what the code does, not style. If you
cannot disprove it, say what makes it real: the triggering condition, a repro, another
affected call site, a bound, a cost.

Reply ONLY in this form:
- Verdict: FALSE | HOLDS
- Evidence: file:line references and what each does (required for both verdicts)
- Sharper: what makes the problem clearer than the finding states, or "none"
- Kind: keep | <blocking|non-blocking|preference|nit|question> — only when the
  evidence changes the consequence, with why
```

Apply the verdicts:

- **FALSE**: verify the cited evidence. If it checks out, drop the finding; do not
  soften it into a question to keep it alive. If it does not, the finding stands.
- **HOLDS, sharper**: fold in the condition, repro, second call site or cost. More
  precise, not longer. Change the kind when the consequence changes (reachable in
  production: up to `blocking`; only from a fixture: down to `nit`/`non-blocking`).
- **HOLDS, nothing new**: post as written.
- **No evidence** (agreed without reading, or errored): re-send once with a sharper
  brief; if it fails again, post unchanged and say in the review body it was not
  counter-checked.

Then prune: drop any surviving `nit` or `question` that does not clear the §4 bar. A
challenge proves a finding true, not that it is worth the author's time. The verdict is
built from what remains.

## 6. Deliver each finding on its diff line

Post findings as inline review comments anchored to the exact line of the PR head, in
one review submission. Each body starts with its kind and `(ai-review)`, then the
finding, no other label:

- `blocking(ai-review): …` must change before merge: incorrect behavior, data loss,
  security, broken rollout or rollback.
- `non-blocking(ai-review): …` worth fixing, not a merge condition. If it matters, the
  first sentence says so.
- `preference(ai-review): …` design or style the author may decline; always with the
  why, or not posted.
- `nit(ai-review): …` rare: a small thing with a concrete cost. Say why, or leave it out.
- `question(ai-review): …?` rare: intent nothing on the PR could settle. Name what you
  checked; end with a question mark.
- `praise(ai-review): …` rarely.

The review body has no prefix: the verdict, then one line mapping the inline findings.

Anchoring:

- `SHA=$(gh pr view "$N" --json headRefOid -q .headRefOid)`. Take line numbers from the
  PR head, never the working tree: `git show HEAD:<path> | grep -n '<anchor>'`, and
  confirm the line is inside a RIGHT-side hunk.
- Anchor on the introduced line, not nearby context. `start_line`/`line` only when a
  span reads better whole.
- Verify after posting: REST can report `line: null`; GraphQL is authoritative
  (`reviews(last:1){comments{nodes{path line}}}`).
- Never re-raise a concern from the §1 list. With evidence to add, reply in that thread:
  `gh api "repos/$OWNER/$REPO/pulls/$N/comments/$ID/replies" -f body='non-blocking(ai-review): …'`.

```bash
gh api "repos/$OWNER/$REPO/pulls/$N/reviews" -X POST --input - <<JSON
{
  "commit_id": "$SHA",
  "event": "COMMENT",
  "body": "<verdict>. <one line mapping the inline findings>",
  "comments": [
    { "path": "src/x.ts", "line": 53, "side": "RIGHT",
      "body": "non-blocking(ai-review): <problem / consequence / smallest improvement>" },
    { "path": "src/y.ts", "line": 12, "side": "RIGHT",
      "body": "blocking(ai-review): <incorrect behavior / condition / fix>" }
  ]
}
JSON
```

`event` stays `COMMENT` unless a formal request-changes is intended.

## 7. Finish

Before approving, confirm: intent and scope are clear; important behavior has evidence;
the code is understandable without needless navigation; failure, performance, rollout
and rollback are acceptable; debt is reduced or consciously bounded; every remaining
concern has an owner or explicit acceptance; every posted finding survived §5 with its
sharpening folded in; nothing repeats an open thread; every `nit` and `question` left
earned its place (§4).
