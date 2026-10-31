---
name: audit-review-fanout
description: "Review a code change with several cheap reviewers, each given a different lens, then verify every finding before reporting it. The deliverable is verified defects only, each with its evidence; none found is a valid result. USE WHEN review this PR, review the diff, code review, review my changes, audit this change, check before merge, second opinion on code. NOT FOR a one-line or docs-only change (one reviewer is enough), proving a test can fail (test-strength), or the merge decision (harbor-merge)."
---

# audit-review-fanout — distinct lenses, then verification

**Done looks like:** a findings list where every item is **confirmed**. It was either reproduced
by a command, or the exact line is quoted beside the text or contract it breaks. Items are
deduplicated and ordered most severe first. Each says whether it is fixed (a review fixes
nothing unless asked: CONSTITUTION №5). Anything unconfirmed is listed separately as
unconfirmed, never as a defect. **No findings is a valid result.**

Why this shape: in the harbor#818 trial, a single reviewer of any tier found every planted
defect. The *extra* real bugs came from different runs noticing different things. Copies of
one prompt mostly repeat each other. Every added reviewer also adds false positives, and a false
positive is a defect (№2.11), so the verify step is the half that makes the fan-out safe.

## 1. Scope

Get the diff and its file list: `gh pr diff <N>`, or `git diff <base>...HEAD`. For a one-line or
docs-only change, run one reviewer (`model: haiku`, `effort: medium`) and stop here.

## 2. Lenses — one agent each, in parallel, in waves of 5 at most

| Lens | `subagent_type` | The question it answers |
|---|---|---|
| Correctness | `pr-review-toolkit:code-reviewer` | Wrong results, edge cases, broken callers |
| Failure handling | `pr-review-toolkit:silent-failure-hunter` | Errors swallowed, fallbacks that hide failure |
| Security and privacy | `general-purpose` | Injection, secrets, paths or identity leaking, egress, CONSTITUTION §3 and §4 |
| Contracts | `pr-review-toolkit:comment-analyzer` | Code that contradicts its own comments, docs, usage text or CONTRACTS |
| Tests | `pr-review-toolkit:pr-test-analyzer` | Would the tests fail if this change were reverted? |
| Surroundings | `general-purpose` | Existing defects in the code the change touches |

Every lens runs with **`model: haiku`, `effort: medium`**. Pass `model` even for the plugin
agents: `code-reviewer` pins `opus`, and only the parameter overrides that.

**Restate every constraint in each brief.** A rule that sits only in a skill is not followed;
the same rule in the request is. Each brief names:
- the diff (PR number or base ref) and its lens;
- read-only, change nothing;
- report only real defects, and say "none" when there are none;
- reply with only a JSON array: `[{"file", "line", "claim", "evidence"}]`.

## 3. Merge

Deduplicate yourself. Two findings are one when they name the same file, lines within ±2 of
each other, and the same claim. Keep the strongest evidence.

## 4. Verify — every finding, by an agent that did not raise it

One agent per finding (`model: haiku`, `effort: high`; batch up to 5 findings per agent when
there are more than 10). The verdict must be one of three:
- **CONFIRMED**, with a command that reproduces it and its output, or the quoted line beside
  the quoted text it contradicts;
- **REFUTED**, with the reason;
- **UNVERIFIABLE**.

Only a CONFIRMED finding is a defect.

## 5. Escalate

Use `opus` only when verifiers disagree, or when a confirmed finding is security-critical.

## 6. Report

List confirmed findings, most severe first. Each one gives `file:line`, the claim, the
evidence, and `FIXED / NOT FIXED`. Then list the unconfirmed findings under their own heading.
Then one line: lenses run, findings raised, confirmed, refuted.

## Keeping it honest

This shape is not measured yet. After each review, add one row to #818: findings raised,
confirmed, and whether a single Sonnet reviewer would have caught them. After about 5 PRs, if
the fan-out has confirmed nothing a single reviewer missed, go back to one Haiku reviewer at
`high` effort plus a verify step.
