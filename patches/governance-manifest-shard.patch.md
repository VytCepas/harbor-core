# Operator patch — shard `suite-manifest` so it stops hitting its 20-minute limit

**STATUS: OBSOLETE (2026-10-14).** It shards the `suite-manifest` job, which the one-pool workflow removed (`grep -c suite-manifest .github/workflows/governance.yml` prints 0). Sharding is now the `suite-shard` matrix of the CI workflow bundle (harbor#1172, harbor#1240). Kept for its measurements; nothing in it applies to the current workflow.

**Why this is a file and not a commit.** `permissions.deny` covers
`.github/workflows/**`, deliberately: that deny exists so an agent cannot rewrite
the gate that judges it. See [README.md](./README.md).

Found by harbor#669 (2026-09-24). Evidence in brief:

- **58 of the 69 suites** in `contracts/suites.txt` run one after another in
  this one job. It was added on 2026-08-01 with a comment saying the correct
  count was 0, and it kept the 20-minute limit it had when it ran nothing.
- **The slowest passing run took 19.2 minutes**, 1,143 s of it suites (run
  35786448317).
- **Across the last 100 runs, 7 to 22% of heavy suite jobs were cancelled at
  the limit.** Contention on the shared Mac raises that figure; the runner count
  does not explain it.

## The edit

One job, `suite-manifest`, in `.github/workflows/governance.yml`. Two
replacements. Nothing else in the file changes, and no other job `needs`
`suite-manifest`: the `status` job needs `[preflight, classify, floor, fast]`.

### 1 · The job header

Replace:

```yaml
  suite-manifest:
    name: manifest suites (not already wired to a job)
    timeout-minutes: 20
    needs: [preflight, classify]
```

with:

```yaml
  suite-manifest:
    name: manifest suites, shard ${{ matrix.shard }} of 3 (not already wired to a job)
    timeout-minutes: 20
    needs: [preflight, classify]
    # harbor#669. Three shards of the same loop, each running every 3rd suite, so
    # the job's time is a third of the manifest's instead of all of it. The
    # 20-minute limit stays: it is the hang guard (#658 was a 4-hour hang), and
    # sharding is what keeps a healthy run well inside it as suites are added.
    strategy:
      fail-fast: false
      matrix:
        shard: [0, 1, 2]
```

### 2 · The loop

Replace the `run: |` body of the step `run manifest suites with no dedicated job`:

```sh
          set -eu
          ran=0
          while IFS= read -r s; do
            case "$s" in ''|\#*) continue ;; esac
            # `--run $s`, not `bin/$s`: the dedicated jobs no longer name
            # the suite path. Getting this wrong runs everything twice and still
            # reports success, which is why it is called out rather than left to
            # be noticed.
            if grep -q -- "--run $s" .github/workflows/governance.yml; then
              printf 'skip %s (has its own job)\n' "$s"
              continue
            fi
            printf '== %s\n' "$s"
            sh bin/test-suite-select.sh --run "$s"
            ran=$((ran + 1))
          done < contracts/suites.txt
          printf '\nmanifest suites considered: %d\n' "$ran"
```

with:

```sh
          set -eu
          ran=0; i=0
          while IFS= read -r s; do
            case "$s" in ''|\#*) continue ;; esac
            # `--run $s`, not `bin/$s`: the dedicated jobs no longer name
            # the suite path. Getting this wrong runs everything twice and still
            # reports success, which is why it is called out rather than left to
            # be noticed.
            if grep -q -- "--run $s" .github/workflows/governance.yml; then
              printf 'skip %s (has its own job)\n' "$s"
              continue
            fi
            # harbor#669: round-robin over the manifest's own order. Counted
            # AFTER the dedicated-job skip, so every shard sees the same index
            # for the same suite and each suite lands in exactly one shard.
            i=$((i + 1))
            [ $(( (i - 1) % 3 )) -eq ${{ matrix.shard }} ] || continue
            printf '== %s\n' "$s"
            sh bin/test-suite-select.sh --run "$s"
            ran=$((ran + 1))
          done < contracts/suites.txt
          printf '\nmanifest suites considered by shard %s of 3: %d of %d\n' "${{ matrix.shard }}" "$ran" "$i"
```

## After applying

1. **Every suite runs exactly once.** On the first PR after this lands, open the
   three shard logs. Each ends with `manifest suites considered by shard N of 3:
   <k> of <total>`. The three `<k>` must **sum to `<total>`**, and `<total>` must
   be the same in all three. At the time of writing it is 58, so each `<k>` is 19
   or 20.
2. **Nothing requires the old check name.** Branch protection on `main`
   requires `conventions linter`, `security-floor suite` and `conventions linter
   suite`. The manifest job is not among them, so renaming it blocks nothing.
   Confirm with `sh bin/gate-merge-check.sh <pr>`, which reads protection live.
3. **Lint C3 stays green.** It only needs `contracts/suites.txt` to still be
   read by the workflow, and it is.

## Failure to watch for

- **A shard that runs nothing and passes.** That is the failure this job's own
  comment warns about. Its count line reads `0 of <total>`, which is why the
  count is printed per shard. If a total is ever below the number of manifest
  suites without a dedicated job, the index is being counted in the wrong place.
- **An unbalanced split.** Round-robin by position does not know that
  `failure-capture-test.sh`, `prove-test.sh` and `inject-hook-test.sh` take about
  3 minutes each. If one shard keeps running near 20 minutes while the others
  finish in 5, balance by measured time instead. `ci-queue.sh` already reads job
  durations, and harbor#669 has the per-suite table.
