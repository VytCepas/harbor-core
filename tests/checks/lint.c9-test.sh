#!/usr/bin/env sh
# lint-conventions.sh (harbor#3), part: C9, the rule that counts rules never watched fail (#517).
# C9 reads bin/lint-conventions.sh and the lint suite's parts in tests/checks/ (harbor#667). The
# fixture copies exactly the paths on C9's own _C9_L / _C9_T lines, never a list typed here (#531).
. "$(dirname "$0")/../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
C9MSG='never mentioned in tests/checks/lint*-test.sh'
PID="V""1"  # built, so this part's text is no mention of the rule: only its real arms are
parts() { find "$1/tests/checks" -maxdepth 1 -type f \( -name 'lint-test.sh' -o -name 'lint.*-test.sh' \) | sort; }

t_section "C9 on a copy of what it reads"
C9R="$TMP/c9root"; mkdir -p "$C9R/bin" "$C9R/tests"
_c9files=0
for _c9f in $(sed -n 's/^_C9_[LTD]="\$ROOT\/\(.*\)"$/\1/p' "$LINT"); do
  cp -R "$ROOT/$_c9f" "$C9R/$_c9f" && _c9files=$((_c9files + 1))
done
t_eq "the fixture copied the three paths C9 reads" 3 "$_c9files"
t_eq "…and the copy holds every lint suite part" "$(parts "$ROOT" | wc -l | tr -d ' ')" "$(parts "$C9R" | wc -l | tr -d ' ')"
t_eq "…and this part itself never spells that rule's id" 0 "$(grep -cw "$PID" "$0")"
t_eq "C9 is silent on the real tree: every rule has an arm (the ratchet's baseline is zero)" "" "$(viol C9 "$C9R")"
t_eq "…and the real run is green on C9" "" "$(lint1 C9 "$ROOT" | grep -F 'VIOLATION [lint.rule-has-test]')"

t_section "C9's count moves with what it counts"
for _p in $(parts "$C9R"); do sed "s/$PID/X_$PID/g" "$_p" > "$_p.new" && mv "$_p.new" "$_p"; done
t_eq "the stripped parts mention it nowhere" 0 "$(parts "$C9R" | xargs cat | grep -cw "$PID")"
t_eq "…where the real parts do" yes "$([ "$(parts "$ROOT" | xargs cat | grep -cw "$PID")" -gt 0 ] && echo yes || echo no)"
t_has "…and it is a VIOLATION that names the message" "$(viol C9 "$C9R")" "$C9MSG"
t_eq "C9 names it once every mention is gone from every part, by its id (harbor#957)" 1 \
  "$(viol C9 "$C9R" | tr ' ' '\n' | grep -cxF "$(lid "$PID")")"

t_section "C9 sees a warn-only rule, and reads every part (harbor#625, harbor#667)"
C9W="$TMP/c9warn"; mkdir -p "$C9W/bin" "$C9W/tests/checks"
printf '%s\n' 'rule_ZZ1() {' 'rule "ZZ1 a warn-only probe"' "printf '  ADVISORY [ZZ1] probe\\n'" '}' \
              'rule_ZZ2() {' 'rule "ZZ2 a failing probe"' 'bad ZZ2 "probe"' '}' > "$C9W/bin/lint-conventions.sh"
printf '# ZZ2 has an arm here\n' > "$C9W/tests/checks/lint-test.sh"
_w="$(viol C9 "$C9W")"
t_has "a warn-only rule with no arm is named, of two" "$_w" '[lint.rule-has-test] 1 of 2 rules'
t_eq "…and it is the warn-only one" "yes" "$(hasre "$_w" '\[lint.rule-has-test\] 1 of 2 rules.* ZZ1$')"
printf '# ZZ1 is exercised in this part\n' > "$C9W/tests/checks/lint.more-test.sh"
t_eq "a mention in a lint.<part>-test.sh counts: C9 is silent" "" "$(viol C9 "$C9W")"
rm -f "$C9W/tests/checks/lint.more-test.sh"
printf '# ZZ1 is named in a suite that is not the lint suite\n' > "$C9W/tests/checks/other-test.sh"
t_has "a mention in another suite is not an arm: ZZ1 is still named" "$(viol C9 "$C9W")" ' ZZ1'
t_section "C9 reads tests/lint/ suites by assertion only, never a comment or a fixture (D-14)"
mkdir -p "$C9W/tests/lint/zz/fixtures"
printf '# ZZ1 is only in a comment here\n' > "$C9W/tests/lint/zz/other.test.sh"
t_has "a comment in a tests/lint suite is no arm: ZZ1 is still named" "$(viol C9 "$C9W")" ' ZZ1'
printf 't_section "ZZ1 is asserted here"\n' > "$C9W/tests/lint/zz/fixtures/planted.test.sh"
t_has "a mention under fixtures/ is no arm: ZZ1 is still named" "$(viol C9 "$C9W")" ' ZZ1'
printf 't_section "ZZ1 is asserted here"\n' > "$C9W/tests/lint/zz/real.test.sh"
t_eq "an assertion in a tests/lint suite counts: C9 is silent" "" "$(viol C9 "$C9W")"
rm -rf "$C9W/tests/lint"

t_section "C9 counts a rule's id or its deprecated letter, as a whole token (harbor#957)"
C9I="$TMP/c9ids"; mkdir -p "$C9I/bin" "$C9I/tests/checks"
printf '%s\n' 'rule_QQ7() {' 'rule "drift.qq-probe a rule born with a letter"' '}' \
              'rule_drift_qq() {' 'rule "drift.qq a rule born after the letters"' '}' > "$C9I/bin/lint-conventions.sh"
printf '# lint1 QQ7 and drift.qq are armed here\n' > "$C9I/tests/checks/lint-test.sh"
t_eq "an arm by the deprecated letter and an arm by the id both count" "" "$(viol C9 "$C9I")"
printf '# drift.qq-probe and drift.qq are armed here\n' > "$C9I/tests/checks/lint-test.sh"
t_eq "…and so does an arm by the letter-born rule's id" "" "$(viol C9 "$C9I")"
printf '# only drift.qq-probe is armed here, and drift.qq.x is another id\n' > "$C9I/tests/checks/lint-test.sh"
_ci="$(viol C9 "$C9I")"
t_has "an id inside a longer id is no mention of it" "$_ci" '1 of 2 rules'
t_eq "…and C9 names the rule by its id, never a letter" yes "$(hasre "$_ci" '1 of 2 rules.* drift\.qq$')"
printf '# drift.qq. ends a sentence here, and drift.qq-probe is armed too\n' > "$C9I/tests/checks/lint-test.sh"
t_eq "an id that ends a sentence is still a mention" "" "$(viol C9 "$C9I")"

t_section "the ratchet: a new rule with no arm turns the run red (harbor#577)"
_rr="$(lint1 C9 "$C9W")"; _rrrc=$?
t_has "an unarmed rule is a VIOLATION, not an advisory" "$_rr" 'VIOLATION [lint.rule-has-test] 1 of 2 rules'
t_hasnt "…and no longer an ADVISORY" "$_rr" 'ADVISORY [lint.rule-has-test]'
t_eq "…and it fails the run" "exit 1" "exit $_rrrc"
rm -f "$C9W/tests/checks/lint-test.sh"
_nw="$(lint1 C9 "$C9W")"; _nwrc=$?
t_has "no lint suite part at all is a hard failure" "$_nw" 'VIOLATION [lint.rule-has-test] cannot read the linter or its suite'
t_eq "…and fails the run" "exit 1" "exit $_nwrc"

t_done
