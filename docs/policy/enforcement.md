---
kind: generated-doc
owner: harbor#1028
status: generated
source: sh bin/policy-check.sh --gen enforcement
---
<!-- generated-by: sh bin/policy-check.sh --gen enforcement -->
# Enforcement matrix — generated, do not edit

Which moment each clause binds at, and in which mode (policy/enforcement.tsv x policy/clauses.tsv). `judgment` is a moment: counted, never hidden. Regenerate with `sh bin/policy-check.sh --gen enforcement`; `--check` fails on a hand edit.

## Pairs per moment and mode

| moment | shadow | warn | block |
|---|---|---|---|
| write | 0 | 2 | 2 |
| session | 0 | 1 | 0 |
| commit | 0 | 0 | 1 |
| pr | 0 | 3 | 5 |
| merge | 0 | 0 | 0 |
| schedule | 0 | 6 | 0 |
| deploy | 0 | 0 | 0 |

## Judgment share per strength

| strength | clauses | judgment only | share |
|---|---|---|---|
| constitutional | 29 | 24 | 82% |
| policy | 40 | 30 | 75% |

## Clause x moment

| clause | strength | write | session | commit | pr | merge | schedule | deploy | judgment |
|---|---|---|---|---|---|---|---|---|---|
| pre.1 | policy |  |  |  | block |  |  |  |  |
| pre.2 | policy |  |  |  |  |  |  |  | judgment |
| n1.1 | constitutional |  |  |  |  |  |  |  | judgment |
| n1.2 | constitutional |  |  |  |  |  |  |  | judgment |
| n1.3 | constitutional |  |  |  |  |  | warn |  |  |
| n1.4 | constitutional |  |  |  |  |  |  |  | judgment |
| n1.5 | constitutional |  |  |  |  |  |  |  | judgment |
| n2.1 | constitutional |  |  |  |  |  | warn |  |  |
| n2.2 | constitutional |  |  |  |  |  |  |  | judgment |
| n2.3 | constitutional |  |  |  |  |  |  |  | judgment |
| n2.4 | constitutional |  |  |  |  |  |  |  | judgment |
| n2.5 | constitutional |  |  |  |  |  |  |  | judgment |
| n2.6 | constitutional |  |  |  |  |  |  |  | judgment |
| n2.7 | constitutional |  |  |  |  |  |  |  | judgment |
| n2.8 | constitutional |  |  |  |  |  |  |  | judgment |
| n2.9 | constitutional |  |  |  |  |  |  |  | judgment |
| n2.10 | constitutional |  |  |  |  |  | warn |  |  |
| n2.11 | constitutional |  |  |  |  |  |  |  | judgment |
| n2.12 | constitutional |  |  |  |  |  |  |  | judgment |
| n3.1 | constitutional |  |  |  |  |  |  |  | judgment |
| n3.2 | constitutional |  |  |  |  |  |  |  | judgment |
| n3.3 | constitutional |  |  |  |  |  |  |  | judgment |
| n3.4 | constitutional |  |  |  |  |  |  |  | judgment |
| n3.5 | constitutional |  |  |  |  |  |  |  | judgment |
| n3.6 | constitutional |  |  |  |  |  |  |  | judgment |
| n4.1 | constitutional | warn | warn |  |  |  |  |  |  |
| n4.2 | constitutional | warn |  |  |  |  |  |  |  |
| n4.3 | constitutional |  |  |  |  |  |  |  | judgment |
| n4.4 | constitutional |  |  |  |  |  |  |  | judgment |
| n5.1 | constitutional |  |  |  |  |  |  |  | judgment |
| n5.2 | constitutional |  |  |  |  |  |  |  | judgment |
| crit.1 | policy |  |  |  |  |  |  |  | judgment |
| crit.2 | policy |  |  |  |  |  |  |  | judgment |
| crit.3 | policy |  |  |  |  |  |  |  | judgment |
| crit.4 | policy |  |  |  |  |  |  |  | judgment |
| crit.5 | policy |  |  |  |  |  |  |  | judgment |
| crit.6 | policy |  |  |  |  |  |  |  | judgment |
| ctx.1 | policy |  |  |  | warn |  |  |  |  |
| ctx.2 | policy |  |  |  |  |  | warn |  |  |
| ctx.3 | policy |  |  |  |  |  |  |  | judgment |
| ctx.4 | policy |  |  |  |  |  |  |  | judgment |
| fix.1 | policy |  |  |  | block |  |  |  |  |
| fix.2 | policy |  |  |  | block |  |  |  |  |
| fix.3 | policy |  |  |  |  |  |  |  | judgment |
| fix.4 | policy |  |  |  |  |  |  |  | judgment |
| fix.5 | policy |  |  |  | warn |  | warn |  |  |
| fix.6 | policy |  |  |  | warn |  |  |  |  |
| fix.7 | policy |  |  |  |  |  |  |  | judgment |
| fix.8 | policy |  |  |  |  |  |  |  | judgment |
| fix.9 | policy |  |  |  |  |  |  |  | judgment |
| mod.1 | policy |  |  |  |  |  |  |  | judgment |
| mod.2 | policy |  |  |  |  |  |  |  | judgment |
| mod.3 | policy |  |  |  |  |  |  |  | judgment |
| idl.1 | policy |  |  |  |  |  |  |  | judgment |
| idl.2 | policy |  |  |  |  |  |  |  | judgment |
| ops.1 | policy |  |  |  |  |  |  |  | judgment |
| ops.2 | policy |  |  |  |  |  |  |  | judgment |
| ops.3 | policy |  |  |  |  |  |  |  | judgment |
| ops.4 | policy |  |  |  |  |  |  |  | judgment |
| ops.5 | policy | block |  |  |  |  |  |  |  |
| ops.6 | policy | block |  |  |  |  |  |  |  |
| ops.7 | policy |  |  |  |  |  |  |  | judgment |
| ops.8 | policy |  |  |  |  |  |  |  | judgment |
| ops.9 | policy |  |  |  |  |  |  |  | judgment |
| ops.10 | policy |  |  |  |  |  |  |  | judgment |
| ops.11 | policy |  |  |  |  |  |  |  | judgment |
| ops.12 | policy |  |  | block | block |  | warn |  |  |
| deg.1 | policy |  |  |  |  |  |  |  | judgment |
| deg.2 | policy |  |  |  |  |  |  |  | judgment |

## Pairs never seen red

A pair whose control has no red proof (controls.tsv red_proof is `-`): it cannot be promoted, and a person may retire it. Proposed here, never edited.

- n1.3 / check.reply-shape (schedule)
- n2.1 / check.reply-shape (schedule)
- n4.1 / admission.external-content-label (write)
- n4.2 / admission.governance-token (write)
