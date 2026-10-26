---
id: tool-failure-is-not-a-result
description: A failed tool call did not run, so its absence is not a result
event: PostToolUseFailure
when: always
once: session
run: tool-failure.sh
---
