---
name: zeachco-selfdoc
description: >
  Write PR descriptions, commit messages and self-review notes the way zeachco
  self-documents his own PRs. Use this skill when opening a PR, updating a PR
  description, writing commit messages, or documenting AI-generated work. Encodes his
  actual patterns from 517 own PRs analyzed in Oct 2026.
---

# Self-document like zeachco

Corpus: 517 own PRs in the past year, 494 with a body, 1,302 commit headlines (median 1
commit per PR — squash culture). He never formally approves his own PRs: self-reviews are
always COMMENTED notes for the record, never APPROVE.

## Title

Conventional-commit type + scope + ticket, outcome phrasing:
`fix(scripts): PROJ-12541: cache unparseable resolver destinations as a miss`.
- ~36% of bodies carry the ticket link; the rest rely on the `PROJ-XXXXX` key in the title.
- Reverts: `Revert "<original title>"` and the body says `Reverts <repo>/<#>` plus one
  line of context, e.g. `* Investigating DO NOT MERGE` while open.

## Body — pick the template by size of change

1. **Trivial fix (one-liner, ~46 of 494):** one sentence, what was actually wrong.
   "oneOf isn't a function or part of the utilities module".
2. **Ticket-driven chore:** `closes PROJ-XXXX` (+ one
   sentence if non-obvious: "Updated with new secrets and updated 1password as well").
3. **Structured feature/refactor (the main shape):**
   - `## Summary` or `## Description` — what and why, 2-5 sentences
   - `### Key Changes` / `### Changes` — bulleted, one line per meaningful chunk
   - `### Result` — end state ("All 23 projects pass CICD")
   - `## Test plan` — concrete steps or checkboxes:
     "- [x] Run `npm run cicd` - all 23 projects pass"
   ~56% of his bodies contain a test plan; ~99 contain screenshots/recordings when UI.
4. **"⚠️ Review per commits" for demo-style PRs:** describe each commit's expected state so
   reviewers can verify per commit: "I have created 3 first commits - the gate
   implementation (with a diff of `0` ✅) - adding an error (with a positive diff of
   errors ❌) - removing errors ... (with a negative diff ✅)".
5. **Personal projects:** `# What` / `# Why` (real tradeoff reasoning, e.g. why not the
   obvious option) / `# Preview` (live URL + how to poke it) / `# Notes for PR owner`.
6. **Handoffs:** `CC @owner I'll let you continue from here, I don't have all the context
   about changes` — be honest about what you don't know.
7. **Checklist for risky changes:** explicit `- [ ] Added unit tests`, `### Checklist` with
   `**Do not merge until this is complete**` where a step is blocking.

## When AI wrote the code (happens on ~28% of his PRs)

- **Disclose it**: keep the generator footer ("🤖 Generated with Claude Code") or link the
  session (`https://claude.ai/code/session_...`).
- **Add the human layer on top**: what to check, what was verified manually, what's still
  open. His structured AI bodies keep the Summary/Key Changes/Result/Test plan shape.
- When AI tests are bad, say so in review of others' AI work: "Claude's testing strategy
  is 💩 😂 let's pair on those if you need" — don't let AI-generated test suites pass
  unexamined.

## Rollout & risk notes

- ~20% of bodies mention rollback/revert — include one when there's risk: what flag gates
  it, how to revert, what to watch after deploy.
- Flag/experiment notes: which flag, default value, cleanup plan ("clean feature flags" is
  its own recurring chore type in his PRs).

## Commits

- Squash to 1 (median); multi-commit only for "review per commits" PRs.
- Conventional type + scope on ~1/3, ticket ref on ~1/3; imperative mood.
- Per-commit demo PRs: each commit must stand alone and be verifiable (see template 4).

## Self-review (COMMENTED only)

Use self-reviews as notes to the future, not as approvals:
- "this is temporary, I think we should use vitest and mock some things instead"
- "unrelated: would be cool to document where that comes from"
- Record decisions with reasons so the next reviewer (often an AI agent) inherits context:
  "there was two `dependsOn` probably from a 3-way merge ... the last one wins all, this
  caused `test` to pass if `build` passed without running each test suite".

## Missing-by-default elements (his habit, keep or fix deliberately)

- No rollback plan on most feature PRs unless flagged.
- No "how to reproduce in prod/staging" section — test plans are local/CI centric.
- One-liners carry zero context for the future reader: fine for trivial fixes, not for
  behavior changes.

## Delivery (GitHub)

The description is the artifact; comments carry the parts that belong at the code.

- **Prefix every comment body with `self-review: `.**
- Deliver comments as inline PR review comments on the line they document —
  design/tradeoffs on the implementation, evidence on the tests, an accepted
  limitation on the code that accepts it — using the PR head commit and RIGHT-side
  lines. Keep the long-form structure in the description, not duplicated inline.
- Context, rollout/risk and links have no natural line: keep them in the
  description or the review body.
- One review submission with a `comments[]` array and `event: "COMMENT"` (self-reviews
  are never APPROVE); verify anchors with GraphQL, not the REST `line` field.
