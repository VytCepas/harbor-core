#!/usr/bin/env sh
# doc-report-verify.sh — does a generated artefact meet contracts/reports.md?
# Ticket: harbor#411 (the first production run that shipped green and unreadable).
#
# WHY THIS EXISTS. A topology audit shipped on 2026-09-03 green on every gate it
# had. The defects a reader actually hit were not in its findings, they were in
# its LEGIBILITY — a bare `123456789` that could have been three different
# objects, a `40 of 40` that bounded three of nine classes and said so nowhere, a
# first diagram containing no pipeline at all. Cheap to fix, and invisible to the
# author, who holds the context and therefore cannot feel its absence.
#
# WHAT IT CHECKS, and the line is drawn deliberately. Properties 4, 5 and 6 of
# contracts/reports.md are mechanical: does the artefact bound its own scope, name
# its source and date, and — if it is a picture — have the text companion beside
# it. Properties 1 to 3 (reads cold, typed identifiers, numbers with comparisons)
# are judgement, and every heuristic for them fires on ordinary work: "a bare id"
# matches version numbers, row counts, dates and currency. A guard that fires on
# ordinary work gets switched off and then protects nothing (gates.md property 5),
# so typing is enforced where ids are PRODUCED — reconcile-estate.sh asserts its
# own — never by scanning finished prose for digits.
#
# EXIT CODES follow gates.md property 7, which this file also has to obey:
#   0  checked, conforms
#   1  checked, does not conform — every failure is named
#   2  COULD NOT CHECK (unreadable, or a kind it has no rules for)
# A checker that cannot read its subject and reports "does not conform" has
# manufactured a finding, which is the defect harbor#407 closed one artefact over.
#
# BSD userland: grep is ugrep and skips gitignored files, so every grep is
# /usr/bin/grep.
set -eu

HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/library-log.sh"
log_init report-contract

usage() {
  printf 'usage: %s <artefact.html|artefact.md> [...]\n' "$0" >&2
  printf '       %s --self-test\n' "$0" >&2
  printf '\n  Checks a GENERATED report against contracts/reports.md:\n' >&2
  printf '    4  it states what it does not cover\n' >&2
  printf '    5  it names its source and its as-of date\n' >&2
  printf '    6  a picture has a text companion beside it\n' >&2
  printf '\n  exit 0 conforms · 1 does not · 2 could not check\n' >&2
  exit 2
}

# ---------------------------------------------------------------- the checks
# Each returns 0 (met), 1 (not met) and prints why. None of them guesses: a
# property this file cannot settle is reported as unsettled, never as met.

# 4 · SCOPE. The artefact says what it did NOT cover. Alternatives are listed
# because three generators arrived at three honest spellings independently, and
# forcing one on them would be the checker deciding a contract it exists to
# serve. What is NOT accepted is silence.
#
# MATCHED CASE-INSENSITIVELY, and that is not cosmetic. The first version was
# case-sensitive and rejected a companion whose heading reads "What this view does
# NOT cover" — the emphasis capital made a conforming artefact fail. A checker
# that fails correct work is a checker somebody switches off (gates.md property
# 5), and the contract is about the artefact SAYING its limits, never about how it
# capitalises them. Caught by running this against real client output.
#
# Widened again 2026-09-04, same reason and the same evidence: a client atlas states its
# limits under "What this page cannot tell you", "What this atlas does not draw" and
# "What nobody could measure", and failed on all three while conforming better than
# anything that passed. Three more honest spellings, not three more loopholes — each one
# still names a limit, which is the whole property.
SCOPE_ERE='NOT ENUMERATED|not enumerated|does not cover|does not draw|not covered|out of scope|bounds only|no reader checks them|UNCHECKED|declares no|cannot tell you|could not measure|could not be answered|cannot see'

# 5 · PROVENANCE. A source AND a date. Either alone is half a claim: a report
# naming its source but not when it was taken reads as current forever, and one
# with a date and no source cannot be re-derived.
SOURCE_ERE='[Gg]enerated (by|from)|derived (only )?from|[Ss]ource:|reconciling |[Ff]rom `'
DATE_ERE='20[0-9][0-9]-[01][0-9]-[0-3][0-9]'

# 7 · CONFIDENCE. An artefact that grades how badly something hurts must also grade how
# well it is known, or the two collapse into one and the reader cannot tell a lead from a
# re-measured fact. Measured on a client atlas 2026-09-03: five findings its own source
# marks "one lane only — treat as a lead, not a fact" rendered identically to the fifteen
# a critic had re-measured, and nothing on the page could get the distinction back.
#
# ASKED ONLY OF AN ARTEFACT THAT ALREADY GRADES SEVERITY, and that narrowness is the
# point. Every broader trigger — "does it list findings", "does it have a table" — fires
# on ordinary documents, and a guard that fires on ordinary work is switched off
# (gates.md property 5). A report grading impact has already declared itself the kind of
# document this property is about; one that does not is left alone.
SEVERITY_ERE='severity|CRITICAL|critical.*high.*medium|>critical<|"critical"'
CONFIDENCE_ERE='[Cc]onfirmed|OVERSTATED|[Oo]verstated|UNDERSTATED|[Uu]nderstated|REFUTED|[Rr]efuted|[Rr]eframed|one lane|ONE LANE|uncritiqued|not re-measured|re-measured|unverified|provisional|treat as a lead|could not verify|rests on'

check_one() {
  _f=$1
  [ -r "$_f" ] || { log_fail "$_f: could not check, unreadable"; log_fix "ls -l $_f"; return 2; }
  [ -s "$_f" ] || { log_fail "$_f: could not check, empty"; log_fix "regenerate the artefact, then rerun sh $0 $_f"; return 2; }
  case "$_f" in
    *.html|*.htm|*.md) : ;;
    *) log_fail "$_f: could not check, no rules for this kind"; log_fix "sh $0 <artefact.html|artefact.md>"; return 2 ;;
  esac

  _bad=0
  if ! /usr/bin/grep -qiE "$SCOPE_ERE" "$_f"; then
    log_fail "$_f: [4] states no limit on itself; a reader cannot infer scope from a document that looks complete"
    log_fix "add a section naming the classes it did not cover (contracts/reports.md, property 4)"
    _bad=1
  fi
  if ! /usr/bin/grep -qE "$SOURCE_ERE" "$_f"; then
    log_fail "$_f: [5] names no source; a report that cannot be re-derived is an assertion"
    log_fix "name what it was generated from (contracts/reports.md, property 5)"
    _bad=1
  fi
  if ! /usr/bin/grep -qE "$DATE_ERE" "$_f"; then
    log_fail "$_f: [5] carries no ISO date, so it reads as current forever"
    log_fix "add the as-of date as YYYY-MM-DD (contracts/reports.md, property 5)"
    _bad=1
  fi

  if /usr/bin/grep -qE "$SEVERITY_ERE" "$_f" 2>/dev/null &&
     ! /usr/bin/grep -qE "$CONFIDENCE_ERE" "$_f"; then
    log_fail "$_f: [7] grades how badly things hurt and never how well they are known; a one-lane lead and a re-measured fact render identically"
    log_fix "grade each finding's confidence beside its severity (contracts/reports.md, property 7)"
    _bad=1
  fi

  # 6 · A PICTURE HAS A COMPANION. Only asked of an artefact that actually draws
  # one — an inline <svg>, or an archify figure. A report with no picture is not
  # failed for lacking a companion to it, which would be the guard firing on
  # ordinary work.
  if /usr/bin/grep -qE '<svg|figure class="af"' "$_f" 2>/dev/null; then
    _stem=${_f%.*}
    if [ ! -s "$_stem.md" ] && ! /usr/bin/grep -qE 'as the map wrote them|the same rows|<table' "$_f"; then
      log_fail "$_f: [6] draws a picture with no text beside it and no $(basename "$_stem").md; a diagram is the one artefact whose defects are invisible in its own output"
      log_fix "write $(basename "$_stem").md beside it, or put the same rows in a <table>"
      _bad=1
    fi
  fi

  if [ "$_bad" -eq 0 ]; then log_ok "$_f"; fi
  return "$_bad"
}

# ---------------------------------------------------------------- self-test
self_test() {
  _d=$(mktemp -d "${TMPDIR:-/tmp}/harbor.XXXXXX")
  # check_one runs in a subshell: its own log lines and counts are the case's, not the self-test's.
  _run() {  # _run <expected-rc> <label> <file>
    _rc=0; ( check_one "$3" ) >"$_d/out" 2>&1 || _rc=$?
    if [ "$_rc" -eq "$1" ]; then
      log_ok "$2 (exit $_rc)"
    else
      log_fail "$2: expected exit $1, got $_rc"
      log_fix "sh $0 $3"
      while IFS= read -r _ol; do log_note "$_ol"; done < "$_d/out"
    fi
  }

  log_head 'a conforming report is GREEN'
  # THE SOURCE AND THE DATE SIT ON SEPARATE LINES DELIBERATELY. Written as one
  # line, the mutation that strips the source also strips the date, so the
  # no-source arm failed on the DATE rule and passed while the source rule was
  # mutated away — a test that cannot fail for the reason it names. Measured
  # 2026-09-03 by mutation, which is the only thing that could have found it.
  cat > "$_d/good.md" <<'EOF'
# ACME — reconciliation
Generated by reconcile-estate.sh from ACME/TOPOLOGY.md.
As of 2026-09-03.
Analytics property 12345, read from accountSummaries, role dir analytics.
-- NOT ENUMERATED: BI assets, warehouse models. A result above bounds only the classes listed.
EOF
  _run 0 'source, date and a scope statement' "$_d/good.md"

  sed 's/NOT ENUMERATED/What this view does NOT cover/' "$_d/good.md" > "$_d/caps.md"
  _run 0 'a scope statement in different casing still counts' "$_d/caps.md"

  log_head 'each missing property must go RED'
  /usr/bin/grep -v 'NOT ENUMERATED' "$_d/good.md" > "$_d/noscope.md"
  _run 1 'no statement of what it does not cover' "$_d/noscope.md"

  /usr/bin/grep -v 'Generated by' "$_d/good.md" > "$_d/nosrc.md"
  _run 1 'no source it can be re-derived from' "$_d/nosrc.md"

  sed 's/2026-09-03/recently/' "$_d/good.md" > "$_d/nodate.md"
  _run 1 'no ISO date, so it reads as current forever' "$_d/nodate.md"

  log_head 'grading impact obliges grading confidence'
  # The severity line and the confidence line are separate lines for the same reason the
  # source and the date are: written as one, the mutation that removes the grade removes
  # the trigger with it, and the arm passes while the rule it names is switched off.
  printf '%s\nEach finding carries a severity: critical, high, medium, low.\n' \
    "$(cat "$_d/good.md")" > "$_d/nograde.md"
  _run 1 'severities but no confidence anywhere' "$_d/nograde.md"
  printf '%s\nF3 is CONFIRMED; F8 rests on one lane and is a lead, not a fact.\n' \
    "$(cat "$_d/nograde.md")" > "$_d/graded.md"
  _run 0 'the same document once the findings carry their grade' "$_d/graded.md"
  # The control that keeps property 7 from firing on ordinary work: a document that never
  # grades impact is never asked to grade confidence.
  _run 0 'a report that grades nothing is not asked to grade confidence' "$_d/good.md"

  log_head 'a picture must have text beside it'
  printf '%s\n<svg width="10"></svg>\n' "$(cat "$_d/good.md")" > "$_d/pic.html"
  _run 1 'a drawing with no companion and no table' "$_d/pic.html"
  printf '%s\n' "conforms" > "$_d/pic.md"
  _run 0 'and the same drawing passes once the companion exists' "$_d/pic.html"

  # THE CONTROLS. Both directions, because a checker that fails everything is as
  # useless as one that passes everything — and the second arm is the one that
  # keeps this from becoming a guard people switch off.
  log_head 'it must NOT fire on ordinary work'
  _run 0 'a report with no picture is not failed for lacking a companion' "$_d/good.md"
  printf '%s\n<table><tr><td>every row, in text</td></tr></table>\n<svg></svg>\n' \
    "$(cat "$_d/good.md")" > "$_d/inline.html"
  _run 0 'a picture whose rows are in a table beside it needs no separate file' "$_d/inline.html"

  # AND IT MUST SAY "COULD NOT CHECK" RATHER THAN "FAILS" — gates.md property 7,
  # which this checker is not exempt from just because it enforces it.
  log_head 'unreadable is not the same as non-conforming'
  _run 2 'a file that does not exist exits 2, never 1' "$_d/nonexistent.md"
  : > "$_d/empty.md"
  _run 2 'an empty file exits 2' "$_d/empty.md"
  printf 'x\n' > "$_d/thing.bin"
  _run 2 'a kind it has no rules for exits 2' "$_d/thing.bin"

  rm -rf "$_d"
  log_end
}

case "${1:-}" in
  -h|--help|'') usage ;;
  --self-test)  self_test; exit $? ;;
esac

log_head "contracts/reports.md properties 4 to 7"
for f in "$@"; do
  # A "could not check" does not become a pass: it is a FAIL and it makes the run
  # non-zero, because a caller that treats unchecked as checked is the failure this
  # whole contract exists to prevent.
  check_one "$f" || :
done
log_end
exit $?
