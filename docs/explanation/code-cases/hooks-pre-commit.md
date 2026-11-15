---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of hooks/pre-commit

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## hooks/pre-commit, lines 3-3 (before this edit)

```text

```

## hooks/pre-commit, lines 6-6 (before this edit)

```text

```

## hooks/pre-commit, lines 7-26 (before this edit)

```text
── THE CONVENTIONS LINTER MOVED TO pre-push (measured 2026-09-05) ───────────

It ran here, unconditionally, on every commit. The comment below already
argues why that is wrong — "paying that on every commit is how a hook becomes
the thing people reflexively bypass, and a gate that is routinely skipped
protects nothing" — and then the linter was exempted from its own argument by
a stale number. That comment priced it at ~14s. MEASURED ON THIS BOX TODAY IT
IS 62s, and the profile is flat: 67 rules, worst rule 9s, no hotspot to fix.
It grew, and nothing re-read the price.

Sixty-two seconds times every commit in a session is the cost, and it buys
nothing pre-push does not: the linter is REPO-WIDE (T2 counts, T3 links, C3/C5
manifests), so a staged-path filter cannot make it honest — any change can
break any rule. The choice is every commit or once per push, and once per push
is where the boundary already is. hooks/pre-push runs it, CI enforces it as a
required check, and a violation is still caught before it becomes a PR.

WHAT STAYS HERE IS THE PART THAT CANNOT MOVE. The smoke suite below judges the
STAGED tree (`git checkout-index`), which is a fact only this hook can see —
pre-push sees a range of commits, not an index.
```

## hooks/pre-commit, lines 30-37 (before this edit)

```text
harbor#824: the smoke suite below goes through hook_scrub_run (hooks/lib.sh), which drops the
GIT_* vars git exports into this hook before running it — see hooks/lib.sh for why. The
`git rev-parse`/`git diff --cached`/`git checkout-index` calls in this file keep the real
GIT_DIR; they need it to see the tree actually being committed.

hooks/lib.sh lives BESIDE THIS FILE, never assumed to be under $ROOT (see hooks/pre-push for
the full reasoning — a test fixture or a foreign repo that copied only this file is not
Harbor's own checkout, and $0 stays the symlink path, unresolved, per POSIX exec).
```

## hooks/pre-commit, lines 48-69 (before this edit)

```text
── M11 (harbor#44) · guard BEHAVIOUR, not just style, when the floor is touched

THE GAP THIS CLOSES. The linter above checks style and — through T1 — that
docs/generated/status.md is fresh. It asserts nothing about whether a guard still BLOCKS what it
is supposed to block. `floor-test.sh` does assert that, but only in CI, so until
now a guard could regress and reach a push with style checking behind it.

CONDITIONAL, AND THAT IS THE WHOLE DESIGN. The linter already costs ~14s on this
machine and `--smoke` adds ~10-16s. Paying that on every commit — most of which
touch documents — is how a hook becomes the thing people reflexively bypass, and
a gate that is routinely skipped protects nothing (policy/constitution.md §2.11). So the
cost lands exactly where the risk is: a commit that stages a floor surface.

STAGED PATHS ONLY (`--cached`), because the hook must judge what is being
committed and not whatever happens to be dirty in the tree. `--diff-filter=ACMR`
so a DELETED guard does not trigger a suite that would fail for the wrong reason.

MATCHED WITH `case`, NOT `grep`, on purpose. This machine's `grep` is a ugrep
wrapper carrying `-I --ignore-files`, which silently skips gitignored and
binary-looking input — the repo has already been burned by resting a decision on
that (a negative that was simply wrong). A `case` glob is POSIX shell, forks
nothing, and cannot have a flavour.
```

## hooks/pre-commit, lines 74-78 (before this edit)

```text
deploy-harden.sh IS a floor surface for this purpose (PR #124 review): the
smoke set installs it and asserts the B1 deny and path-anchoring guarantees
before the boundary, so a bad SEC-0 deny edit was reaching a push with only
the style linter behind it. library-admission.sh and floor-*.sh are already covered
by the two globs above it.
```

## hooks/pre-commit, lines 92-101 (before this edit)

```text
── THE SUITE RUNS AGAINST THE INDEX, NOT THE WORKING TREE (PR #124 review) ──

The trigger is computed from `git diff --cached`, so the check must judge the
same bytes. Running the checkout's copy meant that with a BROKEN guard staged
and an unstaged fix sitting in the worktree, the smoke suite tested the fix,
passed, and the commit recorded the broken blob — a gate that certifies content
nobody is committing.

`git checkout-index -a` materialises exactly the staged tree, so the floor suite
and the guards it copies into its sandbox are the versions being committed.
```

## hooks/pre-commit, lines 103-104 (before this edit)

```text
Inside the confinement no directory named .github/workflows may be made (harbor#555): the workflows are not
what the smoke suite judges, so a tree without them is the second try, and the first stays the whole index.
```

## hooks/pre-commit, lines 122-123 (before this edit)

```text
harbor#667: the guards' verdicts are tables in tests/admission/<guard>/ and tests/guards. Smoke the staged guards'
suites (first row per rule and verdict); a shared floor file stages every guard.
```

## hooks/pre-commit, lines 133-133 (before this edit)

```text
harbor#961 W2: a guard's suites are tests/admission/<guard>/*.test.sh; the directory names the guard
```
