---
description: Editing CONSTITUTION.md changes no running session until it is deployed
event: PreToolUse
tool: Edit|Write
when: path-contains CONSTITUTION.md
once: session
---

Editing CONSTITUTION.md changes no running session. The copy the harness loads is
the box's own `CLAUDE.md`, a separate file, and nothing deploys to it — lint X2
compares only `bin/*.sh`, guard-selfedit protects only the floor's own surfaces,
and reference-check.sh says in its own header that it does not compare live
against repo. So either say plainly in your answer that the change is undeployed,
or deploy it — and deploy only from merged `main`: DEAD-ENDS.md DE-30 rejected
the automated installer, and a copy from a work-in-progress checkout installs
unreviewed text over the live constitution. The verb is
`sh bin/deploy.sh --only constitution --apply --live`, the one live entry: it
refuses a dirty tree and a non-main branch, snapshots first and verifies after.
