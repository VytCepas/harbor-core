---
order: 45
description: Quotes the access card for a system when a command fails with an auth error
event: PostToolUse
tool: Bash
when: always
once: match
run: access-route.sh
---
