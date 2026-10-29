# Tests and CI on this box

Everything an agent needs to run tests and read CI here without rediscovering it. Each claim names the command or
file that re-derives it; where none is named, the claim was observed in a session and says so.

## One CPU budget

Local suites and CI jobs share one Mac. `bin/ci-governor.sh` budgets cores for both (header: `sed -n 2,60p bin/ci-governor.sh`).

- `sh bin/ci-governor.sh run -- <cmd>` runs `<cmd>` once a local slot is free. **Waiting is expected**, not a hang; at its
  deadline it runs anyway and says so. `sh bin/ci-governor.sh status` shows the budget, the runners and the slots.
- The Linux runners are Colima containers named `*-linux` (or `*-linux-<N>`), throttled live with `docker update --cpus`.
  Which classes yield to the rest is the `low_priority` list in the governor's header.
- **Never kill another session's run.** An unscoped `pkill` by one session has killed another's suite runs before (exit 144,
  `xargs: Terminated`). Scope any kill to a pid you started.

## Suites and lint

- Suites: `sh bin/test-suite-run.sh --select` (the changeset's suites; every uncertainty selects all). Flags: `sed -n 2,17p bin/test-suite-run.sh`.
  Never a hand-rolled `xargs` loop over the manifest (`contracts/suites.txt`): one ran nothing and reported green.
- Lint: `sh bin/lint-conventions.sh`.

## Where CI runs

A harbor PR is mirrored by `.github/workflows/public-ci.yml` (`bin/ci-mirror.sh`) to the public `VytCepas/harbor-core`, where
governance CI runs on the self-hosted `harbor-linux` runners. The result returns as the `public-ci` status on the PR head,
which is harbor's required check (`grep harbor contracts/required-checks.tsv`). Other repos' required checks are in the same file.

## Identity

Observed in a session, not derivable from the repo:

- Agent `gh` and `git` calls run as a GitHub App. A command the operator types with a leading `!` in Claude Code inherits
  `CLAUDECODE=1` and also runs as the App; `! /opt/homebrew/bin/gh ...` reaches the operator's own `gh`.
- The App is refused: pushing any commit that touches `.github/workflows/` (no `workflows` permission), even through `! git push`,
  so the operator pushes those from a real terminal; `gh workflow run` in some repos (HTTP 403 "Resource not accessible by
  integration"); reading repo Actions variables and runners, and branch protection (403); merging (branch protection wants the
  expected app or code owner, so merges go to the operator).
- Hand the operator exact commands in run order, each with the one clause saying why it is theirs.

## Nightly-only jobs

Jobs gated on a cadence input (for example mutation tests in idea-to-live) are dispatched with
`gh workflow run ci.yml --ref <branch> -f cadence=nightly`, in repos where the App may dispatch.

## A flipping local result is the machine

Observed: mutmut on macOS reported 1292 mutants as "segfault" (SIGSEGV, exit -11), and re-running one gave "survived" then
"segfault". A result that differs between identical runs is not a finding. Re-run in the repo's Linux CI before concluding.

## Claude Code sandbox

Observed: `git worktree add` and other `.git/config` writes need the sandbox off; reads of `.env.*` are denied
(`project-init upgrade` reads `.env.example`); `open` is blocked. A suite that clones the repo can fail only inside the
sandbox: rerun outside it before believing a red.

## Each repo's own instructions

Scaffolded repos carry a "Tests and CI" section in `AGENTS.md`. Some workload repos carry local-only `CLAUDE.md`
files. Harbor's is in [AGENTS.md](../../AGENTS.md).
