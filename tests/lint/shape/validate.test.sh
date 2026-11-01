#!/usr/bin/env sh
# standard.shape (harbor#996 G2): bin/standard-shape.sh judges the reference graph against kinds.tsv's shapes, on the
# catalog's instances, and bin/lint-conventions.sh relays it (standard.shape-conform). Every relation term is proven
# red on its own fixture under fixtures/standard-shape/. The red proofs: drop an expected finding, the edge that keeps
# an instance green, or a relation's fixture, and the self-test exits 1.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
TOOL="$T_ROOT/bin/standard-shape.sh"; FX="$T_ROOT/fixtures/standard-shape"; REG="$T_ROOT/standards/naming"
setmode() { # <registry dir> <mode> [<id>]: what the live registry says must not decide what this suite proves
  awk -F'\t' -v OFS='\t' -v m="$2" -v id="${3:-standard.shape}" '$1 == id { $2 = m } { print }' "$1/controls.tsv" > "$1/c.tmp" && mv "$1/c.tmp" "$1/controls.tsv"; }
PIN="$T_TMP/pin"; cp -R "$REG" "$PIN"; setmode "$PIN" warn   # the registry, with standard.shape pinned to warn
# findings <case> [extra args] → the A/V records on stdout, stderr dropped
findings() { _c="$1"; shift; sh "$TOOL" --root "$T_ROOT" --registry "$PIN" --kinds "$FX/kinds.tsv" --graph "$FX/$_c/graph.tsv" --targets "$FX/$_c/targets.tsv" --format findings "$@" 2>/dev/null; }
# mkroot <name> → a root holding a copy of the fixtures and the real registry, for edits the live files must not take
mkroot() { _r="$T_TMP/$1"; mkdir -p "$_r/fixtures" "$_r/standards"; cp -R "$FX" "$_r/fixtures/standard-shape"; cp -R "$REG" "$_r/standards/naming"; printf '%s' "$_r"; }

t_section "the self-test passes, and every relation term goes red on its own fixture"
t_exit "--self-test exits 0" 0 sh "$TOOL" --self-test
RED0="$T_TMP/red0"; : > "$RED0"; LINT_REDLOG="$RED0" sh "$TOOL" --self-test >/dev/null 2>&1
t_eq "...and its red log names the rule (what a caller's LINT_REDLOG reads)" "standard.shape" "$(sort -u "$RED0")"
for r in $(awk -F'\t' '/^#/ || $1 == "id" { next } ("," $2 ",") ~ /,relation,/ { print $1 }' "$REG/terms.tsv"); do
  t_has "red-$r: the instance without $r" "$(findings "red-$r")" "A	standard.shape	fx:bad $r"
done

t_section "what must NOT be a finding"
t_hasnt "an instance that carries the relation" "$(findings red-notifies)" "fx:ok"
t_has "two distinct targets break 1..1" "$(findings over-max)" "A	standard.shape	fx:two registered-in"
t_hasnt "one target at two sites is one target, within 1..1" "$(findings over-max)" "fx:twice"
t_hasnt "exactly one is within 1..1" "$(findings over-max)" "fx:one"
t_eq "valid but unusual (min 0, max *, no shape, unknown kind, short row) yields nothing" "" "$(findings pass-unusual)"
t_exit "...and exits 0" 0 sh "$TOOL" --root "$T_ROOT" --kinds "$FX/kinds.tsv" --graph "$FX/pass-unusual/graph.tsv" --targets "$FX/pass-unusual/targets.tsv"
t_eq "a relation the graph does not derive is not a finding" "" "$(findings unchecked-undeclared)"
t_has "...it is a note that says it was not judged" "$(sh "$TOOL" --root "$T_ROOT" --kinds "$FX/kinds.tsv" --graph "$FX/unchecked-undeclared/graph.tsv" --targets "$FX/unchecked-undeclared/targets.tsv" 2>&1 >/dev/null)" "unchecked: the graph derives no listed-in edges, so the shape of k-listed-in over listed-in was not judged"

t_section "the mode is controls.tsv's: warn prints, shadow records only, block fails"
t_eq "standard.shape has one registry row, its mode shadow, warn or block" 1 "$(awk -F'\t' '$1 == "standard.shape" { print $2 }' "$REG/controls.tsv" | grep -cxE 'shadow|warn|block')"
t_eq "standard.shape-conform has one registry row, its mode shadow, warn or block" 1 "$(awk -F'\t' '$1 == "standard.shape-conform" { print $2 }' "$REG/controls.tsv" | grep -cxE 'shadow|warn|block')"
R="$(mkroot shadow)"; setmode "$R/standards/naming" shadow
t_exit "the self-test passes in shadow: it reads SHAPE_FINDINGS, never what the mode lets it print" 0 sh "$TOOL" --self-test --root "$R" --registry "$R/standards/naming"
ARGS="--root $R --kinds $FX/kinds.tsv --graph $FX/red-notifies/graph.tsv --targets $FX/red-notifies/targets.tsv"
OUT="$(sh "$TOOL" $ARGS --format findings 2>&1)"
t_hasnt "shadow prints no finding" "$OUT
x" "fx:bad"
RED="$T_TMP/red"; : > "$RED"; LINT_REDLOG="$RED" sh "$TOOL" $ARGS >/dev/null 2>&1
t_eq "...but the rule is red in the log" "standard.shape" "$(sort -u "$RED")"
t_exit "...and still exits 0" 0 sh "$TOOL" $ARGS
R="$(mkroot block)"; setmode "$R/standards/naming" block
t_exit "...and in block" 0 sh "$TOOL" --self-test --root "$R" --registry "$R/standards/naming"
ARGS="--root $R --kinds $FX/kinds.tsv --graph $FX/red-notifies/graph.tsv --targets $FX/red-notifies/targets.tsv"
t_exit "block exits 1" 1 sh "$TOOL" $ARGS
t_has "...and prints a V record" "$(sh "$TOOL" $ARGS --format findings 2>/dev/null)" "V	standard.shape	fx:bad notifies"

t_section "red proof: a fixture that stops yielding its finding, or yields one it did not expect, fails the self-test"
R="$(mkroot red-expect)"; : > "$R/fixtures/standard-shape/red-notifies/expect.tsv"
t_exit "an expected finding removed -> exit 1" 1 sh "$TOOL" --self-test --root "$R" --registry "$R/standards/naming"
R="$(mkroot red-edge)"; grep -v '^notifies	fx:ok' "$R/fixtures/standard-shape/red-notifies/graph.tsv" > "$R/g.tmp" && mv "$R/g.tmp" "$R/fixtures/standard-shape/red-notifies/graph.tsv"
t_exit "the edge that keeps fx:ok green removed -> exit 1" 1 sh "$TOOL" --self-test --root "$R" --registry "$R/standards/naming"
R="$(mkroot red-extra)"; grep -v 'fx:u	fam:b' "$R/fixtures/standard-shape/pass-unusual/graph.tsv" > "$R/g.tmp" && mv "$R/g.tmp" "$R/fixtures/standard-shape/pass-unusual/graph.tsv"
t_exit "a pass fixture that goes red (owned-by 1, needs 2..*) -> exit 1" 1 sh "$TOOL" --self-test --root "$R" --registry "$R/standards/naming"
R="$(mkroot red-rel)"; for _f in graph targets expect; do rm "$R/fixtures/standard-shape/red-owned-by/$_f.tsv"; done; rmdir "$R/fixtures/standard-shape/red-owned-by"
t_exit "a relation no fixture turns red -> exit 1" 1 sh "$TOOL" --self-test --root "$R" --registry "$R/standards/naming"
t_has "...and the self-test names it" "$(sh "$TOOL" --self-test --root "$R" --registry "$R/standards/naming" 2>&1)" "relation owned-by never went red"
t_exit "no fixtures at all is unchecked, not a pass" 3 sh "$TOOL" --self-test --root "$T_TMP/home" --registry "$REG"

t_section "could not look is exit 3, never a pass"
t_exit "a missing graph" 3 sh "$TOOL" --root "$T_ROOT" --graph "$T_TMP/nope.tsv" --targets /dev/null
printf 'edge\tfrom\tto\tsite\n' > "$T_TMP/headless.tsv"
t_exit "a file that is not a graph.tsv" 3 sh "$TOOL" --root "$T_ROOT" --graph "$T_TMP/headless.tsv" --targets /dev/null
awk -F'\t' -v OFS='\t' '$1 == "k-one" { $11 = "registered-in:2..1" } { print }' "$FX/kinds.tsv" > "$T_TMP/bad-kinds.tsv"
t_exit "a bound with min above max" 3 sh "$TOOL" --root "$T_ROOT" --kinds "$T_TMP/bad-kinds.tsv" --graph "$FX/over-max/graph.tsv" --targets /dev/null
awk -F'\t' -v OFS='\t' '$1 == "k-one" { $11 = "registered-in:one" } { print }' "$FX/kinds.tsv" > "$T_TMP/bad-kinds.tsv"
t_exit "a bound that is not <min>..<max>" 3 sh "$TOOL" --root "$T_ROOT" --kinds "$T_TMP/bad-kinds.tsv" --graph "$FX/over-max/graph.tsv" --targets /dev/null
mkdir -p "$T_TMP/empty/standards"; cp -R "$REG" "$T_TMP/empty/standards/naming"
t_exit "no build/graph.tsv in the root" 3 sh "$TOOL" --root "$T_TMP/empty"
t_exit "an unknown option is usage" 2 sh "$TOOL" --bogus

t_section "the real registry: every shape parses, and the catalog lists the instances"
t_exit "kinds.tsv's shapes all parse" 0 sh "$TOOL" --root "$T_ROOT" --graph "$FX/over-max/graph.tsv" --targets /dev/null
TG="$(sh "$T_ROOT/bin/standard-catalog.sh" --targets 2>/dev/null)"
t_has "a lint rule is a control of kind lint-rule" "$TG" "control:name.case	lint-rule"
t_has "a check row is a control of kind check" "$TG" "control:check.alerting	check"
t_has "the constitution is an instance of policy" "$TG" "harbor:policy/constitution.md	policy"
t_eq "a file the census cannot place is no instance" 0 "$(printf '%s\n' "$TG" | awk -F'\t' '$2 == "-"' | wc -l | tr -d ' ')"

t_section "the real tree, in warn: a fresh graph is judged and the run exits 0"
if command -v python3 >/dev/null 2>&1; then
  sh "$T_ROOT/bin/doc-graph-generate.sh" --out "$T_TMP/real-graph.tsv" >/dev/null 2>&1
  _rc=0; OUT="$(sh "$TOOL" --registry "$PIN" --graph "$T_TMP/real-graph.tsv" 2>&1)" || _rc=$?
  t_eq "exits 0: every finding is warn" 0 "$_rc"
  t_hasnt "no shape is left unchecked: graph-gen derives every relation kinds.tsv requires" "$OUT
x" "unchecked:"
  t_eq "every check is registered in docs/reference/checks.md exactly once" 0 "$(printf '%s\n' "$OUT" | grep -c ' registered-in — ' || :)"
else
  t_section "python3 is absent: the real graph cannot be built here"
fi

t_section "bin/lint-conventions.sh relays the findings as advisories and exits clean"
if command -v python3 >/dev/null 2>&1; then
  D="$T_TMP/relay"; mkdir -p "$D/bin" "$D/standards" "$D/contracts"
  for _b in standard-shape.sh doc-graph-generate.sh standard-catalog.sh library-log.sh scope-roots.sh; do cp "$T_ROOT/bin/$_b" "$D/bin/"; done
  cp "$T_ROOT/contracts/roots.tsv" "$D/contracts/"; cp -R "$PIN" "$D/standards/naming"
  ( cd "$D" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm x ) >/dev/null 2>&1
  OUT="$(lint1 standard.shape-conform "$D")"
  t_has "the advisory carries the relayed id and the instance" "$OUT" "ADVISORY [standard.shape-conform] [standard.shape] control:name.case red-proof"
  t_eq "no violation: a warn rule never fails the run" "0" "$(vcount "$OUT")"
  RED="$T_TMP/red2"; : > "$RED"; LINT_REDLOG="$RED" lint1 standard.shape-conform "$D" >/dev/null
  t_has "the red log names the shape rule" "$(cat "$RED")" "standard.shape"
  t_hasnt "...and never the relay id for a warn finding" "$(cat "$RED"; echo x)" "standard.shape-conform"
  awk -F'\t' -v OFS='\t' '$1 == "check" { $11 = "notifies:3..1" } { print }' "$REG/kinds.tsv" > "$D/standards/naming/kinds.tsv"
  OUT="$(lint1 standard.shape-conform "$D")"
  t_has "a shape that does not parse judges nothing, and the relay goes red" "$OUT" "VIOLATION [standard.shape-conform] bin/standard-shape.sh exited 3"
  RED="$T_TMP/red3"; : > "$RED"; LINT_REDLOG="$RED" lint1 standard.shape-conform "$D" >/dev/null
  t_has "...under the relay id" "$(cat "$RED")" "standard.shape-conform"
else
  D="$T_TMP/relay"; mkdir -p "$D/bin"; cp "$T_ROOT/bin/standard-shape.sh" "$T_ROOT/bin/doc-graph-generate.sh" "$D/bin/"
  t_has "without python3 the advisory says it could not look" "$(lint1 standard.shape-conform "$D")" "unchecked: python3 is absent"
fi
D="$T_TMP/bare"; mkdir -p "$D/bin"
t_has "a tree with neither tool is skipped, said so" "$(lint1 standard.shape-conform "$D")" "skip: no bin/standard-shape.sh"
t_eq "...with no violation" "0" "$(vcount "$(lint1 standard.shape-conform "$D")")"

t_done
