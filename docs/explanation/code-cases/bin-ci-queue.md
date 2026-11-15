---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/ci-queue.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/ci-queue.sh, lines 8-49 (before this edit)

```text
WHAT IT ANSWERS. "How long until CI is done" — asked 2026-09-23 while three
runners worked through two overlapping runs, when the answer took five API
reads and a schedule worked out by hand. status-fleet-glyph.sh renders it as ⏳N ·~Mm.

THE REPOS ARE DERIVED, NEVER LISTED. Every running runner container's
RUNNER_URL, and every <runner>/.runner under HARBOR_CI_RUNNERS_DIR (default
~/runners), names the repo it serves, and the number of runners per repo is the
parallelism the estimate schedules against.
Adding or removing a runner changes the estimate with no edit here.

THE ESTIMATE. A job's typical length is the median of its last three successful
runs in the same workflow. A running job has typical minus elapsed left, never
below zero; a queued job waits for the earliest free runner. A run that has not
listed its jobs yet is assumed to need its workflow's usual set. NOT MODELLED:
`needs:` between jobs, so a job that waits on another reads as startable now and
the estimate runs short — which is why the glyph prints it with a `~`. A job with
no history takes the longest known typical, so an unknown job never shortens it.

ABSOLUTE TIMES ONLY. The cache stores the epoch each repo should be free (`eta`),
never a countdown: status-fleet-glyph.sh subtracts the clock at print time, as row 1
does for the rate-limit reset (harbor#84), because the harness can skip or cancel
any tick and a stored countdown is wrong by however long it was left standing.

A REPO GITHUB WOULD NOT ANSWER FOR is written with "unread": true and renders as
`?`: "could not look" must never read as "nothing running".

A WEDGED RUNNER IS NOT A BUSY ONE (harbor#152). On 2026-08-06 six jobs sat
`queued` for 25 minutes against a runner the API reported `online, busy=false`;
the fault was only in the runner's own _diag log, and a service restart cleared
it. Either fact alone is normal — a queue waits, an idle runner is idle — and
only the conjunction is a stall: a SELF-HOSTED job queued over STALL_SEC (600)
while at least one runner of this repo is online and not busy. It must hold on
two refreshes in a row, because a runner idles about a minute between jobs
(#279) and one sample would page on every handoff. A hosted job queued beside
an idle self-hosted runner is not a stall: that runner could never take it.

IT REPORTS AND NAMES THE REMEDY; IT NEVER RESTARTS ANYTHING. A restart is a
self-healing act on live infrastructure from an unreviewed signal, and the
2026-08-06 outage was server-side, where a restart loop would only flap. The
runners endpoint needs repo admin; when it cannot be read the stall is UNKNOWN
(`idle: null`) and the estimate above is untouched.

```

## bin/ci-queue.sh, lines 83-87 (before this edit)

```text
owner/repo, once per runner folder. The runner writes .runner with a UTF-8
byte-order mark; it is stripped here rather than trusting every jq to skip it.
UNPROVEN ON THIS BOX: jq 1.7 already skips the mark, so ci-queue-test.sh stays
green with the `tr` removed (measured 2026-09-23). The strip is for an older jq,
and no suite here can show it doing anything.
```

## bin/ci-queue.sh, lines 110-114 (before this edit)

```text
A RUN OLDER THAN A DAY IS A GHOST, NOT WORK. Measured 2026-09-23: a governance
run created 2026-08-06, the day of a GitHub Actions outage, still reads
`queued` with no jobs seven weeks later. Assumed to need its workflow's usual
set, it turned "1 job left" into "9 jobs, ~15m". Ghosts are counted, never
scheduled; `gh run cancel <id>` clears one.
```

## bin/ci-queue.sh, lines 150-152 (before this edit)

```text
The idle runners, by name, or null when the endpoint will not answer. Kept
apart from _ok on purpose: an unreadable runner list costs the stall verdict,
never the estimate.
```

## bin/ci-queue.sh, lines 160-164 (before this edit)

```text
A SUSPICION IS CARRIED ONLY ACROSS ONE REFRESH (Codex on #699). If the box
slept, the last cache can be hours old, and reusing its suspect_since would
turn the first sample after waking into a "second" observation. So the
previous cache must be at most two refresh intervals (600s) old, or the
suspicion starts again from now.
```

## bin/ci-queue.sh, lines 195-200 (before this edit)

```text
ONLY A RUNNER THAT COULD TAKE THE JOB (Codex on #699): its labels must
cover the job labels, compared case-blind as GitHub does. This is also what
keeps a HOSTED job out: no self-hosted runner carries ubuntu-latest. A
separate self-hosted filter was redundant beside it, and a mutant removing
it survived every case, so it went. An idle Linux runner
beside a queued macOS job is not a stall, and restarting it would help nothing.
```
