---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/admission-observe.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/admission-observe.sh, lines 3-21 (before this edit)

```text

THIS SCRIPT HAS NO KILL-SWITCH LINE, AND THAT IS THE ENTIRE POINT.
Every guard and admission-hook.sh open with `[ "${HARBOR_ADMISSION_DISABLE:-0}" = "1" ]
&& exit 0` on line 2, and admission-install.sh wires every PreToolUse guard THROUGH
admission-hook.sh. So under an override the wrapper returns at line 2 and the guard
is never spawned: zero processes, zero rule evaluations, nothing anywhere in
the floor that could record that the operator walked past it. An override is
the operator saying "this rule is wrong" with their hands instead of their
mouth — the highest-quality feedback signal in the system — and it was
structurally unobservable. A hook that runs REGARDLESS of the switch is the
only place it can be seen.

bin/decider-set.sh lists this file as exempt from the kill-switch line, with that reason, and lint F1
reads the list. It is SessionStart-only and never reaches a verdict: it cannot block anything.

It is also the ONLY component permitted to create anything. floor_log_decision
on the hot path creates nothing — see library-admission.sh property 3 — so every
directory, the sink, the host token and the salt are made here, once, at
SessionStart, where a fork costs nothing and no verdict is pending.
```

## bin/admission-observe.sh, lines 31-41 (before this edit)

```text
Sourced HERE, not at the recording block below, because the host partition needs
floor_host_token before it can name a directory. library-admission.sh creates nothing at
source time (its property 3), so moving this up adds no side effect and no fork.

Absent library means exit 0, not a degraded token. Nothing this script creates
has any value without the library that records into it: the sink, the salt and
the host token exist only to be written by floor_log_decision. B6 hash-pins
library-admission.sh, so its absence is already a floor failure that guard-integrity
reports under its own name — inventing a second, quieter spelling of that
failure here would create a ledger directory for a floor that cannot record,
which reads as "observed and clean" instead of "not observed".
```

## bin/admission-observe.sh, lines 45-46 (before this edit)

```text
A SessionStart hook must never be the thing that breaks a session. Everything
below is best-effort; the script exits 0 on every path, including this one.
```

## bin/admission-observe.sh, lines 49-65 (before this edit)

```text
obs_safe_write <path> <content> — the ONLY way this script creates a file.

REVIEW 2026-07-28 (#47, findings 1 and 2), both REPRODUCED. The two token files
were written with a bare `> "$F"`, and that is two separate holes:

  FIFO   `mkfifo ~/.claude/.helm-obs-host` makes `>` block in open(2) forever.
         `2>/dev/null` cannot catch a BLOCK. The write sat between 'chmod 0700'
         and 'chmod 0500', so when the harness killed the hung hook the host dir
         was left WRITABLE — and floor_log_decision's `[ ! -w ]` gate then
         refused on every call, permanently blinding the ledger. floor-install
         runs this synchronously, so the installer hung too.
  SYMLINK `ln -s ~/anything ~/.claude/.helm-obs-host` made `>` truncate and
         overwrite the TARGET at every SessionStart.

library-admission.sh's hot-path READER type-checks these same two files for exactly
this reason. The writer did not. Write via a temp file inside a directory we
control, then `mv` — so the final name is never opened through a link or a FIFO.
```

## bin/admission-observe.sh, lines 70-74 (before this edit)

```text
The temp path needs the SAME gate as the final one (pass-2 review): the first
cut only moved the unchecked `>` from "$_p" to "$_t", so a planted symlink or
FIFO at the temp name reopened both holes one name over. `[ -e ]` alone is not
the check — a symlink to a NON-EXISTENT target makes it false, and `>` then
creates through the link.
```

## bin/admission-observe.sh, lines 78-78 (before this edit)

```text
And re-check what we actually created before trusting it.
```

## bin/admission-observe.sh, lines 85-90 (before this edit)

```text
── the host partition ──────────────────────────────────────────────────────
THE SAME FUNCTION as hooks/worklog-push/worklog-push.sh and hooks/memory-harvest/memory-harvest.sh call, so the
ledgers partition identically and a cross-device merge lines up. This used to be
three copies of one `hostname -s` expression, which stayed byte-identical right
up until the value itself moved and forked all three ledgers at once — see
floor_host_token in library-admission.sh for the measurement.
```

## bin/admission-observe.sh, lines 97-99 (before this edit)

```text
The host dir is held at 0500 for the rest of the session, so every step that
needs to CREATE something has to open the mode and close it again. Failing
closed here means failing BLIND — records drop, no verdict is affected.
```

## bin/admission-observe.sh, lines 102-108 (before this edit)

```text
The 0500 restore is a TRAP, not just a line at the end: a hook killed at its
timeout (the FIFO case above) otherwise leaves the directory writable, and a
writable host dir is precisely what reopens the plant this design closes.
The signal handlers must EXIT (pass-2 review). A trap body without `exit`
swallows the signal: the script resumes, the harness sees it still alive and
escalates to SIGKILL — which bypasses traps entirely and leaves the host dir
writable, i.e. exactly the state this trap exists to prevent.
```

## bin/admission-observe.sh, lines 113-123 (before this edit)

```text
── rotation: one live generation, closed ones archived ─────────────────────
Bounded by SIZE and not by date. A day-partitioned FILENAME would need the hot
path to create tomorrow's file at midnight, and the hot path cannot create —
so a session crossing midnight would go silently blind for its whole remainder.
The clock lives in each record's `ts` instead, which loses nothing: file order
is authoritative.
obs_prepare_sink <path> — rotate, type-check, create, 0600. Returns 1 when the
path is refused. ONE spelling for BOTH ledgers (harbor#465): this was inline
and single-use until tool-failures.jsonl arrived, and a second copy of a
rotation-plus-type-check is exactly the shape that drifts while both halves go
on reading correctly.
```

## bin/admission-observe.sh, lines 124-125 (before this edit)

```text
obs_archive_generation <path> — moves a closed generation to archive/<base>.<UTC stamp>.jsonl, 0400,
never replacing an existing archive. Returns 1 (and moves nothing) when it cannot.
```

## bin/admission-observe.sh, lines 152-154 (before this edit)

```text
The old .1 is archived before it is replaced, never overwritten: one generation lost
2026-08-06..10-04 of the guard ledger. Archive refused -> no rotation (an oversize sink
loses nothing). Archived names miss every reader's `<sink>*` glob, so reads stay bounded.
```

## bin/admission-observe.sh, lines 160-162 (before this edit)

```text
A pre-existing NON-FILE at the sink path (a FIFO, a directory, a symlink) is
refused rather than reused: the hot path type-checks too, but a sink it will
always refuse is a ledger that is silently empty forever.
```

## bin/admission-observe.sh, lines 174-183 (before this edit)

```text
── the SECOND ledger: tool outcomes, not guard decisions (harbor#465) ──────
Written by failure-observe.sh at PostToolUseFailure, and created HERE for the
same reason guard-decisions.jsonl is: the host dir goes back to 0500 below and
stays there, so nothing on a hook path can create anything afterwards.

A REFUSAL HERE DOES NOT EXIT, and the asymmetry is deliberate. Above, a refused
guard sink means the thing this whole script exists to prepare cannot be
prepared. Here, the guard ledger is already ready — exiting would skip the salt
and the host token below and take out the FIRST recorder to punish a defect in
the second. One blind ledger beats two.
```

## bin/admission-observe.sh, lines 186-189 (before this edit)

```text
── the stream root (harbor#1181) ───────────────────────────────────────────
harbor_emit (audit-stream-lib.sh) writes <host>/streams/<stream>/<day>/, and the host dir is 0500 for the rest of the
session, so the root is made here. A writable subdir cannot swap the guard sinks: those are entries of the host
dir itself. A non-directory or a symlink at the path is left alone and every emit spills, which says so.
```

## bin/admission-observe.sh, lines 192-197 (before this edit)

```text
── the per-install salt ────────────────────────────────────────────────────
128 bits, created once and never rotated: rotating it would silently reset
every recurrence count, which is the one question the digest exists to answer.
0600 and outside MEMORY/ — it is a secret, not a record, and MEMORY has a git
remote. Without it floor_obs_digest yields "-" and blocks are still counted,
just not correlated.
```

## bin/admission-observe.sh, lines 215-225 (before this edit)

```text
── the host token the hot path reads with a builtin ────────────────────────
Deriving the token costs a fork (see floor_host_token); the hot path reads this
file with `read` instead. Written every session so a rename of the machine is
picked up at the next start rather than never.

This comment used to say the value "changes once per boot". It does not — that
claim is what let the 2026-08-04 fork go unnoticed, because a value believed
constant is a value nobody checks. The cache is refreshed every SessionStart
precisely because the token CAN move.
Type-checked like every other read of this file: `read` from a FIFO blocks
exactly as `>` does, and a symlink would have us compare against the wrong file.
```

## bin/admission-observe.sh, lines 232-238 (before this edit)

```text
── close the directory, THEN record ────────────────────────────────────────
This ordering is load-bearing. floor_log_decision refuses to write unless the
directory is non-writable, because that gate — not the file type check — is
what makes a FIFO plant unwinnable (library-admission.sh property 2). Recording before
the chmod would work here and teach the wrong invariant; recording after also
proves the gate is satisfiable, which is the failure mode a mode-drift bug
would otherwise hide until the ledger was needed.
```

## bin/admission-observe.sh, lines 241-251 (before this edit)

```text
ARMED vs OVERRIDE. `armed` is the DENOMINATOR: without a count of sessions
where the floor was live, "override rate" is uncomputable and the raw override
count says nothing. Per-RULE attribution of an override is deliberately NOT
attempted here — see the reader, which reports "the last blocks preceding an
override" from file order and labels it exactly that. Claiming to know which
rule the operator walked past would be an inference dressed as a record.
library-admission.sh is already sourced at the top — the host partition needed it — and
its absence exited 0 there, so reaching this point means floor_log_decision is
defined.
harbor#309: the SessionStart payload names the session, so these records carry its key `sk`.
Never from a terminal, where cat would wait for input nobody sends.
```

## bin/admission-observe.sh, lines 253-258 (before this edit)

```text
── a settings `env` block that sets either switch (harbor#954 PR B, from #977) ──
The write-time guards (killswitch-assign, switch-in-settings) catch the plain spellings of putting a switch in
a settings file and miss five shapes (docs/explanation/admission-baseline.md residuals). This reads the files instead, so how the switch got
there no longer matters. It lives HERE because this script runs when the switch is set, which is exactly when
every guard has stood down. A report, never a refusal: a SessionStart hook cannot block, and the operator may
have set it on purpose. Keys only, never values.
```

## bin/admission-observe.sh, lines 277-280 (before this edit)

```text
A SHADOW session (harbor#482) is the third boundary: guards run and record, and
almost nothing blocks. It is its own record, never `armed`, so a shadow session
cannot inflate the denominator of a rate it does not enforce. The kill-switch
wins when both are set, because then no guard runs at all.
```
