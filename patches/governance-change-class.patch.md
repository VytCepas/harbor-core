# Operator patch — make CI read the change-class table (CI-2, harbor#150)

**STATUS: APPLIED by the operator on 2026-08-07**, in `a431b6e` (merged as
`04a5661`, PR #168). Every section below landed; 23 edits. The proof is that lint
C5's advisory is gone, which is what this file said it would be.

First run of the patched workflow: all 12 jobs green, including the new
`change class` job, which reported all 23 suites `RUN` for the reason
*"changeset touches the selector's own inputs"* — the self-protection rule firing,
because that PR changed `.github/workflows/governance.yml`. A change to the
selector's inputs is never judged by the selector.

**Why this is a file and not a commit.** `permissions.deny` covers
`.github/workflows/**`, deliberately: that deny exists so an agent cannot rewrite
the gate that judges it. It is not only `Edit` — copying the file to a scratch
path to generate a unified diff was refused too, which is the deny working. So
this is the same shape as
[governance-suite-manifest.patch.md](./governance-suite-manifest.patch.md):
exact replacement blocks rather than a `patch(1)` hunk, because a hunk carries
line numbers that a hand cannot get right and a machine here is not allowed to
generate.

## What is already landed, and works without this patch

- `contracts/suite-paths.txt` — every suite declares which changed paths select
  it, plus `@no-suite` for paths that legitimately select nothing.
- `bin/test-suite-select.sh` — the decision procedure. `--list`, `--changed`, a bare
  suite name for the exit status, and `--run` for CI.
- `bin/suite-select-test.sh` — its suite, in the manifest, so it already runs in
  CI through the `suite-manifest` job.
- Lint rule **C5** — both directions between the manifest and the declarations,
  plus the empty-key, duplicate-key and missing-`@no-suite` cases.

Until this patch is applied the table is **inert**: correct, tested, and consulted
by nothing. The linter says so on every run:

```
ADVISORY [C5] governance.yml does not call bin/test-suite-select.sh yet — the
declarations are inert until patches/governance-change-class.patch.md is applied
```

That advisory disappearing is the observable proof the patch landed — and it has
disappeared. The `build/` path this block used to quote was itself the drift that
`patches/README.md` records: `build/` is gitignored, so the advisory named a file
that existed on one machine and nowhere else.

## The shape, and the one decision inside it

Jobs are **not** gated with `if:`. Every job still runs, still checks out, and
still reports a real verdict; `test-suite-select.sh --run` stands the *suite* down
from inside the job and the job exits 0 with a log saying why.

The alternative — `if: needs.classify.outputs.floor == 'true'` — is shorter and
wrong here. A skipped job reports its check as `skipped`, and this repo has
already written down what that costs, in the comment above the `status` job: *a
skipped required check does not block a merge, so a red suite hides behind a
check that reads as satisfied because it never ran*. `security-floor suite` is
one of the two required contexts on `main`. Standing down inside the job costs a
checkout per stood-down job and buys not depending on that semantics at all.

**What it does not change:** `main` still runs everything, always. The changeset
is `origin/main...HEAD`, which on a push to `main` is empty, and an empty
changeset runs every suite by design. The saving is on branch and PR runs, and it
scales with how many PRs are open — which is the point, because `strict: true`
makes every merge re-run every other open PR.

---

## 1 · New job `classify`, inserted directly after the `preflight` job

One full-history checkout for the whole run. The selector diffs against
`origin/main`, and every other job checks out shallow, so computing the changeset
per job would either need `fetch-depth: 0` in every one of them or silently
produce no changeset — which resolves to *run everything* and would make the
feature inert while looking like it worked. Publishing it once also means every
job judges the same changeset; a set of independent diffs that could disagree is
a worse failure than a slow run.

```yaml
  classify:
    name: change class
    needs: preflight
    outputs:
      changed: ${{ steps.diff.outputs.changed }}
    runs-on: ${{ fromJSON((inputs.runner || vars.HARBOR_RUNNER) == 'github-hosted' && '["ubuntu-latest"]' || '["self-hosted","macOS","ARM64"]') }}
    steps:
      - uses: actions/checkout@v5
        with:
          fetch-depth: 0          # suite-select needs a base to diff against
      - name: The changeset this run is judging
        id: diff
        run: |
          # `github.base_ref` is set only on pull_request; on push it is empty
          # and the base is main, where the diff is empty and everything runs.
          base="origin/${{ github.base_ref || 'main' }}"
          echo "base=$base"
          git diff --name-only "$base"...HEAD > "$RUNNER_TEMP/changed.txt" || :
          cat "$RUNNER_TEMP/changed.txt"
          {
            echo 'changed<<HARBOR_CHANGESET_EOF'
            cat "$RUNNER_TEMP/changed.txt"
            echo 'HARBOR_CHANGESET_EOF'
          } >> "$GITHUB_OUTPUT"
      - name: The verdict, per suite
        env:
          HARBOR_CHANGED: ${{ steps.diff.outputs.changed }}
        run: |
          sh bin/test-suite-select.sh --list > "$RUNNER_TEMP/verdicts.txt"
          cat "$RUNNER_TEMP/verdicts.txt"
          {
            echo '### change class'
            echo '```'
            cat "$RUNNER_TEMP/verdicts.txt"
            echo '```'
          } >> "$GITHUB_STEP_SUMMARY"
```

## 2 · `conventions` — deliberately unchanged

It stays always-on. It is one of the two required contexts, `lint-test.sh` is
declared `always` in the table anyway, and it is the rule set that enforces the
table. Gating the thing that checks the gate is how a narrowing becomes
self-approving.

## 3 · `floor`

Replace the job's `needs:` and `outputs:` and add `env:`:

```yaml
  floor:
    name: security-floor suite
    needs: [preflight, classify]
    outputs:
      count: ${{ steps.suite.outputs.count }}
      ran: ${{ steps.suite.outputs.ran }}
    env:
      HARBOR_CHANGED: ${{ needs.classify.outputs.changed }}
```

Replace the two suite steps. The redirect-never-pipe reasoning, the
`RUNNER_TEMP` artefact and the refuse-an-empty-count check all moved into
`test-suite-select.sh --run`, where there is one copy of them instead of three:

```yaml
      - name: Run the floor suite (guards + mutation pass + wiring assertions)
        id: suite
        run: sh bin/test-suite-select.sh --run floor-test.sh
      - name: Run the replay suite (corpus builder + runner + labels)
        run: sh bin/test-suite-select.sh --run replay-test.sh
```

## 4 · `normalize` and `marker`

Same three changes each — `needs`, a `ran` output, `env` — and one step body.

```yaml
  normalize:
    name: tokenizer suite
    needs: [preflight, classify]
    outputs:
      count: ${{ steps.suite.outputs.count }}
      ran: ${{ steps.suite.outputs.ran }}
    env:
      HARBOR_CHANGED: ${{ needs.classify.outputs.changed }}
```
```yaml
      - name: Prove the segment table is built correctly
        id: suite
        run: sh bin/test-suite-select.sh --run normalize-test.sh
```
```yaml
  marker:
    name: detect-and-defer fixtures
    needs: [preflight, classify]
    outputs:
      count: ${{ steps.suite.outputs.count }}
      ran: ${{ steps.suite.outputs.ran }}
    env:
      HARBOR_CHANGED: ${{ needs.classify.outputs.changed }}
```
```yaml
      - name: Run the marker fixtures against the POSIX resolver
        id: suite
        run: sh bin/test-suite-select.sh --run marker-test.sh
```

## 5 · `statusline`, `cu`, `cli`, `recover`

`needs: [preflight, classify]` and the `env:` block on each, then:

```yaml
      - name: Statusline golden output
        run: sh bin/test-suite-select.sh --run statusline-test.sh
      # A suite invoked WITH ARGUMENTS cannot go through --run, which takes a
      # bare suite name. Gate it on the exit status instead — the same decision,
      # asked directly.
      - name: Statusline golden output (dash)
        run: |
          sh bin/test-suite-select.sh statusline-test.sh > /dev/null || exit 0
          sh bin/statusline-test.sh --dash
```
```yaml
      - name: Pin the cu write-allowlist and its shipped bugs
        run: sh bin/test-suite-select.sh --run cu-test.sh
      - name: Pin the gcx identity disclosure and account pin
        run: sh bin/test-suite-select.sh --run gcx-test.sh
```
```yaml
      - name: harbor dispatcher suite
        run: sh bin/test-suite-select.sh --run harbor-test.sh
      - name: ambient prod_guard shim suite
        run: sh bin/test-suite-select.sh --run prod-guard-test.sh
```
```yaml
      - name: Prove the restore path still works
        run: sh bin/test-suite-select.sh --run recover-test.sh
```

## 6 · `status` — the one job whose behaviour genuinely changes

`needs: [preflight, classify, floor, normalize, marker]`, and the final step
becomes:

```yaml
      - name: docs/generated/status.md must be regenerated, not hand-edited
        run: |
          # WHY --check-fast IS SOUND WHEN THE THREE STAND DOWN. The assertion
          # counts in docs/generated/status.md can only move if a suite's behaviour moved, which
          # needs a bin/ or fixtures/ change, which selects those suites. So when
          # they stand down, those three rows cannot have changed — and the
          # repo-counted rows (lint rules, skills, contracts, guards, fixtures)
          # are still checked, because --check-fast checks exactly those.
          #
          # WHAT WOULD FALSIFY IT: a change that moves an assertion count while
          # touching no path any of the three declares. If that is ever found,
          # the bug is in contracts/suite-paths.txt, not here.
          if [ "${{ needs.floor.outputs.ran }}" = "true" ] \
             && [ "${{ needs.normalize.outputs.ran }}" = "true" ] \
             && [ "${{ needs.marker.outputs.ran }}" = "true" ]; then
            HARBOR_SUITE_COUNTS="floor-test=${{ needs.floor.outputs.count }},normalize-test=${{ needs.normalize.outputs.count }},marker-test=${{ needs.marker.outputs.count }}" \
              sh bin/status-generate.sh --check
          else
            echo "count-bearing suites stood down for this change class —"
            echo "checking the repo-counted fields only (see the comment above)."
            sh bin/status-generate.sh --check-fast
          fi
```

Delete the step's old `env: HARBOR_SUITE_COUNTS:` block; it is inline above now.

**Leave the dependency-failure guard exactly as it is.** It fires on
`result != 'success'`, and no job is skipped under this design, so a stood-down
suite still arrives as `success` and a red one still arrives as `failure`.

## 7 · `suite-manifest`

`needs: [preflight, classify]`, the `env:` block, and a new loop body. **The
dedup grep must change**: it looks for `bin/<suite>` in this file, and after this
patch the jobs above say `--run <suite>` with no `bin/` prefix — so left alone it
would stop recognising every dedicated job and run each of those suites a second
time.

```yaml
      - name: run manifest suites with no dedicated job
        run: |
          set -eu
          ran=0
          while IFS= read -r s; do
            case "$s" in ''|\#*) continue ;; esac
            # `--run $s`, not `bin/$s`: the dedicated jobs no longer name the
            # suite path. Getting this wrong runs everything twice and still
            # reports success, which is why it is called out rather than left
            # to be noticed.
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

---

## After applying

```sh
sh bin/lint-conventions.sh | grep C5     # the ADVISORY must be GONE
sh bin/lint-test.sh                      # C5's own assertions
sh bin/suite-select-test.sh              # the selector's
```

Then watch two runs, because one proves nothing:

| Run | Expect |
|---|---|
| a **docs- or skills-only** PR | `change class` summary lists most suites as SKIP; `security-floor suite` green having stood down; `status` on `--check-fast` |
| a **`bin/`** PR | every suite RUN, `status` on `--check` with three counts, wall clock unchanged from today |

**The failure to look for is the quiet one.** A shorter green run is what both a
working narrowing and a broken selector look like. The check that tells them
apart is the `change class` job summary: it names every suite, its verdict and
the reason, and a run where everything stood down for the wrong reason says so
there in plain text.
