---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/admission-stop.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/admission-stop.sh, lines 3-7 (before this edit)

```text
SG (harbor#291) — the ONE Stop-event gate. docs/reference/coverage.md:86 read "Harbor has no
Stop gate at all", and docs/reference/coverage.md:38 read "№2 Verification is Harbor's longest
constitutional rule and has no mechanism, in a file that says 'a rule with no
mechanism is a wish'". This is that mechanism, narrowed to the part a shell
script can decide without judgement.
```

## bin/admission-stop.sh, lines 17-27 (before this edit)

```text
THE TRANSCRIPT IS THE EVIDENCE, NOT THE WORDING. That is upstream's whole
insight and docs/reference/coverage.md:250 records it: "VerificationGate.hook.ts grades
evidence FROM THE TRANSCRIPT, not from the message's wording, so rewording
never passes it." A gate that read the assistant's prose would be satisfied by
a rewrite, which is the opposite of №2.

WHY TEETH ARE DEFENSIBLE HERE AND WERE NOT FOR M5. FailureCapture declined to
block because "a failure worth healing" is a judgement and fails
policy/constitution.md's `deterministic` criterion. Neither rule below is a judgement:
what counts as evidence is defined by the repo (its own suite), and both
predicates are orderings over tool calls that either happened or did not.
```

## bin/admission-stop.sh, lines 29-45 (before this edit)

```text
`Stop` IS THE END OF A TURN, NOT THE END OF A SESSION, and everything about the
cadence below follows from that. Measured, from the binary's own event summaries
at 2.1.241:
    Stop:        "Right before Claude concludes its response"
    SessionEnd:  "When a session is ending"
The first cut of this gate was designed and documented against the wrong one of
those. The blocking mechanism was unaffected — the binary's operator-facing
string is "A hook blocked the turn from ending" — but the CADENCE was: at
every-turn firing, an unverified floor edit would refuse every subsequent turn
until a five-minute suite run, including the turn spent writing the assertion
for it. That is §2.11 in one paragraph, which is why the verdict block records
state and refuses ONCE per distinct defect.

SessionEnd was considered and is the wrong event even though its name fits: a
session that is already ending cannot be held open, and the reference's
`stop_hook_active` contract names Stop/SubagentStop only. A nudge nobody can act
on is a log line, not a gate.
```

## bin/admission-stop.sh, lines 47-55 (before this edit)

```text
THE HARNESS BOUNDS THE BLOCKING, not this script's care. Measured against the
binary at 2.1.241, all four facts from its embedded reference:
  • the payload carries `stop_hook_active`, and the documented pattern is
    "For Stop/SubagentStop hooks, check stop_hook_active in the input and
    return success while it's true" — honoured on the FIRST live line below
  • there is a block cap, raisable with CLAUDE_CODE_STOP_HOOK_BLOCK_CAP and
    counted as `tengu_stop_hook_block_count`
  • `decision:"block"` carries a `reason` that is "fed back to Claude"
  • the operator sees "A hook blocked the turn from ending"
```

## bin/admission-stop.sh, lines 57-66 (before this edit)

```text
FAIL OPEN ON EVERY ERROR PATH, and this is the one place the floor's usual
polarity is deliberately inverted. admission-integrity.sh is fail-CLOSED at
SessionStart and that is right there: a session that will not START costs one
restart. Here the blast radius of the opposite choice is worse than it first
looks — this hook runs at the end of EVERY turn, so a fail-closed internal error
refuses every turn for the rest of the session, and HARBOR_ADMISSION_DISABLE is read
at startup so it cannot rescue a refusal already under way. Missing jq,
unreadable transcript, bad JSON, any surprise ⇒ allow. The cost is a missed
nudge; that is the correct trade at this event, and it is why nothing else in
the floor may depend on this gate having fired.
```

## bin/admission-stop.sh, lines 68-76 (before this edit)

```text
WHAT IT DOES NOT CATCH, enumerated rather than left to be discovered. A floor
surface mutated through Bash (`sed -i`, a redirect, `cp`) inside a CHECKOUT is
invisible here: the tool route (Write/Edit/NotebookEdit) carries the path as a
field, and the Bash route carries it as text that no reliable rule separates
from a read of the same path — "is this command WRITING that file?" is the
question guard-bash withdrew a rule over after six false positives in pass 10.
Inside the CONFIG dir the floor already blocks that route, so the gap is
checkout-only. It is a real gap and pinned as a PASS in the suite, so the day
one of those starts blocking, this rule has stopped being path-scoped.
```

## bin/admission-stop.sh, lines 85-89 (before this edit)

```text
── THE LOOP GUARD, FIRST, BEFORE ANY OTHER TEST ────────────────────────────
Not merely early — first. Every line after this one can be skipped safely; this
one cannot, and putting it anywhere else invites a later edit to insert work
above it. `.stop_hook_active` is a JSON boolean, and floor_field's `// empty`
maps `false` to the empty string, so a bare string compare is the whole test.
```

## bin/admission-stop.sh, lines 95-106 (before this edit)

```text
IT DOES NOT STAND DOWN INSIDE A GOVERNED REPO (harbor#676). This line was
`floor_engine_stand_down && exit 0`, copied from the two work-log Stop hooks
(worklog-push.sh, memory-harvest.sh). Those are ENGINE hooks: standing down
means not acting, and no rule is withdrawn. This is a GATE for №2 Verification,
and harbor#581 decided the five constitutional rules never yield inside a
governed repo. contracts/marker.md lists every stand-down site and lint M2
holds that list to the code, so re-adding a stand-down here fails the lint
unless it is declared, with a ticket.

NO SESSION ID ⇒ ALLOW. The stand-down used to cover this too: with no id there
is nowhere to record the one-shot verdict, so the gate would refuse at every turn
end. The harness always sends session_id; fail open on the shape it never sends.
```

## bin/admission-stop.sh, lines 115-137 (before this edit)

```text
── THE EVENT STREAM ───────────────────────────────────────────────────────
One jq pass, order preserved, three record kinds, each carrying the tool_use id
where there is one. Measured at 93ms over an 1854-line transcript on this box,
which is why this is a single pass and not a grep-per-rule: a Stop hook that
costs a second is a Stop hook the operator turns off.

THE ID IS WHAT MAKES SG-2 A FACT RATHER THAN A HEURISTIC. A verdict line is
only believed when it came out of a command that RAN that suite. Without the
pairing, `cat` of an old build log — or of a commit message quoting one — reads
as a red suite this session ran, which is a false positive on a rule whose
whole job is to be believed.

The RES branch filters INSIDE jq. A tool result can be a whole file, and
emitting them all to be filtered in the shell was the first shape — it moved
megabytes through a pipe to keep a dozen lines.

`.text? // ""` and the array/scalar test on `.content`: both shapes occur, and
a missing `.text` on a non-text block must not abort the whole extraction.

BGT carries a background task's id (launched so, or moved there at the timeout),
and a Read of a task output file is a
CMD record, so a run in the background pairs through the later read of its own
output file (SG_PAIR below). A Read result's `N<tab>` line prefix is stripped.
```

## bin/admission-stop.sh, lines 261-264 (before this edit)

```text
── ONE SUITE-NAME KEY, SHARED BY SG-1 AND SG-2 (harbor#1176) ───────────────
A labelled summary `<label> <rc> <verdict>` puts its label before the suite name.
Both rules key verdicts by name, so both take the key through this one function,
prepended to each awk program: strip through the last ` <rc> `.
```

## bin/admission-stop.sh, lines 277-309 (before this edit)

```text
PATH-SCOPED, and the pattern is the floor's own file set: bin/admission-*.sh, bin/library-admission.sh,
bin/floor-*.sh, bin/admission-normalize.awk, and the old guard-*.sh names (harbor#961 W6). `bin/` is required, so a note called
guard-notes.sh in a docs dir is not a floor surface.

ONLY THE FULL SUITE COUNTS AS EVIDENCE. Since harbor#727 the floor suite is
tests/admission/baseline/baseline.test.sh plus every tests/admission/baseline/<part>.test.sh, so the
evidence is a verdict line from EVERY part, from a suite-invoking command, after
the edit: one part is a fraction, as a shard was (harbor#679). The pre-commit
smoke prints `baseline.test smoke: …`, another name, so it is refused like the
`--smoke` it replaced (№2.7 — "unavailable verifier means defer, never
substitute"): it is the right depth for a commit gate, not for "verified".

AFTER, not merely PRESENT. A run that happened BEFORE the edit verified the
code the edit replaced. Ordering is the predicate, and it is pinned in both
directions.

HARBOR'S floor surfaces, not every file with a floor-shaped NAME (harbor#676,
found by review on #684). Once this gate stopped standing down inside governed
repos, a project's own bin/guard-auth.sh matched the pattern, and the gate
demanded Harbor's floor-test for code that suite never touches — §2.11. So a
path counts only when the tree above its bin/ holds tests/admission/baseline/baseline.test.sh (a
Harbor checkout or worktree, wherever it lives: the tree whose suite would verify
the edit), or when it is the installed floor in the config dir. The parts owed
are that tree's; the config dir has none beside it, so it owes the cwd's, else
the main part alone. Every other MUT
record is dropped before the rule reads the stream; SG-2 reads the unfiltered one.

THE ROOT CHECK RUNS ONCE PER DISTINCT PATH, never once per stream line. The
first cut filtered the whole stream in a shell loop and cost +215 ms per turn
end on a 7,606-line transcript. So one awk pass lists the few floor-shaped
paths, the shell tests each once, and the rule reads the approved set through
ENVIRON: that is the only channel POSIX awk offers that does not
escape-process the value.
```

## bin/admission-stop.sh, lines 362-372 (before this edit)

```text
Keyed on the suite NAME, so a green normalize-test cannot vouch for a red
floor-test. Last verdict per name wins; a later green clears an earlier red,
which is what makes an ordinary fix-and-rerun cycle invisible to this rule.

`floor-test --smoke` and `floor-test` are DIFFERENT keys on purpose: they are
runs at different depths, and folding them would let the smoke clear a red full
run — №2.7 again, from the other side.

The id gate is the first clause: a verdict whose tool_use id belongs to no
suite-invoking command, nor to a read of a background suite's own output file
(SG_PAIR), is a verdict this session READ, not one it produced.
```

## bin/admission-stop.sh, lines 397-424 (before this edit)

```text
`Stop` is NOT the session-end event. The binary's own summary is "Right before
Claude concludes its response" — it fires at the end of EVERY turn, and
SessionEnd ("When a session is ending") is the other one and cannot block. The
first cut of this gate was written against the wrong premise and would have
blocked every turn until the suite ran.

WHY THAT WOULD HAVE BEEN A GUARD PEOPLE SWITCH OFF. Working on a guard is: edit
it, write the assertion, run the suite. floor-test is ~5 minutes. A gate that
refuses the turn after the edit AND the turn after the assertion is demanding
two five-minute runs to do one piece of work, and §2.11 says exactly what
happens next.

So: block ONCE per distinct unverified state. The key is a digest of what is
wrong — the offending path, and the red verdicts — so ignoring the nudge does
not trap the turn, while a NEW unverified edit is a new state and says so. The
nudge also lands at the earliest moment anything can be done about it, which is
strictly better than the session-end firing this was designed for.

THE COST, STATED: the model may proceed after one refusal. That is deliberate.
The alternative traps a session, and the harness's own cap would end the
refusal anyway — at which point the gate would have spent its credibility
instead of its one useful sentence.

Bounded chattiness: keyed on the path, so a session editing three floor files
without running the suite is refused three times, not once and not thirty.
Precision beats quiet here — each refusal names a different real defect.
SG-2 keys on the red suites' NAMES, not their counts, so a re-run that moves the counts is the
same state. Given up: a different new failure in that suite goes unflagged until it is green once.
```

## bin/admission-stop.sh, lines 431-434 (before this edit)

```text
DIGESTS AND A SESSION ID ONLY — never a path, never command text. This file
lives under the config dir §3 calls private, and a state record that carried
the path would put transcript content into a second place with its own
lifetime.
```

## bin/admission-stop.sh, lines 443-451 (before this edit)

```text
ONE block carrying BOTH findings. Two Stop blocks in a row would spend the
harness's cap on what is a single turn's worth of work, and the second refusal
would arrive after the model had already been told to fix the first.

THE ESCAPE HATCH NAMED HERE IS THE TRUE ONE. The PreToolUse guards print their
own narrow remedy since harbor#482, and the kill-switch would be a lie at this
event anyway: the variable is read when the session starts, so it cannot lift a
refusal already under way. What actually bounds this is the harness's own cap,
so that is what is said.
```

## bin/admission-stop.sh, lines 461-466 (before this edit)

```text
THE STATE IS RECORDED BEFORE THE VERDICT IS EMITTED, so a caller that reads
stdout and exits cannot leave this turn refused and the next one refused again
for the same reason. Best-effort: if the record cannot be written the gate still
blocks, which is the one place it is stricter than fail-open — the alternative
is a refusal it has no memory of, i.e. once per turn, i.e. the shape this whole
block exists to avoid. `|| :` keeps that failure from becoming a non-zero exit.
```

## bin/admission-stop.sh, lines 490-493 (before this edit)

```text
One ledger record PER RULE that fired, not a fused id. A compound token would
be a rule name that appears in no source file, and audit-triage.sh ranks by
rule token — a fused id would rank as its own never-before-seen rule every
time the pair coincided.
```

## bin/admission-stop.sh, lines 86-88 (before this edit)

```text
`gcloud auth login` is NOT P1: its browser flow ran to exit 0 under `!` (replay, 7419e469).
`cd ~/` under `!` was in the issue and is NOT a predicate: `! cd ~/port/… && …` ran
clean in the transcripts, and the trap it names is the model's own tool calls.
```
