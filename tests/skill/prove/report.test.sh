#!/usr/bin/env sh
# prove (skills/test-strength/bin/prove.sh), part 3: P5 derives every floor from the fixture at test
# time, and P6 pins the report format: the spec's printf strings (F1-F26) are the contract, byte for
# byte. Part 1 is prove-test.sh; fixtures are prove-fixture.sh.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/skills/prove-fixture.sh"
same() { cmp -s "$1" "$2" && echo same || diff -u "$1" "$2" 2>/dev/null | sed -n '1,40p'; }  # <want> <got>
jqe() { jq -e "$1" < "$OUT" >/dev/null 2>&1 && echo yes || echo no; }  # <filter>

t_section "P5 · derived floors: every number computed at test time, never hardcoded"
_prove --list
rc 0 'P5-1 --list exits 0 over a valid target set'
find "$T/targets" -maxdepth 1 -name '*.target' 2>/dev/null | sed -e 's|.*/||' -e 's|\.target$||' | sort > "$T/want-list"
awk 'NF { print $1 }' "$OUT" | sort > "$T/got-list"
t_eq 'P5-2 --list names exactly the *.target files on disk' same "$(same "$T/want-list" "$T/got-list")"
t_eq 'P5-3 at least five fixture targets exist, or P5-2 compares two short lists' yes \
  "$([ "$(wc -l < "$T/want-list" | tr -d ' ')" -ge 5 ] && echo yes || echo no)"
# A class's mutant count derives from the seed, so the denominator grows with the contract.
_prove --explain demo
rc 0 'P5-4 --explain exits 0 on a valid target'
WANT_SEC=$(/usr/bin/grep -c '^## ' "$T/targets/demo/seed.md")
t_eq 'P5-5 the demo seed carries at least two ## headings' yes "$([ "${WANT_SEC:-0}" -ge 2 ] && echo yes || echo no)"
t_eq 'P5-6 --explain lists one section-delete site per ## heading' "$WANT_SEC" \
  "$(/usr/bin/grep -o 'SEC-[0-9][0-9]*' "$OUT" 2>/dev/null | sort -u | wc -l | tr -d ' ')"
# --mutators is the only listing of the library: presence, never exactness, so it may grow.
_prove --mutators
rc 0 'P5-7 --mutators exits 0'
t_eq 'P5-8 --mutators prints the library' nonempty "$([ -s "$OUT" ] && echo nonempty || echo empty)"
for M in section-delete section-hollow heading-demote table-header-rename table-cell-blank \
         table-row-drop date-shift anchor-break codefence-strip \
         comparison-flip threshold-widen threshold-narrow guard-clause-delete \
         exit-neuter negation-drop alternation-drop message-drop; do
  t_eq "P5-9 --mutators lists the v1 mutator $M" yes "$(awk -v n="$M" '$2 == n { f = 1 } END { print (f ? "yes" : "no") }' "$OUT")"
done
t_eq 'P5-10 the library bounds both sides of a threshold' yes \
  "$(awk '$2 == "threshold-widen" { w = 1 } $2 == "threshold-narrow" { n = 1 } END { print ((w && n) ? "yes" : "no") }' "$OUT")"
t_eq 'P5-11 --mutators lists no name that does not exist' no "$(re '(^|[[:space:]])no-such-mutator([[:space:]]|$)')"
t_eq 'P5-12 --mutators carries both subject kinds' yes \
  "$(awk '$1 == "markdown-contract" { a = 1 } $1 == "posix-shell" { b = 1 } END { print ((a && b) ? "yes" : "no") }' "$OUT")"
REALT="$T_ROOT/skills/test-strength/targets"
find "$REALT" -maxdepth 1 -name '*.target' 2>/dev/null | sort > "$T/real-targets"
t_eq 'P5-13 the engine ships at least one *.target' yes "$([ "$(wc -l < "$T/real-targets" | tr -d ' ')" -ge 1 ] && echo yes || echo no)"
while IFS= read -r TF; do
  [ -n "$TF" ] || continue
  TN=$(printf '%s' "$TF" | sed -e 's|.*/||' -e 's|\.target$||')
  PT="$REALT" _prove --explain "$TN"
  rc 0 "P5-14 the shipped target $TN parses under --explain"
  t_eq "P5-15 the shipped target $TN declares a control" yes \
    "$(awk '/^[[:space:]]*control[[:space:]]/ { f = 1 } END { print (f ? "yes" : "no") }' "$TF")"
done <<REALTARGETS
$(cat "$T/real-targets")
REALTARGETS

t_section "P6 · the report format: the pinned printf strings ARE the contract"
# Composed from the pinned format strings rather than transcribed; only the workspace path is normalised.
want_demo() {
  printf 'prove: %s  kind=%s  lane=%s  cost=%ss\n' demo markdown-contract fast 1
  printf '  workspace  %s  (removed on exit; --keep to retain)\n' WORKSPACE
  printf '  seed       %s\n' 'demo/seed.md'
  printf '  place      %s\n' '$WORK/doc.md'
  printf '  checker    %s\n' 'sh $TDIR/demo/check.sh $WORK/doc.md'
  printf '\n'
  printf '  BASELINE   %s\n' GREEN
  printf '  CANARY     %s\n' KILLED
  printf '  CONTROLS   %d/%d green\n' 1 1
  printf '    %-4s %-16s varies=%-10s %s\n' ok C-ODD lexical \
    'a lawful section with an escaped pipe and a diacritic and no table at all'
  printf '\n'
  printf '  GENERATED  %d/%d killed  %d inert  %d no-site  %d capped\n' 2 3 0 1 0
  printf '    %-20s %d/%d killed\n' section-delete 2 2
  printf '    %-20s %d/%d killed\n' date-shift 0 1
  printf '    %-20s no-site — %s\n' anchor-break 'the seed carries no markdown link'
  printf '    SURVIVOR  %-10s %-20s %s\n' DATE-1 date-shift 'all ISO dates +400d'
  printf '      diff   mutants/%s.diff\n' DATE-1
  printf '      rerun  sh skills/test-strength/bin/prove.sh %s --only %s --keep\n' demo DATE-1
  printf '  DECLARED   %d/%d killed\n' 1 1
  printf '  NOTE  %s\n' 'GENERATED and DECLARED do not add and are not comparable. GENERATED'
  printf '  NOTE  %s\n' 'measures the mechanical surface; DECLARED measures only what somebody'
  printf '  NOTE  %s\n' 'thought to write down. The survivor is the finding; the ratio is not.'
  printf '\n'
  printf '  UNPROVEN   %d\n' 1
  printf '    %-10s %s\n' WORLD-1 'the doc names a vendor whose contract ended; no textual mutation says that'
  printf '\n'
  printf '  SCANNERS   %d declared\n' 1
  printf '    %-24s %s\n' prove-absent-scanner 'NOT INSTALLED — no coverage obtained, not a pass'
  printf '\n'
  printf '  VERDICT    %s  exit %d\n' SURVIVORS 1
}
want_overbroad() {
  printf 'prove: %s  kind=%s  lane=%s  cost=%ss\n' overbroad markdown-contract fast 1
  printf '  workspace  %s  (removed on exit; --keep to retain)\n' WORKSPACE
  printf '  seed       %s\n' 'demo/seed.md'
  printf '  place      %s\n' '$WORK/doc.md'
  printf '  checker    %s\n' 'sh $TDIR/demo/overbroad-check.sh $WORK/doc.md'
  printf '\n'
  printf '  BASELINE   %s\n' GREEN
  printf '  CANARY     %s\n' KILLED
  printf '  CONTROLS   %d/%d green\n' 0 1
  printf '    %-4s %-16s varies=%-10s %s\n' RED C-ODD lexical \
    'a lawful section with an escaped pipe and a diacritic and no table at all'
  printf '\n'
  printf '  VERDICT    %s  exit %d\n' CONTROL-RED 3
}
norm() { sed 's|^\(  workspace  \)[^ ]*\(  (removed on exit.*\)$|\1WORKSPACE\2|' "$1"; }
t_eq 'P6-1 no binary named prove-absent-scanner is on PATH, which the scanner contract needs' absent \
  "$(command -v prove-absent-scanner >/dev/null 2>&1 && echo present || echo absent)"
_prove demo
rc 1 'P6-2 demo exits SURVIVORS'
want_demo > "$T/exp-demo"; norm "$OUT" > "$T/got-demo"
t_eq 'P6-3 the demo report matches the pinned format byte for byte' same "$(same "$T/exp-demo" "$T/got-demo")"
t_hasnt 'P6-4 no percentage sign appears in a text report' "$O" '%'
t_eq 'P6-5 GENERATED appears with 3 NOTE lines' 3 "$(/usr/bin/grep -c '^  NOTE  ' "$OUT")"
t_eq 'P6-6 the run printed to stdout' nonempty "$([ -s "$OUT" ] && echo nonempty || echo empty)"
t_eq 'P6-7 a non-usage run writes nothing to stderr' 0 "$(wc -c < "$ERR" | tr -d ' ')"
_prove overbroad
rc 3 'P6-8 overbroad exits CONTROL-RED'
want_overbroad > "$T/exp-ob"; norm "$OUT" > "$T/got-ob"
t_eq 'P6-9 the control-red report matches the pinned format byte for byte' same "$(same "$T/exp-ob" "$T/got-ob")"
# An over-broad rule kills every mutant: a recall figure here would read flawless beside a broken guard.
t_hasnt 'P6-10 a control-red report carries NO GENERATED line' "$O" '  GENERATED'
t_hasnt 'P6-11 and no DECLARED line' "$O" '  DECLARED'
t_hasnt 'P6-12 and no NOTE block, there being no figure to caveat' "$O" '  NOTE  '
t_hasnt 'P6-13 and no percentage' "$O" '%'

# max() proven by order-independence, which one reversed argument can establish.
_prove demo overbroad
rc 3 'P6-14 a multi-target run exits max(), not last'
sed -n '/^=== prove:/,$p' "$OUT" > "$T/got-foot"
{ printf '=== prove: %d targets ===\n' 2
  printf '  %-12s %-16s exit %d\n' demo SURVIVORS 1
  printf '  %-12s %-16s exit %d\n' overbroad CONTROL-RED 3
  printf '  EXIT %d\n' 3
} > "$T/exp-foot"
t_eq 'P6-15 the multi-target footer matches the pinned format' same "$(same "$T/exp-foot" "$T/got-foot")"
_prove overbroad demo
rc 3 'P6-16 the same two targets in the other order still exit 3'
_prove clean demo
rc 1 'P6-17 max(0,1) is 1: a clean target cannot average away a survivor'
_prove demo clean
rc 1 'P6-18 in either order'
_prove clean
rc 0 'P6-19 and clean alone is 0, or P6-17 proves nothing about max'
t_has 'P6-19b and reads PROVEN' "$O" '  VERDICT    PROVEN'
t_hasnt 'P6-20 a single-target run emits no footer block' "$O" '=== prove:'

# --json: the positive keys first, or "no recall key" is met by an empty file.
_prove --json demo
rc 1 'P6-21 --json preserves the exit code'
t_eq 'P6-22 --json emits parseable JSON' yes "$(jqe .)"
t_eq 'P6-23 --json .exit is 1' yes "$(jqe '.exit == 1')"
t_eq 'P6-24 --json verdict is SURVIVORS' yes "$(jqe '.targets[0].verdict == "SURVIVORS"')"
t_eq 'P6-25 --json canary is KILLED' yes "$(jqe '.targets[0].canary == "KILLED"')"
t_eq 'P6-26 --json control count is 1' yes "$(jqe '.targets[0].controls.green == 1')"
t_eq 'P6-27 --json names DATE-1 as the survivor' yes "$(jqe '.targets[0].generated.survivors[0].id == "DATE-1"')"
# The schema has no combined figure at any level, so a dashboard cannot render one without inventing it.
t_eq 'P6-28 --json output contains no recall string' no "$(re '[Rr][Ee][Cc][Aa][Ll][Ll]')"
t_eq 'P6-29 --json root has no recall key' yes "$(jqe 'has("recall") | not')"
t_eq 'P6-30 --json generated has no recall key' yes "$(jqe '.targets[0].generated | has("recall") | not')"
t_hasnt 'P6-31 --json suppresses the text report' "$O" 'kind=markdown-contract'

# --only restricts and never licenses. SEC-1 is a KILLED mutant; a survivor outranks PARTIAL (P6-42).
_prove demo --only SEC-1
rc 0 'P6-32 an --only run exits 0'
t_has 'P6-33 with the PARTIAL verdict' "$O" '  VERDICT    PARTIAL  exit 0'
t_hasnt 'P6-34 and never PROVEN' "$O" '  VERDICT    PROVEN'
t_has 'P6-35 the baseline still ran' "$O" '  BASELINE   GREEN'
t_has 'P6-36 the canary still ran' "$O" '  CANARY     KILLED'
t_has 'P6-37 the controls still ran' "$O" '  CONTROLS   1/1 green'
_prove clean --only SEC-1
rc 0 'P6-38 --only on a fully-killed target still exits 0'
t_hasnt 'P6-39 and still never says PROVEN, because a subset is not a proof' "$O" '  VERDICT    PROVEN'
: > "$T/count"
CNT="$T/count" _prove demo
t_eq 'P6-40 demo invokes the checker 7 times (1 baseline + 1 canary + 1 control + 4 mutants)' 7 "$(wc -l < "$T/count" | tr -d ' ')"
: > "$T/count"
CNT="$T/count" _prove demo --only DATE-1
t_eq 'P6-41 an --only run invokes it 4 times (1 + 1 + 1 control + 1 mutant)' 4 "$(wc -l < "$T/count" | tr -d ' ')"
_prove demo --only DATE-1
rc 1 'P6-42 --only naming a SURVIVOR is SURVIVORS, never laundered into PARTIAL'
t_has 'P6-43 and the survivor is still named' "$O" '    SURVIVOR  DATE-1'
t_hasnt 'P6-44 and the verdict does not read PARTIAL' "$O" '  VERDICT    PARTIAL'
t_done
