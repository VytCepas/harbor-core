---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/eval-tally.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/eval-tally.sh, lines 10-65 (before this edit)

```text
ITS TICKET IS #293 AND ITS SIGNAL IS NOT #293's. That ticket asks for
SatisfactionCapture — how good was this session — and demands a decision before
an implementation: VOID it, build the consumer first, or build the narrow
explicit record only. This is the third shape applied to a DIFFERENT signal: a
comparative verdict between two arms, not a rating of one. #293's warning that
"A and B are different measurements and must not share a field" is why they are
different files as well: nothing here writes a satisfaction row, and #293 stays
open and undecided.

#293's FALSIFIER IS INHERITED VERBATIM: if this surface carries no verdicts
after two weeks of ordinary use, the honest reading is that it should not have
been built, and it should be closed by that evidence rather than by argument.

WHY THIS EXISTS. Measured 2026-08-27: 88% of bin/ line-mass is Harbor governing,
testing or observing Harbor, and 44 test suites answer "does Harbor work". Not
one answers "is the work better". Every such instrument is ENDOGENOUS — its
input is Harbor's own output, so green proves self-consistency and nothing else
(docs/explanation/verification-expanded.md § Endogenous and exogenous instruments).

WHAT MAKES THIS ONE EXOGENOUS, AND IT IS ONE LINE OF CODE: the winner is an
ARGUMENT. Nothing here reads a transcript, scores an output, or asks a model.
The moment this script can derive a winner it stops being able to prove
anything, because it would then be judging by the same faculty that produced
the work. The refusal to infer is the whole instrument.

--varied IS REQUIRED, and the check is not bureaucracy. A tally with no
independent variable records which arm won and can never say why, which is a
ledger that accumulates rows and settles no argument.

NOT HOST-SHARDED, DELIBERATELY. bin/status-usage-aggregate.sh keys its ledger by
$HOST; `hostname` on this box has been measured answering both its real name
and a bare `Mac`, and the flip forked every host-sharded ledger into two halves
that each read as complete. One file, no shard, no fork.

`record` WRITES WITHOUT AN --apply GATE, unlike audit-triage-run.sh and
status-usage-aggregate.sh. Those derive a whole file and can clobber; this appends one
operator-typed line to a machine-local ledger, and CONSTITUTION §№2.11 is the
reason to leave it ungated — a weekly habit behind a confirmation prompt is a
habit that stops. `report` and `open` write nothing.

INTEGERS AND LABELS ONLY — THERE IS NO FREE-TEXT FIELD, AND THAT IS #293's
CONSTRAINT RATHER THAN A STYLE CHOICE. A `--note` was drafted and cut. The
ledger lives under $CFG/MEMORY, and `worklog-push.sh` sets
LOG_DIR="${HARBOR_MEMORY_LOG_DIR:-$CFG/MEMORY}" — so this file sits INSIDE the tree
that gets staged for the private memory-store remote. It is safe today only by
extension: the allowlist is deny-by-default and its globs are
WORK/sessions/*/*.md, KNOWLEDGE/*.md, LEARNING/*.md, WISDOM/*.md, IDEAS.md,
README.md, .gitignore — none of which can match AB/*.jsonl (checked
2026-08-28). Safety by extension is one added glob away from being no safety,
and #293 records a harvester killed for writing prose into a directory that WAS
inside the allowlist. So the field that would carry operator prose does not
exist, and --varied is capped and control-char-refused below to stop it
becoming one by drift.

PRINTS IDS, LABELS AND COUNTS, NEVER CONTENT (CONSTITUTION §3). Nothing here
reads a transcript or emits a path under $HOME.
```

## bin/eval-tally.sh, lines 74-74 (before this edit)

```text
die <what failed> <fix> [exit] — FAIL, its fix, the summary, then the exit code the tool always had (2).
```

## bin/eval-tally.sh, lines 112-116 (before this edit)

```text
--varied IS A LABEL AND THE CAP IS WHAT KEEPS IT ONE. Without a bound it
becomes the prose field this ledger deliberately does not have (harbor#293),
one long verdict at a time, and nobody would notice until the first push glob
widened. Control characters are refused outright: a newline would also split
one JSON record into two lines and silently corrupt every later read.
```

## bin/eval-tally.sh, lines 129-130 (before this edit)

```text
DATE IS UTC AND WHOLE-SECOND. A local-time stamp reorders rows across a DST
boundary, and this file is append-ordered by nothing but its own timestamps.
```

## bin/eval-tally.sh, lines 141-143 (before this edit)

```text
A row recorded with --winner tie is DECIDED, not open. "Open" here means a
task the operator started two arms on and never came back to; it exists so an
abandoned comparison is visible rather than quietly absent from the tally.
```

## bin/eval-tally.sh, lines 173-176 (before this edit)

```text
THE n<5 FLOOR IS A VERIFICATION RULE, NOT A DISPLAY CHOICE. A win rate over
three rows is noise wearing a percentage, and printing one invites exactly the
confident-and-wrong conclusion this whole instrument exists to prevent
(CONSTITUTION §№2.2 — confidence requires source).
```
