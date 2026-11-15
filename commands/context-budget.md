---
description: What this session costs before the first word, against the ceiling — and what is not counted
allowed-tools: Bash(sh ~/port/harbor/bin/context-budget.sh:*), Bash(wc:*), Bash(ls:*)
---

What does a session on this box pay before anyone types anything?

!`sh ~/port/harbor/bin/context-budget.sh 2>&1`

Read it back with three things made explicit, because the raw table hides all
three:

1. **The largest line, named.** It is almost certainly `CLAUDE.md` or the
   cwd-keyed auto-memory index, not the skills — and the skills are what people
   reach for first when trimming.
2. **What the tool still does not measure.** Repo-scoped `.claude/rules/*.md`
   load ambiently *in that repo* and appear nowhere in this report. On
   2026-08-07 that was 6,450 B in one workload repo and 4,758 B in another, on top
   of the global figure. A session in the measurement repo (resolved through the repo registry) therefore pays materially more than
   this table says. Say so rather than reporting the total as complete.
3. **The tier split.** A skill carrying `disable-model-invocation: true` is
   removed from the model's listing entirely and costs **nothing** per session.
   Quoting a total across both tiers overstates the ambient cost by roughly 3×,
   which has happened twice in this estate and inverted a recommendation both
   times. If you state a skills number, state which tier it is.

Then, only if asked: what would actually move the number, largest first. Do not
propose trimming skills to save context without checking that the skills are
where the bytes are — twice now, they were not.
