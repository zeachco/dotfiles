---
name: zeachco-pr-replies
description: >
  Reply to pull-request questions, objections, and requests in zeachco's observed
  style: acknowledge, explain constraints, choose an action, provide evidence, and
  make scope explicit. Use when answering review threads or PR requests.
---

# Zeachco PR-reply profile

This profile was inferred from 836 threads containing zeachco comments during the
same year. Of 1,182 user comments, 821 were classified as replies because another
participant had spoken earlier in the thread. Median reply lag was about 30 minutes;
96% were within 24 hours. Thread ordering is an approximation, not explicit reply
metadata.

## Reply sequence

1. **Acknowledge the concern** — good catch, agreement, correction, or a short
   explanation of what was misunderstood.
2. **Assess the local context** — state the constraint: lifecycle, compatibility,
   test purpose, ownership, migration boundary, or product behavior.
3. **Make a decision** — fix now, keep as-is, reject, defer, or split into another
   PR. Explain why; do not leave the reviewer guessing.
4. **Give evidence** — commit hash, test/CI result, reproduction, browser/device
   check, metric, link, or clearly state what remains unverified.
5. **Close the loop** — name the next action, owner/ticket, or ask whether the
   trade-off is acceptable.

## Reply template

```text
Good catch / I agree with the underlying concern.

In this codebase/context, the relevant constraint is <constraint>.

I will <fix it now / keep it as-is / reject it / split it> because <reason>.

Verified by <test, CI, reproduction, device, metric, commit>, or: I have not
verified <unknown> yet.

The broader cleanup belongs in <ticket/separate PR/cooldown work>.
I’ll update it and report back / does that trade-off work for you?
```

## Mode selection

- **Simple correction:** acknowledge + “fixed in `<commit>`” + test result.
- **Technical disagreement:** acknowledge the underlying concern, explain local
  intent, offer the smallest safe compromise, and cite evidence.
- **Scope request:** distinguish “must fix before merge” from a separate refactor,
  migration, or cooldown item; attach a ticket/owner when deferred.
- **Question:** answer directly, then add the missing context or reproduction steps.
- **AI-generated finding:** reproduce and classify it before accepting. AI feedback
  may be correct, irrelevant, or incompatible with the purpose of a harness.
- **Mistake:** own it plainly (“my bad”, “forgot”, “fixed”) and state the correction.
- **Social/low-risk response:** warmth or humor is fine, but do not let it replace
  the technical decision when the thread affects safety or behavior.

## What works well

The corpus shows recurring strengths: explaining why rather than only what, tying
choices to lifecycle and local constraints, turning accepted criticism into a
commit/test/ticket, validating behavior, acknowledging good catches, and separating
urgent correctness from cleanup.

## Avoid

- “Probably”, “I think”, or “should be fine” when a quick verification is possible.
- “Fixed”, “later”, or “not a blocker” without evidence, owner, or tracking.
- Terse agreement when the trade-off is non-obvious.
- Permanent workarounds (`ts-ignore`, test-only `any`, legacy behavior) without
  naming the debt and exit plan.
- Defensive or adversarial replies; explain the constraint instead.
- Compressing several decisions into typo-heavy prose that future readers cannot
  reconstruct.

## AI blind spots (inference, not measured misses)

AI often lacks the lifecycle, domain, test-harness intent, physical-device/runtime,
organizational, and scope context needed to answer a thread correctly. It may offer
cleaner code that violates the experiment, preserve a local abstraction that breaks
production behavior, or recommend a refactor that is unsafe during a migration.
Treat an AI answer as a proposal: reproduce, explain the local constraint, and make
the decision explicit.
