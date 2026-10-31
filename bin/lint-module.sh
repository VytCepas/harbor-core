#!/usr/bin/env sh
# lint-module.sh (harbor#996 C1) — the modularity lint: judges the reference graph against standards/modularity.md.
#
#   sh bin/lint-module.sh                    judge build/graph.tsv (it must be current: doc-graph-generate.sh --check)
#   sh bin/lint-module.sh --graph <file>     judge that graph; the caller vouches it is current
#   sh bin/lint-module.sh --self-test        every fixture yields exactly its expected ids, and every rule went red
#   sh bin/lint-module.sh --list             each rule's id, mode and title, read from standards/naming/controls.tsv
#   sh bin/lint-module.sh --help
#
#   --format findings   also print one `<A|V> TAB <rule> TAB <subject>` record per finding on stdout
#   --format inert      print one `<why> TAB <subject> TAB <site>` record per mention set aside (see below)
#   --root <dir>        the tree whose graph is judged (default: this checkout)
#   --registry <dir>    the registry (default: <root>/standards/naming): terms.tsv families, controls.tsv modes
#   --sites <dir>       read each cited line from <dir>/<system>/<path> instead of the real trees (the self-test's fixtures)
#
#   exit (D-49) 0 pass, warn and shadow findings allowed · 1 a block finding, or a failed self-test · 2 usage
#   · 3 unchecked: python3 absent, or the graph is missing, stale or not a graph. Never 0 for a graph it did
#   not judge: "I could not look" must not read as "nothing is wrong".
#   LINT_REDLOG=<file> appends the id of every rule that goes red, shadow ones too, as bin/lint-name.sh does.
#
# THE RULES, each a standards/naming/controls.tsv row (D-62) whose mode is read there and never here:
#   module.cross-system-path  M1  an edge from one system to a non-contract path of another
#   module.system-cycle       M2  a dependency cycle between systems
#   module.family-cycle       M3  a dependency cycle between families (the graph's edges plus terms.tsv depends_on)
#   module.private-use        M3  a family uses another family's private file (lib or _-prefixed), not its entry
#   module.layer-direction    S3  a source file reads a generated one (standard §5: a layer reads only the one below)
# module.family-shape (M4) stays shadow and unevaluated: it needs the catalog (harbor#996 D1).
#
# WHAT AN EDGE IS HERE. Only `references` edges are judged: a line holds another node's path as a literal
# substring (doc-graph-generate.sh). That is a mention, not proof of a call, so the rules read only files that DO
# things and every finding names its site for a person to confirm. A system is a node prefix that is also an
# `# input` row of the graph. Two cuts keep a mention that cannot read from being judged as one (harbor#996 C1):
#   files that record or exercise are not judged: prose (*.md, docs/, evals/), the contract and register
#     areas (contracts/, contracts/, schemas/, standards/, .agents/config.yaml), and tests/ and fixtures/, which
#     name a path to build or assert on it. A test's family is its directory name, which is a suite group and
#     not who owns the thing under test (tests/ci/ exercises gate-merge-stack.sh), so it cannot make a cycle.
#   a mention is inert when the cited line cannot read the path: a comment (first non-blank character `#` or
#     `//`), or the path occurs only as the tail of a longer name (docs/reports/qa-plan.md holds docs/generated/plan.md). The line is read
#     from the tree, and a line that cannot be read keeps its finding: "I could not look" is never "inert".
#   --format inert lists every pair a cut set aside, so each cut is auditable: why `comment` or `longer-name` for
#     a pair whose every site cannot read, whether it would have been a finding or only an edge of the system or
#     family cycles; and why `test` for a path of another system that a test names (tests are not judged, and a test
#     can really read another system's installed file, so the cut stays visible and is never silent).
#   A path built from parts leaves the graph nothing to match, so no rule sees that read: a script that joins a
#     directory and a file name is invisible whether or not a comment also names the file.
# Layer direction judges code only (bin/, src/, hooks/, githooks/, tools/): without that cut it prints 97 rows today,
# most of them a test naming the file it tests or a registry row mentioning one, which read nothing.
# A family is read from a path alone: bin/<family>-*, tests/<family>/, fixtures/<family>/, src/<pkg>/<family>/.
#
# DELIBERATELY ONE FILE (docs/explanation/modularity.md): one POSIX sh + awk program. The awk judges; the sh around it
# resolves the graph, reads the modes and formats. awk because the graph is ~25,000 rows and the judging is a
# strongly-connected-components pass, not a pipeline; no python3 is needed to JUDGE, only to build or check it.
set -eu

HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
SELF="$HERE/$(basename -- "$0")"
LOG_FD=2   # stdout carries --format findings and --list; the log goes to stderr
. "$HERE/library-log.sh"
log_init lint-module

usage() { awk 'NR < 2 { next } /^# DELIBERATELY/ || !/^#/ { exit } { sub(/^# ?/, ""); print }' "$SELF"; }
unchecked() { log_fail "$1"; log_fix "$2"; log_end || :; exit 3; }
usage_err() { log_fail "$1"; log_fix "sh $SELF --help"; log_end || :; exit 2; }

ACTION=judge; FORMAT=""; ROOT=""; REG=""; GRAPH=""; EXPLICIT=0; TERMS=""; SITES=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --self-test) ACTION=self-test ;;
    --list) ACTION=list ;;
    --graph) [ $# -ge 2 ] || usage_err "--graph needs a file"; GRAPH="$2"; EXPLICIT=1; shift ;;
    --root) [ $# -ge 2 ] || usage_err "--root needs a directory"; ROOT="$2"; shift ;;
    --registry) [ $# -ge 2 ] || usage_err "--registry needs a directory"; REG="$2"; shift ;;
    --terms) [ $# -ge 2 ] || usage_err "--terms needs a file"; TERMS="$2"; shift ;;
    --sites) [ $# -ge 2 ] || usage_err "--sites needs a directory"; SITES="$2"; shift ;;
    --format) [ $# -ge 2 ] || usage_err "--format needs a value"; FORMAT="$2"; shift ;;
    -*) usage_err "unknown option $1" ;;
    *) usage_err "unexpected argument $1" ;;
  esac
  shift
done
case "$FORMAT" in ''|findings|inert) ;; *) usage_err "--format is findings or inert" ;; esac
[ -n "$ROOT" ] || ROOT="$HERE/.."
ROOT="$(CDPATH='' cd -- "$ROOT" 2>/dev/null && pwd -P)" || usage_err "--root is not a directory"
[ -n "$REG" ] || REG="$ROOT/standards/naming"
[ -n "$TERMS" ] || TERMS="$REG/terms.tsv"
CONTROLS="$REG/controls.tsv"
T="$(mktemp -d "${TMPDIR:-/tmp}/lint-module.XXXXXX")"
trap 'rm -rf "$T"' EXIT INT TERM HUP

# The rules this engine emits, in the order they print.
IDS="module.cross-system-path module.system-cycle module.family-cycle module.private-use module.layer-direction"

# mode_of <id> → shadow | warn | block, from controls.tsv. advisory and inform are legacy spellings of warn.
mode_of() {
  awk -F'\t' -v id="$1" '/^#/ { next } $1 == id { m = $2; if (m == "advisory" || m == "inform") m = "warn"; print m; exit }' "$CONTROLS"
}

if [ "$ACTION" = list ]; then
  [ -f "$CONTROLS" ] || unchecked "no controls.tsv at $CONTROLS" "ls $REG"
  awk -F'\t' -v ids="$IDS" 'BEGIN { n = split(ids, I, " "); for (i = 1; i <= n; i++) want[I[i]] = 1 }
    /^#/ || $1 == "id" { next } ($1 in want) { printf "  %-26s %-7s %s\n", $1, $2, $13 }' "$CONTROLS"
  exit 0
fi

# ── the judge ────────────────────────────────────────────────────────────────
# judge <graph> <terms> → `F TAB rule TAB subject TAB message` per finding, `S TAB why TAB subject TAB site` per mention
# set aside as inert, then `I TAB label TAB status` per input.
judge() {
  awk -F'\t' -v TERMS="$2" -v GRAPH="$1" -v ROOT="$ROOT" -v SITES="$SITES" -v HOMEDIR="${HOME:-}" '
  function sysof(n,   p, s) { p = index(n, ":"); if (p == 0) return ""; s = substr(n, 1, p - 1); return (s in SYS) ? s : "" }
  function pathof(n) { return substr(n, index(n, ":") + 1) }
  # a file that records or exercises is not judged: prose (markdown, docs/, evals/), the contract and register
  # areas (a register row names a path to define the seam), and tests/ and fixtures/ (they name a path to build or assert on it)
  function judged(n,   r) { r = pathof(n); return !(r ~ /\.md$/ || r ~ /^(docs|evals|tests|fixtures)\// || contract(n)) }
  function base(r,   a, k) { k = split(r, a, "/"); return a[k] }
  function fam(n,   r, a, k, b) {
    if (sysof(n) == "") return ""
    r = pathof(n); k = split(r, a, "/")
    if (a[1] == "bin" && k == 2) { b = a[2]; sub(/[-.].*$/, "", b); return (b in FAMILY) ? b : "" }
    if ((a[1] == "tests" || a[1] == "fixtures") && k >= 3 && (a[2] in FAMILY)) return a[2]
    if (a[1] == "src" && k >= 4 && (a[3] in FAMILY)) return a[3]
    return ""
  }
  # the entry a family shows is its command and its exports; lib files and _-prefixed ones are private
  function private(n,   r, a, k, i, b) {
    r = pathof(n); k = split(r, a, "/"); b = a[k]
    if (b ~ /^_/ || b ~ /(^|[-_.])lib([-_.]|$)/) return 1
    for (i = 1; i < k; i++) if (a[i] == "lib" || a[i] ~ /^_/) return 1
    return 0
  }
  # a contract is the one thing a system may name in another: contracts/, contracts/, schemas/, the scope marker,
  # and the standard (a registry harbor defines for every other system)
  function contract(n,   r) {
    r = pathof(n)
    return (r ~ /^(CONTRACTS|contracts|schemas|standards)\// || r == ".agents/config.yaml")
  }
  # code that runs: a test of a generated file must name it, and a data row that mentions one reads nothing
  function code(n,   r) { r = pathof(n); return (r ~ /^(bin|src|hooks|githooks|tools)\//) }
  function generated(n,   r) {
    if (n in GEN) return 1
    r = pathof(n)
    return (sysof(n) != "" && r ~ /^(build|docs\/generated)\//)
  }
  # where the files of a system are read from for a cited line: this checkout for harbor, the path of its input row
  # for the rest, or <SITES>/<system> when --sites names a fixture tree. An absent root leaves its lines unreadable.
  function setroot(name, p) {
    if (name in SROOT) return
    if (SITES != "") { SROOT[name] = SITES "/" name; return }
    if (name == "harbor") { SROOT[name] = ROOT; return }
    if (p ~ /^~\//) p = HOMEDIR substr(p, 2)
    SROOT[name] = (p ~ /^\//) ? p : ""
  }
  # the text of the line a graph row cites ("<system>:<path>:<line>"), or SENT when it cannot be read
  function sitetext(site,   p, s, rest, k, f, ln, key, l) {
    p = index(site, ":"); if (p == 0) return SENT
    s = substr(site, 1, p - 1); rest = substr(site, p + 1)
    k = match(rest, /:[0-9]+$/); if (k == 0) return SENT
    f = substr(rest, 1, k - 1); ln = substr(rest, k + 1) + 0
    if (!(s in SROOT) || SROOT[s] == "" || ln < 1) return SENT
    key = SROOT[s] "/" f
    if (!(key in NLINES)) {
      NLINES[key] = 0
      while ((getline l < key) > 0) TXT[key, ++NLINES[key]] = l
      close(key)
      if (NLINES[key] == 0) NLINES[key] = -1
    }
    return (ln <= NLINES[key]) ? TXT[key, ln] : SENT
  }
  # inert(site, path) → "comment" or "longer-name" when the cited line holds the path but cannot read it, else "".
  # A comment is a line whose first non-blank character is # or //. A longer name is every occurrence of the path
  # standing right after a name character (docs/reports/qa-plan.md holds docs/generated/plan.md). A line that cannot be read, or that does not
  # hold the path at all (the graph is not current), is never inert.
  function inert(site, tpath,   t, from, pos, abs, n, whole, c) {
    if (tpath == "") return ""
    t = sitetext(site); if (t == SENT) return ""
    n = 0; whole = 0; from = 1
    while ((pos = index(substr(t, from), tpath)) > 0) {
      abs = from + pos - 1; n++
      c = (abs > 1) ? substr(t, abs - 1, 1) : ""
      if (c == "" || c !~ /[A-Za-z0-9_-]/) whole = 1
      from = abs + 1
    }
    if (n == 0) return ""
    if (t ~ /^[ \t]*(#|\/\/)/) return "comment"
    return whole ? "" : "longer-name"
  }
  # firstlive(pair, target) → the first site of the pair that can read, or "" when every site is inert (WHY says why)
  function firstlive(k, t,   j, tp, r) {
    tp = pathof(t); WHY = ""
    for (j = 1; j <= NS[k]; j++) {
      r = inert(SITE[k, j], tp)
      if (r == "") return SITE[k, j]
      if (WHY == "") WHY = r
    }
    return ""
  }
  function sortw(s,   a, n, i, j, t, o) { n = split(s, a, " ")
    for (i = 2; i <= n; i++) { t = a[i]; for (j = i - 1; j >= 1 && a[j] > t; j--) a[j + 1] = a[j]; a[j + 1] = t }
    o = a[1]; for (i = 2; i <= n; i++) o = o " " a[i]; return o }
  function addedge(g, u, v) {
    if ((g SUBSEP u SUBSEP v) in HAS) return
    HAS[g SUBSEP u SUBSEP v] = 1
    if (!((g SUBSEP u) in NODE)) { NODE[g SUBSEP u] = 1; NL[g] = NL[g] " " u }
    if (!((g SUBSEP v) in NODE)) { NODE[g SUBSEP v] = 1; NL[g] = NL[g] " " v }
    ADJ[g SUBSEP u] = ADJ[g SUBSEP u] " " v
  }
  function tarjan(g, u,   a, n, i, v, w, list) {
    IDX[u] = LOW[u] = ++CNT; STK[++SP] = u; ONS[u] = 1
    n = split(ADJ[g SUBSEP u], a, " ")
    for (i = 1; i <= n; i++) { v = a[i]
      if (!(v in IDX)) { tarjan(g, v); if (LOW[v] < LOW[u]) LOW[u] = LOW[v] }
      else if (ONS[v] && IDX[v] < LOW[u]) LOW[u] = IDX[v] }
    if (LOW[u] == IDX[u]) {
      list = ""
      do { w = STK[SP--]; ONS[w] = 0; list = list " " w } while (w != u)
      SCCN++; SCC[SCCN] = sortw(list); SCCSZ[SCCN] = split(list, a, " ")
    }
  }
  # cycles(g) → SCC[1..SCCN] of size > 1
  function cycles(g,   a, n, i) {
    delete IDX; delete LOW; delete ONS; delete SCC; delete SCCSZ; CNT = 0; SP = 0; SCCN = 0
    n = split(NL[g], a, " ")
    for (i = 1; i <= n; i++) if (!(a[i] in IDX)) tarjan(g, a[i])
  }
  function emit(rule, subject, msg) { print "F\t" rule "\t" subject "\t" msg }
  function inertrec(f, t, site) { print "S\t" WHY "\t" f " -> " t "\t" site }

  BEGIN {
    SENT = sprintf("%c", 1)
    while ((getline l < TERMS) > 0) {
      if (l ~ /^#/ || l ~ /^id\t/) continue
      n = split(l, c, "\t")
      if (("," c[2] ",") ~ /,family,/) { FAMILY[c[1]] = 1; DEP[c[1]] = c[10] }
    }
    close(TERMS)
    while ((getline l < GRAPH) > 0) {
      n = split(l, c, "\t")
      if (c[1] == "# input") { SYS[c[2]] = 1; setroot(c[2], c[3]); print "I\t" c[2] "\t" c[4]; continue }
      if (l ~ /^#/ || c[1] == "edge") continue
      if (c[1] == "derives_from") { GEN[c[2]] = 1; GENOF[c[2]] = c[3] }
      else if (c[1] == "references") {
        k = c[2] SUBSEP c[3]
        if (!(k in NS)) { NP++; PF[NP] = c[2]; PT[NP] = c[3] }
        SITE[k, ++NS[k]] = c[4]
      }
    }
    close(GRAPH)
    for (f in DEP) { n = split(DEP[f], d, ","); for (i = 1; i <= n; i++) if (d[i] != "-" && d[i] != "" ) addedge("fam", f, d[i]) }

    for (i = 1; i <= NP; i++) {
      f = PF[i]; t = PT[i]; k = f SUBSEP t
      sf = sysof(f); st = sysof(t)
      if (sf == "" || st == "") continue
      if (!judged(f)) {   # not judged, but a test that names a path of another system is listed, so that cut is auditable
        if (sf != st && !contract(t) && pathof(f) ~ /^(tests|fixtures)\//) { WHY = "test"; inertrec(f, t, SITE[k, 1]) }
        continue
      }
      if (sf != st) {
        s = firstlive(k, t)
        if (s == "") { inertrec(f, t, SITE[k, 1]); continue }
        addedge("sys", sf, st)
        if (!contract(t)) emit("module.cross-system-path", f " -> " t, "system " sf " reads a path of system " st " that is not a contract (M1; " s ")")
        continue
      }
      ff = fam(f); ft = fam(t)
      famedge = (ff != "" && ft != "" && ff != ft)
      layer = (generated(t) && !generated(f) && code(f) && GENOF[t] != f)
      if (!famedge && !layer) continue
      s = firstlive(k, t)
      if (s == "") { inertrec(f, t, SITE[k, 1]); continue }
      if (famedge) {
        addedge("fam", ff, ft)
        if (private(t)) emit("module.private-use", f " -> " t, "family " ff " uses a private file of family " ft " instead of its entry (M3; " s ")")
      }
      if (layer)
        emit("module.layer-direction", f " -> " t, "source code reads a generated file; a layer reads only the one below it (standard section 5; " s ")")
    }
    cycles("sys")
    for (i = 1; i <= SCCN; i++) if (SCCSZ[i] > 1) { s = SCC[i]; gsub(/ /, ",", s); S2[++n2] = s }
    for (i = 1; i <= n2; i++) emit("module.system-cycle", S2[i], "systems " S2[i] " depend on each other (M2)")
    cycles("fam")
    for (i = 1; i <= SCCN; i++) if (SCCSZ[i] > 1) { s = SCC[i]; gsub(/ /, ",", s); S3[++n3] = s }
    for (i = 1; i <= n3; i++) emit("module.family-cycle", S3[i], "families " S3[i] " depend on each other (M3)")
  }' /dev/null
}

# run <graph> <terms> → judges, reports; sets nothing global but the counts in $T
run() { # <graph> <terms> <what>
  judge "$1" "$2" > "$T/out" || unchecked "the judge (awk) failed, so nothing was judged" "sh $SELF --help"
  _n=0; _blk=0; _shd=0
  awk -F'\t' '$1 == "F"' "$T/out" | LC_ALL=C sort -t '	' -k2,2 -k3,3 > "$T/findings"
  for _r in $IDS; do
    _m="$(mode_of "$_r")"
    [ -n "$_m" ] || unchecked "no controls.tsv row for $_r, so its mode is unknown" "add the row to $CONTROLS"
    printf '%s\t%s\n' "$_r" "$_m"
  done > "$T/modes"
  # Every finding is red under its own rule id, a shadow one too: shadow is how a rule earns warn (§10.3).
  [ -z "${LINT_REDLOG:-}" ] || cut -f2 "$T/findings" >> "$LINT_REDLOG" 2>/dev/null || :
  awk -F'\t' 'NR == FNR { m[$1] = $2; next } { print m[$2] "\t" $2 "\t" $3 "\t" $4 }' "$T/modes" "$T/findings" > "$T/judged"
  awk -F'\t' '$1 == "S" { printf "%s\t%s\t%s\n", $2, $3, $4 }' "$T/out" | LC_ALL=C sort > "$T/inert"
  case "$FORMAT" in
    findings) awk -F'\t' '$1 != "shadow" { printf "%s\t%s\t%s\n", ($1 == "block" ? "V" : "A"), $2, $3 }' "$T/judged" ;;
    inert) cat "$T/inert" ;;
  esac
  while IFS='	' read -r _l _r _s _msg; do
    case "$_l" in
      shadow) _shd=$((_shd + 1)); continue ;;
      block)  _blk=$((_blk + 1)); log_fail "[$_r] $_s — $_msg"; log_nofix "standards/modularity.md" ;;
      *)      log_warn "[$_r] $_s — $_msg" ;;
    esac
    _n=$((_n + 1))
  done < "$T/judged"
  _gone="$(awk -F'\t' '$1 == "I" && $3 ~ /^absent/ { printf "%s%s", (n++ ? ", " : ""), $2 }' "$T/out")"
  [ -z "$_gone" ] || log_note "inputs absent from the graph, so not judged: $_gone"
  _ni="$(wc -l < "$T/inert" | tr -d ' ')"
  [ "$_ni" -eq 0 ] || log_note "$_ni pair(s) set aside (a comment, the tail of a longer name, or a test naming another system's path): sh $SELF --format inert lists them"
  if [ "$_n" -eq 0 ]; then log_ok "$3: no finding"; fi
  [ "$_shd" -eq 0 ] || log_note "$_shd shadow finding(s) recorded, not shown: their rules are in shadow mode (D-29)"
  [ "$_blk" -eq 0 ]
}

# ── --self-test ──────────────────────────────────────────────────────────────
# fixtures/lint-module/<case>/{graph.tsv, terms.tsv, expect.tsv}: expect.tsv lists the ids the case MUST yield, one
# per line, and nothing else may go red; an empty expect.tsv is a pass case. Whether a rule went red is read
# from the red log the run writes, never from the fixture text. A case may carry tree/<system>/<path>, the files
# its cited lines are read from (--sites); a case with no tree/ has unreadable lines, and an unreadable line keeps
# its finding, so the older cases judge the graph alone.
if [ "$ACTION" = self-test ]; then
  FX="$ROOT/fixtures/lint-module"
  [ -f "$CONTROLS" ] || unchecked "no controls.tsv at $CONTROLS, so the modes are unknown" "ls $REG"
  [ -d "$FX" ] || unchecked "no fixtures at fixtures/lint-module — the self-test judged NOTHING" "ls $ROOT/fixtures"
  log_head "self-test: fixtures/lint-module"
  : > "$T/allred"; _cases=0
  for _d in "$FX"/*/; do
    [ -f "${_d}graph.tsv" ] || continue
    _c="$(basename "$_d")"; _cases=$((_cases + 1))
    : > "$T/red"; _rc=0
    LINT_REDLOG="$T/red" sh "$SELF" --root "$ROOT" --registry "$REG" --terms "${_d}terms.tsv" --graph "${_d}graph.tsv" --sites "${_d}tree" > /dev/null 2> "$T/case.err" || _rc=$?
    [ "$_rc" -le 1 ] || { log_fail "$_c: exited $_rc, so it judged nothing ($(grep -m1 'FAIL:' "$T/case.err" | sed 's/^ *FAIL: //'))"; log_fix "sh $SELF --terms ${_d}terms.tsv --graph ${_d}graph.tsv"; continue; }
    sort -u "$T/red" -o "$T/red"; cat "$T/red" >> "$T/allred"
    [ -z "${LINT_REDLOG:-}" ] || cat "$T/red" >> "$LINT_REDLOG" 2>/dev/null || :   # the caller's red log names what went red here
    if [ -f "${_d}expect.tsv" ]; then grep -v '^#' "${_d}expect.tsv" | grep . | sort -u > "$T/want" || :; else : > "$T/want"; fi
    [ -f "$T/want" ] || : > "$T/want"
    if cmp -s "$T/want" "$T/red"; then
      log_ok "$_c: $( [ -s "$T/want" ] && tr '\n' ' ' < "$T/want" | sed 's/ $//' || echo 'stays green' )"
    else
      log_fail "$_c: expected [$(tr '\n' ' ' < "$T/want" | sed 's/ $//')] but went red on [$(tr '\n' ' ' < "$T/red" | sed 's/ $//')]"
      log_fix "sh $SELF --terms ${_d}terms.tsv --graph ${_d}graph.tsv"
    fi
  done
  [ "$_cases" -gt 0 ] || unchecked "fixtures/lint-module holds no case — nothing to judge" "add fixtures/lint-module/<case>/graph.tsv"
  sort -u "$T/allred" -o "$T/allred"
  for _r in $IDS; do
    grep -qx -- "$_r" "$T/allred" || { log_fail "$_r never went red in this self-test"; log_fix "add a fixture under fixtures/lint-module/ that yields $_r"; }
  done
  # A graph that is absent must be unchecked (3), never a pass: the red proof of the exit-3 contract.
  _rc=0; sh "$SELF" --root "$ROOT" --registry "$REG" --graph "$T/no-such-graph.tsv" > /dev/null 2>&1 || _rc=$?
  if [ "$_rc" -eq 3 ]; then log_ok "a missing graph exits 3"; else log_fail "a missing graph exited $_rc, not 3"; log_fix "sh $SELF --graph /nonexistent"; fi
  log_end; exit $?
fi

# ── judge a graph ────────────────────────────────────────────────────────────
[ -f "$CONTROLS" ] || unchecked "no controls.tsv at $CONTROLS, so the modes are unknown" "ls $REG"
[ -f "$TERMS" ] || unchecked "no terms.tsv at $TERMS, so no family is known" "ls $REG"
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
run "$GRAPH" "$TERMS" "${GRAPH#"$ROOT"/}" || { log_end || :; exit 1; }
log_end || :
exit 0
