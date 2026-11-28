---
order: 51
description: Each new session ticks the suggestion counter once and tells the agent how a person stops a suggestion
event: SessionStart
when: source-is startup
once: session
run: suggest-start.sh
---

<!--
harbor#1485: the tick lives here, not in suggest-tool, because that runs per tool call and two open sessions would read as many.
The pointer is here because a note fires only with a line, and a person may say stop in a session where no line was shown.
Disable: delete this file and suggest-start.sh, then `harbor inject --live --apply`.
-->
