---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of hooks/pre-push

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## hooks/pre-push, lines 7-49 (before this edit)

```text

WHY HERE AND NOT AT COMMIT. hooks/pre-commit already pays for the guard smoke
suite when a floor surface is staged, and that is the right cost at that
moment: it is seconds, and it catches the class of regression that must never
reach a PR. Running the WHOLE selected set on every commit is how a hook
becomes the thing people reflexively `--no-verify`, and a gate that is
routinely skipped protects nothing (CONSTITUTION §2.11). Push is the moment
where the cost is proportionate — it happens once per branch, not once per
thought, and it is the last point before CI spends the runner.

THE SELECTOR DOES THE CONDITIONALITY, AND IT ALREADY EXISTS. bin/test-suite-select.sh
is CI-2's change-class decision procedure, declared in contracts/suite-paths.txt.
Reimplementing that here would be a second copy of a policy that lives somewhere
else, and it would drift in the direction that is silent — a local gate that
stands down MORE suites than CI does comes back green and shorter, which reads
as an improvement.

── THE DEFAULT IS NARROW, AND A MEASUREMENT IS WHY (harbor#7) ──────────────
The first cut of this hook ran every suite the selector picked, justified by a
demo: a docs-only push selects 2 of 25. `bin/eval-hook-replay.sh --commits` then
replayed all 143 real changesets in this repo's history through that same
selector, and the demo turns out to be the unrepresentative case:

    median suites selected   24 of 25
    selected EVERYTHING      37% of pushes
    selected 3 or fewer      22% of pushes

Harbor's commits touch bin/ almost every time, so the selector — which is doing
its job correctly — hands back nearly the whole suite on the median push. A
gate that runs 24 of 25 suites before every push is a gate that gets
`--no-verify`'d within a week, and a routinely-skipped gate protects nothing
(CONSTITUTION §2.11). It also duplicates CI, which runs the same selection on
the PR anyway.

So the default is the same pair pre-commit already proved affordable — the
conventions linter, plus the guard smoke suite when a floor surface is in the
pushed range — and the full selected set is opt-in via HARBOR_GATE_PREPUSH_FULL=1.
The cheap default still catches the class that must never reach a PR; the
expensive one is there for the push you actually want to be sure about.

THE RUNNER IS SERIALISED AND SELF-HOSTED, which is why the expensive mode
exists at all: a red push does not merely cost the author a round trip, it
occupies the single runner every other branch is queued behind.
```

## hooks/pre-push, lines 57-69 (before this edit)

```text
harbor#824: everything below this point that runs a suite or the linter goes through
hook_scrub_run (hooks/lib.sh), which drops the GIT_* vars git exports into this hook — a suite
that builds its own scratch git repo and drives it with `git -C <tmp>` must not inherit them.
The git calls ABOVE this line, and $ROOT itself, keep the real GIT_DIR on purpose: they need it
to see the repo the hook actually fired in.

hooks/lib.sh lives BESIDE THIS FILE, never assumed to be under $ROOT — $ROOT is the repo this
hook fires FOR (git rev-parse --show-toplevel), which a test fixture or a foreign repo that
copied only this file is not. Resolve this script's own real location, following the
`.git/hooks/pre-push` symlink the install step creates ($0 stays the symlink path, unresolved,
per POSIX exec). A copy with no lib.sh beside it degrades to an unscrubbed run rather than
crashing the hook outright — Harbor's own checkout (primary or any worktree) always ships both
files together, so a real Harbor push always gets the scrub.
```

## hooks/pre-push, lines 80-82 (before this edit)

```text
A PASS ALREADY PAID FOR BEFORE THE CONNECTION (harbor#1411). git holds the App token from connect to pack send, so
a long hook ends in HTTP 401. `sh bin/gate-push.sh` runs this hook under `git push --dry-run`, records the pass, then
pushes; gate-push.sh check answers 0 only for that exact sha, push and check set (the lines below). Else: full run.
```

## hooks/pre-push, lines 92-94 (before this edit)

```text
ONE CPU SLOT PER CHECK, through bin/ci-governor.sh, which shares this Mac's cores between CI and local runs.
Output is discarded either way; the governor's own "waiting for a slot" line stays on stderr. A checkout
without the governor, or a box whose governor never ran (no state dir), runs the check directly.
```

## hooks/pre-push, lines 100-114 (before this edit)

```text
THE RANGE COMES FROM STDIN, WHICH IS THE ONLY PLACE IT IS ACTUALLY KNOWN.
git feeds pre-push `<local ref> <local sha> <remote ref> <remote sha>` per ref,
and <remote sha> is what the remote has RIGHT NOW — more accurate than
origin/<base>, which is only as fresh as the last fetch. An all-zero remote sha
means a brand-new branch with no remote counterpart; there is no honest range
for that, so it falls through to the selector's own default rather than
inventing one.

A PUSH OF ONLY DELETIONS HAS NO SUBJECT (harbor#575). The per-ref `continue`
below skipped the range for a deleted ref and nothing else, so control fell
through to the repo-wide linter: 2:31 on this box to ask a question no deletion
can change the answer to, since the remote's trees and blobs are untouched. The
decision is over the WHOLE push, never one ref — `git push origin :old main`
deletes `old` AND publishes `main`, and must still run the checks. `--delete`
is not the mixed case: git applies it to every listed ref.
```

## hooks/pre-push, lines 127-128 (before this edit)

```text
SAY IT STOOD DOWN, NEVER PRINT NOTHING. A silent hook on a deletion push reads
exactly like a hook that did not fire (harbor#466), so the reason is printed.
```

## hooks/pre-push, lines 145-147 (before this edit)

```text
A STALE GENERATED FILE FAILS HERE, IN SECONDS (harbor#1287). 7 of 12 failed PR runs 2026-10-14..17 were one, found only
after the 15-20 min CI pool. bin/doc-fresh-verify.sh runs every generator --check that answers in seconds (contracts/fresh-checks.tsv)
and names the fix; it goes BEFORE the linter and the suites because a stale file makes the rest of the run moot.
```

## hooks/pre-push, lines 180-190 (before this edit)

```text
THE ONLY LOCAL RUN OF THE LINTER, since 2026-09-05. It used to run here AND
unconditionally in pre-commit, so a session of ten commits paid 62s eleven
times for one answer. hooks/pre-commit says why it moved; the short version
is that the linter is repo-wide, so it cannot be filtered by staged path,
and the push is the boundary where paying once is proportionate.

GUARD THE LINTER'S EXISTENCE, the same way the selector is guarded above.
Without this the hook exits 1 in any repo that has no lint-conventions.sh —
rejecting a perfectly good push because a tool is absent, which is a gate
failing OPEN into a block. Found by the repaired ref-deletion case on its
first run, in a scratch repo that had a selector stub and no linter.
```

## hooks/pre-push, lines 197-201 (before this edit)

```text
SAME TRIGGER AS pre-commit, applied to the whole pushed RANGE rather than one
commit — which is the only thing this hook can see that pre-commit cannot.
`case` globs, not grep: this box's grep is a ugrep wrapper carrying
`-I --ignore-files` and a matcher whose behaviour depends on PATH order means
something different on the CI runner.
```

## hooks/pre-push, lines 214-224 (before this edit)

```text
THE COUNT MIXED TWO POPULATIONS AND WAS OFF BY ONE. It reported
"<all suites> - 1" while `lint-conventions.sh` is not in suites.txt at all
and `floor-test.sh` — which IS in it — had just run. So "2 run, 24 not run"
counted different things on each side of the comma, in the number the
comment below calls this hook's honesty mechanism. Now it counts exactly the
manifest suites this run did not execute.

`grep -c` EXITS 1 ON ZERO MATCHES, and under `set -eu` an assignment from a
failing substitution kills the shell — a degenerate suites.txt would have
aborted the push after every check passed, with no message at all. `|| true`
is the whole fix and it is not cosmetic.
```

## hooks/pre-push, lines 230-231 (before this edit)

```text
A SILENT CAP READS AS FULL COVERAGE. The stood-down count is printed on every
run, so "the gate passed" can never be confused with "the gate ran everything".
```
