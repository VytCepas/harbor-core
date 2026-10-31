#!/usr/bin/env sh
# bin/lint-rule-health.sh (harbor#577): red proof is read from what the passing suites made go red, a failing
# suite stands the run down, silence is judged only on 8 weeks of ledger, and a ratchet is never silent.
# A fixture linter and fixture suites stand in for the real ones, so the run takes seconds.
. "$(dirname "$0")/../../lib/core.sh"; t_init
RH="$T_ROOT/bin/lint-rule-health.sh"; F="$T_TMP/rh"; mkdir -p "$F"
CLAUDE_CONFIG_DIR="$F/cfg"; export CLAUDE_CONFIG_DIR
REC="$F/cfg/cache/checks/lint.rule-health.json"

# The fixture linter: three rules, A3 a declared ratchet; `--only A1 --plant` goes red the way bad() does.
cat > "$F/lint.sh" <<'LINT'
#!/bin/sh
case "$1" in
  --list) printf '  A1 a rule a suite proves\n  A2 a rule nothing proves\n  A3 the zero ratchet\n' ;;
  --ids)  printf 'id\tdeprecated\nA1\t-\nA2\tQ2\nA3\t-\n' ;;
  --only) [ "${3:-}" = --plant ] || { sleep 1               # every rule costs a second alone, so only an exclusion keeps one off
            [ "$2" != "${FIX_CRASH:-}" ] || exit 3              # a rule that crashes when run alone
            [ "$2" != "${FIX_FIRE:-}" ] || { [ -z "${LINT_REDLOG:-}" ] || printf '%s\n' "$2" >> "$LINT_REDLOG"; exit 1; }
            exit 0; }
          [ -z "${LINT_REDLOG:-}" ] || printf '%s\n' "$2" >> "$LINT_REDLOG"; exit 1 ;;
esac
LINT
printf '#!/bin/sh\nsh "%s" --only A1 --plant >/dev/null; echo "s1: 1 passed, 0 failed"\n' "$F/lint.sh" > "$F/s1.sh"
printf '#!/bin/sh\necho "s2: 0 passed, 1 failed"; exit 1\n' > "$F/s2.sh"

# The finding store: GH_AGE sets how old its oldest finding is; GH_SEEN_A2 marks GH_SEEN_KEY (A2) as
# firing on GH_SEEN.
cat > "$T_BIN/gh" <<'GH'
#!/bin/sh
[ "$1 $2" = "issue list" ] || exit 1
case "${GH_FAIL:-}" in auth) echo "HTTP 401: Bad credentials" >&2; exit 1 ;; html) echo '<html>'; exit 0 ;;
  baddate) echo '[{"createdAt":"yesterday","body":"x"}]'; exit 0 ;; esac
case "$*" in *finding:accepted*) printf '%s\n' "${GH_ACCEPTED:-[]}"; exit 0 ;; esac   # --promotion's accepted-as-false read
b=""; [ -z "${GH_SEEN_A2:-}" ] || b='{"createdAt":"2026-10-01T00:00:00Z","body":"<!-- harbor:finding key=lint/'"${GH_SEEN_KEY:-A2}"' digest=x seen='"${GH_SEEN:-2026-11-30}"' schema=1 -->"},'
printf '[%s{"createdAt":"%sT00:00:00Z","body":"x"}]\n' "$b" "${GH_AGE:-2026-11-30}"
GH
chmod +x "$T_BIN/gh"
# The judged tree: a clean checkout at origin/main is the only one whose receipt is written (#915).
TREE="$F/tree"; mkdir -p "$TREE"; git init -q "$TREE"; git -C "$TREE" symbolic-ref HEAD refs/heads/main
g() { git -C "$TREE" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
: > "$TREE/seed"; g add seed; g commit -qm seed; git -C "$TREE" update-ref refs/remotes/origin/main HEAD
# The reconcile's own receipt: silence is judged only while it is ok and recent (review #931).
rstate() { mkdir -p "$F/cfg/cache"; printf '{"ran_at":"%sT06:34:59Z","status":"%s"}\n' "$1" "$2" > "$F/cfg/cache/findings-state.json"; }
rstate 2026-11-30 ok
rh() { HARBOR_SCOPE_ROOT="$TREE" HARBOR_LINT_RULE_HEALTH_LINT="$F/lint.sh" HARBOR_LINT_FINDINGS_REPO=o/r HARBOR_LINT_RULE_HEALTH_NOW=2026-12-01 sh "$RH" "$@" 2>&1; }

t_section "an unproven rule is a candidate; a proven one is not"
OUT="$(HARBOR_LINT_RULE_HEALTH_SUITES="$F/s1.sh" rh)"; RC=$?
t_eq "exit 1: candidates" 1 "$RC"
t_eq "the receipt is red over the unproven rules only" 'red ["unproven:A2","unproven:A3"]' "$(jq -c -r '"\(.status) \(.subjects)"' "$REC")"
t_eq "it counts as a run for eight days" 8 "$(jq -r .fresh_days "$REC")"
t_has "the budget states both numbers" "$OUT" "2 of 3 have no red proof"

t_section "a failing suite stands the run down: its red log proves nothing"
OUT="$(HARBOR_LINT_RULE_HEALTH_SUITES="$F/s1.sh $F/s2.sh" rh)"; RC=$?
t_eq "exit 3 (D-29 unchecked), not the 2 of a usage error" 3 "$RC"
t_eq "stood-down, with no subject" "stood-down []" "$(jq -c -r '"\(.status) \(.subjects)"' "$REC")"
t_has "and names the suite" "$OUT" "s2.sh exited 1"

t_section "silence is not judged on a ledger under eight weeks old"
OUT="$(HARBOR_LINT_RULE_HEALTH_SUITES="$F/s1.sh" HARBOR_LINT_RULE_HEALTH_COST_S=0 rh)"
t_has "said, not passed" "$OUT" "silence not judged: the ledger is 1 day(s) old"
t_hasnt "and nothing is called silent" "$(jq -c .subjects "$REC")" "silent:"
t_has "positive control: the receipt was read" "$(jq -c .subjects "$REC")" "unproven:A2"

t_section "on eight weeks of ledger, a costly rule with no fire is silent — never a ratchet, never one that fired"
OUT="$(HARBOR_LINT_RULE_HEALTH_SUITES="$F/s1.sh" HARBOR_LINT_RULE_HEALTH_COST_S=0 GH_AGE=2026-09-01 GH_SEEN_A2=1 rh)"
t_eq "A1 is silent; A3 is a ratchet and A2 fired" 'red ["unproven:A2","unproven:A3","silent:A1"]' "$(jq -c -r '"\(.status) \(.subjects)"' "$REC")"

t_section "harbor#957: a finding filed under a rule's deprecated letter is that rule firing"
OUT="$(HARBOR_LINT_RULE_HEALTH_SUITES="$F/s1.sh" HARBOR_LINT_RULE_HEALTH_COST_S=0 GH_AGE=2026-09-01 GH_SEEN_A2=1 GH_SEEN_KEY=Q2 rh)"
t_eq "lint/Q2 seen firing is A2 firing: A2 is not silent" 'red ["unproven:A2","unproven:A3","silent:A1"]' "$(jq -c -r '"\(.status) \(.subjects)"' "$REC")"

t_section "every rule proven and nothing silent is green"
cat > "$F/s3.sh" <<S3
#!/bin/sh
for r in A1 A2 A3; do sh "$F/lint.sh" --only \$r --plant >/dev/null; done; echo "s3: 3 passed, 0 failed"
S3
OUT="$(HARBOR_LINT_RULE_HEALTH_SUITES="$F/s3.sh" rh)"; RC=$?
t_eq "exit 0" 0 "$RC"
t_eq "green, no subjects" "green []" "$(jq -c -r '"\(.status) \(.subjects)"' "$REC")"
# green on a 1-day ledger is honest: no silent: finding can exist before the ledger is 8 weeks old

t_section "review #909: a store that cannot be read stands down; a green would close an open silent: as fixed"
OUT="$(HARBOR_LINT_RULE_HEALTH_SUITES="$F/s3.sh" GH_FAIL=auth rh)"; RC=$?
t_eq "exit 3 (D-29 unchecked)" 3 "$RC"
t_eq "stood-down, never green" "stood-down []" "$(jq -c -r '"\(.status) \(.subjects)"' "$REC")"
t_has "and names why" "$OUT" "HTTP 401: Bad credentials"
OUT="$(HARBOR_LINT_RULE_HEALTH_SUITES="$F/s3.sh" GH_FAIL=html rh)"; RC=$?
t_eq "an answer that is not JSON stands down too, with the documented exit" 3 "$RC"
t_has "and says so" "$OUT" "not a list of issues"

t_section "review #915: only a clean checkout at origin/main writes a receipt"
rm -f "$REC"; : > "$TREE/wip"
OUT="$(HARBOR_LINT_RULE_HEALTH_SUITES="$F/s3.sh" rh)"; RC=$?
t_eq "the verdict still prints and exits" 0 "$RC"
t_eq "a dirty tree writes nothing" no "$([ -f "$REC" ] && echo yes || echo no)"
t_has "and says why" "$OUT" "no receipt written: $TREE has uncommitted changes"
g add wip; g commit -qm ahead
OUT="$(HARBOR_LINT_RULE_HEALTH_SUITES="$F/s3.sh" rh)"
t_eq "a commit not on origin/main writes nothing" no "$([ -f "$REC" ] && echo yes || echo no)"
t_has "and names the commit" "$OUT" "not origin/main"
git -C "$TREE" update-ref refs/remotes/origin/main HEAD
OUT="$(HARBOR_LINT_RULE_HEALTH_SUITES="$F/s3.sh" rh)"
t_eq "positive control: once published, the receipt is written" "green []" "$(jq -c -r '"\(.status) \(.subjects)"' "$REC")"

t_section "review #915: a rule that fires in this run has fired, whatever a frozen seen= says"
OUT="$(HARBOR_LINT_RULE_HEALTH_SUITES="$F/s1.sh" HARBOR_LINT_RULE_HEALTH_COST_S=0 GH_AGE=2026-09-01 GH_SEEN_A2=1 FIX_FIRE=A1 rh)"
t_eq "A1 fires today, so it is not silent" 'red ["unproven:A2","unproven:A3"]' "$(jq -c -r '"\(.status) \(.subjects)"' "$REC")"

t_section "review #915: a dead reconcile is not judged, or every costly rule reads silent"
rstate 2026-10-01 ok
OUT="$(HARBOR_LINT_RULE_HEALTH_SUITES="$F/s1.sh" HARBOR_LINT_RULE_HEALTH_COST_S=0 GH_AGE=2026-09-01 GH_SEEN_A2=1 rh)"
t_has "a reconcile last run 61 days ago is said" "$OUT" "the reconcile last ran 61 day(s) ago"
t_hasnt "and nothing is called silent" "$(jq -c .subjects "$REC")" "silent:"
t_has "positive control: the receipt was written" "$(jq -c .subjects "$REC")" "unproven:A2"
rstate 2026-11-30 failed
OUT="$(HARBOR_LINT_RULE_HEALTH_SUITES="$F/s1.sh" HARBOR_LINT_RULE_HEALTH_COST_S=0 GH_AGE=2026-09-01 GH_SEEN_A2=1 rh)"
t_has "a reconcile that failed is not judged on" "$OUT" "does not say ok (status: failed)"
rm -f "$F/cfg/cache/findings-state.json"
OUT="$(HARBOR_LINT_RULE_HEALTH_SUITES="$F/s1.sh" HARBOR_LINT_RULE_HEALTH_COST_S=0 GH_AGE=2026-09-01 GH_SEEN_A2=1 rh)"
t_has "no reconcile receipt at all is not judged either" "$OUT" "(status: none)"
rstate 2026-11-30 ok
# all findings accepted: no seen= moves, and a live reconcile still judges (review #931)
OUT="$(HARBOR_LINT_RULE_HEALTH_SUITES="$F/s1.sh" HARBOR_LINT_RULE_HEALTH_COST_S=0 GH_AGE=2026-09-01 GH_SEEN_A2=1 GH_SEEN=2026-10-01 rh)"
t_has "a frozen seen= under a live reconcile is still judged" "$(jq -c .subjects "$REC")" "silent:A1"

t_section "review #915: a malformed createdAt stands down with a receipt, never aborts"
OUT="$(HARBOR_LINT_RULE_HEALTH_SUITES="$F/s3.sh" GH_FAIL=baddate rh)"; RC=$?
t_eq "exit 3 (D-29 unchecked)" 3 "$RC"
t_eq "stood-down" "stood-down []" "$(jq -c -r '"\(.status) \(.subjects)"' "$REC")"
t_has "and says what it could not read" "$OUT" "createdAt is not a date"

t_section "review #915: a rule that crashes alone is filed as crashed, never timed as cheap or silent"
OUT="$(HARBOR_LINT_RULE_HEALTH_SUITES="$F/s3.sh" HARBOR_LINT_RULE_HEALTH_COST_S=0 GH_AGE=2026-09-01 GH_SEEN_A2=1 GH_SEEN_KEY=A9 FIX_CRASH=A2 rh)"; RC=$?
t_eq "exit 1" 1 "$RC"
t_eq "crashed:A2 and never silent; A1 is silent, A3 a ratchet" 'red ["silent:A1","crashed:A2"]' "$(jq -c -r '"\(.status) \(.subjects)"' "$REC")"
t_has "and says so" "$OUT" "crashed when run alone (--only exited above 1): A2"

t_section "the real linter's red log is wired: one real suite names the rules it saw go red"
: > "$F/real.red"; LINT_REDLOG="$F/real.red" sh "$T_ROOT/tests/lint/conventions/findings.test.sh" > /dev/null 2>&1 || :
t_has "FL1 went red in its own suite, logged by its id" "$(sort -u "$F/real.red")" "audit.finding-lanes"
: > "$F/t2.red"; LINT_REDLOG="$F/t2.red" sh "$T_ROOT/tests/lint/conventions/docs.test.sh" > /dev/null 2>&1 || :
t_has "T2, which counts FAIL without bad(), is logged too, by its id" "$(sort -u "$F/t2.red")" "doc.counts-in-status-only"

t_section "harbor#968 (D-64): --promotion says which warn rules may go to block, and when, and writes nothing"
# A fixture repo with backdated history: each row and suite lands on the day its name says.
P="$F/ptree"; mkdir -p "$P/standards/naming" "$P/tests/checks"; git init -q "$P"; git -C "$P" symbolic-ref HEAD refs/heads/main
pc() { # <date> <message> — stage everything and commit it as of <date>
  git -C "$P" add -A
  GIT_AUTHOR_DATE="$1T12:00:00Z" GIT_COMMITTER_DATE="$1T12:00:00Z" git -C "$P" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm "$2"
}
HDR() { printf 'id\tmode\ttype\tengine\tsurfaces\tmoment\tfunction\tstability\tsuccessor\towner\tred_proof\temitted\ttitle\n'; }
ROW() { # <id> <mode> <type> <red_proof> <title> [engine] — the engine is the conventions linter unless one is named
  printf '%s\t%s\t%s\t%s\t-\tci\tdetective\texperimental\t-\tstandard\t%s\t-\t%s\n' "$1" "$2" "$3" "${6:-bin/lint-conventions.sh}" "$4" "$5"; }
cat > "$P/tests/checks/fix-test.sh" <<'SUITE'
#!/bin/sh
# the fixture suite watches every rule it names go red, and passes; fix.unproven is not among them
for _r in fix.old fix.accepted fix.open fix.young fix.edge fix.blocked fix.renamed fix.oldacc fix.norun name.fix fix.mystery doc.fix; do
  [ -z "${LINT_REDLOG:-}" ] || printf '%s\n' "$_r" >> "$LINT_REDLOG"
done
echo "fix: 11 passed, 0 failed"
SUITE
S1=tests/checks/fix-test.sh
{ HDR; ROW fix.old warn lint $S1 "landed long ago, red"
  ROW fix.accepted warn lint $S1 "red, but a finding was accepted as false"
  ROW fix.renamed warn lint $S1 "red, but a finding was accepted under its deprecated letter id"
  ROW fix.oldacc warn lint $S1 "a finding was accepted as false, but before the 28 days that count"
  ROW fix.open warn lint $S1 "red and old, with one finding open"
  ROW fix.norun warn lint $S1 "red and old, but the linter does not say it ran"
  ROW fix.unproven warn lint $S1 "its suite never watches it red"
  ROW fix.blocked block lint $S1 "already block, not a warn rule"
  ROW doc.fix warn lint $S1 "an accepted finding on the relay key restarts it" bin/doc-refs.sh
  ROW fix.mystery warn lint $S1 "an engine nobody relays: no finding key" bin/lint-mystery.sh
  ROW fix.check warn check - "a check: no finding counter here"; } > "$P/standards/naming/controls.tsv"
pc 2026-08-01 "seed"
ROW fix.edge warn lint $S1 "lands 28 days before today" >> "$P/standards/naming/controls.tsv"; pc 2026-09-16 "edge"
ROW fix.young warn lint $S1 "lands 27 days before today" >> "$P/standards/naming/controls.tsv"; pc 2026-09-17 "young"
# fix.late's row is old, but its red-proof suite is new: the suite's first commit is what holds it
ROW fix.late warn lint tests/checks/fix-late-test.sh "its row is old, its red proof is not" >> "$P/standards/naming/controls.tsv"; pc 2026-09-01 "late row"
printf '#!/bin/sh\n[ -z "${LINT_REDLOG:-}" ] || echo fix.late >> "$LINT_REDLOG"\necho "late: 1 passed, 0 failed"\n' > "$P/tests/checks/fix-late-test.sh"; pc 2026-10-10 "late suite"
# the fixture linter: a rule's findings are the records it writes to HARBOR_LINT_FINDINGS_OUT, as lint-conventions does,
# and a rule that ran says so with an R record. doc.refs-conform is the relay key bin/doc-refs.sh's rules share.
cat > "$F/plint.sh" <<'PLINT'
#!/bin/sh
case "$1" in
  --list) printf '  fix.old a\n  fix.edge b\n  fix.young c\n  fix.accepted d\n  fix.open e\n  fix.unproven f\n  fix.blocked g\n  fix.check h\n  fix.late i\n  fix.renamed j\n  fix.oldacc k\n  fix.norun l\n  doc.refs-conform m\n' ;;
  --ids)  printf 'id\tdeprecated\nfix.old\t-\nfix.renamed\tZ9\n' ;;
  *) [ -z "${HARBOR_LINT_FINDINGS_OUT:-${HARBOR_FINDINGS_OUT:-}}" ] || {
       for _r in fix.old fix.edge fix.young fix.accepted fix.open fix.unproven fix.blocked fix.late fix.renamed fix.oldacc doc.refs-conform; do printf 'R\t%s\n' "$_r" >> "${HARBOR_LINT_FINDINGS_OUT:-${HARBOR_FINDINGS_OUT:-}}"; done
       printf 'A\tfix.open\tthe one open subject\n' >> "${HARBOR_LINT_FINDINGS_OUT:-${HARBOR_FINDINGS_OUT:-}}"; } ;;
esac
PLINT
acc() { # <key> <closed> — one accepted-as-false finding in the store
  printf '{"body":"<!-- harbor:finding key=%s digest=x seen=2026-10-01 schema=1 -->","createdAt":"2026-09-01T00:00:00Z","closedAt":"%sT09:00:00Z"}' "$1" "$2"; }
# fix.old also has a finding accepted under another tier's key (check/...), which is not its lint record
ACC="[$(acc lint/fix.accepted 2026-10-10),$(acc lint/Z9 2026-10-10),$(acc lint/doc.refs-conform 2026-10-10),$(acc lint/fix.oldacc 2026-08-20),$(acc check/fix.old 2026-10-12)]"
PRO() { env "$@" sh "$RH" --promotion 2>&1; }
line_of() { printf '%s\n' "$OUT" | awk -v id="$1" '$1 == id'; }
rm -f "$REC"
OUT="$(PRO HARBOR_SCOPE_ROOT="$P" HARBOR_LINT_RULE_HEALTH_LINT="$F/plint.sh" HARBOR_LINT_FINDINGS_REPO=o/r HARBOR_LINT_RULE_HEALTH_NOW=2026-10-14 GH_ACCEPTED="$ACC")"; RC=$?
t_eq "exit 0: the report is not a gate" 0 "$RC"
t_has "a rule red and landed long ago is ready" "$(line_of fix.old)" "ready"
t_eq "and a finding accepted under another tier's key (check/...) is not its record" 0 "$(line_of fix.old | awk '{ print $6 }')"
t_has "a rule landed exactly 28 days ago is ready (the boundary is inclusive)" "$(line_of fix.edge)" "ready"
t_has "a rule landed 27 days ago is not before 2026-10-15" "$(line_of fix.young)" "not before 2026-10-15"
t_has "an accepted-as-false closing on 2026-10-10 restarts the clock: not before 2026-11-07" "$(line_of fix.accepted)" "not before 2026-11-07"
t_eq "and the table shows the one accepted finding" "1" "$(line_of fix.accepted | awk '{ print $6 }')"
t_has "an accepted finding older than the 28 days leaves the rule ready: the clock is the latest date" "$(line_of fix.oldacc)" "ready"
t_eq "and it still shows the one accepted finding" "1" "$(line_of fix.oldacc | awk '{ print $6 }')"
t_has "a finding accepted under a deprecated letter id restarts its successor: not before 2026-11-07" "$(line_of fix.renamed)" "not before 2026-11-07"
t_has "an acceptance on the relay key restarts the rule behind it: not before 2026-11-07" "$(line_of doc.fix)" "not before 2026-11-07"
t_eq "and the table marks that count as the relay key's" "1*" "$(line_of doc.fix | awk '{ print $6 }')"
t_has "and the footer names the key the acceptances are counted on" "$OUT" "lint/doc.refs-conform"
t_has "a rule whose red-proof suite is newer than its row waits for the suite: not before 2026-11-07" "$(line_of fix.late)" "not before 2026-11-07"
t_has "an open finding does not hold a ready rule, but says a block fails until it clears" "$(line_of fix.open)" "ready (1 open: a block fails the run until they clear)"
t_has "a rule the linter did not say it ran is not counted zero: open is - and the verdict says so" "$(line_of fix.norun)" "ready (open findings not counted)"
t_eq "a rule whose engine cannot be run has open - too" "-" "$(line_of doc.fix | awk '{ print $5 }')"
t_has "a rule no passing suite watched red is not ready" "$(line_of fix.unproven)" "not ready: no passing lint suite watched it red"
t_has "a rule whose engine nobody relays has no finding key, so it is not judged" "$(line_of fix.mystery)" "not judged: no finding key for engine bin/lint-mystery.sh"
t_eq "a block-mode row is not a warn rule, so it is not listed" "" "$(line_of fix.blocked)"
t_has "a non-lint warn row is listed with its row age alone, not judged" "$(line_of fix.check)" "28 days elapsed"
t_has "and the heading says why none is judged: no finding counter" "$OUT" "not judged: 1 warn rule(s) that are not lint rules have no finding counter here"
t_has "the summary names the ready count and the earliest date" "$OUT" "5 lint rule(s) ready now; earliest not-before: 2026-10-15"
t_eq "it writes no receipt" no "$([ -f "$REC" ] && echo yes || echo no)"
t_eq "it writes nothing into the tree it judges" "" "$(git -C "$P" status --porcelain)"
OUT="$(PRO HARBOR_SCOPE_ROOT="$P" HARBOR_LINT_RULE_HEALTH_LINT="$F/plint.sh" HARBOR_LINT_FINDINGS_REPO=o/r HARBOR_LINT_RULE_HEALTH_NOW=2026-10-14 GH_FAIL=auth)"; RC=$?
t_eq "a finding store that cannot be read stands the report down (3, D-29 unchecked)" 3 "$RC"
t_has "and says why: no accepted count, so no ready verdict" "$OUT" "could not be read"
t_hasnt "and no rule is called ready" "$OUT" "ready"

t_section "harbor#968 (D-92): a lint-name.sh rule is eligible on a red proof and 0 findings in every governed repo"
# Same fixture tree: the rules below are judged by evidence, not by their age. The fixture name lint prints a
# finding per repo as set by NL_FIND ("<rule>@<repo>:<n>" words); a repo called bad exits 3 (it judged nothing).
mkdir -p "$F/rp/ra" "$F/rp/rb" "$F/rp/rc"; git init -q "$F/rp/ra"; git init -q "$F/rp/rb"; git init -q "$F/rp/rc"
mkdir -p "$F/rp/rn"   # a repo that is not a git checkout
printf 'ra\t%s\nrb\t%s\nrn\t%s\n' "$F/rp/ra" "$F/rp/rb" "$F/rp/rn" > "$F/repos.tsv"
cat > "$F/nlint.sh" <<'NLINT'
#!/bin/sh
while [ $# -gt 0 ]; do case "$1" in --root) R="$2"; shift ;; esac; shift; done
case "$R" in *rc) exit 3 ;; esac
for w in $NL_FIND; do
  case "$w" in *"@$(basename "$R"):"*) n="${w##*:}"; r="${w%%@*}"; i=0; while [ "$i" -lt "$n" ]; do printf 'A\t%s\tsubject-%s\n' "$r" "$i"; i=$((i+1)); done ;; esac
done
exit 0
NLINT
N="$F/ntree"; mkdir -p "$N/standards/naming" "$N/tests/checks"; git init -q "$N"; git -C "$N" symbolic-ref HEAD refs/heads/main
cat > "$N/tests/checks/nm-test.sh" <<'SUITE'
#!/bin/sh
for _r in name.clean name.dirty name.multi name.bothbad; do [ -z "${LINT_REDLOG:-}" ] || printf '%s\n' "$_r" >> "$LINT_REDLOG"; done
echo "nm: 4 passed, 0 failed"
SUITE
{ HDR
  ROW name.clean warn lint tests/checks/nm-test.sh "red, 0 findings everywhere" bin/lint-name.sh
  ROW name.dirty warn lint tests/checks/nm-test.sh "red, findings in ra" bin/lint-name.sh
  ROW name.multi warn lint tests/checks/nm-test.sh "red, findings in two repos" bin/lint-name.sh
  ROW name.unred warn lint tests/checks/nm-test.sh "0 findings but never watched red" bin/lint-name.sh
  ROW name.bothbad warn lint tests/checks/nm-test.sh "red, a finding in rb" bin/lint-name.sh; } > "$N/standards/naming/controls.tsv"
git -C "$N" add -A; git -C "$N" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm seed
printf '#!/bin/sh\ncase "$1" in --list) printf "  name.clean a\n  name.dirty b\n  name.multi c\n  name.unred d\n  name.bothbad e\n" ;; --ids) printf "id\tdeprecated\n" ;; esac\n' > "$F/nl-conv.sh"
NPRO() { env HARBOR_SCOPE_ROOT="$N" HARBOR_LINT_RULE_HEALTH_LINT="$F/nl-conv.sh" HARBOR_LINT_RULE_HEALTH_NAME_LINT="$F/nlint.sh" HARBOR_LINT_RULE_HEALTH_REPOS="$F/repos.tsv" HARBOR_LINT_FINDINGS_REPO=o/r HARBOR_LINT_RULE_HEALTH_NOW=2026-10-28 GH_ACCEPTED="[]" "$@" sh "$RH" --promotion 2>&1; }
OUT="$(NPRO NL_FIND="name.dirty@ra:3 name.multi@ra:1 name.multi@rb:2 name.bothbad@rb:1")"; RC=$?
t_eq "exit 0: still a report" 0 "$RC"
t_eq "red and 0 findings everywhere: eligible, on the day its row landed" "eligible" "$(line_of name.clean | sed 's/.*  //')"
t_has "red but 3 findings in ra: not eligible, names the count and the repo" "$(line_of name.dirty)" "not eligible: 3 findings in ra"
t_hasnt "and it is clean in rb, so rb is not named" "$(line_of name.dirty)" "rb"
t_has "findings in two repos: both named" "$(line_of name.multi)" "1 findings in ra, 2 in rb"
t_has "0 findings but no red proof: not eligible, says so" "$(line_of name.unred)" "not eligible: no red proof"
t_has "red and one finding in rb: not eligible" "$(line_of name.bothbad)" "not eligible: 1 findings in rb"
t_has "a repo that is not a git checkout is skipped and named, never silently" "$OUT" "rn is not a git checkout"
t_has "the footer counts the eligible rules" "$OUT" "1 name rule(s) eligible for block now"
t_eq "it writes nothing into the tree it judges" "" "$(git -C "$N" status --porcelain)"
# the arm that fails the other way: a repo that could not be linted blocks every name rule
printf 'ra\t%s\nrc\t%s\n' "$F/rp/ra" "$F/rp/rc" > "$F/repos2.tsv"
OUT="$(NPRO HARBOR_LINT_RULE_HEALTH_REPOS="$F/repos2.tsv" NL_FIND="")"
t_has "a repo the lint could not judge makes no rule eligible" "$(line_of name.clean)" "not eligible: could not lint rc"
t_eq "and the footer counts none eligible" "yes" "$(printf '%s\n' "$OUT" | grep -q '^0 name rule(s) eligible' && echo yes || echo no)"
OUT="$(NPRO HARBOR_LINT_RULE_HEALTH_REPOS="$F/absent.tsv" NL_FIND="")"; RC=$?
t_eq "an unreadable repo list stands the report down (3)" 3 "$RC"

t_section "the relay table covers every engine of a real warn lint rule, and each key is a registered rule"
# A new engine with no relay would count zero accepted for its rules: it fails here, not in a report.
RELAYS="$(grep '^relays()' "$RH")"
# An engine that is a suite (tests/...) files no finding at all, so it has no key and --promotion says "not judged".
awk -F'\t' '$1 !~ /^#/ && $2 == "warn" && $3 == "lint" && $4 != "bin/lint-conventions.sh" && $4 !~ /^tests\// { print $4 }' "$T_ROOT/standards/naming/controls.tsv" | sort -u > "$F/engines"
t_eq "the real register has engines to check" yes "$([ -s "$F/engines" ] && echo yes || echo no)"
while IFS= read -r _e; do t_has "engine $_e has a finding key in relays()" "$RELAYS" "$_e"; done < "$F/engines"
REGISTERED="$(sh "$T_ROOT/bin/lint-conventions.sh" --list 2>/dev/null | awk '{ print $1 }')"
printf '%s\n' "$RELAYS" | tr -d ';' | tr ' ' '\n' | grep -E '^[a-z]+\.[a-z-]+$' | sort -u > "$F/relay.keys"
t_eq "relays() names its keys" yes "$([ -s "$F/relay.keys" ] && echo yes || echo no)"
while IFS= read -r _k; do t_has "relay key $_k is a rule the linter lists" "$REGISTERED" "$_k"; done < "$F/relay.keys"

t_section "a bad argument is a usage error (2): nothing runs, no receipt, never the 3 of a stood-down run"
rm -f "$REC"
OUT="$(HARBOR_LINT_RULE_HEALTH_SUITES="$F/s2.sh" rh --bogus)"; RC=$?
t_eq "exit 2" 2 "$RC"
t_has "it names the argument" "$OUT" "unknown argument: --bogus"
# contracts/logging.md: a usage error is not a run, so its words go to stderr and it ends with no summary line.
HARBOR_SCOPE_ROOT="$TREE" HARBOR_LINT_RULE_HEALTH_LINT="$F/lint.sh" HARBOR_LINT_FINDINGS_REPO=o/r HARBOR_LINT_RULE_HEALTH_NOW=2026-12-01 sh "$RH" --bogus > "$F/u.out" 2> "$F/u.err"
t_eq "usage leaves stdout empty" "" "$(cat "$F/u.out")"
t_has "...and is said on stderr" "$(cat "$F/u.err")" "unknown argument: --bogus"
t_eq "...with no summary line on either stream, because it is not a run" "" "$(cat "$F/u.out" "$F/u.err" | grep -E '^rule-health: [0-9]+ ok' || :)"
t_eq "no suite ran, so no receipt exists (the failing s2 would have written a stood-down one)" no "$([ -f "$REC" ] && echo yes || echo no)"
OUT="$(HARBOR_LINT_RULE_HEALTH_SUITES="$F/s1.sh" rh)"
t_has "valid: a real run still ends with its summary line" "$OUT" "rule-health: "
OUT="$(rh --help)"; RC=$?
t_eq "valid: --help still exits 0" 0 "$RC"

OUT="$(HARBOR_LINT_RULE_HEALTH_SUITES="$F/s2.sh" rh --promotion --bogus)"; RC=$?
t_eq "--promotion with a second argument is a usage error too" 2 "$RC"

t_done
