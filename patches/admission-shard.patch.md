# Operator patch — split `security-floor suite` into three shards (harbor#679)

**STATUS: OBSOLETE (2026-10-14).** `security-floor suite` is now a relay: the `floor` job reads the pool's `--tally floor` verdict and no longer runs `floor-test.sh` itself, so there is no 20-minute job to split. Kept for its measurements; nothing in it applies to the current workflow.

**Why this is a file and not a commit.** `permissions.deny` covers
`.github/workflows/**`, deliberately: that deny exists so an agent cannot rewrite
the gate that judges it. See [README.md](./README.md).

## Why

- `security-floor suite` runs `floor-test.sh` (about 1,860 assertions) as one job under
  `timeout-minutes: 20`, and it is a **required** check.
- On 2026-09-24 it passed on #678 at **19m57s**, 3 seconds under the limit. Earlier
  that day the linter suite, the other long required job, was cancelled at the
  limit (#531, #666).
- Since #672 split the manifest, the manifest shards finish first, so this job and
  the linter suite set every run's wall time.
- This patch covers `security-floor suite` only. The linter suite waits for #531's
  `--only` conversion to be measured first, as #679 says.

The code half ships in the same PR as this file: `floor-test.sh --shard K/N`,
`test-suite-select.sh --run floor-test.sh --shard K/N`, and the Stop gate refusing a
shard as evidence of the full suite. This file is the workflow half.

## Measured before this patch

On this box on 2026-09-24, at load average 8 to 15, with CI and other sessions running:

| run | wall | result |
|---|---|---|
| `floor-test.sh`, unsharded (before this change) | **826 s** | 1,861 passed |
| `floor-test.sh`, unsharded (after this change) | 610 s | 1,878 passed |
| `--shard 0/3`, three shards in parallel | 341 s | 486 passed, 31 of 97 sections |
| `--shard 1/3` | **442 s** | 645 passed, 33 of 97 sections |
| `--shard 2/3` | 440 s | 747 passed, 33 of 97 sections |

- **The shards' counts sum to the unsharded count:** 486 + 645 + 747 = 1,878, which is the old 1,861 plus SHARD-1's 17 new assertions. Their sections sum to 97.
- **The longest shard took 442 s.** The unsharded suite took **610 s** in the window right after it (load falling from 12.6 to 8.2), and 826 s earlier the same afternoon (load 12). That is **28% to 46% less wall time**, depending on which unsharded run is the baseline. It is the lever #679 predicted, not its falsifier, but the saving is well short of a third because:
  - the three shards compete for the same CPU (#666);
  - the heaviest sections are uneven: `red-team pass 3` alone took 87 s and `C1a` took 52 s.
- **In CI** each shard also waits for a runner, and the aggregator needs one more after the shards finish (see "Failure to watch for").

## The edit

One job in `.github/workflows/governance.yml`, `floor`, is replaced by four jobs.
Nothing else in the file changes. `status` keeps `needs: [preflight, classify, floor, fast]`
and its `needs.floor.*` references, because the new aggregator keeps the id `floor`.

Replace this block, the whole `floor:` job, from `  floor:` down to the line before
`  status:`:

```yaml
  floor:
    name: security-floor suite
    timeout-minutes: 20
    needs: [preflight, classify]
    # Published so `status` can check docs/generated/status.md against a count THIS run actually
    # measured, instead of measuring all three suites over again (harbor#122).
    # The evidence is not weakened: same commit, same runner, one execution
    # instead of two.
    outputs:
      count: ${{ steps.suite.outputs.count }}
      ran: ${{ steps.suite.outputs.ran }}
    env:
      HARBOR_CHANGED: ${{ needs.classify.outputs.changed }}
    runs-on: ${{ fromJSON((inputs.runner || vars.HARBOR_RUNNER) == 'github-hosted' && '["ubuntu-latest"]' || '["self-hosted","macOS","ARM64"]') }}
    steps:
      - uses: actions/checkout@v5
      - name: Install dependencies (hosted runners only)
        if: runner.os == 'Linux'
        run: |
          sudo apt-get update -qq && sudo apt-get install -y -qq jq
          curl -sSL https://github.com/gitleaks/gitleaks/releases/download/v8.18.4/gitleaks_8.18.4_linux_x64.tar.gz \
            | sudo tar -xz -C /usr/local/bin gitleaks
      # The redirect-never-pipe reasoning, the RUNNER_TEMP artefact and the
      # refuse-an-empty-count check all live in test-suite-select.sh --run now, where
      # there is ONE copy of them instead of three.
      - name: Run the floor suite (guards + mutation pass + wiring assertions)
        id: suite
        run: sh bin/test-suite-select.sh --run floor-test.sh
      # M2 (harbor#44). Hermetic: it builds a SYNTHETIC transcript tree and points
      # the corpus builder at it via HARBOR_TRANSCRIPTS, so this never reads a real
      # transcript store — the property R13 asserts rather than assumes. That
      # guarantee carries more weight on a self-hosted runner, where the real
      # store IS on the machine.
      - name: Run the replay suite (corpus builder + runner + labels)
        run: sh bin/test-suite-select.sh --run replay-test.sh
```

with:

```yaml
  # harbor#679. `security-floor suite` passed at 19m57s against its 20-minute
  # limit on 2026-09-24. floor-test.sh now takes --shard K/N: the shared fixture
  # runs in every shard, then every Nth section, and each section runs in exactly
  # one shard (floor-test SHARD-1 asserts it). The three shards run as separate
  # jobs, not a matrix, because each must PUBLISH ITS OWN COUNT and a matrix job
  # has one set of outputs, overwritten by whichever leg finishes last.
  floor-shard-0:
    name: security-floor shard 0 of 3
    timeout-minutes: 20
    needs: [preflight, classify]
    outputs:
      count: ${{ steps.suite.outputs.count }}
      ran: ${{ steps.suite.outputs.ran }}
    env:
      HARBOR_CHANGED: ${{ needs.classify.outputs.changed }}
    runs-on: ${{ fromJSON((inputs.runner || vars.HARBOR_RUNNER) == 'github-hosted' && '["ubuntu-latest"]' || '["self-hosted","macOS","ARM64"]') }}
    steps:
      - uses: actions/checkout@v5
      - name: Install dependencies (hosted runners only)
        if: runner.os == 'Linux'
        run: |
          sudo apt-get update -qq && sudo apt-get install -y -qq jq
          curl -sSL https://github.com/gitleaks/gitleaks/releases/download/v8.18.4/gitleaks_8.18.4_linux_x64.tar.gz \
            | sudo tar -xz -C /usr/local/bin gitleaks
      - name: Run floor-test, shard 0 of 3
        id: suite
        run: sh bin/test-suite-select.sh --run floor-test.sh --shard 0/3
      # M2 (harbor#44). Moved here from the unsharded job unchanged; 17 s, so it
      # rides with shard 0 rather than paying a job of its own.
      - name: Run the replay suite (corpus builder + runner + labels)
        run: sh bin/test-suite-select.sh --run replay-test.sh
  floor-shard-1:
    name: security-floor shard 1 of 3
    timeout-minutes: 20
    needs: [preflight, classify]
    outputs:
      count: ${{ steps.suite.outputs.count }}
      ran: ${{ steps.suite.outputs.ran }}
    env:
      HARBOR_CHANGED: ${{ needs.classify.outputs.changed }}
    runs-on: ${{ fromJSON((inputs.runner || vars.HARBOR_RUNNER) == 'github-hosted' && '["ubuntu-latest"]' || '["self-hosted","macOS","ARM64"]') }}
    steps:
      - uses: actions/checkout@v5
      - name: Install dependencies (hosted runners only)
        if: runner.os == 'Linux'
        run: |
          sudo apt-get update -qq && sudo apt-get install -y -qq jq
          curl -sSL https://github.com/gitleaks/gitleaks/releases/download/v8.18.4/gitleaks_8.18.4_linux_x64.tar.gz \
            | sudo tar -xz -C /usr/local/bin gitleaks
      - name: Run floor-test, shard 1 of 3
        id: suite
        run: sh bin/test-suite-select.sh --run floor-test.sh --shard 1/3
  floor-shard-2:
    name: security-floor shard 2 of 3
    timeout-minutes: 20
    needs: [preflight, classify]
    outputs:
      count: ${{ steps.suite.outputs.count }}
      ran: ${{ steps.suite.outputs.ran }}
    env:
      HARBOR_CHANGED: ${{ needs.classify.outputs.changed }}
    runs-on: ${{ fromJSON((inputs.runner || vars.HARBOR_RUNNER) == 'github-hosted' && '["ubuntu-latest"]' || '["self-hosted","macOS","ARM64"]') }}
    steps:
      - uses: actions/checkout@v5
      - name: Install dependencies (hosted runners only)
        if: runner.os == 'Linux'
        run: |
          sudo apt-get update -qq && sudo apt-get install -y -qq jq
          curl -sSL https://github.com/gitleaks/gitleaks/releases/download/v8.18.4/gitleaks_8.18.4_linux_x64.tar.gz \
            | sudo tar -xz -C /usr/local/bin gitleaks
      - name: Run floor-test, shard 2 of 3
        id: suite
        run: sh bin/test-suite-select.sh --run floor-test.sh --shard 2/3
  # THE REQUIRED CONTEXT. Branch protection requires `security-floor suite` by
  # name, so this job keeps that name and the `floor` id that `status` needs. Its
  # first step turns any non-success shard into a FAILURE. Without that step a
  # failed shard would SKIP this job, and a skipped required check reads as
  # satisfied (the defect `status`'s own comment describes).
  #
  # `always()`, NOT the `!cancelled()` that `status` uses, because THIS job is a
  # REQUIRED context (found by review on #688). GitHub reports a skipped job as
  # success, so under `!cancelled()` a run cancelled while a shard was still going
  # would skip this job and satisfy branch protection with the floor never
  # verified. The unsharded job did not have this hole: it reported `cancelled`,
  # which blocks. The cost is a red aggregator on superseded runs nobody is
  # waiting on; `status` may take the quiet option because it is not required.
  floor:
    name: security-floor suite
    timeout-minutes: 5
    needs: [floor-shard-0, floor-shard-1, floor-shard-2]
    if: ${{ always() }}
    outputs:
      count: ${{ steps.sum.outputs.count }}
      ran: ${{ steps.sum.outputs.ran }}
    runs-on: ${{ fromJSON((inputs.runner || vars.HARBOR_RUNNER) == 'github-hosted' && '["ubuntu-latest"]' || '["self-hosted","macOS","ARM64"]') }}
    steps:
      - name: Every shard must have succeeded — a failed or skipped shard FAILS this check
        if: >-
          needs.floor-shard-0.result != 'success' || needs.floor-shard-1.result != 'success' ||
          needs.floor-shard-2.result != 'success'
        run: |
          echo "security-floor suite is NOT green:" >&2
          echo "  shard 0=${{ needs.floor-shard-0.result }}  1=${{ needs.floor-shard-1.result }}  2=${{ needs.floor-shard-2.result }}" >&2
          exit 1
      # The summed count is what `status` checks against docs/generated/status.md, so a section
      # dropped or run twice by the split fails there too, not only in SHARD-1.
      - name: Sum the shard counts for the docs/generated/status.md check
        id: sum
        run: |
          ran="${{ needs.floor-shard-0.outputs.ran }}${{ needs.floor-shard-1.outputs.ran }}${{ needs.floor-shard-2.outputs.ran }}"
          if [ "$ran" = "falsefalsefalse" ]; then echo "ran=false" >> "$GITHUB_OUTPUT"; exit 0; fi
          [ "$ran" = "truetruetrue" ] || { echo "the shards disagree on whether floor-test ran: $ran" >&2; exit 1; }
          c0="${{ needs.floor-shard-0.outputs.count }}"; c1="${{ needs.floor-shard-1.outputs.count }}"; c2="${{ needs.floor-shard-2.outputs.count }}"
          for c in "$c0" "$c1" "$c2"; do
            case "$c" in ''|*[!0-9]*) echo "a shard published no count: '$c'" >&2; exit 1 ;; esac
          done
          echo "count=$((c0 + c1 + c2))" >> "$GITHUB_OUTPUT"
          echo "ran=true" >> "$GITHUB_OUTPUT"
          echo "floor-test across 3 shards: $c0 + $c1 + $c2 = $((c0 + c1 + c2))"
```

## Branch protection: no change, and why that holds

Live protection on `main`, read with `gh api repos/VytCepas/harbor/branches/main/protection`
on 2026-09-24:

```
strict: false
contexts: ["conventions linter", "security-floor suite", "conventions linter suite"]
checks:   [{context: "security-floor suite", app_id: 15368}, …]   (15368 = GitHub Actions)
```

- **The required context is produced by the aggregator.** It is named `security-floor suite`,
  so protection needs no edit. The three shard jobs add new contexts
  (`security-floor shard K of 3`) that are **not** required, and must not be added:
  the aggregator already requires all three.
- **What would break it:** renaming the aggregator. So would deleting its first step:
  without it, a failed shard makes GitHub **skip** the aggregator, and a skipped
  required check does not block a merge.

## After applying

1. **Every section ran exactly once.** On the first PR after this lands, each shard
   log ends with
   `floor-test shard K of 3: <n> passed, 0 failed, <s> of <t> sections`.
   - The three `<s>` sum to `<t>`.
   - The aggregator's log prints `<n0> + <n1> + <n2> = <sum>`, and `<sum>` equals
     the `floor-test` assertion count in `docs/generated/status.md`. `generated status is current`
     checks that last part automatically; if it goes red on the count, the split
     dropped or doubled a section.
2. **The required check still gates.** `sh bin/gate-merge-check.sh <pr>` lists
   `security-floor suite` among the required checks, and it passes.
3. **It still fails.** Once, on a throwaway branch, add `bad "probe"` to one section
   of `floor-test.sh`. That shard goes red, the aggregator goes red,
   `security-floor suite` blocks the merge, and `status` reports `floor=failure`.
   Revert.
4. **Is it faster, at load?** Compare the aggregator's finish time with the old job
   over five PR runs (#679's done-when: the longest required job under 10 minutes).

## Failure to watch for

- **A shard that runs nothing and passes.** Its line reads `0 of <t> sections`, and
  floor-test refuses that itself (`shard K/N selected no section`, exit 2).
- **Queue, not CPU.** A run now has three more jobs on the same four runners, and
  the aggregator needs a runner too. If the shards finish fast but the aggregator
  waits minutes to start, the saving went to the queue (#666). The fix then is
  capacity, not more shards.
- **A section that needs an earlier one.** A shard run alone fails with an unbound
  variable or a missing fixture. The fix is a `# shard-group: <name>` line under the
  section headers that belong together (see the floor-test header); SHARD-1 then
  proves the group is never split.
