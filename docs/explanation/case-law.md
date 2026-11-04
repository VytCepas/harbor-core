---
kind: explanation
owner: @VytCepas
status: unreviewed
---

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

## Operational rules — the long forms

Moved out of `policy/constitution.md` on 2026-11-01 (harbor#1392), when the
resident file was cut to 15 KB. The bolded rules stayed; the cases above keep
their own sections.

**Path root.** Two questions, two roots, one extractor: REF-5 and K1 share
`bin/doc-cited-paths.awk`.

**Language by layer, not by decree.** Harbor is deliberately tri-runtime. The
floor uses no Bun and no Python, because it must run under `/bin/sh` with BSD
`grep`. The trio is `project-init` and `projects-orchestrator`. Net-new work
picks by fit and says why.

**Tests and CI have one box-level guide.** Local suites and CI share one CPU
budget, agent identity limits what an agent may push or merge, and a local result
that flips between identical runs is the machine:
[docs/design/ci-tests-on-this-host.md](../design/ci-tests-on-this-host.md).

**Plan means stop.** "Make a plan" is a request to present and stop.

**Markdown for prompts and docs.** HTML only where markdown genuinely cannot
express it.

**A deliverable gets a folder.** Any document written for a human to read — an
HTML report, a draft, a brief, an export — gets one dated folder per deliverable,
so its source, charts and screenshots sit beside it. Never loose in `$HOME`,
`~/Desktop`, `~/Documents` or `~/Downloads`. Open it, then hand over the link: the
folder is where it LIVES, clickable is how it is DELIVERED.
`admission-deliverables.sh` denies a new loose document and names the path it
should have used.

**Hand over only what is refused.** Watching CI, fixing a red check, pushing,
opening the PR, the gate tools whose permission prompt is the operator's click,
and the live check after their step are yours. What goes to the operator is only
what something refused you (a GitHub approval, a CI re-run the App may not start,
a real-terminal or sudo step, a decision), each with the one clause saying why it
is theirs. A long hand-over hides the one step that blocks. Nothing enforces this
rule.

**Blank tool output.** Never batch a write or a dispatch against reads that have
not returned.

**Tilde cd.** `$HOME/…` works because the analyser does expand it. An unexpanded
tilde makes every *relative* path in the same compound unresolvable, and with any
`Read()` deny rule present the CLI stops and asks — for the whole command, in any
directory, whatever the tool.

**Glob abort.** `ls A/*.ips B/*.ips`, when `A` is empty, prints
`no matches found: A/*.ips` and runs NOTHING: `B` is never looked at, and the
empty output reads exactly like "there is nothing anywhere". `find <dirs> -name
'<pat>'` walks every directory it is given and is silent only when the thing is
genuinely absent. A tool whose silence means "I did not look" is the same class
as this box's `grep`.

**Never brief a delegate from unread files** — not recall, not a pending read.

**Degraded state.** The environment looks wrong when expected context is
missing, a hook misfires, or a guard behaves impossibly. Harbor has no repo
`CLAUDE.md` of its own: the constitution is Harbor's. A misfiring hook is an
observable condition, not a hypothetical: SessionStart and Stop hooks run every
session (`worklog-push.sh`).
