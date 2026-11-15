# Operator patch — `lint-test.sh` runs TWICE in every CI run

**STATUS: OBSOLETE (2026-10-14).** The double run came from the `suite-manifest` job's dedup, which is gone. `lint-test.sh` is one line of `contracts/suites.txt` (`grep -c 'tests/lint/conventions/conventions.test.sh' contracts/suites.txt` prints 1) and the pool runs each line once. Kept for its measurements; nothing in it applies to the current workflow.

**Why this is a file and not a commit.** `permissions.deny` covers
`.github/workflows/**`, deliberately: that deny exists so an agent cannot rewrite
the gate that judges it. See [README.md](./README.md).

Found by the 2026-08-13 feature-health audit. This is the failure that
[governance-suite-manifest.patch.md](./governance-suite-manifest.patch.md) warns
about **in its own prose** — "this job deliberately skips anything they already
cover, so nothing runs twice" — and the job's own comment repeats it: *"Getting
this wrong runs everything twice and still reports success."* It is wrong for
exactly one suite, and it reports success.

## The defect

The `suite-manifest` job dedups against the dedicated jobs by grepping the
workflow for the `--run` spelling:

```sh
if grep -q -- "--run $s" .github/workflows/governance.yml; then
```

Every dedicated suite job invokes `sh bin/test-suite-select.sh --run <suite>` — except
the conventions job, which calls the suite **directly**:

```yaml
      - name: conventions linter suite
        run: sh bin/lint-test.sh
```

So `--run lint-test.sh` appears nowhere, the dedup never matches, and the manifest
job runs it a second time. Measured on this tree:

| Check | Result |
|---|---|
| `grep -oE 'sh bin/[a-z0-9-]+-test\.sh' governance.yml` | `lint-test.sh`, `statusline-test.sh` |
| `grep -c -- '--run lint-test.sh' governance.yml` | **0** |
| `grep -c -- '--run statusline-test.sh' governance.yml` | 1 → dedup matches, correctly skipped |

`statusline-test.sh` is a **true negative, not a second bug**: it is deliberately
run twice under two different shells (the job comment at governance.yml:338 —
"a suite invoked WITH ARGUMENTS cannot go through `--run`"), and because the
`--run` spelling also appears, the manifest job skips it. Leave it alone.

Cost: `lint-test.sh` is 61 assertions and each `sh "$LINT"` invocation runs the
whole linter, on **one serialised self-hosted runner**. Since `strict: true`
landed on `main`, every merge invalidates every other open PR's green status, so
the duplicate is paid again per PR per merge.

## The patch

In `.github/workflows/governance.yml`, in the **`conventions`** job, replace:

```yaml
      - name: conventions linter suite
        run: sh bin/lint-test.sh
```

with:

```yaml
      - name: conventions linter suite
        run: sh bin/test-suite-select.sh --run lint-test.sh
```

## Why this spelling and not a dedup exception

Routing it through `--run` is what every other suite already does, and it makes
the suite **visible to the dedup by construction** rather than by a second list
that can drift out of agreement with the first — the same reasoning that put
`contracts/suites.txt` in a tracked file instead of inside the workflow.

**It is behaviour-preserving.** `contracts/suite-paths.txt` declares
`lint-test.sh always`, so `--run` runs it unconditionally, exactly as the direct
call does today. It does not become path-gated by this change.

## Falsifier

After applying, this must print `0`:

```sh
git grep -c 'run: sh bin/lint-test.sh' -- .github/workflows/governance.yml
```

and the run log must show `conventions linter suite` once and **no**
`lint-test.sh` line under `manifest suites (not already wired to a job)`.

If instead you want to prove the defect first, run the dedup predicate by hand
against the current file — it returns 1 (no match), which is why the skip never
fires:

```sh
grep -q -- "--run lint-test.sh" .github/workflows/governance.yml; echo "rc=$?"
```
