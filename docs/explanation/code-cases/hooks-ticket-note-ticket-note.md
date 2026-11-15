---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of hooks/ticket-note/ticket-note.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## hooks/ticket-note/ticket-note.sh, lines 4-25 (before this edit)

```text

WHY IT IS GATED, AND WHY THAT IS NOT OPTIONAL. Stop fires at the end of EVERY
TURN, not at the end of the session. Verified against the binary here, 2.1.245,
rather than taken from a doc: its own summaries are Stop = "Right before Claude
concludes its response" and SessionEnd = "When a session is ending". An
unconditional reminder would therefore print on every turn of every session,
and a guard that fires on ordinary work gets switched off — CONSTITUTION No.2
clause 11. So it speaks only when a ticket IDENTIFIER is present, and only
once per distinct set of identifiers per session.

IT NEVER BLOCKS. The audience is the operator, not the model, so the channel
is systemMessage and the exit status is 0 on every path. A reminder is a
finding, never an order.

IT PERSISTS NO TRANSCRIPT CONTENT. The dedup state is a DIGEST of the id set,
never the ids themselves: DEAD-ENDS DE-16 rejected building a durable corpus
out of transcript content, and a hash is not a corpus. The ids in the message
are recomputed from the transcript each run and stored nowhere.

Falsifier: a session that names a GitHub issue produces no note, or a session
that names none produces one. A ticket tracker other than GitHub is not core's
(harbor#1273): its nudge, if any, belongs to the pack that carries its tool.
```

## hooks/ticket-note/ticket-note.sh, lines 31-48 (before this edit)

```text
── THE OFF SWITCH (harbor#362) ─────────────────────────────────────────────
THIS EXISTS BECAUSE ITS ABSENCE WAS EXPLOITED BY ITS OWN INSTALLER. The operator
turned this hook off on 2026-08-25 the only way available — an `exit 0` edited
into the script body — and `runtime-install` overwrote the file the next day and
wired a second, undisabled copy beside it. Two entries in `.hooks.Stop`, the
reminder back, and no record that anyone had asked it to stop. A switch that
lives in a file the installer owns is not a switch.

TWO SPELLINGS, AND THE DIFFERENCE IS DURABILITY, NOT PREFERENCE:
  TICKET_NOTE=off        for one run, or exported from a settings `env` block.
  $CFG/ticket-note.off   a sentinel file. NO INSTALLER WRITES OR REMOVES IT, so
                         it survives a reinstall — which the env var alone does
                         not, and surviving the reinstall is the whole ticket.
The installer also reads the sentinel and declines to wire the hook at all, so
turning it off does not leave a wired hook exiting silently forever.

SILENT AND ZERO. No message, no stderr, exit 0 — a hook announcing that it is
disabled is the noise the operator just asked to stop.
```

## hooks/ticket-note/ticket-note.sh, lines 54-57 (before this edit)

```text
Absolute paths, and BSD grep specifically. `grep` on this box is ugrep, which
skips binary and gitignored files — a negative from it is not evidence, and
this hook's whole output rests on a match/no-match decision. A hook also
inherits no shell profile, so PATH is not to be trusted for jq either.
```

## hooks/ticket-note/ticket-note.sh, lines 64-77 (before this edit)

```text
THE WINDOW IS 10 MB, AND THE NUMBER IS MEASURED, NOT PICKED. On this box
2026-08-25: 122 transcripts, median 0.6 MB, p95 9.9 MB, max 87 MB. The
expression below (five shapes when measured) costs ~0.1s per MB (1 MB 0.10s, 5 MB 0.49s,
10 MB 0.95s, 20 MB 2.01s), so 10 MB covers the 95th percentile ENTIRELY at
under a second, against a 10s hook timeout.

A full pass was tried first and rejected: 87 MB took 7.3s, and docs/explanation/admission-baseline.md's
finding is that a hook exceeding its timeout is SKIPPED — latency here is not
discomfort, it is the check silently switching itself off. A `grep -F`
prefilter was tried too and bought nothing (7.1s): `86` appears on nearly
every line of a uuid-laden JSONL, so it filters nothing.

Above the window it degrades to a tail AND SAYS SO in the note: a window that
silently covered part of a session reads exactly like one that covered all.
```

## hooks/ticket-note/ticket-note.sh, lines 81-87 (before this edit)

```text
OWNERS, BECAUSE A GITHUB URL ALONE IS NOT THE OPERATOR'S TICKET. Reading
research during a session drags in other people's issues, and the first
version happily reminded about them: a real 87 MB transcript yielded
apache/superset#13003, facebook/react#10191 and ten
more — every single URL match was third-party. Derived 2026-08-25 from the
actual origin remotes of the checkouts on this box, not from recall.
Falsifier: work on a repo under a fourth owner produces no GitHub line.
```

## hooks/ticket-note/ticket-note.sh, lines 110-112 (before this edit)

```text
The loop guard, even though this hook never blocks: the harness sets it while
a Stop continuation is running, and a hook that ignores it is a hook whose
bound belongs to somebody else's cap rather than to its author.
```

## hooks/ticket-note/ticket-note.sh, lines 117-121 (before this edit)

```text
ONE pass over the file. The shapes below are alternated into a
single expression so a big transcript is read once; the classifying greps then
run over the MATCH LIST, which is tens of bytes. -a because a transcript can
carry NUL bytes and a binary-mode skip would answer "no tickets" silently
(both /usr/bin/grep and the ugrep fallback accept -a; verified).
```

## hooks/ticket-note/ticket-note.sh, lines 136-145 (before this edit)

```text
THE REGEX IS THE WHITELIST. Every id that reaches the message is matched out
of [A-Za-z0-9._-], '/' and '#' only, so no transcript text can carry a quote,
a backslash or a newline into the message it is interpolated into.

Two GitHub shapes: a full issue or PR URL, which names its repo, and a bare
`gh issue close 152`, which does not. Both are ticket work; only the first can
be attributed, so the second is rendered as gh#N rather than guessed at.
The owner filter is a SEPARATE, case-insensitive pass over the tiny match
list, deliberately not folded into the pattern above: -i on the whole
expression would also loosen the verb words, and `GH ISSUE CLOSE` is not typed.
```

## hooks/ticket-note/ticket-note.sh, lines 151-153 (before this edit)

```text
Only verbs that ACT on an issue. `gh issue view` and `gh issue list` are how
research reads someone else's tracker; close/reopen/edit/comment/develop are
things you only do to a ticket you own.
```

## hooks/ticket-note/ticket-note.sh, lines 166-167 (before this edit)

```text
Once per distinct id SET per session. A new ticket entering the session
re-arms the note; a further turn on the same tickets does not.
```

## hooks/ticket-note/ticket-note.sh, lines 173-176 (before this edit)

```text
A STATE DIR THIS CANNOT WRITE MUST NOT SILENTLY DISABLE THE HOOK. The first
version exited 0 there, which is the shape the doctrine calls worst: a check
that stops running without saying so. So dedup degrades to off and the note
says it degraded — noisy and fixable beats quiet and gone.
```

## hooks/ticket-note/ticket-note.sh, lines 188-199 (before this edit)

```text
── THE MESSAGE (harbor#362, trimmed 2026-08-30) ────────────────────────────
WAS 10 LINES AND 767 BYTES, AT THE END OF EVERY TURN THAT NAMED A TICKET, and
only the first of those lines was session state. The rest was REFERENCE re-read
aloud each time — the half-hourly format, what -b means, `cu doctor`, the
EPICS-only mirroring rule, FIXED/IN PROGRESS/NOT FIXED, the alert-thread line —
all of it already in the dev-tracking skill and the operator memory that loads
every session. A reminder that restates a rule the reader already has is how a
gate on ordinary work earns itself an off switch (No.2 clause 11), and this one
had just been given one.

WHAT SURVIVES IS WHAT THE READER CANNOT DERIVE AT THAT MOMENT: which ids this
session touched, and the command that closes them.
```

## hooks/ticket-note/ticket-note.sh, lines 213-214 (before this edit)

```text
Temp-then-rename: five sessions run on this box at once, and a half-written
digest read by a concurrent Stop would re-arm the note for no reason.
```
