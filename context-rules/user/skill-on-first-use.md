---
order: 99
description: Names the skill that owns a call (a CLI, a tool, or content its regex matches), with its SKILL.md path, while the session has not read it; a gate CLI waits for the read
event: PreToolUse
tool: Bash|Agent|Task|Write|Edit|MultiEdit|mcp__claude_ai_Claude_Docs__batch|mcp__claude_ai_Claude_Docs__update|mcp__harbor_chrome__attach|mcp__claude-in-chrome__tabs_context_mcp
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

harbor#1591: the same audit, re-run over 7 days, found the note read in 18 of 47 sessions for agent-routing and the
Lithuanian skill read in 4 of 10, and only 4 of 45 installed skills owned anything. So a skill may own CONTENT
(`owns-content`, a regex over the call input), the note repeats as one line while the skill stays unread (the next
owned call and every 10th after, at most 5 per session), and a `gate-commands` CLI or `cli:subcommand` prints the
deny sentinel. This row is block, promoted by the operator, so the sentinel is a deny; warn would make it a note.
The only deny this pack can emit is a gate, so the row's mode changes nothing else.

Numbered 99 so it runs after 97-agent-model-required: a deny drops the call's notes, and a note sent
beside a denied Agent call would spend the ledger and reach nobody.
Disable: delete this file and its script, then `harbor inject --live --apply`.
-->
