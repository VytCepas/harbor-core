# Operator patch — CI latency: gate runner, fail-fast freshness, push-run base, suite cache (harbor#1286, #1287, #1289, #1172, #1288)

**Why this is a file and not a commit.** `permissions.deny` covers
`.github/workflows/**`, deliberately: an agent may not rewrite the gate that
judges it. See [README.md](./README.md).

Measured 2026-10-17 over the last 100 governance runs: the long tail is
queueing, not tests (run 38871574850: shards done at +38 min, run done at +93,
`conventions linter suite` waited 55 min for 8 s of work); 7 of 12 failed PR
runs were stale generated files found only after the 15–20 min pool; every push
run that ran the pool ran it in full.

## Before applying — ORDER MATTERS

Part A sends jobs to runner labels that do not exist yet. Applied first, those
jobs wait forever. Do these first, in this order:

1. Add a line `gate 1` to `$CLAUDE_CONFIG_DIR/.harbor-ci-runners`, then
   `sh bin/ci-runners.sh up --apply --include-governance` (creates and registers
   `harbor-gate`). Check: `sh bin/ci-runners.sh list` shows `harbor-gate` online.
2. Give the existing governance runners the `harbor-pool` label (the in-session
   `gh` runs as the App and cannot edit runner labels). Get the ids from
   `sh bin/ci-runners.sh list --json`, then for each governance runner id:
   `/opt/homebrew/bin/gh api -X POST repos/VytCepas/harbor/actions/runners/<id>/labels -f 'labels[]=harbor-pool'`
3. Check: both `harbor-linux` runners list `harbor-pool`, `harbor-gate` lists `harbor-gate`.

Parts B–D have no prerequisite and can be applied alone.

## A · Small jobs on the gate runner, shard legs on the pool (#1286)

Every job in `.github/workflows/governance.yml` has this same `runs-on` line:

```yaml
    runs-on: ${{ fromJSON((!github.event.repository.private || (inputs.runner || vars.HARBOR_RUNNER) == 'github-hosted') && '["ubuntu-latest"]' || '["self-hosted","Linux","ARM64"]') }}
```

- In job **`suite-shard`** only, replace `'["self-hosted","Linux","ARM64"]'` with
  `'["self-hosted","Linux","ARM64","harbor-pool"]'`.
- In jobs **`verified`, `suites`, `conventions`, `lint-suite`, `floor`, `status`**,
  replace `'["self-hosted","Linux","ARM64"]'` with
  `'["self-hosted","Linux","ARM64","harbor-gate"]'`.

The hosted half (`'["ubuntu-latest"]'`) is unchanged everywhere. Required check
names are job names, and no job is renamed, so branch protection is untouched.

## B · A stale generated file fails before the pool (#1287)

In job `suite-shard`, replace:

```yaml
          { echo '### change class'; echo '```'; cat "$RUNNER_TEMP/verdicts.txt"; echo '```'; } >> "$GITHUB_STEP_SUMMARY"
      # CONTINUE-ON-ERROR, NOT `|| :`: the outcome is what `conventions linter`
```

with:

```yaml
          { echo '### change class'; echo '```'; cat "$RUNNER_TEMP/verdicts.txt"; echo '```'; } >> "$GITHUB_STEP_SUMMARY"
      # A stale generated file fails here, before the pool (harbor#1287). Shard 1 only.
      - name: Generated files are current (fresh-check)
        if: ${{ matrix.shard == 1 }}
        run: sh bin/doc-fresh-verify.sh
      # CONTINUE-ON-ERROR, NOT `|| :`: the outcome is what `conventions linter`
```

## C · A push run diffs from the merged PR's merge-base (#1289)

1. In job `verified`, replace:

```yaml
      verified: ${{ steps.v.outputs.verified }}
```

with:

```yaml
      verified: ${{ steps.v.outputs.verified }}
      base: ${{ steps.v.outputs.base }}
```

2. In job `suite-shard`, replace:

```yaml
      HARBOR_BASE: origin/${{ github.base_ref || 'main' }}
```

with:

```yaml
      HARBOR_BASE: ${{ (github.event_name == 'push' && needs.verified.outputs.base) || format('origin/{0}', github.base_ref || 'main') }}
```

An empty `base` (no PR found, API failure, anything doubtful) falls back to
today's value, so the full pool still runs on a direct push.

## D · The shard timeout comment matches the new table (#1172)

In job `suite-shard`, replace:

```yaml
  # TIMEOUT. 33 = 1.5 x 21.7 min, shard 1 predicted at the slowest condition
  # measured on 2026-10-13: three suites per CPU, where suites ran up to 2.73x
  # slower than in the run tests/suite-durations.tsv was recorded from. The
  # prediction is 1139 s of recorded suites x 2.73 / 3 at a time = 1037 s, plus
  # lint-conventions 247 s, dash 16 s and setup 5 s, each the slowest measured.
  # Re-derive it from the `shard K/N` and `wall` lines once sharded runs exist.
```

with:

```yaml
  # TIMEOUT. 33 min stays. Since harbor#1172 tests/suite-durations.tsv holds the
  # MEDIAN in-CI time per suite over 85 sharded-era logs (so CI contention is
  # already in it, not a 2.73x factor on top) plus a lint-conventions row that
  # pre-loads shard 1: the full manifest predicts 2954 s per leg / 3 at a time
  # = 16.4 min, so 33 is 2x. Re-derive with `sh bin/test-suite-run.sh --plan --shard 1/2`.
```

## E · The suite cache can be switched on (#1288, opt-in)

In job `suite-shard`, replace:

```yaml
      HARBOR_LEVEL: ${{ (inputs.level || vars.HARBOR_CI_LEVEL) }}
```

with:

```yaml
      HARBOR_LEVEL: ${{ (inputs.level || vars.HARBOR_CI_LEVEL) }}
      HARBOR_SUITE_CACHE: ${{ github.event_name != 'push' && vars.HARBOR_SUITE_CACHE || '' }}
```

This changes nothing until the repo variable exists: on with
`gh variable set HARBOR_SUITE_CACHE --body 1`, off with
`gh variable delete HARBOR_SUITE_CACHE`. Push runs never use it, so `main`
keeps a full verdict. Contract and limits: `contracts/suite-cache.md`.

## After applying — what proves it landed

- **A:** on the next PR run, `gh api repos/VytCepas/harbor/actions/runs/<id>/jobs`
  shows the small jobs with `runner_name` `harbor-gate`, and their
  `started_at - created_at` under 1 min even while another run's shards are busy.
- **B:** a PR with a stale `docs/generated/status.md` fails the step "Generated files are
  current" within about a minute of the shard starting.
- **C:** a push run whose PR was behind main logs `base=<40-hex sha>` in
  "The changeset this run is judging", and the selection is smaller than the
  full manifest.

## Failure to watch for

- **A applied before the runners are labelled:** jobs sit in `queued` with no
  runner. Fix by doing the "Before applying" steps; nothing else is wrong.
- **`harbor-gate` down:** the small jobs wait. `[check:ci.runner-alarm]` fires
  after a gate-labelled job is queued over 10 minutes; restart the container.
- **B blocks a PR for a file it cannot regenerate in CI:** `doc-fresh-verify.sh`
  treats a check that cannot judge (exit not 0/1) as WARN, not FAIL; a FAIL
  names its fix command.
