---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/eval-replay.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/eval-replay.sh, lines 9-45 (before this edit)

```text
THE DELIVERABLE IS THE DELTA, NOT THE RATE. An absolute "the floor blocks 7.6%
of real traffic" is interesting once; what decides whether a rule change is an
improvement is which records CHANGED verdict. Twelve passes argued that
question. This measures it.

THE SELF-CHECK IS NOT OPTIONAL. Three separate ad-hoc replay harnesses were
written while designing this, and all three silently produced wrong numbers:
`xargs` interprets " and ' unless given -0 (zero records), BSD `xargs -I` reads
lines rather than NUL records and conflicts with -P (one record), and a third
mis-scoped its exit-code test (70% where the truth was 4%). EVERY ONE rendered
as a plausible result — "0 blocked" reads exactly like a clean floor. So this
script asserts its own record count and REFUSES to report on a short run.

WHAT A BLOCK MEANS. These are commands the operator actually ran and, by
default, wanted to run — so every block on real traffic is a FALSE-POSITIVE
CANDIDATE until adjudicated, which is CONSTITUTION rule 2 ("a false positive is
a defect, not safety") made measurable.

LABELS HAVE TWO SCOPES, AND THE RULE SCOPE IS THE ONE THAT PAYS. A first cut
keyed adjudications only on the record id, which meant `key-material-read`
firing six times cost six identical judgements — and a corpus that grows makes
that worse, not better. So:

  rule    <guard:rule>   verdict [note]   — settles EVERY occurrence at once
  record  <payload-hash> verdict [note]   — settles one command; overrides the rule

verdict is `false-positive` (the rule is wrong here) or `correct-block` (the
rule is right and the command was genuinely dangerous). A record label wins
over a rule label, because "this rule is generally wrong BUT this one instance
was a real catch" is exactly the case a single scope cannot express.

The record key is a hash of the PAYLOAD, so it survives rule renames and corpus
rebuilds. Editing a command by one byte makes a new record and a new
adjudication, which is correct: it is a different command.

THE UNREVIEWED COUNT IS ALWAYS REPORTED. A false-positive rate computed over
only the labelled subset is a number that flatters itself.
```

## bin/eval-replay.sh, lines 54-54 (before this edit)

```text
die <what failed> <fix> [exit] — FAIL, its fix, the summary, then the exit code the tool always had.
```

## bin/eval-replay.sh, lines 56-56 (before this edit)

```text
notes: each stdin line as a note, for the tables awk builds.
```

## bin/eval-replay.sh, lines 75-78 (before this edit)

```text
Collected into a file, not a string (pass-2 review): the string was expanded
unquoted on the way to the builder, so a pattern was pathname-expanded
against the caller's cwd and the exclusion silently vanished, and a pattern
containing a space became an "unknown option" error.
```

## bin/eval-replay.sh, lines 100-102 (before this edit)

```text
Kill-safe (harbor#1420): a signal kills every descendant of this shell, found by walking `ps` (no job
control: dash ignores `set -m` process groups), then removes both scratch dirs, so a stopped run leaves no
helm-replay* behind. The old bare INT/TERM trap ran while the builder was still writing.
```

## bin/eval-replay.sh, lines 117-117 (before this edit)

```text
The snapshot's own ps/awk/subshell are listed too; kill -0 keeps only what is still running.
```

## bin/eval-replay.sh, lines 130-132 (before this edit)

```text
A THROWAWAY config dir, never the operator's. The guards resolve their own
config dir from CLAUDE_CONFIG_DIR, and three floor-test invocations were
silently pointing guards at the live ~/.claude until lint F4 caught them.
```

## bin/eval-replay.sh, lines 140-145 (before this edit)

```text
Owner decision 2026-07-28: no durable corpus, ever. Materialising it would
turn 481 mixed transcript files into one greppable store of every command the
operator has typed, and it would outlive the 30-day GC that deletes the
transcripts. Rebuilding costs ~30-60s; that is the price of the artifact not
existing. The baseline that DOES persist carries payload hashes and verdicts
and no command text — the same stance L1 takes, for the same reason.
```

## bin/eval-replay.sh, lines 156-156 (before this edit)

```text
The builder's report, less its own summary: this run ends with the one summary.
```

## bin/eval-replay.sh, lines 162-166 (before this edit)

```text
bin/eval-replay-worker.sh, NOT a heredoc into $TMP. It lived here as a heredoc until
harbor#133, which made it unreachable from the suite — replay-test guarded its
never-drop-a-record assertion on a `$TMP` path that never existed and passed via
the `else` branch every run. The worker is a tracked file so the suite can
invoke the code that actually ships.
```

## bin/eval-replay.sh, lines 170-172 (before this edit)

```text
Bounded job pool. `&` + `wait` rather than xargs -P, because xargs' quoting is
what broke every earlier attempt and a shell-quoted JSON record cannot survive
it. Each worker appends one line; appends of this size are atomic.
```

## bin/eval-replay.sh, lines 177-179 (before this edit)

```text
The record goes on STDIN, never argv (#47 finding 8): a command-line
argument is visible to every user on the box via the process table, which
would expose the whole corpus the ephemeral design exists to avoid writing down.
```

## bin/eval-replay.sh, lines 199-201 (before this edit)

```text
Classify every block against the labels. Comments and blank lines are skipped
so the file can carry the reasoning next to the judgement — an adjudication
without its reason is one nobody can re-check.
```

## bin/eval-replay.sh, lines 233-236 (before this edit)

```text
The NO-VERDICT banner goes BEFORE the early return (pass-2 review): it sat
after `[ "$BLOCKS" -gt 0 ] || return 0`, so a run where EVERY guard failed —
zero blocks, the exact case it was written for — returned silently reporting
"0 blocked", which reads as a clean floor.
```

## bin/eval-replay.sh, lines 238-238 (before this edit)

```text
Neither allows nor blocks: a run with many of them measures nothing.
```

## bin/eval-replay.sh, lines 267-269 (before this edit)

```text
The ADJUDICATION QUEUE, ordered by how much each judgement buys. One line
of labels.tsv against the top rule settles more blocks than a dozen
record-level judgements, which is the whole reason the rule scope exists.
```

## bin/eval-replay.sh, lines 280-284 (before this edit)

```text
A join on id: the record ids are stable across corpus rebuilds because they
hash the payload, so a delta survives adding new traffic.
Temp files, NOT `<(...)`: process substitution is a bashism and the floor's
language rule is pure POSIX sh. It parsed fine under an interactive zsh and
died under /bin/sh, which is the shell every hook actually runs.
```

## bin/eval-replay.sh, lines 289-296 (before this edit)

```text
COVERAGE FIRST (#47 finding 4). `join` emits only matching ids, so a
baseline built from a different corpus produced an EMPTY join — reported as
"newly BLOCKED 0" and exit 0, i.e. a perfectly clean delta from a
comparison that never happened. That is the exact failure this tool exists
to prevent, reproduced inside the tool itself.
DISTINCT ids, not join rows (pass-2 review): a duplicate id makes join emit
a cartesian product, which inflated "overlap" past 100% and could mask a
minority overlap as full coverage.
```

## bin/eval-replay.sh, lines 301-301 (before this edit)

```text
A clean delta from a comparison that never happened is the worst output here.
```

## bin/eval-replay.sh, lines 324-328 (before this edit)

```text
The verdict is deliberately NOT automatic. A newly-blocked count of zero is
not "safe to ship" — it is "no real command in this corpus changed verdict",
which is a narrower claim, and encoding a fix stays human-gated
(CONSTITUTION: the system may propose in batch, never promote its own
observations into a rule).
```
