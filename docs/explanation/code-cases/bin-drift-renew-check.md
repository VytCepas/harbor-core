---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/drift-renew-check.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/drift-renew-check.sh, lines 12-34 (before this edit)

```text
WHY. Every other surface on this box answers "is the installed thing healthy".
NOTHING answered "is the installed thing the thing we built" — and the gap is
not hypothetical. Measured 2026-08-13: `.helm-install-stamp` pins the floor at
4f997de (2026-08-09) with **11 later commits touching bin/ and hooks/**, which
is precisely why admission-cloud.sh and admission-destroy.sh — written, tested, merged
— gate nothing on this machine. And `launchd/com.harbor.status.usage.plist` has a
counterpart in no LaunchAgents directory, so the durable usage ledger M9 built
has never been written by a schedule.

A DEPLOY THAT NEVER HAPPENED READS EXACTLY LIKE A FEATURE THAT WORKS. That is
the whole class: the repo is green, the tests pass, the contract describes the
behaviour, and the box does not have it. Everything here compares an artifact
in the CHECKOUT against the same artifact's footprint on the BOX.

IT INSTALLS NOTHING, and that is not timidity. Each remedy it names is a write
to a surface admission-self-edit.sh protects, or a `launchctl` call the floor
refuses — both deliberately out of a session's reach. It prints the command;
the operator runs it in their own terminal.

THE CHECKOUT IS FOUND, NEVER ASSUMED. Installed at $CFG/bin there is no repo
above this file, so the comparison needs $HARBOR_SCOPE_REPO (default ~/port/harbor). If
that is not a git checkout the git-dependent checks STAND DOWN and say so —
never "0 behind", which would read as up to date.
```

## bin/drift-renew-check.sh, lines 48-50 (before this edit)

```text
The target, --apply and --live are install-lib's (lint D7): physical paths, the live dir only by
--live, and a CLAUDE_CONFIG_DIR naming another dir exits 2. Its --apply refreshes a statusline cache
every tick of fleet-snapshot-refresh, so it keeps no run log: one per tick would be the leftover.
```

## bin/drift-renew-check.sh, lines 75-92 (before this edit)

```text
Counts commits touching the files THAT INSTALLER ACTUALLY INSTALLS. A docs
commit does not make an installed floor stale, and a number that moves for
reasons the operator cannot act on is one they learn to ignore.

THE PATHSPEC WAS `bin/ hooks/`, AND IT IS WIDER THAN EITHER INSTALLER IN BOTH
DIRECTIONS. Measured on the live box 2026-08-24: the row read `STALE floor5`
while all sixteen floor payload files were byte-identical to origin/main. The
five commits it counted touched status-fleet-glyph.sh, status-dashboard-generate.sh, cu.sh and
audit-triage.sh — every one of them runtime-install's, and every one of them
already delivered by a runtime-install run that same afternoon. The remedy
printed (`floor-install --live --apply`) would have copied byte-identical files
and moved a stamp. `hooks/` is wider still: it holds this repo's GIT hooks
(commit-msg, pre-commit, pre-push) and appears in NO installer payload at all,
so a commit to a git hook reported the security floor as stale.

§2.11 — a false positive is a defect, not safety. A renewal token that fires on
every statusline commit is one the operator learns to skip, and it is the same
token that has to be believed the day admission-cloud.sh really is not installed.
```

## bin/drift-renew-check.sh, lines 95-120 (before this edit)

```text
THE PAYLOAD IS READ FROM THE INSTALLER, NEVER RESTATED HERE. admission-install.sh
already does exactly this to read deploy-runtime-install.sh's $FILES (:301), and its
own comment names the reason: "a second copy of runtime-install's payload is
the T2 defect harbor#275 was made of". Same sed, same trust boundary — the
declaration inside the installer is the one source of truth for what it owns.

THE INSTALLER'S OWN FILE IS PART OF ITS PATHSPEC. A commit that changes only
admission-install.sh — new hook wiring, a different deny extension, a changed
install order — leaves every payload file identical and still means the box is
behind what installing today would produce.

WHAT THIS DELIBERATELY DOES NOT COUNT, so the next reader does not mistake the
gap for an oversight: floor-install's CONDITIONAL payload (admission-integrity.sh
under --with-b6, admission-stop.sh under --with-stop) and admission-deny.sh, which it
RUNS rather than lists. All three are named in the installer's prose, not in a
payload variable, and grepping prose is a heuristic this file will not carry.
admission-deny.sh and admission-integrity.sh are both in runtime-install's $FILES, so a
commit to either still raises a `runtime` token; only the settings.json deny
entries floor-install regenerates are uncovered. Closing that properly means
floor-install declaring those three the way it declares $GUARDS, which is a
change to the floor installer and belongs in its own review.

EMPTY MEANS STAND DOWN, NEVER "0 BEHIND". If an installer stops declaring its
payload in a form this can read, the honest answer is that the comparison could
not be made — the rule the absent-checkout arm below already follows, and the
distinction renew-check-test.sh case 4 exists to hold.
```

## bin/drift-renew-check.sh, lines 139-145 (before this edit)

```text
`git rev-parse --git-dir`, NOT `[ -d "$REPO/.git" ]`. In a worktree `.git` is a
FILE, so the directory test made every worktree report `repo?` — measured the
first time this ran from ~/harbor-wt-*. contracts/hooks.md records the same
trap for an install snippet that was documented and never run.
HOISTED SO SECTION 1b CAN REUSE THE ANSWER. "Is $REPO a checkout" is asked by
two arms now, and a second inline copy of the test is a second thing that can
be changed in one place and not the other.
```

## bin/drift-renew-check.sh, lines 149-159 (before this edit)

```text
RUNTIME FIRST, AND THE ORDER IS THE FIX, NOT A PREFERENCE. admission-install.sh is
the PIN WRITER (:223, over its payload plus deploy-restore.sh/baseline-pin.sh/
deploy-harden.sh), and deploy-runtime-install.sh REPLACES four of the files it pins. So
whichever runs last decides whether the pins match the bytes on disk.

MEASURED 2026-08-14 on a copy of the live config dir, both orders:
  floor-install → runtime-install : "the next SessionStart will be BLOCKED"
                                    (deploy-restore.sh replaced after its pin was taken)
  runtime-install → floor-install : B6 silent, floor-verify green
This loop printed the blocking order because `floor` sorts before `runtime`,
and a remedy an operator pastes in the order given must not end in a lockout.
```

## bin/drift-renew-check.sh, lines 167-169 (before this edit)

```text
UNQUOTED ON PURPOSE: the pathspec is one git argument per line and must
word-split. This file runs under `sh`, where it does; harbor's own
`for g in $GUARDS` loops rest on the same rule.
```

## bin/drift-renew-check.sh, lines 182-206 (before this edit)

```text
SAME SUBJECT AS SECTION 1, DIFFERENT MECHANISM, AND THE DIFFERENCE IS FORCED.
policy-constitution-install.sh writes NO stamp: it copies policy/constitution.md over
$CFG/CLAUDE.md and verifies with cmp. There is no installed-at commit to count
from, so the loop above could not have covered it by adding a name to its list.
What the installer does leave is a byte-exact footprint, which is a STRONGER
oracle than a commit count rather than a weaker one — the deployed file either
is the merged file or it is not, and drift-install.sh's header already records
why it chose content over a lag counter for the same reason.

WHY THIS ARM EXISTS (harbor#557). Measured 2026-09-18: the live CLAUDE.md sat
413 B behind main for two days and every instrument on the box was green.
floor-verify's install-drift enumerates $DIR/bin and never looks at CLAUDE.md;
this file's own loop covered runtime-install and floor-install and nothing
else; B8 holds the live file against ITS OWN PIN, which is a question about
tampering and answers "unchanged since pinning" for a file that was already
stale when it was pinned. The installer existed the whole time. Nothing ever
said to run it, so it was run when a human happened to think of it.

HELD AGAINST origin/main, NOT THE WORKING TREE. Shelling out to the installer's
dry run would have been shorter and would have reported `identical` on any
branch whose policy/constitution.md happens to match the box — including text nobody
has reviewed, which is DE-30's failure and the thing constitution-install's own
--from-branch gate exists to make deliberate rather than accidental. The live
constitution is supposed to carry MERGED text, so merged text is what it is
compared to.
```

## bin/drift-renew-check.sh, lines 208-211 (before this edit)

```text
HOW FAR BACK THE BLOB WALK BELOW LOOKS. A knob because the cap decides between
two OPPOSITE remedies and the suite has to be able to reach the branch where it
binds; 60 against a path with 19 commits in its entire history (measured
2026-09-20) is slack, not a limit anyone will meet.
```

## bin/drift-renew-check.sh, lines 219-221 (before this edit)

```text
Case 4's rule, one artifact down: "I could not look" and "identical" are
the two states this file exists to keep apart, and silence spells the
second one.
```

## bin/drift-renew-check.sh, lines 224-233 (before this edit)

```text
THE DISTANCE IS WALKED, NOT GUESSED. The commit whose blob the box is
running is the only honest anchor for "how far behind", and it is cheap:
this runs ONLY once the hashes already differ, over a path with 19 commits
in its whole history (measured 2026-09-20, 0.02s).

THE SHAPE IS drift-install.sh's, DELIBERATELY. It walks a path's history
for the live bytes at :137 and grades the result current/stale/modified/
unsourced. This is that walk over the one governed file living OUTSIDE
`bin/`, which is why install-drift cannot reach it: its loop is
`for live in "$DIR"/bin/*` and CLAUDE.md is not in it.
```

## bin/drift-renew-check.sh, lines 242-251 (before this edit)

```text
STOPPED LOOKING IS NOT FOUND NOTHING, and conflating them here would be
the expensive kind of wrong: the two branches around this one print
OPPOSITE remedies, so a truncated walk falling through to const+ would
tell an operator to back-port a box that merely needs deploying.

A history of exactly $CONST_WALK_MAX revisions with no match lands here
too, when `const+` would have been right. That asymmetry is deliberate:
standing down over-reports uncertainty, which costs a second look, while
either of the other two verdicts being wrong costs the operator a
destructive edit or a constitution left stale.
```

## bin/drift-renew-check.sh, lines 254-265 (before this edit)

```text
A SEPARATE TOKEN BECAUSE IT IS A SEPARATE REMEDY, AND THE WRONG ONE IS
DESTRUCTIVE. harbor#462: the live file was 1,933 B LARGER than the repo's
and every hunk was an append — three blocks of doctrine written straight
into the box and committed nowhere, one of them the whole "every check is
registered" rule. Deploying over that state destroys it, byte-perfectly,
with cmp reporting success. So this never prints --apply.

AND IT DOES NOT RE-DECIDE THE QUESTION. Whether the live-only lines are
unsourced text or a reordering is constitution-install's own comm(1) over
sorted unique lines, at :149; a second implementation here would be a
copy that can disagree with the gate it is warning about. This says the
distance is uncomputable and names the tool that owns the answer.
```

## bin/drift-renew-check.sh, lines 272-277 (before this edit)

```text
The plist is the built artifact; LaunchAgents is the footprint. `launchctl
list` is deliberately NOT the oracle: a job can be loaded from a plist that
was since deleted, and a plist can sit on disk unloaded — the file is the
thing an operator can act on, and the load state is one `launchctl` away.
A private layer's jobs/ is a second source of the same plists (harbor#1149, contracts/private-layer.md): client monitors
are built there, and the footprint they owe is the same file in the same LaunchAgents. Darwin only; a Linux box's units are systemd/.
```

## bin/drift-renew-check.sh, lines 279-287 (before this edit)

```text

TWO FOOTPRINTS ARE NOT A MISS, AND ONE FILE IS NOT ALWAYS A JOB (false alarm measured 2026-10-11: `STALE jobs4`, all four wrong).
  - A plist can be installed as a SYSTEM daemon: audit-collector-install.sh writes the collector, its checkpoint and the OTLP receiver
    under sudo, because they run as another uid. Looking only in LaunchAgents reported three loaded daemons as never installed.
  - A plist can be shipped INERT on purpose (event.dispatch: "no installer loads that plist"). It says so itself, with the marker
    `harbor:shipped-inert` anywhere in the file; the marker is the declaration, so a new inert job needs no edit here, and a
    plist that lacks it and is installed nowhere is still reported.
§2.11: a token that is always on is one the operator learns to skip, and it is the token that has to be believed the day a real
agent plist is missing.
```

## bin/drift-renew-check.sh, lines 320-323 (before this edit)

```text
Not recomputed here. admission-integrity.sh already hashes the manifest at
SessionStart and session-verdicts.sh already speaks on teeth drift; a second
implementation of the same hash is a copy that can disagree with the gate.
What this reads is the gate's OWN artifact: a pin file that does not exist.
```

## bin/drift-renew-check.sh, lines 328-332 (before this edit)

```text
A SEPARATE cache and a separate statusline token, deliberately. "The box is
behind what we built" and "somebody must read a patch" are different jobs for
the operator, and folding them into one number would make each one's remedy
ambiguous. Written only when the tool exists — proposal.sh lives in the
checkout and is in no installer payload, because it acts on the repo.
```

## bin/drift-renew-check.sh, lines 9-15 (before this edit)

```text
One number for the statusline (stdout's first line, data), the detail for a human who asks (the
log lines under it, each finding a WARN whose fix is aimed at THIS box: --live, or --dir '<d>').

Why: every other surface answers "is the installed thing healthy"; nothing answered "is the installed thing the thing we built" (2026-08-13: the floor stamp sat 11 bin/hooks commits behind, so admission-cloud.sh and admission-destroy.sh gated nothing here). A deploy that never happened reads exactly like a feature that works.
Installs nothing: each remedy writes to a surface admission-self-edit.sh protects, or calls launchctl, which the floor refuses; it prints the command for the operator's terminal.
The checkout is found, never assumed: installed at $CFG/bin there is no repo above this file, so it needs $HARBOR_SCOPE_REPO (default ~/port/harbor). Without a git checkout the git-dependent checks STAND DOWN and say so, never "0 behind".
Removed notes: docs/explanation/code-cases/bin-drift-renew-check.md
```

## bin/drift-renew-check.sh, lines 24-24 (before this edit)

```text
Where a schedule is built and installed: launchd on macOS, systemd user units elsewhere (harbor#618).
```

## bin/drift-renew-check.sh, lines 37-38 (before this edit)

```text
Every fix names THIS box (harbor#800): a live install is deploy's, the one live entry (the install
standard §4); a sandbox is fixed by its installer, --dir spelled. The pin is the operator's act.
```

## bin/drift-renew-check.sh, lines 74-74 (before this edit)

```text
A hook engine moved to its folder (D-88): both spellings, so neither side of the move drops out of the count.
```

## bin/drift-renew-check.sh, lines 107-107 (before this edit)

```text
A knob because the cap decides between two OPPOSITE remedies and the suite must reach the branch where it binds; 60 is slack against a path with 19 commits.
```

## bin/drift-renew-check.sh, lines 115-115 (before this edit)

```text
Case 4's rule, one artifact down: "could not look" and "identical" must stay apart.
```

## bin/drift-renew-check.sh, lines 155-156 (before this edit)

```text
Absent means the daily judge was never wired; stale means it stopped. Both are
"a self-process that is not running", which is this file's whole subject.
```

## bin/drift-renew-check.sh, lines 197-198 (before this edit)

```text
Then the log (contracts/logging.md): one WARN per finding, its fix aimed at this box. Findings are
WARNs, never FAILs, so the exit stays 0 as the header promises.
```
