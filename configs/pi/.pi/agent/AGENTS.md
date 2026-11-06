# Model routing (local llama.cpp, one router on :7070, nothing autoloads)

One local model does the heavy lifting: `Qwen3.8-Flash-Next` (pi's `defaultModel` since 2026-11-07) thinks AND types; `qwen3.8` is the lighter fallback. Route by the *kind* of step, not by how big the task is. Which model backs each subagent lives in the agent files, not here.

| Step | Who |
|---|---|
| Understand, design, decide, review | The main session (`Qwen3.8-Flash-Next`), or the `planner` / `reviewer` subagents |
| Build: decide, then execute | `/preset build` — types itself for judgement calls, delegates mechanical typing |
| Read many files to answer one question | `scout` subagent |
| Multi-file edits, run commands, run tests | `worker` subagent |
| One small, exact change (fill in code, apply a diff) | `completion` / `code` subagents, or `/preset completion` / `/preset code` |

Rules of thumb:

- Once you know *what* to change, delegate the typing instead of doing it yourself — its verbose tool output stays out of this context: small exact changes to `completion`/`code`, bigger briefs to `worker`.
- `completion` / `code` are the typing tier: one small, fully-spelled-out task each, no judgement. Give them the exact file, the exact change, the exact check — and review their output before accepting it.
- A subagent is a fresh process. It has NOT seen this conversation. Its task text must be self-contained: exact paths, function names, the change, how to verify. If you cannot write that brief yet, you are not done thinking.
- Reach for `scout` before reading more than two or three files yourself.
- The router loads NOTHING on its own (`--no-models-autoload`, since 2026-11-06): a request for a model that is not resident gets 400 "model is not loaded". Picking a model in `/model` loads it when it fits in free GPU memory (llamacpp-discover.ts); otherwise, in a shell, `los` (menu) or `los-drain` then `los-load <model>`. Nothing is evicted behind your back any more — memory is the only budget, and `los` shows it.
- The daily resident model is `Qwen3.8-Flash-Next` — pi's `defaultModel`, ~67 GiB resident (plus ~28 GiB host RSS). `qwen3.8` is the fallback when it does not fit beside something else. The other big ones (`gpt-oss-120b-MXFP4`, `GLM-5.3-Flash`, `DeepSeek-V4-Flash-chat-v2`) each want most of the box: drain first, load one, expect to reload the daily afterwards. Never route a subagent to any of them.
- `Qwen3.8-Flash-Next` is text-only (no projector), so images from a default session go through the vision-relay skill — same as `qwen3.8` since 2026-10-12.
- The small models stay on disk and can be selected by hand, but nothing routes to them automatically: they are 16k-context and cold. There is no local vision model for pi, so images go through the vision-relay skill.

Workflows: `/implement <task>` (scout → planner → worker), `/build <task>` (worker only), `/review [what]`, `/game-dev [project description]` (new browser game per ~/DEV_STYLE.md; asks for a project description and waits if none is given). Manual switch: `/preset think` (alias `/preset plan`), `/preset build`, `/preset completion`, `/preset code`.
