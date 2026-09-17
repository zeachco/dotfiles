---
description: Start a browser game with the TypeScript + game objects style (~/DEV_STYLE.md)
argument-hint: "[project description]"
---
You are starting (or continuing) a browser-game project.

Style: read /home/olivier/DEV_STYLE.md now and adopt its "The prompt" section
verbatim as the binding style for this project. For a brand-new project, create
the style instead of matching existing code. Do not summarize or skip it.

Project description: ${@:-<none given yet>}

If the description is <none given yet> (or is missing key details):
- Ask the user to describe the project: game concept, core entities and what
  each one does, controls, first milestone, and where the code lives (new Vite
  project, or an existing repo + folder).
- Then STOP and wait for the answer. Do not scaffold, create files, or write
  code before the description arrives.
- When the description arrives later in this conversation, continue from there.

Once you have a description:
- Propose the layout derived from it: src/games/<name>/ with main.ts
  (default-exporting `async (state) => ...`), classes/ (one entity class per
  PascalCase file), utilities.ts (+ defaultState), types.ts (tiny enums), the
  `config` Config class singleton exposed on window, and a living doc
  (STREAM.md) with the current goal and an on-screen legend.
- Confirm the entity list with the user if the scope is unclear, then build the
  first milestone following every rule in the style guide (state, loops,
  performance, comments, robustness, format).
- Keep the living doc updated while working, not after.
