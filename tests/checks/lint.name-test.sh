#!/usr/bin/env sh
# lint-conventions.sh (harbor#3), part: N4 and bin/lint-name.sh, the naming registry's own lint (harbor#950).
# Its fixtures are fixtures/naming/; every red here is read from LINT_REDLOG or the lint's own output,
# never from the fixture text. The suite path is the harness's (C9 reads tests/checks/lint*-test.sh).
. "$(dirname "$0")/../lib/core.sh"; t_init
# the suite never reads the box's private overlay (D-85)
HARBOR_SCOPE_PRIVATE="$TMP/no-private"; export HARBOR_SCOPE_PRIVATE; unset PORT_ROOT
. "$T_ROOT/tests/checks/lint-fixture.sh"
LN="$T_ROOT/bin/lint-name.sh"
REG="$T_ROOT/standards/naming"
# the rules are the controls this lint evaluates: type lint, engine bin/lint-name.sh (the module.* rows are bin/lint-module.sh's, and module.family-shape has no engine yet)
rules() { awk -F'\t' '/^#/ || !h++ { next } $3 == "lint" && $4 == "bin/lint-name.sh" { print $1 }' "$1/controls.tsv"; }
. "$T_ROOT/tests/checks/lint.name-fixture.sh"   # mini <dir>

t_section "--self-test: every fail fixture goes red and every pass stays green"
_red="$TMP/self.red"; : > "$_red"
_st="$(LINT_REDLOG="$_red" sh "$LN" --self-test 2>&1)"; _strc=$?
t_eq "--self-test exits 0 on the real registry and fixtures" "exit 0" "exit $_strc"
t_has "…and says every rule went red in this run" "$_st" "every rule in controls.tsv went red at least once"
t_has "…and on every surface each rule declares" "$_st" "every rule went red on every surface it declares"
t_hasnt "…and no fixture failed" "$_st" "  FAIL:"
_never=""
for _r in $(rules "$REG"); do grep -qx -- "$_r" "$_red" || _never="$_never $_r"; done
t_eq "every rule in controls.tsv is in the caller's LINT_REDLOG" "" "$_never"
t_eq "…and the red log holds nothing that is not a rule" "" "$(sort -u "$_red" | grep -vxF "$(rules "$REG")")"

t_section "a mutated renderer goes red: the self-test fails when name.case stops judging"
M="$TMP/mutant"; mini "$M"
sed 's|if (seg ~ /\[A-Z\]/) emit("name.case"|if (0) emit("name.case"|' "$LN" > "$M/bin/lint-name.sh"
t_eq "the mutation changed exactly one line" 1 "$(diff "$LN" "$M/bin/lint-name.sh" | grep -c '^>')"
_mo="$(sh "$M/bin/lint-name.sh" --self-test 2>&1)"; _morc=$?
t_eq "the mutant's self-test exits 1" "exit 1" "exit $_morc"
t_has "…naming the fail fixture that stayed green" "$_mo" "did not go red on name.case"
t_has "…and the rule that never went red" "$_mo" "never went red in this self-test: name.case"
t_eq "the unmutated copy passes the same self-test" "exit 0" "exit $(sh "$LN" --root "$M" --self-test > /dev/null 2>&1; echo $?)"

t_section "the self-test refuses a rule with no fail fixture"
U="$TMP/uncovered"; mini "$U"
printf 'name.ghost-rule\twarn\tlint\tbin/lint-name.sh\tpath\tci\tdetective\texperimental\t-\tstandard\t-\t-\ta rule no fixture exercises\n' >> "$U/standards/naming/controls.tsv"
_uo="$(sh "$U/bin/lint-name.sh" --self-test 2>&1)"; _uorc=$?
t_eq "an uncovered rule fails the self-test" "exit 1" "exit $_uorc"
t_has "…and is named" "$_uo" "never went red in this self-test: name.ghost-rule"

t_section "the self-test refuses a declared surface no fixture turns red (21 of 57 pairs, harbor#950)"
P="$TMP/pair"; mini "$P"
grep -v '^docs/Reports	' "$P/fixtures/naming/directory/fail/expect.tsv" > "$TMP/dir.fail"
mv "$TMP/dir.fail" "$P/fixtures/naming/directory/fail/expect.tsv"
t_eq "the cut removed exactly the one name.case row on directory" 1 \
  "$(diff "$T_ROOT/fixtures/naming/directory/fail/expect.tsv" "$P/fixtures/naming/directory/fail/expect.tsv" | grep -c '^<')"
_po="$(sh "$P/bin/lint-name.sh" --root "$P" --self-test 2>&1)"; _porc=$?
t_eq "a rule red on four of its five surfaces fails the self-test" "exit 1" "exit $_porc"
t_has "…naming the pair" "$_po" "a declared surface never went red: name.case on directory"
t_hasnt "…while the rule itself still went red somewhere" "$_po" "never went red in this self-test: name.case"
t_eq "the uncut copy passes the same self-test" "exit 0" "exit $(sh "$LN" --root "$M" --self-test > /dev/null 2>&1; echo $?)"

t_section "mode (D-29, D-64): shadow records, warn prints, advisory is an alias of warn"
W="$TMP/mode"; mini "$W"
awk -F'\t' 'BEGIN { OFS = "\t" } $1 == "name.case" { $2 = "shadow" } $1 == "name.separator" { $2 = "advisory" } { print }' \
  "$W/standards/naming/controls.tsv" > "$TMP/rules.mode"; mv "$TMP/rules.mode" "$W/standards/naming/controls.tsv"
_wr="$TMP/mode.red"; : > "$_wr"
_wo="$(LINT_REDLOG="$_wr" sh "$W/bin/lint-name.sh" --root "$W" --check path docs/Bad_Name.md 2>&1)"; _worc=$?
t_eq "a shadow finding does not fail the run" "exit 0" "exit $_worc"
t_hasnt "…and is not printed" "$_wo" "[name.case]"
t_has "…but is counted" "$_wo" "1 shadow finding(s) recorded"
t_has "…and is red in LINT_REDLOG under its own id" "$(cat "$_wr")" "name.case"
t_has "an advisory row prints as warn" "$_wo" "WARN: [name.separator] docs/Bad_Name.md"
t_hasnt "…and is not a control-shape finding" "$(sh "$W/bin/lint-name.sh" --root "$W" --check registry standards/naming 2>&1)" "is not shadow, warn or block"
awk -F'\t' 'BEGIN { OFS = "\t" } $1 == "name.case" { $2 = "strict" } { print }' "$W/standards/naming/controls.tsv" > "$TMP/rules.mode"
mv "$TMP/rules.mode" "$W/standards/naming/controls.tsv"
t_has "a mode outside the closed set is a control-shape finding" \
  "$(sh "$W/bin/lint-name.sh" --root "$W" --check registry standards/naming 2>&1)" "mode \`strict\` is not shadow, warn or block"
t_eq "harbor's controls.tsv uses no legacy mode word" "" "$(awk -F'\t' '/^#/ || !h++ { next } $2 != "shadow" && $2 != "warn" && $2 != "block"' "$REG/controls.tsv")"

t_section "the grammar is surfaces.tsv's, not the lint's (harbor#950, 09a S6)"
t_eq "--render builds a bin name from a tuple" "admission-bash.sh" "$(sh "$LN" --render bin family=admission object=bash ext=sh)"
t_eq "…with the optional verb when one is given" "admission-bash-install.sh" "$(sh "$LN" --render bin family=admission object=bash verb=install ext=sh)"
t_eq "…the bare family, which is a family's default action (D-13)" "worktree.sh" "$(sh "$LN" --render bin family=worktree ext=sh)"
t_eq "…an env name in capitals, a hyphenated system joined by _" "MEMORY_STORE_DRIFT_X_Y" "$(sh "$LN" --render env repo=memory-store family=drift name=x-y)"
t_eq "…a test path" "tests/drift/undeployed/install.test.sh" "$(sh "$LN" --render test family=drift subject=undeployed aspect=install ext=sh)"
t_eq "--parse reads a name back into its slots" "family=admission object=bash verb=install ext=sh" "$(sh "$LN" --parse bin admission-bash-install.sh | tr '\n' ' ' | sed 's/ $//')"
t_eq "…and an env name's tuple is the one the bin name gave, joiner aside" "repo=memory-store family=drift name=x-y" "$(sh "$LN" --parse env MEMORY_STORE_DRIFT_X_Y | tr '\n' ' ' | sed 's/ $//')"
for _t in "bin family=audit object=triage-load verb=run ext=sh" "skill family-or-domain=tracking object=standards" "skill family-or-domain=product" \
          "launchd system=harbor family=audit object=triage ext=x" "env repo=harbor family=admission name=disable" "test family=lint subject=name aspect=load ext=sh"; do
  _sf="${_t%% *}"; _kv="${_t#* }"
  # shellcheck disable=SC2086 # the slots are separate words by construction
  _n="$(sh "$LN" --render "$_sf" $_kv 2>/dev/null)"
  # shellcheck disable=SC2086
  _back="$(sh "$LN" --parse "$_sf" "$_n" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
  _want="$(printf '%s\n' $_kv | tr '\n' ' ' | sed 's/ $//')"
  case "$_sf" in launchd) _want="$(printf '%s' "$_want" | sed 's/ ext=x//')" ;; esac
  case "$_sf" in env) _want="$(printf '%s' "$_want" | sed 's/^repo=/repo=/')" ;; esac
  t_eq "parse(render(t)) == t on $_sf: $_n" "$_want" "$_back"
done
t_exit "--render with a missing slot is refused" 1 sh "$LN" --render bin object=bash ext=sh
t_exit "--parse of a name the grammar does not parse is refused" 1 sh "$LN" --parse bin bash-admission.sh
t_exit "--render of a surface with no grammar is refused" 1 sh "$LN" --render path family=audit
SW="$TMP/swap"; mini "$SW"
awk -F'\t' 'BEGIN { OFS = "\t" } $1 == "bin" { $2 = "<object>-<family>" } { print }' "$REG/surfaces.tsv" > "$SW/standards/naming/surfaces.tsv"
t_eq "the swap changed exactly the bin row" 1 "$(diff "$REG/surfaces.tsv" "$SW/standards/naming/surfaces.tsv" | grep -c '^>')"
sh "$SW/bin/lint-name.sh" --root "$SW" --self-test > "$TMP/swap.out" 2>&1; _swrc=$?
t_eq "with bin = <object>-<family>, --self-test exits 1" "exit 1" "exit $_swrc"
t_has "…because the pass fixtures of bin went red" "$(cat "$TMP/swap.out")" "bin/pass: admission-bash.sh went red on name.family"
t_has "…and the round trip says why" "$(cat "$TMP/swap.out")" "grammar bin:"
cp "$REG/surfaces.tsv" "$SW/standards/naming/surfaces.tsv"
t_eq "restored, the same copy's self-test exits 0" "exit 0" "exit $(sh "$SW/bin/lint-name.sh" --root "$SW" --self-test > /dev/null 2>&1; echo $?)"
RT="$TMP/roundtrip"; mini "$RT"
awk -F'\t' 'BEGIN { OFS = "\t" } $1 == "skill" { $5 = "Tracking-Standards" } { print }' "$REG/surfaces.tsv" > "$RT/standards/naming/surfaces.tsv"
_rto="$(sh "$RT/bin/lint-name.sh" --root "$RT" --self-test 2>&1)"; _rtrc=$?
t_eq "an example that parse then render does not give back fails the self-test" "exit 1" "exit $_rtrc"
t_has "…naming the render" "$_rto" "grammar skill: render(parse(\`Tracking-Standards\`)) is \`tracking-standards\`"
awk -F'\t' 'BEGIN { OFS = "\t" } $1 == "test" { $5 = "tests/drift/undeployed/test_install.py" } { print }' "$REG/surfaces.tsv" > "$RT/standards/naming/surfaces.tsv"
_rto="$(sh "$RT/bin/lint-name.sh" --root "$RT" --self-test 2>&1)"
t_has "an example the grammar cannot parse fails it too, though --check accepts the name (D-14)" "$_rto" "grammar test: the example \`tests/drift/undeployed/test_install.py\` does not parse"
t_has "…though --check does accept that name" "$(sh "$LN" --check test tests/drift/undeployed/test_install.py 2>&1)" "no finding"
BG="$TMP/badgrammar"; mini "$BG"
awk -F'\t' 'BEGIN { OFS = "\t" } $1 == "bin" { $2 = "<family>-<widget>.<ext>" } { print }' "$REG/surfaces.tsv" > "$BG/standards/naming/surfaces.tsv"
t_has "a renderer with a slot that is not a slot is a name.surface-grammar finding" \
  "$(sh "$BG/bin/lint-name.sh" --root "$BG" --check registry standards/naming 2>&1)" "[name.surface-grammar] surface:bin"

t_section "the six registers: controls, kinds, registers (harbor#950 PR 2)"
R2="$TMP/regs"; mini "$R2"
reg() { sh "$R2/bin/lint-name.sh" --root "$R2" --check registry standards/naming 2>&1; }
t_has "the copy of the real registry has no finding" "$(reg)" "no finding"
cell() { # <column> <value> → the finding text with that cell of the name.case control replaced
  awk -F'\t' -v c="$1" -v v="$2" 'BEGIN { OFS = "\t" } $1 == "name.case" { $c = v } { print }' "$REG/controls.tsv" > "$R2/standards/naming/controls.tsv"
  diff "$REG/controls.tsv" "$R2/standards/naming/controls.tsv" | grep -c '^>' >> "$TMP/cell.diffs"
  reg; cp "$REG/controls.tsv" "$R2/standards/naming/controls.tsv"
}
: > "$TMP/cell.diffs"
t_has "a mode outside the set" "$(cell 2 strict)" "mode \`strict\` is not shadow, warn or block"
t_has "a type that is not a control-type term" "$(cell 3 gadget)" "type \`gadget\` is not a control-type term"
t_has "an engine that is not in the tree" "$(cell 4 bin/nope.sh)" "engine \`bin/nope.sh\` is not in the tree"
t_has "a surface that is not a row of surfaces.tsv" "$(cell 5 nope)" "surface \`nope\` is not a row of surfaces.tsv"
t_has "a moment that is not a term" "$(cell 6 sometime)" "moment \`sometime\` is not a moment term"
t_has "a function that is not a term" "$(cell 7 beforehand)" "function \`beforehand\` is not a function term"
t_has "a stability outside the set" "$(cell 8 eternal)" "stability \`eternal\` is not experimental, stable or deprecated"
t_has "a successor that is not a control" "$(cell 9 name.nowhere)" "successor \`name.nowhere\` is not a control"
t_has "an owner that is not a family" "$(cell 10 widget)" "owner \`widget\` is not a registered family"
t_has "a red proof that is not in the tree" "$(cell 11 tests/nope.sh)" "red_proof \`tests/nope.sh\` is not in the tree"
t_eq "…and each of those edits changed exactly one row" 1 "$(sort -u "$TMP/cell.diffs" | tr '\n' ' ' | sed 's/ $//')"
t_eq "…and there were ten of them" 10 "$(grep -c . "$TMP/cell.diffs")"
t_has "a legacy mode spelling is read as warn, not refused" \
  "$(awk -F'\t' 'BEGIN { OFS = "\t" } $1 == "name.case" { $2 = "advisory" } { print }' "$REG/controls.tsv" > "$R2/standards/naming/controls.tsv"; reg; cp "$REG/controls.tsv" "$R2/standards/naming/controls.tsv")" "no finding"
for _k in memory-store policy skill check; do
  grep -v "^$_k	" "$REG/kinds.tsv" > "$R2/standards/naming/kinds.tsv"
  t_has "a kind term with no kinds.tsv row is a finding: $_k" "$(reg)" "the kind term \`$_k\` has no row in kinds.tsv"
done
cp "$REG/kinds.tsv" "$R2/standards/naming/kinds.tsv"
awk -F'\t' 'BEGIN { OFS = "\t" } $1 == "script" { $6 = "basement" } { print }' "$REG/kinds.tsv" > "$R2/standards/naming/kinds.tsv"
t_has "a kind whose layer is not a layer term is a finding" "$(reg)" "layer \`basement\` is not a layer term"
cp "$REG/kinds.tsv" "$R2/standards/naming/kinds.tsv"
for _t in lint admission check injection ci vale; do
  grep -v "^$_t	" "$REG/registers.tsv" > "$R2/standards/naming/registers.tsv"
  t_has "a control type with no register is a finding: $_t" "$(reg)" "has no \`$_t\` register"
done
cp "$REG/registers.tsv" "$R2/standards/naming/registers.tsv"
t_eq "memory-store is a kind, with its own folder" "memory-store/" "$(awk -F'\t' '$1 == "memory-store" { print $2 }' "$REG/kinds.tsv")"

t_section "registers.tsv lists every register file, and the lint reads its file list from it (harbor#950)"
t_eq "every standards/naming/*.tsv is named by a registers.tsv row" "" \
  "$(for _f in "$REG"/*.tsv; do awk -F'\t' -v b="${_f##*/}" '/^#/ || !h++ { next } $2 == b { f = 1 } END { if (!f) print b }' "$REG/registers.tsv"; done)"
t_eq "…renames, repo-kinds and dialects, which the lint used to list by hand, among them" "dialect=dialects.tsv rename=renames.tsv repo-kind=repo-kinds.tsv" \
  "$(awk -F'\t' '$1 == "rename" || $1 == "repo-kind" || $1 == "dialect" { print $1 "=" $2 }' "$REG/registers.tsv" | sort | tr '\n' ' ' | sed 's/ $//')"
t_eq "bin/lint-name.sh holds no hand-written file list" 0 "$(grep -c "^FILES='" "$LN")"
t_eq "the guard loop names exactly the files the judge has a handler for: a new handler cannot be left out of it" \
  "$(grep -o 'sh == "[a-z-]*\.tsv"' "$LN" | sed 's/^sh == "//; s/"$//' | LC_ALL=C sort -u | tr '\n' ' ')" \
  "$(sed -n 's/^for _f in \(.*\.tsv\); do$/\1/p' "$LN" | tr ' ' '\n' | LC_ALL=C sort -u | tr '\n' ' ')"
DL="$TMP/droprow"; mini "$DL"
dl() { sh "$DL/bin/lint-name.sh" --root "$DL" "$@" 2>&1; }
t_has "positive control: the copy's registry is clean" "$(dl --check registry standards/naming)" "no finding"
grep -v '^dialect	' "$REG/registers.tsv" > "$DL/standards/naming/registers.tsv"
t_eq "the cut removed exactly the dialect row" 1 "$(diff "$REG/registers.tsv" "$DL/standards/naming/registers.tsv" | grep -c '^<')"
t_has "a register file whose row is deleted is reported, not silently unread" "$(dl --check registry standards/naming)" \
  "[name.registry-shape] register-file:dialects.tsv — \`dialects.tsv\` is in the registry and registers.tsv has no row naming it"
t_has "…and by the whole-tree run" "$(dl)" "register-file:dialects.tsv"
t_exit "…as a warning, so the run still exits 0" 0 sh "$DL/bin/lint-name.sh" --root "$DL" --check registry standards/naming
grep -v '^alias	' "$REG/registers.tsv" > "$DL/standards/naming/registers.tsv"
t_exit "a registers.tsv that stops naming a file the judge has a handler for is UNCHECKED, never clean" 3 sh "$DL/bin/lint-name.sh" --root "$DL" --check path docs/notes.md
t_has "…and says which file" "$(dl --check path docs/notes.md)" "registers.tsv has no row naming aliases.tsv"
cp "$REG/registers.tsv" "$DL/standards/naming/registers.tsv"
t_has "restored, the same copy is clean again" "$(dl --check registry standards/naming)" "no finding"
printf 'phantom\tphantom.tsv\t-\t-\ta row whose file is not there\n' >> "$DL/standards/naming/registers.tsv"
t_exit "a row naming a file that does not exist is UNCHECKED: the lint cannot read what the registry says it holds" 3 sh "$DL/bin/lint-name.sh" --root "$DL" --check path docs/notes.md
printf 'phantom\t../terms.tsv\t-\t-\ta file outside the registry\n' > "$TMP/phantom.row"
cp "$REG/registers.tsv" "$DL/standards/naming/registers.tsv"; cat "$TMP/phantom.row" >> "$DL/standards/naming/registers.tsv"
t_has "a row whose file is not a bare registry file name is a shape finding, and the path is not followed" "$(dl --check registry standards/naming)" \
  "[name.registry-shape] register:phantom — file \`../terms.tsv\` is not the name of a registry file"
cp "$REG/registers.tsv" "$DL/standards/naming/registers.tsv"
RO="$TMP/reorder"; mini "$RO"
awk 'BEGIN { FS = "\t" } /^#/ { print; next } !h++ { print; next } { r[++n] = $0 } END { for (i = n; i >= 1; i--) print r[i] }' "$REG/registers.tsv" > "$RO/standards/naming/registers.tsv"
t_eq "the reordered registers.tsv holds the same rows" "$(sort "$REG/registers.tsv")" "$(sort "$RO/standards/naming/registers.tsv")"
t_eq "…and its first row is no longer term" "no" "$(awk -F'\t' '/^#/ || !h++ { next } { print ($1 == "term") ? "yes" : "no"; exit }' "$RO/standards/naming/registers.tsv")"
t_has "valid but unusual: with the rows reversed (controls first, kinds before surfaces, terms last) the registry is still clean" \
  "$(sh "$RO/bin/lint-name.sh" --root "$RO" --check registry standards/naming 2>&1)" "no finding"
_ro="$(sh "$RO/bin/lint-name.sh" --root "$RO" 2>&1)"
t_has "…and the whole-tree run on that copy judged it" "$_ro" "lint-name:"
t_eq "…with no finding" "" "$(printf '%s\n' "$_ro" | grep -E 'WARN:|FAIL:')"
t_has "a register the lint was never written for is read once a row lists it: its bad row is judged" \
  "$(sh "$LN" --check registry fixtures/naming/registry/fail/listed-register-bad-shape 2>&1)" "draft.tsv — line 7 has 3 columns, the header has 2"
t_has "…and a well-formed one is clean, with no edit to bin/lint-name.sh" \
  "$(sh "$LN" --check registry fixtures/naming/registry/pass/new-register 2>&1)" "no finding"
UL="$TMP/unlisted"; mini "$UL"
cp "$REG/dialects.tsv" "$UL/standards/naming/ghost.tsv"   # a well-formed register file that no row names
_ulo="$(sh "$UL/bin/lint-name.sh" --root "$UL" --self-test 2>&1)"; _ulrc=$?
t_eq "a standards/naming/*.tsv with no registers.tsv row fails the self-test" "exit 1" "exit $_ulrc"
t_has "…naming the file" "$_ulo" "standards/naming holds a file registers.tsv has no row for: ghost.tsv"
rm "$UL/standards/naming/ghost.tsv"
_ulo="$(sh "$UL/bin/lint-name.sh" --root "$UL" --self-test 2>&1)"; _ulrc=$?
t_eq "removed, the same copy's self-test passes" "exit 0" "exit $_ulrc"
t_has "…and says every register file has its row" "$_ulo" "has a registers.tsv row ("

t_section "--check case, path.test and repo-kind exit 0 or 1, never 2 (harbor#996 item 10, #961 items 3 and 6)"
okrc() { sh -c 'sh "$1" --check "$2" "$3" > /dev/null 2>&1; test $? -le 1' _ "$LN" "$1" "$2"; }   # <surface> <name>: exit 0 or 1
RKD="$TMP/rkdirs"; mkdir -p "$RKD"
mkrk() { # <dir> <kind> <entry>... : a repo tree; a trailing / is a directory, .agents/config.yaml carries the kind
  _d="$RKD/$1"; _k="$2"; shift 2; rm -rf "$_d"; mkdir -p "$_d/.agents"; [ -z "$_k" ] || printf 'repo-kind: %s\n' "$_k" > "$_d/.agents/config.yaml"
  for _e in "$@"; do case "$_e" in */) mkdir -p "$_d/$_e" ;; *) mkdir -p "$_d/$(dirname "$_e")"; : > "$_d/$_e" ;; esac; done
  printf '%s' "$_d"
}
rk() { sh "$LN" --check repo-kind "$1" 2>&1; }
WL="README.md AGENTS.md CLAUDE.md justfile docs/"
t_exit "case: a path with a finding" 0 okrc case docs/Notes.md
t_exit "case: a clean path" 0 okrc case docs/notes.md
t_exit "path.test: a test path with a finding" 0 okrc path.test tests/checks/lint-test.sh
t_exit "path.test: a clean test path" 0 okrc path.test tests/admission/bash/destroy.test.sh
t_exit "repo-kind: a repo that has everything" 0 okrc repo-kind "$(mkrk whole workload $WL)"
t_exit "repo-kind: a repo that lacks something" 0 okrc repo-kind "$(mkrk lacking workload README.md)"

t_section "case is path judged for name.case alone, so a path that breaks another rule is green on it"
t_has "an uppercase path is a name.case finding" "$(sh "$LN" --check case docs/Notes.md 2>&1)" "[name.case] docs/Notes.md"
t_has "…and so is an uppercase directory" "$(sh "$LN" --check case Docs/notes.md 2>&1)" "[name.case] Docs"
t_has "a lowercase path with a separator the standard refuses: green on case" "$(sh "$LN" --check case docs/my_notes.md 2>&1)" "no finding"
t_has "…and red on path, where the separator rule judges it" "$(sh "$LN" --check path docs/my_notes.md 2>&1)" "[name.separator] docs/my_notes.md"
t_has "a legacy alias in a lowercase path: green on case" "$(sh "$LN" --check case docs/helm-log-export.md 2>&1)" "no finding"
t_has "…and red on path" "$(sh "$LN" --check path docs/helm-log-export.md 2>&1)" "[name.alias] docs/helm-log-export.md"
for _n in README.md LICENSE CHANGELOG.md SKILL.md .github/ISSUE_TEMPLATE/bug.md CLAUDE.md.tmpl; do
  t_has "a name a tool requires in capitals stays green: $_n" "$(sh "$LN" --check case "$_n" 2>&1)" "no finding"
done
_cr="$TMP/case.red"; : > "$_cr"; LINT_REDLOG="$_cr" sh "$LN" --check case docs/Notes_X.md > /dev/null 2>&1
t_eq "LINT_REDLOG records name.case alone for a path that breaks two rules" "name.case" "$(sort -u "$_cr" | tr '\n' ' ' | sed 's/ $//')"
CB="$TMP/caseblock"; mini "$CB"
awk -F'\t' 'BEGIN { OFS = "\t" } $1 == "name.case" || $1 == "name.separator" { $2 = "block" } { print }' "$REG/controls.tsv" > "$CB/standards/naming/controls.tsv"
t_exit "with both rules at block, an uppercase path fails case" 1 sh "$CB/bin/lint-name.sh" --root "$CB" --check case docs/Notes.md
t_exit "…and a separator problem does not: the view reports name.case alone" 0 sh "$CB/bin/lint-name.sh" --root "$CB" --check case docs/my_notes.md
t_exit "…while path fails on that separator" 1 sh "$CB/bin/lint-name.sh" --root "$CB" --check path docs/my_notes.md

t_section "path.test is the test surface under its second name"
for _n in tests/checks/lint-test.sh tests/admission/bash-test.sh tests/floor/floor.b6-test.sh tests/admission/bash/destroy.test.v2.sh tests/admission/bash/destroy.test.sh tests/drift/undeployed/test_reconcile.py tests/README.md; do
  t_eq "the findings on $_n are the test surface's" "$(sh "$LN" --check test "$_n" 2>&1 | grep -E '^  (WARN|FAIL|ok)' | sed 's/path\.test tests/X tests/; s/test tests/X tests/')" \
    "$(sh "$LN" --check path.test "$_n" 2>&1 | grep -E '^  (WARN|FAIL|ok)' | sed 's/path\.test tests/X tests/; s/test tests/X tests/')"
done
t_has "a test file with a dot outside its extension chain is a name.test-path finding" "$(sh "$LN" --check path.test tests/floor/floor.b6-test.sh 2>&1)" "[name.test-path] tests/floor/floor.b6-test.sh"
t_has "a good test path is not" "$(sh "$LN" --check path.test tests/admission/bash/destroy.test.sh 2>&1)" "no finding"
t_has "a bare test name is read under tests/, as the test surface reads it" "$(sh "$LN" --check path.test admission/bash/destroy.test.sh 2>&1)" "no finding"

t_section "repo-kind: --check <dir> reads the kind .agents/config.yaml declares, and the entries repo-kinds.tsv requires of it"
t_has "a workload with every required entry is clean" "$(rk "$(mkrk whole workload $WL)")" "no finding"
t_has "…with optional entries and entries the kind does not list beside them (valid but unusual)" \
  "$(rk "$(mkrk extras workload $WL bin/ src/ .github/ .gitignore build/ notes.txt)")" "no finding"
t_has "…and a double-quoted kind with a trailing comment" \
  "$(mkrk quoted '' $WL >/dev/null; printf 'repo-kind: "workload"  # standards/naming/repo-kinds.tsv\n' > "$RKD/quoted/.agents/config.yaml"; rk "$RKD/quoted")" "no finding"
t_has "…and a single-quoted one" \
  "$(mkrk single '' $WL >/dev/null; printf "repo-kind: 'workload'\n" > "$RKD/single/.agents/config.yaml"; rk "$RKD/single")" "no finding"
t_has "…and the kind line among other keys" \
  "$(mkrk keys '' $WL >/dev/null; printf 'context: repo\nscope: project\nrepo-kind: workload\n' > "$RKD/keys/.agents/config.yaml"; rk "$RKD/keys")" "no finding"
t_has "a control plane needs its longer list, and has it" "$(rk "$(mkrk plane control-plane README.md AGENTS.md CLAUDE.md LICENSE CHANGELOG.md justfile bin/ tests/ docs/)")" "no finding"
t_has "a required file that is missing is a name.repo-kind finding naming it" "$(rk "$(mkrk nofile workload AGENTS.md CLAUDE.md justfile docs/)")" "[name.repo-kind] repo-kind:$RKD/nofile:README.md"
t_has "a required directory that is missing is one too" "$(rk "$(mkrk nodir workload README.md AGENTS.md CLAUDE.md justfile)")" "repo-kind:$RKD/nodir:docs/"
t_has "…and it says what the kind carries" "$(rk "$RKD/nodir")" "a \`workload\` repo carries \`docs/\`"
t_has "a file where the kind wants a directory is a finding" "$(rk "$(mkrk docfile workload README.md AGENTS.md CLAUDE.md justfile docs)")" "\`docs/\` is a directory in a \`workload\` repo and this one has a file"
t_has "a directory where the kind wants a file is a finding" "$(rk "$(mkrk dirfile workload README.md AGENTS.md CLAUDE.md docs/ justfile/)")" "\`justfile\` is a file in a \`workload\` repo and this one has a directory"
t_has "a repo with no .agents/config.yaml declares no kind" "$(rk "$(mkrk nocfg '' $WL)")" "declares no repo-kind"
t_has "a config with no repo-kind line declares none" "$(mkrk noline '' $WL >/dev/null; printf 'context: repo\n' > "$RKD/noline/.agents/config.yaml"; rk "$RKD/noline")" "declares no repo-kind"
t_has "a kind that is not a row of repo-kinds.tsv is a finding" "$(rk "$(mkrk unknown monorepo $WL)")" "its kind \`monorepo\` is not a row of repo-kinds.tsv"
t_hasnt "…and an unknown kind is not also judged for entries" "$(rk "$RKD/unknown")" "carries"
t_has "a relative directory is read from --root" "$(sh "$LN" --root "$RKD" --registry "$REG" --check repo-kind whole 2>&1)" "no finding"
t_exit "a directory that is not there is usage, never clean" 2 sh "$LN" --check repo-kind "$RKD/nowhere"
t_exit "…and so is a file given for a directory" 2 sh "$LN" --check repo-kind "$RKD/whole/README.md"
t_eq "the red log carries name.repo-kind for a finding" "name.repo-kind" "$(: > "$TMP/rk.red"; LINT_REDLOG="$TMP/rk.red" sh "$LN" --check repo-kind "$RKD/nofile" > /dev/null 2>&1; sort -u "$TMP/rk.red")"
RB="$TMP/rkblock"; mini "$RB"
awk -F'\t' 'BEGIN { OFS = "\t" } $1 == "name.repo-kind" { $2 = "block" } { print }' "$REG/controls.tsv" > "$RB/standards/naming/controls.tsv"
t_exit "at block, a missing entry fails the check" 1 sh "$RB/bin/lint-name.sh" --root "$RB" --check repo-kind "$RKD/nofile"
t_exit "…and a complete repo does not" 0 sh "$RB/bin/lint-name.sh" --root "$RB" --check repo-kind "$RKD/whole"
mkdir -p "$RB/.agents"; printf 'repo-kind: workload\n' > "$RB/.agents/config.yaml"
t_hasnt "never a tree scan: a tree whose own root is a workload missing its entries is not reported by the tree run" "$(sh "$RB/bin/lint-name.sh" --root "$RB" 2>&1)" "name.repo-kind"
t_hasnt "…nor by --changed" "$(git -C "$RB" init -q -b main 2>/dev/null; git -C "$RB" add -A >/dev/null 2>&1; git -C "$RB" -c user.email=t@example.invalid -c user.name=t commit -q -m base >/dev/null 2>&1; : > "$RB/New_Bad.md"; sh "$RB/bin/lint-name.sh" --root "$RB" --base main --changed 2>&1)" "name.repo-kind"
t_has "…while --check on that same root names what it lacks" "$(sh "$RB/bin/lint-name.sh" --root "$RB" --check repo-kind . 2>&1)" "a \`workload\` repo carries \`README.md\`"
RD="$TMP/rkdrop"; mini "$RD"
rd() { sh "$RD/bin/lint-name.sh" --root "$RD" --check repo-kind "$RKD/whole" 2>&1; }
t_has "positive control: the copy's registry names repo-kinds.tsv and judges a valid repo clean" "$(rd)" "no finding"
grep -v '^repo-kind	' "$REG/registers.tsv" > "$RD/standards/naming/registers.tsv"
t_eq "the cut removed exactly the repo-kind row" 1 "$(diff "$REG/registers.tsv" "$RD/standards/naming/registers.tsv" | grep -c '^<')"
t_exit "a registers.tsv that stops naming repo-kinds.tsv is UNCHECKED, never a verdict on the repo" 3 sh "$RD/bin/lint-name.sh" --root "$RD" --check repo-kind "$RKD/whole"
t_has "…and says which file" "$(rd)" "registers.tsv has no row naming repo-kinds.tsv"
t_hasnt "…and does not tell a valid repo its kind is unknown" "$(rd)" "is not a row of repo-kinds.tsv"
cp "$REG/registers.tsv" "$RD/standards/naming/registers.tsv"
t_has "restored, the same copy judges the same repo clean again" "$(rd)" "no finding"

t_section "the three new surfaces are held by the self-test: delete their fail fixtures and it goes red"
GD="$TMP/gone"; mini "$GD"
rm -rf "$GD/fixtures/naming/case/fail" "$GD/fixtures/naming/path.test/fail" "$GD/fixtures/naming/repo-kind/fail"
_gdo="$(sh "$GD/bin/lint-name.sh" --root "$GD" --self-test 2>&1)"; _gdrc=$?
t_eq "with the fail fixtures of case, path.test and repo-kind gone, --self-test exits 1" "exit 1" "exit $_gdrc"
t_has "…naming case" "$_gdo" "a declared surface never went red: "
t_has "…the case pair" "$_gdo" "name.case on case"
t_has "…the path.test pair" "$_gdo" "name.test-path on path.test"
t_has "…the repo-kind pair" "$_gdo" "name.repo-kind on repo-kind"
t_has "…and the rule that never went red at all" "$_gdo" "never went red in this self-test: name.repo-kind"
cp -R "$T_ROOT/fixtures/naming/case/fail" "$GD/fixtures/naming/case/fail"; cp -R "$T_ROOT/fixtures/naming/path.test/fail" "$GD/fixtures/naming/path.test/fail"; cp -R "$T_ROOT/fixtures/naming/repo-kind/fail" "$GD/fixtures/naming/repo-kind/fail"
t_eq "restored, the same copy's self-test exits 0" "exit 0" "exit $(sh "$GD/bin/lint-name.sh" --root "$GD" --self-test > /dev/null 2>&1; echo $?)"
VW="$TMP/views"; mini "$VW"
awk -F'\t' 'BEGIN { OFS = "\t" } $1 == "case" { $7 = "path.test" } { print }' "$REG/surfaces.tsv" > "$VW/standards/naming/surfaces.tsv"
t_has "a view of a view is a shape finding" "$(sh "$VW/bin/lint-name.sh" --root "$VW" --check registry standards/naming 2>&1)" "view \`path.test\` is itself a view"
awk -F'\t' 'BEGIN { OFS = "\t" } $1 == "case" { $7 = "path:name.nope" } { print }' "$REG/surfaces.tsv" > "$VW/standards/naming/surfaces.tsv"
t_has "a view rule that is not a control is one too" "$(sh "$VW/bin/lint-name.sh" --root "$VW" --check registry standards/naming 2>&1)" "view rule \`name.nope\` is not a row of controls.tsv"
t_has "…and a view whose surface is not a row" "$(sh "$LN" --check registry fixtures/naming/registry/fail/surface-bad-view 2>&1)" "view \`no-such-surface\` is not a row of surfaces.tsv"

t_section "name.test-path judges the family slot's boundary and the extension (main did)"
for _n in tests/admission-extra/helper.sh tests/admission.d/helper.sh tests/admission/bash/x.test.s-h tests/admission/bash/x.test.V2; do
  t_has "$_n is a name.test-path finding" "$(sh "$LN" --check test "$_n" 2>&1)" "[name.test-path]"
done
t_has "…and a good test path is not" "$(sh "$LN" --check test tests/admission/bash/x.test.sh 2>&1)" "no finding"

t_section "an id the tree carries and controls.tsv lacks is red, for each census (D-62)"
CN="$TMP/census"; mini "$CN"; mkdir -p "$CN/inject.d/box" "$CN/.claude/inject.d" "$CN/CONTRACTS"
cp "$T_ROOT"/bin/guard-*.sh "$CN/bin/"; cp "$T_ROOT/bin/lint-conventions.sh" "$CN/bin/"; cp "$T_ROOT/CHECKS.md" "$CN/"
cp "$T_ROOT/CONTRACTS/required-checks.tsv" "$CN/CONTRACTS/"; cp "$T_ROOT"/inject.d/box/*.md "$CN/inject.d/box/"; cp "$T_ROOT"/.claude/inject.d/*.md "$CN/.claude/inject.d/"
cn() { sh "$CN/bin/lint-name.sh" --root "$CN" --check registry standards/naming 2>&1; }
t_has "the real guards, checks, packs and rules are all registered: no finding" "$(cn)" "no finding"
grep -v '^admission\.' "$REG/controls.tsv" > "$CN/standards/naming/controls.tsv"
t_eq "…and the census found the guard rules: with no admission row it reports each of them" yes \
  "$([ "$(cn | grep -c 'name.control-unregistered\] admission:')" -gt 50 ] && echo yes || echo no)"
cp "$REG/controls.tsv" "$CN/standards/naming/controls.tsv"
cp "$CN/bin/guard-bash.sh" "$TMP/guard-bash.keep"
printf '\nhit x && floor_block bash "a ghost refusal" ghost-refusal.flat\n' >> "$CN/bin/guard-bash.sh"
t_has "an admission refusal with no row is red" "$(cn)" "[name.control-unregistered] admission:bash:ghost-refusal"
cp "$TMP/guard-bash.keep" "$CN/bin/guard-bash.sh"
printf '\nrule_ZZ() {\nrule "lint.ghost-rule a rule no row holds"\n}\n' >> "$CN/bin/lint-conventions.sh"
t_has "a lint-conventions rule with no row is red" "$(cn)" "[name.control-unregistered] lint:lint.ghost-rule"
cp "$T_ROOT/bin/lint-conventions.sh" "$CN/bin/lint-conventions.sh"
awk '/^## Register/ { print; getline; print; getline; print; print "| `ghost-check` | nothing | never | none | a check no row holds |"; next } { print }' "$T_ROOT/CHECKS.md" > "$CN/CHECKS.md"
t_has "a check in CHECKS.md with no row is red" "$(cn)" "[name.control-unregistered] check:ghost-check"
cp "$T_ROOT/CHECKS.md" "$CN/CHECKS.md"
printf -- '---\nid: ghost-pack\nevent: SessionStart\nwhen: always\n---\nbody\n' > "$CN/inject.d/box/10-ghost-pack.md"
t_has "a rule pack with no row is red" "$(cn)" "[name.control-unregistered] injection:ghost-pack"
rm "$CN/inject.d/box/10-ghost-pack.md"
printf 'VytCepas/harbor\tghost gate\n' >> "$CN/CONTRACTS/required-checks.tsv"
t_has "a required CI check with no row is red" "$(cn)" "[name.control-unregistered] ci:ghost gate"
cp "$T_ROOT/CONTRACTS/required-checks.tsv" "$CN/CONTRACTS/required-checks.tsv"
t_has "and the clean copy is clean again" "$(cn)" "no finding"
for _src in 'guard-rules:bin/guard-\*.sh' 'checks-table:CHECKS.md' 'inject-ids:inject.d,.claude/inject.d' 'lint-rules:bin/lint-conventions.sh' 'required-checks:CONTRACTS/required-checks.tsv'; do
  _bad="${_src%%:*}:zz-missing"
  sed "s#$_src#$_bad#" "$REG/registers.tsv" > "$CN/standards/naming/registers.tsv"
  t_has "a census whose source is missing fails loud: $_src" "$(cn)" "found no id: its source is missing or empty"
done
cp "$REG/registers.tsv" "$CN/standards/naming/registers.tsv"
for _m in 'admission.pipe-to-shell' 'check.fleet-snapshot' 'context.subagent-contract' 'ci.suites'; do
  if grep -q "^$_m	" "$REG/controls.tsv"; then
    grep -v "^$_m	" "$REG/controls.tsv" > "$CN/standards/naming/controls.tsv"
    t_has "removing the row $_m turns the census red" "$(cn)" "[name.control-unregistered]"
    cp "$REG/controls.tsv" "$CN/standards/naming/controls.tsv"
  else t_eq "the row $_m exists in controls.tsv" present absent; fi
done

t_section "terms.tsv: depends_on, the level chain and the closed sets (D-57, D-60)"
t_eq "level and subsystem read as D-57: containment, and a family is not a subsystem" "yes" \
  "$(awk -F'\t' '$1 == "level" && $11 ~ /containment/ { a = 1 } $1 == "subsystem" && $11 ~ /is not one/ && $9 !~ /family/ { b = 1 } END { print (a && b) ? "yes" : "no" }' "$REG/terms.tsv")"
t_eq "there are seven levels, one chain" 7 "$(awk -F'\t' '$2 ~ /(^|,)level(,|$)/ { n++ } END { print n }' "$REG/terms.tsv")"
t_eq "event is a family; with pack (D-84) and session (D-86) there are 26" 26 "$(awk -F'\t' '$2 ~ /(^|,)family(,|$)/ { n++ } END { print n }' "$REG/terms.tsv")"
t_eq "obligation is a concept under the status family" status "$(awk -F'\t' '$1 == "obligation" { print $4 }' "$REG/terms.tsv")"
t_eq "the estate workload (harbor#950) is the one system term core registers; workload systems come from the overlay (D-85)" "estate" \
  "$(awk -F'\t' '$2 ~ /(^|,)system(,|$)/ && $1 != "fleet" && $1 != "memory-store" { print $1 }' "$REG/terms.tsv" | sort | tr '\n' ' ' | sed 's/ $//')"
t_eq "no control id of the modularity rules collides with a lint id" 0 "$(grep -c '^M[0-9]' "$REG/controls.tsv")"
t_eq "…the rules are module.* ids: D-60's five, layer-direction and module.graph-conform (harbor#996)" 7 "$(grep -c '^module\.' "$REG/controls.tsv")"

t_section "exemptions expire by rename wave, never on one day (harbor#950)"
_ex="$(awk -F'\t' '/^#/ || $1 == "id" { next } $4 == "legacy" { n++; d[$5]++ } END { m = 0; for (k in d) if (d[k] > m) { m = d[k]; dk = k }; printf "%d %d %s", n, m, dk }' "$REG/exemptions.tsv")"
_exn="${_ex%% *}"; _exm="${_ex#* }"; _exm="${_exm%% *}"
t_eq "the largest remove_by date holds under a quarter of the legacy rows ($_ex)" yes "$([ $((_exm * 4)) -lt "$_exn" ] && echo yes || echo no)"
t_eq "every legacy row's reason names its wave" "" "$(awk -F'\t' '/^#/ || $1 == "id" { next } $4 == "legacy" && $6 !~ /; (W[1-6] |skills)/' "$REG/exemptions.tsv" | head -3)"

t_section "harbor's tree exits 0 with advisories only"
_tr="$(sh "$LN" 2>&1)"; _trrc=$?
t_eq "the whole-tree run exits 0" "exit 0" "exit $_trrc"
t_hasnt "…with no block-level finding" "$_tr" "  FAIL:"
t_has "…and says what the exemptions hid, without listing it" "$_tr" "exempted by standards/naming/exemptions.tsv"

t_section "one term changes the lint result and the glossary, with no other edit"
O="$TMP/oneterm"; mini "$O"
_before="$(sh "$O/bin/lint-name.sh" --root "$O" --check bin audit-triage.sh 2>&1)"
sh "$O/bin/lint-name.sh" --root "$O" --gen glossary > /dev/null 2>&1; cp "$O/build/naming/glossary.md" "$TMP/glossary.before"
awk -F'\t' 'BEGIN { OFS = "\t" } $1 == "audit" && $2 == "family" { $2 = "concept" } { print }' "$O/standards/naming/terms.tsv" > "$TMP/terms.new"
mv "$TMP/terms.new" "$O/standards/naming/terms.tsv"
t_eq "the edit touched one row of terms.tsv" 1 "$(diff "$REG/terms.tsv" "$O/standards/naming/terms.tsv" | grep -c '^>')"
_after="$(sh "$O/bin/lint-name.sh" --root "$O" --check bin audit-triage.sh 2>&1)"
sh "$O/bin/lint-name.sh" --root "$O" --gen glossary > /dev/null 2>&1
t_has "before: audit-triage.sh is a family script" "$_before" "no finding"
t_has "after: the same name is a name.family finding" "$_after" "[name.family] bin/audit-triage.sh"
t_eq "the glossary changed on exactly the audit row" 1 "$(diff "$TMP/glossary.before" "$O/build/naming/glossary.md" | grep -c '^> | \*\*audit\*\*')"
t_has "…which now reads concept" "$(grep '^| \*\*audit\*\*' "$O/build/naming/glossary.md")" "| concept |"

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
HARBOR_ROOT="$N" HARBOR_FINDINGS_OUT="$_fo" sh "$LINT" --only N4 > /dev/null 2>&1
t_has "…and its finding record carries the path as subject" "$(cat "$_fo")" "$(printf 'A\tstandard.names-conform\tdocs/Bad_Name.md')"
_nr="$TMP/n4.red"; : > "$_nr"
HARBOR_ROOT="$N" LINT_REDLOG="$_nr" sh "$LINT" --only N4 > /dev/null 2>&1
t_has "…and LINT_REDLOG carries each finding's own rule id" "$(sort -u "$_nr")" "name.case"
t_eq "…and never N4 for a naming finding, so each rule has its own record" "" "$(grep -x "$(lid N4)" "$_nr")"
rm "$N/standards/naming/terms.tsv"
t_has "a registry that cannot be read is a VIOLATION, never clean" "$(viol N4 "$N")" "judged nothing"
: > "$_nr"; HARBOR_ROOT="$N" LINT_REDLOG="$_nr" sh "$LINT" --only N4 > /dev/null 2>&1
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
printf 'rule_F1() {\nrule "admission.floor-first a fixture rule"\n}\n' > "$LC/bin/lint-conventions.sh"
t_has "a lint-conventions id is judged as a rule-id name, read and never run" \
  "$(sh "$LC/bin/lint-name.sh" --root "$LC" 2>&1)" "[name.alias] rule-id:admission.floor-first"
printf 'rule_F1() {\nrule "admission.kill-switch-first a fixture rule"\n}\n' > "$LC/bin/lint-conventions.sh"
_lcg="$(sh "$LC/bin/lint-name.sh" --root "$LC" 2>&1)"
t_hasnt "…and a good one is not" "$_lcg" "rule-id:admission"
t_has "positive control: that run judged the tree" "$_lcg" "lint-name:"

t_section "--format findings is the kind TAB id TAB subject record"
F="$TMP/fmt"; mini "$F"; mkdir -p "$F/docs" "$F/bin"; : > "$F/docs/Notes.md"
printf '#!/usr/bin/env sh\nHELM_PROBE_FIXTURE=1 sh x\n' > "$F/bin/probe.sh"
_ff="$(sh "$F/bin/lint-name.sh" --root "$F" --format findings 2>/dev/null)"
t_eq "every record is A TAB name.<rule> TAB subject" "" "$(printf '%s\n' "$_ff" | grep -vE "^A	name\.[a-z-]+	[^	]+$")"
t_has "a bad path is a record" "$_ff" "$(printf 'A\tname.case\tdocs/Notes.md')"
t_has "an env name read from code is a record" "$_ff" "$(printf 'A\tname.env\tenv:HELM_PROBE_FIXTURE')"
t_has "…and its legacy prefix is an alias finding" "$_ff" "$(printf 'A\tname.alias\tenv:HELM_PROBE_FIXTURE')"

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
