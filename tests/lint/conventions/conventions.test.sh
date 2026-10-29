#!/usr/bin/env sh
# lint-conventions.sh (harbor#3), part 1: the linter's own interface — --only, --list, --help and
# every rule running alone (harbor#537) — the guarded_find prune (harbor#658) and X6's fleet walk.
# Parts: tests/checks/lint.<part>-test.sh, all on tests/checks/lint-fixture.sh (harbor#667).
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"

# A fake home with governed repos: one in an excluded tree, one at depth 1, one under a hidden dir.
FH="$TMP/home"
mkdir -p "$FH/Documents/projects/drifted/.agents" "$FH/reachable/.agents" \
         "$FH/Documents/.cache/mirrored/.agents" "$FH/My Docs/spaced/.agents"
cat > "$TMP/fleet-excl.yaml" <<YAML
roots:
  - $FH
projects: []
exclude:
  - Documents
include_plain_repos: false
YAML
cat > "$TMP/fleet-clean.yaml" <<YAML
roots:
  - $FH
  - $FH/Documents/projects
  - $FH/My Docs
exclude:
  - Movies
YAML
cat > "$TMP/fleet-projects.yaml" <<YAML
roots:
  - $FH
projects:
  - $FH/Documents/projects/drifted
  - $FH/My Docs/spaced
exclude:
  - Movies
YAML
cat > "$TMP/fleet-spaced.yaml" <<YAML
roots:
  - $FH
exclude:
  - My Docs
YAML
X6ROOT="$TMP/x6-root"; mkdir -p "$X6ROOT/bin"
X6_CLEAN='every governed repo under a fleet root is reachable'
# Verdict lines only: the rule header prints even with no fleet file, and a bare 'X6' would match it.
x6() { HARBOR_FLEET_FILE="$1" HARBOR_ROOT="$X6ROOT" sh "$LINT" --only X6 2>&1 | grep -E "ADVISORY \[scope.repo-discoverable\]|$X6_CLEAN"; }

t_section "X6: a governed repo the fleet's discovery cannot reach"
OUT="$(x6 "$TMP/fleet-excl.yaml")"
t_has "a repo inside an excluded tree is reported" "$OUT" "cannot reach: $FH/Documents/projects/drifted"
t_has "the count line names how many were unreachable" "$OUT" "2 unreachable"
t_hasnt "a repo at depth 1 under a root stays silent (the path, not the word)" "$OUT" "cannot reach: $FH/reachable"
t_hasnt "a hidden ancestor (cache/mirror copy) is pruned" "$OUT" 'mirrored'
t_has "the excluded-tree fixture does raise an advisory" "$OUT" 'ADVISORY'

t_section "X6: goes green when every repo is reachable"
OUT_CLEAN="$(x6 "$TMP/fleet-clean.yaml")"
t_hasnt "every repo one level under a root raises no advisory" "$OUT_CLEAN" 'ADVISORY'
t_has "…and prints the clean verdict" "$OUT_CLEAN" "$X6_CLEAN"
OUT_PROJ="$(x6 "$TMP/fleet-projects.yaml")"
t_hasnt "a repo listed under projects: is reachable wherever it sits" "$OUT_PROJ" 'ADVISORY'
t_has "…and the projects: fixture prints the clean verdict" "$OUT_PROJ" "$X6_CLEAN"
t_has "an excluded tree whose name has a space is still walked" "$(x6 "$TMP/fleet-spaced.yaml")" \
  "cannot reach: $FH/My Docs/spaced"
t_eq "an absent fleet file says nothing at all (silence, not a clean verdict)" "" "$(x6 "$TMP/does-not-exist.yaml")"
printf 'roots:\n  - %s\nexclude:\n  - reachable\n' "$FH" > "$TMP/fleet-direct.yaml"
t_has "an exclude pattern hides a repo directly under a root" "$(x6 "$TMP/fleet-direct.yaml")" "cannot reach: $FH/reachable"

t_section "X6 is advisory: it cannot fail the gate"
SRCTXT="$(cat "$LINT")"
t_eq "the source does spell a failing rule's call as bad <id> \"…\"" yes \
  "$(nonempty "$(grep -E 'bad [a-z][a-z0-9-]*\.[a-z0-9.-]* "' "$LINT")")"
t_hasnt "X6 never calls bad()" "$SRCTXT" "bad $(lid X6) "

t_section "guarded_find: the folders macOS guards are never walked (harbor#658)"
G5="$TMP/g658"
for _gd in Library Music Pictures Movies Desktop Documents Downloads .Trash; do
  mkdir -p "$G5/$_gd/repo"; : > "$G5/$_gd/repo/marker658"
done
mkdir -p "$G5/plain/repo"; : > "$G5/plain/repo/marker658"
eval "$(sed -n '/^guarded_find() {/,/^}/p' "$LINT")"
_g5="$(HOME="$G5" guarded_find "$G5" 4 -name marker658 -print 2>/dev/null)"
t_has "the control outside the guarded folders is still found" "$_g5" "$G5/plain/repo/marker658"
t_eq "no guarded folder is entered" 1 "$(printf '%s\n' "$_g5" | grep -c marker658)"
t_has "X5 walks through guarded_find" "$SRCTXT" 'guarded_find "$_gr" 4 -path'
t_has "X6 walks through guarded_find" "$SRCTXT" '_x6_found="$(guarded_find "$_r" 4'

# No rule id is written literally below: C9 counts a mention as an arm (harbor#517, #537).
t_section "--only, --list and the dispatcher agree (harbor#537)"
ORT="$TMP/onlyroot"; mkdir -p "$ORT/bin"
_ro_called="$(sed -n 's/^rule "\([A-Za-z0-9._-]*\) .*/\1/p' "$LINT" | sort)"
_ro_defined="$(grep -c '^rule_[A-Za-z0-9_]*() {$' "$LINT" | tr -d ' ')"
t_eq "the source declares rules at all" yes "$(nonempty "$_ro_called")"
t_eq "every rule function declares one id, so the dispatcher runs every function" "$_ro_defined" \
  "$(printf '%s\n' "$_ro_called" | grep -c .)"
t_eq "--ids lists every id the file declares" "$_ro_called" "$(sed 1d "$LINT_IDS" | cut -f1 | sort)"
_ro_id="$(printf '%s\n' "$_ro_called" | head -1)"
_ro_out="$(HARBOR_ROOT="$ORT" sh "$LINT" --only "$_ro_id" 2>&1)"
t_has "--only runs the rule it was given" "$_ro_out" "── $_ro_id "
t_has "--only runs exactly one rule, by the summary line" "$_ro_out" "lint-conventions: 1 rules,"
t_eq "--only prints one rule header" 1 "$(printf '%s\n' "$_ro_out" | grep -c '^── ')"
t_eq "--list lists every rule the file defines" "$_ro_called" \
  "$(sh "$LINT" --list | sed 's/^ *//' | sed -n 's/^\([A-Za-z0-9._-]*\) .*/\1/p' | sort)"

# harbor#957: ids are <family>.<slug>; the letters they replaced are deprecated and still resolve (D-19).
t_section "a deprecated letter id runs its successor, and every letter has one"
_ro_lt="$(awk -F'\t' 'NR > 1 && $2 != "-" { print $2 "\t" $1; exit }' "$LINT_IDS")"
_ro_lo="$(HARBOR_ROOT="$ORT" sh "$LINT" --only "${_ro_lt%%	*}" 2>&1)"
t_has "--only <letter> runs the rule under its successor id" "$_ro_lo" "── ${_ro_lt#*	} "
t_eq "…and runs exactly one rule" 1 "$(printf '%s\n' "$_ro_lo" | grep -c '^── ')"
t_eq "the kill-switch rule's letter resolves to admission.kill-switch-first" "admission.kill-switch-first" "$(lid F1)"
t_eq "every rule born with a letter keeps it as its deprecated id" \
  "$(grep -c '^rule_[A-Z][A-Z]*[0-9][0-9]*[a-z]\{0,1\}() {$' "$LINT" | tr -d ' ')" \
  "$(awk -F'\t' 'NR > 1 && $2 != "-"' "$LINT_IDS" | grep -c .)"
_ro_rl="$TMP/ro.red"; : > "$_ro_rl"
printf '#!/usr/bin/env sh\n# no ticket\n' > "$ORT/bin/zz-noticket.sh"
LINT_REDLOG="$_ro_rl" HARBOR_ROOT="$ORT" sh "$LINT" --only "$(awk -F'\t' '$2 == "S3" { print $1 }' "$LINT_IDS")" > /dev/null 2>&1
t_eq "LINT_REDLOG records the id, never the letter" "$(lid S3)" "$(sort -u "$_ro_rl")"
rm -f "$ORT/bin/zz-noticket.sh"

t_section "a bad invocation is an error, never a clean run of nothing"
_ro_bad="$(HARBOR_ROOT="$ORT" sh "$LINT" --only ZZ9 2>&1)"; _ro_rc=$?
t_eq "--only with an unknown id exits 2" "exit 2" "exit $_ro_rc"
t_hasnt "--only with an unknown id reports no clean result" "$_ro_bad" '0 violations'
t_has "…and names the id it could not find" "$_ro_bad" 'no such rule: ZZ9'
t_exit "--only with no id exits 2" 2 env HARBOR_ROOT="$ORT" sh "$LINT" --only
t_exit "an unknown option exits 2" 2 env HARBOR_ROOT="$ORT" sh "$LINT" --onlt

t_section "--help is answered by running it, not by a matcher over source"
_rh_out="$(sh "$LINT" --help 2>&1)"; _rh_rc=$?
t_eq "--help exits 0" "exit 0" "exit $_rh_rc"
t_has "--help prints usage naming --only" "$_rh_out" '--only <ID>'
t_hasnt "--help prints usage, not a report" "$_rh_out" ' rules, '

t_section "every rule runs alone (harbor#537)"
_RI_FX="$TMP/rule-isolation"
mkdir -p "$_RI_FX/bin" "$_RI_FX/cfg/skills" "$_RI_FX/cfg/bin" "$_RI_FX/contracts" "$_RI_FX/hooks"
printf '#!/usr/bin/env sh\nset -u\necho hi\n' > "$_RI_FX/bin/sample.sh"
_RI_BAD=''; _RI_RAN=0
for _ri_id in $_ro_called; do
  _RI_RAN=$((_RI_RAN + 1))
  _ri_err="$(HARBOR_ROOT="$_RI_FX" CLAUDE_CONFIG_DIR="$_RI_FX/cfg" sh "$LINT" --only "$_ri_id" 2>&1 \
             | grep -E 'unbound variable|command not found|bad substitution|syntax error|parameter not set' | head -1)"
  [ -n "$_ri_err" ] && _RI_BAD="$_RI_BAD $_ri_id"
done
t_eq "no rule reads state an earlier rule set" "" "$_RI_BAD"
t_eq "…asked of every rule the file defines" "$_ro_defined" "$_RI_RAN"

t_done
