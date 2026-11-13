# Model routing (GPT-5.6 Luna default)

`GPT-5.6 Luna` (`openai-codex/gpt-5.6-luna`) is Pi's default model and the model used by every agent profile. Route by the *kind* of step, not by how big the task is; profiles use minimal thinking for mechanical work and high thinking for planning and review.

| Step | Who |
|---|---|
| Understand, design, decide, review | The main session (`GPT-5.6 Luna`), or the `planner` / `reviewer` subagents |
| Build: decide, then execute | `/preset build` — types itself for judgement calls, delegates mechanical typing |
| Read many files to answer one question | `scout` subagent |
| Multi-file edits, run commands, run tests | `worker` subagent |
| One small, exact change (fill in code, apply a diff) | `completion` / `code` subagents, or `/preset completion` / `/preset code` |

Rules of thumb:

- Once you know *what* to change, delegate the typing instead of doing it yourself — its verbose tool output stays out of this context: small exact changes to `completion`/`code`, bigger briefs to `worker`.
- `completion` / `code` are the typing tier: one small, fully-spelled-out task each, no judgement. Give them the exact file, the exact change, the exact check — and review their output before accepting it.
- A subagent is a fresh process. It has NOT seen this conversation. Its task text must be self-contained: exact paths, function names, the change, how to verify. If you cannot write that brief yet, you are not done thinking.
- Reach for `scout` before reading more than two or three files yourself.
- Local llama.cpp models are still available when needed. The router loads NOTHING on its own (`--no-models-autoload`, since 2026-11-06): a request for a model that is not resident gets 400 "model is not loaded". Picking a model in `/model` loads it when it fits in free GPU memory (llamacpp-discover.ts); otherwise, in a shell, `los` (menu) or `los-drain` then `los-load <model>`. Nothing is evicted behind your back any more — memory is the only budget, and `los` shows it.
- If `GPT-5.6 Luna` is unavailable or out of credits, retry the same role with `llamacpp/Qwen3.8-Flash-Next` at the same thinking level. `GPT-5.6 Luna` accepts image input; local `Qwen3.8-Flash-Next` and `qwen3.8` are text-only, so images sent while using them go through the vision-relay skill.
- The small local models stay on disk and can be selected by hand, but nothing routes to them automatically: they are 16k-context and cold.

Workflows: `/implement <task>` (scout → planner → worker), `/build <task>` (worker only), `/review [what]`, `/game-dev [project description]` (new browser game per ~/DEV_STYLE.md; asks for a project description and waits if none is given). Manual switch: `/preset think` (alias `/preset plan`), `/preset build`, `/preset completion`, `/preset code`.
- On the mac, `llamacpp-remote/*` is the Strix Halo box (`oli-llms.local:7070`) over the LAN; `/model` loads there the same way, `los` targets it with `LOS_URL=http://oli-llms.local:7070`.

# Writing style

The user is not a native English speaker. Write every reply, document, comment, commit
message, and PR text in plain English:

- Use short sentences. One idea for each sentence.
- Use common words. Do not use idioms, slang, or rare words.
- Use one name for each thing. Do not change the name later in the text.
- Put the condition first: "If the test fails, stop."
- Use the active voice, and the imperative for instructions.

This is not strict ASD-STE100. Use the `asd-ste100` skill only when the user asks for STE.
Do not change code, commands, identifiers, or quoted text.
