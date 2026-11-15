---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/doc-report-verify.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/doc-report-verify.sh, lines 5-30 (before this edit)

```text
WHY THIS EXISTS. A topology audit shipped on 2026-09-03 green on every gate it
had. The defects a reader actually hit were not in its findings, they were in
its LEGIBILITY — a bare `123456789` that could have been three different
objects, a `40 of 40` that bounded three of nine classes and said so nowhere, a
first diagram containing no pipeline at all. Cheap to fix, and invisible to the
author, who holds the context and therefore cannot feel its absence.

WHAT IT CHECKS, and the line is drawn deliberately. Properties 4, 5 and 6 of
contracts/reports.md are mechanical: does the artefact bound its own scope, name
its source and date, and — if it is a picture — have the text companion beside
it. Properties 1 to 3 (reads cold, typed identifiers, numbers with comparisons)
are judgement, and every heuristic for them fires on ordinary work: "a bare id"
matches version numbers, row counts, dates and currency. A guard that fires on
ordinary work gets switched off and then protects nothing (gates.md property 5),
so typing is enforced where ids are PRODUCED — reconcile-estate.sh asserts its
own — never by scanning finished prose for digits.

EXIT CODES follow gates.md property 7, which this file also has to obey:
  0  checked, conforms
  1  checked, does not conform — every failure is named
  2  COULD NOT CHECK (unreadable, or a kind it has no rules for)
A checker that cannot read its subject and reports "does not conform" has
manufactured a finding, which is the defect harbor#407 closed one artefact over.

BSD userland: grep is ugrep and skips gitignored files, so every grep is
/usr/bin/grep.
```

## bin/doc-report-verify.sh, lines 48-50 (before this edit)

```text
---------------------------------------------------------------- the checks
Each returns 0 (met), 1 (not met) and prints why. None of them guesses: a
property this file cannot settle is reported as unsettled, never as met.
```

## bin/doc-report-verify.sh, lines 52-68 (before this edit)

```text
4 · SCOPE. The artefact says what it did NOT cover. Alternatives are listed
because three generators arrived at three honest spellings independently, and
forcing one on them would be the checker deciding a contract it exists to
serve. What is NOT accepted is silence.

MATCHED CASE-INSENSITIVELY, and that is not cosmetic. The first version was
case-sensitive and rejected a companion whose heading reads "What this view does
NOT cover" — the emphasis capital made a conforming artefact fail. A checker
that fails correct work is a checker somebody switches off (gates.md property
5), and the contract is about the artefact SAYING its limits, never about how it
capitalises them. Caught by running this against real client output.

Widened again 2026-09-04, same reason and the same evidence: a client atlas states its
limits under "What this page cannot tell you", "What this atlas does not draw" and
"What nobody could measure", and failed on all three while conforming better than
anything that passed. Three more honest spellings, not three more loopholes — each one
still names a limit, which is the whole property.
```

## bin/doc-report-verify.sh, lines 71-73 (before this edit)

```text
5 · PROVENANCE. A source AND a date. Either alone is half a claim: a report
naming its source but not when it was taken reads as current forever, and one
with a date and no source cannot be re-derived.
```

## bin/doc-report-verify.sh, lines 77-87 (before this edit)

```text
7 · CONFIDENCE. An artefact that grades how badly something hurts must also grade how
well it is known, or the two collapse into one and the reader cannot tell a lead from a
re-measured fact. Measured on a client atlas 2026-09-03: five findings its own source
marks "one lane only — treat as a lead, not a fact" rendered identically to the fifteen
a critic had re-measured, and nothing on the page could get the distinction back.

ASKED ONLY OF AN ARTEFACT THAT ALREADY GRADES SEVERITY, and that narrowness is the
point. Every broader trigger — "does it list findings", "does it have a table" — fires
on ordinary documents, and a guard that fires on ordinary work is switched off
(gates.md property 5). A report grading impact has already declared itself the kind of
document this property is about; one that does not is left alone.
```

## bin/doc-report-verify.sh, lines 124-127 (before this edit)

```text
6 · A PICTURE HAS A COMPANION. Only asked of an artefact that actually draws
one — an inline <svg>, or an archify figure. A report with no picture is not
failed for lacking a companion to it, which would be the guard firing on
ordinary work.
```

## bin/doc-report-verify.sh, lines 141-141 (before this edit)

```text
---------------------------------------------------------------- self-test
```

## bin/doc-report-verify.sh, lines 157-161 (before this edit)

```text
THE SOURCE AND THE DATE SIT ON SEPARATE LINES DELIBERATELY. Written as one
line, the mutation that strips the source also strips the date, so the
no-source arm failed on the DATE rule and passed while the source rule was
mutated away — a test that cannot fail for the reason it names. Measured
2026-09-03 by mutation, which is the only thing that could have found it.
```

## bin/doc-report-verify.sh, lines 185-187 (before this edit)

```text
The severity line and the confidence line are separate lines for the same reason the
source and the date are: written as one, the mutation that removes the grade removes
the trigger with it, and the arm passes while the rule it names is switched off.
```

## bin/doc-report-verify.sh, lines 194-195 (before this edit)

```text
The control that keeps property 7 from firing on ordinary work: a document that never
grades impact is never asked to grade confidence.
```

## bin/doc-report-verify.sh, lines 204-206 (before this edit)

```text
THE CONTROLS. Both directions, because a checker that fails everything is as
useless as one that passes everything — and the second arm is the one that
keeps this from becoming a guard people switch off.
```

## bin/doc-report-verify.sh, lines 213-214 (before this edit)

```text
AND IT MUST SAY "COULD NOT CHECK" RATHER THAN "FAILS" — gates.md property 7,
which this checker is not exempt from just because it enforces it.
```

## bin/doc-report-verify.sh, lines 233-235 (before this edit)

```text
A "could not check" does not become a pass: it is a FAIL and it makes the run
non-zero, because a caller that treats unchecked as checked is the failure this
whole contract exists to prevent.
```
