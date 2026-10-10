---
name: zeachco-code-review
description: >
  Review code in Zeachco's style: make it readable, simple, clear, precise, fast,
  resilient, and pleasant to change. Use for pull-request and diff reviews.
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
5. **Priority** — blocker, should-fix, question, or nit.

Prefer questions when intent is unclear. Separate correctness issues from design
preferences. Acknowledge good work when it matters. Do not produce a long list of
style opinions after the important risks are covered.

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

## 5. Finish the review

Before approving, confirm that:

- the intent and scope are clear;
- important behavior has evidence, not assumptions;
- the code is understandable without unnecessary navigation;
- failure, performance, rollout, and rollback paths are acceptable;
- technical debt is reduced or consciously bounded;
- every remaining concern has an owner, scope, or explicit acceptance.
