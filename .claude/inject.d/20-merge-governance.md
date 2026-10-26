---
id: merge-governance
event: PreToolUse
tool: Bash
when: cmd-prefix gh pr merge
once: never
run: merge-note.sh
---
