---
order: 96
description: A Write or Edit of the installed copy of a skill, script, hook or hooks block is refused, naming the source path and the install route
event: PreToolUse
tool: Write|Edit
when: always
once: never
run: default-way-deny.sh
---

<!--
harbor#1397, the deny half. default-way-route.md only notes; this pack decides, and only where nothing legitimate
writes: the Write and Edit tools on the config dir's skills, bin and hooks folders and the hooks block of
settings.json. A deploy installs those by copy, never through Write or Edit, so the call is a hand edit of a copy the
next deploy overwrites. A Bash write stays a note (default-way-route), because a command may be an installer.

THE ROWS ARE DATA. default-way-route.tsv beside this file: a row's `deny` cell names the tools it denies, and
default-way-route.sh --deny answers for them. A kind that becomes a deny is a cell, not a code change. The message
names the source path to edit and the install command.

BORN WARN (harbor/D-64). The controls.tsv row context.default-way-deny says warn, so the engine delivers the same text as a
note and denies nothing; promoting it to block is a person's one-cell edit after the replay has run clean.
once: never, because a deny that is said only the first time lets the retry through.

Falsifier: tests/context/injection-rule/default-way-deny.test.sh (every deny row refused when the row is block, the
same content written to the source path passes, a note and no deny when the row is warn).
False positives: the admission corpus replay in that suite, and a local replay of recent sessions' Write and Edit calls
(counts only, never copied).
Off: sh <config>/context-rules/user/default-way-route.sh --off  (one command for both packs; --on and --status undo and
read it; every switch is a line in <config>/cache/context-switch.log). Retire: delete this file, its script and its
controls.tsv row, then `harbor inject --live --apply`.
-->
