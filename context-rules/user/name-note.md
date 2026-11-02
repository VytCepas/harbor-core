---
order: 98
description: A new file name that breaks the naming standard draws a note before the file exists
event: PreToolUse
tool: Write
when: always
once: match
run: name-note.sh
---

<!--
harbor#978 PR 4 (#949 T5, from #991): a Write that CREATES a file in a repo carrying the naming
standard draws a note when the new name breaks it, before anything references the name. It NEVER
denies: the sentinel is not in the script, so this pack cannot block a call.

The judge is the repo's own bin/lint-name.sh reading its own standards/naming/, never a copy of the
grammar here, and never harbor's registry applied to a repo that has not taken the standard. Only
what the write creates is judged: a finding about a folder that already exists is not the agent's
choice and is dropped. An edit of an existing file names nothing new and draws nothing.

`once: match` re-delivers when the path changes, so a retry of the same bad name is not noise.
Disable: delete this file and its script, then `harbor inject --live --apply`.
-->
