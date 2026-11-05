---
order: 92
description: A suite run directly with sh or bash is pointed at test-suite-run.sh --select, which carries the timeouts
event: PreToolUse
tool: Bash
when: always
run: suite-run-through-runner.sh
once: session
---

<!--
`when: always` with the gate in the run script: "this runs a suite directly" is a parse (a command word of sh, bash or
a path, whose first argument is a `*.test.sh`), not a substring, so `ls tests/x.test.sh`, `git add` and a quoted
mention stay silent.

OWNER. harbor#1010 (agent discoverability); the runner is bin/test-suite-run.sh (harbor#679) and its idle and hard
timeouts are what a direct run lacks. The rules for build lanes say the same in prose, which is the shape this pack
exists to replace: measured 2026-11-02, a suite run outside the runner hung 14 h.

WHY IT CLEARS THE BAR IN "Writing a good rule":
  · moment      - the Bash call that starts one suite by hand.
  · cost        - 14 h of a lane on a hung suite; the CI governor's CPU slot is bypassed too.
  · nothing else fires - admission is block-only and has no suite rule; no lint can see a runtime call.
  · falsifier   - a direct `tests/x/y.test.sh` run that does NOT get the note, or the runner call itself,
                  `ls tests/x/y.test.sh`, `git add` or a quoted mention that DOES.
Disable: delete this file and its script, then `harbor inject --live --apply`; the control row is context.suite-run-through-runner.
-->
