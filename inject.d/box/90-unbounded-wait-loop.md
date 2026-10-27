---
id: unbounded-wait-loop
description: A wait loop with no deadline is replaced by the wait-for helper
event: PreToolUse
tool: Bash
when: always
run: unbounded-wait-loop.sh
once: match
---

<!--
`when: always` with the real gate inside the run script, the same idiom
50-project-pointer.md and 60-variable-is-one-argument.md use. This cannot be a
substring predicate: the rule needs to know that a loop keyword is UNBOUNDED
(`while`/`until`, but not `for`, and not `while read`) and that no deadline is
computed anywhere in the command. That is a parse, not a match.

`once: match` because the subject of a PreToolUse Bash pack is the raw command
(CONTRACTS/inject.md, harbor#180) — two different wait loops in one session are
two different mistakes and both deserve the note.

OWNER. The fact lives in the operator's auto-memory as
`never-poll-harness-tracked-work`, and the remedy ships as `~/.local/bin/wait-for`
whose header records the same incident. Same provenance shape as the $VAR pack,
which cites `zsh does not word-split`.

WHY IT CLEARS THE BAR IN "Writing a good rule":
  · moment      — the Bash call that arms the loop, not a general principle.
  · cost        — measured 2026-08-24: 39 minutes of a session spent in a loop
                  whose predicate could never match, killed by hand.
  · nothing else fires — guard-bash.sh is block-only (exit 2, no advisory
                  channel) and carries no loop rule; no lint rule and no CI job
                  can see a runtime shell loop.
  · falsifier   — a session that writes `until … sleep` with no deadline and
                  does NOT get the note, or a bounded loop (`for`, `while read`,
                  or one computing a `date +%s` deadline) that DOES.
-->
