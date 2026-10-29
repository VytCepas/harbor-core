---
description: Check a PR against the merge backstop, report the verdict, and stop for a decision
argument-hint: <pr-number>
allowed-tools: Bash(sh ~/port/harbor/bin/merge-check.sh:*), Bash(gh pr view:*), Bash(gh pr checks:*)
---

Run the merge backstop for PR **$1** and report. Do not merge.

!`sh ~/port/harbor/bin/merge-check.sh $1 2>&1 | tail -30`

Branch protection, separately — a private repo on a free plan gets a 403 from
the protection endpoint and every rule silently stops applying, with nothing
turning red anywhere in the UI:

!`sh ~/port/harbor/bin/merge-check.sh --protection 2>&1 | tail -12`

Report in this order:

1. **The verdict, first line.** May this merge, yes or no.
2. **Any red or cancelled check by name.** A *cancelled* run scores as failing
   against a required context and never clears — that is a real block with a
   misleading cause, and it has cost this repo a morning before.
3. **Whether protection is still enforcing.** If the answer is no, say so before
   anything else: every other check in this report is then advisory.
4. **The exact command to merge**, for the operator to run or not.

**Then stop — unless the operator has already said to merge.** This command
reports, and merging is normally a separate decision and a separate keystroke.

**An explicit operator go-ahead in this session IS that decision.** If they have
said to merge — in so many words, or by choosing an option that named merging —
then a green verdict is the trigger, not a prompt: run
`sh ~/port/harbor/bin/merge-check.sh --merge $1` and report the merge commit. Do not
re-ask. Settled 2026-08-25, when this file's "stop there" was read as outranking
a yes the operator had already given, and the operator's answer was *"if I allow
merges then it is ok"*.

Absent that go-ahead, report and stop. The gate is against merging on the
model's own judgement, never against the operator's instruction — and a report
that stops after a person has already decided is friction, which is how a gate
gets ignored on the occasion it matters.

Three things the go-ahead does NOT extend to, because none of them is what was
approved:

- **A red or cancelled verdict.** Approval was to merge a green PR. Say what
  would have to change; never reach for `--admin`, which bypasses required
  checks and leaves no record outside the audit log, where
  `sh ~/port/harbor/bin/merge-check.sh --merge $1 --force` writes the override into
  the merge commit itself.
- **Protection having silently stopped enforcing** (§3 above). Then the verdict
  is advisory and the operator is approving something other than what they
  think.
- **A later PR.** Approval is per-merge and per-session, like every other
  outward-facing act in this repo.

Every path here is absolute on purpose: a slash command runs in whatever cwd the
session has, and `sh bin/…` resolved to nothing from anywhere but the repo root.
