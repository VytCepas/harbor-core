---
order: 99
description: Names the skill that owns a CLI or tool, with its SKILL.md path, the first time a session uses it unread
event: PreToolUse
tool: Bash|Agent|Task
when: always
once: never
run: skill-first-use.sh
---

<!--
A 30-day transcript audit found 28-38% of sessions that ran a skill's CLI never read its SKILL.md, and
75 of 81 that spawned agents never read agent-routing. Prose in the skill did not bind; a note at the tool
call does (docs/reports/evals.md E6: 0/4 as prose, 4/4 injected).

`when: always` with the gate in the script: which command belongs to which skill is DERIVED from the
installed skills' own frontmatter (owns-commands, owns-tools, inline-section; skills/README.md), so core
names no client system. `once: never` because the script keeps its own ledger, one entry per skill, which
the engine's per-pack `once` cannot express.

Numbered 99 so it runs after 97-agent-model-required: a deny drops the call's notes, and a note sent
beside a denied Agent call would spend the ledger and reach nobody.
Disable: delete this file and its script, then `harbor inject --live --apply`.
-->
