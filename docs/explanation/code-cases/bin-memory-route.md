---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/memory-route.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/memory-route.sh, lines 18-54 (before this edit)

```text
`--apply` REFUSES TO GUESS ITS TARGET. Writing needs `--live` or an explicit
`--dir`, because the read path defaults to the live config dir and a mutator
that inherits a convenience default writes to the operator's real box on a
bare `--apply`. Same shape as D2's settings.json rule, for the same reason.

WHY. The auto-memory store is keyed by the session's working directory:
~/.claude/projects/<cwd-key>/memory/. A session started at $HOME gets the
store; a session started in the measurement repo (resolved through the repo registry) gets a DIFFERENT key, which has no store
behind it, so it loads nothing. Measured 2026-09-16: 291 notes under
`-Users-someone`, and 0 under `-Users-someone-harbor`. Every other governed
repo had no project directory at all.

That is the whole defect, and it is worse than it sounds because it is silent
and it inverts. The notes most worth having in the measurement repo (resolved through the repo registry) are the ones written
WHILE WORKING IN the measurement repo (resolved through the repo registry) — the ugrep negative, the zsh word-split, the
`cd ~` prompt — and every one of them was filed from a $HOME session and is
therefore invisible in the repo it describes. `memory-store-topology.md` has
recorded this since 2026-08-02 and nothing acted on it, because a note about a
routing defect is itself subject to the routing defect.

THE FIX IS ONE STORE WITH MANY DOORS, not a store per repo. Each governed
repo's key gets its `memory` directory symlinked at the $HOME silo, so there
is exactly one set of notes, one MEMORY.md index, and a note written from any
repo is visible from all of them. A store per repo would re-create the same
invisibility one level down and multiply the index nobody reads.

WHAT IT COSTS, said plainly because `context-budget.sh` will now charge it
everywhere: the $HOME store's index is ~40 KB, so every governed repo's
sessions begin paying what only $HOME sessions paid before. That is the
intended trade — an index that is loaded and slightly over budget beats an
index that is under budget because nothing reads it — but it makes trimming
MEMORY.md a real task rather than a tidy one.

IT WRITES ONLY SYMLINKS, AND ONLY UNDER --apply. It never creates, moves,
copies or deletes a note. A pre-existing real directory is reported and left
alone: that is somebody's store, and silently replacing it with a link to a
different store would lose notes.
```

## bin/memory-route.sh, lines 106-115 (before this edit)

```text
THE WRITE NEEDS AN EXPLICIT --live FOR THE LIVE DIR (lint D2). Reading
defaults to the live config dir because that is the question anyone asking
has; writing must not inherit that convenience, or `--apply` typed while
thinking about a sandbox lands on the operator's real store.

RESOLVED PATHS, NOT STRINGS, and that is not ceremony: `--dir ~/.claude/`
with a trailing slash, or any symlinked route to the same directory, is the
live dir by another spelling and a string compare waves it through. D2's own
header records a pass that stripped every hook from a live config exactly that
way. The comparison is of physical paths, so only `--live` opens the live dir.
```

## bin/memory-route.sh, lines 125-127 (before this edit)

```text
A target that is NOT the live dir still has to be named, so a bare --apply
with no target at all cannot fall through this gate on a box where
CLAUDE_CONFIG_DIR happens to point elsewhere.
```

## bin/memory-route.sh, lines 134-137 (before this edit)

```text
Claude Code names a project directory after the session's cwd with every `/`
replaced by `-`, leading slash included: /Users/x/<repo> -> -Users-x-<repo>.
Derived, never parsed back: two different paths can in principle collide once
a directory name contains a dash, and this only ever needs the forward map.
```

## bin/memory-route.sh, lines 149-154 (before this edit)

```text
PHYSICAL, on both sides of the comparison. Claude Code keys the directory off
the resolved path, which this box's own store proves: the scratchpad silos are
named `-private-tmp-claude-501-...` and not `-tmp-...`, because /tmp is a
symlink to /private/tmp. Taking $HOME raw while resolving the repo paths works
only for as long as no path above either one is a link — true for
this box's $HOME today and false the moment this runs anywhere else.
```

## bin/memory-route.sh, lines 160-162 (before this edit)

```text
drift-renew-check.sh's case 4 is the precedent: "nothing to compare against" and
"nothing wrong" must not render the same. A green here would certify routing
that was never examined.
```

## bin/memory-route.sh, lines 174-182 (before this edit)

```text
A store that exists and holds nothing is the same blindness as no store, so
the count is the subject, not the directory's existence.

RESOLVE FIRST, THEN WALK. `find -P <symlink>` does not descend — it reports on
the link itself — so counting a correctly routed repo returned 0 and this tool
called its own successful --apply a failure. Resolving to the real directory
keeps -P's guarantee (nothing below is ever followed) while letting the one
link that matters be followed exactly once. A dangling link resolves to
itself, finds nothing, and is reported BLIND, which is right.
```

## bin/memory-route.sh, lines 201-218 (before this edit)

```text
A REGISTRY ROW IS NOT A DIRECTORY, IT IS A TREE. The first version routed the
ten registry paths and called the job done; measured immediately afterwards,
eight more directories a session can legitimately open were still blind —
three harbor worktrees (INCLUDING THE ONE THIS TOOL WAS BEING WRITTEN IN),
the pipeline repo's sub-checkouts (resolved through the repo registry), a yard worktree, and a mail
tool's installed copy under ~/.local/lib.

Two shapes, both ordinary on this box:
  worktrees   `worktree.sh` creates one per branch, so they are the NORMAL way
              work happens here. Each gets its own cwd key and its own
              blindness.
  sub-repos   the pipeline repo (resolved through the repo registry) is a ROOT and not a repo — its sub-checkouts are several
              separate checkouts one level below it. A session runs in those,
              never in the root, so routing only the root routes nobody.

Discovered, never listed: a hardcoded set of worktrees is stale the next time
anyone branches, which is exactly the copy-drift "derive it, don't state it"
exists for.
```

## bin/memory-route.sh, lines 221-223 (before this edit)

```text
`worktree list` prints the main checkout first; every later line is an extra
tree. Silent when the path is not a git repo, which is how a root like
the pipeline repo (resolved through the repo registry) falls through to the sub-repo branch below.
```

## bin/memory-route.sh, lines 225-234 (before this edit)

```text
Immediate children that are themselves checkouts. One level only: deeper is
vendored dependencies, not somewhere anyone opens a session.

`-e`, NOT `-d`, AND THAT IS THE WHOLE CASE. A normal clone has `.git` as a
DIRECTORY; a git worktree has `.git` as a FILE containing a gitdir pointer.
Testing for a directory therefore found the pipeline repo's checkout (resolved through the repo registry) and silently missed all
five of its `<sub>-wt-*` worktrees — the branch checkouts, which
is where the work in that tree actually happens. Measured 2026-09-16: the
first --apply reported a confident "18 of 18 routed" with those five still
blind, which is why the suite now pins both spellings.
```

## bin/memory-route.sh, lines 241-246 (before this edit)

```text
THE TARGET LIST IS BUILT FIRST, THEN WALKED ONCE — deliberately, and not for
tidiness. `route_targets ... | while read` puts the loop in a PIPELINE, and a
pipeline runs its stages in subshells, so every BAD/OK/MADE increment would be
discarded at the closing `done` and this tool would report 0 of 0 whatever it
found. That is a silent wrong-green, which is the one outcome the whole file
is built to prevent.
```

## bin/memory-route.sh, lines 255-257 (before this edit)

```text
A ROW WHOSE DIRECTORY IS GONE IS SKIPPED, matching project-pointer.sh's own
rule. Lint IJ5 is what catches a stale row; duplicating that judgement here
would make this check fail for a reason it does not own.
```

## bin/memory-route.sh, lines 261-263 (before this edit)

```text
The label names the row for the row itself, and row/dir for anything
discovered under it, so a BLIND line says which tree it means without
printing an absolute home (CONSTITUTION §3).
```

## bin/memory-route.sh, lines 270-277 (before this edit)

```text
THE WORKSPACE ROOT IS A DOOR TOO (harbor#619). The repos live under
${PORT_ROOT:-$HOME/port} and that is where sessions are launched from, but it
is not a repo, so no registry row names it and nothing above routes it.
Measured 2026-09-23 after the move: its store was an EMPTY directory the
harness had made on the first session there, so every session started in
~/port loaded no memory, and this check was green throughout. Same rule as
floor_port_root (contracts/port-root.md): empty is unset. A root that does not
exist is skipped, as a registry row's missing directory is.
```

## bin/memory-route.sh, lines 281-282 (before this edit)

```text
The WHOLE field, never a prefix: every repo lives under this root, so a
substring test finds the root "already listed" on every real box.
```

## bin/memory-route.sh, lines 287-290 (before this edit)

```text
WORKTREES UNDER <PORT_ROOT>/.worktrees/<repo>/<slug> ARE DOORS TOO (harbor#1149). A registry row finds its
own trees through `git worktree list`, but projects.tsv is not repos.tsv: a repo registered only in the
private layer has no row here, so a tree of it would start blind. Read off the directory, as the port root
is. `.git` is a FILE in a linked worktree. The WHOLE path is compared, never a prefix.
```

## bin/memory-route.sh, lines 322-323 (before this edit)

```text
A REAL DIRECTORY WITH NOTES IS NEVER REPLACED. It holds notes this tool
did not write and cannot merge; clobbering it would lose them silently.
```

## bin/memory-route.sh, lines 329-337 (before this edit)

```text
AN EMPTY ONE IS A DIRECTORY, NOT A STORE, and leaving it is a permanent
red the operator can do nothing about: the harness creates it the first
time a session runs there, so on this box `harbor` had one and would have
stayed blind forever.

`rmdir`, NEVER 'rm -rf' — the safety property, not a style choice. rmdir
refuses a non-empty directory, so if anything at all is in there the
replacement cannot proceed and the store survives. The guard is the
syscall, not this comment.
```

## bin/memory-route.sh, lines 363-366 (before this edit)

```text
EXAMINED IS ASSERTED, not assumed. A registry that parses to zero rows — a
changed separator, a CRLF checkout — would otherwise print a clean green
having checked nothing at all, which is the failure this file's own stand-down
block exists to prevent one level up.
```
