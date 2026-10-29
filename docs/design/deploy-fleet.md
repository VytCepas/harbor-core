# Ship — merge and deploy the fleet overnight, restore a bad deploy, report in the morning

**Status:** harbor#1060, harbor#1018. `harbor ship night|deploy`, one POSIX `sh` tool (`bin/deploy-fleet.sh`), built to
**ship contract v1.2** §3, §5, §5a and §5b (the runner). The approval gate (`gate-classify.sh`, `gate-approve.sh`,
`gate-queue.sh`, the kill switch) is the contract's §2, §4 and §6, built separately; this tool calls it only through the
contract's CLI, at the installed paths §5b.9 pins. The suites are `tests/ci/deploy-fleet/`; every rail below has a
mutant in them that goes red when the rail is removed.

**Universal.** Any repo opts in by adding one file, `.agents/ship.conf`, on its default branch. No code path in the
runner names a repo, a tool or a register of its own (`fleet.test.sh` greps for it, and the grep has its own
red-proof). The suites run two different fake repos with no harbor file in either, one deploy-capable on a default
branch called `trunk` and one merge-only on `main`, end to end.

## The commands

```
harbor ship night [--plan <file>]... [<owner/repo>...]
harbor ship deploy <owner/repo> --sha <sha> [--approved]
```

- `night` runs every fleet repo that opts in, or only the repos named, or only the repos the given merge-stack plans
  name ([merge-stack.md](merge-stack.md), the plan format; its `checkout` line picks the checkout).
- `deploy` is one repo's deploy stage at `<sha>`, with the same verify and auto-restore. **`--approved` belongs to
  `gate-approve.sh` alone**: it lets a protected change, a repo with no baseline, a rolled-back commit or a manifest
  with no verify through. The runner takes it only while the click's one-shot token
  `<config>/.helm-approvals/approved/deploy-<owner>_<name>-<sha12>` exists, and deletes it; it refuses it when
  `SHIP_UNATTENDED=1` (§5a.4), and the approval gate's floor guard refuses every other spelling. Without it, a
  protected change is queued.
- **Installed** by the floor component beside the gate tools, as `<config>/bin/deploy-fleet.sh`, with one allow rule,
  `Bash(<config>/bin/deploy-fleet.sh night*)` (floor-deny, removed by floor-uninstall). No rule names `deploy`.
- Exit 0 when nothing failed (queued work, a skipped red PR, a PR left for the next night and the kill switch are not
  failures), 1 when a problem was reported (a rollback, a failed plan or merge, an unknown repo), 2 a usage error,
  143 when a signal stopped it.

## What is read where (§5b.11)

Opt-in, the manifest and the protected register are read from **`origin/<default branch>`**, never from the working
tree: the checkout of a merge-only repo is never pulled, so its files can be any age. The default branch is what
`git ls-remote --symref origin HEAD` names. The classifier is handed a scratch root holding the manifest and the
register exactly as origin has them. A merge-stack `merge-check.sh` comes from merge-stack's own install (§5a.6),
so a repo needs none of harbor's scripts.

**The recorded baseline is checked twice before it is trusted.** It lives in `<config>/.helm-ship/`, which the floor
guards (#1127), and each file carries `.sum`, the sha256 of the rest: a file that fails it is not trusted and the
deploy is queued. The sum is not keyed, so it catches an edit that did not recompute it; the guard is what stops a
deliberate one. And when the manifest has `deployed`, the live install's commit must equal the recorded sha: a
restore outside the runner (a manual `restore.sh`) undoes a deploy without telling it, so a disagreement means no
trusted baseline, and the deploy is queued for the click.

## One night

For each repo, in `owner/name` order:

1. **Merge.** The PRs are a plan's `pr` lines, else the open PRs labelled `ship:auto`, lowest number first. For each:
   - The head GitHub reports must equal the fetched `pull/N/head`, or the PR is not judged.
   - It gets a merge-stack plan of its own, **pinned**: `pr N head <sha>` (§5b.10). `merge-stack check` exits 1 →
     **skipped red**, with merge-stack's reason, never handed to `merge`.
   - Its changed paths against its merge-base with `origin/<default>`, a rename's old and new path and a deletion's
     path, go to `gate-classify.sh`. Protected → **queued** through `gate-queue.sh add`.
   - Otherwise `merge-stack merge`, which merges only that head. If the head moved, merge-stack reports
     `needs-rebase` and never syncs: the PR is **left for the next night**, when its new head is classified again.
2. **Deploy**, when the manifest has `apply`. The main checkout must be clean and on the default branch; it is
   fast-forwarded to `origin/<default>`. The change is every path between the **last deployed commit** and that sha.
   It is **queued** when the manifest has no `verify` or no `restore`, when no commit was ever deployed, when the last
   one is not an ancestor, when the range contains a rolled-back commit, or when the classifier says a path is
   protected. Otherwise: `plan`, then `apply` (which snapshots and writes the id to `$SHIP_SNAPSHOT`), then every
   `verify`. All green → the deployed commit is recorded.
3. **Red verify, a failed or timed-out apply, or a signal after apply started.** `restore` with **this run's**
   snapshot id, every `verify` again, the commit recorded as rolled back, a finding filed, the report written, and
   **the whole night stops**: no further repo, and no unattended merge or deploy for 16 hours (§5a.7).

The kill switch is read at the start, before every merge, and before each deploy's plan and apply. A restore after a
red verify still runs: it undoes, it does not deploy.

## Bounded commands and signals (§5a.5)

Every manifest command runs under a timeout, in its own process group (perl's `setpgrp`; perl is required, and a repo
is not deployed without it). Defaults: plan 600 s, apply 1800 s, verify 600 s, restore 1800 s; the manifest's
`timeout.<cmd> <secs>` overrides one. On timeout the whole group gets TERM, then KILL 2 s later. A timed-out `verify`
is red, a timed-out `apply` is a failed apply (restore follows), and a timed-out `restore` is reported as such and
stops the night. A TERM, INT or HUP to the runner kills the running command's group; once `apply` has started it
then restores this run's snapshot, reports, and exits 143. A signal during a restore lets the restore finish.

## The rails

| Rail | How | Red-proof (`tests/ci/deploy-fleet/`) |
|---|---|---|
| A red PR is never merged | `merge-stack check`'s exit; merge-stack's own preflight again in `merge` | `merge` MR1; merge-stack's report removed merges it |
| The head that merges is the head classified | the plan's `pr N head <sha>`; a moved head is `needs-rebase`, left a night | `merge` MP1 (the review's push-after-classify attack) |
| The fetched head is the reported head | compared before anything is judged | `merge` MC |
| A protected PR is queued, never merged unattended | classifier exit 1, a classifier that cannot answer, or a path git had to quote | `merge` MR2 |
| Opt-in and the register come from origin | `git show origin/<default>:…`, never the tree | `merge` MO (manifest deleted on origin), MR (register gained `docs/*`) |
| A protected deploy is queued | the classifier over the deploy change | `deploy` MD1 |
| No `verify` or no `restore` → never deployed unattended | the manifest check | `deploy` MD3 |
| A commit with no baseline is queued | no recorded commit, never a fallback | `deploy` MD2 |
| A recorded commit that is not an ancestor is queued | `merge-base --is-ancestor` | `deploy` MA |
| The default branch is origin's, never `main` | `ls-remote --symref` | `deploy` MDB |
| `--approved` never in an unattended run | refused when `SHIP_UNATTENDED=1` | `deploy` MU |
| The kill switch stops the run | `<config>/.harbor-autoship.off`, read before each step | `merge` MR3, and switched on mid-run; `deploy` MK (between plan and apply) |
| A hung command never hangs the night | per-command timeout, process-group kill | `signal` MT |
| A signal after apply restores | the TERM/INT/HUP trap | `signal` MS |
| Restore only targets this run's snapshot | a fresh, empty `$SHIP_SNAPSHOT` per apply; no id → not restored | `rollback` MB5 |
| A reused snapshot id is refused (§5b.13) | an id equal to the recorded one is not this run's | `rollback` MF |
| At most one rollback a night | a rollback stops the run and every unattended run for 16 hours | `rollback` MB2, MB3 |
| A rolled-back commit is never applied unattended again | queued until `approve deploy` moves the baseline past it | `rollback` MB4 |
| The deployed sha moves only after a green verify | recorded only on the all-green branch | `rollback` MB1 |
| A linked worktree is never the checkout | `--git-dir` must equal `--git-common-dir`, whatever the name | `fleet` ME |
| `--approved` needs the click's token, once | `<config>/.helm-approvals/approved/<id>`, deleted on use | `deploy` MTK |
| An edited baseline is not trusted | `.sum` over the state; mismatch → queued | `deploy` MSUM |
| A restore outside the runner is seen | the manifest's `deployed` must equal the recorded sha | `deploy` MLIVE |

## The manifest: `.agents/ship.conf` on the default branch

One `key value` line each; a `#` at the start of a line or after whitespace starts a comment. A command keeps its
own spacing.

| key | meaning | default |
|---|---|---|
| `repo` | `owner/name`; must equal the checkout's `origin` | required |
| `workflow` | the CI workflow file that gates a merge | every workflow on the head |
| `protected` | path of the repo's protected-paths register (read by the classifier) | `.agents/protected-paths.tsv` |
| `plan` | deploy dry run; exit 0 = the plan is sane; writes nothing | none |
| `apply` | unattended deploy; **must snapshot first** and write the snapshot id to the file in `$SHIP_SNAPSHOT` | none (merge-only repo) |
| `verify` | a health check; exit 0 = healthy. Repeatable, and all must pass | none (then a deploy is never autonomous) |
| `restore` | puts back the snapshot whose id is in `$SHIP_SNAPSHOT_ID` | none (then a deploy is never autonomous) |
| `deployed` | prints the commit the live install is at (first token); the recorded sha is trusted only while it agrees | none (a restore outside the runner is not seen) |
| `timeout.<cmd>` | seconds for `plan`, `apply`, `verify`, `restore` or `deployed` | 600, 1800, 600, 1800, 60 |

Commands run from the repo's main checkout through `sh -c`, with `SHIP_UNATTENDED=1`, `SHIP_REPO=<owner/name>`,
`SHIP_SNAPSHOT=<file>` and, for `restore` only, `SHIP_SNAPSHOT_ID=<id>`. A snapshot id is one token of
`[A-Za-z0-9._:/@+-]`, new for this run; anything else counts as no id. The manifest is repo content, so it is itself
protected.

## Opting a repo in

1. Add `.agents/ship.conf` and `.agents/protected-paths.tsv` (`glob<TAB>class<TAB>reason`) in a PR; the manifest,
   the register and `.github/` are always protected, so it merges with the operator's click.
2. The repo must be in the fleet snapshot (`fleet.yaml`, as `ci-runners.sh` reads it), with one main checkout: a
   linked worktree is never used, and of two clones the one named after the repo wins. Otherwise name it in a plan.
3. For merges, merge-stack's opt-in: `.agents/required-checks.tsv` or branch protection ([merge-stack.md](merge-stack.md)).
4. Label PRs `ship:auto`. The first deploy is always queued: approving it sets the baseline.

An example for a repo that is not harbor (documentation only):

```
# .agents/ship.conf: acme/storefront, a static site behind a CDN
repo      acme/storefront
workflow  ci.yml
plan      make deploy-plan
apply     make deploy SNAPSHOT_TO="$SHIP_SNAPSHOT"      # uploads the previous release id first
verify    make healthcheck                             # the live site answers 200
verify    make smoke
restore   make rollback RELEASE="$SHIP_SNAPSHOT_ID"
timeout.verify 120
```

A merge-only repo is two lines: `repo owner/name` and, if it has several workflows, `workflow ci.yml`.

## State, queue and report

| What | Where |
|---|---|
| Last deployed commit, its snapshot, the rolled-back commits, and `.sum` | `<config>/.helm-ship/<owner>_<name>.json` (guarded) |
| The last rollback (stops unattended runs for 16 h), with its sha256 | `<config>/.helm-ship/last-rollback` (guarded) |
| The lock, the run log, and every plan, apply, verify, restore and merge-stack log | `~/.local/state/harbor/ship/` (`backups/deploy-fleet/<ts>/`) |
| Queued approvals | written only by `gate-queue.sh add <kind> <owner/repo> <sha> [<pr>] --reason <text>`, id `<kind>-<owner>_<name>[-<pr>]-<sha12>` (§5a.2); the gate emits `approval.open` |
| The morning report | `~/Deliverables/<date>-ship/REPORT.md` (`HARBOR_DEPLOY_FLEET_REPORT_DIR` moves it): one section per run, newest last: merged, deployed (sha range), rolled back (failing check, log, snapshot), skipped red, left for the next night, queued (each with its `gate-approve.sh` command and queue id), problems |
| The check | one `[check:ship]` line per run in `~/.claude/cache/checks.log`, and the receipt `<config>/cache/checks/ship.json` (CHECKS.md `ship`) |

A finding is the receipt: red over `<owner/name>:<stage>` (`rollback`, `plan`, `merge`, `queue`, `checkout`, …), which
`findings.sh reconcile` files as `check/ship`. It stays red while a rollback stops the night.

## Not handled, on purpose

- **Side effects outside the snapshot** are the repo's `restore`'s business; the runner cannot see them.
- **A signal during a restore** waits for the restore; a second signal then is ignored until it ends.
- **Scheduling.** Nothing runs `ship night` on a schedule; a schedule needs the operator's yes.
