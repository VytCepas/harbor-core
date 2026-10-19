# Operator patch — stop the workflow firing twice (CI-1 follow-up, harbor#150)

**STATUS: APPLIED.** The functional line by the operator on 2026-08-06: the `on:`
block reads `push: branches: [main]`. The comment block below it by the CI
workflow bundle (chore/ci-workflow-bundle, 2026-10-14), shortened: the `on:` block
now carries the reasoning, and this file keeps the measurements.

Until it landed, no pull request in this repo could be merged through branch
protection. That was measured, not predicted, and it was measured three times.

## The defect

Branch protection went on `main` on 2026-08-06 with two required contexts,
`conventions linter` and `security-floor suite`. PR #153 then passed every job
and still reported `mergeable_state: blocked`. Asking GitHub which required
checks it counts:

```
$ gh pr checks 153 --required
conventions linter      pass   1m38s   .../runs/31103305313   ← pull_request run
security-floor suite    pass   6m8s    .../runs/31103305313
conventions linter      fail   24s     .../runs/31103255469   ← push run, CANCELLED
security-floor suite    fail   24s     .../runs/31103255469
```

**A cancelled check run scores as `fail`, and it never clears.** Run
`31103255469` was cancelled after 24 seconds — it did not fail, it was
superseded — but branch protection reads the required context as failing and
blocks the merge.

The cancellation is by design. `on:` fires on both `push` and `pull_request`, so
a push to a PR branch starts the workflow **twice**; the `concurrency` block puts
both runs in one group keyed on the head branch, so one is cancelled. The comment
above that block already documents the double-fire and argues for cancelling the
loser. That reasoning was correct for a year and stopped being correct the moment
required status checks existed.

**It recurs on every push.** Pushing an update to #153 produced run
`31107889224` (`push`) cancelled by `31107892653` (`pull_request`) within
seconds, reproducing the block on the new SHA. There is no way to wait it out.

## The fix

```yaml
on:
  push:
    branches: ["**"]
  pull_request:
  workflow_dispatch:
```

becomes

```yaml
on:
  # ONLY `main`, and this is load-bearing rather than tidiness. With
  # `branches: ["**"]` a push to a PR branch fires this workflow TWICE — once
  # here and once on `pull_request` — and the concurrency block below then
  # cancels one of them. A CANCELLED check run scores as FAILING against a
  # required status check and never clears, so from the day branch protection
  # went on, every PR was unmergeable while every suite passed. Measured on
  # harbor#153, twice, on two different SHAs.
  #
  # Nothing is lost by narrowing it: `pull_request` already covers every branch
  # that is proposed for merge, and a branch with no PR has no gate to satisfy.
  # What is gained beyond the fix is that a push to a PR branch now costs ONE
  # run instead of two-minus-a-cancellation, on a single serialised runner.
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:
```

Leave the `workflow_dispatch` input block and everything below `on:` unchanged.

## Why the concurrency block stays exactly as it is

It is still doing real work, just not this work:

- On `main` it queues rather than cancels (CI-1), so every merged commit gets a
  completed verdict.
- On a PR branch, pushing twice in quick succession still produces two
  `pull_request` runs, and cancelling the superseded one is still right — that
  run measured a commit that no longer exists.

What changes is only that a `push` run and a `pull_request` run for the same
commit stop racing each other, because the `push` run no longer exists.

## After applying

The immediate unblock for a PR already carrying a cancelled check is to re-run
the cancelled run so its check runs complete:

```sh
gh run rerun <cancelled-run-id>
```

Then, on the next PR opened after this patch:

| Check | Expect |
|---|---|
| `gh run list --branch <branch>` | exactly ONE run per push, event `pull_request` |
| `gh pr checks <n> --required` | two rows, both `pass` — no `fail` twin |
| `gh pr view <n> --json mergeStateStatus` | not `BLOCKED` when the suites are green |

**The failure to watch for** is a PR whose checks never appear at all. That is
what happens if `pull_request` is narrowed too — a required context that never
reports leaves the PR waiting forever, which is the deadlock this patch must not
trade the current one for. `pull_request` stays unfiltered.
