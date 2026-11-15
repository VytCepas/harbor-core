---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of hooks/commit-msg

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## hooks/commit-msg, lines 3-3 (before this edit)

```text

```

## hooks/commit-msg, lines 5-5 (before this edit)

```text
Bypass:   git commit --no-verify   (deliberate, visible, and rare)
```

## hooks/commit-msg, lines 6-25 (before this edit)

```text

WHY A HOOK WHEN LINT C2 ALREADY CHECKS THIS. C2 counts attribution on commits
that already exist, so the earliest it can speak is the next lint run — by
which time the trailer is in the history and removing it needs a rebase. On
`main` it cannot even do that: the rule downgrades itself to an advisory
there, because the repair is a force-push to a shared branch and that is the
operator's call. So the rule's only enforceable window is the moment the
message is written, and nothing was watching it. A rule with no mechanism is a
wish; this is the mechanism.

THE PATTERN IS DEFINED HERE AND NOWHERE ELSE. lint-conventions.sh's C2 READS
it out of this file rather than carrying its own copy. Two greps for the same
shape in two files is the drift this repo keeps re-finding: the copies stay
readable while they disagree, and the one that runs less often is the one that
rots. One definition, one consumer.

ANCHORED TO THE LINE START so a commit message may still DISCUSS attribution —
quoting the rule, or explaining why a trailer was removed — without tripping
the hook that enforces it. A guard that blocks writing about itself is a guard
people route around.
```

## hooks/commit-msg, lines 28-35 (before this edit)

```text
`Claude-Session:` IS ATTRIBUTION (harbor#584). It is a trailer whose only
content names the AI session that wrote the commit, with a claude.ai link, and
82 commits on main carry it because this pattern did not: the hook passed
every one and C2, which reads this line, counted none. The rule stopped being
broken on 2026-09-10 only because sessions were told to stop — held by an
instruction, with a green mechanism that would not notice it change back.

HARBOR_LINT_ATTRIBUTION_ERE — the single definition. Do not duplicate; see above.
```

## hooks/commit-msg, lines 41-43 (before this edit)

```text
Comment lines are stripped by git before the message is stored, so judging
them would fail a commit for text that never reaches the history — the false
positive CONSTITUTION §2.11 names.
```
