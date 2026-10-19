# Absent by decision — what CONSTITUTION.md deliberately does not claim

**On-demand.** Moved out of the resident prompt on 2026-07-26 because it is read
when *auditing* the constitution, not when following it — and `bin/context-budget.sh`
showed the resident surface was already over its ceiling before TELOS, IDENTITY
and memory injection land.

This is upstream's own move: upstream relocated `SelfHealing.md`,
`VerificationExpanded.md` and `Philosophy.md` out of its resident system prompt
for exactly this reason (see the "Relocated verbatim … (7.0.0 BPE)" headers at
the `RULES/` directory of the mirror at `~/.harbor-upstream`).

**Load when:** someone proposes adding a mechanism to the constitution, or asks
why an upstream feature is missing from it.

Harbor does not run upstream's engine, and a constitution that referenced machinery
that does not exist would be a constitution that lies — after which a reader has
no way to tell which other parts are also wrong. So the following are **absent by
decision**, not by oversight, and are not to be re-added by citation until they
are built:

| Not here | Status |
|---|---|
| A response banner, a named persona, a signature closer | de-persona'd on intake ([PROVENANCE.md](../PROVENANCE.md)) |
| `DA_IDENTITY.md`, a principal identity tree, TELOS data | never taken |
| A memory-delta / memory-health field | no memory hooks emit one; an unfillable field is worse than none |
| The Algorithm as a runtime, `ALGORITHM/LATEST`, an ISA store | F1 is **model only**; the `isa` skill is vendored, nothing drives runs from it |
| Upstream's Pulse — the `localhost:31337` service, the menubar app, the voice server | **the service is still not taken; the monitoring is.** E1 shipped 2026-08-02 as a launchd-scheduled probe in POSIX sh (`bin/pulse.sh`, `bin/pulse-notify.sh`) with no resident daemon and no listening port. The row is kept rather than deleted because the distinction is the point: a constitution may cite Harbor's probe, and may not cite a daemon that does not exist here |
| An `Interceptor`-only browser doctrine | never vendored; the **fidelity principle** in №2 survives, the tool ban does not |
| A release/containment-scrub workflow | never taken; №3 rests on judgment plus `permissions.deny` |
| A turn-level deliverable-contract hook (workstream **R4**) | **declined 2026-09-02**, against R1's own pre-written rule rather than on preference. R1 said that if `casefile` fired unprompted at a rate no better than DS-1's zero of six, the skill layer was inert and the hook was the only load-bearing item — and if it did fire, the hook was optional and had to be argued on its own cost. Measured across three evals: `casefile` fired unprompted **4 of 4** on fixtures built to carry none of its trigger vocabulary, and hidden skills were reached **6 of 6** by path. The layer is not inert. R3 shipped the cheap half instead — `deliverable-contract` is model-invocable, which is the in-turn binding the hook was going to buy, at the cost of one description rather than a plugin, a hook contract and a guard that must stay silent on ordinary turns. **What a hook would still buy is real and unmeasured**: firing on turns where no skill fires at all. That is a new argument, not this one, and it starts from zero |
| `UPSTREAM/RULES/*.md` pointers | dropped **by name**. The upstream mirror is readable at `~/.harbor-upstream`, so a relative pointer would resolve *into upstream doctrine* — turning a harmless dangling reference into a path back to the engine the no-fork decision excluded. A bare basename is worse still: `Philosophy.md` resolves to the RedTeam skill's file, silently and wrongly. |

**One note on de-persona, kept because the sequence is the point.** When this
file was written on 2026-07-26 it recorded de-persona as *not* complete: 6
unrendered `{{PRINCIPAL_NAME}}` tokens shipped literally in three vendored Fabric
READMEs, and 7 occurrences of "the principal" survived in `telos/`, `isa/`,
`fabric/` and `harvest/` — all installed, all loadable in the same session as
this document, which says "the operator". A constitution that contradicts skills
loaded beside it is worse than one that admits a gap, so it admitted the gap.

**Closed the same day IN THE REPO**, all 13 replaced (`vendor/skills/PROVENANCE.md`).
The rule this illustrates is §Fix the system: the earlier ledger asserted the intake
rule had been applied, and nothing checked. Writing the gap down is what got it
fixed within the hour.

**And then this note made the same mistake one layer out.** It read "closed the
same day" full stop until 2026-08-13, when an audit measured the BOX rather than
the tree: the repo is clean (one match, in the ledger recording the fix) while the
LIVE install still renders `{{PRINCIPAL_NAME}}` literally in three Fabric READMEs
and still says "the principal" in four more files — loadable in the same session as
a constitution that says "the operator", which is verbatim the condition this
section calls "worse than one that admits a gap". A `diff` of one pair settles that
it is install drift and not a different artefact: the repo line reads "the
operator's main `extractwisdom` version", the installed line reads
"{{PRINCIPAL_NAME}}'s".

The reason it survived seventeen days is that no mechanism could see it, which is
the §Fix the system point repeating: lint **X8** byte-compares only the Harbor-
AUTHORED `skills/` (its own output on 2026-09-16 says "1 of 49 installed
skill(s) have drifted"), **X4** compares tier agreement and not bytes, and the
vendored skills were never compared to their installed copies at all. X8 now
walks `vendor/skills/` too — so the next intake-rule claim is falsifiable from
inside the repo, which this one
was not. The remedy for the drift itself is a re-install, not a repo edit: the repo
is the correct side.
