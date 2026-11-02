---
description: After gh pr merge, names the branches it retired and how far behind origin the checkout is
event: PostToolUse
tool: Bash
when: cmd-prefix gh pr merge
once: never
run: merge-note.sh
---
