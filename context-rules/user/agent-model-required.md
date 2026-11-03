---
order: 97
description: An Agent call with no model inherits the parent model, so one is required
event: PreToolUse
tool: Agent|Task
when: always
once: never
run: agent-model.sh
---

<!--
harbor#843: the harbor#818 tier rule as a check rather than a memory. An Agent call
with no `model` silently inherits the parent's model, and nothing saw it.

`when: always` with the real gate in the run script, because the exemptions are a
lookup, not a match: a fork ignores `model`, and an agent whose definition pins
`model:` is already routed (passing `model` would override the pin). `once: never`
because every unrouted call is its own miss, and a deny that went quiet after the
first one would let the second through.

A DENY, NOT A NOTE. A PreToolUse note arrives beside a call that has already
launched the agent on the wrong tier, so it can only help the next call. The deny
costs one retry, and the reason says exactly which parameter to add.

It checks that a tier was CHOSEN, not that it was the right one. #818's usage
report is what measures the mix.
Disable: delete this file and its script, then `harbor inject --live --apply`.
-->
