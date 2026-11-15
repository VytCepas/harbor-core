---
description: After the operator answers an AskUserQuestion round, record each answer where it binds and re-derive the frontier (docs/explanation/grilling.md; disable by deleting this file, then harbor inject --live --apply)
event: PostToolUse
tool: AskUserQuestion
when: always
once: never
---

The operator just answered. In this turn, before the next round or any build step: record each
answer where it binds (the ticket or PR it changes, a decision record under docs/decisions/, or a
named memory-note edit), never only in chat; treat a free-text Other answer as a possible redirect and
re-derive the frontier from it rather than asking the next prepared question; and if questions remain,
say how many and the one-line shape of each before asking them. Standard: harbor
docs/explanation/grilling.md.
