#!/usr/bin/env sh
# bin/standard-fleet-names.sh against fixture repos and a stubbed gh (harbor#967, harbor#957): one clean repo, one with a
# bad name, one with a release-title drift. Exit 0 nothing new, 1 something new, 3 nothing judged; the report is the
# delta with ages; a second run with no change reports nothing new; a fix is reported fixed; a receipt reaches the channel.
. "$(dirname "$0")/../../lib/core.sh"; t_init
FX="$T_TMP/fx"; GH="$T_TMP/gh"; REG="$T_TMP/reg.tsv"; CFG="$T_TMP/jobcfg"
mkdir -p "$FX" "$CFG"
mkrepo() { # <name> <slug> <file>
  mkdir -p "$T_TMP/r/$1"; git -C "$T_TMP/r/$1" init -q
  git -C "$T_TMP/r/$1" remote add origin "https://github.com/$2.git"
  printf 'x\n' > "$T_TMP/r/$1/$3"
  git -C "$T_TMP/r/$1" add . && git -C "$T_TMP/r/$1" -c user.name=t -c user.email=t@t commit -qm x
  printf '%s\t%s\n' "$1" "$T_TMP/r/$1" >> "$REG"
}
: > "$REG"
mkrepo clean o/clean README.md
mkrepo bad o/bad Bad_Name.txt
mkrepo drift o/drift README.md
cat > "$GH" <<'STUB'
#!/bin/sh
r="$(printf '%s' "$4" | tr / _)"
case "$*" in
  "release list -R "*" --limit 1000 --json tagName,name,isDraft") cat "$FX/$r.rel" ;;
  "api -H Accept: application/vnd.github.raw repos/"*"/contents/CHANGELOG.md") printf '## [1.0.0]\n' ;;
  *) echo "UNEXPECTED gh call: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$GH"
for s in clean bad; do printf '[{"tagName":"v1.0.0","name":"v1.0.0","isDraft":false}]\n' > "$FX/o_$s.rel"; done
printf '[{"tagName":"v1.0.0","name":"Drift 1.0.0","isDraft":false}]\n' > "$FX/o_drift.rel"
run() { FX="$FX" sh "$T_ROOT/bin/standard-fleet-names.sh" --registry "$REG" --gh "$GH" --config-dir "$CFG" --today "$1" 2>&1; }
code() { FX="$FX" sh "$T_ROOT/bin/standard-fleet-names.sh" --registry "$REG" --gh "$GH" --config-dir "$CFG" --today "$1" >/dev/null 2>&1; echo "exit $?"; }

t_section "the first run reports what is new"
_o="$(run 2026-10-05)"; _c="$(rm -f "$CFG/cache/standard-fleet-names.tsv"; code 2026-10-05)"
t_has "stamped with the check id" "$_o" "[check:standard.fleet-names]"
t_has "the bad name is a finding, under its rule" "$_o" "name.case bad: Bad_Name.txt"
t_has "the title drift is a finding" "$_o" 'release v1.0.0 is titled "Drift 1.0.0"'
t_hasnt "the clean repo is not named" "$_o" "clean:"
t_eq "new findings exit 1" "exit 1" "$_c"

t_section "a second run with no change reports nothing new"
_o="$(run 2026-10-12)"
t_has "nothing new is said" "$_o" "nothing new"
t_has "the standing findings are counted with their age" "$_o" "oldest 7 day(s)"
t_hasnt "…and not listed again" "$_o" "new      "
t_eq "exits 0" "exit 0" "$(code 2026-10-12)"

t_section "the receipt is the findings channel's input"
_r="$CFG/cache/checks/standard.fleet-names.json"
t_has "red, with the subjects" "$(cat "$_r")" '"status":"red"'
t_has "…fresh for a weekly check" "$(cat "$_r")" '"fresh_days":9'
t_has "…naming the bad file" "$(cat "$_r")" "Bad_Name.txt"
t_has "the delta line reached checks.log" "$(cat "$CFG/cache/checks.log")" "[check:standard.fleet-names]"

t_section "a fix is reported fixed, and green"
git -C "$T_TMP/r/bad" mv Bad_Name.txt good-name.txt && git -C "$T_TMP/r/bad" -c user.name=t -c user.email=t@t commit -qam fix
printf '[{"tagName":"v1.0.0","name":"v1.0.0","isDraft":false}]\n' > "$FX/o_drift.rel"
_o="$(run 2026-10-19)"
t_has "fixed is reported" "$_o" "  fixed "
t_has "the name is named as fixed" "$_o" "name.case bad: Bad_Name.txt"
t_has "the title drift is named as fixed" "$_o" "titled \"Drift 1.0.0\""
t_has "the receipt is green" "$(cat "$_r")" '"status":"green"'
t_eq "a fix exits 0" "exit 0" "$(code 2026-10-19)"

t_section "a part that could not be read is never fixed (D-29)"
printf 'ghost\t%s/nowhere\n' "$T_TMP" >> "$REG"
_o="$(run 2026-10-26)"
t_has "the unread repo is named" "$_o" "not judged this run"
printf 'ghost\t%s/nowhere\n' "$T_TMP" > "$T_TMP/only-ghost.tsv"
t_eq "nothing judged is exit 3" "exit 3" "$(FX="$FX" sh "$T_ROOT/bin/standard-fleet-names.sh" --registry "$T_TMP/only-ghost.tsv" --gh "$GH" --config-dir "$T_TMP/c2" >/dev/null 2>&1; echo "exit $?")"
t_eq "an unknown argument is exit 2" "exit 2" "$(sh "$T_ROOT/bin/standard-fleet-names.sh" --nope >/dev/null 2>&1; echo "exit $?")"
t_done
