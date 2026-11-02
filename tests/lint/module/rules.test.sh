#!/usr/bin/env sh
# module.* rules (harbor#996 C1): bin/lint-module.sh judges the reference graph, bin/lint-conventions.sh relays it.
# Each rule is proven on a fixture graph under fixtures/lint-module/, so nothing here depends on the live tree.
# The red proofs: remove an expected id, or the edge that yields it, and the self-test exits 1.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
TOOL="$T_ROOT/bin/lint-module.sh"; FX="$T_ROOT/fixtures/lint-module"; REG="$T_ROOT/standards/naming"
# findings <case> [extra args] → the A/V records on stdout, stderr dropped. Every case reads its cited lines from its own tree/.
findings() { _c="$1"; shift; sh "$TOOL" --root "$T_ROOT" --terms "$FX/$_c/terms.tsv" --graph "$FX/$_c/graph.tsv" --sites "$FX/$_c/tree" --format findings "$@" 2>/dev/null; }
rc_of() { _c="$1"; shift; sh "$TOOL" --root "$T_ROOT" --terms "$FX/$_c/terms.tsv" --graph "$FX/$_c/graph.tsv" --sites "$FX/$_c/tree" "$@" >/dev/null 2>&1; echo $?; }
# messages <case> → the warnings on stderr (they name the site a person confirms), stdout dropped
messages() { _c="$1"; shift; sh "$TOOL" --root "$T_ROOT" --terms "$FX/$_c/terms.tsv" --graph "$FX/$_c/graph.tsv" --sites "$FX/$_c/tree" "$@" 2>&1 >/dev/null; }
# mkroot <name> → a root holding a copy of the fixtures and the real registry, for edits the live files must not take
mkroot() { _r="$T_TMP/$1"; mkdir -p "$_r/fixtures" "$_r/standards"; cp -R "$FX" "$_r/fixtures/lint-module"; cp -R "$REG" "$_r/standards/naming"; printf '%s' "$_r"; }

t_section "the self-test passes, and each of five fixtures yields its id"
t_exit "--self-test exits 0" 0 sh "$TOOL" --self-test
RED0="$T_TMP/red0"; : > "$RED0"; LINT_REDLOG="$RED0" sh "$TOOL" --self-test >/dev/null 2>&1
t_eq "...and its red log names all five rules (what a caller's LINT_REDLOG reads)" "module.cross-system-path module.family-cycle module.layer-direction module.private-use module.system-cycle" "$(sort -u "$RED0" | tr '\n' ' ' | sed 's/ $//')"
t_has "an upward layer read" "$(findings layer-direction)" "A	module.layer-direction	sysa:bin/alpha-run.sh -> sysa:docs/generated/index.txt"
t_has "a family cycle" "$(findings family-cycle)" "A	module.family-cycle	alpha,beta"
t_has "a declared family cycle (terms.tsv depends_on), with no graph edge at all" "$(findings family-cycle-declared)" "A	module.family-cycle	alpha,beta"
t_has "a system cycle" "$(findings system-cycle)" "A	module.system-cycle	sysa,sysb"
t_has "a cross-system path" "$(findings cross-system-path)" "A	module.cross-system-path	sysa:bin/alpha-run.sh -> sysb:src/internal/engine.py"
t_has "a private use" "$(findings private-use)" "A	module.private-use	sysa:bin/alpha-run.sh -> sysa:bin/beta-lib.sh"

t_section "what must NOT be a finding"
t_hasnt "a contract path is the allowed crossing" "$(findings cross-system-path)" "zeta-contract.md"
t_hasnt "prose (docs/*.md) names a path and reads nothing" "$(findings cross-system-path)" "docs/notes.md"
t_hasnt "the generator may read its own output" "$(findings layer-direction)" "alpha-gen.sh"
t_hasnt "a test naming the file it tests is not an upward read" "$(findings layer-direction)" "tests/alpha"
t_hasnt "a generated file reading its source is the downward direction" "$(findings layer-direction)" "docs/generated/index.txt -> "
t_hasnt "a family's own lib file is not private use" "$(findings private-use)" "beta-run.sh -> sysa:bin/beta-lib.sh"
t_eq "the clean graph yields nothing" "" "$(findings clean)"
t_exit "...and exits 0" 0 sh "$TOOL" --root "$T_ROOT" --terms "$FX/clean/terms.tsv" --graph "$FX/clean/graph.tsv"

t_section "a mention that cannot read is set aside, and the live twin of each still goes red (harbor#996 C1)"
t_eq "a comment, a longer name, a register, a test: nothing is a finding" "" "$(findings inert-mentions)"
t_eq "...and --format inert lists exactly what was set aside, with why: every pair, a family or system edge too, and a test's path of another system, but not a test's contract or its own system" "comment	sysa:bin/alpha-run -> sysa:bin/beta-run	sysa:bin/alpha-run:5
comment	sysa:bin/alpha-run -> sysa:docs/generated/index.txt	sysa:bin/alpha-run:2
comment	sysa:bin/beta-run -> sysb:contracts/seam.md	sysa:bin/beta-run:3
comment	sysa:src/pkg/alpha/mod -> sysb:src/internal/engine	sysa:src/pkg/alpha/mod:2
longer-name	sysa:bin/alpha-run -> sysa:docs/generated/plan.md	sysa:bin/alpha-run:3
test	sysa:tests/alpha/run.test -> sysb:src/internal/engine	sysa:tests/alpha/run.test:2" "$(findings inert-mentions --format inert)"
t_has "...and the run counts them, so the count in the log is the list's length" "$(messages inert-mentions)" "6 pair(s) set aside"
t_exit "...and exits 0" 0 sh "$TOOL" --root "$T_ROOT" --terms "$FX/inert-mentions/terms.tsv" --graph "$FX/inert-mentions/graph.tsv" --sites "$FX/inert-mentions/tree"
LIVE="$(findings live-mentions)"
t_has "a code line with a trailing comment still reads (layer-direction)" "$LIVE" "A	module.layer-direction	sysa:bin/alpha-run -> sysa:docs/generated/index.txt"
t_has "a line holding docs/reports/qa-plan.md AND docs/generated/plan.md still reads docs/generated/plan.md" "$LIVE" "A	module.layer-direction	sysa:bin/alpha-run -> sysa:docs/generated/plan.md"
t_has "a code line in a TypeScript file with a trailing // comment still reads (cross-system-path)" "$LIVE" "A	module.cross-system-path	sysa:src/pkg/alpha/mod -> sysb:src/internal/engine"
t_has "a register-shaped file OUTSIDE the contract areas is still judged" "$LIVE" "A	module.cross-system-path	sysa:ops/roots.tsv -> sysb:src/internal/engine"
t_has "a family cycle between two code files still goes red" "$LIVE" "A	module.family-cycle	alpha,beta"
t_has "a graph whose cited line no longer holds the path is never inert" "$LIVE" "A	module.layer-direction	sysa:bin/gamma-run -> sysa:docs/generated/index.txt"
t_has "a cited line past the end of the file is never inert" "$LIVE" "A	module.layer-direction	sysa:bin/gamma-run -> sysa:docs/generated/plan.md"
t_has "a pair with a comment site AND a code site names the code site" "$(messages live-mentions)" "sysa:bin/alpha-run -> sysa:docs/generated/index.txt — source code reads a generated file; a layer reads only the one below it (standard section 5; sysa:bin/alpha-run:3)"
t_hasnt "...and never the comment before it" "$(messages live-mentions)" "sysa:bin/alpha-run:2)"
t_eq "a case with no tree/ cannot be read, so every finding stands: the older fixtures judge the graph alone" "A	module.layer-direction	sysa:bin/alpha-run.sh -> sysa:docs/generated/index.txt" "$(findings layer-direction)"

t_section "red proof: break each cut and the fixtures notice (a mutant of bin/lint-module.sh, then the tool as shipped)"
# mutant <name> [sed script] → a root holding a copy of the tool, with one cut broken by the script; NOCHANGE when it matched nothing
mutant() {
  _m="$(mkroot "mut-$1")"; mkdir -p "$_m/bin"; cp "$T_ROOT/bin/library-log.sh" "$_m/bin/"
  if [ -z "${2-}" ]; then cp "$TOOL" "$_m/bin/lint-module.sh"; printf '%s' "$_m"; return 0; fi
  sed "$2" "$TOOL" > "$_m/bin/lint-module.sh"
  if cmp -s "$TOOL" "$_m/bin/lint-module.sh"; then printf 'NOCHANGE'; else printf '%s' "$_m"; fi
}
mrun() { _r="$1"; _c="$2"; shift 2; sh "$_r/bin/lint-module.sh" --root "$T_ROOT" --registry "$REG" --terms "$FX/$_c/terms.tsv" --graph "$FX/$_c/graph.tsv" --sites "$FX/$_c/tree" "$@"; }
mfind() { mrun "$1" "$2" --format findings 2>/dev/null; }
mmsgs() { mrun "$1" "$2" 2>&1 >/dev/null; }
mself() { sh "$1/bin/lint-module.sh" --self-test --root "$1" --registry "$1/standards/naming" >/dev/null 2>&1; echo $?; }
t_eq "the harness notices a script that changes nothing" "NOCHANGE" "$(mutant noop 's/set -eu/set -eu/')"
M="$(mutant intact)"
t_eq "control: a copy with nothing broken passes its self-test" "0" "$(mself "$M")"
M="$(mutant comment 's/return "comment"/return ""/')"
t_eq "comments no longer set aside -> the pass fixture goes red, self-test exits 1" "1" "$(mself "$M")"
M="$(mutant longer-name 's/return whole ? "" : "longer-name"/return ""/')"
t_eq "a longer name no longer set aside -> the pass fixture goes red, self-test exits 1" "1" "$(mself "$M")"
M="$(mutant register 's/ || contract(n)) }/) }/')"
t_eq "a register row judged again -> the pass fixture goes red, self-test exits 1" "1" "$(mself "$M")"
M="$(mutant tests 's/evals|tests|fixtures/evals/')"
t_eq "tests judged again -> the pass fixture goes red, self-test exits 1" "1" "$(mself "$M")"
M="$(mutant fam-edge '/layer = (generated/,$ s/if (s == "") { inertrec(f, t, SITE\[k, 1\]); continue }/if (s == "") { inertrec(f, t, SITE[k, 1]); if (famedge) addedge("fam", ff, ft); continue }/')"
t_eq "a comment-only family edge counted in the cycle graph again -> the pass fixture goes red (alpha,beta), self-test exits 1" "1" "$(mself "$M")"
t_has "...and the red is the family cycle" "$(mfind "$M" inert-mentions)" "A	module.family-cycle	alpha,beta"
M="$(mutant sys-edge '/^      if (sf != st) {/,/^      }$/ s/if (s == "") { inertrec(f, t, SITE\[k, 1\]); continue }/if (s == "") { inertrec(f, t, SITE[k, 1]); addedge("sys", sf, st); continue }/')"
t_eq "a comment-only system edge counted in the cycle graph again -> the pass fixture goes red (sysa,sysb), self-test exits 1" "1" "$(mself "$M")"
t_has "...and the red is the system cycle" "$(mfind "$M" inert-mentions)" "A	module.system-cycle	sysa,sysb"
minert() { mrun "$1" "$2" --format inert 2>/dev/null; }
M="$(mutant list-fam '/layer = (generated/,$ s/if (s == "") { inertrec(f, t, SITE\[k, 1\]); continue }/if (s == "") { if (layer || (famedge \&\& private(t))) inertrec(f, t, SITE[k, 1]); continue }/')"
t_hasnt "a comment-only family edge left out of --format inert (the old condition) -> it is no longer listed" "$(minert "$M" inert-mentions)" "sysa:bin/alpha-run -> sysa:bin/beta-run"
M="$(mutant list-contract '/^      if (sf != st) {/,/^      }$/ s/if (s == "") { inertrec(f, t, SITE\[k, 1\]); continue }/if (s == "") { if (!contract(t)) inertrec(f, t, SITE[k, 1]); continue }/')"
t_hasnt "a comment-only edge to another system's contract left out of --format inert -> it is no longer listed" "$(minert "$M" inert-mentions)" "contracts/seam.md"
M="$(mutant list-test 's/{ WHY = "test"; inertrec(f, t, SITE\[k, 1\]) }/{ }/')"
t_hasnt "a test's path of another system not listed -> the cut is silent again" "$(minert "$M" inert-mentions)" "sysa:tests/alpha/run.test"
M="$(mutant list-test-contract 's/sf != st \&\& !contract(t) \&\& pathof(f)/sf != st \&\& pathof(f)/')"
t_has "a test's contract path listed too -> noise on ordinary work, caught" "$(minert "$M" inert-mentions)" "test	sysa:tests/alpha/run.test -> sysb:contracts/seam.md"
M="$(mutant unreadable 's/if (t == SENT) return ""/if (t == SENT) return "comment"/')"
t_eq "an unreadable line counted as inert -> the older fixtures go quiet, self-test exits 1" "1" "$(mself "$M")"
M="$(mutant any-hash '/if (t ~ .*return "comment"/s/.*/    if (index(t, "#") > 0) return "comment"/')"
t_hasnt "a # ANYWHERE counted as a comment -> a code line with a trailing comment stops reading" "$(mfind "$M" live-mentions)" "sysa:bin/alpha-run -> sysa:docs/generated/index.txt"
M="$(mutant any-tail 's/) whole = 1$/) whole = 0/')"
t_hasnt "any occurrence counted as a longer name -> a line that also holds docs/generated/plan.md whole stops reading" "$(mfind "$M" live-mentions)" "sysa:bin/alpha-run -> sysa:docs/generated/plan.md"
M="$(mutant stale 's/if (n == 0) return ""/if (n == 0) return "comment"/')"
t_hasnt "a line that does not hold the path counted as inert -> the stale-graph finding vanishes" "$(mfind "$M" live-mentions)" "sysa:bin/gamma-run -> sysa:docs/generated/index.txt"
M="$(mutant first-site 's/if (r == "") return SITE\[k, j\]/if (r == "") return SITE[k, 1]/')"
t_hasnt "the first site named instead of the first LIVE one -> the message points at the comment" "$(mmsgs "$M" live-mentions)" "sysa:bin/alpha-run:3)"

t_section "the modes are controls.tsv's: warn prints, shadow records only, block fails"
for _id in module.cross-system-path module.system-cycle module.family-cycle module.private-use module.layer-direction; do
  t_eq "$_id is warn in the registry" "warn" "$(awk -F'\t' -v i="$_id" '$1 == i { print $2 }' "$REG/controls.tsv")"
done
t_eq "module.family-shape stays shadow" "shadow" "$(awk -F'\t' '$1 == "module.family-shape" { print $2 }' "$REG/controls.tsv")"
setmode() { # <root> <rule> <mode>
  awk -F'\t' -v OFS='\t' -v r="$2" -v m="$3" '$1 == r { $2 = m } { print }' "$1/standards/naming/controls.tsv" > "$1/c.tmp" && mv "$1/c.tmp" "$1/standards/naming/controls.tsv"; }
R="$(mkroot modes)"; setmode "$R" module.private-use shadow
OUT="$(sh "$TOOL" --root "$R" --terms "$FX/private-use/terms.tsv" --graph "$FX/private-use/graph.tsv" --format findings 2>&1 >/dev/null)"; _rc=$?
RED="$T_TMP/red"; : > "$RED"; LINT_REDLOG="$RED" sh "$TOOL" --root "$R" --terms "$FX/private-use/terms.tsv" --graph "$FX/private-use/graph.tsv" >/dev/null 2>&1
t_hasnt "shadow prints no finding" "$OUT
x" "[module.private-use]"
t_eq "...but the rule is red in the log" "module.private-use" "$(sort -u "$RED")"
t_eq "...and still exits 0" "0" "$(sh "$TOOL" --root "$R" --terms "$FX/private-use/terms.tsv" --graph "$FX/private-use/graph.tsv" >/dev/null 2>&1; echo $?)"
R="$(mkroot block)"; setmode "$R" module.private-use block
t_eq "block exits 1" "1" "$(sh "$TOOL" --root "$R" --terms "$FX/private-use/terms.tsv" --graph "$FX/private-use/graph.tsv" >/dev/null 2>&1; echo $?)"
t_has "...and a V record" "$(sh "$TOOL" --root "$R" --terms "$FX/private-use/terms.tsv" --graph "$FX/private-use/graph.tsv" --format findings 2>/dev/null)" "V	module.private-use"

t_section "red proof: a fixture that stops yielding its id, or yields one it did not expect, fails the self-test"
R="$(mkroot red-expect)"; : > "$R/fixtures/lint-module/private-use/expect.tsv"
t_exit "an expected id removed -> exit 1" 1 sh "$TOOL" --self-test --root "$R" --registry "$R/standards/naming"
R="$(mkroot red-edge)"; grep -v 'beta-lib' "$R/fixtures/lint-module/private-use/graph.tsv" > "$R/g.tmp" && mv "$R/g.tmp" "$R/fixtures/lint-module/private-use/graph.tsv"
t_exit "the edge that yields the id removed -> exit 1" 1 sh "$TOOL" --self-test --root "$R" --registry "$R/standards/naming"
R="$(mkroot red-extra)"; printf 'references\tsysa:bin/alpha-run.sh\tsysb:src/x.py\tsysa:bin/alpha-run.sh:1\n' >> "$R/fixtures/lint-module/clean/graph.tsv"
t_exit "a pass fixture that goes red -> exit 1" 1 sh "$TOOL" --self-test --root "$R" --registry "$R/standards/naming"
R="$(mkroot red-rule)"; rm -r "$R/fixtures/lint-module/private-use"   # the one rule only this fixture turns red
t_exit "a rule no fixture turns red -> exit 1" 1 sh "$TOOL" --self-test --root "$R" --registry "$R/standards/naming"
t_exit "no fixtures at all is unchecked, not a pass" 3 sh "$TOOL" --self-test --root "$T_TMP/home" --registry "$REG"

t_section "bin/lint-conventions.sh relays the findings as advisories and exits clean"
if command -v python3 >/dev/null 2>&1; then
  D="$T_TMP/relay"; mkdir -p "$D/bin" "$D/standards" "$D/contracts" "$D/docs/generated"
  cp "$T_ROOT/bin/lint-module.sh" "$T_ROOT/bin/doc-graph-generate.sh" "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/scope-roots.sh" "$D/bin/"; cp "$T_ROOT/contracts/roots.tsv" "$D/contracts/"
  cp -R "$REG" "$D/standards/naming"
  printf '#!/bin/sh\ncat docs/generated/status.md\n' > "$D/bin/deploy-doctor.sh"
  printf '# STATUS\n\nRegenerate with `sh bin/status-generate.sh`\n' > "$D/docs/generated/status.md"
  printf '#!/bin/sh\n: generator\n' > "$D/bin/status-generate.sh"
  ( cd "$D" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm x ) >/dev/null 2>&1
  OUT="$(lint1 module.graph-conform "$D")"
  t_has "the advisory carries the relayed id and both ends" "$OUT" "ADVISORY [module.graph-conform] [module.layer-direction] harbor:bin/deploy-doctor.sh -> harbor:docs/generated/status.md"
  t_eq "no violation: a warn rule never fails the run" "0" "$(vcount "$OUT")"
  t_has "...and the run says so" "$OUT" "0 violations"
  RED="$T_TMP/red2"; : > "$RED"; LINT_REDLOG="$RED" lint1 module.graph-conform "$D" >/dev/null
  t_has "the red log names the module rule, not the relay" "$(cat "$RED")" "module.layer-direction"
  t_hasnt "...and never the relay id for a warn finding" "$(cat "$RED"; echo x)" "module.graph-conform"
else
  D="$T_TMP/relay"; mkdir -p "$D/bin"; cp "$T_ROOT/bin/lint-module.sh" "$T_ROOT/bin/doc-graph-generate.sh" "$D/bin/"
  t_has "without python3 the advisory says it could not look" "$(lint1 module.graph-conform "$D")" "unchecked: python3 is absent"
fi
D="$T_TMP/bare"; mkdir -p "$D/bin"
t_has "a tree with neither tool is skipped, said so" "$(lint1 module.graph-conform "$D")" "skip: no bin/lint-module.sh"
t_eq "...with no violation" "0" "$(vcount "$(lint1 module.graph-conform "$D")")"

t_done
