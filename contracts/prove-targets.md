# prove targets — the declaration format, and why each rule is in it

**Status:** proposed 2026-08-30 · ticket **R5** ([gates.md](./gates.md)) · the
grammar below is what `skills/test-strength/bin/prove.sh` parses and what lint
rule **C6** enforces statically.

## What a target is

> **A target is a (subject, checker) pair, plus the mutations that must be
> noticed and the legitimate inputs that must not be refused.**

`prove` mutates the subject on a copy, runs the checker, and records whether the
checker changed its verdict. A mutant the checker did not notice is a
**survivor**, and the survivor is the finding — a gate that stays green over a
broken artefact is an assertion that does not assert.

The engine never edits a tracked file. Mutants are built under a `mktemp`
workspace, the checker is pointed at that workspace, and a hash manifest of
`bin contracts fixtures hooks skills vendor` is compared before and after every
run. Read-only is asserted, not assumed.

**The manifest needs a working hasher, and its absence is exit 4 rather than a
silent pass.** `shasum` is used where it runs, `cksum` otherwise; both are probed
by *running* them, because the measured failure was a name that resolved and then
exited 127. With no hasher the manifest was empty before and after, two empties
compare equal, and the tripwire never fired — a zero meaning *looked at nothing*,
reading exactly like *clean*. If neither hasher runs, `prove` refuses to run at
all.

## One file per target

`skills/test-strength/targets/<name>.target`, with fixtures in a sibling
`<name>/` directory. A new target is a **new file**, never an edit to a shared
list — so there is no second list to drift and no merge conflict between two
people adding two targets.

## Grammar

Line-oriented. Field 1 of a non-indented line is the directive. A line beginning
with whitespace is a **continuation** of the directive above it, of the form
`key: value`. Blank lines and lines whose first non-blank character is `#` are
ignored.

**An unknown directive, an unknown continuation key, or an unknown mutator name
refuses the whole file — it never skips the line.** Skipping is how a
declaration silently loses the control it thought it had: the file still parses,
the run still prints a number, and nothing about the output looks wrong.

**Paths, one rule.** `repo:` resolves against the repo root; an absolute path
resolves to itself; anything else resolves against the directory holding the
`.target` file, so a target and its fixtures move together.

### Header directives — each exactly once unless noted

| directive | value |
|---|---|
| `target` | the name; **must equal the file's basename minus `.target`** |
| `subject-kind` | `posix-shell` or `markdown-contract` |
| `lane` | `fast` or `deep` — a cost class, never a tier |
| `cost` | integer, worst-case **seconds per checker run** |
| `sites` | optional; default site cap per mutator class. Default 8, ceiling 64 |
| `seed` | the pristine subject; the checker must accept it |
| `place` | absolute path under `$WORK` where seed / mutant / control is written |
| `checker-cmd` | the command line, `eval`'d with cwd at the repo root |
| `checker-env` | optional, repeatable; `VAR=VAL` prefixed to the checker |
| `green` | integer exit code meaning *accepted* |
| `red` | integer exit code meaning *refused* |
| `stage` | optional, repeatable; `mkdir`, `copy` or `copy-tree`, run before anything else |

`stage` takes a **fixed verb vocabulary and is never `eval`'d**, and its
destination must be under `$WORK`.

**A destination outside `$WORK` is `REFUSED` (5), checked before the budget
test; a `stage` that fails to *execute* is `COULD-NOT-LOOK` (4).** The
destination is a static property of the declaration — every variable it may name
is expanded from values known before a single byte is staged — so it is knowable
without running, and the repair is to fix the `stage` line. A `mkdir` or `cp`
that fails is the environment, and its repair is the box. Checking it ahead of
the budget means an authoring error is reported whatever the budget says.

### Body directives

```
mutate  <PREFIX>  <mutator-name> [<arg>]
        sites: <n>                       optional, overrides the target default

plant   <ID>  <recipe>                   a command line, eval'd; MUST create $MUTANT
        why:  <one line>                 MANDATORY

manual  <ID>  <one-line description>     unscriptable; reported UNPROVEN, never omitted

control <ID>  file <path>                placed at `place`; the checker must exit `green`
control <ID>  cmd  <command>             eval'd; must exit `green`; MUST reference $SUBJECT
        varies: <one word>               MANDATORY
        why:    <one line>               MANDATORY

scanner <name> <argv...>                 optional, repeatable
```

Exported into every `eval`'d recipe, checker and control: `ROOT WORK TDIR SEED
MUTANT SUBJECT TODAY TARGET`.

**`eval` is a deliberate exception to the constitution's no-interpolation rule.**
`.target` files are tracked, reviewed, in-repo, and in the same trust class as
`bin/*.sh`; an out-of-tree one needs `PROVE_ALLOW_EXTERNAL=1`. Recorded here
rather than discovered later.

## The rule that shapes everything else: no mutator takes a list

**Every mutator derives its sites from the seed at run time.** A mutation that
would need the contract restated in the declaration must be written as a
`plant`, which is honestly hand-written and whose staleness is visible in kind.

This is [doc-truth](../docs/explanation/doc-truth.md) applied to a gate's own
declaration: the file stores **pointers and reasons, never derived facts**. No
counts, no expected recall, no "last measured". A count written into a
declaration is a copy, and a copy drifts silently while reading correctly — and
a *recall* figure that drifts reads as a gate getting stronger.

The visible consequence: the denominator grows when the contract grows, with no
edit to any declaration. Add a tenth section to the map contract and
`section-delete` produces a tenth mutant on the next run.

## The mandatory control, and its five enforcement layers

A target with **zero controls is refused (exit 5)** before a single byte is
mutated. This is not a formality:

> An over-broad rule that refuses everything kills every mutant and scores 100 %
> recall. Check 1 cannot see it. Only a valid-but-unusual legitimate input can,
> and a mutant sweep can never generate one — mutants are derived from the thing
> under test.

1. **Parse-time refusal.** No control → exit 5, `no control declared`.
2. **Anti-tautology, and what counts as discountable is per `subject-kind`.** A
   `file` control byte-identical to the seed is refused: *"the seed wearing a
   control's name; it asserts nothing"*. So is one identical once the
   discountable lines are dropped — **blank lines for both kinds, and `#` lines
   for `posix-shell` only**. A `cmd` control whose text never names `$SUBJECT` is
   refused. This is how the rule actually dies in practice — a control file
   copied and never edited.

   **Why the `#` filter is kind-dependent.** In `posix-shell` a `#` line is a
   comment and a control varying only in comments really does assert nothing. In
   `markdown-contract` a `#` line is a **heading** — the most load-bearing
   structure in a contract and the subject of three mutators — so discounting
   headings refused a control differing by a whole added section, which is the
   most natural control there is for a structure gate, and blamed the author for
   a correct declaration. Measured 2026-08-30: a control adding one heading-only
   optional section, which the target's own checker *accepted* at exit 0, was
   refused here at exit 5. A false positive is a defect, and a guard that blocks
   ordinary work gets switched off.
3. **Mandatory `varies:` and `why:`** on every control, and **`why:` on every
   `plant`**, checked at parse time and again statically by lint C6. Until
   2026-08-30 the plant half was enforced only by C6, so the engine ran to a
   verdict on a file the linter refused — two enforcers of one contract
   disagreeing teaches a reader that whichever one they met first is noise.
4. **Ordering and a dedicated exit code.** Controls run after the baseline and
   the canary and **before the first mutant**. A red control aborts the target at
   **exit 3**, and the report then contains no recall figure at all. Printing
   100 % beside a broken guard is worse than printing nothing.
5. **One printf.** `_recall_block()` is the only function that emits a
   `GENERATED` or `DECLARED` line, and it emits the three `NOTE` lines in the
   same call — a recall figure with no control count above it is unreachable in
   the code, not merely discouraged.

**The residual, stated because it cannot be mechanised.** A control can be
unusual along an axis nobody cares about. No machine can judge relevance. C6
asserts that `varies:` and `why:` **exist**, never that they are **true** — they
are there so a reviewer can see the weakness instead of it being invisible. Do
not read a green C6 as evidence that a control is a good one.

## The canary

One generated mutant per run, applied before any declared one, whose kill is
guaranteed by construction: a shell subject becomes `exit 7`, a markdown subject
becomes zero bytes. A **surviving canary means the checker is not reading what
the engine mutates** — a moved artefact, a renamed subject, a flag that changed
what gets read — and it forces `COULD-NOT-LOOK`.

Without it that failure is silent in the worst possible direction: every mutant
survives, and the report reads as a weak gate rather than as a broken harness.

## Exit codes

| code | name | means | what to repair |
|---|---|---|---|
| 0 | `PROVEN` | every eligible mutant killed, canary killed, controls green | — |
| 1 | `SURVIVORS` | a mutant lived — an assertion that does not assert | **tighten** the checker |
| 2 | `USAGE` | bad flag or selector. The only code whose message goes to stderr | the command line |
| 3 | `CONTROL-RED` | a declared-legitimate input was refused | **loosen** the checker |
| 4 | `COULD-NOT-LOOK` | the run was vacuous. Never a pass, never a survivor | the **harness** |
| 5 | `REFUSED` | the declaration is not gate-shaped | the **declaration** |

`PARTIAL` is verdict text, always with exit 0, emitted instead of `PROVEN` for
any `--only` run. It replaces the *clean* verdict only: an `--only` run that
finds a survivor is still `SURVIVORS` (1).

### What `COULD-NOT-LOOK` covers

Every one of these is a run that measured less than it reported, so each is 4 —
never a pass, never a survivor:

| condition | why it is not a result |
|---|---|
| baseline not green, or the canary survived | the checker is not reading what is mutated |
| a checker exit that is neither `green` nor `red` | a crash is not a refusal |
| a run that exceeds `PROVE_RUN_TIMEOUT` | nobody watched it finish |
| an **inert** mutant — byte-identical to the seed | the recipe matched nothing, so the seed was measured |
| an **empty** mutant, generated or planted | an empty subject **is** the canary, so scoring it counts the canary twice |
| a `control` file that cannot be placed | the control was never exercised; the baseline ran twice |
| zero mutants applied, or the run counter not matching | the report describes runs that did not happen |
| `--require-scanners` with a declared scanner absent | no coverage was obtained |
| the target is over `PROVE_BUDGET` | it was not run; raise the budget or name it on the command line |
| neither `shasum` nor `cksum` runs | the read-only claim cannot be built |

**The empty-mutant rule is decided by emptiness, not by the recipe's exit
status**, because a legitimate `grep`/`sed` recipe can exit non-zero having
written a perfectly good mutant. The status is reported *in the reason* instead,
with the path to the recipe's own output, so a silently failing recipe names
itself. Measured 2026-08-30 before the rule existed: a plant whose `grep` matched
nothing reported `DECLARED 1/1 killed`, `VERDICT PROVEN`, exit 0.

**An unplaceable control is 4, not 3 and not 5.** Not `CONTROL-RED`, which would
point the repair at the checker and invite loosening a rule that is fine; not
`REFUSED`, because the declaration is correct. Nobody looked, so it says nobody
looked.

**1 and 3 are separate on purpose.** Their repairs point in opposite directions,
and a report that conflates them invites the fix that ends with a guard switched
off — which protects nothing.

A multi-target run exits `max()` of the per-target codes. The ordering is by how
corrosive the state is to trust, so a *could not look* cannot be averaged away
by nine clean targets.

## Two numbers that do not add

`GENERATED` measures the mechanical surface. `DECLARED` measures only what
somebody thought to write down. They are printed separately, they are never
summed, and **there is no combined recall key anywhere in `--json`** — not a
field left unset, but a field the schema does not have, so a dashboard cannot
render a merged number without someone inventing one in a reviewable file.

`prove` never writes `docs/generated/status.md`. A gate that scores itself on a dashboard is
the shape the constitution rules out.

## What a zero means

`--coverage` is a **census, not a score**, and prints no percentage. A checker
having a target is not a checker that discriminates; only a run says that.

`no-site` is reported with a reason, never as a bare zero, because a zero is two
different claims — *the seed has none of these* and *the scanner is broken* — and
they are indistinguishable from outside. That is the SKILL's check 3 pointed at
the engine itself.

## Vocabulary, and two live collisions avoided

`bin/admission-mutation-tier.sh` already owns *mutation tier* and means something else
entirely; *operator* means the human everywhere else in Harbor. So nothing in
this format, the engine, or its output says **tier**, **mutation tier**,
**mutant score**, or **operator** for a code artefact.
