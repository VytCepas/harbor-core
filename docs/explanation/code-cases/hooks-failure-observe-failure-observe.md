---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of hooks/failure-observe/failure-observe.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## hooks/failure-observe/failure-observe.sh, lines 4-74 (before this edit)

```text

WHAT WAS MISSING, AND IT IS NOT WHAT IT LOOKS LIKE. Harbor already registers,
analyses and notifies end to end: admission-observe.sh writes guard-decisions.jsonl,
audit-triage.sh judges it, audit-triage-run.sh runs that daily, session-verdicts.sh
speaks the verdict. All of it works. It watches GUARD DECISIONS — what the floor
decided ABOUT a call — and records nothing about what the call then DID. So a
Read on a path that resolves to nothing, a Bash command exiting non-zero, a
skill invoked by a name that no longer exists: none of them leave a trace
anywhere. That is precisely harbor#462's class. Ten dead constitution pointers
were followed by sessions for 34 days; every follow was a tool call that found
nothing, and not one of them was written down.

`PostToolUseFailure` was already wired, under matcher `.*`, to inject-hook.sh
ALONE — which emits a note into the session and a dedup marker, both of which
die with the session. The event carries what a ledger needs and nobody was
keeping it.

REGISTER AND ANALYSE. NEVER REPAIR. CONSTITUTION "Encoding a fix is a
human-gated act", and this repo carries the receipt: pass 9's fixes were
applied confidently and pass 10 found ~24 defects caused by them, with a green
suite throughout. A ledger that quietly repaired the harbor#462 citations would
have rewritten the constitution on its own authority AND GOTTEN IT WRONG — the
correct repair was to declare a root, not to delete ten pointers.

── FIVE PROPERTIES INHERITED FROM THE GUARD LEDGER, NOT REINVENTED ─────────

1. THIS SCRIPT CREATES NOTHING. admission-observe.sh is the only component allowed
   to create, at SessionStart, where a fork costs nothing and no verdict is
   pending. It holds the host directory at 0500 for the rest of the session, so
   an append into an existing 0600 file works and a create does not. A recorder
   that could create could be made to create somewhere else.

2. THE SINK FOLLOWS THE WRITER ($0), NOT THE CALLER'S ENVIRONMENT. Measured
   2026-08-25 on the guard ledger: 1,723 records in one day written by suite
   copies into the operator's real ledger, because the sink was resolved from
   $CLAUDE_CONFIG_DIR. Per-suite isolation cannot fix that — a caller running
   `env -i` strips the variable by construction — so the sink is derived from
   this script's own path. A checkout has no MEMORY/OBSERVABILITY tree, so a
   copy run from one is BLIND rather than misfiled.

3. THE RECURRENCE KEY IS THE TOOL AND ITS INPUT, NEVER THE WHOLE PAYLOAD. The
   payload carries session_id and cwd, so hashing it would give the same failing
   call a different digest in every session — and recurrence counting, the one
   thing the digest exists for, would be dead on arrival. library-admission.sh already
   learned this; the comment above floor_obs_digest says so in those words.

4. SALTED, NOT TRUNCATED. Same argument as the guard ledger's: an unsalted
   truncated hash of a low-entropy input is a confirmation oracle, not a
   redaction. The salt is the same per-install 128 bits, deliberately never
   rotated — rotating it would silently reset every recurrence count.

5. EVERY PATH EXITS 0. A hook that fails a session is worse than a ledger with
   a hole in it, and this one fires on the failure path, where something has
   already gone wrong for the operator.

── WHAT THIS RECORDS THAT THE GUARD LEDGER DELIBERATELY DOES NOT ───────────

A READABLE SUBJECT (`k`), and it is the one place this design is wider than the
ledger it copies. The guard ledger stores a digest and no plaintext at all,
correctly: floor_block's own stderr tells the operator which commands were
blocked, so known plaintext is guaranteed and a command is far more sensitive
than a filename. Here the question the ticket asks is "which tool fails, ON WHAT
INPUT", and a finding that cannot name the input cannot be acted on — a digest
would answer "this recurred" and never "this path is dead", which is the whole
of harbor#462.

So `k` is bounded on purpose and is NOT the input: a file path with $HOME
replaced by `~`, or the BARE COMMAND NAME of a Bash call with every argument
discarded, capped at 120 characters and charset-gated. Never content, never
arguments, never a URL's query. The full input is still only ever present as
the salted digest.
```

## hooks/failure-observe/failure-observe.sh, lines 77-77 (before this edit)

```text
── the payload, bounded ────────────────────────────────────────────────────
```

## hooks/failure-observe/failure-observe.sh, lines 81-82 (before this edit)

```text
jq absent means BLIND, never wrong (B9's lesson, one layer in): a recorder that
cannot parse must write nothing rather than write something unparseable.
```

## hooks/failure-observe/failure-observe.sh, lines 85-85 (before this edit)

```text
── the config root, derived from THIS FILE (property 2) ────────────────────
```

## hooks/failure-observe/failure-observe.sh, lines 90-92 (before this edit)

```text
library-admission.sh is sourced for floor_obs_digest and the tool enum — ONE digest
implementation and ONE tool vocabulary on this box, not a second spelling that
drifts. Absent library means exit 0: nothing here has value without it.
```

## hooks/failure-observe/failure-observe.sh, lines 96-98 (before this edit)

```text
── the host partition, read exactly as the hot path reads it ───────────────
Type-checked before `read`, because a FIFO at this path blocks the builtin the
same way `>>` blocks, and 2>/dev/null cannot catch a block.
```

## hooks/failure-observe/failure-observe.sh, lines 107-109 (before this edit)

```text
THE TWO GATES, IN THIS ORDER. The directory gate is what keeps the file gate's
answer true one instruction later: a writable host dir means somebody other
than admission-observe.sh can swap the sink between the check and the append.
```

## hooks/failure-observe/failure-observe.sh, lines 115-117 (before this edit)

```text
── the fields ──────────────────────────────────────────────────────────────
One jq, tab-separated. @tsv escapes an embedded tab or newline rather than
forging a field boundary, which a hostile tool_input would otherwise do.
```

## hooks/failure-observe/failure-observe.sh, lines 132-143 (before this edit)

```text
SPLIT BY PARAMETER EXPANSION, NEVER BY `IFS=<tab> read`. Tab is IFS WHITESPACE
in POSIX sh, so a run of tabs collapses to one delimiter and an EMPTY field
shifts every field after it one place left. Measured by this file's own suite:
a failure whose `error` is the empty string moved the subject into the session
slot and left the digest subject empty, floor_obs_digest returned "-", and the
record was dropped — so every tool that fails without an error MESSAGE would
have been silently absent from the ledger. `read -r a b c d` on `A\tB\t\tD`
assigns c=D, verified directly. This split preserves empties.
Written out rather than wrapped in a helper, because a helper called as
`F="$(_cut)"` runs in a SUBSHELL and its update to the remainder never reaches
this scope — so every field came back as the first one. That was the first fix
for the bug above and it was worse than the bug.
```

## hooks/failure-observe/failure-observe.sh, lines 152-155 (before this edit)

```text
@tsv escapes a literal tab inside a field as `\t`, so a tab surviving in the
LAST field means the row had more columns than this split expects — a shape
nothing here understands. Dropped, rather than filed under fields that have
quietly shifted.
```

## hooks/failure-observe/failure-observe.sh, lines 158-161 (before this edit)

```text
── an INTERRUPT IS NOT A FAILURE, and this is the first thing checked ──────
`is_interrupt` is the operator pressing Ctrl+C. Counting it would make the
busiest signal in the ledger a record of the operator changing their mind, and
a ledger whose loudest finding is noise is one that gets muted (No.2.11).
```

## hooks/failure-observe/failure-observe.sh, lines 164-178 (before this edit)

```text
── the tool: gated and capped, NOT matched against an enum ────────────────
tool_name is attacker-shaped for exactly one family. `mcp__server__tool` takes
its middle from a repo-supplied .mcp.json, so only its charset-gated, capped server
segment survives (below); the tool part never does.

EVERY OTHER TOOL NAME COMES FROM THE HARNESS, and that is why this does NOT
reuse FLOOR_OBS_TOOLS. That enum bounds cardinality against names an attacker
could choose, and once mcp__* is mapped there is no such name left here. What a
hand-listed enum WOULD do is relabel every tool the list has not caught up with
as `other` — and the first casualty is measured, not hypothetical: `Read` is
absent from FLOOR_OBS_TOOLS, correctly, because no guard gates a read. A read
that finds nothing is the whole of harbor#462, so a ledger built on that enum
would file the single most important failure class on this box under `other`.
A stale enum is blindness aimed precisely at the newest tool, which is the one
most likely to be failing.
```

## hooks/failure-observe/failure-observe.sh, lines 180-181 (before this edit)

```text
The MCP SERVER segment alone is kept (`mcp__<server>`): enough to say WHICH server fails, never the tool or any argument.
Charset-gated and capped like every other tool name; a server that fails either gate stays the bare constant `mcp`.
```

## hooks/failure-observe/failure-observe.sh, lines 191-199 (before this edit)

```text
── the error CLASS, never the error text ──────────────────────────────────
An enum, for the same reason the guard ledger's verdicts are one: free text
from a failing tool is unbounded, frequently carries the very path or payload
that failed, and cannot be grouped. Six classes, ordered most-specific first.

`blocked` exists so the two ledgers do not double-count. A floor block reaches
this event as a failure AND is already one record in guard-decisions.jsonl;
without a class of its own it would inflate every count here with decisions
that are, by design, working exactly as intended.
```

## hooks/failure-observe/failure-observe.sh, lines 209-210 (before this edit)

```text
browser-agent's own refusals that hand the next step to the operator (signed out, a hidden window,
a destructive click, an off-list host): its rules working, not the tool failing. Its server only.
```

## hooks/failure-observe/failure-observe.sh, lines 213-213 (before this edit)

```text
── the readable subject, bounded and redacted (see the header) ────────────
```

## hooks/failure-observe/failure-observe.sh, lines 216-217 (before this edit)

```text
A cap by parameter expansion rather than `cut`: no second PATH-resolved binary,
and 120 characters is past every real path in this estate.
```

## hooks/failure-observe/failure-observe.sh, lines 219-222 (before this edit)

```text
The charset gate is the injection boundary. jq escapes correctly on emission
below, so this is defence in depth rather than the only line — but a subject
that reaches the ledger carrying a control character is one that breaks the
reader, and a broken reader reports clean.
```

## hooks/failure-observe/failure-observe.sh, lines 225-228 (before this edit)

```text
── the digests ─────────────────────────────────────────────────────────────
Recurrence key: tool + NUL + the input's canonical JSON (property 3). The
session digest answers "across how many sessions" without the ledger holding a
session id, and is salted by the same secret for the same reason.
```

## hooks/failure-observe/failure-observe.sh, lines 240-242 (before this edit)

```text
A record with no recurrence key cannot answer the only question this ledger
exists for, and a row of dashes is worse than no row: it inflates every count
while carrying nothing. Dropped, deliberately.
```

## hooks/failure-observe/failure-observe.sh, lines 248-250 (before this edit)

```text
── the clock ───────────────────────────────────────────────────────────────
A malformed clock ABORTS the record rather than writing an unparseable field:
one dropped record beats a ledger jq refuses to read.
```

## hooks/failure-observe/failure-observe.sh, lines 257-261 (before this edit)

```text
── the record ──────────────────────────────────────────────────────────────
Built by jq and not printf. Every other field above is enum- or charset-gated,
but `k` is the one that carries text derived from a tool input, and a `"` in a
printf template is a forged record — after which the whole file stops parsing
and every rule downstream reports clean.
```
