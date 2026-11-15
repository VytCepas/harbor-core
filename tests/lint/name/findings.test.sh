#!/usr/bin/env sh
# bin/lint-name.sh (harbor#950), part: the N4 relay into lint-conventions, --list, --format findings, an env rename's window,
# --changed and the exit codes. Split from tests/lint/name/name.test.sh at the 500-line budget (tests/README.md T2); the fixture
# tree comes from tests/lint/name/fixture.sh.
. "$(dirname "$0")/../../lib/core.sh"; t_init
# the suite never reads the box's private overlay (D-85)
HARBOR_SCOPE_PRIVATE="$TMP/no-private"; export HARBOR_SCOPE_PRIVATE; unset PORT_ROOT
HARBOR_LINT_TODAY=2026-10-20; export HARBOR_LINT_TODAY
. "$T_ROOT/tests/checks/lint-fixture.sh"
LN="$T_ROOT/bin/lint-name.sh"
REG="$T_ROOT/standards/naming"
rules() { awk -F'\t' '/^#/ || !h++ { next } $3 == "lint" && $4 == "bin/lint-name.sh" { print $1 }' "$1/controls.tsv"; }
. "$T_ROOT/tests/lint/name/fixture.sh"
t_section "N4 relays the lint into lint-conventions"
N="$TMP/n4"; mini "$N"; mkdir -p "$N/docs"
t_eq "a clean tree has no N4 advisory" "" "$(advs N4 "$N")"
t_has "…and says it judged" "$(lint1 N4 "$N")" "lint-name:"
: > "$N/docs/Bad_Name.md"
_a="$(advs N4 "$N")"
t_has "a new bad name is an N4 advisory" "$_a" "ADVISORY [standard.names-conform] [name.case] docs/Bad_Name.md"
t_has "…naming the separator rule too" "$_a" "[name.separator] docs/Bad_Name.md"
t_eq "…and an advisory is not a violation" "" "$(viol N4 "$N")"
_fo="$TMP/n4.findings"; : > "$_fo"
HARBOR_SCOPE_ROOT="$N" HARBOR_LINT_FINDINGS_OUT="$_fo" sh "$LINT" --only N4 > /dev/null 2>&1
t_has "…and its finding record carries the path as subject" "$(cat "$_fo")" "$(printf 'A\tstandard.names-conform\tdocs/Bad_Name.md')"
_nr="$TMP/n4.red"; : > "$_nr"
HARBOR_SCOPE_ROOT="$N" LINT_REDLOG="$_nr" sh "$LINT" --only N4 > /dev/null 2>&1
t_has "…and LINT_REDLOG carries each finding's own rule id" "$(sort -u "$_nr")" "name.case"
t_eq "…and never N4 for a naming finding, so each rule has its own record" "" "$(grep -x "$(lid N4)" "$_nr")"
rm "$N/standards/naming/terms.tsv"
t_has "a registry that cannot be read is a VIOLATION, never clean" "$(viol N4 "$N")" "judged nothing"
: > "$_nr"; HARBOR_SCOPE_ROOT="$N" LINT_REDLOG="$_nr" sh "$LINT" --only N4 > /dev/null 2>&1
t_has "…and that is when N4 itself is red in LINT_REDLOG, by its id" "$(cat "$_nr")" "$(lid N4)"
rm "$N/bin/lint-name.sh"
t_has "no lint at all is a VIOLATION" "$(viol N4 "$N")" "no bin/lint-name.sh"

t_section "bin/lint-conventions.sh's ids share --list and the rule-id surface (harbor#957)"
_ls="$(sh "$LN" --list)"
t_eq "--list holds no id twice" "" "$(printf '%s\n' "$_ls" | awk '{ print $1 }' | sort | uniq -d)"
t_has "…and lists bin/lint-conventions.sh's ids" "$_ls" "admission.kill-switch-first"
t_has "…beside controls.tsv's" "$_ls" "name.case"
t_eq "…every one of them" "$(($(rules "$REG" | grep -c .) + $(grep -c '^rule "' "$LINT")))" "$(printf '%s\n' "$_ls" | grep -c .)"
LC="$TMP/lcids"; mini "$LC"
printf 'rule_F1() {\nrule "admission.golden-first a fixture rule"\n}\n' > "$LC/bin/lint-conventions.sh"
t_has "a lint-conventions id is judged as a rule-id name, read and never run" \
  "$(sh "$LC/bin/lint-name.sh" --root "$LC" 2>&1)" "[name.alias] rule-id:admission.golden-first"
printf 'rule_F1() {\nrule "admission.kill-switch-first a fixture rule"\n}\n' > "$LC/bin/lint-conventions.sh"
_lcg="$(sh "$LC/bin/lint-name.sh" --root "$LC" 2>&1)"
t_hasnt "…and a good one is not" "$_lcg" "rule-id:admission"
t_has "positive control: that run judged the tree" "$_lcg" "lint-name:"

t_section "--format findings is the kind TAB id TAB subject record"
F="$TMP/fmt"; mini "$F"; mkdir -p "$F/docs" "$F/bin"; : > "$F/docs/Notes.md"
# the real helm row retired with its window, so a synthetic legacy prefix stands in for it
printf 'xoldpfx\tplatform\tlegacy\tglossary\t2099-01-01\ta fixture legacy prefix\n' >> "$F/standards/naming/aliases.tsv"
printf '#!/usr/bin/env sh\nXOLDPFX_PROBE_FIXTURE=1 sh x\n' > "$F/bin/probe.sh"
_ff="$(sh "$F/bin/lint-name.sh" --root "$F" --format findings 2>/dev/null)"
t_eq "every record is A TAB name.<rule> TAB subject" "" "$(printf '%s\n' "$_ff" | grep -vE "^A	name\.[a-z-]+	[^	]+$")"
t_has "a bad path is a record" "$_ff" "$(printf 'A\tname.case\tdocs/Notes.md')"
t_has "an env name read from code is a record" "$_ff" "$(printf 'A\tname.env\tenv:XOLDPFX_PROBE_FIXTURE')"
t_has "…and its legacy prefix is an alias finding" "$_ff" "$(printf 'A\tname.alias\tenv:XOLDPFX_PROBE_FIXTURE')"

t_section "an env rename's dual-read window exempts the old name until remove_by (harbor#961 W5)"
# The names are built from pieces, so this suite's own source holds no env token for the tree lint to judge.
H=HARBOR; WO="${H}_WINDOWPROBE_X"; WN="${H}_TEST_WINDOW_PROBE"; WP="${H}_WINDOWPROBE_Y"
W="$TMP/window"; mini "$W"
printf '#!/usr/bin/env sh\nx="${%s:-${%s:-}}"\n' "$WN" "$WO" > "$W/bin/window-probe.sh"
_w0="$(sh "$W/bin/lint-name.sh" --root "$W" --today 2026-11-01 2>&1)"
t_has "control: with no row the old name is a finding" "$_w0" "[name.env] env:$WO"
t_hasnt "…and the new one is not" "$_w0" "env:$WN"
printf 'rename-9999\tenv:%s\tenv:%s\tenv\tW5\t2026-11-15\ta fixture window\n' "$WO" "$WN" >> "$W/standards/naming/renames.tsv"
t_hasnt "an open window exempts the old name" "$(sh "$W/bin/lint-name.sh" --root "$W" --today 2026-11-15 2>&1)" "env:$WO"
t_has "…and a window past its date does not" "$(sh "$W/bin/lint-name.sh" --root "$W" --today 2026-11-16 2>&1)" "[name.env] env:$WO"
t_has "…nor does --check, which judges a name at its birth" "$(sh "$W/bin/lint-name.sh" --root "$W" --today 2026-11-01 --check env "$WO" 2>&1)" "name.env"
printf 'rename-9998\tenv:%s\tenv:%s_PLAIN\tenv\tW5\t-\ta plain rename\n' "$WP" "$WN" >> "$W/standards/naming/renames.tsv"
printf 'y="${%s:-}"\n' "$WP" >> "$W/bin/window-probe.sh"
t_has "a plain rename (no remove_by) opens no window" "$(sh "$W/bin/lint-name.sh" --root "$W" --today 2026-11-01 2>&1)" "[name.env] env:$WP"

t_section "--changed judges only what a branch adds"
G="$TMP/git"; mini "$G"; : > "$G/Legacy_Old.md"
git -C "$G" init -q -b main && git -C "$G" add -A \
  && git -C "$G" -c user.email=t@example.invalid -c user.name=t commit -q -m base
: > "$G/New_Bad.md"
_ch="$(sh "$G/bin/lint-name.sh" --root "$G" --base main --changed 2>&1)"
t_has "a new bad name is judged" "$_ch" "[name.case] New_Bad.md"
t_hasnt "…and the legacy one beside it is not" "$_ch" "Legacy_Old.md"
t_has "the whole-tree run does see the legacy one" "$(sh "$G/bin/lint-name.sh" --root "$G" 2>&1)" "[name.case] Legacy_Old.md"
t_exit "--changed with no base to diff against is unchecked, not clean" 3 sh "$G/bin/lint-name.sh" --root "$G" --base no-such-ref --changed

t_section "exit codes (D-49): usage 2, unchecked 3"
t_exit "an unknown flag is usage" 2 sh "$LN" --bogus
t_exit "an unknown --check surface is usage" 2 sh "$LN" --check no-such-surface x
X="$TMP/noreg"; mkdir -p "$X"
t_exit "a missing registry is unchecked" 3 sh "$LN" --root "$X"
B="$TMP/block"; mini "$B"
awk -F'\t' 'BEGIN { OFS = "\t" } $1 == "name.case" { $2 = "block" } { print }' "$B/standards/naming/controls.tsv" > "$TMP/rules.block"
mv "$TMP/rules.block" "$B/standards/naming/controls.tsv"
t_exit "a block-level finding exits 1" 1 sh "$B/bin/lint-name.sh" --root "$B" --check path Notes.md
t_exit "…and an advisory one exits 0" 0 sh "$LN" --check path Notes.md
t_done
