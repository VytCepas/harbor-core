---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/admission-install.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/admission-install.sh, lines 9-22 (before this edit)

```text
Copies the guard scripts into <dir>/bin, applies the B1 deny extension
(admission-deny.sh), and additively merges the floor hooks into <dir>/settings.json.
Additive + idempotent: never removes a foreign hook, never re-adds a floor hook
already present (keyed by command string). Assumes the SEC-0 read-deny base is
already applied (it is, live). B6 (the recurring integrity gate) is deliberately
NOT installed by default — it lands LAST, after this install is verified
(docs/explanation/admission-baseline.md order).

--help, the target and every standard flag come from bin/deploy-install-lib.sh (lint D7):
physical paths, so `~/.claude/` or a symlink cannot reach live without --live
(P11-01); intent is a flag, never a position (harbor#52: `<sandbox> --live` used to
write live, the last word winning); CLAUDE_CONFIG_DIR never picks the dir. Every
printed command is spelled by il_spell/il_cmd, so it passes this script's own gate
(harbor#95, #142 — a hint the gate refuses teaches the operator to delete the gate).
```

## bin/admission-install.sh, lines 29-32 (before this edit)

```text
SG (harbor#291) — the Stop gate is OPT-IN, on the same reasoning that makes B6
opt-in: a gate that can refuse to let a TURN end must be a deliberate act on each
box, not a side effect of deploying the floor. deploy-runtime-install.sh's header
invariant — "installs no guard and wires no hook" — is why the wiring lives here.
```

## bin/admission-install.sh, lines 61-70 (before this edit)

```text
THE RECOVERY PATH, SEPARATE FROM THE GUARDS AND INSTALLED WITH THEM (harbor#275).
These are not guards — nothing wires them to a hook — but B6's own block message
is `sh $CFG/bin/deploy-restore.sh …`, so a floor whose gate can fire without them
present hands a locked-out operator a command that is not there. Held apart from
$GUARDS because that variable is read by floor-test.sh's X13 payload derivation,
admission-integrity.sh's floor MINIMUM and admission-remove.sh's removal list, and
widening it would change all three by accident.
baseline-pin.sh left this list when deploy's snapshots replaced it (harbor#765).
library-log.sh and deploy-install-lib.sh are what deploy-restore.sh, deploy-harden.sh and pin-instructions.sh source
(harbor#771, #765), so they are the recovery path too: copied, and content-pinned, with it.
```

## bin/admission-install.sh, lines 72-76 (before this edit)

```text
THE EVENT PRODUCERS (harbor#1043, PR 2): the hook and the bus it calls. Not guards — nothing here
can veto a call, and the floor never depends on them — so they are copied and recorded in the
manifest but NOT content-pinned and not in $GUARDS (B6's minimum, floor-test's X13 payload and
the removal list all read that variable). floor-uninstall reads this line too. event-bus.sh
sources library-log.sh, which $RECOVERY already ships beside it.
```

## bin/admission-install.sh, lines 78-82 (before this edit)

```text
THE APPROVAL GATE (harbor#1018): the tools the ask and allow rules name, the library they share, and merge-stack
with its merge backstop, which every gate merge goes through (ship contract §5b.10). Copied and recorded, NOT content-pinned and NOT in $GUARDS: no hook runs them, and
B6 blocks every session over a pinned file with no kill-switch line. The rules name these installed copies because
a session cannot write <cfg>/bin (B1, guard-bash, guard-selfedit). Required checks are each repo's own
.agents/required-checks.tsv, read from GitHub (contract §5a.6). floor-uninstall reads this line too.
```

## bin/admission-install.sh, lines 85-89 (before this edit)

```text
The floor hook wiring: event, matcher, guard. guard-egress covers Bash+Write;
guard-bash Bash; guard-selfedit Write|Edit|MultiEdit; annotate-web the web/MCP
content sources on PostToolUse.
<onfail> is `block` for a veto (P13E-2): padding a payload until the guard is slow was a way past every
rule. il_merge_hook (install-lib) sets it on a hook already wired, too.
```

## bin/admission-install.sh, lines 94-96 (before this edit)

```text
THE WIRING TABLE (harbor#766), one row per hook: <event>;<matcher>;<argv after /bin/sh>;<opt-in>;
<also wired by>. A bare name in the argv is a file in <dir>/bin. The dry run and the apply both
wire from it, and admission-remove.sh reads it to decide what to strip, so the three cannot drift.
```

## bin/admission-install.sh, lines 204-207 (before this edit)

```text
Merge every row this run installs into $NEW. The opt-in rows are in the DRY RUN
too, so its hooks diff shows the Stop gate and B6 this run would wire: a gate the
dry run never mentioned is one the operator did not know this installer owns
(harbor#275). A `case`, never `[ … ] && …`: under set -eu that leaves $? = 1.
```

## bin/admission-install.sh, lines 237-249 (before this edit)

```text
THE VERDICT, AT THE MOMENT OF DECISION (2026-08-03). Five documents described
`eval-pass-score.sh` as the gate on this installer. It is not one and never was: no
CI job wraps this script, so `--live --apply` was never blocked by anything. The
fix is DISCLOSURE, not a gate: the install decision is the operator's policy
call, and a script that refuses on a score turns a judgement into a number the
next person routes around with a flag. Advisory by construction — a failure to
compute it is reported as that, never as approval.
LINT X7 REPORTS THIS CALL AND THAT ADVISORY IS CORRECT — it stands on purpose.
eval-pass-score.sh is repo-scoped: it reads $ROOT/docs/explanation/admission-baseline.md, the adversarial pass
register, which is not shipped to a config dir either; shipping the script alone
would make it RUN AND FAIL on every install, and shipping docs/explanation/admission-baseline.md to fix that
would put the defect register on every box to serve one advisory line. So the
call stays repo-only and the ABSENCE is announced (CONSTITUTION No.2 clause 7).
```

## bin/admission-install.sh, lines 267-268 (before this edit)

```text
LISTED IN THE DRY RUN TOO, because these are content-pinned and a pin the dry
run never mentioned is a file the operator did not know this installer owns (harbor#275).
```

## bin/admission-install.sh, lines 285-297 (before this edit)

```text
On 2026-08-04 a deploy from a `main` checkout that predated an unmerged branch
wrote older guards over newer ones and silently removed four live security
fixes. `git pull` said "Already up to date" — correctly. `floor-verify` still
said FLOOR IS ON, because every check it makes was still true.

A REFUSAL IN BOTH MODES NOW (the install standard's dry-run rule): the dry run is
the moment the operator would have caught this, and deploy's plan phase reads its
exit code to predict the apply before anything is written.

"THE CHECK SAID NO" AND "THE CHECK COULD NOT RUN" ARE DIFFERENT ANSWERS (harbor#313):
an deploy-install-stamp.sh that is simply NOT THERE was once announced as a regression that
did not exist. STILL FAIL-CLOSED: an unrunnable check is not permission to deploy
over live work; only the diagnosis differs, decided by existence, not exit code.
```

## bin/admission-install.sh, lines 314-315 (before this edit)

```text
The Stop gate, in the DRY RUN as well as after the apply: a gate that can hold a
session open must not be discoverable only in hindsight.
```

## bin/admission-install.sh, lines 347-357 (before this edit)

```text
Two of $RECOVERY are in deploy-runtime-install.sh's own $FILES, so copying them
unconditionally would, after a runtime deploy from a newer checkout and a floor
deploy from an older one, silently revert them to the older bytes and pin them —
while the runtime stamp goes on claiming the newer version is installed. The
regression gate above cannot see it: it asks install-stamp about `floor-install`.

THE STAMP TIMESTAMP, NOT GIT ANCESTRY: the question is "did runtime-install write
these shared bytes more recently than the last floor deploy", i.e. who is the
current author. Lexical compare is correct for same-offset ISO-8601, which one box
writes; a DST change between two installs makes it fail SAFE, toward copying.
THE SHARED SET IS DERIVED, never listed here (the T2 defect harbor#275 was made of).
```

## bin/admission-install.sh, lines 380-386 (before this edit)

```text
Per-guard content pins. B6 checked only that the files existed, so a guard
gutted to its kill-switch line plus `exit 0` was reported intact (red-team pass 6).
ONE LIST, USED TWICE — COPY THEN PIN, and that is the whole of harbor#275: a pin
over a file this run did not write captures bytes of unknown provenance, and B6
then blocked EVERY session (measured on this box 2026-08-22). Copying first makes
the pin describe bytes this installer wrote, and makes the install order stop
mattering: both installers write identical bytes, so the hash cannot move.
```

## bin/admission-install.sh, lines 394-401 (before this edit)

```text
B8 (harbor#38) — pin the persistent INSTRUCTION surfaces. Not a lock: these stay
writable, but from here a change to CLAUDE.md / agents / skills / commands is
reported at the next SessionStart instead of loading unseen.

THE PINNER'S GATE IS NOT OURS TO PASS (harbor#135, #142): re-pinning blesses
whatever the instruction surfaces currently say, so on the live dir it is the
operator's act, never an installer's (CONSTITUTION's self-approval rule). The live
path DISCLOSES the exact command instead; a sandbox is pinned here.
```

## bin/admission-install.sh, lines 427-431 (before this edit)

```text
SG (harbor#291) — the Stop gate, wired from its table row. CONTENT-PINNED in the
same breath as the copy: a guard this installer wrote and did not pin is invisible
to B6's content loop. Pinned here rather than listed in $GUARDS, because $GUARDS is
also the presence list and a box that never opted in must not fail a check for a
file it deliberately does not have.
```

## bin/admission-install.sh, lines 436-437 (before this edit)

```text
Re-read settings (floor-deny just rewrote deny) and wire the SAME table the dry
run showed onto THAT (harbor#766: this was a second, hand-kept copy of it).
```

## bin/admission-install.sh, lines 446-449 (before this edit)

```text
OBSERVE-1 bootstrap. The hot path creates NOTHING (guard-lib property 3), so
without this the ledger does not exist until the next SessionStart and every
decision until then is silently unrecorded. Run once, here, where a fork costs
nothing and no verdict is pending.
```

## bin/admission-install.sh, lines 452-454 (before this edit)

```text
NOT SILENT, and the pin is the reason: a kept file is pinned to the bytes on disk,
so the gate stays quiet — exactly when a reader needs telling that this deploy did
not write what its own line above says it writes.
```

## bin/admission-install.sh, lines 459-460 (before this edit)

```text
RECORD WHAT WAS DEPLOYED (harbor#115), only after the apply ran, so a refused or
aborted install never claims to be installed. --live is install-stamp's own gate.
```

## bin/admission-install.sh, lines 470-471 (before this edit)

```text
What this run installed, one row per file (install standard §3). B6's .helm-pins above is the
separate store: the tamper gate never reads a record written by the thing it checks.
```

## bin/admission-install.sh, lines 474-475 (before this edit)

```text
THE TARGET IS SPELLED OUT, never left to the environment (Codex review, #148),
and --live stays because it is the AUTHORISATION. Deploy asks this itself (#285).
```

## bin/admission-install.sh, lines 479-481 (before this edit)

```text
A printed NEXT whose work is already done is the same defect as an advisory that
cries wolf (§2.11): measured 2026-08-18, `--apply --with-b6` then told the operator
to run `--apply --with-b6`. Deploy prints its own B6 advice, so it is skipped there.
```
