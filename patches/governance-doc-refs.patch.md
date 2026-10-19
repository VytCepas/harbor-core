# Operator patch: report the doc-refs check in CI (harbor#996 E2)

**STATUS: APPLIED by the CI workflow bundle (chore/ci-workflow-bundle, 2026-10-14).** The step now lives in the
sharded `suite-shard` job, shard 1 only, beside `lint-conventions`. The Before and After blocks below are the
single `suites` job it was written against.

**Why this is a file and not a commit.** `permissions.deny` covers
`.github/workflows/**`, deliberately: that deny exists so an agent cannot rewrite the gate that
judges it. See [README.md](./README.md).

## What already runs, and what this adds

`bin/lint-conventions.sh` already runs `bin/doc-refs.sh` as rule `doc.refs-conform` (warn), so
every CI run of the `Enforce CONTRACTS/naming.md + house style` step prints the doc-refs findings
as `ADVISORY [doc.refs-conform]` lines, in the `suites` job, which fetches full history
(`fetch-depth: 0`), so staleness can be counted. **Nothing needs this patch for the check to run.**

What the patch adds is a separate step with its own summary block, so the dangling and stale
counts are one click from the PR instead of buried in the lint log. It does not gate: the
step is `continue-on-error`, and the rules are `warn` in `standards/naming/controls.tsv`
(promotion to `block` is a one-cell edit after the rules have run 4 weeks with no finding
accepted as false, standards/naming.md section 10.3).

## The patch

In `.github/workflows/governance.yml`, in the **`suites`** job, directly after the
`Enforce CONTRACTS/naming.md + house style` step (the one with `id: conv`).

Before:

```yaml
      - name: Enforce CONTRACTS/naming.md + house style
        id: conv
        continue-on-error: true
        run: sh bin/lint-conventions.sh
      - name: Every selected suite, longest first
        id: run
```

After:

```yaml
      - name: Enforce CONTRACTS/naming.md + house style
        id: conv
        continue-on-error: true
        run: sh bin/lint-conventions.sh
      # SAME CHECK AS THE doc.refs-conform ADVISORIES ABOVE, with its own summary block (harbor#996 E2).
      # Never gates: exit 0 whatever it finds, 3 only when no entry doc could be read, and that is shown.
      # A citation it could not look at (no sibling checkouts in CI) is counted "not judged" in the summary line.
      - name: Entry docs cite paths that exist (doc-refs, warn)
        id: docrefs
        continue-on-error: true
        run: |
          rc=0
          sh bin/doc-refs.sh --format findings > "$RUNNER_TEMP/doc-refs.tsv" 2> "$RUNNER_TEMP/doc-refs.log" || rc=$?
          cat "$RUNNER_TEMP/doc-refs.log"
          { echo '### doc-refs'; echo '```'; cat "$RUNNER_TEMP/doc-refs.log" "$RUNNER_TEMP/doc-refs.tsv"; echo '```'; } >> "$GITHUB_STEP_SUMMARY"
          exit "$rc"
      - name: Every selected suite, longest first
        id: run
```

The suite lock does not apply to CI; the step costs about a second (measured on this tree: 0.8 s,
`time sh bin/doc-refs.sh`).

## Repos without CI, and sibling repos

`doc-refs.sh` judges any checkout: `sh bin/doc-refs.sh --root <dir> --self <id>`. For the repos that
have no CI, the fleet audit runs it over every checkout in the registry and prints one count row each:

```sh
sh bin/doc-refs.sh --fleet
```

A sibling repo's own CI would call the harbor copy of the tool; that is harbor#996 T6's patch to carry,
not this one's.

## Falsifier

After applying, plant a dead citation in a PR branch and watch the step's summary name it:

```sh
printf '\nSee `bin/no-such-file-doc-refs-probe.sh`.\n' >> README.md
sh bin/doc-refs.sh --format findings 2>&1 | grep no-such-file-doc-refs-probe   # expect: a doc.refs-resolve line
git checkout -- README.md                                                      # restore
```

A summary that does not show the planted path means the step reads a different tree from the one
the PR changed.
