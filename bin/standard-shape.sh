#!/usr/bin/env sh
# standard-shape.sh (harbor#996 G2) — the shape validator: every instance of a kind carries the relations kinds.tsv requires.
#
#   sh bin/standard-shape.sh                     judge build/graph.tsv (it must be current: doc-graph-generate.sh --check)
#   sh bin/standard-shape.sh --graph <file>      judge that graph; the caller vouches it is current
#   sh bin/standard-shape.sh --self-test         every fixture yields exactly its expected findings, and every relation went red
#   sh bin/standard-shape.sh --list              the rule's id, mode and title, read from standards/naming/controls.tsv
#   sh bin/standard-shape.sh --help
#
#   --targets <file>    the instances, `<node> TAB <kind>` (default: what sh bin/standard-catalog.sh --targets prints)
#   --kinds <file>      the shapes (default: <registry>/kinds.tsv)
#   --format findings   also print one `<A|V> TAB standard.shape TAB <node> <relation>` record per finding on stdout
#   --root <dir>        the tree whose graph is judged (default: this checkout)
#   --registry <dir>    the registry (default: <root>/standards/naming): kinds.tsv, controls.tsv, terms.tsv
#
#   exit (D-49) 0 pass, warn and shadow findings allowed · 1 a block finding, or a failed self-test · 2 usage
#   · 3 unchecked: the graph is missing, stale or not a graph, the targets could not be read, or a bound is malformed.
#   LINT_REDLOG=<file> appends standard.shape once per finding, shadow ones too, as bin/lint-module.sh does.
#   SHAPE_FINDINGS=<file> appends `<node> <relation>` once per finding, shadow ones too: what --self-test reads, so its
#   verdict never depends on the rule's live mode (--format findings prints nothing in shadow).
#
# THE SHAPE. A kinds.tsv row's required_relations are `<relation>[:<min>..<max>]`, a bare name being 1..*. For every
# instance of the kind, the number of DISTINCT nodes it reaches over graph edges of that relation must fall in
# [min, max]. The instances are the catalog's (each tracked file by its kind, each controls.tsv row by its type), so
# no shape states its own scope. One rule, standard.shape; a finding names the instance and the relation.
# A RELATION THE GRAPH DOES NOT DERIVE IS UNCHECKED, NEVER RED: doc-graph-generate.sh writes a `# relation` row for each relation
# it derives, and a shape over any other relation is one note, not a finding per instance: "could not look" is not "absent".
#
# DELIBERATELY ONE FILE (docs/explanation/modularity.md): one POSIX sh + awk program, as bin/lint-module.sh is. awk joins three
# tables and counts; no python3 is needed to judge, only to build the graph.
set -eu

HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
SELF="$HERE/$(basename -- "$0")"
LOG_FD=2   # stdout carries --format findings and --list; the log goes to stderr
. "$HERE/library-log.sh"
log_init standard-shape

usage() { awk 'NR < 2 { next } /^# DELIBERATELY/ || !/^#/ { exit } { sub(/^# ?/, ""); print }' "$SELF"; }
unchecked() { log_fail "$1"; log_fix "$2"; log_end || :; exit 3; }
usage_err() { log_fail "$1"; log_fix "sh $SELF --help"; log_end || :; exit 2; }

ACTION=judge; FORMAT=""; ROOT=""; REG=""; GRAPH=""; EXPLICIT=0; TARGETS=""; KINDS=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --self-test) ACTION=self-test ;;
    --list) ACTION=list ;;
    --graph) [ $# -ge 2 ] || usage_err "--graph needs a file"; GRAPH="$2"; EXPLICIT=1; shift ;;
    --targets) [ $# -ge 2 ] || usage_err "--targets needs a file"; TARGETS="$2"; shift ;;
    --kinds) [ $# -ge 2 ] || usage_err "--kinds needs a file"; KINDS="$2"; shift ;;
    --root) [ $# -ge 2 ] || usage_err "--root needs a directory"; ROOT="$2"; shift ;;
    --registry) [ $# -ge 2 ] || usage_err "--registry needs a directory"; REG="$2"; shift ;;
    --format) [ $# -ge 2 ] || usage_err "--format needs a value"; FORMAT="$2"; shift ;;
    -*) usage_err "unknown option $1" ;;
    *) usage_err "unexpected argument $1" ;;
  esac
  shift
done
case "$FORMAT" in ''|findings) ;; *) usage_err "--format is findings" ;; esac
[ -n "$ROOT" ] || ROOT="$HERE/.."
ROOT="$(CDPATH='' cd -- "$ROOT" 2>/dev/null && pwd -P)" || usage_err "--root is not a directory"
[ -n "$REG" ] || REG="$ROOT/standards/naming"
[ -n "$KINDS" ] || KINDS="$REG/kinds.tsv"
CONTROLS="$REG/controls.tsv"
ID=standard.shape
T="$(mktemp -d "${TMPDIR:-/tmp}/standard-shape.XXXXXX")"
trap 'rm -rf "$T"' EXIT INT TERM HUP

# mode_of <id> → shadow | warn | block, from controls.tsv. advisory and inform are legacy spellings of warn.
mode_of() {
  awk -F'\t' -v id="$1" '/^#/ { next } $1 == id { m = $2; if (m == "advisory" || m == "inform") m = "warn"; print m; exit }' "$CONTROLS"
}

if [ "$ACTION" = list ]; then
  [ -f "$CONTROLS" ] || unchecked "no controls.tsv at $CONTROLS" "ls $REG"
  awk -F'\t' -v id="$ID" '/^#/ || $1 == "id" { next } $1 == id { printf "  %-26s %-7s %s\n", $1, $2, $13 }' "$CONTROLS"
  exit 0
fi

# ── the judge ────────────────────────────────────────────────────────────────
# judge <graph> <targets> <kinds> → `F TAB <node> <relation> TAB message` per finding, `U TAB relation TAB kinds` per
# shape over a relation the graph does not derive, `E TAB kind TAB shape` per malformed shape, `N TAB instances judged`.
judge() {
  awk -F'\t' -v GRAPH="$1" -v TARGETS="$2" -v KINDS="$3" '
  BEGIN {
    col = 0
    while ((getline l < KINDS) > 0) {
      if (l ~ /^#/ || l ~ /^[ \t]*$/) continue
      n = split(l, c, "\t")
      if (c[1] == "id") { for (i = 1; i <= n; i++) if (c[i] == "required_relations") col = i; continue }
      if (col == 0 || c[col] == "-" || c[col] == "") continue
      k = c[1]; m = split(c[col], s, " ")
      for (i = 1; i <= m; i++) {
        r = s[i]; lo = 1; hi = "*"
        if (index(r, ":") > 0) {
          b = substr(r, index(r, ":") + 1); r = substr(r, 1, index(r, ":") - 1)
          if (b !~ /^[0-9]+\.\.([0-9]+|\*)$/) { print "E\t" k "\t" s[i]; continue }
          lo = substr(b, 1, index(b, ".") - 1) + 0; hi = substr(b, index(b, "..") + 2)
          if (hi != "*" && lo > hi + 0) { print "E\t" k "\t" s[i]; continue }
        }
        NS[k]++; SR[k, NS[k]] = r; SLO[k, NS[k]] = lo; SHI[k, NS[k]] = hi
      }
    }
    close(KINDS)
    if (col == 0) { print "E\t-\tno required_relations column"; exit }
    while ((getline l < GRAPH) > 0) {
      n = split(l, c, "\t")
      if (c[1] == "# relation") { DECL[c[2]] = 1; continue }
      if (l ~ /^#/ || c[1] == "edge" || n < 3) continue
      if ((c[1], c[2], c[3]) in SEEN) continue
      SEEN[c[1], c[2], c[3]] = 1; CNT[c[1], c[2]]++
    }
    close(GRAPH)
    while ((getline l < TARGETS) > 0) {
      n = split(l, c, "\t")
      if (n < 2 || !(c[2] in NS)) continue
      x = c[1]; k = c[2]; judged++
      for (i = 1; i <= NS[k]; i++) {
        r = SR[k, i]
        if (!(r in DECL)) { if (index(" " UNC[r] " ", " " k " ") == 0) UNC[r] = UNC[r] (UNC[r] == "" ? "" : " ") k; continue }
        v = CNT[r, x] + 0
        if (v < SLO[k, i] || (SHI[k, i] != "*" && v > SHI[k, i] + 0))
          print "F\t" x " " r "\t" k " needs " SLO[k, i] ".." SHI[k, i] " " r " and this " k " has " v " (kinds.tsv)"
      }
    }
    close(TARGETS)
    for (r in UNC) print "U\t" r "\t" UNC[r]
    print "N\t" judged + 0
  }' /dev/null
}

# run <graph> <targets> <what> → judges and reports; returns 1 on a block finding
run() {
  judge "$1" "$2" "$KINDS" > "$T/out" || unchecked "the judge (awk) failed, so nothing was judged" "sh $SELF --help"
  _bad="$(awk -F'\t' '$1 == "E" { printf "%s%s %s", (n++ ? ", " : ""), $2, $3 }' "$T/out")"
  [ -z "$_bad" ] || unchecked "kinds.tsv has a shape that is not <relation>[:<min>..<max>], so nothing was judged: $_bad" "sh bin/lint-name.sh --check registry standards/naming"
  _m="$(mode_of "$ID")"
  [ -n "$_m" ] || unchecked "no controls.tsv row for $ID, so its mode is unknown" "add the row to $CONTROLS"
  awk -F'\t' '$1 == "F"' "$T/out" | LC_ALL=C sort -t '	' -k2,2 > "$T/findings"
  _n=0
  # Every finding is red under the rule id, a shadow one too: shadow is how a rule earns warn (standards/naming.md §10.3).
  [ -z "${LINT_REDLOG:-}" ] || awk -v id="$ID" '{ print id }' "$T/findings" >> "$LINT_REDLOG" 2>/dev/null || :
  [ -z "${SHAPE_FINDINGS:-}" ] || cut -f2 "$T/findings" >> "$SHAPE_FINDINGS" 2>/dev/null || :
  if [ "$FORMAT" = findings ] && [ "$_m" != shadow ]; then
    awk -F'\t' -v id="$ID" -v k="$( [ "$_m" = block ] && echo V || echo A)" '{ printf "%s\t%s\t%s\n", k, id, $2 }' "$T/findings"
  fi
  while IFS='	' read -r _f _s _msg; do
    case "$_m" in
      shadow) continue ;;
      block)  log_fail "[$ID] $_s — $_msg"; log_nofix "standards/naming/kinds.tsv" ;;
      *)      log_warn "[$ID] $_s — $_msg" ;;
    esac
    _n=$((_n + 1))
  done < "$T/findings"
  _all="$(wc -l < "$T/findings" | tr -d ' ')"
  awk -F'\t' '$1 == "U" { print $2 "\t" $3 }' "$T/out" | LC_ALL=C sort > "$T/unc"
  while IFS='	' read -r _r _k; do
    log_note "unchecked: the graph derives no $_r edges, so the shape of $_k over $_r was not judged"
  done < "$T/unc"
  _j="$(awk -F'\t' '$1 == "N" { print $2 }' "$T/out")"
  if [ "$_all" -eq 0 ]; then log_ok "$3: $_j instances carry their shapes"; fi
  [ "$_m" != shadow ] || [ "$_all" -eq 0 ] || log_note "$_all shadow finding(s) recorded, not shown: $ID is in shadow mode (D-29)"
  [ "$_m" != block ] || [ "$_all" -eq 0 ]
}

# ── --self-test ──────────────────────────────────────────────────────────────
# fixtures/standard-shape/<case>/{graph.tsv, targets.tsv, expect.tsv} and an optional kinds.tsv (else the shared
# fixtures/standard-shape/kinds.tsv). expect.tsv lists the `<node> TAB <relation>` findings the case MUST yield and
# nothing else may; an empty one is a pass case. Every relation term (terms.tsv, class relation) must go red in some
# case, read from the findings the run recorded (SHAPE_FINDINGS, in any mode), never from the fixture text.
if [ "$ACTION" = self-test ]; then
  FX="$ROOT/fixtures/standard-shape"
  [ -f "$CONTROLS" ] || unchecked "no controls.tsv at $CONTROLS, so the mode is unknown" "ls $REG"
  [ -d "$FX" ] || unchecked "no fixtures at fixtures/standard-shape — the self-test judged NOTHING" "ls $ROOT/fixtures"
  log_head "self-test: fixtures/standard-shape"
  : > "$T/allred"; _cases=0
  for _d in "$FX"/*/; do
    [ -f "${_d}graph.tsv" ] || continue
    _c="$(basename "$_d")"; _cases=$((_cases + 1))
    _k="${_d}kinds.tsv"; [ -f "$_k" ] || _k="$FX/kinds.tsv"
    _rc=0; : > "$T/got.raw"
    SHAPE_FINDINGS="$T/got.raw" sh "$SELF" --root "$ROOT" --registry "$REG" --kinds "$_k" --graph "${_d}graph.tsv" \
      --targets "${_d}targets.tsv" > /dev/null 2> "$T/case.err" || _rc=$?
    [ "$_rc" -le 1 ] || { log_fail "$_c: exited $_rc, so it judged nothing ($(grep -m1 'FAIL:' "$T/case.err" | sed 's/^ *FAIL: //'))"; log_fix "sh $SELF --kinds $_k --graph ${_d}graph.tsv --targets ${_d}targets.tsv"; continue; }
    awk 'match($0, / [^ ]*$/) { print substr($0, 1, RSTART - 1) "\t" substr($0, RSTART + 1) }' "$T/got.raw" | LC_ALL=C sort -u > "$T/got"
    cut -f2 "$T/got" >> "$T/allred"
    if [ -f "${_d}expect.tsv" ]; then grep -v '^#' "${_d}expect.tsv" | grep . | LC_ALL=C sort -u > "$T/want" || :; else : > "$T/want"; fi
    if cmp -s "$T/want" "$T/got"; then
      log_ok "$_c: $( [ -s "$T/want" ] && tr '\t\n' ' ;' < "$T/want" | sed 's/;$//' || echo 'stays green' )"
    else
      log_fail "$_c: expected [$(tr '\t\n' ' ;' < "$T/want" | sed 's/;$//')] but found [$(tr '\t\n' ' ;' < "$T/got" | sed 's/;$//')]"
      log_fix "sh $SELF --kinds $_k --graph ${_d}graph.tsv --targets ${_d}targets.tsv"
    fi
  done
  [ "$_cases" -gt 0 ] || unchecked "fixtures/standard-shape holds no case — nothing to judge" "add fixtures/standard-shape/<case>/graph.tsv"
  [ -z "${LINT_REDLOG:-}" ] || [ ! -s "$T/allred" ] || echo "$ID" >> "$LINT_REDLOG" 2>/dev/null || :
  LC_ALL=C sort -u "$T/allred" -o "$T/allred"
  _rels="$(awk -F'\t' '/^#/ || $1 == "id" { next } ("," $2 ",") ~ /,relation,/ { print $1 }' "$REG/terms.tsv")"
  [ -n "$_rels" ] || { log_fail "terms.tsv names no relation term, so no relation was proven red"; log_fix "grep relation $REG/terms.tsv"; }
  for _r in $_rels; do
    grep -qx -- "$_r" "$T/allred" || { log_fail "relation $_r never went red in this self-test"; log_fix "add fixtures/standard-shape/red-$_r/"; }
  done
  # The exit-3 contract, proven red: a graph that is absent, and a bound that does not parse, are unchecked, never a pass.
  _rc=0; sh "$SELF" --root "$ROOT" --registry "$REG" --kinds "$FX/kinds.tsv" --graph "$T/no-such-graph.tsv" --targets /dev/null > /dev/null 2>&1 || _rc=$?
  if [ "$_rc" -eq 3 ]; then log_ok "a missing graph exits 3"; else log_fail "a missing graph exited $_rc, not 3"; log_fix "sh $SELF --graph /nonexistent"; fi
  _g="$(for _d in "$FX"/*/; do [ -f "${_d}graph.tsv" ] && { echo "${_d}graph.tsv"; break; }; done)"
  awk -F'\t' -v OFS='\t' '$1 == "id" || /^#/ { print; next } { $11 = "notifies:3..1"; print }' "$FX/kinds.tsv" > "$T/bad-kinds.tsv"
  _rc=0; sh "$SELF" --root "$ROOT" --registry "$REG" --kinds "$T/bad-kinds.tsv" --graph "$_g" --targets /dev/null > /dev/null 2>&1 || _rc=$?
  if [ "$_rc" -eq 3 ]; then log_ok "a malformed bound exits 3"; else log_fail "a malformed bound exited $_rc, not 3"; log_fix "sh $SELF --kinds <a kinds.tsv with notifies:3..1>"; fi
  log_end; exit $?
fi

# ── judge a graph ────────────────────────────────────────────────────────────
[ -f "$CONTROLS" ] || unchecked "no controls.tsv at $CONTROLS, so the mode is unknown" "ls $REG"
[ -f "$KINDS" ] || unchecked "no kinds.tsv at $KINDS, so no shape is known" "ls $REG"
if [ "$EXPLICIT" = 0 ]; then
  GRAPH="$ROOT/build/graph.tsv"
  [ -f "$GRAPH" ] || unchecked "build/graph.tsv is missing, so nothing was judged" "sh bin/doc-graph-generate.sh"
  # Stale is unchecked, not green: doc-graph-generate.sh --check rebuilds in memory and compares (exit 3 without python3).
  _grc=0; sh "$HERE/doc-graph-generate.sh" --check --root "$ROOT" --out "$GRAPH" > /dev/null 2>&1 || _grc=$?
  case "$_grc" in
    0) ;;
    3) unchecked "python3 is absent, so the graph cannot be shown current" "$(pkg_hint python3), then sh bin/doc-graph-generate.sh" ;;
    *) unchecked "build/graph.tsv is stale (doc-graph-generate.sh --check exited $_grc), so nothing was judged" "sh bin/doc-graph-generate.sh" ;;
  esac
fi
[ -f "$GRAPH" ] || unchecked "the graph $GRAPH does not exist, so nothing was judged" "sh bin/doc-graph-generate.sh"
head -1 "$GRAPH" | grep -q '^# graph\.tsv ' || unchecked "$GRAPH is not a graph.tsv, so nothing was judged" "sh bin/doc-graph-generate.sh"
grep -q '^edge	from	to	site$' "$GRAPH" || unchecked "$GRAPH has no edge header, so nothing was judged" "sh bin/doc-graph-generate.sh"
if [ -z "$TARGETS" ]; then
  TARGETS="$T/targets.tsv"
  sh "$HERE/standard-catalog.sh" --targets --root "$ROOT" > "$TARGETS" 2> "$T/cat.err" \
    || unchecked "the catalog could not list the instances, so nothing was judged: $(grep -m1 'FAIL:' "$T/cat.err" | sed 's/^ *FAIL: //')" "sh bin/standard-catalog.sh --targets"
fi
[ -f "$TARGETS" ] || [ -c "$TARGETS" ] || unchecked "the targets $TARGETS do not exist, so nothing was judged" "sh bin/standard-catalog.sh --targets"
run "$GRAPH" "$TARGETS" "${GRAPH#"$ROOT"/}" || { log_end || :; exit 1; }
log_end || :
exit 0
