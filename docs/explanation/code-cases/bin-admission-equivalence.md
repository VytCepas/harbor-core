---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/admission-equivalence.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/admission-equivalence.sh, lines 19-76 (before this edit)

```text
WHY THIS EXISTS. harbor#264 wants the guards to stop forking ~74 greps per
fire, and the honest objection to every proposed fix is the same: "floor-test
still passes" is not evidence when floor-test is the thing being optimised. Its
1,022 assertions are the cases somebody thought of. An optimisation that skips
a rule breaks the cases nobody thought of, and by construction those are absent
from the suite.

So the corpus is not written, it is HARVESTED: this box holds thousands of real
Bash commands in its session transcripts. Those are commands that actually
occurred, including every shape the suite's author never imagined. A change that
is verdict-identical across that corpus AND green on floor-test has been tested
against reality as well as against intent.

KNOWN LIMIT: IT PROVES AN OPTIMISATION, NOT A FIX. Every payload in the corpus
was selected because the BASELINE blocks it, so this tool can see a candidate
that LOSES a block and is blind to one that ADDS one. Demonstrated, not
theorised: run against the one-flag fix for harbor#282 — which provably turns
`cat f | CRONTAB` from ALLOW into BLOCK — it reported `603 identical, 0
DIFFERENT`, because no corpus payload is in the set whose verdict the fix
changes.

That is the correct answer to the question this tool asks ("does the candidate
preserve every verdict I can observe?") and the wrong instrument for the question
a bypass fix asks ("does the candidate change the two verdicts I intend?"). The
second needs matched pairs — same command, one variable altered — and a green run
here must never be quoted as evidence for it.

KNOWN LIMIT: THE VERDICT IS SHAPE-BLIND, and it is blind because the guard is.
Rule ids follow `<rule>.<shape>` (lint F5), and a single rule name can carry more
than one shape — `crontab-install` exists twice in admission-bash.sh, as
`crontab-install.flat` at line 208 and `crontab-install.argv` at line 248 — but
the block MESSAGE prints only `bash:crontab-install`. So a refactor that moved a
decision from one shape to the other would be reported equivalent here.

That is the right granularity, not a gap to paper over: the operator sees one
message either way, so the product has not changed. It is recorded because it
cost an hour — floor-equiv-test's mutation neutralised the `.flat` arm, the
`.argv` arm still fired, the verdict was unchanged, and the suite read as "the
harness cannot fail" when in fact the harness was right and the mutation was
incomplete. Any future mutation testing against this file must neutralise EVERY
shape of a rule, which is what that suite now does.

THE VERDICT IS THE EXIT CODE *AND* THE RULE ID. Two guards that both block are
not equivalent if they block for different reasons: the rule id is what the
operator reads, what the ledger records, and what floor-verify asserts. A
refactor that silently moves a decision from `bash:pipe-to-shell` to
`bash:fetch-then-exec` has changed the product even though both exit 2.

NOTHING IS EXECUTED, EVER. Every payload is fed to a guard on stdin exactly as
the harness feeds it — the guard's whole job is to read JSON and decide. The
corpus is full of destructive commands precisely because those are the ones
worth pinning, and not one of them is run.

PRIVACY (CONSTITUTION §3). A harvested corpus contains real commands and real
absolute paths from this operator's sessions. It is written under build/, which
is gitignored, and it is never committed, printed in full, or sent anywhere.
fixtures/admission-corpus.jsonl is the small, hand-shaped, committable corpus so CI
has something deterministic; harvesting is a local superset.
```

## bin/admission-equivalence.sh, lines 86-87 (before this edit)

```text
The report is the run's log (contracts/logging.md, harbor#771); the verdict is the exit code, so stdout carries
no data.
```

## bin/admission-equivalence.sh, lines 94-117 (before this edit)

```text
IT DEFAULTS TO A SANDBOX, AND THE LIVE DIR IS THE DANGEROUS CHOICE (PR #281
review, P1). Every guard fire calls floor_log_decision, which appends to
$CLAUDE_CONFIG_DIR/MEMORY/OBSERVABILITY/<host>/guard-decisions.jsonl. A
two-tree run over 597 payloads therefore writes ~1,200 synthetic rows into the
ledger that feeds the statusline's block count, admission-observe-report.sh and
audit-triage.sh's recurrence counts — turning an observability record of real
tool calls into a record of a test harness. MEASURED, not predicted: building
this tool put 9,837 rows into the live ledger in three hours.

The sandbox suppresses it by the sink's own design rather than by a new switch:
floor_log_decision requires the sink FILE to already exist, so a fresh config
dir is simply blind. No guard changed, no flag added to the floor.

AND IT COSTS NOTHING, which is why this is the default rather than an option:
coverage measured 57 of 61 against the live dir and 57 of 61 against the
sandbox. The surface rules resolve against whatever config dir is given, and
since BOTH trees get the same one, equivalence is unaffected.

THE CONFIG DIR IS AN INPUT, NOT AN ASSUMPTION (found by floor-equiv-test).
It decides which paths count as floor surfaces, so a guard fired against a
different config dir can return a different rule — and the suite discovered
its mutation target under one dir while this harness compared under another,
so sections 3 and 6 mutated a rule the comparison never exercised and reported
"identical" over it. A test must also not read the live dir (lint F4).
```

## bin/admission-equivalence.sh, lines 130-133 (before this edit)

```text
COVERAGE WITHOUT A CANDIDATE. Half the fires, and it answers the question
you have BEFORE a refactor exists: which rules can this corpus even see?
Asking that first is what stops a 4-minute equivalence run from returning a
confident "identical" over a corpus that touches a third of the rules.
```

## bin/admission-equivalence.sh, lines 148-149 (before this edit)

```text
The sandbox is seeded with settings.json so teeth/deny reads resolve, and with
nothing else — in particular no MEMORY/OBSERVABILITY tree.
```

## bin/admission-equivalence.sh, lines 157-159 (before this edit)

```text
SAID OUT LOUD, because it is a real side effect on an audit record and the
operator may be doing it deliberately for a realistic surface comparison.
both sides resolved: a dir that does not exist is "" on both, and "" = "" warned falsely
```

## bin/admission-equivalence.sh, lines 162-162 (before this edit)

```text
Coverage is identical with the sandbox default (measured 57 of 61 both ways).
```

## bin/admission-equivalence.sh, lines 178-184 (before this edit)

```text
`@HOME@` IS RENDERED TO THIS RUNNER'S HOME (harbor#602). The committed corpus
names the config dir by absolute path, a spelling the `$HOME` and `~` rows do
not cover, and it used to name ONE operator's home: on any other machine
those rows named a stranger's path, fired nothing, and shrank the coverage
figure without an error. Text substitution, not a jq round-trip — a
re-serialised row can change its escapes, and the guards have a parse path
that does not use jq. ENVIRON, not `awk -v`, which would eat backslashes.
```

## bin/admission-equivalence.sh, lines 198-200 (before this edit)

```text
Every Bash command this box has issued, as a hook payload. `-c` keeps one
object per line; a command containing a newline stays one record because jq
emits it escaped.
```

## bin/admission-equivalence.sh, lines 208-215 (before this edit)

```text
THERE IS NO --from-ledger, AND THAT IS A MEASUREMENT, NOT AN OMISSION. The
obvious second source is ~/.claude/MEMORY/OBSERVABILITY/*/guard-decisions.jsonl
— 6,046 rows of decisions the installed guards really made. It cannot be a
replay corpus: the schema is `v,ts,g,d,r,s,t,h` and the command survives only as
`h`, a HASH. That is the right design for a ledger that records every session's
refusals (CONSTITUTION §3), and it means the ledger can tell you WHICH RULES
have ever fired but never WHAT to re-fire. A flag that silently yields zero rows
is worse than no flag, so there isn't one.
```

## bin/admission-equivalence.sh, lines 217-219 (before this edit)

```text
DEDUPE, because a corpus of 20,000 rows that is 300 distinct commands costs 60x
the wall clock for the same coverage — and at ~300ms a fire, that is the
difference between a usable gate and one nobody runs.
```

## bin/admission-equivalence.sh, lines 229-238 (before this edit)

```text
── one verdict ─────────────────────────────────────────────────────────────
Exit code plus the rule id parsed out of whatever the guard said. A guard that
blocks prints `HELM FLOOR [<rule>]`; one that decides prints JSON carrying a
permissionDecision. Both are part of the verdict, so both are captured.

ONE FIRE PER VERDICT, and the first cut of this function did two — once inside
`$(... || true)` to capture the output, which swallows the status, then again to
read the exit code. That doubled the cost of the whole harness, and a gate that
takes twice as long is a gate that gets run half as often. The payload goes to a
file so stdin, stdout and the status all come from a single invocation.
```

## bin/admission-equivalence.sh, lines 261-262 (before this edit)

```text
Which rule the BASELINE fired — the corpus's coverage is a property of the
tree being compared against, not of the candidate, which may have lost rules.
```

## bin/admission-equivalence.sh, lines 272-273 (before this edit)

```text
The command, truncated: a corpus row can be a multi-kilobyte heredoc, and
this output is read in a terminal.
```

## bin/admission-equivalence.sh, lines 279-290 (before this edit)

```text
── COVERAGE, BECAUSE "0 DIFFERENT" ALONE IS UNFALSIFIABLE ──────────────────
Measured while building this: deleting the `pipe-to-shell` block from a
candidate guard and replaying 60 harvested payloads reported 60 identical, 0
DIFFERENT, exit 0. The harness was working perfectly and proving nothing — the
corpus simply held no pipe-to-shell case. A gate that answers "equivalent"
after exercising three of sixty-nine rules is the shape CONSTITUTION §2.10
forbids, and it is worse than no gate because it carries an approval.

So the verdict is two numbers, never one: how many payloads agreed, and how
many RULES the corpus was able to disagree about. The rule universe is derived
from the guard's own source, so adding a rule lowers the reported coverage
instead of silently sitting outside it.
```

## bin/admission-equivalence.sh, lines 291-311 (before this edit)

```text
THE UNIVERSE IS PER-GUARD AND MAY NOT BE DERIVABLE AT ALL (PR #281 review, P2).
The first cut matched only single-line `floor_block <g> "<msg>" <id>.<shape>`,
which is guard-bash's spelling and not everyone's. Measured across the payload:

  admission-bash.sh      61 ids, all single-line   -> derivable
  admission-egress.sh    15 floor_block, 13 match  -> derivable but INCOMPLETE
  admission-self-edit.sh   1 floor_block,  0 match  -> not derivable
  admission-destroy.sh    0 floor_block            -> decides via permissionDecision
  admission-cloud.sh      0 floor_block            -> same

So `--guard admission-destroy.sh` reported `rules exercised: 1 of 0` and exited 0 —
a ratio that reads as coverage while hiding every untested rule. Two changes:
the ids are scraped by SHAPE SUFFIX anywhere in the file, which catches
multi-line calls; and a universe that cannot be derived, or that is smaller than
what was observed, is a REFUSAL rather than a number.
AND floor_log_decision LINES ARE EXCLUDED, or the denominator is wrong. The
widened scrape picked up `bash-clean.meta` — admission-bash.sh:1747, the ALLOW
observation written when no rule fired at all. It is shaped exactly like a rule
id and is not one, so coverage read `57 of 62` when the truth was 57 of 61. Wrong
in the safe direction, and still wrong: a denominator nobody can reproduce from
the source is the kind of number this repo generates rather than states.
```

## bin/admission-equivalence.sh, lines 319-324 (before this edit)

```text
`wc -l`, NOT `grep -c . || echo 0`. The first cut used the latter and it is the
fallback trap this repo has hit before: on an empty file `grep -c .` PRINTS 0 and
EXITS 1, so the `|| echo 0` fired as well and SEEN became the two-line string
"0\n0". Every downstream `[ "$SEEN" -eq 0 ]` then failed with "integer expression
expected" — and because those tests sit in the refusal branch, the harness sailed
past its own coverage gate and reported a clean pass. wc -l always exits 0.
```

## bin/admission-equivalence.sh, lines 329-330 (before this edit)

```text
It may decide via permissionDecision rather than floor_block (admission-cloud.sh, admission-destroy.sh), in which
case this harness cannot yet say what a corpus leaves untested for it.
```
