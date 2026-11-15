---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/alert-notify.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/alert-notify.sh, lines 6-65 (before this edit)

```text

This is the only thing in workstream E that writes, and the only thing that
speaks. alert-probe.sh evaluates and stays silent; keeping the two apart is what
lets every verdict be tested without a state file or a notification sink.

EDGES, NOT LEVELS. A monitor that announces a standing condition on every tick
is a monitor the operator mutes, and a muted channel monitors nothing — the
same economics as a guard with false positives (CONSTITUTION №2.11), which
docs/explanation/admission-baseline.md already paid for once when B7 blocked `git grep` over Harbor's own
docs. So: a verdict is announced when it CHANGES, a persisting CRIT is
repeated at most once a day, a recovery is announced once, and everything
else is silent. The tile and `sh alert-probe.sh` carry the level at all times; the
lock screen carries only the news.

UNKNOWN NEVER SPEAKS. A source that stopped being readable is a real fact and
it is on the tile, but it is the one class most likely to be transient — a
fleet cache mid-write, a MEMORY checkout mid-rebase — and a channel that fires
on those is a channel that cried wolf first.

THE NOTIFICATION BODY IS THE LEAST PRIVATE SURFACE IN HARBOR. It renders on a
lock screen, in a screen share, and into the system's own notification store.
§3's boundary applies with no judgment call available at the moment it fires,
so the body is built only from alert-probe.sh's own vocabulary — a check id, a
verdict, and a detail string this repo wrote — and then scrubbed of anything
path-shaped anyway. Two independent controls, because the first one is a
convention and the second one is a mechanism.

THE SINK IS BEST-EFFORT AND SAYS SO. `osascript -e 'display notification'`
returns 0 whether the banner renders or is suppressed — the attributed bundle
may never have been granted permission, and Focus silences it with no signal
to the caller. Delivery therefore cannot be proven from inside this script;
it closes only on a human saying they saw one.

MEASURED 2026-08-03, BOTH CONTEXTS, and they were measured separately because
they are separate claims. A banner sent by this file from a SESSION was seen
by the operator; that settles the sink and the AppleScript path. A banner sent
by the LAUNCHD job was then seen too — the unit bootstrapped into gui/<uid>,
the state file cleared so a standing verdict became a fresh edge again, and
`launchctl kickstart -k` fired it. The log carries the pair that proves the
edge logic at the same time:

  pulse: worst=warn spoke=0 sink=osascript answered=4/4   <- state already held it
  pulse: worst=warn spoke=1 sink=osascript answered=4/4   <- same verdict, fresh state

Nothing here rests on that measurement staying true. The durable record is the
state file and the dashboard tile; the banner is an accelerator, and `sink`
records which of the three cases each run was in, so "no banner appeared" is
diagnosable rather than mysterious. A grant can be revoked in System Settings
without telling anyone, which is why the sink is still best-effort by design.

`--selftest` EXISTS BECAUSE THE VERIFICATION STEP DID NOT WORK. The plist
header told the operator to kickstart the job and look for a banner — but a
scheduled run is edge-triggered, so a box whose verdicts have not moved sends
nothing, and a silent sink and a healthy box are indistinguishable at exactly
the moment you are trying to tell them apart. `--selftest` sends one banner
unconditionally, writes no state, and touches no verdict.

THE SCRIPT IS PASSED ON STDIN AND THE TEXT AS ARGV, deliberately. Interpolating
a message into an `-e` string is the shell-injection shape CONSTITUTION §4
forbids; `on run argv` means no part of the body is ever parsed as AppleScript.
```

## bin/alert-notify.sh, lines 68-74 (before this edit)

```text
--help BEFORE ANY WORK (S4, harbor#140). Placed immediately after strict mode
so it is the first executable line: a --help that reaches an argument parser is
a --help that a script with no parser ignores, and this file had none. Measured
2026-08-20: a sweep of `bin/*.sh --help` ran past five minutes because at least
one script treated the flag as a request to do work, and five of the scripts
with no --help at all are mutators. The text is the header, read out of THIS
file at runtime, so a help message cannot drift from what the script says it is.
```

## bin/alert-notify.sh, lines 88-89 (before this edit)

```text
A CRIT that nobody has fixed is still worth one reminder a day. Anything more
frequent is the standing-condition spam this file exists to avoid.
```

## bin/alert-notify.sh, lines 128-130 (before this edit)

```text
The probe cannot read state — it is the pure evaluator — but it needs one fact
only the writer has: when this pair last ran. Without it a stale fleet cache
and a laptop that was closed are the same observation.
```

## bin/alert-notify.sh, lines 139-141 (before this edit)

```text
`-f` and not `-e`: a FIFO planted at the state path would hang a reader
forever and there is no `timeout` on macOS (DE-11). A named pipe is not a
regular file, so this refuses to read it and the run continues on defaults.
```

## bin/alert-notify.sh, lines 150-155 (before this edit)

```text
REFUSE TO SPEAK IF I CANNOT REMEMBER THAT I SPOKE. Notifications go out first
and state is written last, so a state write that fails AFTER the banners turns
an edge-triggered notifier into a level-triggered one: the same verdict is
announced on every tick, forever, which is the failure mode this whole design
is built to avoid. Proving the write is possible before any banner leaves is
cheaper than making the send transactional.
```

## bin/alert-notify.sh, lines 164-167 (before this edit)

```text
The redirection is inside a SUBSHELL because a failed redirect is reported
by the shell itself, before the command runs, so the command's own 2>/dev/null
never suppresses it — the operator would get the shell's raw diagnostic and
then this file's explanation of the same thing.
```

## bin/alert-notify.sh, lines 176-178 (before this edit)

```text
Path-shaped anything becomes [path] before it can reach a lock screen. The
vocabulary upstream of this has none today; this is the mechanism that keeps
that true when someone adds a check next month and quotes a filename in it.
```

## bin/alert-notify.sh, lines 182-186 (before this edit)

```text
THE RETURN VALUE IS LOAD-BEARING. This used to swallow every failure and
return 0, so a box with no sink at all recorded the edge as announced and
then suppressed it forever: the operator would never hear about a WARN that
was "sent" into nothing. A send that did not happen must leave the edge
unrecorded, so the next run says it again.
```

## bin/alert-notify.sh, lines 198-204 (before this edit)

```text
THE COMPARISON IS AGAINST WHAT WAS LAST ANNOUNCED, not against the previous
verdict. Those differ the moment an `unknown` lands between two real ones,
and reading the previous verdict got both directions wrong: warn → unknown →
ok announced no recovery at all (the operator's last message stayed an
unresolved warning), while warn → unknown → warn announced the same standing
condition twice. The last thing SAID is the only thing the operator's
attention is actually holding, so it is the thing to diff against.
```

## bin/alert-notify.sh, lines 220-221 (before this edit)

```text
_rv/_rat is what the notified map should hold for this check after this run.
Default: whatever it held before — an unannounced run must not disturb it.
```

## bin/alert-notify.sh, lines 237-237 (before this edit)

```text
Clear it. The condition is over, and the next occurrence must be news.
```

## bin/alert-notify.sh, lines 243-244 (before this edit)

```text
_ok=1 means the sink refused it: leave the map untouched so the next run
tries the same edge again rather than pretending it was delivered.
```

## bin/alert-notify.sh, lines 246-252 (before this edit)

```text
AN `if`, NOT `[ … ] && printf`. The AND-list form makes the loop body's exit
status 1 whenever the test is false, which makes the whole `while` exit 1 —
and the loop is the tail of a pipeline, so `set -e` kills the script right
here, BEFORE the state write below. Measured: a recovery notification was
sent, the script died silently on the way out, the stale state survived, and
the next run announced the same recovery again. A run that did half its job
and exited 0 is the exact shape DE-14 is about.
```

## bin/alert-notify.sh, lines 258-263 (before this edit)

```text
TWO FILES, BECAUSE ONE COUNTED THE WRONG THING. The loop runs in a subshell
(right-hand side of a pipe), so a counter variable cannot survive it — but the
first version counted $KEEP, which also carries FORWARD the entries that were
not announced. A silent second run therefore reported `notifications: 1`, a
field claiming this run spoke when it had not. $SAID holds only what was
actually said.
```

## bin/alert-notify.sh, lines 266-268 (before this edit)

```text
A notifier that cannot speak is a no-op by decision, not a failure (harbor#618): WSL2 and servers often have no
sink or no daemon behind notify-send. One note per run; every held edge stays unrecorded, so the first run
that has a working sink announces it. The tile and `sh alert-probe.sh` carry the level meanwhile.
```

## bin/alert-notify.sh, lines 279-283 (before this edit)

```text
The directory was created and proven writable above, before anything was said.
The precedent for creating it at all is status-fleet-snapshot-refresh.sh, which does
the same: DE-11 and DE-13 forbid this in the GUARD hot path, where a hang is a
total bypass of every rule, not in a scheduled writer whose worst failure is a
missing tile.
```

## bin/alert-notify.sh, lines 286-288 (before this edit)

```text
Temp-then-rename, never append: a rename cannot be intercepted by whatever is
at the destination, and a half-written state file is the one thing that would
make the next run's edge detection wrong in both directions.
```

## bin/alert-notify.sh, lines 297-302 (before this edit)

```text
ONE LINE PER RUN, ON STDOUT. The plist declares StandardOutPath so that a run
that happened is distinguishable from one that did not — and the first version
of this file printed nothing on success, which made that log exactly as
uninformative as the always-empty stderr of the fleet job this design
criticised for exactly that. A healthy silent run and a job that has not fired
since July must not produce the same artefact.
```
