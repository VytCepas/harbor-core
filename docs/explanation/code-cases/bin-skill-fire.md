---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/skill-fire.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/skill-fire.sh, lines 8-51 (before this edit)

```text

WHY THIS EXISTS. Every argument about which skills to keep has been settled by
reading descriptions and guessing. Measured 2026-08-28, guessing was wrong in
both directions: 25 of 27 vendored skills had never been opened in 600
sessions, AND a skill that looked dead fired as the first tool call the moment
it was listed against a proportionate task. Neither fact was predictable from
the SKILL.md. So the roster is decided by running it.

THE MEASUREMENT IS EXOGENOUS (docs/explanation/verification-expanded.md). The input is
a real session's real tool calls, not this repo's opinion of what should have
happened. Nothing here scores an answer's quality — only whether the skill
fired — because quality is a judgement and `sh` cannot make one.

IT NEVER TOUCHES ~/.claude/skills. The candidate roster is copied into a
scratch project's `.claude/skills`, which Claude Code reads as a project-scoped
skill directory. That is also what makes `disable-model-invocation` testable
from both sides: the copy is rewritten with the flag stripped, so a skill can
be trialled as LISTED without the live box ever being modified. guard-selfedit
refuses a live-skills edit and it is right to; this is the route that does not
need one.

IT COSTS REAL MONEY AND REAL TIME, AND THE FIRST ESTIMATE HERE WAS WRONG BY
TWO ORDERS OF MAGNITUDE. This header said "~20s and ~$0.33 for a small case",
which was true of a small case and worthless as a planning number, because a
sweep worth running is made of PROPORTIONATE cases and those are what a skill
has to fire on. Measured 2026-08-28 over 17 proportionate cases against a
roster of 39: 98 minutes wall clock, 5.8 minutes a case, 699k output tokens
and ~32M of cache reads — on the order of $100, not $6. The estimate was
quoted twice while planning off it and under-priced the sweep both times.
So the DRY RUN now prints the measured per-case figures rather than a
reassuring sentence, because the plan output is where the decision is made and
a number nobody sees cannot inform it.

THE CONFOUND IS PRINTED, NEVER HIDDEN. A roster of one is an easier choice than
a roster of thirty, so a skill that fires alone may lose against its siblings.
The report always names the roster size, because a fire-rate without it is a
number nobody can compare.

CASES FILE FORMAT — tab-separated, `#` comments and blank lines skipped:
  <id><TAB><expected-skill-or-NONE><TAB><prompt>
The operator's own case files are private data: <private layer>/evals/skill-fire/ (harbor#1273).
`NONE` is a REQUIRED negative control, not an optional extra: a roster that
fires on everything is as useless as one that fires on nothing, and only a case
that must NOT fire can tell those apart (CONSTITUTION §No.2.10).
```

## bin/skill-fire.sh, lines 54-55 (before this edit)

```text
The per-case table and the score line on stdout are the report the suite and --json readers consume, so they
stay byte-identical; the log is on stderr (LOG_FD=2, contracts/logging.md, harbor#771).
```

## bin/skill-fire.sh, lines 92-101 (before this edit)

```text
THIS DOES NOT WRITE THE CONFIG DIR ITSELF, AND IT WRITES IT ANYWAY. The roster
copy goes to a scratch project under TMPDIR and ~/.claude/skills is never
touched — that much the header has always claimed and it is true. What the
first cut missed is the SESSIONS: every case is a real `claude -p`, and every
one of those lands a transcript in $CFG/projects/<slug>/. A ten-case sweep
therefore deposits ten sessions in the live store, which is the surface
memory-store-check.sh bounds and B8 pins. D2 keys on the write, not on the intent,
and it was right to flag this.
Paths are compared RESOLVED, never as strings: a trailing slash is a measured
bypass of the string form (context-injection-install.sh records it).
```

## bin/skill-fire.sh, lines 107-107 (before this edit)

```text
Each case is a real session and lands a transcript in $CFG/projects.
```

## bin/skill-fire.sh, lines 111-111 (before this edit)

```text
── the roster ──────────────────────────────────────────────────────────────
```

## bin/skill-fire.sh, lines 116-116 (before this edit)

```text
── the cases ───────────────────────────────────────────────────────────────
```

## bin/skill-fire.sh, lines 117-118 (before this edit)

```text
Read with `read -r` on a tab IFS rather than cut, so a prompt may contain
anything but a tab, including the quotes and apostrophes a real task carries.
```

## bin/skill-fire.sh, lines 127-128 (before this edit)

```text
A sweep with no negative control cannot tell a working roster from one that
fires on everything, so refuse rather than report a number that means nothing.
```

## bin/skill-fire.sh, lines 138-142 (before this edit)

```text
THE COST GOES IN THE PLAN, NOT IN A HEADER NOBODY OPENS. Derived from the
2026-08-28 sweep — 17 proportionate cases, 98 minutes, ~$100 — so it scales
with the case count the operator actually passed rather than reassuring them
with a small-case figure. Stated as an ORDER, not a precision: the real
driver is how proportionate the cases are, which no script can read.
```

## bin/skill-fire.sh, lines 149-149 (before this edit)

```text
── the sandbox project ─────────────────────────────────────────────────────
```

## bin/skill-fire.sh, lines 157-159 (before this edit)

```text
STRIP THE HIDE FLAG IN THE COPY, NEVER AT THE SOURCE. A hidden skill is
absent from the model's listing, so leaving the flag on would measure
"can the model invoke what it cannot see", whose answer is known and is no.
```

## bin/skill-fire.sh, lines 168-181 (before this edit)

```text
`</dev/null` IS THE WHOLE MEASUREMENT, AND ITS ABSENCE VOIDED A $100 SWEEP.
This loop is fed by `done < "$CASES"`, so without an explicit redirect the
case file IS this command's stdin — and `claude -p` appends what it finds
there to the prompt. Measured 2026-08-28: every one of the 17 sessions
received the entire fixture, header and all, which includes the `want`
column. The model was handed the answer key and the five named cases all
scored `ok`. Reproduced out of band: `claude -p "print any codeword" <f`
prints the file's codeword, `<`/dev/null` prints NONE.

THE LEAK IS SILENT AND IT READS AS SUCCESS. Nothing errored, the exit code
was 0, and a contaminated sweep scores BETTER than a clean one — which is
why this is a comment and not a one-word fix. tests/skill/fire/fire.test.sh stubs
`claude` and asserts stdin arrives empty, because that is the only evidence
that this line still does its job.
```

## bin/skill-fire.sh, lines 186-187 (before this edit)

```text
The transcript path is derived from the cwd, and the harness's own slug
rules are not ours to restate — find it by name instead of building it.
```

## bin/skill-fire.sh, lines 190-203 (before this edit)

```text
TWO WAYS TO REACH A SKILL, AND COUNTING ONE OF THEM INVERTED A RESULT.
Measured 2026-08-28 on the clean sweep: `red-team-big` scored MISS while
its session's fourth tool call was
`cat ~/.claude/skills/red-team/SKILL.md`, and `council-decision` scored
silent having read council's. Both HAD routed to the right skill — by
path, not by the Skill tool — and the report called them failures.

THE CAUSE IS THIS BOX'S OWN GOVERNANCE, which is why it is not an
oddity to wave away. The injected project pointer tells every session
"read its .claude/skills/ … do not conclude the capability is absent
because you cannot see it", and the hidden tier trains the same habit:
a hidden skill cannot be invoked, so reading its file is the ONLY route.
A roster measured only by Skill-tool calls therefore scores the box's
own doctrine as a failure to route.
```

## bin/skill-fire.sh, lines 208-211 (before this edit)

```text
The verdict counts EITHER as reaching the skill — a control that reads a
SKILL.md has not stayed quiet — while the report keeps them in separate
columns, because "invoked" and "consulted" are different claims and
collapsing them is how the first version got the answer wrong.
```

## bin/skill-fire.sh, lines 218-224 (before this edit)

```text
THREE EXPECTATION KINDS, AND `?` IS NOT A MISSING VALUE. A case can ask
"does X fire" (a name), "does anything fire" (NONE, the control), or
"WHAT fires" (`?`). The third has no right answer to score against: writing
a guess into the column and then scoring the run against it measures the
guess, not the roster, which is the same defect as inventing a case to
flatter a skill. `?` rows are reported and read by a human, and they do not
move ok/MISS/FALSE-FIRE either way.
```

## bin/skill-fire.sh, lines 233-235 (before this edit)

```text
BOTH ROUTES IN THE REPORT. `invoked` is the Skill tool; `read` is a session
that opened the SKILL.md instead. A single `fired` column hid the second and
turned two correct routings into a MISS and a silent case.
```

## bin/skill-fire.sh, lines 253-253 (before this edit)

```text
--json has always exited 0 whatever the scores; the exit code stays, and the summary still counts them.
```
