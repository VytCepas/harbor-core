---
order: 55
description: The first listed tool call (the core built-ins, no MCP) of a session with no title asks for one, written with the Write tool where the title hook reads it
event: PreToolUse
tool: Bash|Read|Write|Edit|MultiEdit|NotebookEdit|Grep|Glob|Agent|Task|Skill|WebFetch|WebSearch|AskUserQuestion|ToolSearch
when: always
once: session
run: session-title-missing.sh
---

<!--
Titles were a memory note only, and 17 of 30 large sessions in a week never got one: a rule the
model must remember at close is the rule that gets dropped. The note fires on the first tool call
of an untitled session, when the topic is known; the script is silent once a title file exists,
in a subagent, or when ~/.claude/session-title.off is set. hooks/session-title applies the file.
Disable: delete this file and its script, then `harbor inject --live --apply`.
tool: is the core built-in tools, no MCP and not Monitor, SendMessage or TaskStop; the note waits for the first of them. With none, the matcher was `.*` and every MCP call (harbor chrome above all) paid ~0.25 s for this one-off note (harbor#1507).
-->
