---
id: post-merge-state
event: PostToolUse
tool: Bash
when: cmd-prefix gh pr merge
once: never
run: merge-note.sh
---
