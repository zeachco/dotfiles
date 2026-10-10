---
name: zeachco-pr-replies
description: >
  Answer pull-request questions and requests with clear technical reasoning,
  evidence, scope, and an explicit decision. Use when replying to review threads.
---

# PR reply runbook

A reply should move the review forward. It should make the code, tradeoff, or next
step clearer—not merely acknowledge that a comment was seen.

## Reply sequence

1. **Understand the request**
   - Is the person asking about correctness, readability, simplicity, performance,
     resilience, scope, or project context?
   - Restate the concern briefly if it could be misunderstood.
2. **Acknowledge the useful part**
   - Agree, thank them, correct your mistake, or say what is unclear.
   - Do not use politeness to avoid answering the technical question.
3. **Explain the local context**
   - State the relevant constraint: lifecycle, legacy status, blackbox boundary,
     migration order, test purpose, compatibility, or product behavior.
4. **Make the decision explicit**
   - Fix now, keep as-is, reject, defer, or split into another PR.
   - Explain why the decision preserves clarity, simplicity, precision, performance,
     resilience, or maintainability.
5. **Give evidence or name the unknown**
   - Link the test, command, CI result, benchmark, reproduction, device check,
     metric, commit, or relevant documentation.
   - If it has not been verified, say so and name the next check.
6. **Close the loop**
   - State the commit/owner/ticket/follow-up, or ask whether the tradeoff is clear.

## Reply patterns

### Straightforward fix

> Good catch. I fixed `<behavior>` in `<commit>` and verified it with `<test>`.

### Technical disagreement

> I agree with the underlying concern. In this component, `<constraint>` means
> `<current choice>` is intentional because `<reason>`. I verified `<evidence>`.
> I’ll keep the broader cleanup in `<separate PR/ticket>`.

### Lifecycle exception

> I would normally prefer `<cleaner design>`, but this project is `<superseded /
> blackboxed / legacy-to-be-removed>`. I’m keeping this change to `<minimum safe
> scope>` so we do not add work to the exit path. The preserved contract is `<...>`.

### Clarification request

> Do you mean `<interpretation A>` or `<interpretation B>`? The behavior differs
> when `<condition>`. I can check `<specific evidence>` once we confirm the intent.

### Deferred work

> This is worth doing, but it is separate from the correctness fix here. I’ll track
> `<specific work>` in `<ticket/owner>` rather than expand this PR.

### Mistake

> You’re right; I missed `<fact>`. I corrected it in `<commit>` and added `<test /
> guard>`.

## Avoid

- “Fixed”, “later”, “not a blocker”, or “should be fine” without a decision and
  evidence.
- Defending a preference without explaining the codebase or lifecycle constraint.
- Agreeing to a refactor that makes a focused fix harder to review or roll back.
- Treating an AI suggestion as authoritative; reproduce it and check whether it
  respects the purpose of the test, boundary, and production behavior.
- Accepting `ts-ignore`, test-only `any`, silent fallback, or legacy workarounds
  without naming the debt and its exit path.
- Overexplaining a trivial nit while underexplaining a correctness or operational
  risk.

## Final check

Before posting, the reader should know:

- what you understood;
- whether you agree;
- what will change or remain unchanged;
- why that is the right tradeoff here;
- what proves it, or what remains unverified;
- who owns the next step.
