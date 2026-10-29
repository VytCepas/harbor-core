# Reconcile — one `--status` for every drift check

**Seam:** L0 Helm check → the console, the batch report and the operator. **Status: harbor#1031 PR 1 —
the contract, its test and two adopters, [`memory-route.sh`](../bin/memory-route.sh) and
[`drift-reference-check.sh`](../bin/drift-reference-check.sh), are implemented. The remaining adopters, the
auto-remediation allowlist and the consumers are PR 2 and later (the last section).**

A drift check compares a desired state with an observed one. Harbor has many, and each used to answer in
its own words. This is the controller pattern from Kubernetes (spec, status, reconcile) applied as an
interface and not a daemon: every drift check answers `<check> --status` with the **same rows**, so a reader
(the console, the batch report, a person) needs one parser, and the report is **the delta and the ages, not
the census** (CONSTITUTION, "a finding has a destination").

It is not the finding ledger's `lint-findings.sh reconcile`, which ingests the receipts the checks leave
([finding.md](./finding.md)). A check's receipt says *that* it ran and what was red; `--status` says *which
rows* are off, by how much, and for how long.

## The interface

`<check> --status` runs the check's own judgement and prints the records below on **stdout**. Anything else
the check says (its log lines, a warning) goes to stderr, so stdout stays data. It **only reports**: it does
not repair, it refuses `--apply` where the check has one (exit 2), and the only files it writes are the
check's own receipt (if it writes one) and the first-seen state below. Its exit code is the plain run's.

Where the check takes a target (`--dir`, `--live`, a config dir), `--status` takes the same one.

## Records

Tab-separated, one record per line, in this order: the header, the drifted rows, the cleared rows, then
**exactly one** closing record.

| Record | Fields | Meaning |
|---|---|---|
| `reconcile` | `1`, `<check-id>` | The header and the contract version. `<check-id>` is the check's receipt id (`controls.tsv` `emitted`) |
| `new` | `<key>`, `<desired>`, `<observed>`, `<delta>`, `0` | A row that is not at its desired state, **first seen on this run** |
| `standing` | `<key>`, `<desired>`, `<observed>`, `<delta>`, `<age>` | The same, seen on an earlier run. `<age>` is the seconds since it was first seen; `-` only when the first-seen state cannot be kept (see below) |
| `cleared` | `<key>` | A row an earlier run listed that this one does not: it converged (or is no longer examined). Printed once |
| `summary` | `<examined>`, `<drifted>`, `<cleared>` | Closes a run that judged. `<drifted>` is the number of `new` plus `standing` rows, `<cleared>` the number of `cleared` rows |
| `unchecked` | `<reason>` | Closes a run that **could not judge**. There are no rows before it |

- **`<key>` is a stable id** (a repo label, a rule and a subject), never a count or a date, which would make
  the same row look new every run. It is unique within a report: where one item is found more than once (a
  script wired under two matchers is reported by each wiring), the helper lists the first and counts it once,
  so an adopter does not dedupe by hand and a reader never sees a key twice.
- **`<desired>`** is what the row should be, **`<observed>`** what it is, **`<delta>`** what would make them
  equal, each in the check's own words and each one line. A tab or a line break inside a field is replaced
  by a space. `-` stands for an empty field.
- **Only drifted rows are listed.** A row at its desired state is counted in `<examined>` and printed nowhere.
  A report whose `summary` says `0` examined says so; whether that is green or `unchecked` is the check's own
  plain-mode verdict, and `--status` keeps it.

## Exit codes (D-29)

| Exit | Closing record | Meaning |
|---|---|---|
| 0 | `summary`, `<drifted>` 0 | Green: every examined row is at its desired state |
| 1 | `summary`, `<drifted>` above 0 | Red: at least one row is not |
| 2 | none (stdout is empty) | Usage: a flag the check does not take, or `--status` with a flag it refuses (`--apply`, `--json`) |
| 3 | `unchecked` | It could not judge (no registry, no jq, a store it cannot read). **Never a green**, and the first-seen state is left alone |

The exit code and the closing record must agree, and `<drifted>` must equal the rows printed: the contract
test reads all three. Where a check's plain mode predates D-29 and exits something else for "could not
judge" (`drift-reference-check.sh` exits 1 with no jq), `--status` exits 3.

## First-seen state

`<config dir>/cache/reconcile/<check-id>.tsv`, one `key<TAB>epoch` line per drifted row, written
atomically by a run that **judged** (`summary`) and untouched by one that did not (`unchecked`). That is
what makes the three promises:

1. **A second run with nothing changed prints no `new` row.** Every row it lists is `standing`, with an age.
2. **A standing row shows its age**, counted from the run that first saw it, across any number of runs.
3. **A blind run does not reset the ages.** A check that cannot look leaves the state as it was, so the
   run after it still knows how long each row has been off.

A state directory that cannot be written is said on stderr and is not an error of the check: the rows are
printed as `standing` with age `-`, and the exit code is the verdict's. A config dir that does not exist is
not made for this.

## Writing an adopter

`bin/library-log.sh` carries the helper, so no check re-implements the state or the format:

```sh
LOG_FD=2                                     # stdout is data
. "$HERE/library-log.sh"; log_init my-check
status_init my-check "$CFG" || exit 3        # the header; $CFG is the config dir the state lives under
status_ok 12                                 # twelve rows at their desired state: counted, not printed
status_drift "$key" "$want" "$have" "$fix"   # one that is not
status_end; exit $?                          # `cleared` rows, the summary, the state saved; 0 or 1
# a run that cannot judge:  status_unjudged "no registry, so nothing was judged"; exit 3
```

An adopter is a check that answers `--status`; adopting is: the helper above, the exit codes above, and a
driver in the contract test (next section). `--status` on a check is this interface, so a check does not use
the flag for anything else.

## Who adopts — derived, never listed

An adopter is a check row of [`standards/naming/controls.tsv`](../standards/naming/controls.tsv) (`type`
`check`) whose script, `bin/<emitted>.sh`, answers `--status`: it calls `status_init`, or takes the flag.
The derivation runs both ways, so it is neither a list nor a marker someone has to remember: a script that
calls `status_init` and has no check row naming it is red too.

It is not an `owner` cell. `controls.tsv` has no control-kind column yet (#950 PR 2), and `owner` is the one
cell `bin/standard-catalog.sh` places a file through: a file is placed by the owner of the controls whose
engine it is, and where those rows disagree it is not placed. The check rows share one engine
(`awk -F'\t' '$3 == "check" { print $4 }' standards/naming/controls.tsv | sort | uniq -c`), so giving two of them
another owner took `docs/reference/checks.md` out of the `check` family in the catalog and the context map. The test asserts
that check rows of one engine file share one owner.

`sh tests/drift/reconcile/contract.test.sh` iterates that derivation and, for each adopter:

- requires a driver in the test that can put it in the green, drifted, fixed and blind
  states (a new adopter without one is red, so adopting cannot skip the proof);
- reads each report against the table above: the header, the field counts, the closing record, the exit
  code, the unique keys, `new` only on a first sighting;
- runs it twice with nothing changed and requires the second to add no `new` row;
- requires that a blind run exits 3 and leaves the ages alone, and that a bad flag exits 2 with nothing on stdout;
- requires that the run changed nothing outside `cache/`.

A fixture check that answers `--status` and does not conform goes red; a conforming one, a script that only
mentions `status_init` in a comment or a string, a lint rule and a check that does not answer `--status` stay
green. The `drift.*` lint rules (`awk -F'\t' '$3 == "lint" && $10 == "drift"' standards/naming/controls.tsv`) are
judged inside `bin/lint-conventions.sh`, which has no `--status`; they are not adopters in PR 1.

## Not in this contract yet

- **The auto-remediation allowlist** (#1031 item 4): a reconciler that repairs outside the list is refused.
  Nothing here repairs, so PR 1 has nothing to refuse.
- **The consumers** (#1031 item 5): the console (#737) and the batch report (#1028) reading `--status` through
  one parser. They land when the adopters they read do.
- **The remaining adopters**, including the `--check` modes of #996, #1026 and #1027. Each adopts by the
  section above.
