---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/status-plan-generate.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/status-plan-generate.sh, lines 7-34 (before this edit)

```text
WHY THIS EXISTS. Harbor could state every COUNT about itself (docs/generated/status.md, lint
T1/T2) and could not state which of its own PLAN was built. Asked on
2026-08-21, three methods gave three answers: parsing docs/reports/platform-build-tickets.md
for "DONE" said B1-B6, L3, M5, M8, M9 were open; parsing each ticket's whole
block said the same; probing for the artifacts said every one of them exists.
The prose and the repo disagreed and the prose lost. That is harbor#117 —
"a workstream tracked only in prose … stale checkboxes" — and it means nobody,
including the tool writing this, could say when Harbor is finished.

THE MECHANISM IS THE TICKET'S OWN FALSIFIER, NOT A SECOND LIST. A registry
mapping ids to artifacts would be a copy of the plan and would drift against it
exactly the way the checkboxes did (T2). Instead each ticket declares, in its
own block, what would prove it shipped:

    - Evidence: bin/memory.sh
    - Evidence: cmd: sh bin/deploy-doctor.sh --json

and this tool EVALUATES that. A path is tested for existence; a `cmd:` is run
and judged by exit status. The plan stays one document.

UNDECLARED IS ITS OWN STATE, and that is the point rather than an omission. A
ticket with no Evidence line is neither done nor open — it is unfalsifiable,
and the count of those is the honest measure of how much of this plan is still
prose. It starts high. Driving it to zero is the work; hiding it behind a
default would reproduce the defect.

NOTHING HERE INFERS. "DONE" written in a ticket is deliberately NOT read: that
is the copy that was wrong. Only evidence counts.
```

## bin/status-plan-generate.sh, lines 69-72 (before this edit)

```text
── parse: one row per ticket, with its Evidence line if it has one ──────────
A ticket heading is `**<ID> · <title>** — effort <S|M|L>`; the id is what the
rest of the estate cites, so it is the key. `sane()` strips the pipes and
backticks that would break the emitted table.
```

## bin/status-plan-generate.sh, lines 81-82 (before this edit)

```text
VOID IS READ FROM THE HEADING, AND ONLY THE HEADING. See the note above the
state machine below for why this one word is trusted when "DONE" is not.
```

## bin/status-plan-generate.sh, lines 94-113 (before this edit)

```text
── VOID BEATS EVIDENCE, AND IS THE ONE THING READ FROM PROSE ────────────────
A cancelled ticket is not open and is not built, and evidence cannot tell you
which. M4 (SessionHarvester) and M12 (ProposalGC) were VOIDED by the owner on
2026-08-05 and this file reported both DONE, because each named a path that
happens to exist — `hooks/memory-harvest/memory-harvest.sh`, `bin/proposal.sh`. A reader saw
"shipped as specified"; what shipped was something adjacent, after the ticket
was closed. That is harbor#117's own defect, reappearing inside the tool built
to end it, so the check runs BEFORE any evidence is looked at.

WHY "VOID" IS TRUSTED WHEN "DONE" IS NOT — the distinction is the whole
design, not an exception to it. DONE is a claim about the world: an artifact
either exists or it does not, so prose asserting it is redundant at best and
wrong at worst, and we probe instead. VOID is a DECISION. No artifact's
presence or absence can prove a ticket was cancelled — an unbuilt void ticket
and an unbuilt open ticket leave identical traces on disk. The owner's written
decision is the only possible source, so reading it is not the defect; it is
the only correct move.

The discriminator is the HEADING LINE. A body that merely discusses voiding
something (M6's does, at length) must not silently cancel the ticket.
```

## bin/status-plan-generate.sh, lines 121-133 (before this edit)

```text
── HOST-DEPENDENT EVIDENCE IS NAMED, NEVER EVALUATED ───────────────────
docs/generated/plan.md is committed, so it must read the same on every machine — the same
rule docs/generated/status.md follows, and for the same reason: a generated file whose
content depends on the box reddens T1c on every clone until somebody
regenerates it. Caught on my own first pass: L2's falsifier was a path
under the live config dir, which would have made this file say DONE here
and OPEN on a fresh checkout.

So a ticket whose proof lives OUTSIDE this repo — another repository, or
machine state — declares `host:` and is reported rather than judged. It is
excluded from done and open because it is neither: it is a claim this file
cannot settle, and saying so is the honest form. `harbor status --observed`
is where machine truth belongs.
```

## bin/status-plan-generate.sh, lines 137-148 (before this edit)

```text
A COMMAND IS RUN, NOT PATTERN-MATCHED. Output is discarded and only
the exit status is read, so a check cannot pass by printing the
right words — the failure mode this whole file exists to stop.

KEEP IT STATIC AND CHEAP: `test -f`, `test -d`, a grep. NOT a suite
run. My first pass declared `cmd: sh bin/marker-test.sh` for four
tickets and the pre-commit hook rejected the result — that hook
lints the STAGED SNAPSHOT, where a suite resolves differently than
in the working tree, so docs/generated/plan.md came out one way here and another
way there and T1c called its own output stale. A falsifier that
depends on where it runs is not a falsifier. It also made this file
cost minutes; it now costs milliseconds.
```
