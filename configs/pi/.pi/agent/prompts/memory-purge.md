---
description: Clean up memories that don't serve development or product context. When unsure about relevance, ask with a short summary.
---

Review the memories in ~/.pi/agent/memory/ and identify which to remove.

**Keep criteria:**
- Development work (code, repos, debugging, fixes)
- Product decisions or requirements
- Infrastructure or server configs
- Hardware specs or setup details

**Remove if:**
- Personal trivia or preferences without dev/product relevance
- Outdated notes or temporary state
- Duplicates of information elsewhere
- Irrelevant to current or future work

**For uncertain cases:**
Before removing a memory, report:
- Its title
- A 2-3 sentence summary
- Your recommendation (keep/remove)

Use `remove_memory` to delete items you choose. Report your final cleanup summary.
