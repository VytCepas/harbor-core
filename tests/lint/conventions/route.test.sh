#!/usr/bin/env sh
# lint.route-covers-surfaces (harbor#1397) — a surface in surfaces.tsv with no row in default-way-route.tsv is a finding, a row
# naming a surface that is not there is one, and the repo's own two registers are clean. Red first, then green.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
RP="$TMP/route"
reg() { # <mode> → a fixture register holding the one lint rule at that mode
  printf 'id\tmode\ttype\tengine\tsurfaces\tmoment\tfunction\tstability\tsuccessor\towner\tred_proof\temitted\ttitle\nlint.route-covers-surfaces\t%s\tlint\tbin/lint-conventions.sh\t-\tci\tdetective\texperimental\t-\tlint\t-\t-\tfixture\n' "$1" > "$RP.reg"
}
runr() { # <mode> <root> → output and exit status of the rule alone
  reg "$1"; HARBOR_LINT_CONTROLS="$RP.reg" HARBOR_SCOPE_ROOT="$2" sh "$LINT" --only lint.route-covers-surfaces 2>&1; printf 'exit=%s\n' "$?"
}
fx() { # <root> <routes file body> — a tree with two surfaces
  rm -rf "$1"; mkdir -p "$1/standards/naming" "$1/context-rules/user"
  printf '# surfaces\nid\trenderer\nskill\tkebab\nbin\tkebab\n' > "$1/standards/naming/surfaces.tsv"
  printf '# routes\nkind\ttools\trecogniser\tcontent\tquiet\thome\tinstall\treason\tsurface\tdeny\n%s\n' "$2" > "$1/context-rules/user/default-way-route.tsv"
}
ROW='skill	Write	cfg:skills/*	-	-	h	i	r	%s	-'

t_section "a surface with no route row is a finding"
fx "$RP.a" "$(printf "$ROW" skill)"
_o="$(runr warn "$RP.a")"
t_has "warn: advisory naming the surface" "$_o" 'ADVISORY [lint.route-covers-surfaces] bin: the surface has no row'
t_has "warn: exit 0" "$_o" 'exit=0'
_o="$(runr block "$RP.a")"
t_has "block: the same finding fails the run" "$_o" 'VIOLATION [lint.route-covers-surfaces] bin: the surface has no row'
t_has "block: exit 1" "$_o" 'exit=1'

t_section "green once a row names it, including a row that says no session builds it by default"
fx "$RP.b" "$(printf "$ROW" skill)
named-in-a-checkout	-	-	-	-	home	-	why	bin	-"
_o="$(runr block "$RP.b")"
t_hasnt "no finding" "$_o" 'lint.route-covers-surfaces]'
t_has "exit 0" "$_o" 'exit=0'

t_section "a row naming a surface that is not there, and a row with no surface cell, are findings"
fx "$RP.c" "$(printf "$ROW" skill)
other	-	-	-	-	home	-	why	bin,nothing-here	-
bare	Write	cfg:x/*	-	-	home	i	r"
_o="$(runr block "$RP.c")"
t_has "dangling surface" "$_o" 'other: names the surface nothing-here'
t_has "missing cell" "$_o" 'bare: has no surface cell'

t_section "the repo's own registers are clean"
_o="$(HARBOR_SCOPE_ROOT="$T_ROOT" sh "$LINT" --only lint.route-covers-surfaces 2>&1; printf 'exit=%s\n' "$?")"
t_hasnt "no finding on the real tree" "$_o" 'lint.route-covers-surfaces] '
t_has "exit 0" "$_o" 'exit=0'
t_done
