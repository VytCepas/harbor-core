---
order: 98
description: A create command whose new name breaks the naming standard draws a note with the compliant form
event: PreToolUse
tool: Bash
when: always
once: match
run: name-note-create.sh
---

<!--
harbor#978 item 9 (#949 T5, from #994): the Bash half of the write-time name note. A Bash command that
CREATES a named thing draws a note when the new name breaks the standard, before the thing exists.
It NEVER denies: the sentinel is not in the script, so this pack cannot block a call.

CORE SHIPS THE MECHANISM, NEVER A COMMAND. Which commands create, and the surface each name is judged
as, are rows in <config dir>/name-create.d/*.tsv, written by the workload's pack (#950, #1273):
  <ERE matched against the command, ending where the name begins> TAB <surface> TAB <note>
The first word after the match that is not a flag is the name, or the whole of a quoted one (harbor#978). A name
built from $VARS or `$(..)` is not judged. Core's own rows (secret put, harbor access add, gcloud iam service-accounts
create) are contracts/name-create.tsv, installed as name-create.d/harbor.tsv; `harbor check --live` is red
(check context.name-create) when name-create.d holds no row, because then this rule is off. The judge is the repo's own bin/lint-name.sh --check <surface>, else the one beside this
config; none, no rows, or a lint error prints nothing and exits 0.

Disable: delete this file and its script, then run the inject installer for the live config.
-->
