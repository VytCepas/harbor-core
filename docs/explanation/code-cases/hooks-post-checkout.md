---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of hooks/post-checkout

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## hooks/post-checkout, lines 3-3 (before this edit)

```text

```

## hooks/post-checkout, lines 7-12 (before this edit)

```text

bin/worktree.sh new routes at creation (harbor#589), but a raw `git worktree add` skips it, and
that is how worktrees are really made here, so the repair did not survive worktree creation.
git runs this on every checkout; only a worktree's first one (previous HEAD all zeros, git-dir
differing from the common dir) acts. memory-route.sh --apply stays the one linker. It writes
symlinks only, and nothing here can fail the checkout: exit 0 on every path.
```

## hooks/post-checkout, lines 14-17 (before this edit)

```text
WHY BOX-WIDE (harbor#966). Wired through harbor's core.hooksPath, this ran for harbor's trees only:
a raw worktree of any other governed repo stayed blind until the next harbor worktree routed the box,
so memory-route's colour depended on which happened last (2026-10-04: RED 1 of 56, then GREEN).
A config hook (git >= 2.36's hook.<name>.event) runs beside each repo's own hooks, whatever its hooksPath.
```

## hooks/post-checkout, lines 28-29 (before this edit)

```text
Box-wide, this runs for every scratch worktree too; the router's registry rows are ~/ paths, so a tree
outside $HOME (a suite's fixture under $TMPDIR) is never one it routes, and costs no 3 s router run.
```

## hooks/post-checkout, lines 31-31 (before this edit)

```text
Already routed (harbor's own hooksPath copy ran first, when both are wired): nothing left to do.
```

## hooks/post-checkout, lines 34-34 (before this edit)

```text
$0 is the symlink path when installed by `ln -s`, so resolve it to find bin/ (see hooks/pre-commit).
```

## hooks/post-checkout, lines 43-43 (before this edit)

```text
--live only when the config dir IS the live one: the tool's write gate demands it spelled out.
```

## hooks/post-checkout, lines 46-47 (before this edit)

```text
git exports GIT_DIR into hooks, and memory-route runs `git worktree list` on other trees
(hooks/lib.sh explains the hazard); unset it for that child only.
```

## hooks/post-checkout, lines 51-52 (before this edit)

```text
A command inside the agent sandbox cannot write <config>/projects, so a worktree made there is
born blind and nothing else says why (harbor#966): name the cause and the one unsandboxed fix.
```
