---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/admission-integrity.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/admission-integrity.sh, lines 12-22 (before this edit)

```text

INSTALLS LAST, after the floor is live and verified (docs/explanation/admission-baseline.md order): a gate
that blocks sessions must never be the thing that breaks the install.

Mechanism (verified against the hooks docs): a SessionStart hook CANNOT block
via exit code — exit 2 is a non-blocking error there. The only hard stop is
emitting {"continue": false} on stdout, so that is what a drift verdict does,
alongside systemMessage (operator) and additionalContext (model). Threat
model per REVIEW F10: the mutators are InstallHooks.ts / InstallSettings.ts,
which re-edit settings.json after any fork upgrade — exactly the drift this
catches (docs/reports/platform-epic.md:160, "the floor is swallowable over time").
```

## bin/admission-integrity.sh, lines 39-41 (before this edit)

```text
pin-instructions.sh is here because B6 TRUSTS it: its advisory tells the
operator to run it, and floor-verify calls it. An edited copy reported the
surfaces clean over a live injection (pass 10, RT10-03).
```

## bin/admission-integrity.sh, lines 46-65 (before this edit)

```text
WHICH DIR THE RECOVERY COMMAND NAMES (harbor#110). Every hint below used to
hardcode `--live`, and `--live` in admission-deny.sh/deploy-restore.sh means literally
$HOME/.claude — it does NOT follow CLAUDE_CONFIG_DIR, deliberately, because
those tools use it as the accident gate that stops a caller who meant a
sandbox from rewriting the real box. But $CFG here comes from
floor_config_dir, which DOES follow CLAUDE_CONFIG_DIR. So a gate that fired
against a sandbox printed a command aimed at live: run it and you re-pin the
operator's real config, blessing whatever drift is sitting on it under a
verdict that was never measured there.

The two halves are each right on their own; only the hint spanned them. So the
hint names the dir the verdict was measured against, in a spelling those tools
accept for that dir: `--live` when they are the same, the positional form when
they are not. The physical compare is P11-01's — a trailing slash must not
decide which box an operator is told to rewrite.

LIVE_DIR, not a bare path, because lint D1 draws exactly this line already:
naming the live dir in order to COMPARE it is the sanctioned idiom; reading or
writing state through a hardcoded path is not. Nothing here operates on
LIVE_DIR — $CFG is the only dir this gate ever touches.
```

## bin/admission-integrity.sh, lines 69-76 (before this edit)

```text
THE HINT IS A COMMAND THE OPERATOR PASTES, so every path in it has to survive
the shell a second time (PR #113, Codex P2). A config dir carrying a space —
`/tmp/harbor test` — split into two arguments: deploy-restore.sh would restore
`/tmp/harbor` while admission-deny.sh took `test` as its target. That is harbor#110
one level in: the hint naming a directory other than the one the verdict was
measured against, this time by word-splitting rather than by flag semantics.
Quoting `--live` too is harmless — the shell strips it back to the flag — and
uniform quoting means there is no branch here to get wrong later.
```

## bin/admission-integrity.sh, lines 90-92 (before this edit)

```text
Tracked apart from $DRIFT because the RECOVERY differs by class: a settings or
teeth drift is re-pinned with admission-deny.sh, and a guard CONTENT drift is not
— floor-deny never writes .helm-pins. See the $RECOVER block at the end.
```

## bin/admission-integrity.sh, lines 99-101 (before this edit)

```text
Fail CLOSED: a missing pin or missing jq means the gate cannot verify, which
is itself a drift verdict — the opposite of the fail-open guards, and the
same idiom as the work-log gitleaks gate.
```

## bin/admission-integrity.sh, lines 110-149 (before this edit)

```text
Distinguish the floor's TEETH from ordinary user state. enabledPlugins and
extraKnownMarketplaces are written by the /plugin UI: hashing them into a
fail-CLOSED gate meant installing a plugin locked the operator out of
every session, with a recovery hint that would silently uninstall it
(red-team pass 3 — the one failure with no in-session escape). Plugin
drift is still worth saying out loud, because plugins ship hooks and
skills (REVIEW F13) — it is reported, not blocking.

THE SAME TIERING NOW CARRIES THE REST OF settings.json (harbor#221). The
projection above used to name FOUR selected fields, so everything else in
the file was unwatched by this gate and unwatched by B8, which does not
list settings.json at all. On 2026-08-16 a slash command rewrote the file
— 12,237 bytes, a new top-level `autoMode` key — and no control on the box
said anything. The write was benign, which is exactly what proves the
point: the same channel adding a `permissions.allow` entry or flipping
`defaultMode` would have been equally silent, and the gate cannot tell the
two apart.

`perms:.permissions` replaces the four fields, so allow, ask, defaultMode
and additionalDirectories are covered. The `keys` arm watches the NAMES of
top-level keys, which is how `autoMode` would have been caught, without
hashing volatile user state that no rule reads.

`hooks` IS EXCLUDED FROM THE KEY SET, measured rather than aesthetic:
admission-install.sh writes the hook wiring AFTER it pins the baseline, so a
freshly installed floor reported drift against its own install. Six
assertions went red on it, including "a freshly pinned state is not
silent" — a gate that cries wolf the moment it is installed is §2.11 in
its purest form. It costs no coverage: hook wiring is checked directly
below by check_wired, which asserts each floor hook is wired under the
RIGHT EVENT with a matcher that can fire, and that is strictly more than a
key-name hash could say. The alternative was reordering three writers to
pin last — a wider change for a weaker check.

THE NEW COVERAGE IS ADVISORY, NOT TEETH, AND THAT IS DELIBERATE. Clicking
"always allow" on a prompt writes `permissions.allow` — an ordinary,
frequent, legitimate act. A fail-closed gate over it would reproduce the
/plugin lockout with a commoner trigger, and §2.11 makes that a defect
rather than safety. deny and the two locks stay fail-closed; everything
else in the file is reported and re-pinnable.
```

## bin/admission-integrity.sh, lines 153-161 (before this edit)

```text
`--repin`, NOT `--apply`. This branch is reached with deny and the locks
already INTACT — only the plugin/marketplace hashes moved — so there is
nothing to add and `--apply` is the wrong verb twice over: it re-adds the
full B1 entry set, which RESURRECTS any entry the operator withdrew
deliberately (admission-deny.sh's WITHDRAWN list), and it is the flag whose
blast radius made deploy-runtime-install.sh choose `--repin` for exactly this
situation ("--repin adds no deny entry, so a withdrawn entry stays
withdrawn", deploy-runtime-install.sh). The checkout path matches the idiom
session-verdicts.sh already prints for the same recovery.
```

## bin/admission-integrity.sh, lines 168-169 (before this edit)

```text
Every floor hook still wired, under the RIGHT EVENT and a matcher that can
actually fire for the tools the guard exists to inspect.
```

## bin/admission-integrity.sh, lines 187-192 (before this edit)

```text
GATED ON THE PIN, so this cannot false-alarm a box installed before these two
guards existed. admission-install.sh both pins (:82) and wires (:122-123) them in
the same run, so on any box where the pin is present the wiring was present
too — which makes a missing hook here real drift and not an old install.
Unwiring is the cheaper attack than editing: the content pin above catches an
edited admission-cloud.sh, and until now nothing caught a deleted hook entry.
```

## bin/admission-integrity.sh, lines 197-201 (before this edit)

```text
guard-deliverables answers on the FILE TOOLS as well, and the Bash check
above cannot see that half. It is one hook entry under one alternation, so
today both checks read the same line — but narrowing that matcher to `Bash`
is a one-word edit that would leave every Write of a loose document ungated,
which is the majority of the traffic this guard exists for, silently.
```

## bin/admission-integrity.sh, lines 205-207 (before this edit)

```text
guard-apiroute repairs AFTER a call, so its wiring is PostToolUse, and the
Bash matcher is the one that matters: the 2026-09-17 reroute came from a
program a shell command ran. Gated on the pin for the same reason as above.
```

## bin/admission-integrity.sh, lines 216-226 (before this edit)

```text
EVERY WIRED COMMAND MUST NAME A FILE THAT RUNS, PINNED OR NOT (harbor#960). A
hook whose file is gone exits 127, which Claude Code treats as non-blocking:
the guard is off and the session proceeds. The checks above are gated on a
pin under the OLD name, so renaming a script and its pin together while
settings.json still wired the old path passed this gate silently, and so did
a missing admission-hook.sh, the wrapper behind three guards (research/07, T2/C).
Scope is this config dir's bin/: a user's own hook elsewhere is not ours.
Tokens honour "…" and '…'; $HOME, ${HOME}, ~ and $CLAUDE_CONFIG_DIR expand
outside single quotes, as the shell running the hook would expand them.
Run as wired: the command word needs +x (126 otherwise); a file handed to an
interpreter needs to be readable and non-empty — an empty script exits 0.
```

## bin/admission-integrity.sh, lines 265-282 (before this edit)

```text
This line used to read `for g in $GUARDS library-admission.sh admission-normalize.awk`,
which made it the third of FOUR hand-maintained copies of one set:
admission-install.sh:82 (the payload it writes pins for), $GUARDS above,
deploy-runtime-install.sh's drift report, and admission-verify.sh's presence loop. Copies
drift silently while reading correctly, and these had already drifted.

MEASURED 2026-08-14 on a clean `admission-install.sh --with-b6` install:
admission-cloud.sh and admission-destroy.sh (harbor#194/#201) ship in the payload, are
WIRED by the installer, and are PINNED in .helm-pins/ beside the others — and
no verifier ever read those pins back. Gut both to `exit 0` and this gate exits
0 SILENTLY with the disagreeing pin sitting in the same directory;
admission-verify.sh said nothing either. context-resolve.sh and admission-hook.sh had
the same hole for longer. The pin existed the whole time. Nothing read it.

$GUARDS STAYS as the floor MINIMUM rather than being replaced by the pin dir,
because deriving only from the pins means DELETING a pin removes its guard from
the check — and the `no content pin for` branch below is the thing that makes a
deleted pin visible. Union, so neither direction can hide a file.
```

## bin/admission-integrity.sh, lines 285-286 (before this edit)

```text
POSIX sh has no nullglob: an unmatched pattern arrives as the literal string,
so this is a real guard and not a formality on a box with no pins yet.
```

## bin/admission-integrity.sh, lines 289-293 (before this edit)

```text
B6 DOES NOT CHECK B6, and that is §2.11, not an oversight. deploy-runtime-install.sh
carries admission-integrity.sh in REFRESH_ONLY and deliberately does NOT move its
pin ("the pin on the gate is the operator's to move"), so checking it here
would make every `runtime-install --apply` block the next session with an
alarm the installer the operator was just told to run had itself caused.
```

## bin/admission-integrity.sh, lines 302-303 (before this edit)

```text
Content hash, not mere presence: a guard truncated to its kill-switch line
plus `exit 0` passed every earlier check (red-team pass 6).
```

## bin/admission-integrity.sh, lines 309-310 (before this edit)

```text
Tracked separately from the message, because the RECOVERY for this drift
class is not the recovery for a settings/teeth drift — see $RECOVER below.
```

## bin/admission-integrity.sh, lines 317-337 (before this edit)

```text
Not hooks: sourced library, data, and the operator's pinning tool. They are
content-pinned above but have no kill-switch line to carry.

THE FOUR ADDED WITH THE DERIVED SET ABOVE ARE MEASURED, NOT ASSUMED. Their
first live lines on 2026-08-14 are `set -u` / `set -eu`, so requiring the
kill-switch of them would have raised a session-BLOCKING alarm the moment the
pin dir became the source of truth — the §2.11 defect, shipped by the fix for
a §2.11 defect. deploy-harden.sh is the one that proved it: admission-install.sh:223
pins it whenever it happens to be in bin/, which the recovery fixture does, so
the widened loop turned the RESTORE path into a lockout (floor-test Q-R6 went
red — the assertion that exists because that lockout already happened once).

admission-observe.sh is the sharp one: it IS a wired hook (SessionStart,
admission-install.sh:143), so its exemption is a finding rather than a category —
a wired hook that does not honour HARBOR_ADMISSION_DISABLE. Left as it is on purpose
(an observer writing a ledger under a disabled floor is not a gate acting),
and floor-test X15 asserts this line stays the EXHAUSTIVE set, so the next
pinned file without a kill-switch goes red in CI instead of at the operator's
next SessionStart.
baseline-pin.sh is retired (harbor#765) but stays exempt while boxes still carry its pin.
library-log.sh and deploy-install-lib.sh are sourced libraries of the recovery path (harbor#771, #765).
```

## bin/admission-integrity.sh, lines 341-344 (before this edit)

```text
$FLOOR_GREP, not bare grep: this file sources guard-lib and therefore has
the pinned interpreter in scope, and this IS the kill-switch presence
check — a grep-resolution difference here decides whether the gate blocks
the session (convention audit 2026-07-25).
```

## bin/admission-integrity.sh, lines 355-364 (before this edit)

```text
CLAUDE.md, agents/, skills/, commands/, output-styles/ are loaded into every
session, so a write there is an instruction the model follows from the NEXT
session on. They stay writable by owner decision; this makes the change
visible at exactly the session where it would first take effect.

ADVISORY, not blocking, and deliberately so. These are surfaces the operator
edits as ordinary work — making them fail-closed would turn "I added a skill"
into a locked-out session, which is the failure that already had to be undone
once for plugins (red-team pass 3). Reported ≠ ignored: the message names the
changed paths and the model sees it too.
```

## bin/admission-integrity.sh, lines 368-369 (before this edit)

```text
Previously this fell through to the diff, which also failed, producing the
content-free "(0 path(s): )" (red-team B8-07). Say what is actually wrong.
```

## bin/admission-integrity.sh, lines 378-382 (before this edit)

```text
Count PATHS, not diff lines: an edited file produces both a `<` and a `>`
line, so counting lines reported "2 changed" for one changed file.
The path is everything after the two-space separator — `awk '{print $NF}'`
returned only the last word, so a file named "my evil skill.md" was
reported as "skill.md", a path that does not exist (red-team B8-06).
```

## bin/admission-integrity.sh, lines 385-413 (before this edit)

```text
── DRIFT HAS TWO CLASSES, AND ONE WAS CAMOUFLAGING THE OTHER (harbor#135).
`projects/*/memory` is a watched surface for a good reason — it is the
auto-memory injected into every session, the highest-value injection target
in the tree — but the MODEL writes it as part of ordinary work. Measured on
this box: memory files were modified on 11 of the last 13 days. So the
advisory was red almost every day, and the operator can only clear it from
their own terminal, which is harbor#135's complaint. An advisory that is
permanently red is one nobody reads, and library-admission.sh's own comment says so
in those words about the `.in_use` markers it prunes for exactly this
reason.

NOT PRUNED — SPLIT. Dropping the memory dir from the watch list was tried
once and refuted on measurement (B8-NOISE-06); it is model-authored content
loaded into every session, which is precisely what this check exists to
surface. What was wrong was reporting it in the same breath as a change to
CLAUDE.md, hooks/ or skills/, because then the day a real instruction
surface moves it arrives inside a sentence the reader has learned to skip.
Both classes are still reported, still need the same deliberate re-pin, and
neither is auto-blessed. Only the SENTENCE changes — which is the whole
remedy, because the failure was one of attention, not of coverage.
`(/|$)`, NOT a bare `/`. floor_instr_manifest emits an UNMATCHED GLOB
LITERALLY — its own comment says so — so a config dir with no memory yet
carries the entry `projects/*/memory`, and the first memory file both
removes that literal and adds a real path. With the trailing slash
required, the literal fell into the NON-memory class and a pure memory
write was announced as an instruction-surface change naming `projects/*/
memory`, a path that does not exist. Caught by B8-05, which asserts the
real path is named — the same shape as B8-06, where `awk '{print $NF}'`
reported "skill.md" for "my evil skill.md".
```

## bin/admission-integrity.sh, lines 414-421 (before this edit)

```text
── A STANDING ADVISORY NAMES WHAT IS NEW (harbor#1390). The same 26 paths, reprinted at every SessionStart
until a re-pin, is an alarm the reader learns to skip, and then the 27th scrolls past with it. So every changed
path is still COUNTED, but a path is NAMED only in the first session that sees its current content, and the rest
are summed with the age of the oldest. The record is <cfg>/.helm-context/instructions.seen, `<epoch> TAB <key>`
per changed path, the key being its manifest line now (`gone  <path>` once removed), so a path edited again is
new again. .helm-context is an integrity row: a session cannot write the record to keep its own edit unnamed.
Only a run with a session id writes it, so `harbor verify` names what is new and consumes nothing. A record
that is lost or unreadable names everything, the old behaviour; a clean manifest deletes it (the re-pin).
```

## bin/admission-integrity.sh, lines 453-454 (before this edit)

```text
The named paths are the NON-memory ones, always — a real instruction
surface must never be the entry `head -6` truncated away.
```

## bin/admission-integrity.sh, lines 464-470 (before this edit)

```text
THE PATHS ARE STILL NAMED HERE. The first cut printed only a count, and
B8-05 went red for the right reason: it asserts that a memory file which
changed is NAMED, and an operator who cannot see which file changed
cannot review it — which is the whole instruction the advisory ends with.
Nothing is being crowded out in this branch, so naming them costs
nothing; the crowding problem was the MIXED case, and that is handled
above by putting the non-memory paths first.
```

## bin/admission-integrity.sh, lines 481-493 (before this edit)

```text
WHY HERE AND NOT EVERY SESSION. store-check costs ~0.9s, of which ~0.7s is
context-budget deriving the allowance — a tax on every session start is how
a guard earns being switched off (No.2.11). The index can only GROW when a
memory file is written, and that is exactly the condition this branch
already detected, so the check is free on an ordinary session and runs when
it can have changed.

THE KNOWN GAP, stated rather than hidden: an index that is already over
budget, unchanged, and re-pinned goes quiet until the next memory write.
The alternative was caching the derived allowance, which is a second copy of
a number that must agree with HARBOR_CONTEXT_CEILING — the exact thing
store-check's own header refuses. A gap that re-fires beats a copy that
silently disagrees.
```

## bin/admission-integrity.sh, lines 519-524 (before this edit)

```text
OBSERVE-1 (harbor#41). This gate reaches a SESSION-BLOCKING verdict while
exiting 0 — it denies via {"continue":false} on stdout, not via exit 2. So a
ledger built on "hook floor_block" would miss the only control in the floor
that can stop a whole session. It is also the one script running `set -u`
WITHOUT `-e`, which is why the tests assert its stdout byte-for-byte rather
than trusting its exit code.
```

## bin/admission-integrity.sh, lines 533-549 (before this edit)

```text
THE RECOVERY DEPENDS ON WHAT DRIFTED, and until 2026-08-02 it did not. This
message named `admission-deny.sh --live --apply` for every drift class, including
guard CONTENT drift — for which it does nothing whatever: floor-deny mentions
.helm-pins only inside the deny LIST it writes, and never refreshes a content
pin. So the gate blocked the session and handed the operator an instruction
that could not unblock it. Found live, after deploy-runtime-install.sh replaced
library-admission.sh and context-resolve.sh with their (identical-to-main) copies.

THE PIN REFRESH IS DELIBERATELY NOT WRAPPED IN A TOOL. Re-baselining the file
that judges the agent is the operator's act — CONSTITUTION § "Encoding a fix is
a human-gated act" — and a script that did it would be reachable by the very
agent whose changes B6 exists to catch. permissions.deny stops an Edit of
.helm-pins and guard-bash stops a redirect into it, but neither can see what a
script does internally. So the gate hands over the exact command and stops.

The hasher named is the one THIS machine has: a message that tells a macOS
operator to run sha256sum is a message that fails on the box printing it.
```

## bin/admission-integrity.sh, lines 552-565 (before this edit)

```text
$TGTQ AND $CFGQ, NOT `--live` AND A BARE PATH. harbor#110 is the rule that a
recovery hint must name the dir the verdict was measured against, and the fix
for it landed on the settings branch below while THIS branch kept both halves
of the bug: a hardcoded `--live`, which means literally $HOME/.claude in
deploy-restore.sh regardless of CLAUDE_CONFIG_DIR, and an unquoted $CFG, which the
header at :60 explains splits a config dir containing a space into two
arguments. So a content drift measured on a SANDBOX printed "deploy-restore.sh
--live": paste it and you overwrite the real box from a verdict that was never
taken there — the exact inversion harbor#110 exists to prevent, in the one
message a locked-out operator has to act on.

It survived because X9 asserts only that this branch names .helm-pins and the
drifted file, never which DIR it aims at, and X9b asserts the dir on the
settings branch only. Both directions are asserted now.
```

## bin/admission-integrity.sh, lines 568-592 (before this edit)

```text
THE PATH WAS DANGLING AND THE FLAG WAS WRONG — both, in the one message a
locked-out operator has to act on, and harbor#103 fixed only the CONTENT-drift
half of the same sentence.

The path: NO INSTALLER SHIPS admission-deny.sh. admission-install.sh copies its GUARDS
list plus admission-integrity.sh; deploy-runtime-install.sh copies FILES plus
REFRESH_ONLY. admission-deny.sh is in none of them, and was confirmed ABSENT from
the live ~/.claude/bin on 2026-08-02 — so this line named a file that is not
there. Lint X7 reports it. deploy-restore.sh above is fine: it IS in FILES.

It is NOT fixed by adding admission-deny.sh to a payload. floor-deny --repin
re-pins .sec0-baseline and .helm-floor-teeth — the two hashes THIS gate checks
— so putting it inside the config dir installs a one-command amnesty for the
gate, next to the gate, and nothing would stop a session running it:
permissions.deny binds the Edit/Write TOOLS and carries no Bash entry that
matches, and the guard-bash rule that once matched a pinner's filename was
DELIBERATELY WITHDRAWN after producing six false positives in pass 10
("is this command RUNNING that script against that directory?" is not
decidable from command text). The checkout copy is equally reachable today,
so this is not a hole being closed — it is a hole not being dug closer.

The flag: `--apply` re-adds the full B1 entry set and RESURRECTS anything the
operator withdrew. Re-pinning a baseline is `--repin`, which adds nothing.
Both corrections match what session-verdicts.sh already prints for this exact
drift, so the operator sees one idiom rather than two.
```

## bin/admission-integrity.sh, lines 4-14 (before this edit)

```text
Asserts, at every session start, that the floor is intact:
  1. permissions.deny + mode locks + plugins + marketplaces hash-match the
     pinned baseline (.sec0-baseline.sha256, deploy-harden.sh:82 recipe)
  2. every floor guard is present, non-empty, and still carries the
     HARBOR_ADMISSION_DISABLE kill-switch on its first live line
  3. every floor hook is still wired in settings.json, and every hook command
     wired into this bin/ names a file that runs as wired (harbor#960)
On drift it BLOCKS the session; a clean state passes silently.
INSTALLS LAST, after the floor is live and verified (docs/explanation/admission-baseline.md order): a gate that blocks sessions must never be what breaks the install.
Mechanism: a SessionStart hook CANNOT block via exit code (exit 2 is a non-blocking error there); the only hard stop is {"continue": false} on stdout, alongside systemMessage (operator) and additionalContext (model). Threat model (REVIEW F10): InstallHooks.ts / InstallSettings.ts re-edit settings.json after any fork upgrade, which is the drift this catches.
Removed notes: docs/explanation/code-cases/bin-admission-integrity.md
```

## bin/admission-integrity.sh, lines 20-21 (before this edit)

```text
harbor#1390: a hook run carries a session id, and only a session records what B8 named (see B8 below). A terminal
stdin is a hand run with no payload, never something to wait on.
```

## bin/admission-integrity.sh, lines 49-50 (before this edit)

```text
pin-instructions.sh takes the same two spellings (the install standard, harbor#765): its --live is
$HOME/.claude only, so a sandbox verdict must name --dir, or the re-pin blesses the wrong box.
```

## bin/admission-integrity.sh, lines 327-328 (before this edit)

```text
A dangling hook is fixed by the file or by the wiring; floor-deny re-pins neither,
so a wiring-only verdict does not name it.
```
