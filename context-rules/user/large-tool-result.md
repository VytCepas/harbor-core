---
order: 80
description: A large tool result is read in slices, never whole
event: PostToolUse
tool: Read|Bash|Grep|Glob|WebFetch|WebSearch|mcp__.*
when: always
run: large-tool-result.sh
once: session
---

<!--
harbor#184 · lever 2 — "read slices, not whole files". `when: always` with the
real gate inside the run script, the idiom project-pointer.md and
variable-is-one-argument.md already use: "this result is large" is a LENGTH,
and no substring predicate can express one.

THE `tool:` MATCHER IS WIDE, AND EXPLICIT, AND BOTH HALVES MATTER. The ticket
names `Read`, and Read is not the biggest offender — measured over the 30 newest
transcripts on 2026-08-22, 6,249 results and 88 MB,
`mcp__claude-in-chrome__browser_batch` alone is 43.2 MB over 498 calls and
`mcp__claude-in-chrome__computer` a further 15.1 MB. Scoping to Read would leave
58 of those 88 MB unmentioned.

The first draft declared NO `tool:` at all, meaning "any tool", and that was
worse than wrong — it was silently narrower. `bin/inject-install.sh` wired the
engine's PostToolUse hook with a hardcoded `Read|Bash|Grep|WebFetch`, so the
harness never invoked it for a single browser call and this pack could not fire
on the traffic it exists for. Every arm in the suite passed, because they call
inject-hook.sh directly and never cross that outer matcher (PR #269 review; the
same §2.6 shape as harbor#254). The installer now DERIVES its matcher from these
declarations, so the list here is the one that governs — and declaring the tools
keeps the engine off the calls nobody here cares about, which matters while
harbor#264 is open on per-call fork cost.

`once: session`, and this is the §2.11 trade stated rather than hidden. 665 of
6,249 results cross the threshold, so `once: match` would fire roughly twenty
times in a working session and be switched off within a day. Firing once puts the
lesson in context at the moment of action, which is the mechanism E6 measured
(0/4 as prose, 4/4 injected at the tool call); the cost is that a second, worse
offender later in the same session is not named again.

WHY POST AND NOT PRE. The size is not knowable before the call — a `Read` with no
`limit` may return 200 bytes or 660 KB. PostToolUse cannot block, which is
correct here: the tokens are already spent, and the only thing left worth doing is
changing the NEXT call. That also makes this an inform channel by construction,
which is the arm E6 found beat vetoing.
-->
