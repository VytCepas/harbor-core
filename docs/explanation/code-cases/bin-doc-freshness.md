---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/doc-freshness.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/doc-freshness.sh, lines 5-26 (before this edit)

```text
Upstream's Interview reads the constitutional files, scores each one's age
against a threshold, surfaces the stalest, and asks "still right?" instead of
"what's your mission?". Harbor took the *method*; the plumbing did not port —
TelosFreshness.ts/InterviewScan.ts are Bun, the seven files are upstream's, and
the cache is Pulse's. Here the age source is git, which already knows.

STALENESS IS A PRIORITY SIGNAL, NOT A FAILURE FLAG. A 200-day-old contract may
be exactly right; the question this produces is "still right?", and that is
why this script never exits non-zero for age alone.

TWO CORPORA, TWO AGE SOURCES (C1a, harbor#43). The repo's documents are aged
from git, which already knows. The operator's working context —
`MEMORY/TELOS/*.md` and `MEMORY/IDENTITY.md` — CANNOT be, because those files
must never reach the Log (harbor#43's privacy decision) and an untracked file
has no commit date. So that corpus is aged from mtime, and `GOALS.md` carries a
per-entry reviewed date because mtime is a whole-file signal and a goal list is
not one thing: editing G4 must not make G1 look reviewed.

THE REPORT NEVER PRINTS THE CONTENT OF THAT CORPUS. Ids and ages only. A
freshness table gets pasted into a chat, screenshotted, and read over someone's
shoulder; goals and identity are exactly the material CONSTITUTION №3 keeps
inside this machine. A test asserts the text cannot appear here.
```

## bin/doc-freshness.sh, lines 29-35 (before this edit)

```text
--help BEFORE ANY WORK (S4, harbor#140). Placed immediately after strict mode
so it is the first executable line: a --help that reaches an argument parser is
a --help that a script with no parser ignores, and this file had none. Measured
2026-08-20: a sweep of `bin/*.sh --help` ran past five minutes because at least
one script treated the flag as a request to do work, and five of the scripts
with no --help at all are mutators. The text is the header, read out of THIS
file at runtime, so a help message cannot drift from what the script says it is.
```

## bin/doc-freshness.sh, lines 48-51 (before this edit)

```text
D1: the config dir is a variable, never a bare ~/.claude. HARBOR_DOC_TELOS_DIR
overrides the whole corpus root so the suite can score a fixture instead of
reading the operator's real goals — a test that needs live personal files to
pass is a test nobody can run.
```

## bin/doc-freshness.sh, lines 54-56 (before this edit)

```text
Thresholds in days, by what the document is FOR. A contract that froze a seam
should outlive a handoff brief by a wide margin; PROVENANCE tracks an upstream
that ships continuously, so it goes stale fastest.
```

## bin/doc-freshness.sh, lines 65-69 (before this edit)

```text
The default 90 would nag forever
about a file whose whole job is to
stop changing, and a check that
fires on the ordinary case is one
that gets muted (№2.11).
```

## bin/doc-freshness.sh, lines 80-97 (before this edit)

```text
mtime, in seconds, portably. BSD stat and GNU stat disagree on the flag, and
`ls -l` parsing loses the year. Both spellings are tried and the failure is
-1 = unknown, never 0 = brand new: a corpus whose age cannot be read must not
render as freshly reviewed.

VALIDATE THE OUTPUT, NEVER THE EXIT CODE — the rule already written at
bin/alert-probe.sh:93 and applied here late. `stat -f` means "format" to BSD stat and
"file system status" to GNU stat, so on Linux the first call PRINTS a block of
filesystem fields to stdout and THEN fails; an `||` chain appends the second
call's answer to that garbage, `$_m` is non-empty, `[ -n "$_m" ]` waves it
through, and the arithmetic below dies:

  bin/doc-freshness.sh: 84: Illegal number:   File: ".../TELOS.md"

Under this file's `set -eu` that ABORTS `harbor fresh` part-way through its own
report — measured 2026-09-06 on GNU coreutils 9.4, which is also why the eight
C1a assertions in floor-test could not pass on a Linux runner. The BSD path is
unchanged: `stat -f %m` returns digits there and wins the first case.
```

## bin/doc-freshness.sh, lines 106-107 (before this edit)

```text
A `YYYY-MM-DD` → day number. Pure arithmetic on the calendar fields (no
`date -d` / `date -j`, which are the GNU/BSD split this repo keeps tripping over).
```

## bin/doc-freshness.sh, lines 114-115 (before this edit)

```text
${x#0} not $((x)): POSIX arithmetic reads a leading zero as OCTAL, so `08` and
`09` are errors under set -eu and August and September would abort the script.
```

## bin/doc-freshness.sh, lines 123-132 (before this edit)

```text
Age in days, LOCAL to LOCAL. Prints ERR when the date is unreadable, so the
caller can tell "cannot be scored" from "dated in the future" — different facts
with different fixes.

BOTH SIDES ARE LOCAL, and that is the bug this shape exists to prevent. The first
cut compared a local calendar date against UTC epoch days (`NOW / 86400`), so in
a UTC+3 timezone every entry dated TODAY scored -1 between 00:00 and 03:00 local
and was reported as an unparseable date. Found on 2026-07-31 at 00:30 local, by
the first real GOALS.md rather than by the suite — the fixture used today's date
and passed all afternoon, because the skew only appears inside the offset window.
```

## bin/doc-freshness.sh, lines 141-157 (before this edit)

```text
UNKNOWN FLAG → 2, WHICH IS THE CLI CONTRACT AND WAS NOT HONOURED HERE.
contracts/cli.md:70 makes exit 2 "usage error — unknown verb, unknown flag,
missing argument", uniform across verbs "because a caller that has to remember
per-verb codes will not". Measured 2026-08-14: `harbor fresh --bogus` ran the full
report and exited 0 — the flag was neither honoured nor refused, so a typo in a
wired invocation or a CI step reads as success. `harbor cite` and `harbor dash`
had the same hole; unknown VERBS were already handled at bin/harbor.

The guard is HERE and not in the dispatcher because the dispatcher cannot know
which flags a verb takes without a second copy of that list — and a copy is what
rots. Each verb owns its own flag set; bin/harbor forwards and exits verbatim.

AND THE GUARD VALIDATED ONLY $1 (harbor#226). `doc-freshness.sh --open --bogus` and
`doc-freshness.sh --open extra` ran the full report and exited 0 — the same hole one
position over, with the same consequence the paragraph above describes. The
offending token is named rather than counted, because "too many arguments" sends
the reader back to work out which one.
```

## bin/doc-freshness.sh, lines 167-169 (before this edit)

```text
-w, NOT \b. `\b` is a GNU extension that git grep's default engine silently
does not honour here — it matched NOTHING and reported "none", which is the
exact fail-open shape lint rule F2 exists to catch in the guards.
```

## bin/doc-freshness.sh, lines 189-193 (before this edit)

```text
ROWS, not a pipeline. `for … done | sort` puts the loop body in a SUBSHELL, so
every `stale_n=$((stale_n + 1))` inside it was discarded and the summary below
reported "Nothing past its threshold" unconditionally — a report that cannot
report (CONSTITUTION №2.10). Invisible in this repo only because every document
is younger than its threshold today, so the true and the broken answer agree.
```

## bin/doc-freshness.sh, lines 214-216 (before this edit)

```text
The `telos` skill is installed and ambient and reads these three paths. When
they do not exist the honest output is the FINDING, not a silent empty table —
a live skill pointed at an empty address is the defect the ticket names.
```

## bin/doc-freshness.sh, lines 225-232 (before this edit)

```text
PER ENTRY, because a goal list is not one document. Format, mirroring
IDEAS.md so the operator learns one shape and not two:
  - `G1` · 2026-07-30 · active · <the goal>
The date is when the entry was last REVIEWED. Ids are stable: an edited
or retired goal keeps its id, which is what makes staleness trackable
per entry rather than resetting the whole file on every edit.

The goal TEXT is cut here and never printed. Ids and ages only.
```

## bin/doc-freshness.sh, lines 235-238 (before this edit)

```text
COLUMN 0, not `^[[:space:]]*-`. The relaxed form scored the FORMAT EXAMPLE
in the file's own header — an indented `- \`G1\` · YYYY-MM-DD · …` inside a
code block — as a real, undated goal. A document that documents its own
shape must not be parsed as an instance of it.
```

## bin/doc-freshness.sh, lines 251-252 (before this edit)

```text
A future review date is a typo or a clock problem, not staleness — and
calling it stale would send the operator to re-review a fresh entry.
```

## bin/doc-freshness.sh, lines 264-266 (before this edit)

```text
mtime is a WEAK signal and this says so rather than pretending: `touch`
looks identical to a review. It is the only signal available for an
untracked file, which is why GOALS.md carries dates in the content.
```
