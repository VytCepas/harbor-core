---
id: merge-governance
description: Before gh pr merge, hands the moment to the merge backstop (bin/govern-hook.sh)
event: PreToolUse
tool: Bash
when: cmd-prefix gh pr merge
once: never
run: merge-note.sh
---
