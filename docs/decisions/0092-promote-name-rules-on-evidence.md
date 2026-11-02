---
kind: decision-record
status: accepted
alias: D-92
date: 2026-10-28
source: harbor#968
---

# Name rules are promoted on evidence, not on the calendar

Naming-standard decision D-92. Settles when a `warn` name rule may become `block`; close-out of the naming epic (harbor#949, harbor#968).

## Context

- Operator decision, 2026-10-28: close the naming epic as fast as possible.
- The old rule (D-64, §10.3): a warn rule is promoted after it has gone red and run 28 days with no finding accepted as false.
  The wait measures time, not whether the rule is right.

## Decision

**A `warn` rule run by `bin/lint-name.sh` may go to `block` when both hold:** (a) it has a red proof (a passing lint suite
watched it fail on a planted violation), and (b) it reports 0 findings across every governed repo. The repos are those of
`bin/roots.sh --repos`; `bin/lint-name.sh` is run against each checkout with harbor's registry.
`sh bin/rule-health.sh --promotion` prints eligible or not eligible per rule, with the reason (no red proof, or N findings in
repo X). A rule with findings stays `warn` until they are fixed. Promotion is still a commit that changes one `controls.tsv`
cell. Rules not run by `lint-name.sh` keep D-64's 28 days.

## Consequences

- **Risk accepted:** a rule with 0 findings today can still false-positive on new code. The fix then is to demote it to `warn`,
  not to add an exemption or an inline ignore.
- `remove_by` dates in `aliases.tsv` and `renames.tsv` that were 2027-01-31 to 2027-03-14 are now 2026-11-15.
