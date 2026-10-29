# Operator patch — CI that is safe to run on a public repo (harbor#1149, lane 3)

**STATUS: APPLIED by the CI workflow bundle (chore/ci-workflow-bundle, 2026-10-14),
before the visibility flip, which is the order it needs: a public repo with the old
selector still sends a fork PR to whatever `HARBOR_RUNNER` says. Edits 1 to 5 are in,
except that Edit 1's selector does NOT carry `|| 'github-hosted'`: unset
`HARBOR_RUNNER` on a PRIVATE repo still means `self-hosted`, as the file's header and
`bin/runner-switch.sh` read it, so this repo's runner does not move to billed minutes
the day it lands. A public repo is hosted through `!github.event.repository.private`
alone, unset variable or not. The operator's controls below are settings pages, not
files, and nothing here applies them.

Epic done-when 3: *a fork PR cannot run on a self-hosted runner.*

## The decision taken

**Default taken: GitHub-hosted runners for the public repo** (`ubuntu-latest` is
free for public repos). **Alternative rejected:** keep the self-hosted runner but
gate its jobs to the owner's own pushes with an `if:`. A job skipped by an `if:`
reports *skipped*, and a required check that is skipped reads as passed, so the
gate would let a PR through unjudged — the exact failure `governance.yml` already
documents for cancelled runs. A selector that picks the runner is not skippable;
a job guard is.

## What a YAML guard cannot do (read this before adding one)

A `pull_request` run from a fork executes **the workflow file from the fork's
merge commit**. The author of the PR controls that file, so an
`if: github.event.pull_request.head.repo.fork == false` written into
`governance.yml` is deleted by the same PR that wants to get past it. No edit to
this repository's workflow closes the fork-PR vector on its own. The selector
change below is defence in depth (the file *as merged* never names the Mac for a
public repo); the controls that actually close it are the operator's, in the
next section.

## The operator's controls (none of these are files)

Do all three before flipping visibility, in this order. An agent token cannot read
or set them (the admin endpoints returned 403 on 2026-10-13), so each is a
settings page the operator opens.

1. **Deregister the self-hosted runner from this repository.** Settings → Actions
   → Runners → the colima runner → Remove (or
   `gh api -X DELETE repos/VytCepas/harbor/actions/runners/<id>` with an admin
   token). A runner that is not registered to the repo cannot be picked by any
   workflow, whatever the YAML says. If the Mac must keep serving other private
   repos, register it to *those* repos or to an organisation runner group that
   excludes this one — never leave it attached to a public repository.
2. **Require approval for fork PR workflows.** Settings → Actions → General →
   *Fork pull request workflows from outside collaborators* → **Require approval
   for all outside collaborators**. First-time contributors are not enough: a
   returning contributor's second PR would run unapproved.
3. **Check `bin/runner-switch.sh` does not reset `HARBOR_RUNNER`.** It runs every
   300 s from `fleet-snapshot-refresh.sh` on the box and writes `self-hosted` into
   the repo variable when the account's *private-repo* Actions minutes pass 90 %
   of the allowance. After the flip harbor's own minutes stop counting (public
   repos are free) but other private repos still count, so the variable can still
   be set to `self-hosted` by the box. Edit 1 below makes the variable irrelevant
   on a public repo, so this is a belt check, not the control: after the flip run
   `sh bin/runner-switch.sh --print` and confirm it neither errors on a public
   repo nor is the only thing standing between a fork PR and the Mac.

If lane 2 chooses a **fresh public repo** rather than flipping this one, the
variable is unset there; Edit 1 treats unset as hosted, which is why that default
matters. `runner-switch.sh` hard-codes `VytCepas/harbor` (`REPO=`), so it will
not touch the new repo at all.

## How to verify (the done-when's verifier)

From a second GitHub account, fork the repository after the flip, push a trivial
commit to a branch of the fork and open a pull request against it. Approve the
run if GitHub asks. Then:

```
gh run list -R VytCepas/harbor --event pull_request --limit 1 --json databaseId
gh run view <databaseId> -R VytCepas/harbor --json jobs \
  --jq '.jobs[] | {name, runner_name, labels}'
```

Every job must show a hosted runner name (`GitHub Actions <n>` / `GitHub-Hosted`
labels, `ubuntu-latest`), and **none** may show the colima runner's name or the
labels `self-hosted`, `Linux`, `ARM64`.

Negative control, so the check is known to be able to fail: a fork PR cannot be
opened on a private repo, so do it with an ordinary branch PR while the repo is
still private and `HARBOR_RUNNER=self-hosted` — the same command must then list
the colima runner's name. If it does not, the command cannot see the difference
and its all-hosted answer after the flip proves nothing.

## Edit 1 — `governance.yml`: the six `runs-on` selectors

**Six identical lines**, at 117, 163, 284, 296, 313 and 327. Replace each.

Selects hosted when the repo is public, **or** when `HARBOR_RUNNER` (and the
dispatch input) is unset or says `github-hosted`. Only a private repo with the
variable set to something else reaches `self-hosted`. `!github.event.repository.private`
is also true when the payload carries no repository at all, so an unexpected event
fails toward the hosted runner, never toward the Mac.

Before (each of the six):

```yaml
    runs-on: ${{ fromJSON((inputs.runner || vars.HARBOR_RUNNER) == 'github-hosted' && '["ubuntu-latest"]' || '["self-hosted","Linux","ARM64"]') }}
```

After (each of the six):

```yaml
    runs-on: ${{ fromJSON((!github.event.repository.private || (inputs.runner || vars.HARBOR_RUNNER || 'github-hosted') == 'github-hosted') && '["ubuntu-latest"]' || '["self-hosted","Linux","ARM64"]') }}
```

Behaviour change on the still-private repo: an **unset** `HARBOR_RUNNER` used to
mean `self-hosted` and now means hosted (billed minutes). Check
`gh variable get HARBOR_RUNNER -R VytCepas/harbor` first; `runner-switch.sh`
normally keeps it set, so this should change nothing today. To keep unset =
self-hosted while private, drop `|| 'github-hosted'` from the After line.

## Edit 2 — `governance.yml`: a read-only token by default

Insert a top-level `permissions` block between the `on:` block and the first
comment of the concurrency section. Jobs inherit it; `verified` keeps its own
broader block (line 111), and no other job calls the API or pushes.

Before (lines 60–62):

```yaml
        options: [full, quick]

# A push to a PR branch fires this workflow TWICE (push + pull_request), and the
```

After:

```yaml
        options: [full, quick]

# The token every job inherits can read the repository and nothing else; a job that
# needs more says so itself (`verified` does). A public repo's fork PRs get a
# read-only token regardless, this keeps pushes to main and dispatches equally small.
permissions:
  contents: read

# A push to a PR branch fires this workflow TWICE (push + pull_request), and the
```

## Edit 3 — `governance.yml`: checkouts do not leave the token on disk

Three checkouts, at 119, 165 and 334. `persist-credentials: false` stops
`actions/checkout` writing the job token into `.git/config`, where any later step
(a suite, a script from the PR) can read it. Nothing in the workflow runs
`git fetch`, `git push` or `git ls-remote` after the checkout, and the second
checkout already fetches all history (`fetch-depth: 0`) so `origin/main` exists.

Lines 119 and 334, before (identical):

```yaml
      - uses: actions/checkout@v5
```

After (both):

```yaml
      - uses: actions/checkout@v5
        with:
          persist-credentials: false
```

Line 165, before (lines 165–167):

```yaml
      - uses: actions/checkout@v5
        with:
          fetch-depth: 0          # suite-select diffs against the base; lint C2 needs main..HEAD
```

After:

```yaml
      - uses: actions/checkout@v5
        with:
          fetch-depth: 0          # suite-select diffs against the base; lint C2 needs main..HEAD
          persist-credentials: false
```

**Failure to watch for:** a suite or script that fetches from the remote after the
checkout now fails with an authentication error on a *private* repo (it still works
anonymously once the repo is public). If `suites` goes red with `could not read
Username` or `Authentication failed`, that step needs its own explicit credential
rather than the persisted one; do not revert the flag to silence it.

## Edit 4 — `governance.yml`: the header stops claiming the old default

Lines 16 and 20–21 describe `self-hosted` as the default and as where *any* value
lands; line 33–34 says unset falls back to self-hosted. All three become false
with Edit 1. Replace them in place.

Before (line 16):

```yaml
#   self-hosted (default)  a GitHub runner in a Linux container on the operator's
```

After:

```yaml
#   self-hosted (private)  a GitHub runner in a Linux container on the operator's
```

Before (lines 20–21):

```yaml
#                          holds no ~/.claude. Any value but `github-hosted` lands
#                          here, so bin/runner-switch.sh needs no change.
```

After:

```yaml
#                          holds no ~/.claude. Only a PRIVATE repo with HARBOR_RUNNER set
#                          to anything but `github-hosted` lands here; a public repo never does.
```

Before (lines 33–34):

```yaml
#   repo-wide — `gh variable set HARBOR_RUNNER --body github-hosted` (or
#               `self-hosted`); unset falls back to self-hosted
```

After:

```yaml
#   repo-wide — `gh variable set HARBOR_RUNNER --body github-hosted` (or
#               `self-hosted`); unset, and every public repo, falls back to github-hosted
```

## Edit 5 — `stranger-install.yml`: the stale header, and the same checkout flag

The file lives in `.github/workflows/` (moved there in `8f5404e9`), so lines 1–2,
which say it is a draft that must still be moved there, are wrong.

Before (lines 1–2):

```yaml
# stranger-install (harbor#1149, #831) - DRAFT, MANUAL TRIGGER ONLY. Not under .github/workflows/ because
# an agent cannot write there; move it to .github/workflows/stranger-install.yml to activate.
```

After:

```yaml
# stranger-install (harbor#1149, #831) - MANUAL TRIGGER ONLY (workflow_dispatch). Lives here since #1149; an agent
# cannot write under .github/workflows/, so edits to this file arrive as operator patches (patches/README.md).
```

Before (line 27):

```yaml
      - uses: actions/checkout@v5
```

After:

```yaml
      - uses: actions/checkout@v5
        with:
          persist-credentials: false
```

Its `runs-on` already defaults to `ubuntu-latest` and `permissions: contents: read`
is already top-level, so nothing else changes. The `self-hosted` choice in its
dispatch input stays selectable by the owner only on a private repo; with control 1
above there is no runner for it to pick on a public one.

## Prove each before-block matches the file (do this first)

`grep -n -F` of the first line of each Before block must print the cited line
number(s). Run from the repository root:

```
grep -n -F "runs-on: \${{ fromJSON((inputs.runner || vars.HARBOR_RUNNER) == 'github-hosted'" .github/workflows/governance.yml
grep -n -F "        options: [full, quick]" .github/workflows/governance.yml
grep -n -F "      - uses: actions/checkout@v5" .github/workflows/governance.yml
grep -n -F "#   self-hosted (default)  a GitHub runner" .github/workflows/governance.yml
grep -n -F "#                          holds no ~/.claude. Any value but" .github/workflows/governance.yml
grep -n -F "#   repo-wide " .github/workflows/governance.yml
grep -n -F "# stranger-install (harbor#1149, #831) - DRAFT" .github/workflows/stranger-install.yml
grep -n -F "      - uses: actions/checkout@v5" .github/workflows/stranger-install.yml
```

Expected lines: `117 163 284 296 313 327`; `60`; `119 165 334`; `16`; `20`; `33`; `1`; `27`.
A different number means the file moved since this patch was written; re-read the
block against the file before applying, do not apply on faith.

## After applying

- `sh bin/lint-conventions.sh` and the workflow-shape suites (`tests/floor/floor.shards-test.sh`
  checks the `floor` relay against the pool) stay green; run the selected suites.
- Push to a branch and watch one `pull_request` run: on the still-private repo every
  job lands on the runner `HARBOR_RUNNER` names; `gh run view <id> --json jobs` lists it.
- After the visibility flip, run the fork-PR verification above and keep its output
  with the epic.
- **Failure to watch for:** a job stuck `Waiting for a runner` means the selector
  returned a label set no registered runner has — after control 1 that is expected
  for `self-hosted` and a bug for anything else.
