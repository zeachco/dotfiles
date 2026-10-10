---
name: zeachco-pr-documentation
description: >
  Write or improve a pull-request description in zeachco's observed style: concrete
  context, reviewer guidance, test evidence, impact, and release safety. Use when
  opening, updating, or self-documenting a PR.
---

# Zeachco self-documentation profile

This profile was inferred from 167 zeachco-authored PRs in the same year. There
were 165 non-empty descriptions. Common sections were Description (92), Testing
(82), Reviewer Focus (73), Release Safety (41), Impact (39), and Quality Checklist
(39). Treat these as observed habits, not mandatory boilerplate.

## Writing principles

- Explain **why**, not just what changed.
- Name affected apps/packages/services and the behavior boundary.
- Give reviewers concrete questions instead of asking for a generic review.
- Report evidence honestly: commands, environments, results, limitations, and what
  was not tested. Never invent a test result.
- Keep the description current when review decisions change the implementation.
- Separate urgent correctness work from refactor, migration, generated output, and
  future cleanup.
- Use lifecycle and risk to decide how much release detail is needed.

## Required pass before opening or updating

1. **Context / problem** — failure, cost, user impact, request, evidence, and root cause.
2. **Goal and non-goals** — what this PR will and will not do.
3. **Change and scope** — affected projects, API/schema/config changes, dependencies,
   flags, migration requirements, and compatibility.
4. **Acceptance criteria** — observable “given/when/then” outcomes and success metric.
5. **Testing** — automated commands/results, manual/browser/device/environment matrix,
   before/after evidence, and known failures or untested paths.
6. **Reviewer focus** — two to five specific risks or decisions to inspect.
7. **Release safety** — rollout/flag, migration ordering, monitoring/alerts,
   rollback, owner, and follow-up ticket when applicable.
8. **Links** — issue, design/spec, related PRs, dashboards, screenshots, or demo.

## Preferred template

```md
## Context / Problem
- What is broken, costly, risky, or requested?
- Evidence and root cause:

## Goal and Non-goals
- This PR will:
- This PR will not:

## Change and Scope
- Affected apps/packages/services:
- Behavior/API/schema changes:
- Compatibility or migration requirements:
- Dependencies and feature flags:

## Acceptance Criteria
- Given [condition], expect [observable result].
- Success metric:
- Known limitations:

## Testing
- Automated commands and results:
- Manual/browser/device/environment matrix:
- Before/after evidence:
- Not tested / pre-existing failures:

## Reviewer Focus
1. [specific implementation or risk]
2. [edge case, compatibility, or operational concern]

## Release Safety
- Rollout/flag:
- Migration:
- Monitoring/alerts:
- Rollback:
- Owner/follow-up:

## Links
- Issue/spec/design:
- Related PRs:
```

For meaningful updates, fold the decision back into the main description and add a
small dated note only when useful:

```md
### Update — <date or commit>
- Evidence:
- Decision:
- Remaining risk:
- Follow-up:
```

## Observed strengths to preserve

Descriptions became especially concrete after the PR-template work: affected
projects, failure modes, commands, expected results, flags, rollback, and reviewer
focus. Strong examples include monoco#1236 (impact, test matrix, rollback),
monoco#2426 (experiment arms and untested arms), and monoco#2717 (error-volume
evidence plus root-cause follow-up).

## Common omissions to correct

- Empty or changelog-only descriptions.
- No explicit success criteria or “not tested” section.
- Monitoring, ownership, rollback, compatibility, and follow-up left implicit.
- Decisions remain buried in comments instead of the PR body.
- Checklists become unchecked/checked boilerplate without evidence.
- Generated deployment output makes a long PR harder to review.

When an AI drafts the description, verify every factual claim against the diff,
commands, CI, and actual rollout plan. Prefer “not verified” over plausible prose.
