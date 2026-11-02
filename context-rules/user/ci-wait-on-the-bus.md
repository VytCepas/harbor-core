---
order: 91
description: A CI wait runs on the event bus, never as a poll
event: PreToolUse
tool: Bash
when: always
run: ci-wait-on-the-bus.sh
once: session
---

<!--
`when: always` with the gate inside the run script, as 90-unbounded-wait-loop.md does: "this command
polls CI" is a parse (a `gh pr checks` or `gh run` read inside a wait, or a `--watch`), not a substring.

`once: session` because the remedy is one command a session learns once; a second poll in the same
session is the same lesson.

OWNER. harbor#1367. The bus carries ci.job.done from every runner this box hosts (ci-governor listen
and the job hook), and `harbor event ci` (bin/ci-wait.sh) is the wait that sleeps on it.

WHY IT CLEARS THE BAR IN "Writing a good rule":
  · moment      — the Bash call that starts polling CI, not a general principle.
  · cost        — measured 2026-10-25: a `wait-for` on project-init#1112's checks ran 31 minutes after CI
                  was green, held by review/decision, a status that is not CI; earlier the same day a
                  waiter on #1366 ran 50 minutes against a script path it could not read.
  · nothing else fires — 90-unbounded-wait-loop stays silent on any command calling wait-for, which is
                  exactly the shape of these polls; no lint or CI job sees a runtime wait.
  · falsifier   — a session polling `gh pr checks` in wait-for, a loop or `--watch` that does NOT get the
                  note, or a single `gh pr checks <n>` read (or `harbor event ci` itself) that DOES.
-->
