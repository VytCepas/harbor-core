---
id: post-compaction-carry
description: After a compaction, summary counts and paths are copies to re-derive, plus the traps this session sprang
event: SessionStart
when: source-is compact
once: never
run: post-compaction-carry.sh
---
