# Local CI that heals itself (harbor#1060)

**Status:** built in the PR that adds this file. Evidence base: the 2026-10-06 sessions on `harbor-linux`.
Nothing here edits `.github/workflows/` or `~/.claude`; the operator steps are at the end.

| Seen 2026-10-06 | What it became |
|---|---|
| A network drop (18:47-18:50Z, `BrokerServer ... TaskCanceledException` in the runner log) left run 37511778240's `suites` job with its "Every selected suite" step **without a conclusion**; only a manual `gh run rerun --failed` fixed it | `ci-runners.sh rerun-lost` now re-runs that shape, once (below) |
| `suites` hit its 30-minute limit twice (runs 37471031089, 37461944104) at load 20+, harbor's container at the governor's floor | The governor **lifts** a low-priority job that has run past `lift_after` (below) |
| Eight or nine runs queued behind the one `harbor-linux` runner | `governance 2`, operator steps below. Not applied by an agent: the config lives in `~/.claude` |
| `busy=true` with no run in progress | Not a wedge: the runner was between jobs. `ci-queue.sh`'s stall detection already covers a real one |

## 1. Infrastructure-failed jobs are re-run once

`rerun-lost` (check id `ci.lost-rerun`, same `cache/ci-lost-reruns.tsv`, same one `checks.log` line per action) grew from one
shape to three. All three are a job that **failed or was cancelled with no step concluded `failure`**; a job with a failed
step is a real failure and its annotations are not even read.

| Shape | Test | First seen |
|---|---|---|
| not acquired | no steps, every annotation says no runner acquired it | #675 |
| no conclusion | a job that **failed** (never `cancelled`) with a step that started and never concluded (`conclusion: null`) and no annotation | 2026-10-06 |
| runner lost | every annotation matches `ci-lost-job.sh --runner-pattern` (`lost communication with the server`, `received a shutdown signal`) | 2026-10-06 |

Never matched: a cancel, a timeout (`exceeded the maximum execution time`) or a fail-fast sibling, each of which carries an open step and
its own annotation (`The operation was canceled.` is not the runner's phrase either), lost-communication text beside any other
annotation, a failed step beside an open one.

**Once** is three guards, any one of which stops a second re-run: the job id in `ci-lost-reruns.tsv` (written before the call), the
run id in the same file, and the `attempt == 1` filter (a re-run run is on attempt 2, so a second infrastructure failure of the
re-run is left to a person). Falsifier: `sh tests/ci/runners/lost.test.sh`.

Unverified against live GitHub: that a human-cancelled job never carries a step with a null conclusion. The suite stubs the shape
the operator's definition gives; if a cancelled job ever re-runs by mistake, the `[check:ci.lost-rerun]` line names the reason
(`a step left with no conclusion`) and `lost-rerun off` disables the whole check.

## 2. Load timeouts: the governor lifts an old low-priority job

The governor already cut a busy low-priority container (harbor, Fleet, Yard) to `linux_min` (1 core) whenever a day-to-day job
ran. A job that started under that cut, or ran into one, could not finish inside its timeout at load 20+.

**Lift:** a busy low container whose `Runner.Worker` is older than `lift_after` seconds (default **900**, half of harbor's 30-minute
`suites` timeout; `0` = off) keeps `lift_cpus` cores (default **2**) instead of the floor.

- **Age** is the worker's own elapsed time (`ps -o etimes=` in the container, one `docker exec` that also answers busy/idle). No state
  file, no GitHub call, and a new job on the same runner starts young. An age that cannot be read is never aged.
- **No starvation:** the lift is capped so every other busy container keeps `linux_min`, so a priority repo is never cut under the floor
  to pay for it; with a single day-to-day job on budget 4 it gets 2 cores instead of 3, only while a harbor job is past 900s. An
  emergency (rung c) overrides the lift like every cap, and nothing else changes: young low jobs are cut exactly as before.
- **Visible:** the `[check:ci.governor]` line says `harbor-linux --cpus 1 -> 2 (job over 900s keeps its lift)`; `status` marks the
  runner `aged`.
- **Falsifier:** `sh tests/ci/governor/priority.test.sh` (boundary 899s/900s, the floors, `lift_after=0`, config keys, the
  unread age, an aged and a young low job together, the emergency).

**What it does not fix:** a job that needs more than the lift at load 20+ still times out. The operator-side options, neither done
by an agent: raise the `suites` job's `timeout-minutes` in the workflow (agents may not edit `.github/workflows/`), or lower the load
(`governance 2` does not help here: two busy governance runners split the same budget, 2 cores each).

## 3. Second runner: `harbor-linux-2` (operator steps)

`governance N` (harbor#1083) is already built and tested; it is just not enabled. From `~/port/harbor`:

```sh
# 1. the config line (private ~/.claude, so the operator's edit)
printf 'governance 2\n' >> ~/.claude/.harbor-ci-runners

# 2. what it would create: a dry run, touches nothing
sh bin/ci-runners.sh up --include-governance

# 3. create and register harbor-linux-2 on VytCepas/harbor (made as harbor-linux is: image, events mount, hooks,
#    restart policy, memory, --cpus linux_min); an existing one is adopted, a stopped one started
sh bin/ci-runners.sh up --apply --include-governance

# 4. check: two `governance` rows, both online; the governor shows harbor-linux-2 as class low
sh bin/ci-runners.sh list
sh bin/ci-governor.sh status
```

What it buys and costs. It removes the queue (two harbor jobs at once), and the alarm (`ci.runner-alarm`) and `rerun-lost` already watch
it by name. It does **not** add cores: the governor's budget (4 active, 8 idle) is split between two busy low runners, so each job runs
slower. Pair it with the lift above, or the second runner trades queueing for timeouts.

Going back: `docker rm -f harbor-linux-2`, delete its registration (`gh api -X DELETE repos/VytCepas/harbor/actions/runners/<id>`, the id is
in `sh bin/ci-runners.sh list --json`), then `governance 1`.

## 4. The wedge alarm already exists

The #1060 item "a registered runner offline, or jobs queued > N minutes with no runner" is `ci.runner-alarm` (docs/reference/checks.md), built on
`ci-runners.sh tick`'s reads with no poll of its own; `sh tests/ci/runner/alarm.test.sh` replays the 2026-10-05 reboot. Not added again.
Its one blind spot is by design: a job queued **behind a busy runner** is not "no runner able to take it", so the 2026-10-06 queue of
eight runs would not raise it; that queue is what `ci-queue.sh` estimates (the statusline `⏳N ·~Mm`) and what the second runner relieves.
