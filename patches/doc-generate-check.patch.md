# Operator patch — nothing checks that `docs/index.html` was regenerated

**STATUS: OBSOLETE (2026-10-14).** Lint rule `doc.site-generated` (bin/lint-conventions.sh) runs `doc-index-generate.sh --check`, and the required `conventions linter` check runs that rule in every CI run, so a stale `docs/index.html` is already red there. A second step in the `status` job would run the same check twice. Kept for its measurements; nothing in it applies to the current workflow.

**Why this is a file and not a commit.** `permissions.deny` covers
`.github/workflows/**`, deliberately: that deny exists so an agent cannot rewrite
the gate that judges it. See [README.md](./README.md).

Found by the 2026-08-13 feature-health audit (harbor#176). `bin/status-generate.sh`
and `bin/doc-index-generate.sh` are the same mechanism — a generated file in the repo,
derived from the repo, with an `--apply` writer and a `--check` staleness gate.
`bin/lint-conventions.sh:333` says so in as many words: docs-gen is
"status-generate.sh's **exact shape**".

One of them has a CI job. The other has nothing.

## The defect, measured on this tree

```
$ sh bin/doc-index-generate.sh --check
docs-gen: docs/index.html is STALE — run: sh bin/doc-index-generate.sh --apply
rc=1
```

```
$ grep -c 'docs-gen' .github/workflows/governance.yml
0
```

The committed page has been stale since **2026-08-12**. What it is missing is not
cosmetic — it is the inventory the page exists to state:

| Section | Missing from the committed page |
|---|---|
| The guards | `admission-cloud.sh`, `admission-destroy.sh` — both live `PreToolUse(Bash)` hooks |
| Manifest suites | `destroy-guard-test.sh`, `cloud-guard-test.sh`, `judge-run-test.sh`, `renew-check-test.sh`, `proposal-test.sh` |
| Lint rules | X8's description, still the pre-vendored wording |
| Skills | `reporting-apis` description, one revision behind |

So the architecture document a reader opens describes a floor with four guards
when the box runs six. That is the exact drift class the T rules and `status-gen`
exist for, on the one generated file no rule watches.

**Scope, stated honestly:** GitHub Pages is **not** enabled on this repo
(`gh api repos/VytCepas/harbor/pages` → 404) and the repo is private, so this is
a local artefact opened with `open docs/index.html`, not a published page. The
defect is a document that lies to its reader, not a leak.

## The patch

In `.github/workflows/governance.yml`, in the **`status`** job
(`name: generated status is current`), after the existing
`docs/generated/status.md must be regenerated, not hand-edited` step, add:

```yaml
      # SAME MECHANISM AS THE STEP ABOVE, SECOND GENERATED FILE. doc-index-generate.sh is
      # status-generate.sh's exact shape (lint-conventions.sh:333) and had no gate at
      # all, so the committed page drifted for a day and named four guards on a
      # box running six. No env plumbing and no dependency guard: unlike
      # status-gen, docs-gen derives nothing from a suite count and nothing from
      # host state — verified by generating twice and comparing (identical), and
      # by grepping it for STATUS/HARBOR_SUITE_COUNTS/hostname (no matches).
      - name: docs/index.html must be regenerated, not hand-edited
        run: sh bin/doc-index-generate.sh --check
```

## Why this job, and why a step rather than a new job

- **This job**, because it is already the home of "a generated file is current",
  it already has a checkout, and it already carries the
  `A dependency that did not succeed must FAIL this check` guard that stops a
  skipped check from reading as satisfied.
- **A step, not a job**, because a new job costs a fresh checkout on **one
  serialised self-hosted runner**, and the whole point of harbor#122 was to stop
  this workflow paying twice for the same thing.
- **Not the `conventions` job**, which is a *required* context. Putting docs
  staleness in the merge gate is a policy escalation — whether a stale
  architecture page should block a merge is the operator's call, not this
  patch's. `status` is not a required context, so this reports red on the PR
  without gating it. Promote it later by moving the step if the report gets
  ignored.

## Before applying: regenerate once

The check will fail on the first run until the committed page is current:

```sh
sh bin/doc-index-generate.sh --apply && git add docs/index.html
```

## Falsifier

After applying, with a deliberately stale page, the job must go red:

```sh
sh bin/doc-index-generate.sh --apply                 # make it current
sh bin/doc-index-generate.sh --check                 # expect: is current, rc=0
printf '<!-- break it -->\n' >> docs/index.html
sh bin/doc-index-generate.sh --check; echo "rc=$?"   # expect: STALE, rc=1
git checkout -- docs/index.html            # restore
```

A `--check` that passes on the appended file would mean the gate compares
something other than the committed bytes, and the step is worthless.
