# Model routing (local llama.cpp, light router on :7070, heavy on :7072)

One local model does the heavy lifting: `qwen3.8` thinks AND types. Route by the *kind* of step, not by how big the task is. Which model backs each subagent lives in the agent files, not here.

| Step | Who |
|---|---|
| Understand, design, decide, review | The main session (`qwen3.8`), or the `planner` / `reviewer` subagents |
| Build: decide, then execute | `/preset build` — types itself for judgement calls, delegates mechanical typing |
| Read many files to answer one question | `scout` subagent |
| Multi-file edits, run commands, run tests | `worker` subagent |
| One small, exact change (fill in code, apply a diff) | `completion` / `code` subagents, or `/preset completion` / `/preset code` |

Rules of thumb:

- Once you know *what* to change, delegate the typing instead of doing it yourself — its verbose tool output stays out of this context: small exact changes to `completion`/`code`, bigger briefs to `worker`.
- `completion` / `code` are the typing tier: one small, fully-spelled-out task each, no judgement. Give them the exact file, the exact change, the exact check — and review their output before accepting it.
- A subagent is a fresh process. It has NOT seen this conversation. Its task text must be self-contained: exact paths, function names, the change, how to verify. If you cannot write that brief yet, you are not done thinking.
- Reach for `scout` before reading more than two or three files yourself.
- Locally there is exactly ONE big resident model: `qwen3.8`. Keep it that way: the light router evicts by LRU with no pinning and counts models, not bytes, so every extra light-tier model that gets loaded costs a slot of `--models-max 4`, and a fan-out loop against a small model elects qwen3.8 as the victim — that is what the cheap tier on :7071 exists for (light.ini, "Eviction hazard").
- Heavy-tier models (`llamacpp-heavy`, :7072) are never loaded implicitly (selecting one gives 400 "model is not loaded"): in a shell, `los-drain` then `los-load <model>`, or inside pi `/llama` (after a one-time `/login llama.cpp` with http://127.0.0.1:7072). Expect qwen3.8 to reload afterwards. Never route a subagent to them.
- The small light-tier models stay on disk and can be selected by hand, but nothing routes to them automatically: they are 16k-context and cold. There is no local vision model for pi, so images go through the vision-relay skill.

Workflows: `/implement <task>` (scout → planner → worker), `/build <task>` (worker only), `/review [what]`, `/game-dev [project description]` (new browser game per ~/DEV_STYLE.md; asks for a project description and waits if none is given). Manual switch: `/preset think` (alias `/preset plan`), `/preset build`, `/preset completion`, `/preset code`.
