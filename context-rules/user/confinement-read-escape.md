---
order: 71
description: A read-only Bash call that asks to leave the sandbox is told it runs confined
event: PreToolUse
tool: Bash
when: always
run: confinement-read-escape.sh
once: session
---

<!--
harbor#1441 · #555 decision 10 (a) — the `readonly` escape class has no confinement row to add: reads already run
confined, so the treatment is a note on the call that asks for the flag. `when: always` with the gate in the run script,
the same idiom confinement-refused.md uses: the flag is in tool_input, which no substring predicate reads.

Falsifier (the ticket's): if the read-only escapes are mostly retries after a sandbox refusal earlier in the same
compound, the class's cause is that earlier command and this note is noise. The measured week shows it: the class
share falling after the note, or not.
-->
