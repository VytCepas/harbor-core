---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of hooks/memory-harvest/memory-harvest.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## hooks/memory-harvest/memory-harvest.sh, lines 3-33 (before this edit)

```text

THE GAP IT CLOSES. worklog-push.sh writes a session record on Stop. A session
that crashes, is killed, or ends with the machine asleep never reaches Stop, so
it leaves a transcript and no record. Measured on this machine before this hook
existed: 87 transcripts in 30 days, 61 of them with no work-log record. D1's
done-when is "a crashed session re-harvests on next start"; this is that.

IT NEVER OPENS A TRANSCRIPT. Everything it needs is in the index: the session
id is the filename, the project is the directory name, and the clock is the
file's mtime. That is not a shortcut — DEAD-ENDS DE-16 rejected building a
durable corpus out of transcript CONTENT, because it outlives the 30-day GC
that deletes the transcripts and because a shape-preserving scrubber still let
live-secret-shaped payloads through. Reading only the index makes the whole
class unreachable rather than mitigated. There is no scrubber here because
there is nothing to scrub.

WIRED AT SessionStart (harbor#1390). It was at Stop because its stand-down once read
the context a SessionStart hook writes; since harbor#954 it reads only the repo's
`worklog: off`, so the reason is gone and Stop only made it run every turn. The
starting session is skipped: its transcript exists and its record is Stop's to write.
hooks/memory-harvest/manifest.tsv carries the history.

BOUNDED, because a SessionStart hook is on a path the operator waits for.
DEAD-ENDS DE-09: a hook that exceeds its timeout is SKIPPED, so a slow
reconciler does not fail loudly — it silently stops running, and a fail-open
bypass wearing a performance regression's clothes is the worst shape
available. Two bounds: a day window, and a per-run cap. What the cap drops is
REPORTED, never silent: a run that quietly covered half the backlog reads
exactly like one that covered all of it.

NEVER BLOCKS THE SESSION: every path exits 0.
```

## hooks/memory-harvest/memory-harvest.sh, lines 50-51 (before this edit)

```text
Stdin FIRST: the shared resolver reads .cwd from the payload, and the
stand-down decision depends on it. Same order as worklog-push.sh.
```

## hooks/memory-harvest/memory-harvest.sh, lines 63-76 (before this edit)

```text
Every session id already recorded under ANY host partition, from the FILENAMES —
the record's name is <date>-<session-id>.md and the date is not known in advance,
so matching on the id means stripping the date rather than guessing it.

ALL partitions, not just this host's (PR #119 review). A session id belongs to
exactly one machine, so "recorded anywhere" is the correct predicate, while
scoping the check to $HOST makes every record written under a PREVIOUS host token
invisible: the session reads as unharvested and gets written a second time.

Not hypothetical, and not a risk this change introduces — it is a duplication this
change STOPS. The 2026-08-04 token flip did exactly this, and every one of the 38
session records it wrote under `Mac` was a duplicate of one that already existed
under the real host name: 38 ids in both directories, 0 unique to `Mac`. Writes
still go to $HOST; only the reconciliation predicate is host-agnostic.
```

## hooks/memory-harvest/memory-harvest.sh, lines 80-85 (before this edit)

```text
A project directory name is the cwd with every separator replaced by a dash,
which is LOSSY: a path that itself contains a dash is indistinguishable from a
separator. So the decode is checked rather than trusted — if the reconstructed
path is a real directory, use it; otherwise record the encoded name verbatim
and let the reader see that it is encoded. Guessing a plausible path that was
never the cwd would be worse than showing the raw one.
```

## hooks/memory-harvest/memory-harvest.sh, lines 102-102 (before this edit)

```text
Already recorded — by id, whatever date the record carries.
```

## hooks/memory-harvest/memory-harvest.sh, lines 106-108 (before this edit)

```text
Harness scratch directories are not work. They are created by test runs and
e2e probes under the system temp dir, and backfilling them would fill the
cross-device work-log with sessions that never belonged to anyone.
```

## hooks/memory-harvest/memory-harvest.sh, lines 118-119 (before this edit)

```text
The transcript's mtime is the closest available stamp for when the session
ended. `date -r` reads a file's mtime on both BSD and GNU date.
```

## hooks/memory-harvest/memory-harvest.sh, lines 132-134 (before this edit)

```text
NO SILENT CAPS. If the backlog is bigger than one run may write, say so — the
next session start takes the next batch, and the operator can see it happening instead
of wondering why the log is still short.
```
