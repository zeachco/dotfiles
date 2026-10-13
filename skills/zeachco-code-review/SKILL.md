---
name: zeachco-code-review
description: >
  Review code in Zeachco's style: make it readable, simple, clear, precise, fast,
  resilient, and pleasant to change. Use for pull-request and diff reviews. Builds on
  the review threads already on the PR instead of repeating them, and proposes a
  simpler shape (as code or pseudo code) when the surrounding code is messy, even
  outside the diff.
---

# Code review runbook

Review for the code that should exist, not only whether the current diff works.
Optimize for code that is easy to understand, hard to misuse, fast enough in real
conditions, resilient to failure, and cheap to change later.

## 1. Establish the frame

Before commenting, understand:

- the user or system problem;
- the intended behavior and the existing behavior;
- the affected apps, packages, APIs, data, and environments;
- whether this is new code, a migration, a refactor, a temporary bridge, or legacy
  code scheduled for removal;
- whether the component is deliberately blackboxed or isolated.

Do not impose a general architectural preference without understanding this frame.

Then read what has already been said on the PR, so the review adds to it instead of
repeating it:

```bash
# inline review threads: path:line, author, first line of the comment
gh api "repos/$OWNER/$REPO/pulls/$N/comments" --paginate \
  --jq '.[] | "\(.path):\(.line // .original_line) \(.user.login): \(.body | split("\n")[0])"'
# conversation comments and review summaries
gh api "repos/$OWNER/$REPO/issues/$N/comments" --paginate \
  --jq '.[] | "\(.user.login): \(.body | split("\n")[0])"'
gh api "repos/$OWNER/$REPO/pulls/$N/reviews" \
  --jq '.[] | select(.body != "") | "\(.user.login): \(.body | split("\n")[0])"'
```

Keep that list of (file, line, concern) already raised — by humans or bots — and review
around it. New comments go where nobody has looked yet; something to add to an existing
thread is a reply in that thread, not a new comment beside it.

## 2. Review in this order

### Correctness and precision

- Are names, types, interfaces, schemas, defaults, and boundaries exact?
- Is the behavior correct for normal, empty, null, malformed, duplicate, stale,
  partial, and unexpected input?
- Are errors propagated or handled intentionally?
- Are timeout, retry, ordering, idempotency, and concurrency behaviors correct?
- Does the implementation preserve compatibility where it must?

### Readability and simplicity

- Can a competent developer understand the code at first reading?
- Do names explain intent instead of implementation history?
- Is the control flow obvious, or hidden behind indirection, cleverness, or state?
- Is the abstraction earning its existence, or would direct code be clearer?
- Can related behavior be kept together without creating a large, mixed-purpose file?
- Are comments explaining *why*, rather than narrating the code?

Prefer the smallest design that makes the behavior obvious. Avoid both needless
abstraction and needless duplication when either makes future changes harder.

Look beyond the diff here. When the surrounding code is chaotic — tangled conditionals,
state threaded through several helpers, one function that validates, looks up, filters
and formats in a row — the diff is rarely where it gets fixed, but it is the moment to
name a simpler shape. Sketch the shape (the composition form in §4) rather than only
saying it is messy: a mess without a proposed alternative is not actionable.

### Performance

- Does this add unnecessary work, network calls, allocations, parsing, logging,
  bundle size, latency, memory, or cost?
- Does it change behavior at realistic scale, not only with a unit-test fixture?
- Are caching, batching, lazy loading, and retry limits correct rather than merely
  present?
- Could a fallback, loop, polling path, or observer become expensive or unbounded?

Ask for measurement when performance is important. Do not accept “should be fine”
when a baseline, smoke test, metric, or simple benchmark is available.

### Resilience and operability

- What happens when a dependency, provider, browser, service, or configuration is
  unavailable or returns an unexpected response?
- Can failures be diagnosed through useful logs, metrics, or traces without leaking
  secrets or creating noise?
- Is there a safe rollout, feature flag, migration order, off-switch, and rollback?
- Could the change silently lose data, corrupt state, or make recovery harder?
- Are credentials, permissions, input validation, allowlists, and destructive
  operations safe?

### Maintainability and technical debt

- Does this make the next change faster and safer, or add another special case?
- Does it leave a clearer boundary, smaller module, better test, or better tool?
- Does it preserve a workaround without naming the debt or exit path?
- Is generated or unrelated cleanup obscuring the behavior under review?
- Should refactor, migration, infrastructure, and behavior changes be split?

## 3. Apply lifecycle exceptions deliberately

The default is to improve clarity, simplicity, performance, resilience, and
maintainability. Make an explicit exception when:

- **The project will be superseded or passed through later:** do the minimum safe
  change; do not gold-plate it, but document the debt and avoid adding new debt.
- **The component is blackboxed or intentionally isolated:** protect the boundary
  and its contract; do not refactor internals just to satisfy preferences.
- **The code is legacy and scheduled for removal:** minimize blast radius, avoid
  architectural investment, preserve behavior needed for the exit, and improve the
  removal path rather than polishing the dead end.

The exception must explain why the normal quality bar is being relaxed.

## 4. Make useful comments

Every non-trivial finding should include:

1. **Location** — file, line, or behavior.
2. **Problem** — what is unclear, slow, fragile, or incorrect.
3. **Consequence** — who is affected and under what condition.
4. **Smallest improvement** — a concrete change or verification.
5. **Kind** — the comment prefix (§5): `blocking`, `non-blocking`, `preference`, `nit`,
   `question`, or `praise`.

Prefer questions when intent is unclear. Separate correctness issues from design
preferences. Praise is rare: reserve it for something not commonly seen in the field,
not for ordinary good practice. Do not produce a long list of style opinions after the
important risks are covered.

Useful forms:

- “Can we make this direct/explicit? I have to navigate through `<abstraction>` to
  understand `<behavior>`.”
- “What happens when `<failure or edge case>`? Please add a test or explain the
  intended fallback.”
- “This adds `<cost>` per `<request/item>`; can we measure it or bound the work?”
- “Can we split the refactor from the behavior change so rollback and review stay
  clear?”
- “I would normally prefer `<cleaner design>`, but given `<lifecycle/boundary>` the
  smaller safe change is appropriate. Please record the follow-up.”
- When the style is chaotic, do not stop at naming the mess: offer the simpler shape
  you have in mind, as a few lines of code or pseudo code, and leave the decision open —
  a question, not a verdict. The sketch only has to show the direction, not compile:

  “I think it would be clearer if we extracted that part and composed what we need,
  roughly:

  ```ts
  const result = await pipe(input, validate, applySettings, format)
  ```

  Would that fit here, or is there a constraint I'm not seeing?”

  Scope it: in this PR when it is small and stays within the changed code, otherwise a
  recorded follow-up. On its own it is a `question` or `preference`, never `blocking`,
  and the lifecycle exceptions in §3 apply (no shape proposals on code leaving soon).

## 5. Deliver each finding on its diff line

Post findings as **inline PR review comments anchored to the exact line of the PR
head** — not only as a summary. The author should meet each concern where the code
is. One review submission carries all of them.

- Prefix every comment body with its kind and the `ai-review` decoration, then the
  finding — no other label inside the body (no bold “Should-fix.” after the prefix; the
  prefix is the label):
  - `blocking(ai-review): …` — must change before merge: incorrect behavior, data loss,
    security, a broken rollout or rollback.
  - `non-blocking(ai-review): …` — worth fixing but not a merge condition: a should-fix,
    a readability problem, a recorded follow-up. When it matters, the first sentence
    says so.
  - `preference(ai-review): …` — a design or style preference the author may decline.
    Only with the reasoning and why it is worth considering here; a preference without
    its why is not posted.
  - `nit(ai-review): …` — a small thing (naming, a typo, formatting, a stale usage
    line). Same rule: say why it is worth the change, or leave it out.
  - `question(ai-review): …?` — intent is unclear; the body ends with a question mark.
  - `praise(ai-review): …` — rarely: only for something not commonly seen in the field.
- The review body carries no kind prefix: it opens with the verdict and maps the inline
  findings in a line. The `(ai-review)` decoration on each comment marks the origin.
- Use the PR head commit: `gh pr view <n> --json headRefOid -q .headRefOid`.
- Take the line number from the **PR head**, never the dirty working tree: when the
  branch has uncommitted edits, `git show HEAD:<path> | grep -n '<anchor>'`, and
  confirm the line sits inside a diff hunk on the RIGHT side.
- Anchor on the smallest relevant line (the introduced line), not a nearby context
  line. Use `start_line`/`line` only when a multi-line span reads better whole.
- Verify the anchors after posting: REST can report `line: null`; GraphQL is
  authoritative (`reviews(last:1){comments{nodes{path line}}}`).
- Do not re-raise a concern that is already on the PR (the list from §1). Skip it, or
  when there is evidence or a sharper fix to add, reply in that thread with the same
  prefixes:
  `gh api "repos/$OWNER/$REPO/pulls/$N/comments/$ID/replies" -f body='non-blocking(ai-review): …'`.

```bash
SHA=$(gh pr view "$N" --json headRefOid -q .headRefOid)
gh api "repos/$OWNER/$REPO/pulls/$N/reviews" -X POST --input - <<JSON
{
  "commit_id": "$SHA",
  "event": "COMMENT",
  "body": "<verdict>. <one line mapping the inline findings>",
  "comments": [
    { "path": "src/x.ts", "line": 53, "side": "RIGHT",
      "body": "non-blocking(ai-review): <problem / consequence / smallest improvement>" },
    { "path": "src/y.ts", "line": 12, "side": "RIGHT",
      "body": "question(ai-review): <what is unclear, under which condition>?" }
  ]
}
JSON
```

`event` is `COMMENT` unless the intent is a formal request-changes; keep `COMMENT`
for verdicts that are approve-after-fix or questions.

## 6. Finish the review

Before approving, confirm that:

- the intent and scope are clear;
- important behavior has evidence, not assumptions;
- the code is understandable without unnecessary navigation;
- failure, performance, rollout, and rollback paths are acceptable;
- technical debt is reduced or consciously bounded;
- every remaining concern has an owner, scope, or explicit acceptance;
- nothing in the review repeats a thread that was already open.
