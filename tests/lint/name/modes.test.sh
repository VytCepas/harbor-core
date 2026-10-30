#!/usr/bin/env sh
# bin/lint-name.sh (harbor#950): --added and its relay standard.names-added (harbor#968), --gen, the share column (D-83), the
# private overlay (D-85). Split from tests/lint/name/name.test.sh at the 500-line budget (tests/README.md T2); the fixture
# tree comes from tests/lint/name/fixture.sh.
. "$(dirname "$0")/../../lib/core.sh"; t_init
# the suite never reads the box's private overlay (D-85)
HARBOR_SCOPE_PRIVATE="$TMP/no-private"; export HARBOR_SCOPE_PRIVATE; unset PORT_ROOT
. "$T_ROOT/tests/checks/lint-fixture.sh"
LN="$T_ROOT/bin/lint-name.sh"
REG="$T_ROOT/standards/naming"
. "$T_ROOT/tests/lint/name/fixture.sh"
t_section "--added judges only the paths a branch adds, and standard.names-added relays it (harbor#968)"
AD="$TMP/addedmode"; mini "$AD"
: > "$AD/Legacy_Old.md"; mkdir -p "$AD/docs" "$AD/scripts"; printf 'one\n' > "$AD/docs/keep-me.md"
git -C "$AD" init -q -b main && git -C "$AD" add -A \
  && git -C "$AD" -c user.email=t@example.invalid -c user.name=t commit -q -m base
git -C "$AD" checkout -q -b feature
: > "$AD/New_Bad.md"; : > "$AD/docs/good-new.md"                                  # a bad name added, a good one added
printf 'more\n' >> "$AD/Legacy_Old.md"                                            # a legacy bad name, only modified
git -C "$AD" mv docs/keep-me.md docs/Renamed_Bad.md                              # a good name renamed to a bad one
printf '#!/usr/bin/env sh\nHELM_PROBE_FIXTURE=1\n' > "$AD/scripts/probe.sh"       # a new file using a legacy env prefix
cp "$AD/standards/naming/dialects.tsv" "$AD/standards/naming/ghost.tsv"          # a register file registers.tsv does not name
git -C "$AD" add -A && git -C "$AD" -c user.email=t@example.invalid -c user.name=t commit -q -m branch
: > "$AD/Untracked_Bad.md"                                                        # not the branch's yet
ad() { sh "$AD/bin/lint-name.sh" --root "$AD" --base main "$@" 2>&1; }
_ad="$(ad --added)"
t_has "a bad name the branch adds is judged" "$_ad" "[name.case] New_Bad.md"
t_has "…and so is a good name renamed to a bad one: a rename is an add of its new path" "$_ad" "[name.case] docs/Renamed_Bad.md"
t_hasnt "a good name the branch adds is not" "$_ad" "good-new.md"
t_hasnt "…nor a legacy bad name the branch only modified" "$_ad" "Legacy_Old.md"
t_hasnt "…nor an untracked file, which is not the branch's yet" "$_ad" "Untracked_Bad.md"
t_hasnt "…nor an env token read out of an added file: the file may only use one that was there" "$_ad" "HELM_PROBE_FIXTURE"
t_hasnt "…nor the registry: a file registers.tsv does not name is a tree finding, not an added name" "$_ad" "register-file:ghost.tsv"
t_has "positive control: the same run judged the branch" "$_ad" "the names added since main"
_chg="$(ad --changed)"
t_has "--changed on the same branch does see the modified legacy name" "$_chg" "[name.case] Legacy_Old.md"
t_has "…the untracked one" "$_chg" "[name.case] Untracked_Bad.md"
t_has "…the env token" "$_chg" "env:HELM_PROBE_FIXTURE"
t_has "…and the unlisted register file" "$_chg" "register-file:ghost.tsv"
t_exit "an added bad name exits 0 at warn" 0 sh "$AD/bin/lint-name.sh" --root "$AD" --base main --added
t_exit "with no base to compare against, --added is unchecked, never clean" 3 sh "$AD/bin/lint-name.sh" --root "$AD" --base no-such-ref --added
NG="$TMP/nogit"; mini "$NG"
t_exit "…and so is a tree that is not git" 3 sh "$NG/bin/lint-name.sh" --root "$NG" --added
_adf="$(ad --added --format findings 2>/dev/null)"
t_has "--format findings carries the added path as its subject" "$_adf" "$(printf 'A\tname.case\tNew_Bad.md')"
AB="$TMP/addedblock"; mini "$AB"
awk -F'\t' 'BEGIN { OFS = "\t" } $1 == "name.case" { $2 = "block" } { print }' "$AB/standards/naming/controls.tsv" > "$TMP/ab.controls"; mv "$TMP/ab.controls" "$AB/standards/naming/controls.tsv"
git -C "$AB" init -q -b main && git -C "$AB" add -A && git -C "$AB" -c user.email=t@example.invalid -c user.name=t commit -q -m base
git -C "$AB" checkout -q -b feature; : > "$AB/New_Bad.md"; git -C "$AB" add -A && git -C "$AB" -c user.email=t@example.invalid -c user.name=t commit -q -m branch
t_exit "at block, an added bad name exits 1" 1 sh "$AB/bin/lint-name.sh" --root "$AB" --base main --added
git -C "$AB" checkout -q main
t_exit "…and a branch that adds nothing exits 0" 0 sh "$AB/bin/lint-name.sh" --root "$AB" --base main --added
t_has "…saying it found nothing, not judging the file list as paths (an empty set once joined to the whole tree)" "$(sh "$AB/bin/lint-name.sh" --root "$AB" --base main --added 2>&1)" "no finding"
t_hasnt "…and --changed on an unchanged tree the same" "$(sh "$AB/bin/lint-name.sh" --root "$AB" --base main --changed 2>&1)" "100644"

t_section "standard.names-added: bin/lint-conventions.sh relays --added on its own record"
na() { HARBOR_SCOPE_ROOT="$AD" HARBOR_CI_BASE=main sh "$LINT" --only standard.names-added 2>&1; }
_nao="$(na)"
t_has "an added bad name is an advisory of the rule" "$_nao" "ADVISORY [standard.names-added] [name.case] New_Bad.md"
t_has "…and a renamed-to-bad one" "$_nao" "ADVISORY [standard.names-added] [name.case] docs/Renamed_Bad.md"
t_hasnt "…and not a legacy name the branch only modified" "$_nao" "Legacy_Old.md"
t_eq "…and an advisory is not a violation" "" "$(printf '%s\n' "$_nao" | grep 'VIOLATION')"
_nf="$TMP/na.findings"; : > "$_nf"
HARBOR_SCOPE_ROOT="$AD" HARBOR_CI_BASE=main HARBOR_LINT_FINDINGS_OUT="$_nf" sh "$LINT" --only standard.names-added > /dev/null 2>&1
t_has "…its finding record carries the added path as subject" "$(cat "$_nf")" "$(printf 'A\tstandard.names-added\tNew_Bad.md')"
_nr="$TMP/na.red"; : > "$_nr"
HARBOR_SCOPE_ROOT="$AD" HARBOR_CI_BASE=main LINT_REDLOG="$_nr" sh "$LINT" --only standard.names-added > /dev/null 2>&1
t_has "LINT_REDLOG records the rule's own id" "$(sort -u "$_nr")" "standard.names-added"
t_has "…beside the name.* rule the path went red on" "$(sort -u "$_nr")" "name.case"
git -C "$AD" checkout -q main
_ncl="$(na)"
t_hasnt "on a branch that adds nothing the rule is silent" "$_ncl" "ADVISORY"
t_has "…and says it judged" "$_ncl" "lint-name:"
: > "$_nr"; HARBOR_SCOPE_ROOT="$AD" HARBOR_CI_BASE=main LINT_REDLOG="$_nr" sh "$LINT" --only standard.names-added > /dev/null 2>&1
t_eq "…and writes nothing to LINT_REDLOG" "" "$(cat "$_nr")"
git -C "$AD" checkout -q feature
_nu="$(HARBOR_SCOPE_ROOT="$AD" HARBOR_CI_BASE=no-such-ref sh "$LINT" --only standard.names-added 2>&1)"
t_has "with no base the rule says it could not look, as an advisory" "$_nu" "ADVISORY [standard.names-added] unchecked: no base to compare against"
t_eq "…which is not a violation" "" "$(printf '%s\n' "$_nu" | grep 'VIOLATION')"
: > "$_nr"; HARBOR_SCOPE_ROOT="$AD" HARBOR_CI_BASE=no-such-ref LINT_REDLOG="$_nr" sh "$LINT" --only standard.names-added > /dev/null 2>&1
t_eq "…and 'could not look' is not the rule going red: LINT_REDLOG stays empty" "" "$(cat "$_nr")"
t_has "a tree that is not git is skipped, and says so" "$(HARBOR_SCOPE_ROOT="$NG" sh "$LINT" --only standard.names-added 2>&1)" "skip: not a git tree"
mv "$AD/bin/lint-name.sh" "$TMP/ln.keep"
t_has "no lint at all is skipped by name, never read as a clean branch" "$(na)" "skip: no bin/lint-name.sh in this tree"
cp "$TMP/ln.keep" "$AD/bin/lint-name.sh"
printf 'exit 7\n' > "$AD/bin/lint-name.sh"
t_has "a lint that exits above 1 judged nothing: a VIOLATION" "$(na)" "VIOLATION [standard.names-added] bin/lint-name.sh exited 7 and judged nothing"
cp "$TMP/ln.keep" "$AD/bin/lint-name.sh"
grep -v '^alias	' "$REG/registers.tsv" > "$AD/standards/naming/registers.tsv"   # a base exists, the registry cannot be read
_nb="$(na)"
t_has "a registry the lint cannot read, with a base that exists, is a VIOLATION of the rule" "$_nb" \
  "VIOLATION [standard.names-added] bin/lint-name.sh exited 3 and judged nothing: registers.tsv has no row naming aliases.tsv"
t_hasnt "…and is not told as a missing base" "$_nb" "no base to compare against"
: > "$_nr"; HARBOR_SCOPE_ROOT="$AD" HARBOR_CI_BASE=main LINT_REDLOG="$_nr" sh "$LINT" --only standard.names-added > /dev/null 2>&1
t_has "…and the rule's record goes red, because it could not judge" "$(cat "$_nr")" "standard.names-added"
cp "$REG/registers.tsv" "$AD/standards/naming/registers.tsv"
t_hasnt "restored, the same tree is no violation" "$(na)" "VIOLATION"
t_eq "controls.tsv holds the rule at warn, owned by standard, with this suite as its red proof" "standard.names-added	warn	lint	bin/lint-conventions.sh	tests/lint/name/name.test.sh" \
  "$(awk -F'\t' '$1 == "standard.names-added" { print $1 "\t" $2 "\t" $3 "\t" $4 "\t" $11 }' "$REG/controls.tsv")"
t_has "--list names it beside its sibling" "$(sh "$LN" --list)" "standard.names-added"

t_section "--gen writes every view under build/, from the registry"
M="$TMP/gen"; mini "$M"   # a copy of its own: in tests/lint/name/name.test.sh this ran on the mutant tree
for _v in glossary naming-guide cli-tree labels vale; do
  t_exit "--gen $_v exits 0" 0 sh "$M/bin/lint-name.sh" --root "$M" --gen "$_v"
done
t_has "the glossary carries the generated marker" "$(head -1 "$M/build/naming/glossary.md")" "generated by bin/lint-name.sh --gen glossary"
t_exit "the glossary is valid UTF-8 (a byte-cut → made 234 rows invalid, harbor#950)" 0 iconv -f UTF-8 -t UTF-8 "$M/build/naming/glossary.md"
t_has "…and its broader chain is whole" "$(grep '^| \*\*lint\*\*' "$M/build/naming/glossary.md")" "audit → "
t_has "the CLI tree parses a family script back into its tuple" "$(cat "$M/build/naming/cli-tree.txt")" "harbor lint name    <- bin/lint-name.sh"
t_has "the label set is <axis>:<value>" "$(cat "$M/build/naming/labels.tsv")" "$(printf 'family:admission\t')"
t_has "the Vale swap list comes from the legacy aliases" "$(cat "$M/build/vale/styles/Harbor/Legacy.yml")" "'floor': security baseline"
t_has "…and the spelling swap from the spelling aliases (D-16)" "$(cat "$M/build/vale/styles/Harbor/Spelling.yml")" "'behaviour': behavior"
if command -v vale > /dev/null 2>&1; then
  printf '# Notes\n\nThe floor blocks it. Its behaviour holds.\n' > "$M/vale-probe.md"
  _vl="$(cd "$M" && vale --config build/vale/.vale.ini vale-probe.md 2>&1)"
  t_has "vale runs the generated config and flags a legacy term" "$_vl" "security baseline"
  t_has "…and a UK spelling" "$_vl" "Use behavior instead of behaviour"
else
  t_eq "vale is absent: the generated config was not run (verified NOTHING about it)" absent absent
fi

t_section "spelling (D-16): a UK spelling is allowed nowhere and never expires"
SP="$TMP/spelling"; mini "$SP"
_al="$SP/standards/naming/aliases.tsv"; awk -F'\t' '$1 != "colour"' "$_al" > "$_al.new" && mv "$_al.new" "$_al"
printf 'colour\tcolor\tspelling\tglossary\t2027-01-31\tD-16\n' >> "$_al"
printf '#!/usr/bin/env sh\nCOLOUR_MODE_X=1\n' > "$SP/bin/probe.sh"
_spf="$(sh "$SP/bin/lint-name.sh" --root "$SP" --format findings 2>/dev/null)"
t_has "a spelling row with a surface or a date goes red" "$(sh "$SP/bin/lint-name.sh" --root "$SP" 2>&1)" \
  "[name.registry-term] alias:colour — a spelling is allowed nowhere and never expires"
t_hasnt "…and a spelling's US word is never judged as a term" "$_spf" "alias:behaviour"
t_hasnt "a spelling is never an env prefix: a token under it in the tree is not judged" "$_spf" "env:COLOUR_MODE_X"

t_section "share (D-83): a kind names the SET of shares it may take, and the lint refuses a missing or unknown one"
SH="$TMP/share"; mini "$SH"
shf() { sh "$SH/bin/lint-name.sh" --root "$SH" --format findings 2>/dev/null | grep -E "^[AV]	name.registry-shape	kind:policy:share$"; }
t_eq "a registry whose every kind has a share set is clean on the share column" "" "$(shf)"
t_eq "…and every kind row carries a comma-separated set of core, hub, workload, personal" "" \
  "$(awk -F'\t' '/^#/ || !h++ { next } $10 !~ /^(core|hub|workload|personal)(,(core|hub|workload|personal))*$/ { print $1 }' "$SH/standards/naming/kinds.tsv")"
t_eq "…a hook is core only (a pack carries none) and a skill may be core or workload" "core core,workload" \
  "$(awk -F'\t' '$1 == "hook" { a = $10 } $1 == "skill" { b = $10 } END { print a, b }' "$SH/standards/naming/kinds.tsv")"
cp "$SH/standards/naming/kinds.tsv" "$TMP/kinds.keep"
for _bad in "" everyone core,nowhere core,; do
  awk -F'\t' -v v="$_bad" 'BEGIN { OFS = "\t" } $1 == "policy" { $10 = v } { print }' "$TMP/kinds.keep" > "$SH/standards/naming/kinds.tsv"
  t_has "a share cell of '$_bad' goes red" "$(shf)" "name.registry-shape"
done
t_has "…and the message names the closed set" "$(sh "$SH/bin/lint-name.sh" --root "$SH" 2>&1)" "is not a share term: core, hub, workload or personal"
awk -F'\t' 'BEGIN { OFS = "\t" } $1 == "policy" { $10 = "core,hub,workload,personal" } { print }' "$TMP/kinds.keep" > "$SH/standards/naming/kinds.tsv"
t_eq "a set of all four is accepted" "" "$(shf)"
cp "$TMP/kinds.keep" "$SH/standards/naming/kinds.tsv"
t_eq "restored, the same check is clean again" "" "$(shf)"

t_section "private overlay (D-85): harbor-private/terms.tsv adds client and system terms and nothing else"
OV="$TMP/overlay"; mini "$OV"; PV="$TMP/priv"; mkdir -p "$PV"
_hdr="$(grep -m1 '^id	class' "$REG/terms.tsv")"
_row() { printf '%s\t%s\t%s\t-\t-\tstable\t-\ttest\t-\t-\ta fixture row\n' "$1" "$2" "$1"; }
ovf() { HARBOR_SCOPE_PRIVATE="$PV" sh "$OV/bin/lint-name.sh" --root "$OV" --format findings 2>/dev/null | grep -E "^[AV]	name\.registry-(shape|duplicate)	" || :; }
chk() { HARBOR_SCOPE_PRIVATE="$PV" sh "$OV/bin/lint-name.sh" --root "$OV" --check "$@" 2>&1; }
rm -f "$PV/terms.tsv"
t_eq "an absent overlay is not an error" "" "$(ovf)"
t_eq "core terms.tsv carries no client row" "" "$(awk -F'\t' '/^#/ || !h++ { next } $2 ~ /(^|,)client(,|$)/ { print $1 }' "$REG/terms.tsv")"
t_has "positive control: without the overlay a system prefix is unregistered" "$(chk env ACME_LINT_X)" "not a registered system"
{ printf '%s\n' "$_hdr"; _row acme client; _row acme-tool system; _row acmesys system; } > "$PV/terms.tsv"
t_eq "a client row and a system row are accepted" "" "$(ovf)"
t_has "…and a system row takes effect: its env prefix is registered" "$(chk env ACMESYS_LINT_X)" "no finding"
mkdir -p "$OV/bin"; printf '#!/usr/bin/env sh\nACMESYS_NOPE_X=1\n' > "$OV/bin/probe.sh"
t_has "…and env_tokens reads it: a token under that prefix in the tree is judged" "$(HARBOR_SCOPE_PRIVATE="$PV" sh "$OV/bin/lint-name.sh" --root "$OV" --format findings 2>/dev/null)" "$(printf 'name.env\tenv:ACMESYS_NOPE_X')"
t_hasnt "…and not when the overlay is absent" "$(HARBOR_SCOPE_PRIVATE="$TMP/none" sh "$OV/bin/lint-name.sh" --root "$OV" --format findings 2>/dev/null)" "env:ACMESYS_NOPE_X"
rm -f "$OV/bin/probe.sh"
t_exit "…and the run is never unchecked" 0 sh -c 'HARBOR_SCOPE_PRIVATE="$1" sh "$2" --root "$3" >/dev/null 2>&1; test $? -le 1' _ "$PV" "$OV/bin/lint-name.sh" "$OV"
{ printf '%s\n' "$_hdr"; _row acme client; _row sneaky family; } > "$PV/terms.tsv"
t_has "a row of another class goes red" "$(ovf)" "private-term:sneaky"
t_has "…as a block finding, shown by --check" "$(chk env HARBOR_SCOPE_X)" "FAIL: [name.registry-shape] private-term:sneaky"
{ printf '%s\n' "$_hdr"; printf 'acme\tclient\tacme\t-\t-\tstable\n'; } > "$PV/terms.tsv"
t_has "a row with the wrong column count goes red" "$(ovf)" "name.registry-shape"
t_exit "…as a block finding, so the run fails" 1 sh -c 'HARBOR_SCOPE_PRIVATE="$1" sh "$2" --root "$3" --check env HARBOR_SCOPE_X >/dev/null 2>&1' _ "$PV" "$OV/bin/lint-name.sh" "$OV"
printf 'id\tclass\tpref\nacme\tclient\tacme\n' > "$PV/terms.tsv"
t_has "a header that differs from core's goes red" "$(ovf)" "name.registry-shape"
t_exit "…and a malformed overlay fails the run" 1 sh -c 'HARBOR_SCOPE_PRIVATE="$1" sh "$2" --root "$3" --check env HARBOR_SCOPE_X >/dev/null 2>&1' _ "$PV" "$OV/bin/lint-name.sh" "$OV"
{ printf '%s\n' "$_hdr"; _row acme client; _row acme client; } > "$PV/terms.tsv"
t_has "a repeated id in the overlay goes red" "$(ovf)" "name.registry-duplicate"
{ printf '%s\n' "$_hdr"; _row family client; } > "$PV/terms.tsv"
t_has "an id that collides with a core term goes red" "$(ovf)" "name.registry-duplicate"
_helm=$(printf helm | tr a-z A-Z)   # built, so the tree holds no legacy env name
{ printf '%s\n' "$_hdr"; _row helm system; } > "$PV/terms.tsv"
t_has "an id that is a core alias goes red" "$(chk env "$_helm"_ADMISSION_DISABLE)" "is a core alias"
t_has "…and --check does not let the alias through" "$(chk env "$_helm"_ADMISSION_DISABLE)" "FAIL: [name.registry-duplicate]"
{ printf '%s\n' "$_hdr"; _row AcmeSys client; } > "$PV/terms.tsv"
t_has "an id that is not lowercase kebab goes red" "$(ovf)" "name.registry-shape"
t_has "…and --check blocks it, not just warns" "$(chk env ACME_LINT_X)" "FAIL: [name.registry-shape]"
{ printf '\357\273\277%s\r\n' "$_hdr"; _row acme client | sed 's/$/\r/'; } > "$PV/terms.tsv"
t_eq "a BOM and CRLF are stripped, not a malformed overlay" "" "$(chk env ACME_LINT_X | grep 'FAIL:' || :)"
t_has "…and say so" "$(chk env ACME_LINT_X)" "CRLF line endings; they were stripped"
t_has "…and the BOM" "$(chk env ACME_LINT_X)" "byte-order mark"
PS="$TMP/priv space"; mkdir -p "$PS"; { printf '%s\n' "$_hdr"; _row acme system; } > "$PS/terms.tsv"
t_has "a private root with a space in it is read, not unchecked" "$(HARBOR_SCOPE_PRIVATE="$PS" sh "$OV/bin/lint-name.sh" --root "$OV" --check env ACME_LINT_X 2>&1)" "no finding"
{ printf '%s\n' "$_hdr"; _row sneaky family; } > "$PV/terms.tsv"
_hst="$(HARBOR_SCOPE_PRIVATE="$PV" sh "$LN" --self-test 2>&1)"; _hstrc=$?
t_eq "--self-test never reads the box's overlay, even a bad one" "exit 0" "exit $_hstrc"
rm -f "$PV/terms.tsv"
t_eq "restored, no overlay means no overlay finding" "" "$(ovf)"

t_section "pack overlays (harbor#950): <config dir>/terms.d/<id>.tsv adds a workload's system terms and nothing else"
PK="$CLAUDE_CONFIG_DIR/terms.d"; mkdir -p "$PK"
t_has "positive control: with no pack overlay a workload's prefix is unregistered" "$(chk env WIDGETSYS_LINT_X)" "not a registered system"
{ printf '%s\n' "$_hdr"; _row widgetsys system; } > "$PK/widget.tsv"
t_eq "a system row is accepted" "" "$(ovf)"
t_has "…and takes effect: its env prefix is registered" "$(chk env WIDGETSYS_LINT_X)" "no finding"
{ printf '%s\n' "$_hdr"; _row widget client; } > "$PK/widget.tsv"
t_has "a client row goes red: a pack registers systems only" "$(ovf)" "private-term:widget"
t_has "…as a block finding naming the pack file" "$(chk env HARBOR_SCOPE_X)" "terms.d/widget.tsv (pack overlay"
{ printf '%s\n' "$_hdr"; _row widgetsys system; } > "$PK/widget.tsv"; cp "$PK/widget.tsv" "$PK/other.tsv"
t_has "the same term in two packs goes red" "$(ovf)" "name.registry-duplicate"
rm -f "$PK/other.tsv"; cp "$PK/widget.tsv" "$PV/terms.tsv"
t_has "…and so does a term the private overlay also registers" "$(ovf)" "name.registry-duplicate"
rm -f "$PV/terms.tsv"; { printf '%s\n' "$_hdr"; _row family system; } > "$PK/widget.tsv"
t_has "a core term goes red" "$(ovf)" "name.registry-duplicate"
printf 'id\tclass\nwidgetsys\tsystem\n' > "$PK/widget.tsv"
t_has "a header that differs from core's goes red" "$(ovf)" "name.registry-shape"
t_exit "…and fails the run" 1 sh -c 'HARBOR_SCOPE_PRIVATE="$1" sh "$2" --root "$3" --check env HARBOR_SCOPE_X >/dev/null 2>&1' _ "$PV" "$OV/bin/lint-name.sh" "$OV"
_hst="$(sh "$LN" --self-test 2>&1)"; _hstrc=$?
t_eq "--self-test never reads a pack overlay, even a bad one" "exit 0" "exit $_hstrc"
CS="$TMP/cfg space"; mkdir -p "$CS/terms.d"; { printf '%s\n' "$_hdr"; _row widgetsys system; } > "$CS/terms.d/widget.tsv"
t_exit "a pack overlay path with whitespace is unchecked, never read short" 3 env CLAUDE_CONFIG_DIR="$CS" sh "$OV/bin/lint-name.sh" --root "$OV" --check env WIDGETSYS_LINT_X
rm -rf "$PK"
t_eq "restored, no pack overlay means no finding" "" "$(ovf)"

t_section "field grammar and severity priority (harbor#1001)"
t_has "a retired time spelling goes red" "$(sh "$LN" --check field created_ts 2>&1)" "[name.field] field:created_ts"
t_hasnt "its successor stays green" "$(sh "$LN" --check field created_at 2>&1)" "name.field"
F="$TMP/field"; mini "$F"
sed 's/^\(id.term.kind.surfaces.remove_by.\)note$/\1note_ts/' "$F/standards/naming/aliases.tsv" > "$TMP/al"; mv "$TMP/al" "$F/standards/naming/aliases.tsv"
t_has "a register header column off the grammar goes red" "$(sh "$F/bin/lint-name.sh" --root "$F" 2>&1)" "column:aliases.tsv:note_ts"
sed 's/^\(critical.*	\)p0\(	\)/\1p1\2/' "$F/standards/naming/terms.tsv" > "$TMP/tm"; mv "$TMP/tm" "$F/standards/naming/terms.tsv"
t_has "two severities setting one priority go red" "$(sh "$F/bin/lint-name.sh" --root "$F" 2>&1)" "is already set by"
t_done
