---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/admission-verify.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/admission-verify.sh, lines 7-11 (before this edit)

```text
WHY THIS EXISTS: the QA review (docs/reports/qa-plan.md, R12) found no way for an operator
to check. Worse, the failure mode that matters is SILENT — a floor that is
installed, pinned and wired but whose guards never fire looks identical to a
working one. So this does not read settings.json and report success: it fires
a known-blocked shape through each guard and checks the verdict.
```

## bin/admission-verify.sh, lines 14-20 (before this edit)

```text
ARGUMENT CONTRACT — install-lib's, like every tool that names a config dir (lint D7, harbor#800).
`--live` once fell into $DIR verbatim, so `admission-verify.sh --live` printed a MISSING and then six
✓s for guards that were not installed (measured 2026-08-01): a verifier that manufactures a pass
is worse than none. Later `--live` meant ${CLAUDE_CONFIG_DIR:-~/.claude}, so the environment chose
the box it verified. Now `--live` is $HOME/.claude, `--dir` is any other, and the env never picks.
EXIT 2 FOR USAGE, because `harbor verify` forwards this status verbatim and contracts/cli.md fixes
the codes across every verb: 0 success, 1 the verb ran and reported a problem, 2 usage error.
```

## bin/admission-verify.sh, lines 32-32 (before this edit)

```text
READ-ONLY: a verifier that took --apply would read as one that writes.
```

## bin/admission-verify.sh, lines 38-42 (before this edit)

```text
AN ABSENT CONFIG DIR IS AN ANSWER, NOT A MISUSE. `admission-verify.sh --live` on a
machine with no ~/.claude yet is a perfectly valid question with a correct
reply: the floor is not on. Reporting a usage error there tells the operator
they typed it wrong when they did not, and hands automation the one code that
means "ignore this result".
```

## bin/admission-verify.sh, lines 52-55 (before this edit)

```text
A SHADOW ENVIRONMENT IS NAMED, NOT VERIFIED THROUGH (harbor#482). Under HARBOR_ADMISSION_SHADOW the
guards record instead of blocking, so every `blocks:` probe below read as a broken floor (7 false
FAILs, review of #970). The probes ask whether the INSTALLED floor blocks, so they run with the
switch cleared, and the run says that the environment it was started from is in shadow.
```

## bin/admission-verify.sh, lines 62-64 (before this edit)

```text
THE PROBES NEVER FILE IN THE LEDGER (harbor#735). A guard files its decision under the config dir its
own path is in (floor_log_decision), so each fires through a temp link to $DIR/bin: the same bytes,
the same CLAUDE_CONFIG_DIR, and a verifier that writes nothing. With no temp dir, it fires in place.
```

## bin/admission-verify.sh, lines 68-69 (before this edit)

```text
Every fix is a command its tool's gate accepts, and a LIVE install goes through deploy, the one
live entry (the install standard §4); a sandbox is fixed by the installer itself, --dir spelled.
```

## bin/admission-verify.sh, lines 90-92 (before this edit)

```text
Advisories are NOT failures — B8 drift is reported, never blocking — but a run
that ends "FLOOR IS ON" while an advisory is outstanding hides it, which is
the reporting bug this whole workstream keeps re-finding (red-team B8-INC-08).
```

## bin/admission-verify.sh, lines 96-103 (before this edit)

```text
THE SET IS DERIVED FROM THE PINS THE INSTALLER WROTE, not listed here. This was
a hardcoded six, and it is the fourth copy of one set (admission-install.sh:82,
admission-integrity.sh, deploy-runtime-install.sh, here) — measured 2026-08-14, the copies
had drifted: admission-cloud.sh and admission-destroy.sh were in the payload, wired, and
pinned, and `harbor verify` reported a floor that was ON without ever naming
them. `contracts/cli.md:106` meanwhile tells the operator that firing those two
by hand is this command's job. The core six stay as the floor MINIMUM so a
DELETED pin cannot quietly shrink the check.
```

## bin/admission-verify.sh, lines 139-141 (before this edit)

```text
3. THE PART THAT MATTERS — do the guards actually BLOCK? A guard that is
   installed, pinned and wired but never fires looks identical to a working
   one from the filesystem alone.
```

## bin/admission-verify.sh, lines 143-147 (before this edit)

```text
THE GUARD MUST EXIST BEFORE ITS VERDICT MEANS ANYTHING. Exit 2 is overloaded:
it is both "this guard blocked" and "sh could not run this at all" — a missing
file, an unreadable one, a path that parsed as an option. Belt to the argument
contract's braces: even with a well-formed $DIR, a guard that was never
installed must report that it was never tested, not that it blocked.
```

## bin/admission-verify.sh, lines 153-165 (before this edit)

```text
AN EXIT CODE IS NOT A VERDICT. `sh` returns 2 for a SYNTAX ERROR as well, so a
guard that is present, wired, and completely broken — one stray `if [` — exits 2
and used to read as a successful block. That hole survives the argument fix
above and is strictly worse than it: the file is on disk, the wiring is real,
and every filesystem-level check passes while the guard vetoes nothing.

So require the PAYLOAD. floor_block (library-admission.sh:392-401) announces itself on
stderr before exiting 2; a broken guard emits its interpreter's error instead.
Demanding the announcement is the difference between "something exited 2" and
"this guard decided to block", which is the only claim this line is entitled to
make (№2.4 — a claim with no falsifier is not a claim).
Every printf feeding a guard drops its own stderr: a guard that exits unread makes dash print
"printf: I/O error" (EPIPE, SIGPIPE ignored under the Actions runner), a race that reddened main.
```

## bin/admission-verify.sh, lines 186-198 (before this edit)

```text
3b. THE ASK/DENY GUARDS DECIDE DIFFERENTLY, WHICH IS WHY THEY WERE UNPROBED.
admission-cloud.sh (harbor#194) and admission-destroy.sh (harbor#201) are the WARNING
layer: they exit 0 and emit a PreToolUse permissionDecision on STDOUT, so
probe() above — which requires exit 2 plus a stderr banner — can only ever call
them broken. The consequence of having no probe at all is worse than a wrong
one: `contracts/cli.md:106` promises this command fires every guard by hand, and
for these two it fired nothing while printing "FLOOR IS ON".

The posture is NOT set here. Default posture is `ask`, `CLOUD_POSTURE=deny` /
`HARBOR_ADMISSION_DESTROY_POSTURE=deny` escalate to `deny`, and both are legitimate installed
states — a verifier that demanded one would fail the operator's own choice. So
the assertion is "it reached a decision", which is the claim that discriminates a
live guard from one gutted to `exit 0`.
```

## bin/admission-verify.sh, lines 217-226 (before this edit)

```text
guard-deliverables decides the same way (stdout JSON, exit 0), so it probes the
same way. BOTH ARMS, because they share nothing but the classifier: the file-tool
arm reads a path out of the payload and the Bash arm has to find one inside a
command line, and a gutted extractor would leave the other arm answering for it.
TWO PROPERTIES OF THE PROBE PATH, both measured rather than assumed. It must NOT
exist — condition 3 exempts anything already on disk, so a probe aimed at a real
path goes quiet the day someone creates it and reads as a gutted guard. And it
must NOT be a DOTFILE: the first draft used ~/.floor-verify-probe-report.html to
keep it out of sight, and the guard exempts dotfiles as configuration, so both
probes returned NO DECISION against a guard that was working perfectly.
```

## bin/admission-verify.sh, lines 231-235 (before this edit)

```text
guard-apiroute REPAIRS rather than decides, so it is probed on a throwaway
config dir: a clean settings.json is accepted, then one that routes Claude Code
to a dead port must come back without the key and with a block reason (a routed
file seen for the FIRST time is a baseline, never a repair). Wired AND working,
or it is not on. CLAUDE_PROJECT_DIR is pinned so no real project is read.
```

## bin/admission-verify.sh, lines 252-254 (before this edit)

```text
govern-hook --box (harbor#516) is the merge backstop wired box-level, probed on a
throwaway REGISTERED repo whose gate-merge-check.sh always refuses: a merge named by
-R from outside that repo must come back denied. Wired AND deciding, or it is not on.
```

## bin/admission-verify.sh, lines 280-283 (before this edit)

```text
4. And that benign work still passes — a floor that blocks everything is also broken.
   Routed through runnable() for the same reason as probe(): with admission-bash.sh
   absent these two reported "OVER-BLOCKS ordinary work" and "kill-switch
   BROKEN", which sends the reader to debug a guard that is not there.
```

## bin/admission-verify.sh, lines 295-297 (before this edit)

```text
5a. Every decider that is meant to carry the kill-switch does (harbor#954): the set admission-decider-set.sh derives from the
    wiring floor-install writes, the same one lint F1 and floor-test read. Installed deciders only; an absent one is
    the presence check's finding (1.), and a copy with no admission-decider-set.sh beside it says so rather than guessing a list.
```

## bin/admission-verify.sh, lines 311-314 (before this edit)

```text
5b. THE APPROVAL GATE (harbor#1018). Its click is an `ask` rule on the installed gate-approve.sh: without the rule
    nothing asks anyone. And a PermissionRequest hook can grant a prompt with no person, so one this floor does
    not own makes every click untrusted (gate-approve.sh refuses then too). Settings files only: a plugin's hooks,
    --settings on the command line and mods are not seen here (docs/design/approval-gate.md, residual risks).
```

## bin/admission-verify.sh, lines 342-345 (before this edit)

```text
COMPLETENESS FIRST, then equality. A truncated manifest matches a truncated
pin, so "unchanged" was reported over live injections when a planted symlink
dropped whole surfaces from both sides (pass 11, B8-02, critical). An empty
diff only means something if every surface is actually IN the pin.
```

## bin/admission-verify.sh, lines 357-358 (before this edit)

```text
THE REMEDY HAS TO BE A COMMAND THE PINNER ACCEPTS (harbor#142, #148): its own target
spelling, --live for the live dir and --dir '<dir>' otherwise (the install standard).
```

## bin/admission-verify.sh, lines 362-384 (before this edit)

```text
PINNED AS ABSENT IS NOT PINNED, and the completeness loop above cannot tell
the difference. floor_instr_manifest emits `absent  <name>` for a surface
that does not exist, and that line satisfies the `  <name>$` grep — so a box
with NO CONSTITUTION AT ALL passes completeness, passes equality, and prints
"instruction surfaces pinned and unchanged" over a session running with no
doctrine loaded at all. This is the same shape as the truncated-pin bug the
completeness loop was added to fix (pass 11, B8-02), one level down: there,
a missing LINE read as clean; here, a present line for a missing FILE does.

The arm is reachable and not hypothetical — the live pin's own first line is
`absent  CLAUDE.local.md`. Found 2026-08-03 by an adversarial pass on a
proposed CLAUDE.md deploy path, whose acceptance test would have been
byte-identical green whether the deploy had happened or not.

ADVISORY, NOT A FAILURE, and the severity is MEASURED rather than chosen:
test-sandbox-make.sh:69 aborts when floor-verify fails, and it never writes a
CLAUDE.md into a sandbox — so `no` here would break every
`sandbox-make --with-floor`, which is the false-positive class that gets a
check switched off (№2.11).

ONLY CLAUDE.md is named. CLAUDE.local.md, agents, commands and output-styles
are absent on an ordinary box by design, and an alarm that fires on the
ordinary case is an alarm that gets muted.
```

## bin/admission-verify.sh, lines 394-410 (before this edit)

```text
── is the installed floor still equal to its source? ──────────────────────
B6 above pins the box to ITSELF (a baseline it wrote) and B8 pins instruction
surfaces; `bin/` is in neither. So a guard that is present, wired, non-empty
and stale passes every check made so far. drift-install.sh asks the one
question none of them do.

DELIBERATELY `adv`, NOT `no`. On 2026-09-05 the live floor was 47/48 current
with one unsourced helper — a real finding, and nowhere near "the floor is
off". Wiring a true-but-minor difference into the FAIL path would make
`floor-verify` red on an ordinary box, and a command that is always red is a
command nobody reads (CLAUDE.md No.2.11). Promoting it to fail-closed is the
operator's call, not this script's.

It runs from the REPO copy on purpose: the tool resolves its repository from
its own location, so an installed copy under a config dir that is not a git
checkout could not answer. Absent means skipped and said so, never a silent
pass.
```

## bin/admission-verify.sh, lines 425-428 (before this edit)

```text
── the mods lockdown (harbor#1022): a root-owned managed file refusing user mods ──
Runs for --live, or wherever HARBOR_SCOPE_MANAGED_SETTINGS names a file (the test path). A sandbox --dir
has no managed tier of its own, so it skips rather than reporting the host's file against it.
HARBOR_SCOPE_MANAGED_OWNER_UID (default 0) lets a fixture stand in for root; production never sets it.
```

## bin/admission-verify.sh, lines 435-437 (before this edit)

```text
a missing file is the state before the operator's one sudo install, so it warns; a present file that is
wrong (key unset, unparseable, not root-owned) still fails below. Failing here would turn every box
red, and deploy's own verify with it, before the install this row asks for can run.
```

## bin/admission-verify.sh, lines 452-453 (before this edit)

```text
The managed line's gate. The compose reads contracts/ and the private layer, so the installed copy skips, as
install-drift does. Born warn (standards/naming/controls.tsv): drift and unchecked are advisories, never a FAIL.
```

## bin/admission-verify.sh, lines 470-472 (before this edit)

```text
SILENCE IS CLEAN ONLY FROM A GATE THAT RAN (harbor#767). guard-integrity always
exits 0 and passes a clean state silently, so a crash, a non-zero exit or a
signal also prints nothing — and read as "reports clean".
```

## bin/admission-verify.sh, lines 479-482 (before this edit)

```text
A BLOCK IS NOT AN ADVISORY (harbor#767). `continue:false` + stopReason refuses
the next session, and this passed it to adv(), so a box that could not start a
session ended "FLOOR IS ON". Only a bare systemMessage is advisory; output this
cannot classify cannot be ruled out as a block, so it fails too.
```
