---
name: zeachco-complexity-pass
description: >
  Reduce code complexity in a repo, a branch, or the current working tree: delete dead
  code, simplify lines that are clever without a reason, keep the complexity that is a
  real optimisation (encapsulated or commented), collapse repeated concepts into one
  shared shape, and extract functions, utilities, or files when a function, file, or
  class has grown too large (Rust-style inline tests move to a colocated `_spec.rs`).
  Use when asked to simplify, clean up, de-duplicate, DRY, remove dead code, split a big
  function or file, tame a messy module, or run a refactor pass that must not change
  behaviour.
  Built for small-context sessions (a 27B model at 64k-128k): three disk-backed phases —
  collect, reference, change — so the session holds the notes, never the codebase.
---

# Complexity pass

Make the code say what it does in fewer, plainer pieces, and keep only the complexity
that buys something.

**This runbook assumes a small context window.** You cannot hold the codebase. You can
hold one notes file, one plan row, and one file's worth of lines. Everything else lives
on disk or inside a sub-agent that returns a conclusion. Whenever a step would need more
than that, that is the signal to delegate or to write a note — not to read more.

## The four phases

| phase | you produce | you hold in context |
| --- | --- | --- |
| 1. **Collect** — exploratory data | `00-baseline.md`, `01-inventory.md`, `02-findings.md` | one sub-agent report at a time |
| 2. **Reference** — the plan and the shapes | `03-reference.md`, `04-plan.md`, `05-do-not-touch.md` | the notes you are writing |
| 3. **Change** — the code | diffs, `06-progress.md` | one plan row + one file |
| 4. **Close out** — the durable bits in code, notes deleted | `why:` comments, rejection note | `05-do-not-touch.md` + one code site at a time |

Never mix phases. Finish and write the notes of a phase before starting the next; if you
are interrupted, the next session resumes from the notes alone.

## Phase 0 — Scope, before anything else

Notes live in the target repo, never in the repo history:

```bash
root=$(git rev-parse --show-toplevel); notes="$root/.complexity-pass"
mkdir -p "$notes"; grep -qxF '.complexity-pass/' "$root/.git/info/exclude" 2>/dev/null \
  || echo '.complexity-pass/' >> "$root/.git/info/exclude"
```

Then fix the **scope** — what "the current work" means for this pass:

```bash
git status --short          # the current work, including the user's WIP
git diff --stat             # unstaged size
git diff --cached --stat    # staged size
git diff -U0 | rg '^\+' | wc -l
```

- Default scope: the files touched by the working tree and the current branch, plus the
  files those touch that are demonstrably part of the same concept. Widen to the whole
  repo only when the user asks, or when a repetition found inside the scope is clearly
  the same code in files outside it.
- If there is no current work, scope = the last commit range (`git diff --stat
  <base>..HEAD`) or the directory the user named.
- **Do not touch the user's uncommitted work beyond what the pass requires**, and never
  attribute it to yourself. If the WIP is half-finished, it is a `?` row in the plan,
  not a silent fix.

Write the gate you will use after every change — one command, discovered now, not later,
with its pre-existing failures recorded:

```markdown
# 00-baseline.md
scope: <files or range>
gate: <exact command>        # e.g. bun test · npm run lint && npm test · cargo test
baseline: <N pass / M fail — name the failures>
build: <exact command>       # the cheapest real check (typecheck/build) if different
```

A red baseline is normal. Without it you cannot tell your damage from the existing damage.

## Phase 1 — Collect exploratory data

Rules for the whole phase:

- **Do not read whole files yourself.** List with `rg`/`git`, and hand anything wider than
  ~60 lines to a sub-agent. The sub-agent is a fresh process that has not seen this
  conversation, so every brief is self-contained: absolute repo path, the files or
  directory, the question, the output format, and the cap.
- Ask for **conclusions with `path:line` evidence**, never for pasted code, and never for
  more than ~25 lines back per call. Paste-ready code is phase 3's job.
- Write each report into its notes file **the moment it comes back**, in your own short
  words, then drop the rest. If you cannot summarise it in five bullets, the brief was
  too broad — re-cut it.
- Anything you cannot classify goes in `02-findings.md` under `?` with the reason. Later
  sessions decide; nothing is deleted on a guess.

The four collections, in this order. Any harness's agent tool will do (pi `subagent`
with `scout`; Claude Code `Agent`; Codex task tool; opencode agent):

**A. Inventory + hotspots** → `01-inventory.md`

```bash
git ls-files -z -- '*.ts' '*.tsx' '*.js' '*.py' '*.rs' '*.go' '*.sh' \
  | xargs -0 wc -l | sort -rn | head -40      # biggest files
git log --since=6.months --name-only --pretty=format: | sort | uniq -c | sort -rn | head -30
rg -n 'TODO|FIXME|HACK|XXX|@deprecated' | head -40
```

Brief the sub-agent to answer, for the top files in scope only: what concept each file
owns, which files duplicate the same concept, and where the file is doing three unrelated
things. Record: file, lines, concept, and one line of verdict.

**B. Dead code** → `02-findings.md` § dead

Ask a sub-agent to prove absence, not to guess: unused exports and files (no importer
anywhere, including tests, scripts, configs and dynamic `import()`), unreachable branches
(guarded by a constant or a flag that is never set), parameters never passed, fields never
written or never read, comments-out code, feature flags past their date, compatibility
shims for versions no longer supported.

```
Report only candidates you can prove are unreferenced, with the search you ran:
- path:line — symbol — proof it is dead (rg pattern + zero hits, or the constant that
  makes the branch impossible) — related remains (a similar live symbol?)
Cap: 25 rows. Say "unproven" explicitly for anything you suspect but could not prove.
```

Exclude from "dead": public API surface of a published package, entry points referenced
only from config, DI/plugin hooks invoked by name, and tests. Ambiguous ones go to `?`.

**C. Repeated concepts (DRY)** → `02-findings.md` § repeated

This is the collection that needs the written plan most, so gather it as **concepts**, not
as code: retry/backoff loops, error mapping, validation, fetch wrappers, date/number
formatting, path/URL building, feature-flag reads, DB session setup, colour/spacing tokens,
test fixtures/harness setup. For each, the sub-agent returns: the concept in one sentence,
every `path:line` site, and how much the sites differ.

```
Cluster the matches into concepts. For each concept: a one-sentence definition,
all call sites as path:line, and the differences between them (arguments, defaults,
error behaviour, types). Skip anything with fewer than 3 sites.
Cap: 8 concepts, 20 site lines each.
```

**D. Suspicious complexity** → `02-findings.md` § complex

Only for files in scope, and only where the sub-agent can quote the reason: nested
conditionals three levels deep, boolean-parameter soup, one-method classes, single-use
indirection, duplicated validation, defensive branches for impossible states, comments
narrating the next line, and one-liners that need a paragraph to read. For each, the
sub-agent must also say whether the complexity looks **load-bearing** — a tight loop,
inlined hot path, manual index math, a cache, a precomputed table, a workaround with a
link — because that kind decides between deleting and keeping.

Also collect **magic numbers** in scope: bare numeric literals with meaning (durations,
sizes, limits, ratios) that are not already named. For each: `path:line`, the literal,
what it means, and whether the meaning is *certain* (documented elsewhere, used in the
same role at several sites, or obvious from the expression) or a guess.

```
Report bare numeric literals that carry meaning, as path:line — literal — meaning —
certainty (certain: <where documented> | guess). Skip 0, 1, -1, array indices, and
test fixtures. Cap: 20 rows.
```

And, in typed languages, **untyped boundaries**: functions that return `any` (or the
language's escape hatch) at an I/O or external-API edge — storage reads, `fetch`/HTTP
wrappers, JSON parsing, env/config reads, message handlers — where every caller then
re-asserts the type by hand. Report `path:line`, the function, and how many callers cast
its result. Cap: 10 rows.

**E. Oversized units** → `02-findings.md` § oversized

Size is measured per unit, and the tolerance differs by unit:

| unit | tolerance | signal to report |
| --- | --- | --- |
| function / method | **strict** | > ~40 lines, > 3 nesting levels, > 4 parameters, or more than one reason to change |
| file / module | **moderate** | > ~400 lines, or owning more than one concept (per 1A) |
| class / struct impl | **lenient** | acceptable when large but cohesive; report only when the same big shape repeats across many types |

```
For each unit over its tolerance: path:line-range, unit kind, size, the distinct
responsibilities you can name (one line each), and which of them could stand alone
under a name. For Rust-like files with inline tests (#[cfg(test)] mod tests), report
the production line count and the test line count separately.
Cap: 20 rows.
```

## Phase 2 — Reference

Turn the findings into the two documents phase 3 obeys. Nothing else survives: after this
phase, the notes are the task.

### `03-reference.md` — the canonical shapes

One section per repeated concept from 1C that you decided to unify. For each:

```markdown
## <concept>
shape:      <module path to create or existing home> — signature, in one line
sites:      <path:line>, <path:line>, ...
variances:  <what differs and how the shape absorbs it, or why it cannot>
not-now:    <sites to leave, and why>
```

Rules that keep a de-duplication safe:

- **Rule of three.** Unify at three real sites; at two, duplication is cheaper than the
  coupling. If the sites differ in behaviour, unify the skeleton and keep the difference
  as an explicit argument — never as a flag that re-selects the two old bodies.
- **Unify the concept, not the coincidence.** Identical-looking code that changes for
  different reasons stays apart; it is cheaper to read twice than to change once and
  break half the app.
- **One home per concept**, named after the concept (`retryWithBackoff`, not `helpers`),
  placed at the layer all its callers already depend on. If they disagree on the layer,
  stop: the concept is not shared, only similar.
- Types stay with their concept; no `utils` bucket, no barrel re-export of everything.

The shape is a sketch, not a mandate — a few lines are enough for a small model to
implement. Say plainly when you are unsure and leave it open.

### `04-plan.md` — the ordered task list

One row per change. Fixed columns, so an edit tool can tick a row and a 27B can execute
it without re-deriving anything:

```markdown
- [ ] T1 | src/api/client.ts:120-178 | extract the retry loop into retryWithBackoff | ~40 lines | check: bun test client
- [ ] T2 | src/api/client.ts, src/jobs/run.ts | use retryWithBackoff at both sites | ~15 lines | check: bun test
- [ ] T3 | src/legacy/old-report.ts | delete file (dead: 02-findings § dead #4) | ~0 lines | check: build
```

Rules:

- **Behaviour-preserving only.** A bug fix or a behaviour change you spot goes into the
  plan as a separate row marked `behaviour: <what changes>`, for the user to approve —
  never bundled into a simplification.
- **Small rows.** One file, one concept, roughly ≤50 changed lines. A row you cannot
  state in one line is two rows.
- **Order: delete → unify → extract → simplify.** Deleting first shrinks everything
  after it; unifying before extracting prevents extracting the same code four times;
  extracting before simplifying gives each simplification a small target.
- Delete rows come with their proof transcribed (`02-findings § dead #n`), because the
  proof is what justifies the deletion in review and in the commit message.
- Independent rows can be marked `(parallel)`; rows that touch the same file never are.
- **Magic numbers, with a grain of salt.** Two cheap readability rows, both
  behaviour-preserving:
  - Large literals get digit separators where the language has them (`86_400_000`, not
    `86400000`; JS/TS, Python, Rust, Go, Java, Kotlin, C# all accept `_`). Do it for
    anything with more than four digits, as part of whichever row touches the line, or
    as one sweep row per file.
  - A literal whose meaning is **certain** — documented elsewhere, used in the same role
    at several sites, or obvious from the expression — becomes a self-documenting
    constant named for the meaning (`ONE_DAY_MS = 24 * 60 * 60 * 1000`), placed beside
    its callers. A literal whose meaning is a guess stays a literal; a wrong name is
    worse than no name. One-use constants that only restate the expression
    (`const THOUSAND = 1000`) are not an improvement — use common sense.
- **Untyped boundaries, rarely and lightly.** When an I/O or external-API wrapper
  returns `any` and its callers each cast or re-type the result, give the wrapper a type
  parameter the caller supplies, defaulting to the safe unknown:

  ```ts
  readLocalStorage(key: string): any            // callers: `as Settings` everywhere
  readLocalStorage<T = unknown>(key: string): T  // caller says what it expects, once
  ```

  Only at the edge where the code meets the outside world (storage, HTTP, JSON, env,
  message bus), and only when leaving it as is forces boilerplate or a bad type on every
  caller. Internal functions that happen to say `any` are a plain simplify row or left
  alone; no sweeping `any` hunt. Changing the default from `any` to `unknown` can turn
  compile-clean callers red — that is the gate's job to show, and the fix is the callers
  naming their type, not widening the default back.
- **Rows are verified on the spot.** Anchor line numbers shift after earlier same-file
  rows, and sub-agent reports can name symbols that do not exist. Identify each target
  by content, verify it is actually present before executing, and re-cut the row if the
  scout hallucinated it.

### `05-do-not-touch.md` — the kept complexity

Every piece of complexity you decided to keep because it is an optimisation or a
deliberate workaround goes here with the reason and how to verify it:

```markdown
- src/render/hot-path.ts:88 — manual index loop instead of map, keeps the per-frame
  allocation at zero. Kept inline, comment added: // why: 0 alloc/frame, see bench/draw.ts
  verify: bun bench draw
```

Two ways to keep complexity honest, and the plan says which one per case:

1. **Encapsulate** — move it behind a name that states the intent (`fastPathFor…`,
   `precomputedTable`), so the caller reads simply and the ugliness has one home with a
   documented reason.
2. **Comment** — when inlining is the point, keep the lines and add a `why:` comment
   above them: the constraint, the measurement, and how to check it. A comment that
   narrates the code is deleted; a comment that records a reason is the price of keeping
   the code unreadable.

Complexity with no reason and no measurable benefit is not kept — it is deleted in a T
row. If you cannot find the reason and cannot measure it, offer to measure (a bench or a
test) rather than trusting the shape.

### Extraction — when a unit is too large

Each row from 1E becomes an extract row in `04-plan.md`, or a line in
`05-do-not-touch.md` saying why the size is earned. The tolerance ladder decides:

- **Functions first, strictly.** A function doing two nameable things becomes two
  functions; a block that needs a comment to introduce it becomes a function named after
  the comment. Extract a utility only when the piece has a name that stands without its
  caller — otherwise it is a private helper beside the caller, not a shared module.
- **Files moderately.** Split a file when it owns more than one concept, along the
  concept boundary from 1A — never into `part1`/`part2`. A single large file that owns
  one concept is fine; a mid-sized file owning three is not.
- **Classes leniently.** A big class with one cohesive responsibility stays. Extract
  when the same large shape (the same methods, the same private helpers) repeats across
  many types — that is a repeated concept (1C), and the extraction is a shared trait,
  base, or utility, not a per-class split.
- **Inline tests move to a colocated spec file.** In languages where tests live in the
  production file (Rust `#[cfg(test)] mod tests`, and the like), when the file is over
  its tolerance, move the tests to `<file>_spec.rs` next to it and keep a stub in place:

  ```rust
  #[cfg(test)]
  #[path = "parser_spec.rs"]
  mod tests;
  ```

  The spec file keeps `use super::*;` so private items stay reachable. This counts as a
  file split along the test/production boundary; do it before splitting production code
  across files, since it often brings the file back under tolerance by itself.

An extraction is behaviour-preserving by construction only if the extracted piece keeps
its inputs, outputs, and side-effect order. Anything else is a `behaviour:` row.

## Phase 3 — Change the code

Work the plan top to bottom, one row at a time. The loop, per row:

1. **Load only the row and the target.** Read the row from `04-plan.md`, then the cited
   file region (`read` with offset/limit around the lines, not the whole file); the notes
   files if the row references them.
2. **Change.** A row that is a pure mechanical edit — rename, extract, replace call site,
   delete a file — goes to a cheap typing sub-agent (`completion`/`code` in pi, a small
   model elsewhere) with the exact file, the exact before/after, and the exact check. A
   row that needs judgement (the shape is a sketch, the site has surprises) you do
   yourself, or hand to `worker` as a self-contained brief.
3. **Verify, always.** Run the gate from `00-baseline.md` and diff the actual work:
   `git diff` (never trust a sub-agent's success report — read the diff). Failures are
   compared to the baseline, not to zero.
4. **Record.** Tick the row (`- [x] T3 | …`), and append one line to `06-progress.md`:
   `T3 done — removed old-report.ts, gate green (baseline + 0) — <commit or WIP>`.
   A row that turns out wrong is marked `- [ ] T3 skipped — <why>` and, if it is real
   work, re-cut as new rows. Do not silently drop it. Tick and append in the same step
   as the commit — a committed-but-unchecked row is a notes bug, and the notes are the
   only state the next session can trust.
5. **Commit per row** when the repo allows it: one concept per commit, message naming the
   concept and citing the plan row. Small commits are the only rollback a small model
   can reason about.
6. **Context checkpoint.** After the commit, forget everything except `04-plan.md`'s next
   unchecked row, the last line of `06-progress.md`, and the current file. If you notice
   you are re-reading things you already decided, re-read the notes file instead — the
   decision is written down.

Stop and ask the user when: a row would change behaviour, a deletion has an unclear
proof, two concepts want the same name, or the gate breaks in a way the baseline cannot
explain. The pass can always pause: the plan is on disk.

## Phase 4 — Close out after a green run

When every row is checked or skipped and `06-progress.md` has its final gate line, the
notes have done their job. Close out so the next pass starts clean; without it, the only
record of *why* something was kept or rejected dies with the notes directory.

1. **Persist the kept complexity in code, not in notes.** Walk `05-do-not-touch.md`
   entry by entry. Each one must already be honest in the code — an encapsulating name,
   or a `why:` comment on the kept lines (the constraint, the measurement, how to check).
   If an entry's reason exists only in the notes, add the comment now, directly above the
   lines it describes. It is the only record that survives the deletion, and it cannot
   drift because it sits on the code.
2. **Keep the rejection memory.** The skipped rows and the "judged not worth it"
   verdicts live only in the notes. Copy them — one line each, with the verdict — into
   the PR description, a short `docs/` note, or agent memory, so a future pass does not
   re-flag and re-litigate them.
3. **Delete the notes.** `rm -rf "$notes"`. The commits are the deliverable. Leaving the
   directory is acceptable only when another pass is expected soon — and then the next
   pass must read the old `05-do-not-touch.md` before planning, or it re-proposes the
   kept complexity as if it were new.

A from-scratch re-run earns its cost only after the code has changed again (new WIP or
commits) or after a long interval. Immediately after a green run it re-derives
"nothing to do" — minus the rejection memory, which is exactly what step 2 keeps alive.

## Notes files, at a glance

| file | content | rule |
| --- | --- | --- |
| `00-baseline.md` | scope, gate, build, pre-existing failures | written first, never edited |
| `01-inventory.md` | files by size/churn, the concept each owns | ≤120 lines |
| `02-findings.md` | dead · repeated · complex · oversized · `?`, every row with `path:line` | ≤200 lines; split rather than grow |
| `03-reference.md` | canonical shape per concept to unify | one section per concept |
| `04-plan.md` | ordered checkbox rows, exact anchors and checks | the only file phase 3 reads wholesale |
| `05-do-not-touch.md` | kept complexity, reason, verify command | append-only |
| `06-progress.md` | one line per executed row | append-only |

Notes are working state, not a deliverable: they are git-excluded, and the durable output
is the commits. At close-out (phase 4) the directory is deleted after its durable bits —
the kept-complexity reasons and the rejection verdicts — are folded into code comments
and the PR or a docs note. Offer to copy the final `03-reference.md` + `04-plan.md` into
`docs/` when the user wants the reasoning kept.

## What not to do

- Do not refactor outside the scope because the file is in front of you.
- Do not rename, move, and simplify in the same change.
- Do not extract a function used once into a shared module, and do not split a cohesive
  class because it is long.
- Do not delete "unused" code without the zero-hits proof, and never delete tests,
  migrations, configs, or public API on the strength of "nothing calls it" alone.
- Do not unify two things just because they look alike, and do not add a parameter that
  keeps both old behaviours alive.
- Do not replace a comment that records a reason with a cleaner-looking abstraction —
  the abstraction may be slower.
- Do not delete the notes before persisting their reasons: the `05` entries are the only
  record of kept complexity until they sit in the code as names or `why:` comments.
- Do not let the notes drift from the code: if a row is edited, the notes are edited in
  the same step.
