# CONTRACT — a finding: its key, its digest, its age, and a person's disposition

`schema_version: 1` · **written 2026-09-22 (harbor#590); the lint tier and its HEAL runner are
implemented (`bin/lint-findings.sh`, lint FL1 and FL2) and scheduled daily** (launchd
`com.harbor.lint.findings`, operator yes 2026-10-02) — its `docs/reference/checks.md` row is `lint.findings`. The check tier
is implemented too: a registered check's receipt under `~/.claude/cache/checks/` is filed as
`check/<id>` (harbor#896). The CI, review and floor tiers below are still the intent, and this line says so.

## Why this exists

Today a finding has two states: unread, and unread. `ADVISORY [X3] OVER by 21238
bytes` standing since 2026-09-06 and a line that appeared this morning render
identically, so the rational response to a block of advisories is to skim it. #578
measured one G1 advisory in seven to be false, and without a place to record that,
it is re-derived on every read.

A finding needs four things: an **id**, a **digest** of what it is about, an
**age**, and a **disposition** that only a person gives. The floor's ledger has the
first three for one layer (`bin/library-admission.sh`, `floor_log_decision`). Nothing has
the fourth.

## Decisions this contract rests on (operator, 2026-09-22)

| # | question | decided |
|---|---|---|
| 1 | where findings live and where a person dispositions them | **GitHub issues** on this repo: the store is the destination |
| 2 | what one finding is | **one per rule**, carrying the set of subjects it currently fires on |
| 3 | how the per-call guard ledger joins | **stays local**; the daily judge promotes aggregated candidates into findings |

Decision 1 follows a working implementation one layer down:
`projects-orchestrator`'s `heal_issues.py` (po#164, shipped 2026-09-19). It keeps
its dedup state in the issues themselves because *"a state file would lose track
after a reinstall, a new machine or a cleared `$XDG_STATE_HOME`, and then file
every issue again."* The same argument answers the question raised on #590, *who
watches the ledger?* A store that is also the destination has no separate
existence to go quiet in. What can still go quiet is the job that reconciles it,
and **Liveness** below covers that.

## The record

One open issue per finding, identified by a hidden marker in its body:

```
<!-- harbor:finding key=<key> digest=<16 hex> seen=<YYYY-MM-DD> schema=1 -->
```

| field | what it is | rule |
|---|---|---|
| `key` | `<tier>/<rule>` — `lint/drift.prod-policy-copy`, `check/drift.renew-check`, `ci/floor`, `floor/bash:redirect-into-cfg` | must match `^[a-z]+/[A-Za-z0-9._:-]+$`; a key that does not is **not filed**, and the reconcile says so, rather than filed under a mangled name |
| `digest` | 16 hex of `sha256` over the finding's **subject set** | see **The digest** |
| `seen` | the date of the last reconcile that ran this rule and found it still firing | written by the reconcile only |
| `schema` | this contract's `schema_version` | a reader refuses a marker with a higher major version |

The rule's id **joins** to where the rule is registered, and is never restated:
`lint/<id>` to `sh bin/lint-conventions.sh --list`, `check/<id>` to a `docs/reference/checks.md` row,
`ci/<job>` to a job in `governance.yml`. A key whose rule is not registered is refused
the same way as a malformed key. This keeps it from becoming a fifth register.
A renamed check keeps its history: a `standards/naming/renames.tsv` row of surface `check-id`
(`check:<old>` to `check:<new>`) is read until its `remove_by` date, so `check/<old>` is re-keyed to `check/<new>`
on the same issue, as a letter id is, and a receipt `<old>.json` counts as `<new>`'s until `<new>.json` exists.
`docs/reference/checks.md` registers what runs, `contracts/idle-tools.txt` what runs on nothing,
`contracts/unwatched.txt` what nothing watches, and this, what is currently firing.

A lint id is `<family>.<slug>` and permanent; the letter ids it replaced (`X5`) are deprecated,
never reused (D-19, harbor#957). A marker that still spells a letter joins under its successor
(`sh bin/lint-conventions.sh --ids`), so a rename orphans no finding: the reconcile reports it as
`would re-key`, and `--apply` rewrites the marker and the title on the same issue.

Every finding issue carries the label `finding`, which is how the reconcile lists
the store. A disposition adds one more: `finding:accepted`, `finding:superseded`, or
`finding:fixed` (the reconcile's). The title is `finding <key>: <the rule's title>`.
The label-filtered list can lag a just-created issue by seconds (harbor#893), so the reconcile
also reads the newest issue numbers one by one, in a single GraphQL call, and merges any finding
the list missed. Without that, a second `--apply` inside the lag would file it twice.

**Age** is the issue's `createdAt`, never a field. The **evidence** (the rule's
own message lines, capped at 4,000 characters) goes in the body below the marker
and is replaced on each reconcile. It is evidence, not identity.

## The digest

**The subject set is supplied by the emitter, never parsed from the message.** A
subject is a stable identifier: a repo-relative path, a skill or repo name, a rule
id. It is never a count, a size, a date or command text.

The trap is the one the floor recorded when it refused to hash `$FLOOR_IN`: hash
anything that moves on its own and recurrence counting is *"dead on arrival."*
`bin/deploy-runtime-install.sh is 321 lines of code` changes on every commit to that file, so
G1's subject is `bin/deploy-runtime-install.sh`, and `321` stays in the evidence.

```
digest = first 16 hex of sha256( the subjects, one per line, LC_ALL=C sort -u, newline-terminated )

printf '%s\n' <subjects…> | LC_ALL=C sort -u | shasum -a 256 | cut -c1-16
```

Worked, so an implementation has something to match. Each line was computed with
the command above:

| subjects | digest |
|---|---|
| `bin/deploy-runtime-install.sh` | `c492b52679fa45c2` |
| `labkit/.agents/hooks/prod_guard.py`, `zorbcorp/.agents/hooks/prod_guard.py` | `44ae053f90619d2c` |
| the same two, in the other order | `44ae053f90619d2c` (order does not matter) |

`sh bin/lint-findings.sh digest <subject>…` prints it, and `tests/lint/findings/findings.test.sh`
holds it to the three rows above.

### The lint emitter

Every `ADVISORY` line in `bin/lint-conventions.sh` is printed beside
`_adv <ID> <subject>…`, and **lint FL2 fails a line that is not**. With
`HARBOR_LINT_FINDINGS_OUT` set, each run appends `R <ID>` for every rule that ran, `A <ID>
<subject>` for every advisory subject and `V <ID> <subject>` for every violation, one
tab-separated line each. With it unset, which is every push and every CI run, `_adv` is
one `[ -z ]` and writes nothing.

- Where one rule reports several kinds of thing, the subject is `<kind>:<name>`, so
  `live-newer:<path>` and `repo-newer:<path>` are different subjects: a flip in
  direction re-opens an accepted finding, and a size or a count never does. X3 names the
  baseline verdict `context-budget.sh --check --kind` prints: `grew:`, `shrank:`,
  `instrument-changed:`, `no-baseline:`, `unreadable:` or `malformed:registries/context-baseline.tsv`
  (`verdict-unreadable:` when it printed none), so an instrument change is never filed as
  regrowth (harbor#585).
- A rule that could not look (`shellcheck-absent`, `no-base`, `no-dev-sandbox`) names
  that as its subject, so *"verified nothing"* is a finding of its own.
- A violation's subject is its rule id unless the rule names one (S6 names the path).
- A path under the checkout is repo-relative and one under `$HOME` starts `~/`, so a
  subject, and therefore a digest, is the same on every machine.

Unsalted, unlike the floor's digest. A finding is reconciled from whichever
machine runs the job, so its digest has to be the same everywhere. That is safe
only because the subjects are paths and ids, which is what the rule above
enforces. Floor-tier findings are the exception, and **Tiers** covers them.

## Dispositions

| state | who sets it | how | what the reconcile does next |
|---|---|---|---|
| `new` | the reconcile | files the issue | refreshes `seen` and the evidence while it keeps firing |
| `accepted` | **a person** | closes the issue as *not planned*, labels it `finding:accepted`, and comments the reason | leaves it closed while the rule fires with the **same digest**; on a **different digest**, files a **new** finding that links the accepted one |
| `superseded` | **a person** | closes it as *not planned*, labels it `finding:superseded`, and names what replaces it | treats a later recurrence as **new**: a recurrence is a **different digest**, which files a new finding linking this one. The same digest is the finding a person has already said is replaced, and stays closed |
| `fixed` | **the reconcile only** | closes it as *completed* and labels it `finding:fixed`, when the rule **ran on the published default branch** and did not fire | nothing; a recurrence is new |

**The person's command.** `sh bin/lint-findings.sh accept <key> --reason "<why>"` and
`sh bin/lint-findings.sh supersede <key> --by "<what replaces it>"` do all three steps
(close, label, comment). They refuse to run without a terminal on stdin and stdout,
refuse inside an agent session (`CLAUDECODE` is set), and ask the person to type the
key back. Doing the same three steps in GitHub's UI is equivalent, and the reconcile
reads the result either way. **The floor refuses the agent's hand route** (harbor#855):
inside an agent session, a `finding:accepted`, `finding:superseded` or `finding:fixed` label, in
any letter case, carried by `gh issue edit|create`, by a writing `gh api` call (judged per command
on the method gh will send, after percent-decoding), by a `gh alias set` whose expansion writes,
or by `gh label edit` is blocked. Reads such as `gh issue list --label …`, a GET, and prose naming
the label are not. Rows: `tests/admission/bash/exec.jsonl`, `fl855-*`. **Not covered.** A hand close
is not refused, because a finding closed without a disposition is re-filed by the next reconcile.
A label the argv never holds is not seen: one built in a variable, a substitution, `xargs` or a
brace expansion, one sent by `gh api --input` from a file, or one applied through GraphQL, whose
label mutations take ids rather than names. Each is a recorded `todo` row, and together they are
the floor's structural limit (docs/explanation/admission-baseline.md).

Three rules the table implies:

- **Nothing auto-accepts.** *"Encoding a fix is a human-gated act"*: the system
  observes and proposes, and a person dispositions. Accepting is one click in
  GitHub, with no code edit and no config change, and it survives every re-run.
  It is stored where the finding is.
- **An accepted finding whose digest changes reopens as new.** Otherwise
  acceptance is a mute button and §2.11 arrives by the back door. The first
  emitter has to show this happening before it closes: accept a finding, change a
  subject, and watch the new issue appear (No.2.10).
- **Closing needs evidence.** Only a reconcile that ran the rule may close as
  `fixed`. A rule that was skipped, or could not run, says nothing either way,
  and its finding stays open with its `seen` unchanged. An issue a person closes
  **without** a disposition label, while its rule still fires, is filed again
  once on the next reconcile, and the report says so.

## Lanes: what happens to a finding, declared by a person

Triage is three lanes, and **the lane is a property of the key, written in the table
below by a person**. The system never infers one: a model deciding at run time that a
finding is safe to auto-fix is the promotion `policy/constitution.md` forbids, *"Encoding a fix
is a human-gated act."* This table is also the enumeration the constitution's
self-repair exemption never had (*"the exemption is a list, not a judgement"*).

| lane | meaning | who decides |
|---|---|---|
| `HEAL` | a deterministic repair with no judgment in it. It runs without a person and writes what it repaired into the finding, so a repair that keeps coming back shows as a recurrence rather than as silence | a person, by adding a row |
| `PROPOSE` | the system drafts, a person approves. **The default**: every key with no row is PROPOSE | the constitution's default |
| `DECIDE` | no draftable answer, so the finding is a ticket for a person | a person, by adding a row |

- **Adding a row is the human-gated act.** It is an edit to this file, reviewed as a PR.
  Running a HEAL repair afterwards is mechanical. **Nothing outside the HEAL rows may
  repair on its own.**
- `subject` narrows a row: an exact subject, a `case` glob such as `bin/*`, or `*` for
  every subject of the key. A subject the row does not match is PROPOSE. T9's
  `generator-failed` is PROPOSE for exactly this reason: its own message says *do NOT
  run it to "fix" this*.
- `<subject>` in a repair is replaced with the subject being repaired.
- A repair that changes a tracked file lands as a **draft PR**, never as a push
  (the #591 decision record, po#162).
- The HEAL members are the four the operator approved on 2026-09-30, and `check/ci.lost-rerun` (operator yes 2026-10-06, harbor#675: re-run a job GitHub cancelled because no runner acquired it, at most once per job, never one that ran; it runs on `ci-runners.sh tick`'s own 5-minute schedule, off with `lost-rerun off` in `~/.claude/.harbor-ci-runners`). `sh bin/lint-findings.sh
  heal` runs them (harbor#856): a dry run prints the plan and runs nothing, and `--apply`,
  from the published default branch only, runs each matched repair in a throwaway worktree.
  The subject reaches the repair as `"$1"`, never spliced into the text, and a subject that
  is not a plain path or id is refused. A repair with no `<subject>` runs once per finding.
  Each repair is commented into its finding's issue, and a finding with no issue yet is
  not repaired. A repair that exits nonzero publishes nothing, is written into the finding
  with its output, and fails the run. It runs daily from launchd `com.harbor.lint.findings`
  (operator yes 2026-10-02), after a clean reconcile only. The check tier now emits (harbor#896),
  so `check/memory.route` is filed from its receipt; a check with no fresh receipt is reported as
  not visible, never as healthy.

**Lint FL1** reads the block and fails when there is not exactly one block or a lane
is declared anywhere else, a lane is not one of the three, a key is malformed or
declared twice, a key names a rule that is not registered (`lint/<id>` in `--list`; a deprecated letter id names its successor instead,
`check/<id>` in `docs/reference/checks.md`), a row cites no ticket, or a HEAL row names no repair or
a `bin/` script that does not exist.

<!-- lanes:begin -->
| lane | key | subject | repair | ticket |
|---|---|---|---|---|
| HEAL | `lint/skill.book-current` | `skills/skill-catalog/SKILL.md` | `sh bin/skill-catalog.sh` | #591 |
| HEAL | `check/memory.route` | `*` | `sh bin/memory-route.sh --live --apply` | #589 |
| HEAL | `lint/lint.exec-bit-kept` | `bin/*` | `chmod +x <subject>` | #574 |
| HEAL | `check/ci.lost-rerun` | `*` | `sh bin/ci-runners.sh rerun-lost --apply` | #675 |
<!-- lanes:end -->

`check/memory.route` is the worktree born blind (#589). memory-route is the check that sees it, and
its daily run is lint IJ6 inside the reconcile's own census, which writes the receipt the reconcile
then reads. IJ6 still prints its advisory, but records no subject, so the condition is one finding,
not two (harbor#896). A `stood-down` subject is never HEAL, whatever a row's glob says: the repair
cannot fix why a check could not look.

## Tiers and their emission budgets

The tiers fire at rates four orders of magnitude apart, so each gets its own
budget. Assuming one budget for all of them would be wrong.

| tier | fires | what it may do | store |
|---|---|---|---|
| `floor` | per tool call | **one local append, no fork on the allow path, no network.** Unchanged from `library-admission.sh` today | the local guard-decision JSONL (salted digest) |
| `floor`, promoted | daily, inside the `audit.triage` run | aggregates by the salted `h` and promotes only candidates above a threshold. The subject set is the salted digests, which are comparable **within one install only**, and the contract says so rather than pretending otherwise | issues |
| `lint` | per push, in the census | nothing new: the census still prints in full at push time | — |
| `lint`, reconciled | daily at most, against the published default branch — `sh bin/lint-findings.sh reconcile --apply`, daily from launchd `com.harbor.lint.findings` (operator yes 2026-10-02) | one `gh` read of the finding issues, plus at most one write per finding per day | issues |
| `check` | on each check's own `docs/reference/checks.md` schedule | the check writes one receipt per run, `~/.claude/cache/checks/<id>.json` = `{id, ran_at, status: green\|red\|stood-down, subjects}`, through log-lib's `log_receipt` (harbor#896). The reconcile reads it and never re-runs the check: red fires over the subjects, stood-down fires over `stood-down`, a receipt at most two days old is a run (so green closes as fixed), an older or missing one is not seen, and an id with no `docs/reference/checks.md` row is refused. Adopted by `memory.route` and `ci.main-tip-verdict` | issues |
| `ci` | per merge | a red verdict on a commit already on `main` (#586) | issues |
| `review` | per push to a PR | the reviewer (projects-orchestrator#312) writes the same marker in its PR review. The finding lives and dies with the PR, so it never files an issue | the PR's review thread |

**Only the published default branch is reported.** It is the same rule as
`heal_issues.py`, for the same reason: a result from a dirty tree, a local branch
or unpushed commits describes the operator's own work. Filing on it would publish
a failure `main` may not have, and closing on it would close a finding while
`main` is still red.

**The floor tier is blocked on #560.** Today `observe --fp`'s top rows are
floor-verify's own self-test shapes, about 1,000 rows above the first real
candidate. Promoting from that ledger before the self-test is excluded would
file the harness as a finding.

## The report is the delta and the ages, never the census

What `sh bin/lint-findings.sh reconcile` prints, here a second run over a real lint census
(2026-09-30, 90 rules) against a stub store, one week after the first:

```
findings: reconciled 2026-10-08 against owner/harbor at ef949eb (21 write(s)) — examined 90 rules, could not classify 0
  subjects changed:           lint/G1 (#7, now 2 subject(s))
                              lint/X3 (#15, now 1 subject(s))
  fixed:                      lint/X1 #12
  oldest open:                lint/C2, 7 day(s) (#1)
  open: 20 · accepted: 0 · superseded: 0 · not seen this run: 0
  store last written:         2026-10-01 (7 day(s) before this run)
```

The other lines it can print: `new since <date>:` (with each finding's lane),
`re-filed:` (an accepted or superseded finding whose digest changed, a recurrence of a
fixed one, or an issue closed without a disposition), and `could not classify:`.
`sh bin/lint-findings.sh report` reads the store alone: when it was last written, the oldest
open finding, and the open findings' ages in three buckets.

- **The denominator is stated** (#467): rules examined, and findings that could
  not be classified, such as a malformed key or an unregistered rule.
- **"Not seen" is a line of its own.** *"Nothing new since Tuesday"* and *"nothing
  has run since Tuesday"* must never render the same.
- **When the store was last written is always printed**, from the newest `seen=` on an
  open finding: *"no findings since Tuesday"* and *"nothing has written since Tuesday"*
  must not render the same either.
- The census stays where it is: the linter still prints every advisory at push
  time. The report is a second surface, not a replacement.

## Liveness: who watches the reconcile

The store cannot fall out of step with itself, but the job that writes it can
stop running. Two measures cover that:

- **The reconcile is a `docs/reference/checks.md` row**, with an id, a schedule, where it
  reports, and the command that disables it, registered before it first runs.
  It is red when no reconcile has completed within twice its interval.
- **Every open finding carries `seen=`**, so staleness shows on the store itself:
  an open finding whose `seen` is older than the last reconcile is one the job
  could not look at. That is never "fixed".

## Not in scope

- **Making an advisory blocking.** X3 is advisory on purpose: #183 measured all
  three justifications for its byte ceiling dead. The fix for an ignored
  advisory is a destination, not a gate.
- **Converging with the fleet's `heal-notify` marker.** Both use the same shape
  (`<scope>/<rule>` keys, the store as destination, evidence-gated closing), so
  a shared implementation is possible later. Merging them now would couple two
  repos before either tier ships.

## Falsifier

The ledger ships, and six weeks later every finding still sits at `new`, or the
delta report is itself unread. Then dispositioning costs more than skimming, and
the design was wrong about where the friction is. The report's own counts measure
this: if `accepted + fixed` does not move, the report is being ignored.
