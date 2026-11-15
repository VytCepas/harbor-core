---
order: 93
description: Before a long wait on a background task, confirm its process exists, and stop waiting if it is gone
event: PreToolUse
tool: Bash
when: always
run: long-wait-process-exists.sh
once: session
---

<!--
`when: always` with the gate in the run script: "this is a long wait" is a parse of a duration (a `sleep` of 300 s or
more, `wait-for` or `event wait` with a timeout of 600 s or more), not a substring.

OWNER. harbor#1010; the rule is also in the build lanes' "Waiting" rules (measured 2026-11-02: one lane idled 7.5 h on a
background run that no longer existed). Prose in a rules file is read once; this note arrives at the wait.

WHY IT CLEARS THE BAR IN "Writing a good rule":
  · moment      - the Bash call that begins the long wait.
  · cost        - 7.5 h of an idle lane; the harness re-invokes the model on a task's completion, but not when the task
                  was killed or never existed, so a gone process is silent.
  · nothing else fires - unbounded-wait-loop and ci-wait-on-the-bus judge loops and CI polls; neither sees a plain
                  `sleep 1800`, and no lint sees a runtime wait.
  · falsifier   - `sleep 1800` or `wait-for -t 3600 ...` that does NOT get the note, or `sleep 5`, `wait-for -t 60 ...`
                  or a quoted mention that DOES.
Disable: delete this file and its script, then `harbor inject --live --apply`; the control row is context.long-wait-process-exists.
-->
