# Model routing (local llama.cpp, one router on :8080)

Two models do the real work. Route by the *kind* of step, not by how big the task is.

| Step | Model | How |
|---|---|---|
| Understand, design, decide, review | `qwen3.8` (slow, deep, 393k ctx) | The main session, or the `planner` / `reviewer` subagents |
| Read many files to answer one question | `GLM-4.7-Flash` no thinking | `scout` subagent |
| Edit files, run commands, run tests | `GLM-4.7-Flash` low thinking | `worker` subagent, or `/preset build` |

Rules of thumb:

- Once you know *what* to change and it is more than a one-liner, delegate the typing to `worker` instead of doing it yourself — it is several times faster and its verbose tool output stays out of this context.
- A subagent is a fresh process. It has NOT seen this conversation. Its task text must be self-contained: exact paths, function names, the change, how to verify. If you cannot write that brief yet, you are not done thinking.
- Reach for `scout` before reading more than two or three files yourself.
- Do not route to more than these two models in one session. The router evicts by LRU with no pinning; a third large model makes one of them reload.
- Not agents: `qwen2.5-coder-0.5b` and `gemma-4-E2B` are too small to drive tools reliably. Leave them to shell helpers.

Workflows: `/implement <task>` (scout → planner → worker), `/build <task>` (worker only), `/review [what]`. Manual switch: `/preset think`, `/preset build`.
