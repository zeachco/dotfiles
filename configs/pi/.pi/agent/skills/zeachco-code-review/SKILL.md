---
name: zeachco-code-review
description: >
  Review a pull request in zeachco's observed engineering style: evidence-first,
  operationally cautious, scope-aware, and focused on readable contracts and real
  behavior. Use when reviewing code, a diff, or an AI-generated PR review.
---

# Zeachco code-review profile

This is a calibration profile, not a rule that every PR must look the same. It was
inferred from 556 non-owned PRs reviewed by `zeachco` during 2025-10-09—2026-10-09:
1,338 non-empty comments across 382 PRs. Counts below are overlapping thematic
approximations; the source inventory is
`docs/pr-review-audit-2025-10-09--2026-10-09.md`.

## Review stance

- Prefer **evidence over assumption**: reproduce, measure, inspect CI, or ask for
  the missing evidence.
- Review behavior and operational consequences, not only local code style.
- Treat reviewability as quality: clear names, typed boundaries, focused modules,
  and a diff whose scope is easy to understand.
- Match rigor to lifecycle and risk. A sunset or experimental service may justify
  a pragmatic fix, but record deferred debt instead of pretending it is ideal.
- Be direct without being adversarial. Acknowledge good catches and explain the
  constraint behind a disagreement.

## Procedure

1. **Reconstruct intent and context**
   - What problem, user, service, or failure is this solving?
   - Which apps, packages, environments, owners, and lifecycle stage are involved?
   - Separate the requested behavior change from refactoring, migration, generated
     output, and unrelated cleanup.
2. **Check the contract**
   - Inputs, outputs, types, schemas, defaults, names, and compatibility.
   - Null, empty, malformed, unexpected, duplicate, and partially migrated data.
   - Fallbacks, error propagation, timeouts, retries, idempotency, ordering, and
     race/concurrency behavior.
   - Browser, mobile, client/server, and cross-environment differences where relevant.
3. **Check production behavior**
   - Dependency and lockfile drift, CI/build/deploy configuration, Docker/Kubernetes,
     feature flags, migrations, secrets, permissions, and rollback.
   - Request volume, latency, memory, bundle size, cost, capacity ceilings, and
     silent data loss.
   - Logs, metrics, traces, alerts, and an explicit off-switch for risky behavior.
4. **Check evidence**
   - Does the test exercise the regression and realistic fixtures, or merely execute?
   - Ask for fresh-install, smoke, browser/device, baseline-vs-branch, or real-edge
     evidence when the claim cannot be established statically.
   - Treat passing CI as evidence for the tested path, not proof of every environment.
5. **Check review shape**
   - Request separate PRs or commits when refactor, behavior, migration, or
     infrastructure changes make rollback and review ambiguous.
   - Prefer intention-revealing names and explicit code over clever indirection or
     hidden state.
6. **Check automation and security**
   - Validate inputs early; look for SSRF/allowlist, auth, secret, permission,
     destructive-command, auditability, and production-credential risks.
   - For AI tooling, minimize untrusted context, protect destructive commands, and
     retain a human owner.

## Finding format

For each finding, state:

1. **Location** — file, line, or behavior.
2. **Risk** — what breaks, for whom, and under which condition.
3. **Evidence** — reproduction, test, metric, link, or the missing fact.
4. **Recommendation** — the smallest safe change.
5. **Scope** — fix now, separate PR, ticket/cooldown, or acceptable as-is.

Classify as blocking, should-fix, question, or nit. Do not turn every preference
into a blocker. If the PR is safe, say so explicitly and list only useful follow-up
nits.

Useful comment shapes:

- “What happens when `<edge case>`? I would like a test or a short explanation of
  the intended fallback.”
- “Could we split the refactor from the behavior change? It would make rollback and
  review easier.”
- “I agree with the underlying concern, but this service is `<constraint>`; I would
  keep the current behavior here and track the broader cleanup separately.”
- “Can we verify this with `<command/metric/device>` rather than assume the behavior?”

## Likely AI blind spots (inference, not measured misses)

Use human judgment especially for:

- traffic, capacity, cost, proxy/CDN, browser/device, and deployment behavior;
- domain vocabulary, ownership, lifecycle, and whether a cleaner refactor is safe;
- sequencing of refactor + migration + behavior changes and rollback boundaries;
- silent failure, observability, production scripts, credentials, and auditability;
- whether an AI recommendation invalidates the purpose of a test harness.

AI findings are inputs to reproduce and triage, not automatic blockers.

## Deliberate gap checks

The corpus shows weaker explicit coverage of accessibility, privacy/data retention,
dependency licensing/supply-chain risk, authorization threat modeling, success
metrics, monitoring ownership, compatibility/breaking behavior, and “not tested”.
Add a short pass for these even when the diff looks familiar.
