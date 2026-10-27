---
id: confinement-refused
description: Names the treatment for each kind of sandbox refusal at the moment it happens
event: PostToolUse
tool: Bash
when: always
run: confinement-refused.sh
once: session
---

<!--
harbor#1298 · #555 — the sandbox refused part of a Bash call, and the treatment for each kind of refusal is
already decided (#1297's verdicts), so the note names it at the moment of the refusal rather than leaving the
model to rediscover it, or to retry outside the sandbox.

The real gate is in the run script: the refusal is in the RESULT, which no substring predicate reads.
`once: session`: the treatments do not change between refusals, and a note repeated on each one is noise.
-->
