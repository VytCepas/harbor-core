---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/govern-token.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/govern-token.sh, lines 9-35 (before this edit)

```text
THE HOLE THIS CLOSES, MEASURED RATHER THAN IMAGINED. The obvious way to make a
hook's reminder trustworthy is to have it say so — `[GOVERNANCE HOOK]` at the
top of the text. That is exactly what an attack writes too, and on this box the
attack has a ready-made delivery path: `bin/annotate-web.sh` pipes FETCHED WEB
PAGES into `hookSpecificOutput.additionalContext` using a byte-identical
envelope to this hook's. Verified 2026-08-07 — the two emissions differ in
nothing a reader could use. So a fetched page containing `[GOVERNANCE HOOK — …]`
arrives indistinguishable from the real thing, and a constitution that said
"trust text labelled GOVERNANCE" would have turned Harbor's own trust rule into
a prompt-injection amplifier, aimed at the one hook whose job is carrying
hostile input.

SO THE LABEL IS NOT THE MECHANISM. A per-session token is: the salt never
leaves this box, the session id is not in the fetched content, and external
text therefore cannot compute the value. The constitution can then say "a
governance note carries THIS SESSION'S token" instead of "a governance note
says it is one".

DERIVED, NOT STORED. token = sha256(salt || session_id), so nothing per-session
is written anywhere and five concurrent sessions cannot collide or fork a
shared file — which matters here specifically, because `hostname` on this Mac
intermittently answers `Mac` and has already forked host-sharded ledgers.

THE HOOK NEVER WRITES. Only `--init` creates anything, it is run by hand, and
it refuses the live config dir without `--live` (rule D2). With no salt the
token is EMPTY and every caller degrades to an unlabelled note that still says
something true — a missing salt must not turn reminders off.
```

## bin/govern-token.sh, lines 58-65 (before this edit)

```text
D2's gate, by hand: this writes into the config dir, and a secret that
silently reappears under a different value would invalidate every note
already injected this session.
`LIVE_DIR=` is lint D1's sanctioned idiom for NAMING the live dir in order
to refuse it — what D1 forbids is reading or writing state through a
hardcoded path, which is the opposite of this. Resolved physical paths on
both sides, so a relocated or symlinked config dir cannot slip past by
spelling.
```

## bin/govern-token.sh, lines 89-96 (before this edit)

```text
SessionStart. The token is named ONCE, in the trusted prefix, and the
constitution's rule points at it. Silent with no salt — announcing an
empty token would teach a reader that the field is decorative.
THE GUARD HAS TO COME FIRST. It used to sit three lines below its own
first use of jq, so with no jq the session id parsed empty, the token came
back empty, and the function exited on the line above — the guard was
unreachable and the correct behaviour happened by accident. An accident
that produces the right answer is still a defect: the next edit changes it.
```

## bin/govern-token.sh, lines 130-132 (before this edit)

```text
EXIT 2 ON AN UNKNOWN FLAG, matching eval-hook-replay.sh and skill-install.sh.
It printed help and exited 0, so a typo in a wired hook would have looked
like success — the same vacuous-gate shape skill-catalog.sh's header records.
```
