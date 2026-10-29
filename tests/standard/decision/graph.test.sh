#!/usr/bin/env sh
# graph-gen decision edges (harbor#1029): `defines` (a record's alias line), `decided-by` (a citation in the
# tree, vendor and the records excluded) and `revised-by` (a record's revised_by line). A citation whose id
# has no record is still an edge, so `refs D-n` shows where it dangles. Hermetic: a fixture harbor tree.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/graph-gen.sh"
command -v python3 >/dev/null 2>&1 || { t_section "python3 is absent"; t_exit "graph-gen is unchecked without python3" 3 sh "$TOOL"; t_done; }
HB="$T_TMP/hb"; mkdir -p "$HB/docs/decisions" "$HB/standards" "$HB/bin" "$HB/vendor"
DANG="D-$((900 + 1))"   # no record carries it; built here so this file cites nothing
rec() { printf -- '---\nkind: decision-record\nstatus: accepted\nalias: %s\ndate: 2026-10-04\nsource: x\n---\n\n# %s\n' "$1" "$2"; }
rec D-1 One > "$HB/docs/decisions/0001-one.md"
{ rec D-2 Two; printf 'revised_by: D-1\n'; } > "$HB/docs/decisions/0002-two.md"
printf 'the rule is D-1 here\n' > "$HB/standards/a.md"
printf '# x\nthe old rule was D-1 and a new one %s\n' "$DANG" > "$HB/bin/c.sh"
printf 'vendored D-1\n' > "$HB/vendor/v.md"
git -C "$HB" init -q && git -C "$HB" add -A
G="$HB/build/graph.tsv"
gen() { sh "$TOOL" --root "$HB" "$@"; }
row() { awk -F'\t' -v e="$1" -v f="$2" -v t="$3" '$1 == e && $2 == f && $3 == t { n++ } END { print n + 0 }' "$G"; }
gen >/dev/null 2>&1

t_section "defines: the alias line of a record names its id"
t_eq "D-1 is defined by its record" "1" "$(row defines harbor:docs/decisions/0001-one.md decision:D-1)"

t_section "decided-by: a citation points at the id, from the citing file's line"
t_eq "standards/a.md cites D-1 once" "1" "$(row decided-by harbor:standards/a.md decision:D-1)"
t_has "...with its site" "$(cat "$G")" "$(printf 'decided-by\tharbor:bin/c.sh\tdecision:%s\tharbor:bin/c.sh:2' "$DANG")"
t_eq "a dangling citation is an edge to an id with no defines row" "0" "$(awk -F'\t' -v d="decision:$DANG" '$1 == "defines" && $3 == d' "$G" | wc -l | tr -d ' ')"
t_eq "vendored text makes no edge" "0" "$(awk -F'\t' '$1 == "decided-by" && $2 ~ /^harbor:vendor\//' "$G" | wc -l | tr -d ' ')"
t_eq "a record's own text makes no decided-by edge" "0" "$(awk -F'\t' '$1 == "decided-by" && $2 ~ /^harbor:docs\/decisions\//' "$G" | wc -l | tr -d ' ')"

t_section "revised-by: a record's revised_by line"
t_eq "D-2 is revised by D-1" "1" "$(row revised-by decision:D-2 decision:D-1)"

t_section "refs answers by the alias, and the sites diff to the citing lines"
R="$(gen --refs D-1 2>/dev/null)"; t_has "refs D-1 lists the record that defines it" "$R" "defines"
t_has "...and the citing file" "$R" "harbor:standards/a.md"
t_eq "refs --sites D-1 names the citing line" "standards/a.md:1" "$(gen --refs --sites D-1 2>/dev/null | grep 'standards/a.md')"
t_exit "refs of a dangling id answers, so the dangling site is reachable" 0 gen --refs "$DANG"

t_section "same input, same bytes"
gen --check >/dev/null 2>&1; t_exit "--check is green on a fresh build" 0 gen --check
t_done
