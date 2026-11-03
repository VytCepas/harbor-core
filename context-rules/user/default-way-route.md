---
order: 97
description: A skill, script, hook, rule or scheduled job built into the box the default way draws a note naming harbor's home for it and its install route
event: PreToolUse
tool: Write|Edit|Bash
when: always
once: match
run: default-way-route.sh
---

<!--
harbor#1397: a stranger on harbor-core, or a fresh session on this box, builds the way Claude Code allows by
default: a skill straight into ~/.claude/skills, a script into ~/.claude/bin or hooks/, a hook into settings.json,
a rule into CLAUDE.md or a feedback memory, a job into LaunchAgents, a systemd user unit or crontab. Each works
until the next deploy overwrites it or leaves it unowned, and the only feedback was a later drift report.

THE KINDS ARE DATA. default-way-route.tsv beside this file holds one row per kind: how a creation is recognised,
the harbor home, the install route and the reason. A new kind is a row, not a code change. A Bash call is judged
by what it WRITES (redirect, tee, mkdir, touch, sed -i, the last operand of cp/mv/ln/rsync/install), so a read of
an installed copy draws nothing, and a row's `quiet` pattern stands down for harbor's own route (the launchd
renderer, the skill installer, deploy-hooks.sh).

ADVISORY, NEVER A DENY: the sentinel is not in the script, so this pack cannot block a call, and the floor's
verdict on the same call is unchanged. The one deny on these rows is default-way-deny.md, a second pack (a row's
`deny` cell names the Write and Edit of an installed copy), born warn; this pack stays silent on those calls so
nothing is said twice. A write into a checkout, a repo's own .claude/, or a test fixture under $TMPDIR is never
under the config dir and never matches. `once: match` keys on the path or the command, so one file draws one
note per session.

INFERRED KINDS (a `path:` recogniser, a note wherever the file is): a SKILL.md outside a skills source, a skill
whose whole body is one command (a bin/ tool), a memory note phrased as a rule. Every surface in
standards/naming/surfaces.tsv has a row in some surface cell, or a row with tools - saying why no session builds
it by default (lint.route-covers-surfaces).

Falsifier: tests/context/injection-rule/default-way-route.test.sh (every row fires on its default path, stays
silent on the harbor path and on ordinary work, and goes silent when its recogniser is broken).
Off, for both packs, one command, logged to <config>/cache/context-switch.log:
  sh <config>/context-rules/user/default-way-route.sh --off     (--on undoes it, --status reads it)
Retire: delete this file, its script, default-way-route.tsv and default-way-deny.*, then `harbor inject --live --apply`.
-->
