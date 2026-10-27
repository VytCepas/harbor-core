---
name: test-strength
description: Prove a load-bearing test can actually fail, and that it fails for the right reason. Break the thing it guards, watch it go red, restore — then check it stays green on a valid-but-unusual input, because red on a mutant proves discrimination, not correctness. USE WHEN a suite is written or changed, a guard is trusted, a gate reports zero, or a green result is about to be cited as evidence. NOT FOR reviewing a diff for defects (audit-review-fanout), or running a suite to see it pass (`bin/suite-run.sh`).
disable-model-invocation: true
---

# test-strength — make green mean something

> **Path root:** `~/port/harbor` — every `./`-prefixed path below resolves there, not
> against the directory this skill is installed into. Paths with no `./` ship
> beside this file. Checked by `bin/reference-check.sh` REF-9 where the skill is
> READ; the `../../` form this replaced was green in the repo and dead from
> `~/.claude/skills/test-strength/` (harbor#462) — this skill's own pointer to
> the prove-targets contract handed the reader nothing.

CONSTITUTION.md §№2 rule 10 says a test that cannot fail is worse than no test.
This is the procedure that discharges it, and the reason it exists as a file is
that the rule had no mechanism: measured 2026-08-27, **2 of 44 `bin/*-test.sh`
suites plant a violation at all**, and nothing distinguishes a suite that has
been checked from one that has not.

**Invoked-only, deliberately.** The always-on surface is over its ceiling; a
resident description would be paid in every session to be useful in a few. Reach
for it by name, or from `skills/README.md`.

## The three checks, and only the first is the famous one

A suite that passes all three discriminates. A suite that passes only the first
may be matching far too much and still going red on every mutant.

**1 · It goes red on a planted violation.** Break the exact thing the test claims
to guard — flip a comparison, drop a guard clause, return a wrong constant,
widen a bound. Run it. It **must** fail. If it passes, the assertion is vacuous:
fix the assertion, never the code. Restore, confirm green.

**2 · It stays green on a valid-but-unusual input.** The odd-shaped legitimate
case: the 48-character label against a 48-character cap, the quoted string, the
diacritic, the empty-but-lawful list. This is the check a mutant sweep can never
generate, because mutants are derived from the thing under test — so an
over-broad rule that refuses everything passes check 1 perfectly and fails here.
CONSTITUTION.md §№2 rule 11 is the consequence: a rule that blocks ordinary work
gets switched off, and a switched-off guard protects nothing.

**3 · A gate that reports ZERO gets an *eligible* planted violation.** A zero is
two different claims — *the system is clean* and *the harness looked at nothing*
— and they are indistinguishable from the outside. Plant one violation the gate
is genuinely in scope to find, and watch the count go to one. Until it does, the
zero is the harness's, not the system's.

## The mechanism

A rule with no mechanism is a wish, and until 2026-08-30 this file was one.
`bin/prove.sh` is the mechanism: it mutates a copy of the artefact a gate
guards, runs the gate, and reports every mutant the gate did not notice.

    sh skills/test-strength/bin/prove.sh --list        what is declared
    sh skills/test-strength/bin/prove.sh <target>      measure one gate
    sh skills/test-strength/bin/prove.sh --self-test   prove the engine goes red

It discharges check 1 by construction (a survivor is a mutant that lived),
check 2 by refusing to score a target that declares no valid-but-unusual
control, and check 3 by reporting every empty class with a reason rather than a
zero. The declaration format is `./CONTRACTS/prove-targets.md`;
lint **C6** keeps the declarations gate-shaped between runs.

## Bound both sides of every threshold

A cap, a floor, a window, a count: test the value that must pass **and** the
value that must fail. A one-sided test on a `< 5` floor stays green against a
floor of `0` (refuses nothing) or `999` (refuses everything). Both are total
failures of the thing being guarded and both read as coverage.

## Where the check goes once it passes

**Into the suite, not into a commit message.** A hand-run mutation is evidence
that expires the moment the session ends; the next reader cannot tell a checked
suite from an unchecked one, which is exactly the state 42 of Harbor's suites are
in. Where the mutation can be scripted, script it. Where it cannot, say in the
suite's own header what was flipped and what went red — a comment naming the
mutation is recoverable evidence, and prose in a PR body is not.

## Coverage is per-case, not per-run

A sweep faithful in every row can still be blind: sixteen rows that all share one
provider prefix exercise one path sixteen times. Enumerate the dimensions the
input actually varies on and check that more than one value of each appears. The
variants that **differ** are the ones nobody asks for unless they are written
down.

## Gotchas measured on this box

- **`grep` here is `ugrep`**, carrying `-I --ignore-files`: it skips binary and
  gitignored files silently. Never rest a **negative** assertion on it — "the
  mutant left no trace" may mean grep declined to look. Build file lists with
  `find`.
- **A stale `__pycache__` keeps a killed mutant alive.** A same-length mutant
  written and restored inside the same second can keep loading from a `.pyc`, so
  the run measures the original while reporting on the mutant. Clear the cache
  between rounds.
- **`timeout` and `gtimeout` do not exist here.** A mutation loop that hangs
  hangs forever; bound it in the harness itself.
- **Restore is not optional and not automatic.** Copy the target aside, or mutate
  a copy and point the suite at it — a mutation left in place is a live defect
  wearing a test's clothes.

## Not this

- **Not a coverage number.** Executing a line is not asserting on it; a suite can
  reach every line and catch nothing.
- **Not the whole suite at once.** This is expensive. Reach for it on the tests
  whose green is about to be *cited* — a guard, a contract, a parser, an
  invariant — not on every assertion.
- **Not a forced green.** An equivalent mutant, an unreachable branch, or a
  defensive check the types already guarantee are all legitimate survivors. Say
  which ones you did not kill and why. Contorting a test until it asserts the
  mutant's own behaviour is worse than the hole it was hiding.

## Provenance

Re-authored for Harbor from `project-init`'s `verify-test-strength`
(L3, `plugins/project-init-workflow/`), read 2026-08-28. **Not a copy and not a
move:** `CONTRACTS/box-profile.md` makes the box profile the only up-pointing
edge, so an L0 session may not depend on a Yard plugin — the idea comes up, the
file does not. What changed in the re-authoring: the upstream leads with a
Python `mutmut` runner and treats the manual loop as a fallback, which inverts
for a POSIX-`sh` estate where the manual loop is the only path; and checks 2 and
3 above are Harbor's, from
`./DOCTRINE/verification-expanded.md`.
