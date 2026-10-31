---
order: 55
description: The first tool call of a session with no title asks for one, written where the title hook reads it
event: PreToolUse
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
-->
