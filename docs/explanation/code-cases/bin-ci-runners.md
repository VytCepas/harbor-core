---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/ci-runners.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/ci-runners.sh, lines 4-74 (before this edit)

```text
  sh ci-runners.sh list [--json]       desired (fleet repos whose workflows read vars.CI_RUNS_ON) against actual
                                       (container, image, runner online on GitHub, CI_RUNS_ON); writes nothing
  sh ci-runners.sh up [--apply]        create the missing <repo>-linux containers, start stopped ones, and set an adopted
                                       one's memory to its configured value LIVE (docker update, no recreate); a dry run without --apply
  sh ci-runners.sh down <repo|org> [--apply]   remove the container and its GitHub registration; refuses a busy runner
  sh ci-runners.sh refresh [--apply]   recreate (busy re-read right before each removal), as up does, each container on an image older than the configured tag (list says
                                       `stale`); skips a busy runner, one at a time, stops at the first failure; tick never runs it
  sh ci-runners.sh refresh --apply --include-governance   also recreate harbor-linux, the governance runner `list` shows as a
                                       read-only `governance` row: only when it is stale, idle AND GitHub shows no queued or
                                       in-progress run on the governance repo; it keeps its mounts, memory and hooks (harbor#1083)
  sh ci-runners.sh up --apply --include-governance   also create (or start) a governance runner that is absent or stopped: with
                                       `governance 2` in the config, harbor-linux-2, made as harbor-linux is (image, events mount,
                                       hooks, restart policy, memory, --cpus linux_min), registered on the governance repo
  sh ci-runners.sh switch [--apply]    set CI_RUNS_ON=self-hosted on every repo (or org) with a local runner when its
                                       owner's ci-runner-switch.sh verdict says the minutes are short, unset it when not
  sh ci-runners.sh rerun-refused [--apply]   re-run, once, each run of the last 48h GitHub refused for billing
  sh ci-runners.sh rerun-lost [--apply]      re-run, once, a job of the last 48h that no runner took (harbor#675) or whose runner dropped
                                       mid-job: a step with no conclusion, or the runner's own lost-connection text (harbor#1060)
  sh ci-runners.sh tick                switch + rerun-refused + rerun-lost applied, and the drift report; run by status-fleet-snapshot-refresh.sh
  sh ci-runners.sh unwedge <container> [--apply]   a container the alarm confirmed WEDGED (busy on a dead job): prints the job's
                                       step processes (every descendant of Runner.Worker); --apply sends them TERM, then KILL to any
                                       left after 10s (HARBOR_CI_UNWEDGE_GRACE), so the runner fails the job and takes the next. Never
                                       Runner.Worker or Runner.Listener; refuses unless cache/ci-runner-alarm.json (<=900s old)
                                       confirms it wedged and the job running now is that job; one checks.log line
  (up --apply and tick also install bin/ci-governor-hook.sh into the events mount every container runs it from)

THE FLEET is the fleet snapshot (fleet.yaml's roots and projects, read through cache/fleet-snapshot.json).
A repo wants a runner when its workflows read vars.CI_RUNS_ON, unless its .agents/config.yaml says `ci_runner: hosted`
or its origin names no GitHub repo (never pushed: nothing to register a runner to); a repo under another owner is listed as `foreign` and left alone (personal-account runners are per repo).
CONFIG is $CLAUDE_CONFIG_DIR/.harbor-ci-runners: `image NAME` (else HARBOR_CI_IMAGE, else port-linux-runner:local),
`cpus N`, `memory SIZE`, and `hold REPO why` for a repo another runner still serves (listed, never provisioned or switched).
`governance N` (default 1, max 9) is how many governance runners harbor's own checks get: harbor-linux, harbor-linux-2, ...
`list` shows each as a read-only `governance` row; the governor keeps an idle one at linux_min and splits cores among busy ones.
`gate N` (default 0, max 9) is how many GATE runners the small jobs get (harbor#1286): harbor-gate, harbor-gate-2, ... made as the
governance runners are but labelled `self-hosted,Linux,ARM64,harbor-gate`, at cpus 1 and memory 2g (a `limits harbor-gate ...` line
changes either). Governance runners carry `harbor-pool` as well. The workflow sends shard legs to harbor-pool and the small jobs to
harbor-gate, so the small jobs never queue behind a 15-20 min leg. `list` shows each as a read-only `gate` row; `up --apply
--include-governance` creates (or starts) one; they are not *-linux, so the governor never changes their cpus.
Going back down is the operator's: `docker rm -f harbor-linux-2`, delete its registration (id in `list --json`:
gh api -X DELETE repos/OWNER/harbor/actions/runners/<id>), then `governance 1`; `down` refuses a governance row.
`repo OWNER/NAME` adds a repo the fleet does not list (not cloned here): wanted as if its workflows read the variable.
`org ORG [cap] [runners N]` gives the organisation N org-level runners (default 1, max 9), <org lower-cased>-linux,
then -linux-2 .. -linux-N (rows <org>, <org>-2 ..), each registered at the org with the same labels; its repos
are listed as `org` (served by them, no container of their own) and its CI_RUNS_ON is the ORG-level variable
(visibility private), which every private repo of the org reads. `hold <org lower-cased> why` holds the org.
Going down from N: `down <org>-N --apply` (container and registration), then lower N.
LIMITS: `limits NAME [memory SIZE] [cpus N]`, NAME one container (exampleorg-linux-2) or a group: <repo>, <org
lower-cased> (every runner of it) or `harbor` (every governance runner). Its own line beats its group's, which
beats the global `memory`/`cpus` lines (fleet and org runners only), then 1g / 1. A new container is made with
them. MEMORY is also kept: `list` reports an adopted container whose cap differs from an EXPLICIT value (a limits
or memory line; the 1g default is never enforced on what exists) as drift, and `up --apply` sets it live with
docker update (swap 2x, as docker run makes it): a raise even under a job, a lowering never under a job nor below
what the container uses now (refused, said, the rest carried on). A governance runner only with a limits line naming
it and --include-governance. CPUS are set at creation only: the governor moves them live (ci-governor.sh).
`list` ends with the memory budget: every runner container's cap against the VM's memory (docker info).
`mount REPO HOST-PATH CONTAINER-PATH` bind-mounts a host path into REPO's container when up creates it, ALWAYS read-only
(no mode field); `~` in the container path is the runner's HOME. A host path outside /Users/ or that does not exist is
refused (Colima shares only /Users into its VM: it would mount empty). list reports an adopted container's drift.
PER OWNER: the personal repos follow cache/runner-switch.json, an org follows cache/runner-switch.<ORG>.json
(ci-runner-switch.sh --org ORG, the org's minutes cap); each verdict is read, and trusted or not, on its own.
A container that exists is ADOPTED: up never recreates, stops or removes one, and never touches one running a job
beyond raising its memory live (the LIMITS rule above).
THE TOKEN goes GitHub -> a 0600 file -> docker --env-file -> deleted: never an argv, a URL, a log line or the screen.
NOTHING HERE READS OR WRITES BILLING: the minutes rule is ci-runner-switch.sh's, read from its cache.
`lost-rerun off` in CONF turns rerun-lost off (tick then skips it). Its lines are `[check:ci.lost-rerun]`, each naming the reason.
Findings: one `[check:ci.runners]` line in cache/checks.log per CHANGE (and per change of drift), cache/ci-runners.json.
POSIX sh, jq, gh, docker (HARBOR_TEST_GH and HARBOR_CI_DOCKER swap in fakes).
SPLIT (harbor#1060, docs/explanation/modularity; `lint-module-shape.sh --seam` called it earned): this file is the entry point, the
flags and the config; each verb group is a sourced lib beside it: ci-runners-fleet-lib.sh (the desired and actual
sets, `list`, mounts), -provision-lib.sh (`up`, `refresh`, `down`, the governance runners, the hook sync),
-github-lib.sh (`switch`, `rerun-refused`, `rerun-lost`), -watch-lib.sh (the alarm, the drift cache, `tick`).
```

## bin/ci-runners.sh, lines 119-119 (before this edit)

```text
the fleet file through the registry-aware reader beside this script (harbor#966)
```

## bin/ci-runners.sh, lines 122-122 (before this edit)

```text
the fleet CLI, a roots.tsv row read through the same reader (harbor#966)
```

## bin/ci-runners.sh, lines 140-140 (before this edit)

```text
the organisations with an org-level runner, and what a slug's scope is: OWNER/NAME is a repo, a bare ORG is an org
```

## bin/ci-runners.sh, lines 164-164 (before this edit)

```text
the verbs, one lib each (harbor#1060 split; each is sourced, never run): fleet view, container lifecycle, GitHub side, watching
```

