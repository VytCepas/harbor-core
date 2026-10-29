---
name: housekeeping
description: "Reclaim a drifted box: the measured trash classes that accumulate here, the detector for each, and — the load-bearing half — the things that LOOK like trash and are live. Every class carries a safe-to-delete predicate and what breaks if you get it wrong. `bin/housekeeping-clean.sh` decides the machine-decidable part and is --dry-run until told otherwise; the rows only a person can decide (merged branches, finished worktrees, green PRs, done issues) come to the operator as ONE batch. USE WHEN the statusline shows 🧹 or SWEEP, clean up, sweep, free disk space, the box feels cluttered, tidy the fleet, obsolete worktrees or branches, stale sessions, what is safe to delete, disk is full, prune caches, retire a PR nobody will merge, merge what is waiting, garbage collect. NOT FOR deleting one file you can already name, or a repo's own build artefacts (its justfile owns those)."
argument-hint: [--apply] [class]
disable-model-invocation: true
---

# housekeeping

## Ideal state

**Nothing that is still load-bearing is deleted, and nothing that is dead is
kept because nobody could tell.** Done looks like: every reclaimed class named
with the bytes it returned, every *refused* class named with the reason it was
refused, and a reader able to re-run each verdict from the command in its row.

The failure this exists to prevent is not a full disk. It is a confident sweep
that removes a recovery path, a live plugin's state, or the only copy of
something — and reports success. So the deliverable is a decision per class,
never a total.

**Two verdicts are both real answers, and one of them is the more common:**

- **Reclaim** — dead by a stated predicate, regenerable or already preserved.
- **Refuse** — looks like trash, is not. Say which predicate saved it.

## When the statusline says 🧹 or SWEEP

`🧹N` is the count of rows that need a person; `SWEEP N ·age` means it is due —
at least one RISK row, or enough DECIDE rows. The fleet refresher records it at
09:00 and 16:00 (`bin/housekeeping-clean.sh --record`, check `sweep` in `docs/reference/checks.md`).

**Done looks like:** every DECIDE and RISK row has the operator's disposition —
**act**, **keep** (with a reason), or **later** — asked in **one batch grouped by
class**, each row showing its subject, reason and the exact command. What was
acted on is done through each repo's own gate, and a re-record afterwards shows
the count dropped by what was acted on. The operator never has to read a row
twice: a *keep* lands in `~/.claude/.helm-sweep-keep` as
`class<TAB>subject<TAB>reason`, and that row stops counting.

The rows: `~/.claude/.helm-sweep.jsonl` if under an hour old, otherwise
`sh ~/port/harbor/bin/housekeeping-clean.sh --json`. An aggregated row (`old-scratch`,
`old-downloads`) lists its members with `sh ~/port/harbor/bin/housekeeping-clean.sh <class>`.
Re-record with `sh ~/port/harbor/bin/housekeeping-clean.sh --record --live`.

The gates, none of which a batch approval waives:

- **The yes covers the batch shown and nothing else.** A row that appears after
  the question — a re-scan, a new PR — is the next batch.
- **RISK rows are never in a delete batch.** Each is work that exists in one
  place. Show it first (`git diff`, `git stash show -p`, `git log <oid>..<b>`),
  then offer: push it to a PR, commit it, turn the stash into a branch, or
  discard — the last only on a yes for that row by name.
- **Bundle before the first ref delete** (below). `git branch -D` on a
  squash-merged branch is only safe because the PR carried every commit, and the
  row says so only when that was proven; a row that says *unproven* gets a look.
- **Merge through the repo's gate**: harbor's rows carry `sh bin/gate-merge-check.sh
  --merge N --squash --delete-branch`. After a merge, diff what actually closed
  against what the PR claimed (memory `would-close-is-a-closing-keyword`).
- **Deleting a GitHub branch and closing an issue are outward** — they belong to
  the batch only because the operator saw them listed. Close with a comment
  that carries the row's reason.
- **Pulling or switching a main checkout moves files under any session working
  there.** Check the statusline's `SHARED TREE` and the live sessions first.

## Read this before deleting anything

`bin/housekeeping-clean.sh` is the mechanism; run it with no flags for a dry run.
`references/classes.md` carries the measured table: every class, its detector,
its safe-to-delete predicate, its growth rate where measured, and the incident
that put it in the table.

## The four rules that survived contact

**1 · Uncommitted work is the most expensive thing on the box, and `git status`
is not enough to find it.** Concurrent sessions revert uncommitted work while
`git status` reads clean (memory `concurrent-sessions-revert-uncommitted-work`).
Measured 2026-09-06: a workload repo held **69 uncommitted lines** of `docs/decisions/rejected-approaches.md`
— two dead ends from a Citadele session, the kind of knowledge nothing
regenerates. A sweep that started with `rm` would have destroyed it. So the
FIRST action of any cleanup is to find and commit unsaved work, before a single
byte is reclaimed.

**2 · A backup you delete is a recovery path you delete.** Prefer consolidating
to removing when a thing is small. Twelve loose `settings.json.bak.*` files were
132 KB and some were the only copy of a July state; they were **moved into
`~/.claude/backups/`**, not deleted. 132 KB is never worth a lost restore.

**3 · Look at the thing before removing it, and look at BOTH copies before
calling one redundant.** The `Mac` memory shard read as 51 poorer duplicates of
the canonical shard. A size comparison said three were *richer*; a line-level
union said **27 of 51 carried lines that existed nowhere else**. A plain delete
would have silently lost content from 27 sessions. Merge by union, then assert
absorption line by line, then remove.

**4 · A test suite can leak into the repo it tests.** Running
`projects-orchestrator`'s pytest suite set **`core.bare = true` on the operator's
real checkout**, registered 6 worktrees in it, and left 6 branches behind. The
symptom is indirect — a fresh worktree shows hundreds of staged deletions — and
`git status` in the main checkout reads clean. Always check `git config --get
core.bare` and `git worktree list` for `prunable` after running a suite that
touches git.

## What is NOT trash, however much it looks like it

This list is the reason the skill exists. Each was a candidate this session and
each was **refused on evidence**:

| looks dead | actually | how you know |
|---|---|---|
| `~/.claude/security/agent-sdk-venv` (282 MB, untouched 50d) | LIVE plugin state | `ensure_agent_sdk.py` in the `security-guidance` plugin recreates it — grep the plugin tree before believing a venv is orphaned |
| `~/.claude/.helm-replay/` (820 KB, 31d) | LIVE corpus | `eval-replay.sh`, `eval-replay-corpus.sh` and `eval-pass-score.sh` read it |
| `~/.claude/backups/` (139 files) | the recovery store | `deploy-restore.sh`'s subject; it grows one file per install by design |
| `~/.claude/.helm-*` pins, salts, teeth | floor state | deleting breaks `guard-integrity`; the obs salt makes the ledger unreadable |
| an old unmerged branch | unlanded work | `merge-tree --write-tree` vs `origin/main`; only a tree EQUAL to main's is landed |
| a worktree in another session's scratchpad | another live session | it still exists on disk and `worktree prune` refuses it — `hb-444` was on `c2-clean` |
| runner `_work/` while a runner is busy | an in-flight job | `gh api repos/<r>/actions/runners` → `busy` |
| `~/.claude/projects/` transcripts | harness-managed | `cleanupPeriodDays` (default 30) owns these; do not hand-prune |

**`git cherry` is not the tool for the landed question** — it misclassifies
cherry-picks (memory `git-cherry-misclassifies-cherry-picks`). Use
`merge-tree --write-tree` and compare to `origin/main^{tree}`.

## Before the first delete

**Bundle every ref in every repo, and verify the bundle restores.** A backup
that cannot restore is not a backup:

```sh
git -C <repo> bundle create ~/Deliverables/<date>-cleanup/<repo>-all-refs.bundle --all
git bundle verify ~/Deliverables/<date>-cleanup/<repo>-all-refs.bundle
```

Ten repos cost 20 MB and thirty seconds. This is the precedent set by
a dated branch-cleanup deliverable of 2026-09-03.

## The guards will stop you, and they are usually right

Cleanup shapes trip the floor by design. Do not reach for
`HARBOR_ADMISSION_DISABLE=1`; change the command:

- `find … -delete` rooted under `$HOME` → `find-xargs-spray`. Add a selective
  filter (`-name '*.log'`) and name one directory, not a home-rooted set.
- `rmdir ./*/` instead of `find -delete` for empty directories — it *cannot*
  remove a non-empty one, which is a stronger guarantee than a filter.
- `rm -rf` under `~/.claude` is denied. `mv` the directory out instead, once its
  content is provably absorbed and archived.
- `cp` of a `.plist` reads as `unit-file-install` even when copying *out* of
  `~/Library/LaunchAgents`. Use `cat`, or the file tools.
- An interpreter pointed at `~/.claude/bin/…` is `interpreter-at-surface`. `cat`
  the file to a scratch path and analyse the copy; use `jq`, not `python`, on
  `settings.json`.

A guard refusing a cleanup command is the cheapest possible reminder that the
command was broader than the intent.

## Then hand over what changed

Reclaimed bytes per class, refused classes with their reason, and the bundle
path. A cleanup with no refusal list read as thorough is a cleanup nobody can
audit.
