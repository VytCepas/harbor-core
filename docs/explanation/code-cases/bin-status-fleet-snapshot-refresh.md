---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/status-fleet-snapshot-refresh.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/status-fleet-snapshot-refresh.sh, lines 8-14 (before this edit)

```text
--help BEFORE ANY WORK (S4, harbor#140). Placed immediately after strict mode
so it is the first executable line: a --help that reaches an argument parser is
a --help that a script with no parser ignores, and this file had none. Measured
2026-08-20: a sweep of `bin/*.sh --help` ran past five minutes because at least
one script treated the flag as a request to do work, and five of the scripts
with no --help at all are mutators. The text is the header, read out of THIS
file at runtime, so a help message cannot drift from what the script says it is.
```

## bin/status-fleet-snapshot-refresh.sh, lines 20-21 (before this edit)

```text
One log format (contracts/logging.md): a scheduled job is silent while it works, and its one failure
says what failed and how to see why, on the stdout launchd keeps.
```

## bin/status-fleet-snapshot-refresh.sh, lines 26-26 (before this edit)

```text
the fleet file through the registry-aware reader beside this script (harbor#966)
```

## bin/status-fleet-snapshot-refresh.sh, lines 28-28 (before this edit)

```text
the fleet CLI, a roots.tsv row read through the same reader (harbor#966)
```

## bin/status-fleet-snapshot-refresh.sh, lines 37-45 (before this edit)

```text
── guard-decision counts (L1/OBSERVE-1, harbor#41 → statusline, harbor#59) ──
Reduced to the two numbers the statusline renders. Done HERE and not in the
statusline because reading the ledger means reading every record in it, and a
statusline tick must not scale with the size of a log.

REMOVE THE CACHE ON FAILURE, never leave the last good value. observe-report
exits 1 on an absent or empty ledger, which is the state on any box where the
guards are not installed — and a persisted "blocks 3" from a ledger that no
longer exists is a number the operator would act on. Absent must stay absent.
```

## bin/status-fleet-snapshot-refresh.sh, lines 58-70 (before this edit)

```text
── what is BUILT here and NOT RUNNING there (harbor#44 follow-through) ──────
Piggybacked on this refresher rather than given a launchd job of its own, and
that is the whole point: a check for "the schedule was never installed" cannot
depend on a schedule the operator has to install first. This refresher is
already loaded on this box, so the check runs today.

BEFORE the orchestrator block below, which `exit 1`s when the snapshot fails.
Ordered after it, a missing orchestrator would silently take this with it —
and the state where nothing is installed is exactly when it must still speak.

The --live/dir split is session-verdicts.sh's idiom: renew-check refuses
--apply on the live dir unless it was NAMED --live, so passing the path would
make the refresher a no-op that looks like a clean box.
```

## bin/status-fleet-snapshot-refresh.sh, lines 82-96 (before this edit)

```text
── the sweep: what is left over and needs a person, counted twice a day ─────
The operator's call (2026-09-22): this job, at 09:00 and 16:00 — not a launchd
job of its own. housekeeping-clean.sh --if-due makes every other tick a no-op that
reads one line, so the slot gate lives in one place and is tested there.

It COUNTS AND NEVER DELETES: --record refuses --apply outright. It writes
.helm-sweep, which the statusline renders as 🧹N and SWEEP.

INLINE, NOT BACKGROUNDED, and the cost is accepted: a record takes about a
minute (measured 2026-09-22 at 60s over fifteen repos), twice a day, during
which this tick's snapshot waits. `&` would not save it — launchd kills every
process left in the job's process group when the job exits (launchd.plist(5),
AbandonProcessGroup), so a backgrounded sweep would die with this script.
BEFORE the orchestrator block, for renew-check's reason: that block exits 1
when the snapshot fails, and the sweep must still run then.
```

## bin/status-fleet-snapshot-refresh.sh, lines 98-99 (before this edit)

```text
Restated, not inherited from the renew-check block: that block is skipped
when drift-renew-check.sh is absent, and set -u would then end this whole job.
```

## bin/status-fleet-snapshot-refresh.sh, lines 110-114 (before this edit)

```text
── the CI queue: jobs left on this box's runners, and when they should end ────
Operator request 2026-09-23 (harbor#657): ⏳ on the statusline. Every tick, not
on a slot — a queue changes by the minute, and an idle box costs two GitHub
reads per repo. The cache holds epochs only; status-fleet-glyph.sh does the countdown.
BEFORE the orchestrator block, for the sweep's reason: that block can exit 1.
```

## bin/status-fleet-snapshot-refresh.sh, lines 119-122 (before this edit)

```text
── main's tip: does every recent commit on main carry a green CI verdict? ─────
harbor#586. Inside this run and not on a schedule of its own: a new launchd job needs the
operator's yes, and one bounded read of main's runs a tick is cheaper than the ⏳ tile's.
Writes cache/main-tip-verdict.json (the statusline's MAIN RED) and one checks.log line per change.
```

## bin/status-fleet-snapshot-refresh.sh, lines 127-130 (before this edit)

```text
── the obligations ledger: fold the bus, then ask the real state about what is still open (harbor#1050) ──
Inside this run and not on a schedule of its own, for main-tip-verdict's reason. Reads are bounded (10s each, 40s together,
HARBOR_STATUS_OBLIGATION_BUDGET) and a source that does not answer flips nothing, so a failure or a timeout costs this tick
at most the budget and never its exit status. BEFORE the orchestrator block, which can exit 1.
```

## bin/status-fleet-snapshot-refresh.sh, lines 135-137 (before this edit)

```text
── the account plan and main's protection: say the first time either moves (harbor#1060) ───
Pro -> Free on 2026-10-05 turned protection off and cut the minutes, and surfaced only when a merge was refused.
Two reads a tick; one checks.log line per change, and the statusline's PLAN/GATE alarm until `ci-github-plan.sh ack`.
```

## bin/status-fleet-snapshot-refresh.sh, lines 142-145 (before this edit)

```text
── the CI runner: GitHub-hosted until the month's Actions minutes run short ───
harbor#865. Inside this run and not on a schedule of its own, for main-tip-verdict's reason. One bounded read of the
month's bill a tick; sets the repo variable HARBOR_CI_RUNNER only when the value would change, and logs
one checks.log line per change. A read that fails flips nothing (bin/ci-runner-switch.sh).
```

## bin/status-fleet-snapshot-refresh.sh, lines 154-157 (before this edit)

```text
── the fleet's runners: each repo's CI_RUNS_ON follows that verdict (harbor#1060) ───
After runner-switch, which writes the verdict this reads. Sets CI_RUNS_ON on the repos with a local runner, re-runs
billing-refused runs once, logs drift on change, and raises the ci-runner-alarm (a runner offline, docker down, a job no
runner can take). It creates no container and reads or writes no billing (bin/ci-runners.sh).
```

## bin/status-fleet-snapshot-refresh.sh, lines 162-188 (before this edit)

```text
-- the watch . are the schedulers this board depends on actually loaded ------
THE NUMBERS THE STATUSLINE RENDERS ARE ONLY AS TRUE AS THIS JOB. .helm-renew,
.helm-judge, guard-decisions.json and the fleet snapshot are all files on disk
refreshed by launchd. If a job stops, every token sourced from it freezes at its
last value and keeps rendering as current -- a green board over a dead reporter.
That failure has been measured on this operator's data pipelines (alerting fires
on build FAILURE, so a green build over a dead feed is silent); there is no
reason to assume the same shape is safe here.

INSTALLED IS THE DENOMINATOR, LOADED IS THE NUMERATOR, and the distinction is
the whole check. drift-renew-check.sh already answers "built here, installed nowhere"
by comparing repo plists against ~/Library/LaunchAgents. It does NOT answer
"installed and not loaded", and its own comment explains why it declines to: a
job can be loaded from a plist since deleted, and a plist can sit on disk
unloaded, so the FILE is what an operator can act on. True -- and the load state
is the thing that decides whether that file does anything today.

launchctl list IS MATCHED ON THE LABEL, NOT PARSED FOR STATUS. The third column
is the label; the first is a pid or "-", and "-" means loaded-but-not-currently-
running, which for a periodic job is the NORMAL state. Reading it as dead would
put every healthy interval job in the alarm -- the false-positive shape
CONSTITUTION 2.11 calls a defect rather than safety.

WRITTEN ONLY WHEN launchctl (or systemctl) EXISTS AND SOMETHING IS INSTALLED. Otherwise the
file stays absent and the statusline renders no watch tile, which is the honest
answer: this check has never run here. Never "watch 0 0" -- that reads as "no
jobs needed" rather than "nobody looked".
```

## bin/status-fleet-snapshot-refresh.sh, lines 199-201 (before this edit)

```text
Anchored on both sides: a bare substring match would count
com.harbor.status.usage as loaded because com.harbor.status.usage-sessions is. The listing is wrapped in
newlines because $(...) strips the last one: a harbor job listed last must still match.
```

## bin/status-fleet-snapshot-refresh.sh, lines 228-246 (before this edit)

```text
`-s` IS LOAD-BEARING, NOT STYLE. `jq -e 'type == "array"'` is evaluated ONCE PER
JSON DOCUMENT, so a producer emitting two concatenated top-level arrays passes
it — every document is an array, every check returns 0, and the file is
published. Measured 2026-08-14: the consumer then rendered THREE statusline rows
with TWO different fleet counts, because `jq -r PROGRAM file` also runs per
document. Slurping collapses the whole file into ONE array of documents, so
`length == 1` is the only spelling that can say "exactly one answer in here".
The consumer degrades on this too now (bin/status-fleet-glyph.sh), because a cache with
a private remote and a launchd writer needs the check at both ends.

EVERY ELEMENT MUST BE AN OBJECT (fleet#218). The array check
alone admitted `[…, null]`, and each consumer counts elements: measured
2026-09-19, a null-padded copy of the live cache moved the statusline from ⚓15
to ⚓16, a phantom project with no fields and no error. The producer's schema
(snapshot.v1, `items: object`) already refuses that shape, so this is the
writer agreeing with the contract, not a stricter one. It stops at the ELEMENT:
fields inside an object stay unchecked on purpose, because the seam is
additive-only and a field-level gate here would blank the tile on a legitimate
producer change (the trade tests/status/statusline/fleet.test.sh pins).
```

## bin/status-fleet-snapshot-refresh.sh, lines 257-259 (before this edit)

```text
harbor#1181: the cache above is overwritten every refresh, so fleet state had no history. One counts-only line per
refresh makes it a stream; never project names, which can be client names.
A missing library skips the history line, never the refresh: telemetry spills, it does not fail its caller.
```
