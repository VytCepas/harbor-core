---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/policy-constitution-install.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/policy-constitution-install.sh, lines 9-27 (before this edit)

```text
THE GAP THIS CLOSES IS THAT THERE WAS NO MECHANISM AT ALL. Editing
policy/constitution.md changes no running session: the copy the harness loads is the
box's own CLAUDE.md, a separate file, and nothing deployed to it. Lint X2
compares only bin/*.sh; guard-selfedit protects the floor's own surfaces;
drift-reference-check.sh says in its own header that it does not compare live against
repo. So a session could edit the constitution, report the rule as in force, and
be wrong — with every instrument green.

DE-30 REJECTED AN AUTOMATED INSTALLER AND THIS IS NOT ONE. What it rejected was
a deployment that runs unattended with a byte-equality oracle deciding when to
fire. This is a VERB: it does nothing without --apply, refuses the live file
without --live, and refuses to deploy from anything but a clean `main` unless
the operator says --from-branch out loud. The failure DE-30 names — unreviewed
text arriving over the live constitution from a work-in-progress checkout — is
the specific thing those two gates exist to make impossible by accident.

IT NEVER RE-PINS. B8 is the operator's act from their own terminal, for the
reason admission-install.sh records at length: an installer run from a session that
blesses its own instruction surfaces is a self-approval loop.
```

## bin/policy-constitution-install.sh, lines 48-48 (before this edit)

```text
── what would change ───────────────────────────────────────────────────────
```

## bin/policy-constitution-install.sh, lines 62-66 (before this edit)

```text
THE ONE THAT IS NOT ABOUT PERMISSIONS. --live says "yes, the live file"; this
one says "yes, THIS TEXT" — and they are different questions. A feature branch
is by definition text nobody has reviewed, and the live constitution is the one
file where unreviewed text governs every future session on the box.
The dry run runs every gate --apply runs (the dry-run exit rule), so deploy's plan sees a refusal.
```

## bin/policy-constitution-install.sh, lines 87-146 (before this edit)

```text
THIS DEPLOYS IN ONE DIRECTION AND THE BOX HAS DRIFTED IN THE OTHER. Measured
2026-09-06: the live CLAUDE.md was 1,933 bytes LARGER than policy/constitution.md and
every diff hunk was an append — three blocks of doctrine written straight into
the live file and never committed anywhere. `git log -S` over each of their
distinctive phrases returned ZERO commits, so version control had never held
them. One of the three was the entire "Every check and every notifier is
registered" rule, which docs/reference/checks.md opens by citing as its reason to exist.

Running this command in that state would have destroyed all three, silently and
with a post-write `cmp` reporting success — the copy is byte-perfect, which is
exactly what makes it unrecoverable. The backup below is real but it is a file
in `backups/` that nobody has a reason to open, because nothing said anything
was lost.

NOTHING DETECTED THIS. Lint X2 compares bin/*.sh and not this document.
drift-reference-check.sh states in its own header that it does not compare live
against repo. admission-self-edit.sh stops a SESSION writing there, which is a
different question from whether the operator's own edits ever come back. The
one-way installer was the whole mechanism, and a one-way installer facing a
two-way surface loses the direction it does not carry.

SO THE GATE IS HERE, IN THE TOOL THAT WOULD DO THE DAMAGE, rather than in a
note asking people to check first. A rule with no mechanism is a wish, and the
operator reading a warning is not a mechanism — they are running this command
precisely because they believe the repo is ahead.

LINE-LEVEL AND ORDER-FREE, deliberately. `diff` would call a moved paragraph a
deletion and refuse a legitimate reorder; `comm` over sorted unique lines asks
only "is there text on the box that is in no commit", which is the actual
question. Blank lines and pure-whitespace lines are dropped so reflowing does
not manufacture a refusal (§2.11 — a gate with false positives gets switched
off, and a switched-off gate protects nothing).

"IN NO COMMIT" MEANS EVERY COMMITTED VERSION, NOT JUST HEAD (harbor#683). The
sentence above stated the right question and the code asked a narrower one: it
compared the live file with the current policy/constitution.md only. So every
intentional edit that replaced a line refused. Deploying #581 (2026-09-24)
named the three lines of the old defer paragraph as text "that exists in
exactly one place on this box", although it had been committed for weeks and
was replaced on purpose. An operator trained to answer every refusal with
--accept-loss answers the real one the same way. The known set is therefore
the current file plus every version `git log --follow -- policy/constitution.md`
reaches, under each name it had: 22 revisions on 2026-09-24, about half a second at load 10.

OUTSIDE A GIT CHECKOUT the history cannot be read, so the known set falls back
to the current file alone, and the refusal says so. Stricter, never looser.

WHAT THIS CANNOT TELL APART, stated rather than discovered: a line removed from
the repo as WRONG and then hand-written back into the live file still passes as
"known", because some commit once held it. If that case turns out to be real,
narrow the known set to what the repo held at the last deploy (install-stamp
records it).

A HISTORY READ THAT FAILS IS SAID, NEVER PASSED OFF AS COMPLETE (review of
#685). If `git log` fails (a corrupt or partial object store), or some
`git show` does, the known set shrinks. That only makes the gate stricter, so
nothing live is ever let through. But the first cut then claimed "none of the 0
committed versions", a search that never happened, so the refusal reported a
false fact on exactly the run where the operator most needs a true one.
Failures are counted, and the message names what was read and what was not.
```

## bin/policy-constitution-install.sh, lines 156-157 (before this edit)

```text
ACROSS RENAMES (harbor#949): the W2 move left `rev-list -- policy/constitution.md` one version, and 17
lines committed under CONSTITUTION.md refused. --follow pairs each version with the path it had then.
```

## bin/policy-constitution-install.sh, lines 213-214 (before this edit)

```text
POST-WRITE VERIFY. A copy that reported success and landed different bytes is
the failure every installer in this repo was written for.
```

## bin/policy-constitution-install.sh, lines 222-222 (before this edit)

```text
Its row in the install manifest (install standard §3); a symlinked CLAUDE.md is recorded as the link.
```
