---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/alert-probe.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/alert-probe.sh, lines 7-55 (before this edit)

```text
THE CADENCE THIS OCCUPIES, AND WHY IT IS THE ONLY ONE LEFT. Harbor already
answers "what is true right now" three times, each at a different rhythm:
status-fleet-glyph.sh carries the numbers that MOVE, per statusline tick, over a
cache; session-verdicts.sh carries the standing verdicts that do NOT move,
once per session, loudly; status-dashboard-generate.sh renders everything on demand. All
three run only while the operator is already looking. A box with no session
open for three days is checked by nothing, and that is exactly the window in
which a work-log stops syncing or a floor stands down unnoticed. Pulse is the
unattended rhythm: launchd fires it, it evaluates, and alert-notify.sh speaks
only when a verdict CHANGES.

WRITES NOTHING. This file is a pure evaluator so it is safe to run at any
moment, from any session, in any state — the writer is alert-notify.sh, which
is the only thing that touches the state file. That split is what makes the
suite able to test every verdict without a sink or a cache.

IT NEVER FIRES A GUARD. admission-verify.sh answers "is the floor ON?" by firing
six known-blocked shapes, and every one of those appends a real block record
to the guard-decision ledger — the only real-traffic dataset Harbor has, and
the one observe-report --fp adjudicates false positives from. On a 300s
interval that is on the order of a thousand fabricated blocks a day. A probe
must not manufacture the evidence its own system learns from, so this reads
the wiring and refuses to call the reading a firing test: `floor` says WIRED,
never PROVEN. `harbor verify` remains the thing that proves it, by hand.

EVERY CHECK IS ANSWERABLE FROM THE LIVE CONFIG DIR ALONE. Nothing here reads
the repo. That is a constraint, not an omission: a probe that needs a checkout
to be present, current and unbroken cannot report on the box while the
checkout is any of those things. It costs four candidate checks, each of which
has a better home — live-bin lag and the repo counts are `status-gen
--observed` and the dashboard; document staleness is doc-freshness.sh; the full
twenty-row dependency table is deploy-doctor.sh. `deps` here asks the narrower
question those cannot: which tools does the INSTALLED surface need tonight.

UNKNOWN IS NOT OK, AND A ZERO IS UNMEASURED UNTIL THE RUN IS PROVEN. A source
that cannot be read yields `unknown`, never `ok`, and `inputs_seen` counts the
checks that got a real answer. DE-14 and DE-18 are both instances of the same
defect — a reporter that says zero when it never ran, and the clean number is
the one you want to believe.

THE WIRED-GUARD PREDICATE IS A COPY, AND THE SUITE KNOWS IT. status-generate.sh
owns the correct one: a whole-path-segment match on admission-hook.sh plus a
presence-and-nonempty check over the guard files. The tempting one-liner —
`test("guard-")` over the hook table — produced a false green on 2026-08-01,
because prod-guard-ambient.sh satisfies the substring on a box with none of
B2-B6. This file cannot call status-gen (that would be the repo dependency
above), so it copies the corrected predicate, and pulse-test.sh asserts the
two agree on the same fixture. A copy with a test that fails when it diverges
is a seam; a copy without one is the drift T2 exists to prevent.
```

## bin/alert-probe.sh, lines 61-63 (before this edit)

```text
Six times the refresher's own interval. Narrower than that and a machine that
slept through one wake-up reports a dead fleet job every morning, which is the
false positive that gets a channel muted (CONSTITUTION №2.11).
```

## bin/alert-probe.sh, lines 91-93 (before this edit)

```text
jq missing is not a reason to print nothing — it is the single dependency
whose absence made every guard exit 0 on 'rm -rf /' (B9). Say so in plain
text and exit non-zero rather than emitting malformed JSON.
```

## bin/alert-probe.sh, lines 110-113 (before this edit)

```text
ASK FOR THE ENTRY ONLY admission-deny.sh WRITES, not for a non-empty list. A
deny array is a list anyone may add to, so a single unrelated rule made this
read "B1 is live" on a box where every Harbor pattern had been removed.
status-generate.sh asks for the sentinel by name; so does this.
```

## bin/alert-probe.sh, lines 117-130 (before this edit)

```text
THE MATRIX, NOT THE BASENAME. admission-install.sh wires five distinct
(event, matcher, guard) triples, and a check that flattens them into "does
this guard appear anywhere" cannot see the failure the installer's own
comment records as pass 11's critical: admission-egress.sh carries dedicated
branches for mcp__*, Task/Agent, WebFetch/WebSearch and NotebookEdit, and
for months NONE of them could run because only the Bash|Write|Edit matcher
was ever wired. The suite missed it "because its wiring assertions only
checked the pairs the installer already wired". Same trap, one level up:
asking an easier question than the one the row claims to answer.

This list is a MIRROR of admission-install.sh and cannot read it — the probe
runs from the live config dir with no repo. pulse-test.sh extracts the
installer's own `add` lines and fails when the two disagree, which is what
keeps a mirror from becoming a fossil.
```

## bin/alert-probe.sh, lines 154-159 (before this edit)

```text
An EMPTY file parses as neither valid nor invalid to a naive check: jq over
zero inputs prints nothing and exits 0, so an earlier version of this code
fell through every integer test into its `ok` default and reported a healthy
floor on a completely unguarded box. Reachable, not theoretical -
deploy-harden.sh writes the live settings with a truncating in-place redirect,
so an interrupted apply leaves exactly that file.
```

## bin/alert-probe.sh, lines 163-167 (before this edit)

```text
ALL SEVEN FILES, not the five that are obviously guards. annotate-web.sh is
the B4 PostToolUse guard and admission-normalize.awk is the shared normaliser; a
live dir missing either is a partial install that reads as complete. This
list started as five, and the suite's agreement assertion against
status-generate.sh failed on its first run and named the two.
```

## bin/alert-probe.sh, lines 200-202 (before this edit)

```text
gitleaks is fail-CLOSED by design: without it worklog-push refuses the
commit, silently, on every Stop. A missing sink means this probe's own
sink is dead and a CRIT would be seen by nobody.
```

## bin/alert-probe.sh, lines 210-214 (before this edit)

```text
READS FOUR FIELDS AND NO OTHERS. The cache carries each repo's full memory
store inline, bodies and all — client names, escalation notes, whatever a
scaffolded repo happens to keep in .agents/memory. §3 makes that the operator's
business and nobody else's, so this reads descriptor.name, hooks and status
only, and a notification body never carries even those.
```

## bin/alert-probe.sh, lines 222-228 (before this edit)

```text
A CLOSED LAPTOP LOOKS EXACTLY LIKE A DEAD REFRESHER, in wall-clock. Both
jobs are launchd StartInterval jobs on the same machine, so if OUR last
run is also older than the window, nothing was running and the stale
cache says nothing about the refresher. Warning here would fire a false
WARN on the first probe after every sleep, and a false RECOVERED five
minutes later — a flap on a channel whose whole value is that it only
speaks when something changed. The notifier passes its previous ran_at.
```

## bin/alert-probe.sh, lines 241-246 (before this edit)

```text
ONLY the literal "missing" is a finding. The live snapshot carries a third
value — `-` — for a repo the orchestrator could not answer for, and the
first cut of this check counted it as broken: it reported three repos in
trouble when two were. A predicate of the form "anything that is not OK is
bad" turns every future field value into a false alarm, which is the defect
that gets a channel muted.
```

## bin/alert-probe.sh, lines 251-254 (before this edit)

```text
Drift is deliberately NOT a verdict. Most repos carry uncommitted work most
of the time; alerting on it would notify every day and teach the operator to
ignore the channel. Governance hooks missing is the fleet fact that is
actually broken rather than merely in progress.
```

## bin/alert-probe.sh, lines 256-258 (before this edit)

```text
An empty fleet is a valid fleet — a box with nothing scaffolded yet. The
unread-equals-total branch below would otherwise call 0 == 0 an unreadable
snapshot and report unknown forever on a clean machine.
```

## bin/alert-probe.sh, lines 272-290 (before this edit)

```text
THE RECEIPT HAD NO READER. bin/cu-doctor-run.sh writes cu-doctor-state.json and
its own header calls `ran_at` liveness — "a clean run and a run that never
happened both leave an empty log". Measured 2026-09-02: nothing on the box read
it. The repo, ~/.claude/bin and ~/.local/bin between them contained exactly one
file naming the path, and it was the writer. So the job could stop firing and
the file would sit there reading `green` forever, which is the same defect one
level up — a reporter that says zero when it never ran.

THREE STATES, NOT TWO, and `error` is the one that matters most: it means
cu doctor REFUSED and nothing was checked. A `green` receipt and an `error`
receipt are equally quiet on stdout; only this tells them apart unattended.

THE THRESHOLD IS 3x THE CADENCE, not the 6x check_fleet uses, and the
difference is deliberate. Fleet is a 300s job where one sleep cycle explains a
stale cache; this is a StartCalendarInterval job at 08:47 that launchd fires on
WAKE when the hour has passed, so a closed laptop still gets its run. Two
consecutive days with no run is not a laptop being shut, it is the job being
gone. Overridable, because a box on a different cadence should not have to
patch this file.
```

## bin/alert-probe.sh, lines 297-299 (before this edit)

```text
ran_at, NOT mtime, because that is the field the writer promises and the one
its header names. mtime moves if anything touches the file; ran_at only moves
when a run actually completed.
```

## bin/alert-probe.sh, lines 305-306 (before this edit)

```text
BSD date parses the Z form with -j -f; GNU wants -d. Digits or nothing, the
same contract mtime() above keeps, for the same reason.
```

## bin/alert-probe.sh, lines 313-316 (before this edit)

```text
STALENESS OUTRANKS THE VERDICT INSIDE. A receipt saying `green` from six
days ago is not evidence the board is clean; it is evidence nothing has
looked. Reporting the stored verdict here would be believing a number
that predates the question.
```

## bin/alert-probe.sh, lines 328-329 (before this edit)

```text
A status the writer does not currently emit is not ok. Every future value
arriving as a healthy green is the defect this whole file keeps finding.
```

## bin/alert-probe.sh, lines 335-337 (before this edit)

```text
Cleanliness is NOT the signal: the store is dirty by design (IDENTITY.md and
TELOS/ are untracked forever, outside the staging allowlist). Unpushed commits
are, because they only accumulate when the Stop push is failing.
```

## bin/alert-probe.sh, lines 343-344 (before this edit)

```text
session-verdicts.sh owns this one, loudly, once per session. Repeating it
as a WARN here would put the same fact on two channels.
```

## bin/alert-probe.sh, lines 354-366 (before this edit)

```text
AHEAD=0 HAS TWO MEANINGS AND ONE OF THEM IS BAD. Everything pushed, or
nothing was ever committed — which is what a frozen Stop hook produces: the
gitleaks gate is fail-closed, so a missing scanner makes worklog-push refuse
the commit, silently, on every session. The ahead-count then sits at 0
forever and the check reports a healthy log that has not moved in weeks.
Age is the only thing that separates the two. A week is wide enough that a
normal stretch of use never trips it and an actual freeze always does; the
wording carries both readings because an idle machine is the innocent one.
SCOPED TO THE RECORD PATHS. An unscoped `log -1` is refreshed by any commit
the store receives — idea commits and pushes IDEAS.md on its own — so a
work-log whose Stop hook has been frozen for months reads as fresh the
moment the operator files an idea. The staging allowlist in worklog-push.sh
is the authority on where a session record lands.
```

## bin/alert-probe.sh, lines 378-383 (before this edit)

```text
A NOT FOLLOWING line in checks.log scrolled out of the console's 40-line panel
within an hour, and launchd lists a job that exited 0 the same way as one that
is idle (harbor#1044 review r3 #4). So the follower leaves a receipt — status
following, down, off or stopped, with its pid and reason — and this row is the
surface: down is crit, and pulse-notify speaks on the change. No receipt is ok,
not unknown: the dispatcher is opt-in and ships inert, so most boxes have none.
```

## bin/alert-probe.sh, lines 409-411 (before this edit)

```text
ok < unknown < warn < crit. unknown outranks ok deliberately: "I could not
look" is worse news than "I looked and it was fine", and a run where every
source was unreadable must not render as a healthy zero.
```
