---
order: 96
description: Names what an Agent call prompt lacks: an outcome, constraints, an output location
event: PreToolUse
tool: Agent|Task
when: always
once: never
run: agent-brief.sh
---

<!--
harbor#953 (#949 harbor/D-44): an inform pack for the brief an Agent call carries. It names what the
`prompt` lacks (a done/outcome statement, constraints, an output location) and whether `model` is
unset, and it NEVER denies: the sentinel is not in the script, so this pack cannot block a call.

`when: always` with the gate in the script, as 97-agent-model-required: what counts as present is
a text test, not a predicate. `once: never`, because every brief is its own and the note names what THIS brief lacks; the script spends the
explanation once per context (key `ctx:agent-brief` in the engine ledger, purged on a compaction or a clear) and later
thin briefs draw one line, "does not state: X" (P10: 152 of 267 notes repeated the explanation). A complete brief draws
nothing and spends nothing. A fork inherits the whole conversation and is
briefed by it, so it is skipped, as it is by 97.

The `model` half reuses agent-model.sh, so the exemptions (a fork, an agent whose definition pins
`model:`) live in one place. 97 DENIES that same case and a deny drops this call's notes, so for an
unset model this pack's sentence is seen only where 97 is not installed; the brief half is this
pack's own.

The test is a keyword heuristic on purpose: it can miss a brief that is thin in substance but uses
the words. It is meant to catch the brief that does not even try. A pass proves nothing about
quality (#818's usage report and review measure that).
Disable: delete this file and its script, then `harbor inject --live --apply`.
-->
