# zeachco PR corpus — past year (2025-10-09 → 2026-10-09)

## Analysis (Oct 2026)

Full corpus: 1,468 PRs fetched serially (951 reviewed-window + 517 own).
- zeachco comments: 3,218 on reviewed PRs (510 inline, 1,911 inline-reply, 406
  issue-comment, 391 review-body), 1,338 on own PRs.
- Bot comments on the same PRs: 839 (codex 522, semgrep 156, copilot 109, other 52).
- 85% of reviewed PRs get comments; silent approves (106) are all small chores.
- Median 3 comments/PR; 75 PRs with 10+ (refactors/migrations/experiments).
- Own PRs: 494 bodies (28% AI-generated & marked), median 1 commit, 681 self-reviews
  all COMMENTED (never self-approve), 228 replies to bot threads.

Profiles extracted into three skills:
- `configs/opencode/.config/opencode/skills/zeachco-review/` — how I review + what AI review misses
- `configs/opencode/.config/opencode/skills/zeachco-selfdoc/` — how I document my own PRs
- `configs/opencode/.config/opencode/skills/zeachco-replies/` — how I answer threads (human + bot)

Raw corpus (transient, regenerated on demand): /tmp/opencode/zeachco/ (flat/, batches/, notes/)
