# Model routing (local llama.cpp, light router on :7070, heavy on :7072)

Two models do everything: `qwen3.8` thinks, `GLM-4.7-Flash` types. Route by the *kind* of step, not by how big the task is.

| Step | Model | How |
|---|---|---|
| Understand, design, decide, review | `qwen3.8` (slow, deep, 393k ctx) | The main session, or the `planner` / `reviewer` subagents |
| Build: decide, then execute | `qwen3.8` | `/preset build` — types itself for judgement calls, delegates mechanical typing |
| Read many files to answer one question | `GLM-4.7-Flash` no thinking | `scout` subagent |
| Multi-file edits, run commands, run tests | `GLM-4.7-Flash` low thinking | `worker` subagent |
| One small, exact change (fill in code, apply a diff) | `GLM-4.7-Flash` no thinking | `completion` / `code` subagents, or `/preset completion` / `/preset code` |

Rules of thumb:

- Once you know *what* to change, delegate the typing instead of doing it yourself — it is several times faster and its verbose tool output stays out of this context: small exact changes to `completion`/`code`, bigger briefs to `worker`.
- `completion` / `code` are the typing tier: the same GLM as `worker`, but with thinking off and a stricter prompt. One small, fully-spelled-out task each, no judgement. Give them the exact file, the exact change, the exact check — and review their output before accepting it.
- A subagent is a fresh process. It has NOT seen this conversation. Its task text must be self-contained: exact paths, function names, the change, how to verify. If you cannot write that brief yet, you are not done thinking.
- Reach for `scout` before reading more than two or three files yourself.
- Every subagent here targets one of exactly two models, and both stay resident (~67 of ~120 GiB GTT). Keep it that way: the router evicts by LRU with no pinning and counts models, not bytes, so a third one — even a 0.5B — costs a slot of `--models-max 5`, and a fan-out loop against it keeps its own weights freshest and elects a big model as the victim. It is also faster: decode is bandwidth-bound and continuous batching shares one weight stream, so fanning out onto ONE model with `np` >= the agent count beats spreading across several (see ryzen-llm-setup.md, "Which heavy model for what").
- Heavy-tier models (`llamacpp-heavy`, :7072 -- gpt-oss-120b, DeepSeek) are never loaded implicitly (selecting one gives 400 "model is not loaded"): in a shell, `los-drain` then `los-load <model>`, or inside pi `/llama` (after a one-time `/login llama.cpp` with http://127.0.0.1:7072). Expect qwen3.8/GLM to reload afterwards. Never route a subagent to them.
- `qwen2.5-coder-0.5b`, `gemma-4-E2B` and the other small light-tier models stay on disk and can be selected by hand, but nothing routes to them automatically: they are 16k-context and cold, so a delegated step pays a load stall to use a weaker model. `gemma-4-E2B` is still the vision path.

Workflows: `/implement <task>` (scout → planner → worker), `/build <task>` (worker only), `/review [what]`. Manual switch: `/preset think` (alias `/preset plan`), `/preset build`, `/preset completion`, `/preset code`.
