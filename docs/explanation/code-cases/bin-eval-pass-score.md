---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/eval-pass-score.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/eval-pass-score.sh, lines 5-14 (before this edit)

```text
Why this exists. The stated criterion for installing the floor live is "a pass
must find fewer defects than it introduces", and it has been called failed
three times by eye. By eye is not good enough: with four data points, a metric
that moves 17 -> 9 looks like progress and may be indistinguishable from the
scatter of the series itself. Upstream's Loop skill gates exactly this — it
computes |delta| / MAD(series) per iteration and refuses to bank a delta below
the noise floor, logging it `marginal` instead. Same problem, same gate.

MAD (median absolute deviation) rather than stddev: n=4, and one pass-10-shaped
outlier would swallow a stddev whole.
```

## bin/eval-pass-score.sh, lines 17-23 (before this edit)

```text
--help BEFORE ANY WORK (S4, harbor#140). Placed immediately after strict mode
so it is the first executable line: a --help that reaches an argument parser is
a --help that a script with no parser ignores, and this file had none. Measured
2026-08-20: a sweep of `bin/*.sh --help` ran past five minutes because at least
one script treated the flag as a request to do work, and five of the scripts
with no --help at all are mutators. The text is the header, read out of THIS
file at runtime, so a help message cannot drift from what the script says it is.
```

## bin/eval-pass-score.sh, lines 34-34 (before this edit)

```text
die <what failed> <fix> <exit> — FAIL, its fix, the summary, the exit code the tool always had.
```

## bin/eval-pass-score.sh, lines 42-47 (before this edit)

```text
The header row names the passes; each metric row carries one integer per pass.
Numbers are read with a leading ~ tolerated ("~24" — pass 10 was an estimate,
and recording it as exact would be a worse lie than recording it as fuzzy).
docs/explanation/admission-baseline.md carries one table per pass-review, each a superset of the last, so
the LAST match is the current one. `grep -m1` here read the pass-11 table and
silently reported a three-point series as if it were the whole record.
```

## bin/eval-pass-score.sh, lines 76-77 (before this edit)

```text
MAD == 0 means the series has not moved off its median often enough to
have a scale. Any movement is then unmeasurable, not automatically real.
```

## bin/eval-pass-score.sh, lines 101-101 (before this edit)

```text
POSIX sh has no float compare; awk decides.
```

## bin/eval-pass-score.sh, lines 114-124 (before this edit)

```text
harbor#44's Done-when says "eval-pass-score.sh reads real block counts instead of
pass-report estimates". Taken literally that is a CATEGORY ERROR and
implementing it literally would make this script lie: the table above counts
DEFECTS FOUND PER ADVERSARIAL PASS, while the replay counts RULE HITS ON REAL
TRAFFIC. Substituting one for the other would silently change what the MAD
gate is gating. So the replay is reported ALONGSIDE, with the relationship
stated, and the pass series is left alone.

What the replay genuinely adds is the denominator the table never had:
CONSTITUTION rule 2 says "a false positive is a defect, not safety", and until
harbor#44 there was no data source that could ever falsify it.
```

## bin/eval-pass-score.sh, lines 140-165 (before this edit)

```text
THE GATE WAS ONE-SIDED (#47 finding 20). It fired only when `criticals` was
BOTH above the noise floor AND rising on the last step — so the worst possible
series, a run of clean passes followed by a jump, exited 0: with a low MAD the
ratio is huge, but a single quiet pass before the jump made `last > prev` the
only test that mattered, and any series ending flat sailed through. Two extra
tests, both cheap:
  • the LEVEL, not just the delta — criticals above zero at the end is not a
    clean floor however the series got there;
  • the TREND across the whole series, so one quiet pass cannot launder a rise.
`|| true` because `grep` is LAST in this pipeline, so the assignment inherits
its status — and under `set -eu` a docs/explanation/admission-baseline.md whose newest criticals row carries
no numeric cell killed the script right here: the table printed, then nothing,
rc=1, no verdict, no message.

TWO CORRECTIONS TO WHAT THIS COMMENT USED TO CLAIM (pass-3 review), both of
which were wrong in the direction that flatters the fix:
  • "or one whose cells are `n/a`, which stats() itself emits" — stats() writes
    n/a to its OWN stdout at line 52; it never writes docs/explanation/admission-baseline.md, and nothing in
    this repo does. A table with fewer than 3 passes leaves crit_all populated
    and the gate firing. That path does not exist.
  • "the guards below were unreachable on exactly the path they were written
    for" — they are reachable now and still cannot fire, because every one is
    gated on `[ -n "${crit_last:-}" ]`, which is empty precisely when this path
    is taken. Completing the run is not the same as running the gate.
So the honest state is the third branch below: an empty series is UNMEASURED,
and a gate that did not run must not print a verdict that reads like it did.
```

## bin/eval-pass-score.sh, lines 168-168 (before this edit)

```text
This is not "no worsening".
```

## bin/eval-pass-score.sh, lines 193-194 (before this edit)

```text
A criterion of "fewer defects than it introduces" is not met by a series that ENDS above zero, whichever
direction it moved.
```
