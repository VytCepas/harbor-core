---
id: repo-tier-not-loaded
description: Reports the repo rules a session started elsewhere is not loading
event: PreToolUse
when: always
once: session
run: repo-tier.sh
---
