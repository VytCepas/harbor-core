# Case law — the dated cases behind the constitution's rules

**On-demand.** [policy/constitution.md](../../policy/constitution.md) states each rule without a date,
a ticket, a path or a workload's name, and points here for the case it came from. This
file is where those specifics live, so the rules can stay true while the box changes
under them. A workload's own cases belong in that workload's pack, not here.

**Load when:** a rule's reason is not obvious, or you are about to argue with one.

Each section is named by the rule it backs; the constitution links to it by that name.

## Path root

The constitution is authored in the Harbor repo and deployed to the box's `CLAUDE.md`.
Ten `./`-prefixed paths were green at the source and dead at the only surface anyone
reads, because they resolved against the repo and not against the installed copy
(harbor#462). REF-5 in `bin/drift-reference-check.sh` checks the installed copy; lint K1
checks the repo.

## Deference inside a governed repo

A governed repo's own governance wins on workflow, conventions and tooling, and the
five constitutional rules never yield, inside a governed repo or out (harbor#581).

## Skill share

The sentence on hidden skills read *two thirds* until 2026-09-21, when the same count
came back **39 of 49**. A share written into prose drifted while it read perfectly, so
the constitution now carries the command that derives it, not the number.

## Memory routing

Measured 2026-09-16: every gate green, every rule correct, and **10 of 10 governed
repos loading no memory at all**, because the store is keyed to the working directory.
It was fixed the same day and it regrew: the fix does not survive worktree creation.
`sh bin/memory-route.sh` is the state today.

## Module census

The module-shape prose said *42 files* and *exactly one earns a split* until the
mechanism existed to contradict it. It was corrected on 2026-08-30 to *52 / 36 / NOT
ONE*, and by 2026-09-20 the tree had moved again and one file did meet both
(harbor#582). Two hand measurements, both wrong, are why the number left and the
command stayed.

## Hand over only what is refused

Stated by the operator on 2026-10-16. That day the operator deployed twice and
reported done while four PRs still waited on the approval buried in a long hand-over
list. Memory `do-everything-allowed-paste-only-necessary` is the long form.

## Tilde cd

Measured 2026-09-04 in a client repo: `cd ~/<repo> && grep … <relative path>` was
blocked, while the same command with an absolute `cd`, with `cd $HOME/<repo>`, or
with no `cd` and absolute operands all ran silently. Wrapping the `cd` in a script
does not help. The mechanism and the 2×2: memory `cd-relative-read-prompt-is-a-static-gate`.

## Glob abort

Measured 2026-09-03: a multi-path glob hid two kernel panics in
`/Library/Logs/DiagnosticReports/Retired/` for three tool calls, because the
user-level glob beside it matched nothing and zsh aborted the whole line. Mechanism:
memory `zsh-glob-abort-false-negative`.
