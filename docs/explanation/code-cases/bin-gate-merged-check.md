---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/gate-merged-check.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/gate-merged-check.sh, lines 2-91 (before this edit)

```text
merged-check (harbor#213) — answer "is this branch's work already in BASE?" by
CONTENT, because this repository's merge method is not fixed.

THE MERGE METHOD IS A SETTING, NOT A PROPERTY OF THE REPO, and this header said
otherwise until 2026-08-29: "for a repository whose every PR lands as a squash
merge". That was true of the fortnight harbor#213 was written in, and false on
both sides of it. GitHub permits all three methods here — `squashMergeAllowed`,
`mergeCommitAllowed` and `rebaseMergeAllowed` all measured true — and the
operator uses more than one. Measured 2026-08-29 over the whole of
`origin/main`: 219 first-parent landings — 86 merge commits, 84 squashes, 49
direct commits — and the mix is not a phase it grew out of, because 82 of those
landings are since 2026-08-16 and they split 54 merge / 28 squash. What made
the old premise plausible is that it was written inside 2026-08-13/14, a window
that genuinely was squash-only.

THE FAILURE DIRECTION OF A SINGLE-MODEL ASSUMPTION IS `absent`, NOT `merged`,
and that is worth stating because it sounds like the safe kind of wrong. Drop
the content tests believing everything is a merge commit and squashed branches
read `absent`: nothing is destroyed, a `--force` is printed, and the gate is
ignored from then on. That is harbor#213's actual complaint, and it is a slower
way to lose the work than deleting it.

WHY THIS EXISTS. Three tools asked that question with commit REACHABILITY:
  bin/deploy-install-stamp.sh   git rev-list --count "$cur..$old"     → refused a deploy
  bin/worktree.sh        git merge-base --is-ancestor           → refused `retire`
  bin/govern-hook.sh     git merge-base --is-ancestor           → under-reported
A squash merge produces one new commit with a new SHA and one parent, so a
squash-merged branch is never an ancestor of main and all three were
false-negative on every branch that landed that way — each refusal naming a
bypass flag (`--allow-regression`, `--force`), which is how a gate that cries
wolf becomes a gate nobody reads (CONSTITUTION §2.11).

THE CORRECTION DOES NOT SHRINK THE TOOL, WHICH IS THE POINT OF MAKING IT. A
reader holding the old premise looks at test 1 (ancestor) and sees dead weight
kept for tidiness; a reader holding this one can see it answers the majority of
recent landings on its own. Each of the five is a sound sufficient condition by
itself, so the correct response to the method changing again is to change
nothing. What carries that guarantee is tests/gate/merged-check/merged-check.test.sh, which lands
the same work by every method the repo permits — a one- and a three-commit
squash, a real merge, a rebase replay — and not this paragraph, which is why the paragraph
was free to rot for two weeks while the suite stayed green and correct.

WHY NOT `git cherry`, WHICH harbor#213's OWN REMEDY PROPOSED. Because it is only
right when the branch holds exactly ONE commit. Measured 2026-08-14 in a scratch
repo, three branches against a squash-merging main:

  branch              commits  ancestor?  git cherry      total-diff patch-id
  squash-merged            1   no         0/1 absent  ✓   match      ✓
  squash-merged            3   no         3/3 absent  ✗   match      ✓
  genuinely unmerged       1   no         1/1 absent  ✓   no match   ✓

`git cherry` compares PER-COMMIT patch-ids, and a squash collapses N commits into
one, so no individual commit matches the squash for N>1. All five branches merged
into this repo on 2026-08-13/14 carried 2-3 commits, i.e. the case it gets wrong.
The predicate that held in every row is the patch-id of the branch's TOTAL diff
against the patch-ids of the commits BASE gained since the merge-base.

FIVE TESTS, CHEAPEST FIRST, and each one exists because it is the only one that
catches its case:
  1 ancestor            — a real (non-squash) merge or a direct commit. Nothing
                          else is needed and it costs one call.
  2 empty diff vs BASE  — the tree is identical to BASE. Catches a branch whose
                          content landed by ANY route, including a hand-applied
                          patch, and is what harbor#213 used to verify its claims.
  3 git cherry all `-`  — per-commit patch-equivalence. Keeps the N=1 squash and
                          the rebase/cherry-pick cases working, and is cheap.
                          It is the ONLY test that answers for a rebase-merge,
                          which was an assertion until arm 5b measured it:
                          delete this test and that arm alone goes red.
  4 total-diff patch-id — the N>1 squash case, which is the defect. Only reached
                          when the three above have failed.
  5 no-op merge         — a squash made against context the branch never had,
                          because a sibling landed nearby lines first
                          (harbor#634). A patch-id hashes context, so test 4
                          cannot match it; a clean merge that changes nothing
                          can. Costs a merge, so it runs only when 4 said no.
ORDER IS COST, NOT PRECEDENCE: any one of them answering "merged" is sufficient,
because each is a sound sufficient condition on its own.

FAIL TOWARD "ABSENT". Every unknown — a bad ref, a git that cannot answer, an
unreadable patch-id — reports `absent`, because the consumers delete worktrees
and skip regression warnings on `merged`. The permissive direction here destroys
work; the conservative direction costs one `--force`.

THAT PARAGRAPH WAS A WISH FOR TESTS 3 AND 4 UNTIL harbor#226. Both read a
command's OUTPUT and neither read its STATUS, and for both the output of failure
is byte-identical to the output of "merged" — empty. So the two tests that exist
to catch the squash case were the two that failed toward the destructive verdict.
The suite now forces each command to exit non-zero and asserts `absent`, which is
the only thing that keeps this paragraph true rather than aspirational.
```

## bin/gate-merged-check.sh, lines 109-110 (before this edit)

```text
The verdict lines are DATA that worktree.sh, govern-hook.sh and deploy-install-stamp.sh parse, so the run log
is on stderr and never mixes with them.
```

## bin/gate-merged-check.sh, lines 142-146 (before this edit)

```text
THE PATCH-ID INDEX IS BUILT ONCE, NOT PER REF. govern-hook.sh calls this at
SessionStart over every local branch, and `git show | git patch-id` per branch
per commit is the shape that made memory-lint a 27-second gate nobody could
afford to run. Built lazily: the common case is that test 1, 2 or 3 answers and
the index is never needed at all.
```

## bin/gate-merged-check.sh, lines 156-158 (before this edit)

```text
Rebuilt when the merge-base moves, because a different branch has a different
merge-base and an index keyed on the wrong one would answer about the wrong
window. Cached when it does not, which is the usual case for sibling branches.
```

## bin/gate-merged-check.sh, lines 169-193 (before this edit)

```text
TEST 5 — A PATCH-ID HASHES THE CONTEXT LINES, SO TEST 4 CANNOT SEE A SQUASH
THAT LANDED ON A BASE A SIBLING HAD ALREADY MOVED (harbor#634). Measured
2026-09-23: #623 and #624 were squash-merged back to back, #623 added a row
within three lines of the one #624 changed in docs/generated/status.md, and #624's squash was
therefore made against context its branch never had. Its patch-id could not
match, tests 1-3 did not apply, and `retire` refused a merged branch — the
`--force`-as-normal-path that worktree.sh's is_merged() calls a gate that has
stopped meaning anything. `git merge-tree --write-tree BASE REF` equalled
`BASE^{tree}` exactly, which is the content question asked directly: a clean
three-way merge that changes nothing means everything REF changed since the
merge-base is already in BASE. Test 2 is the special case with nothing extra.

ONLY A CLEAN MERGE COUNTS. Exit 1 is a conflict and anything else is a git
that cannot answer — including one older than 2.38, which has no
`--write-tree` and exits 129 — and every one of them is `absent`.

NOTHING IS WRITTEN INTO THE REPO. `--write-tree` stores merged blobs and trees
in the object database whenever both sides touched a file; govern-hook calls
this at every SessionStart over every local branch, so a check would leave
loose objects behind on each run. Measured: two per both-sides file. They go to
a scratch store instead, with the real one as an alternate for reading, and the
scratch store is removed on exit. Called as `git`, not `_git`: an assignment in
front of a shell FUNCTION persists afterwards under this box's /bin/sh (bash in
POSIX mode — measured; dash and zsh drop it), and every later call would then
write to the scratch store.
```

## bin/gate-merged-check.sh, lines 237-247 (before this edit)

```text
ASK GIT WHETHER IT SUCCEEDED BEFORE BELIEVING THE COUNT (harbor#226). The
count used to be read straight out of a pipeline — `_git cherry … | grep -c
'^+' || true` — and this comment used to argue the conflation was harmless:
"grep -c on empty input returns 0, so both spellings agree here without a
special case". They do not agree. `_git` discards stderr, so a cherry that
FAILS prints exactly what a ref adding no commits prints — nothing — `grep -c`
turns both into `0`, and `|| true` discards the one bit that told them apart.
`merged` is the DESTRUCTIVE verdict (worktree.sh:138 hands it to `gc`, which
removes the worktree), so the permissive reading here loses work. Reproduced
by forcing only `git cherry` to exit 128 against a genuinely unmerged topic:
the verdict moved from `absent` to `merged`.
```

## bin/gate-merged-check.sh, lines 256-267 (before this edit)

```text
4 · THE SQUASH CASE. The ref's total diff, as one patch-id, against the
patch-ids base gained since the merge-base.

THE SAME DEFECT, ONE STEP DOWN, AND THEY HAD TO MOVE TOGETHER (harbor#226).
`_bp="$(_git diff "$MB..$REF" | _patch_id || true)"` followed by "empty means
the branch adds nothing → merged" reads a failed `git diff`, and a failed
`git patch-id`, as evidence of an empty diff. Fixing test 3 alone routes MORE
refs into this line, so it would have made the surviving half worse.

Both statuses are checked now, and the two empties are separated: a diff that
SUCCEEDED and is empty still means `merged`, one that could not be taken or
could not be hashed means `absent`.
```

## bin/gate-merged-check.sh, lines 272-275 (before this edit)

```text
Round-trip through the variable is byte-preserving for this input: `$(…)`
strips the trailing newlines a diff has exactly one of, and it is added back.
Asserted rather than argued — the suite compares this patch-id against one
taken from a direct pipe.
```
