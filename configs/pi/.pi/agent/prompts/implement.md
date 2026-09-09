---
description: scout (fast) → planner (slow) → worker (fast). Full delegated implementation of a task.
---
Use the subagent tool with the `chain` parameter:

1. "scout" – find all code relevant to: $@
2. "planner" – write an implementation brief for "$@" from the scout findings ({previous})
3. "worker" – execute the brief from {previous} verbatim

Pass output between steps via {previous}. When the chain finishes, summarise what the worker changed and whether verification passed. Do not re-do the work yourself.
