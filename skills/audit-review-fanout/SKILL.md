---
name: audit-review-fanout
description: "Review a code change with several cheap reviewers, each given a different lens, then verify every finding before reporting it. The deliverable is verified defects only, each with its evidence; none found is a valid result. USE WHEN review this PR, review the diff, code review, review my changes, audit this change, check before merge, second opinion on code. NOT FOR proving a test can fail (test-strength), or the merge decision (gate-merge)."
architecture: code-review
---

# audit-review-fanout — distinct lenses, then verification

**Every PR gets one.** Check `session.review` (`docs/reference/checks.md`): when a session opens a PR, its Stop hook asks
that session once to run this skill on it, standards lenses included. Off: `~/.local/state/harbor/review-auto.off`.
A member laptop runs no user-tier Stop hook, so there the note is the core context rule `review-on-pr-open`
(`contracts/member-context-rules.tsv`), fired after `gh pr create`. A company's or workload's own rules reach the standards
lenses as rule-set files from a hub or workload pack (`packs/README.md`), never hard-coded here.

**Done looks like:** a findings list where every item is **confirmed**. It was either reproduced
by a command, or the exact line is quoted beside the text or contract it breaks. Items are
deduplicated and ordered most severe first. Each says whether it is fixed (a review fixes
nothing unless asked: CONSTITUTION №5). Anything unconfirmed is listed separately as
unconfirmed, never as a defect. **No findings is a valid result.**

**Architecture:** this skill is `code-review` in `contracts/agent-architectures.tsv`: `review` lens
agents (haiku/medium), an `audit` verifier per finding (sonnet/medium), and a `verify` adjudicator
(opus/high) only when two verifiers disagree. A lens never verifies; a verifier never raised the finding.

Why this shape: in the harbor#818 trial, a single reviewer of any tier found every planted
defect. The *extra* real bugs came from different runs noticing different things. Copies of
one prompt mostly repeat each other. Every added reviewer also adds false positives, and a false
positive is a defect (№2.11), so the verify step is the half that makes the fan-out safe.

## 1. Scope

Get the diff and its file list: `gh pr diff <N>`, or `git diff <base>...HEAD`. Pick the tier.
**No tier is a single agent.** Every tier runs at least one lens subagent, then a separate
verifier subagent that did not raise the finding, then the merge (§3).

| Tier | Lenses | Verify |
|---|---|---|
| quick (one-line or docs-only) | the one lens that fits (docs: Contracts) | one Sonnet verifier per finding |
| standard | all nine | one Sonnet verifier per finding |
| deep (security-critical, or a verifier disagrees) | all nine | two Sonnet verifiers per finding, so they can disagree (§5) |

## 2. Deterministic lints first, then the lenses

**Lints before lenses.** A lens judges only what no lint can. Before any lens runs, run the repo's deterministic lints on the
change and keep their output: in harbor, `sh bin/lint-name.sh --changed`, `sh bin/lint-conventions.sh`,
`sh bin/doc-fresh-verify.sh` and, for a PR, `sh bin/lint-pr.sh --title <t> --body-file <f> --branch <b>`; in another repo,
`sh vendor/naming/lint-name.sh --changed` and the lint entry points its `AGENTS.md` "Tests and CI" section names. A lint
finding is reported as the lint's, never re-raised by a lens: paste the lint output into every lens prompt as already reported.

**Lenses — one subagent each, in parallel, in waves of 5 at most.** The nine briefs are in `lenses/` beside this file; each
holds its question, rules and reply format. The last three are the standards lenses: each holds ONE of Harbor's own rule
sources, so a Haiku can hold all of it.

| Lens | Brief | The question it answers |
|---|---|---|
| Correctness | `lenses/correctness.md` | Wrong results, edge cases, broken callers |
| Failure handling | `lenses/failure-handling.md` | Errors swallowed, fallbacks that hide failure |
| Security and privacy | `lenses/security.md` | Injection, secrets, paths or identity leaking, egress, CONSTITUTION §3 and §4 |
| Contracts | `lenses/contracts.md` | Code that contradicts its own comments, docs, usage text or CONTRACTS |
| Tests | `lenses/tests.md` | Would the tests fail if this change were reverted? |
| Surroundings | `lenses/surroundings.md` | Existing defects in the code the change touches |
| Naming | `lenses/naming.md` | Every new or renamed name judged by `lint-name.sh --check <surface>`; a name with no surface, or on an uncheckable one, is a finding |
| Constitution | `lenses/constitution.md` | The `judgment` clauses of `policy/clauses.tsv` a diff can break (tokens in URLs, shell interpolation, rules with no mechanism, weakened gates), and a governed repo's own `AGENTS.md`/`.agents/` rules |
| Registration | `lenses/registration.md` | A new check, hook, notifier, lint or injector without its `controls.tsv` row, off switch, emitted id, red-once proof or finding destination; a rule list that can be empty with no alarm |

Every lens is `subagent_type: general-purpose`, **`model: haiku`, `effort: medium`**. No plugin
is needed. Pass `model` always (`context-rules/user/agent-model-required`).

**Restate every constraint in each brief.** A rule that sits only in a skill is not followed;
the same rule in the request is. Paste the lens brief into the prompt and add:
- the diff (PR number or base ref);
- the lint output from the step above, as already reported;
- read-only, change nothing;
- report only real defects, and `[]` when there are none;
- reply with only a JSON array (schema: `contracts/finding.md`, "The review-tier finding").

A lens that errors, runs out of turns or returns non-JSON is **failed**, never "none": re-run it
once, then report the lens as failed.

## 3. Merge

Deduplicate yourself. Two findings are one when they name the same file, lines within ±2 of
each other, and the same claim. Keep the strongest evidence and record every lens that raised it.
Give each finding its `raised_by` (the lens agent id). This step also runs when no lens raised
anything: the report then says none were found.

## 4. Verify — every finding, by an agent that did not raise it

One **new** subagent per finding (`model: sonnet`, `effort: medium`; batch up to 5 findings per
agent when there are more than 10). A verifier is never a lens agent and never the agent that
raised the finding: record its agent id beside the finding. The verdict is one of three:
- **CONFIRMED**, with a command that reproduces it and its output, or the quoted line beside
  the quoted text it contradicts;
- **REFUTED**, with the reason;
- **UNVERIFIABLE**.

Only a CONFIRMED finding is a defect.

## 5. Escalate

Run the deep tier on a finding when it is security-critical, or when its verifier says
UNVERIFIABLE. Deep means a second Sonnet verifier, independent of the first and given no
verdict from it. If the two verdicts differ, `opus` adjudicates as a third subagent that raised
and verified nothing. Record all agent ids.

## 6. Report

List confirmed findings, most severe first. Each one gives `file:line`, the claim, the
evidence, the lens agent id, the verifier agent id(s), and `FIXED / NOT FIXED`. Then list the
unconfirmed findings under their own heading. Then one line: lenses run (and failed), findings
raised, confirmed, refuted.

## Keeping it honest

This shape is not measured yet. After each review, add one row to #818: findings raised,
confirmed, and whether a single Sonnet reviewer would have caught them. That comparison is a
measurement only: the shipped skill has no single-agent path at any tier.
