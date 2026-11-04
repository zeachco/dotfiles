# llama.cpp tooling — still open

History (the "more parallel models" ask of 2026-09, np vs --models-max, LRU eviction, the
cheap tier) is written up in `docs/ryzen-llm-setup.md`; the GTT unlock it depended on was
applied 2026-11-04. What remains:

- **`los-check` has no Linux equivalent.** The `los` menu (`llamacpp/shared/_los_menu.sh`)
  shows each model's `.ini` section but does not diff section names against the router's
  ids, so a section matching no id is ignored silently. The macOS helpers in
  `variants/osx/profile.sh` remain a separate implementation.
- **Three readers of `/v1/models`.** `bin/llamacpp-sync` writes both clients and pi's
  `llamacpp-discover.ts` reads live; `_ai_tools.sh:_ai_resolve_model` is still a second
  reader and the `los` menu a third (read-only).
- **Faster models.** Nothing new was downloaded for the light tier; the cheap tier only
  gives shell calls a fast path.
