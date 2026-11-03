---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/idea

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/idea, lines 6-9 (before this edit)

```text
The event-time counterpart to worklog-push.sh's Stop-hook batch: here the
event IS you running the command, so there is no watcher, no daemon and no
schedule to drift. Same repo, same token, same fail-closed secret gate.

```

## bin/idea, lines 13-13 (before this edit)

```text

```

## bin/idea, lines 18-24 (before this edit)

```text
--help BEFORE ANY WORK (S4, harbor#140). Placed immediately after strict mode
so it is the first executable line: a --help that reaches an argument parser is
a --help that a script with no parser ignores, and this file had none. Measured
2026-08-20: a sweep of `bin/*.sh --help` ran past five minutes because at least
one script treated the flag as a request to do work, and five of the scripts
with no --help at all are mutators. The text is the header, read out of THIS
file at runtime, so a help message cannot drift from what the script says it is.
```

## bin/idea, lines 30-34 (before this edit)

```text
guard-lib for floor_gitleaks_staged ONLY (the gate below). Nine other non-guard
scripts source it the same way — worklog-push.sh, worklog-pull.sh,
memory-harvest.sh and the rest — so this is house practice, not a new coupling,
and it is what keeps the scanner-dialect probe to ONE implementation instead of
the three call sites it was about to become.
```

## bin/idea, lines 50-52 (before this edit)

```text
idea_git <git args>: git with the work-log token as a header, never in the URL (CONSTITUTION No.4).
The token is the store's `worklog-token` and nothing else (harbor#1205, decided 2026-10-23): a plaintext file left
from before is never read, only named with the command that moves it. Returns 3 when the store has no token.
```

## bin/idea, lines 62-62 (before this edit)

```text
die <what failed> [fix command]: FAIL, its fix, the summary, exit 1.
```

## bin/idea, lines 71-71 (before this edit)

```text
The log repo is the pool's own GitHub origin, never a name core carries (harbor#1149); none means local only.
```

## bin/idea, lines 88-91 (before this edit)

```text
Pull first. A single shared file across devices is the one place the work-log's
host-partitioning trick does not apply, so we rebase onto origin before
appending rather than discovering the divergence at push time. Offline is fine
— we just append locally and the next idea (or the Stop hook) carries it up.
```

## bin/idea, lines 117-122 (before this edit)

```text
Next id — derived from the file, never stored in a counter that can drift.
Snapshot BEFORE the append. A rejected idea must leave no trace: `git reset`
alone only unstages, so the rejected line would stay in the working file —
which both leaves the secret sitting on disk AND makes gitleaks re-find it on
every later run, bricking the pool permanently. Found by testing the gate
(CONSTITUTION No.2.10/2.11: a guard that blocks ordinary work gets switched off).
```

## bin/idea, lines 127-128 (before this edit)

```text
grep -c PRINTS 0 and EXITS 1 on no match, so `|| echo 0` would emit "0\n0"
and break the arithmetic. Take grep's stdout; only default when it is empty.
```

## bin/idea, lines 136-138 (before this edit)

```text
Fail-closed secret gate, same posture as worklog-push.sh. An idea pool is
exactly where a pasted key goes to die, and this repo has a remote. Set
IDEA_NO_SCAN=1 to bypass deliberately.
```

## bin/idea, lines 143-146 (before this edit)

```text
ONE implementation of the subcommand probe, in guard-lib, not a third copy
here — see floor_gitleaks_staged. 8.18.4 has no `gitleaks git` and exits 1 on
it, so with `--exit-code 1` an absent subcommand read as a secret and this
gate reverted every idea on a box carrying the version CI pins.
```
