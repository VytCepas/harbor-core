---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/admission-hook.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/admission-hook.sh, lines 3-27 (before this edit)

```text
B9 (harbor#39) — fail-CLOSED wrapper for the PreToolUse floor guards.

THE PROBLEM IT SOLVES: every dependency failure in the guard chain was silent,
and the floor still looked installed, pinned and wired:

  jq missing            → guard exits 0   (every field reads empty → allow all)
  guard file deleted    → sh exits 127    (not a deny)
  guard not executable  → sh exits 126    (not a deny)
  guard syntax error    → sh exits 1      (not a deny)

None of those is exit 2, so none of them denies. B6 catches some of it, but
only at the NEXT SessionStart, and B6 installs last. This wrapper converts the
whole class from silent-allow into loud-deny.

  sh admission-hook.sh <guard-path>            # fail-CLOSED (PreToolUse)
  sh admission-hook.sh --advisory <guard-path> # never blocks (PostToolUse)

WHY --advisory EXISTS: exit 2 is meaningless on PostToolUse and SessionStart —
a PostToolUse hook that exits 2 just discards its annotation, and a SessionStart
gate blocks via {"continue":false} instead. Fail-closed is only coherent where
a non-zero exit actually denies, so annotate-web is wrapped in advisory mode
and guard-integrity is not wrapped at all (it is already fail-closed itself).

THE ESCAPE HATCH IS FIRST, DELIBERATELY: a broken floor must never lock the
operator out of fixing it. `HARBOR_ADMISSION_DISABLE=1 claude` always opens.
```

## bin/admission-hook.sh, lines 33-35 (before this edit)

```text
harbor#810: this wrapper's own crash (a fork or exec failure) is a deny, never a non-blocking error.
Safe here only because this file runs without set -e: under -e, bash 3.2 hands an EXIT trap $?=0 for
a fatal set -u or `.` error and the shell then exits 0 (measured), which is why the guards carry none.
```

## bin/admission-hook.sh, lines 38-43 (before this edit)

```text
OBSERVE-1 (harbor#41): the wrapper's OWN denies. These are the class that says
"the floor is broken", as distinct from "a rule fired" — without them a jq
outage reads as a quiet drop in block counts and looks like the rules getting
better. guard-lib is sourced LAZILY, on the deny path only: this wrapper runs
on every tool call and its entire job is to still work when the guard chain
does not, so it must not take a 780-line dependency to say yes.
```

## bin/admission-hook.sh, lines 45-50 (before this edit)

```text
Resolve from the WRAPPER's own directory, never from $GUARD (#47 finding 16).
`dirname -- ''` is `.`, so an empty or relative GUARD sourced
./library-admission.sh from the SESSION's cwd — an attacker-authored file in the repo
being worked on, executing inside the hook with stderr swallowed, able to
`exit 0` and turn this fail-CLOSED deny into an ALLOW.
harbor#810: no dirname fork. A failed or unresolvable $(dirname) resolved this to the cwd too.
```

## bin/admission-hook.sh, lines 57-80 (before this edit)

```text
THE WRAPPER HAS NO SUBJECT, SO IT MUST NOT INHERIT ONE (harbor#350 follow-up).
floor_obs_digest hashes $FLOOR_OBS_SUBJECT, which every GUARD sets from the
payload it just extracted. This wrapper extracts nothing: its denials are
class-level — the guard file is missing, jq is unavailable, the guard exited
without a verdict — and none of them is about a particular command, so `h`
belongs at `-`.

WHY THIS IS A CONTROL AND NOT TIDINESS. harbor#350 widened the digest from
`block` to `block|deny|ask` (library-admission.sh:584). `wrapper deny` is inside that
set and sets no subject, so the value hashed became whatever the ENVIRONMENT
held — and a project's settings.json `env` block can set it. That is the
exact class already refused for FLOOR_GREP, FLOOR_AWK and FLOOR_INSTR_SURFACES
(library-admission.sh:438): an attacker-chosen constant stamped into the one record
class that means "the floor is broken", on the channel FC-2 reads.

LATENT WHEN WRITTEN, NOT WHEN EXPLOITED. Every reader of `h` still filters
`.d=="block"` (audit-triage.sh:489,582,605,750 and admission-observe-report.sh:141),
so nothing consumes it today. Widening those readers is the obvious next step
after harbor#350, and the hole opens the moment it happens — so it is closed
here rather than left as a note on a ticket.

CLEARED, NOT VALIDATED. A charset gate would still let a chosen value through
as long as it looked like a command; only refusing to carry one is sound, and
an empty subject already returns `-` (library-admission.sh:626).
```

## bin/admission-hook.sh, lines 94-96 (before this edit)

```text
The ADVISORY early-exit records too: annotate-web is wired --advisory and can
never signal anything through an exit code, so a wrapper failure there is
invisible by construction unless it is written down.
```

## bin/admission-hook.sh, lines 102-125 (before this edit)

```text
WHICH WIRING, not just which class (FC-2 follow-up). The stderr banner above
already names the guard and the exit code, so the OPERATOR watching a denied
call can see both — but `obs` writes only the rule token, so the ledger keeps
the class and drops the identity. A judge reading that record days later gets
"some guard was missing" and cannot say which of the five wirings it was, which
is why the one live 2026-08-20 record could only ever be diagnosed by the
timestamp next to it.

THE ENRICHMENT IS DISCARDED ON ANY DOUBT. floor_log_decision gates the rule
token to [a-z0-9-] and 40 characters and rewrites ANY violation to
`unclassified` wholesale (library-admission.sh:479-480) — so a basename with an
underscore, or one long enough to overflow, would cost the class name this
record already carried. Worse-than-today is not a trade a diagnostic aid gets
to make, so every step below falls back rather than reaching.

A VARIABLE, NOT A COMMAND SUBSTITUTION: `$(...)` is a subshell fork, and this
wrapper runs on EVERY tool call. Parameter expansion needs no child, and each
caller invokes this from inside its own failure branch — the allow path must
not pay for a diagnostic it will never emit.

NOT ON no-jq / no-grep, DELIBERATELY. Those are one systemic outage, not a
per-guard fault: tagging them by wiring would split a single jq failure into
five rows of x1 in the report's top-rules census and hide the shape that
matters. The interpreter canaries stay class-only.
```

## bin/admission-hook.sh, lines 131-133 (before this edit)

```text
Degrade in the order that keeps the more valuable half: guard+rc, then guard
alone, then the bare class. The rc distinguishes 127 (missing) from 126 (not
executable), but WHICH guard is what routes the repair.
```

## bin/admission-hook.sh, lines 143-157 (before this edit)

```text
CANARY the interpreters the guards depend on. Without jq every floor_field
returns empty, so a guard "sees" an empty command and allows everything — the
most dangerous silent failure in the set.
ABSOLUTE PATH FIRST, exactly as the grep canary below and as guard-lib's
FLOOR_JQ now resolves it. A bare `command -v` made this canary fire on a merely
STRIPPED PATH while /usr/bin/jq was executable and the guards could read it
perfectly well — a deny with nothing wrong. The two checks must agree, or the
canary passes while the guards starve, or denies while they are fine.
THE CANARY HONOURS THE SAME OVERRIDE THE GUARDS WILL USE (review of harbor#341).
Ignoring FLOOR_JQ meant that on a host with no /usr/bin/jq, a VALID allowlisted
override the guards could have parsed with was denied here first — the canary
contradicting the resolver it exists to predict. The allowlist is repeated
rather than sourced because this wrapper must still answer when guard-lib
cannot be read; it is duplicated deliberately, and both copies must move
together.
```

## bin/admission-hook.sh, lines 3-9 (before this edit)

```text
B9 (harbor#39) - fail-CLOSED wrapper for the PreToolUse floor guards.
A missing jq, deleted or non-executable guard, or guard syntax error exits 0/127/126/1, never 2, so none denied; this turns the class into a loud deny.
  sh admission-hook.sh <guard-path>            # fail-CLOSED (PreToolUse)
  sh admission-hook.sh --advisory <guard-path> # never blocks (PostToolUse)
--advisory: exit 2 means nothing on PostToolUse/SessionStart, so annotate-web is wrapped advisory.
The escape hatch on line 2 is first on purpose: a broken floor must never lock the operator out of fixing it.
Removed notes: docs/explanation/code-cases/bin-admission-hook.md
```

## bin/admission-hook.sh, lines 18-19 (before this edit)

```text
OBSERVE-1 (harbor#41): the wrapper's OWN denies ("floor is broken", not "a rule fired").
guard-lib is sourced lazily, on the deny path only: the allow path must not depend on it.
```

## bin/admission-hook.sh, lines 29-30 (before this edit)

```text
The wrapper has no subject, so it must not inherit one (harbor#350): floor_obs_digest hashes FLOOR_OBS_SUBJECT, and a
project's settings.json env could set it. Cleared, not validated; an empty subject already hashes as `-`.
```

## bin/admission-hook.sh, lines 44-44 (before this edit)

```text
The advisory early-exit records too: annotate-web can never signal through an exit code.
```

## bin/admission-hook.sh, lines 50-52 (before this edit)

```text
The rule token carries the wiring (guard basename, plus rc) only when that is safe: floor_log_decision rewrites any token
outside [a-z0-9-] or over 40 characters to `unclassified`, so every step falls back to the bare class.
No $(...) (a fork on every call) and not on no-jq/no-grep (one systemic outage must stay one row).
```

## bin/admission-hook.sh, lines 58-58 (before this edit)

```text
Degrade in order: guard+rc, guard alone, bare class.
```

## bin/admission-hook.sh, lines 68-70 (before this edit)

```text
Canary the interpreters the guards depend on: without jq every floor_field is empty and a guard allows everything.
Mirrors guard-lib's FLOOR_JQ resolution (absolute path first, then the allowlisted override) so the two cannot disagree;
the allowlist is duplicated on purpose (this wrapper must answer when guard-lib is unreadable), keep both copies in step (harbor#341).
```

## bin/admission-hook.sh, lines 80-81 (before this edit)

```text
stdin is consumed once, so read it here and hand it to the guard. harbor#810: /bin/cat first,
and an unread payload is a deny: read as empty, it let the guard allow anything.
```

## bin/admission-hook.sh, lines 84-85 (before this edit)

```text
Pass 14 E-3: floor_field is empty on bad JSON, so a payload jq rejects (a lone \uD83D escape) made
every guard allow. Nothing a guard could read is nothing it vetted.
```

## bin/admission-hook.sh, lines 90-92 (before this edit)

```text
The guard's stderr goes to a mktemp file: a fixed /tmp name is refused inside the confinement (only $TMPDIR is
writable there, harbor#555), and the guard then never ran. /tmp is the fallback, so a repo's TMPDIR cannot stop it.
/usr/bin first, as /bin/cat: a stripped PATH must not deny (B9).
```

## bin/admission-hook.sh, lines 99-101 (before this edit)

```text
A builtin printf (bash 3.2 as sh) whose blocked write a signal interrupts exits 1 with this text
and no verdict. The guard is pure, so re-running it is safe: at most twice, ONLY for that text on
a code other than 0/2, and the retry's verdict is the verdict. Any other exit keeps the deny below.
```

## bin/admission-hook.sh, lines 113-114 (before this edit)

```text
harbor#810: a fork or descriptor that failed inside a rule reads as "no match", so an allow that
carries one on stderr judged nothing. It is refused like a guard that never reached a verdict.
```
