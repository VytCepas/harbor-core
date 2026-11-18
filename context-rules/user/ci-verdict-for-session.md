---
order: 94
description: Delivers the CI verdict of a PR this session opened, written by event.session-ci-watch, on the session's next Bash, Read, Grep or Glob call, once
event: PostToolUse
tool: Bash|Read|Grep|Glob
when: always
once: never
run: ci-verdict-for-session.sh
---

<!--
`once: never` with the once-ness in the run script: each note is printed once and removed, so the next verdict (a
re-armed watch sends a still-running notice and then the verdict) is a new note, not a repeat.

OWNER. harbor#1044 (event.session-ci-watch). Measured 2026-11-16: the watch wrote "still running after 1800s" to
reactions.log and the desktop, and the session that opened the PR never saw it; the PR's relay job had been cancelled.

WHY IT CLEARS THE BAR IN "Writing a good rule":
  · moment      - the opening session's next Bash, Read, Grep or Glob call after the watch wrote a note for it.
                  Not every tool: an MCP call (harbor chrome above all) would wake the engine for this rare note (harbor#1507).
  · cost        - a session waiting on, or merging past, a PR whose CI is stuck or red without knowing it.
  · nothing else fires - the banner reaches the desktop, not the model; UserPromptSubmit injection is refused
                  (contracts/hooks.md), and the pull hook it would use is not wired.
  · falsifier   - a note in session-notes/<this session> that is NOT printed, printed twice, or printed to another
                  session; or a note printed with no note file.
Disable: delete this file and its script, then `harbor inject --live --apply`; the control row is context.ci-verdict-for-session.
-->
