# Model routing (local llama.cpp, light router on :7070, heavy on :7072)

Two large models do the real work; two small models do the typing. Route by the *kind* of step, not by how big the task is.

| Step | Model | How |
|---|---|---|
| Understand, design, decide, review | `qwen3.8` (slow, deep, 393k ctx) | The main session, or the `planner` / `reviewer` subagents |
| Build: decide, then execute | `qwen3.8` | `/preset build` — types itself for judgement calls, delegates mechanical typing |
| Read many files to answer one question | `GLM-4.7-Flash` no thinking | `scout` subagent |
| Multi-file edits, run commands, run tests | `GLM-4.7-Flash` low thinking | `worker` subagent |
| One small, exact change (fill in code, apply a diff) | `qwen2.5-coder-0.5b` / `gemma-4-E2B` | `completion` / `code` subagents, or `/preset completion` / `/preset code` |

Rules of thumb:

- Once you know *what* to change, delegate the typing instead of doing it yourself — it is several times faster and its verbose tool output stays out of this context: small exact changes to `completion`/`code`, bigger briefs to `worker`.
- The small models (`completion`, `code`) are not conversational: one small, fully-spelled-out task each, no judgement. Give them the exact file, the exact change, the exact check — and review their output before accepting it.
- A subagent is a fresh process. It has NOT seen this conversation. Its task text must be self-contained: exact paths, function names, the change, how to verify. If you cannot write that brief yet, you are not done thinking.
- Reach for `scout` before reading more than two or three files yourself.
- Do not route to more than the two large models in one session. The router evicts by LRU with no pinning; a third large model makes one of them reload. The two small models coexist with either (they are tiny).
- Heavy-tier models (`llamacpp-heavy`, :7072 -- gpt-oss-120b, DeepSeek) are never loaded implicitly (selecting one gives 400 "model is not loaded"): in a shell, `los-drain` then `los-load <model>`, or inside pi `/llama` (after a one-time `/login llama.cpp` with http://127.0.0.1:7072). Expect qwen3.8/GLM to reload afterwards. Never route a subagent to them.
- `qwen2.5-coder-0.5b` and `gemma-4-E2B` are the typing tier (`completion` / `code`): mechanical, self-contained briefs only. Anything that needs a back-and-forth or a plan goes to the large models.

Workflows: `/implement <task>` (scout → planner → worker), `/build <task>` (worker only), `/review [what]`. Manual switch: `/preset think` (alias `/preset plan`), `/preset build`, `/preset completion`, `/preset code`.
