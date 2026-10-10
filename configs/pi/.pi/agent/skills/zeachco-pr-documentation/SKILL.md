---
name: zeachco-pr-documentation
description: >
  Document a pull request so another engineer can understand the intent, scope,
  tradeoffs, evidence, risks, and safe rollout. Use when writing or updating a PR.
---

# PR self-documentation runbook

The description is part of the change. Make it precise enough that a reviewer can
understand the behavior without reconstructing the whole history, while keeping it
short enough to remain readable and current.

## Write these answers

### Context and intent

- What problem or request caused this change?
- Who or what is affected?
- What evidence shows the problem exists?
- What is the desired behavior?

### Scope

- What changed, and in which apps, packages, services, APIs, or environments?
- What is deliberately not changing?
- Are there migrations, dependencies, feature flags, compatibility constraints, or
  generated files?
- Is this a refactor, behavior change, temporary bridge, isolated component, or
  legacy code on the way out?

### Design and tradeoffs

- Why this design instead of the obvious alternatives?
- How does it preserve readability, simplicity, precision, performance, resilience,
  and maintainability?
- What tradeoff or technical debt is being accepted, and why is it appropriate now?

### Evidence

- Which commands, tests, CI jobs, benchmarks, browsers, devices, or environments
  were used?
- What were the results?
- What was not tested, and what pre-existing failures remain?
- What observable result proves the change works?

### Safety

- What can fail or degrade?
- How is it rolled out, monitored, disabled, migrated, and rolled back?
- Who owns the follow-up or remaining debt?

### Reviewer focus

Give reviewers a short list of the decisions or risks that deserve attention. Do not
ask for a generic “please review”; point them to the difficult parts.

## Preferred structure

```md
## Context
- Problem/request:
- Affected users or systems:
- Evidence/root cause:

## Goal and non-goals
- This PR will:
- This PR will not:

## Change and scope
- Affected apps/packages/services:
- Behavior/API/schema/config changes:
- Dependencies, flags, migrations, compatibility:

## Design and tradeoffs
- Why this approach:
- Alternatives rejected:
- Intentional debt or lifecycle exception:

## Acceptance criteria
- Given [condition], [observable result] should happen.
- Success metric:

## Testing and evidence
- Automated commands and results:
- Manual/browser/device/environment checks:
- Performance or before/after evidence:
- Not tested / known failures:

## Reviewer focus
1. [specific decision or risk]
2. [edge case, performance, resilience, or compatibility concern]

## Release safety
- Rollout/feature flag:
- Migration order:
- Monitoring/alerts:
- Rollback/off-switch:
- Owner and follow-up:

## Links
- Issue/spec/design:
- Related PRs/dashboards/demos:
```

## Keep it current

When review changes the design, update the main description so it describes the
code that will actually merge. Add a small update note only when the history is
useful:

```md
### Update — <date or commit>
- Decision:
- Evidence:
- Remaining risk:
- Follow-up:
```

Remove stale alternatives, abandoned plans, generated noise, and claims that are no
longer true. Do not bury an important decision only in a comment.

## Lifecycle exceptions

If the project will be superseded, is deliberately blackboxed/isolated, or is
legacy code scheduled for removal, say so explicitly. Document the minimum safe
scope, the preserved contract, and the debt or exit path. Do not use lifecycle as an
excuse to omit correctness, security, or operational risk.

## Quality bar

The description should let a new reviewer answer:

- What is this for?
- What exactly changes?
- Why is it simple and understandable enough?
- What could be slow, fragile, or expensive?
- How was it proven?
- What remains unknown?
- How do we undo or finish it safely?

Never invent tests, metrics, approvals, links, or rollout details. If something is
unknown, write that it is unknown and assign the next verification step.
