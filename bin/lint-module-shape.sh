#!/usr/bin/env sh
# M11 · ModuleShape (harbor#379) — answer the two questions CONSTITUTION "Module
# shape" asks, as measurements instead of judgement.
#
#   sh lint-module-shape.sh [--json] <file|dir>...        classify a codebase
#   sh lint-module-shape.sh --seam <file> [corpus-dir]    should THIS file be split?
#
# DELIBERATELY ONE FILE (docs/explanation/modularity.md): both modes are two questions
# over ONE symbol-ownership map and ONE compression primitive. Split them and the
# uniqueness filter — the defect three separate revisions of this instrument
# reintroduced — would exist in two spellings, which is exactly how it came back.
#
# READ-ONLY. It writes nothing outside a temp dir it removes.
#
# THE TWO AXES ARE PERPENDICULAR, and conflating them is the whole confusion:
#   DEPTH  = LOC / uniquely-owned symbols.  Ashby hidden variety; Ousterhout depth.
#   DENS   = distinct caller->callee file pairs / n(n-1).  NOT an edge count: a
#            count cannot tell one shared deep library with many independent
#            callers (a hub, the good shape) from every module reaching every
#            other (a mesh). Both are large. Destination ENTROPY cannot either —
#            it scored a 6-module pipeline and a 6-module mesh identically.
# Splitting a file moves DENS and leaves DEPTH untouched, so a file count is
# never evidence of modularity.
#
# AND FOR ONE FILE, TWO MORE:
#   REALITY  cut it at its own function boundaries; cut a copy at arbitrary
#            offsets into the SAME number of parts; compare description cost.
#            gzip bounds it (AIT: C(x) >= K(x)). Structure survives the first cut
#            and not the second. Dennett's Real Pattern, made operational. The
#            null model is load-bearing: raw split cost is dominated by part
#            COUNT, so without it a file with many small functions always loses.
#   VALUE    symbols with >= 2 callers in OTHER files. The two-adapter rule as a
#            count. One caller is the file talking to itself through a longer path.
# A SPLIT NEEDS BOTH. Reality alone marks MOST of the files over 300 lines here,
# every test suite included — correctly, because a suite IS a flat list of
# independent blocks whose boundaries nothing crosses. Acting on reality alone
# would fragment this repository.
#
# THE COUNT USED TO BE IN THIS SENTENCE, and it was wrong (harbor#466). It said
# "36 of the 42" while CONSTITUTION and docs/explanation/modularity.md both said 52 —
# corrected there on 2026-08-30 by running THIS TOOL, and the correction never
# came back to the tool that produced it, because nothing runs the tool. A
# mechanism that restates its own output in prose has made a copy of the one
# number it exists to derive; CONSTITUTION "Don't state a fact that lives
# somewhere else — derive it". Ask the instrument instead:
#   for f in bin/*.sh; do [ "$(wc -l < "$f")" -gt 300 ] && sh bin/lint-module-shape.sh --seam "$f"; done
#
# THREE MEASUREMENT DEFECTS THIS ENCODES, each found by a control, not by review:
#   1. a symbol defined in SEVERAL files (`ok` in 47, `bad` in 41) credited to the
#      first scanner -> only UNIQUELY-owned symbols count.
#   2. a symbol shorter than 3 characters is an ordinary shell word, not evidence
#      of a call. admission-observe-report.sh defines `n`; every bare "n" in 85 files scored
#      as an edge into it, 2761 of them, outranking guard-lib.sh.
#   3. a mention anywhere is not a call -> command position only.
set -eu

usage() {
  cat <<'U'
lint-module-shape.sh — measure module shape (harbor#379)

  sh lint-module-shape.sh [--json] <file|dir>...       classify a codebase on both axes
  sh lint-module-shape.sh --seam <file> [corpus-dir]   is a split of THIS file earned?
  sh lint-module-shape.sh --help

Classify prints: files, LOC, uniquely-owned symbols, depth, density, hub share,
split cost, and the quadrant. --seam prints: reality gain against an arbitrary-cut
null model, and the count of symbols with two or more external callers.

Exit 0 always on success; 2 on bad usage. Writes nothing. The measurement is on stdout; the
run log (contracts/logging.md) is on stderr.
U
}

# stdout is the measurement (a line, or --json), so the run log is on stderr.
LOG_FD=2
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/library-log.sh"
log_init module-shape
# A usage error is a FAIL, its fix, and the summary, exit 2: it is not a run.
_usage_fail() { # <what failed>
  log_fail "$1"; log_fix "sh $0 --help"; log_end || :; exit 2
}

MODE=classify; JSON=0; DEEP_T=25
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --json)    JSON=1; shift ;;
    --seam)    MODE=seam; shift ;;
    --deep)    DEEP_T="${2:?--deep needs a number}"; shift 2 ;;
    --)        shift; break ;;
    -*)        _usage_fail "unknown flag $1" ;;
    *)         break ;;
  esac
done
[ $# -gt 0 ] || _usage_fail "missing argument: a file or directory to measure"

# expand dirs to the .sh files under them; keep explicit files as given
files_of() {
  for a in "$@"; do
    if [ -d "$a" ]; then find "$a" -name '*.sh' -type f | sort
    elif [ -f "$a" ]; then printf '%s\n' "$a"
    else :   # classify() has already refused a path that does not exist
    fi
  done
}

# The awk program below is ONE single-quoted shell word. NO APOSTROPHES INSIDE IT,
# in code or in comments — one ends the word and the file stops parsing as shell.
# harbor#299 is that defect in the statusline jq program; `sh -n` is what catches it.
SHAPE_AWK='
  function owner_of(s) { return (ndef[s] == 1 && length(s) >= 3) ? own[s] : "" }
  /^[a-zA-Z_][a-zA-Z0-9_]*\(\)/ { s = $0; sub(/\(\).*/, "", s); ndef[s]++; own[s] = FILENAME }
  { line[++nl] = FILENAME "\x01" $0; loc++ }
  END {
    for (s in ndef) if (owner_of(s) != "") nu++
    for (i = 1; i <= nl; i++) {
      split(line[i], p, "\x01"); f = p[1]; t = p[2]
      gsub(/\$\(/, " ", t); gsub(/[;&|()`]/, " ", t)
      n = split(t, w, /[ \t]+/)
      for (j = 1; j <= n; j++) {
        o = owner_of(w[j]); if (o == "" || o == f) continue
        if (j > 1 && w[j-1] != "" && w[j-1] !~ /^(if|then|else|do|!|\{|\}|&&|\|\|)$/) continue
        ed++; dest[o]++; pair[f "\x01" o] = 1
      }
    }
    for (k in pair) np++
    for (d in dest) if (dest[d] > top) { top = dest[d]; topf = d }
    if (nu == 0) nu = 1
    depth = loc / nu
    dens  = (nf > 1) ? np / (nf * (nf - 1)) : 0
    hub   = (ed > 0) ? top / ed : 0
    sc    = (cw > 0) ? (cp - cw) / cw : 0
    deep  = (depth >= dt); frag = (nf > 1)
    quad  = deep ? (frag ? "DEEP+MICRO" : "DEEP+MONO") : (frag ? "SHALLOW+MICRO" : "SHALLOW+MONO")
    topo  = (dens >= 0.40) ? "MESH" : ((hub >= 0.25) ? "HUB" : "chain")
    sub(/.*\//, "", topf)
    if (js)
      printf "{\"files\":%d,\"loc\":%d,\"symbols\":%d,\"depth\":%.1f,\"density\":%.3f,\"hub\":%.2f,\"split_cost\":%.3f,\"quadrant\":\"%s\",\"topology\":\"%s\",\"hub_file\":\"%s\"}\n",
             nf, loc, nu, depth, dens, hub, sc, quad, topo, topf
    else
      printf "%-14s files=%-4d LOC=%-6d symbols=%-5d depth=%-6.1f density=%-5.2f hub=%-5.2f split_cost=%+.3f  %s / %s%s\n",
             label, nf, loc, nu, depth, dens, hub, sc, quad, topo, (topf ? "  (hub: " topf ")" : "")
  }'

csum() { _t=0; for _p in "$@"; do _t=$((_t + $(gzip -9c < "$_p" | wc -c))); done; printf '%s' "$_t"; }

classify() {
  for _a in "$@"; do
    [ -e "$_a" ] || { log_fail "no such path: $_a"; log_fix "ls -d $_a  # name a file or a directory of .sh files"; log_end || :; exit 2; }
  done
  set -- $(files_of "$@")
  [ $# -gt 0 ] || { log_fail "no .sh files found under the paths given"; log_fix "find . -name '*.sh' -type f"; log_end || :; exit 2; }
  log_head "classify $# file(s)"
  _cw=$(cat "$@" | gzip -9c | wc -c | tr -d ' ')
  awk -v nf="$#" -v cw="$_cw" -v cp="$(csum "$@")" -v dt="$DEEP_T" -v js="$JSON" \
      -v label="${LABEL:-shape}" "$SHAPE_AWK" "$@"
  log_ok "classified $# file(s)"
}

seam() {
  _f="$1"; _corp="${2:-$(dirname "$_f")}"
  [ -f "$_f" ] || { log_fail "no such file: $_f"; log_fix "ls $_f  # --seam takes one file"; log_end || :; exit 2; }
  log_head "seam $_f"
  _d=$(mktemp -d "${TMPDIR:-/tmp}/harbor.XXXXXX"); trap 'rm -rf "$_d"' EXIT INT TERM
  mkdir -p "$_d/fn" "$_d/arb"
  awk -v d="$_d/fn" 'BEGIN{n=0;o=d"/000.sh"}
    /^[a-zA-Z_][a-zA-Z0-9_]*\(\)/ {n++; o=sprintf("%s/%03d.sh", d, n)} {print >> o}' "$_f"
  _np=$(ls "$_d/fn" | wc -l | tr -d ' '); _loc=$(wc -l < "$_f" | tr -d ' ')
  awk -v d="$_d/arb" -v per="$(( (_loc + _np - 1) / _np ))" \
    '{printf "%s\n", $0 >> sprintf("%s/%03d.sh", d, int((NR-1)/per))}' "$_f"
  _cw=$(gzip -9c < "$_f" | wc -c | tr -d ' ')
  # VALUE — only symbols the whole corpus defines exactly once, called from >=2
  # other files at command position. Without the uniqueness filter this scores
  # every suite SPLIT HAS VALUE on `bad`, `run` and `verdict`.
  _uniq=$(grep -hoE '^[a-zA-Z_][a-zA-Z0-9_]*\(\)' "$_corp"/*.sh 2>/dev/null \
          | tr -d '()' | sort | uniq -c | awk '$1 == 1 { print $2 }')
  _b=$(basename "$_f"); _tot=0; _val=0
  for _s in $(grep -oE '^[a-zA-Z_][a-zA-Z0-9_]*\(\)' "$_f" | tr -d '()' | awk 'length($0) >= 3'); do
    printf '%s\n' "$_uniq" | grep -qx "$_s" || continue
    _tot=$((_tot + 1))
    _n=$(grep -lE "(^|[;&|(\`]|\\\$\()[[:space:]]*$_s([[:space:]]|\$|\))" "$_corp"/*.sh 2>/dev/null \
         | grep -vc "/$_b\$" || true)
    [ "${_n:-0}" -ge 2 ] && _val=$((_val + 1))
  done
  awk -v f="$_b" -v np="$_np" -v loc="$_loc" -v cw="$_cw" -v tot="$_tot" -v val="$_val" \
      -v a="$(csum "$_d"/fn/*)" -v b="$(csum "$_d"/arb/*)" -v js="$JSON" 'BEGIN{
    sf = (a - cw) / cw; sa = (b - cw) / cw; gain = sa - sf
    real = (gain >= 0.06); worth = (val >= 2)
    v = (real && worth) ? "SPLIT IS EARNED" \
        : (real ? "real but PRIVATE — leave it one file" \
                : (worth ? "callers exist but the boundaries are arbitrary" : "no seam"))
    if (js)
      printf "{\"file\":\"%s\",\"parts\":%d,\"gain\":%.3f,\"real\":%s,\"external_callers\":%d,\"earned\":%s}\n",
             f, np, gain, (real ? "true" : "false"), val, ((real && worth) ? "true" : "false")
    else
      printf "%-26s LOC=%-6d parts=%-4d gain=%+.3f symbols=%-4d callers>=2: %-4d %s\n",
             f, loc, np, gain, tot, val, v
  }'
  log_ok "measured $_b: $_np part(s), $_tot owned symbol(s)"
}

case "$MODE" in
  classify) classify "$@" ;;
  seam)     seam "$@" ;;
esac
log_end; exit $?
