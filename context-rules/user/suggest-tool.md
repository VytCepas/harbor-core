---
order: 94
description: A job Harbor has a better way for draws one plain line to the person and a matching note to the agent, at most once a session
event: PreToolUse
when: always
once: session
mode: notify
summary: Harbor has a better way for this job
run: suggest-tool.sh
spoke: suggest-tool-spoke.sh
---

<!--
harbor#1485: an agent can do by hand, for a whole session, a job Harbor has a tool for, and the person never learns the tool exists.
Context rules speak to the agent. This one also speaks to the person, once a session, in words from the table.

THE JOBS ARE DATA. suggest-tool.tsv beside this file holds one row per job. A new job is a row, not a code change. It ships with a
header and no rows until the operator names the jobs; bin/lint-suggest-table.sh holds every row (lint.suggest-table).

COLUMNS  id, kind (verb tool skill mod intro), tools, word, recogniser, quiet, line, switch_to, safe, install, requires, source.
`word` is a literal the raw Bash command must hold before the floor's parser loads. `recogniser` and `quiet` are EREs on the subject
built by suggest-subject.sh. For a mod row `switch_to` is the mod's name, which the rule checks is not already loaded.

SAFE means the same outcome as the hand way, nothing installed, no outward effect. Trust comes from the file a row was read from: a
row outside this pack's own table is treated as safe=no whatever its cells say. The switch sentence is composed from `switch_to`.
Company rows are not read yet: their delivery, and the check that holds them before they reach a person, land with harbor#1278.

Stays silent for a subagent, whose person cannot answer. The hand-rolled CI wait stays with ci-wait-on-the-bus: when a pack named in
SUGGEST_OVERLAP speaks on a call, this one stands down. The surface check is a stub until the Desktop probe.

Falsifier: tests/context/injection-rule/suggest-tool.test.sh, tests/status/suggest/e2e.test.sh. Replay before a row ships: sh bin/eval-suggest-replay.sh --days 14.
Go live: docs/how-to/suggest-go-live.md.
Off, for a person: the status panel, or sh <config>/bin/status-suggest.sh off --origin panel.
Retire: delete suggest-tool.* suggest-tool-spoke.sh suggest-start.* suggest-subject.sh, then `harbor inject --live --apply`.
-->
