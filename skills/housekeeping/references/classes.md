# The measured trash classes on this box

Every row was **measured on 2026-09-06** during the sweep that produced this
skill. Sizes are that day's; the detector is what re-measures them, and the
predicate is what makes a delete safe. Where a class has an incident, it is
named — a rule whose reason has been deleted is one nobody can re-examine.

`bin/housekeeping-clean.sh` implements the machine-decidable rows. The rows it does
**not** implement are marked *judgement* and say why.

## A · Session residue (harness-written, high count, low bytes)

| class | measured | detector | safe when | notes |
|---|---|---|---|---|
| `~/.claude/session-env/<uuid>/` | **1,134 dirs, 0 files, 0 B** | `ls ~/.claude/session-env \| wc -l` | the directory is EMPTY | one per session, never reaped. `rmdir ./*/` — it cannot remove a non-empty one, which beats any filter |
| `~/.claude/shell-snapshots/` | 25 files, 300 KB | `ls` | older than the oldest live session | a snapshot is sourced by a running shell; check `ListAgents`/live sessions first |
| `~/.claude/paste-cache/` | 43 files, 304 KB | `ls` | older than the retention you want | cheap; low priority |
| `~/.claude/file-history/` | 5,021 files, **124 MB** | `du -sh` | *judgement* | this is the undo history for file edits. Age-prune only; never wholesale |
| `~/.zsh_sessions/` | 354 entries | `ls` | shell not running | macOS shell history shards |

## B · Harness-managed — do NOT hand-prune

| class | measured | who owns it |
|---|---|---|
| `~/.claude/projects/**.jsonl` | **1.3 GB**, nothing older than 27 days | `cleanupPeriodDays` in settings.json (default 30). The harness already reaps these; the histogram proves it works. Hand-pruning here removes the transcripts every audit and usage ledger reads |
| `~/.claude/.last-cleanup` | — | written by the harness, not by harbor. Its presence is why "nothing cleans this box" was a false premise about *transcripts* only |

Lowering `cleanupPeriodDays` is the supported lever. Deleting transcripts by
hand is not, and `status-usage-aggregate.sh` reads them.

## C · Build and CI residue (the real bytes)

| class | measured | detector | safe when |
|---|---|---|---|
| runner `_diag/*.log` | **859 MB total, 210 MB older than 14d** | `find <runner>/_diag -type f -mtime +14` | always for logs; unbounded and unrotated by the GitHub runner | 
| runner `_work/` | 634 MB | `du -sh` | **only while every runner reports `busy: false`** — `gh api repos/<r>/actions/runners`. Deleting forces a re-clone, so age-prune per-repo subdirs instead |
| `__pycache__` / `*.pyc` inside a payload or template dir | 2 files | `find <payload> -name '__pycache__'` | always | **not merely clutter** — see the incident below |
| `~/.playwright-mcp/` | 94 dirs, 4.7 MB | `ls` | session ended | one per browser session |
| `.DS_Store` | 26 KB at `$HOME` alone | `find . -name .DS_Store` | always | Finder rewrites them |

### Incident · bytecode inside a payload dir is not cosmetic

`project-init`'s `payload_sha256` walked `plugin_root.rglob("*")` and hashed
everything. `hooks/prod_guard.py` is importable, so any local run wrote
`__pycache__/prod_guard.cpython-*.pyc` **inside the hashed payload**. Result:
`test_lock_matches_the_committed_tree` failed locally while the same SHA was
green on CI, whose checkout has no bytecode. A tripwire firing on an artefact of
running the thing it guards is the false positive No.2.11 forbids — and PI-881's
real job is catching a stale plugin. Fixed in project-init#972; the class stays
in this table because the same shape reaches any content-hash over a source tree.

## D · One-off caches and dated artefacts

| class | measured | safe when |
|---|---|---|
| `~/.claude/cache/harbor-archive-<date>.bundle` | 4.3 MB | the archive it backed is landed or preserved elsewhere |
| `~/.claude/cache/cu.pre-<migration>-<date>` | 160 KB | a pre-migration binary; the migration shipped |
| `~/.claude/gh-pr-status-cache.json` | 4 KB, 30d stale | nothing greps for it |
| `~/.claude/daemon.log`, `daemon-auth-*` | 20 KB, 18d | the daemon is not running |
| `~/.claude/jobs/<id>/` | **28 MB**, newest 18d | harness background-job records; no harbor script reads them |
| `<repo>/fleet.yaml.bak.<ts>` | 4 KB | the live file is known-good |
| loose `settings.json.bak*`, `CLAUDE.md.bak` at `~/.claude` root | 132 KB | **CONSOLIDATE, never delete** — move into `~/.claude/backups/`; some are the only copy of an older state |

## E · Git state

| class | detector | safe when |
|---|---|---|
| landed local branch | `git merge-tree --write-tree origin/main <b>` == `origin/main^{tree}` | tree equal to main's. **Never `git cherry`** — it misclassifies cherry-picks |
| landed remote branch | same, against `origin/<b>` | same, and bundled first |
| worktree whose branch landed | `git worktree list` + the predicate above | 0 uncommitted files AND 0 unpushed commits |
| **prunable worktree registration** | `git worktree list \| grep prunable` | its gitdir is gone — `git worktree prune -v` |
| **stray branch left by a test suite** | branches matching the suite's naming (`work/alpha-*`, `heal/*`) pointing at a commit already on a pushed branch | the commit is reachable from a remote ref |
| **`core.bare = true` on a real checkout** | `git config --get core.bare` | *never trash — this is damage.* `git config --unset core.bare` |
| no-op open PR | `merge-tree` of its head == main's tree | merging it would change nothing; close, don't merge |

### E2 · What only the PR knows (the GitHub layer, 2026-09-22)

A squash merge leaves a branch whose tree is **not** main's, so the rows above
never claim it; the PR is the evidence. `housekeeping-clean.sh` reads each repo's PRs,
branches, open PRs and open issues once, and every class below joins against
that read. A repo it cannot read is reported `unread` — its rows are missing,
never clean. Verdicts: **DECIDE** needs a person; **RISK** is work that exists in
one place. `--apply` touches neither.

| class | detector | verdict |
|---|---|---|
| `finished-worktrees` | a non-main worktree whose branch's newest PR is merged or closed, or with no PR and no commit for `IDLE` days | DECIDE when clean and every commit is in the PR head; **RISK** with uncommitted changes, or with commits after the PR that no remote holds (pushed, they are DECIDE); KEEP while a live session's cwd is inside it |
| `pr-branches` | a local branch no worktree holds, not landed by tree, whose PR is merged or closed | DECIDE when the PR head contains the tip; **RISK** when the tip has commits after it that no remote holds, DECIDE once they are pushed; with no PR, **RISK** if no remote ref contains it after `IDLE` days (the only copy), DECIDE if pushed and idle twice that |
| `remote-branches` | a GitHub branch whose newest PR is merged or closed | DECIDE: delete when it sits at the PR head, *look* when it moved after. A branch with no PR is not counted — the list carries no date |
| `stale-checkouts` | the main checkout's default branch behind GitHub's, or the checkout parked on a branch whose PR is done | DECIDE (a pull moves files under any session there); **RISK** when local main has commits GitHub's does not |
| `waiting-prs` | an open PR green and mergeable for a day, red for two, or silent for twice `IDLE` | DECIDE |
| `closable-issues` | an open issue with no unticked box AND every done-when box ticked, every sub-issue closed, or a merged PR claiming to close it — an unticked box vetoes the rest | DECIDE |
| `old-stashes` | a stash `IDLE` days old | **RISK** — a stash exists in one clone only |
| `stray-files` | an untracked, un-ignored top-level entry in a main checkout, a day old | DECIDE |

**Measured 2026-09-22, the first run:** 96 DECIDE and 14 RISK rows across the
fleet, in 62 seconds. Of the RISK rows, 9 were branches on no remote and in no
PR, 4 carried commits made after their PR was merged or closed, and 1 was a
stash. One of each of the first two kinds was confirmed by hand against git and
GitHub (`<repo> docs/<client>-data-quality-findings`; `<container>/<repo>-wt-mta-mirror`,
one commit after PR #59 closed); the rest are the tool's word.

### Incident · a test suite leaked into the repo under test

Running `projects-orchestrator`'s pytest suite (`uv run pytest -n auto`) on
2026-09-06 set **`core.bare = true` on `~/projects-orchestrator`**, registered 6
worktrees inside it pointing at `/private/var/folders/.../pytest-of-*/`, and left
6 branches (`b`, `heal/lint-alpha-*`, `work/alpha-*`). The main checkout's
`git status` read clean throughout; the tell was a *new* worktree showing 264
staged deletions. After a suite that touches git, check:

```sh
git config --get core.bare          # must be empty for a working checkout
git worktree list | grep prunable   # then: git worktree prune -v
git for-each-ref refs/heads         # for names no human chose
```

## F · Stores that fork or regrow

| class | measured | detector | fix |
|---|---|---|---|
| **host-sharded store forked in two** | `WORK/sessions/Mac/` (51 files) beside `<owner>s-MacBook-Air/` (807) | `memory-lint.sh` → collisions; `ls <store>/*/` | union-merge, ASSERT absorption line by line, archive, then remove. 37 collisions → 0 |
| MEMORY.md over its byte ceiling | 12,387 B; worst case 40,569 vs 40,000 | `bin/context-budget.sh` | move task-specific pointers to `INDEX-FULL.md`. **Third time in four days** (09-03, 09-04, 09-06) — this regrows weekly, so it is maintenance, not a repair |
| `registries/context-baseline.tsv` stale | recorded 21,844 vs measured 28,182 | `context-budget.sh --check` | `--record`, then write an ATTRIBUTED reason. Recording without attribution defeats the instrument |
| dangling memory wikilinks | 3 | `memory-lint.sh` | write the note, or drop the link |

### Why the host fork happens, and why it stopped

`hostname -s` on macOS reports the DHCP/DNS-supplied name, and with
`scutil --get HostName` unset — the macOS default — it falls back to the literal
`Mac`. Measured live on 2026-09-06: `scutil --get LocalHostName` →
`<owner>s-MacBook-Air`, `hostname -s` → `Mac`. Every host-sharded ledger forks
in place when the network changes, and **nothing errors**. `floor_host_token`
now reads `LocalHostName`, so the `Mac` shard's newest file is 2026-08-06 — the
mechanism is fixed and the residue was historical. Any NEW shard directory
appearing beside the canonical one means the pin has been bypassed.

## G · Deliverables and documents

| class | detector | fix |
|---|---|---|
| loose document in `$HOME`, `~/Desktop`, `~/Documents`, `~/Downloads` | `find . -maxdepth 1 -type f -not -name '.*'` | move into `~/Deliverables/<YYYY-MM-DD>-<slug>/`, append a row to `MANIFEST.md`. `guard-deliverables.sh` denies NEW ones; these predate it |
| an ad-hoc output directory (`~/reports/`) | a dir holding one dated document | same — the guard covers four locations, not every name someone invents |
| dead session scratchpads under `/private/tmp/claude-501/` | dir whose session is not live | `ListAgents` first; another session's scratchpad may hold its worktree |

## What this table deliberately does not do

**No total.** A headline "freed N GB" invites the sweep this skill exists to
prevent. The 859 MB figure for runner logs is the class size; the >14d cut
actually returned 210 MB, and reporting the first as if it were the second is
the kind of drift No.2 forbids.

**No schedule.** Nothing here is registered in `docs/reference/checks.md`, on purpose: that
file is the register of things that run on a schedule, lint X9 requires a
tracked plist for every row in it, and a row for a hand-run command would make
X9 report a plist that should not exist. Deciding what to delete is a
human-gated act — "Encoding a fix is a human-gated act" applies with more force
to a tool whose verb is `rm`.
