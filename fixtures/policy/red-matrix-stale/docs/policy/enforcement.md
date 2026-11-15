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
| write | 9 | 9 | 9 |
| session | 0 | 0 | 0 |
| commit | 0 | 0 | 0 |
| pr | 0 | 0 | 1 |
| merge | 0 | 0 | 0 |
| schedule | 0 | 0 | 0 |
| deploy | 0 | 0 | 0 |

## Judgment share per strength

| strength | clauses | judgment only | share |
|---|---|---|---|
| policy | 2 | 1 | 50% |

## Clause x moment

| clause | strength | write | session | commit | pr | merge | schedule | deploy | judgment |
|---|---|---|---|---|---|---|---|---|---|
| t.1 | policy |  |  |  | block |  |  |  |  |
| t.2 | policy |  |  |  |  |  |  |  | judgment |

## Pairs never seen red

A pair whose control has no red proof (controls.tsv red_proof is `-`): it cannot be promoted, and a person may retire it. Proposed here, never edited.

None.
