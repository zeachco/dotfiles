# Model routing (local llama.cpp, light router on :7070, heavy on :7072)

One local model does the heavy lifting: `qwen3.8` thinks AND types. The fast typing tier runs on OpenRouter (`glm-5.3-flash` / `gemini-3.8-flash`, no local footprint — local `GLM-4.7-Flash` was retired from the light router 2026-10-12, see light.ini). Route by the *kind* of step, not by how big the task is.

| Step | Model | How |
|---|---|---|
| Understand, design, decide, review | `qwen3.8` (slow, deep, 393k ctx) | The main session, or the `planner` / `reviewer` subagents |
| Build: decide, then execute | `qwen3.8` | `/preset build` — types itself for judgement calls, delegates mechanical typing |
| Read many files to answer one question | `glm-5.3-flash` via OpenRouter, no thinking | `scout` subagent |
| Multi-file edits, run commands, run tests | `gemini-3.8-flash` via OpenRouter, low thinking | `worker` subagent |
| One small, exact change (fill in code, apply a diff) | `glm-5.3-flash` via OpenRouter, no thinking | `completion` / `code` subagents, or `/preset completion` / `/preset code` |

Rules of thumb:

- Once you know *what* to change, delegate the typing instead of doing it yourself — it is several times faster and its verbose tool output stays out of this context: small exact changes to `completion`/`code`, bigger briefs to `worker`.
- `completion` / `code` are the typing tier: the same GLM as `worker`, but with thinking off and a stricter prompt. One small, fully-spelled-out task each, no judgement. Give them the exact file, the exact change, the exact check — and review their output before accepting it.
- A subagent is a fresh process. It has NOT seen this conversation. Its task text must be self-contained: exact paths, function names, the change, how to verify. If you cannot write that brief yet, you are not done thinking.
- Reach for `scout` before reading more than two or three files yourself.
- Locally there is exactly ONE big resident model now: `qwen3.8`. Keep it that way: the light router evicts by LRU with no pinning and counts models, not bytes, so every extra light-tier model that gets loaded costs a slot of `--models-max 4`, and a fan-out loop against a small model keeps its own weights freshest and elects qwen3.8 as the victim — that is what the cheap tier on :7071 exists for (light.ini, "Eviction hazard"). If local typing is ever wanted again, `Qwen3-4B` (2.4 GB, text-only) is the candidate: one slot, versus GLM's ~27 GiB.
- Heavy-tier models (`llamacpp-heavy`, :7072 -- gpt-oss-120b, DeepSeek) are never loaded implicitly (selecting one gives 400 "model is not loaded"): in a shell, `los-drain` then `los-load <model>`, or inside pi `/llama` (after a one-time `/login llama.cpp` with http://127.0.0.1:7072). Expect qwen3.8 to reload afterwards. Never route a subagent to them.
- `qwen2.5-coder-0.5b`, `gemma-4-E2B` and the other small light-tier models stay on disk and can be selected by hand, but nothing routes to them automatically: they are 16k-context and cold, so a delegated step pays a load stall to use a weaker model. `gemma-4-E2B` is the local vision path (qwen3.8's projector was retired 2026-10-12 to activate prefix KV reuse; the vision-relay skill relays images to a vision model).

Workflows: `/implement <task>` (scout → planner → worker), `/build <task>` (worker only), `/review [what]`, `/game-dev [project description]` (new browser game per ~/DEV_STYLE.md; asks for a project description and waits if none is given). Manual switch: `/preset think` (alias `/preset plan`), `/preset build`, `/preset completion`, `/preset code`.
