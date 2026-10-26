---
id: variable-is-one-argument
event: PreToolUse
tool: Bash
when: always
run: variable-is-one-argument.sh
once: match
---

<!--
`when: always` with the real gate inside the run script, the same idiom
50-project-pointer.md uses. The trap this pack describes cannot be expressed as a
substring predicate — it needs to know that a bare `$VAR` sits in ARGUMENT
POSITION to a flag-taking tool, which is a parse, not a match. The script emits
nothing when it does not apply, and the engine treats an empty note as silence.

A pack with no `when:` at all is refused outright by both the engine and lint
IJ1 — deliberately, so the most likely typo cannot produce the loudest possible
rule. That refusal is what this file tripped over on its first draft.
-->

