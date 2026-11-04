---
description: Denies an AskUserQuestion whose options lack pros, cons, consequence, or a first recommended option with its reason and flip condition
event: PreToolUse
tool: AskUserQuestion
when: always
once: never
run: decision-question.sh
---

<!--
The decision standard (docs/explanation/grilling.md, "The anatomy of an option") as a check at the
moment of asking. The operator's call on 2026-10-29: every option carries pros, cons and the
consequence, and the recommendation comes first.

A DENY, NOT A NOTE. A PreToolUse note reaches the model beside the tool result, and the result of
this tool is the operator's answer: the note would land after they chose from a thin question. The
deny costs one re-ask, and its reason names each option and the label it lacks.

`when: always` with the gate in the script, because "carries the parts" is a test of the questions
array, not a predicate. `once: never`, because every question is its own. A question with no options
is out of scope.

It checks that the parts are PRESENT, not that they are honest. A strawman option with every label
passes; the standard in grilling.md is what forbids it, and nothing mechanical can.
Disable: delete this file and decision-question.sh, then `harbor inject --live --apply`.
-->
