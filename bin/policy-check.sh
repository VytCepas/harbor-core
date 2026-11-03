#!/usr/bin/env sh
# policy-check.sh (harbor#1026, #1028) — the constitution as a register: every clause a row, every row traced.
#
#   sh bin/policy-check.sh --census              every bold-led clause of policy/constitution.md beside its row; a clause with no row,
#                                                a row with no clause, or a repeated anchor is a finding
#   sh bin/policy-check.sh --deployed [FILE]     the same anchors against the deployed constitution (default ~/.claude/CLAUDE.md)
#   sh bin/policy-check.sh --shape               strength, binding, modality and relation values against terms.tsv and the grammar
#   sh bin/policy-check.sh --trace               trace down: a clause with neither a control nor `judgment`, or a control id that is no row
#   sh bin/policy-check.sh --trace-up            trace up: a control that no clause names (counts by type; --all lists them)
#   sh bin/policy-check.sh --check               --census, --shape and --trace: what lint-conventions runs
#   sh bin/policy-check.sh --motivation          each clause's issues, derived from commit subjects that touched its anchor and from
#                                                coverage-incidents.tsv; a clause with none is a finding
#   sh bin/policy-check.sh --why <path>          file -> control -> clause -> issue, from registry rows and commit refs only
#   sh bin/policy-check.sh --notes DIR           feedback notes with neither an `enforced_by:` line nor a clause, for the PROPOSE lane
#   sh bin/policy-check.sh --amends BASE HEAD    the constitutional clauses (row or prose block) that differ between two trees; exit 1 when any
#   sh bin/policy-check.sh --ask <1-10> [ARG]    the competency questions of research/15 section 6 as queries over the registers
#   sh bin/policy-check.sh --enforcement         policy/enforcement.tsv: every clause has a pair, moments and modes are known, a pair binds
#                                                at its earliest checkable moment or says why not, and promotion rules hold (--promotion: those only)
#   sh bin/policy-check.sh --gen enforcement [--check]   docs/policy/enforcement.md, the clause x moment matrix; --check fails on a hand edit
#   sh bin/policy-check.sh --report              pairs not earning their keep (never red), proposed to a person, never edited
#   sh bin/policy-check.sh --self-test           every arm goes red once on a fixture under fixtures/policy/
#   --root DIR   the tree judged (default: this checkout); --all lists every item instead of the first few
#
# A CLAUSE IS ONE BOLD-LED BLOCK: a paragraph, bullet or numbered item whose first characters are `**`. Its ANCHOR is that bold text,
# whitespace-collapsed, so the prose carries no id of its own and the always-on file grows by nothing (harbor#1026 item 10). Editing
# the bold lead of a clause is an amendment: the census goes red until its row follows.
# exit 0 pass · 1 a finding · 2 usage · 3 unchecked (a register or the constitution is missing). Findings print as `  WARN: [policy.<rule>]`:
# the mode of each rule is its standards/naming/controls.tsv row, applied by the engine that calls this (bin/lint-conventions.sh).
set -eu
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/library-log.sh"
log_init policy-check
LOG_FD=2   # stdout carries the answer (--ask, --why, --gen); findings and the summary go to stderr
ROOT="$(CDPATH='' cd -- "$HERE/.." && pwd)"
TAB="$(printf '\t')"
MODE=''; ARG=''; ARG2=''; GENCHECK=0; ALL=0; DEPLOYED_FILE=''
usage() { sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; }
while [ $# -gt 0 ]; do
  case "$1" in
    --check) if [ "$MODE" = gen ]; then GENCHECK=1; else MODE=check; fi ;;
    --census|--shape|--trace|--trace-up|--motivation|--self-test|--enforcement) MODE="${1#--}" ;;
    --deployed) MODE=deployed; case "${2:-}" in ''|--*) ;; *) DEPLOYED_FILE="$2"; shift ;; esac ;;
    --promotion|--report) MODE="${1#--}" ;;
    --why|--notes|--gen) MODE="${1#--}"; [ $# -ge 2 ] || { usage >&2; exit 2; }; ARG="$2"; shift ;;
    --ask) MODE=ask; [ $# -ge 2 ] || { usage >&2; exit 2; }; ARG="$2"; shift; case "${2:-}" in ''|--*) ;; *) ARG2="$2"; shift ;; esac ;;
    --amends) MODE=amends; [ $# -ge 3 ] || { usage >&2; exit 2; }; ARG="$2"; ARG2="$3"; shift 2 ;;
    --root) [ $# -ge 2 ] || { usage >&2; exit 2; }; ROOT="$(CDPATH='' cd -- "$2" && pwd)"; shift ;;
    --all) ALL=1 ;;
    -h|--help) usage; exit 0 ;;
    *) lg_fail 'unknown argument %s' "$1"; usage >&2; exit 2 ;;
  esac
  shift
done
[ -n "$MODE" ] || { usage >&2; exit 2; }
CONST="$ROOT/policy/constitution.md"; CLAUSES="$ROOT/policy/clauses.tsv"
TERMS="$ROOT/standards/naming/terms.tsv"; CONTROLS="$ROOT/standards/naming/controls.tsv"
# a refusal to judge: the log line, and where to read why (contracts/logging.md)
lg_fail() { _lf="$1"; shift; log_fail "$(printf "$_lf" "$@")"; log_nofix "bin/policy-check.sh --help (harbor#1026)"; }
# findings are counted in a file: most are raised inside a `| while read` subshell, which a plain counter would not survive
FOUNDF="$(mktemp "${TMPDIR:-/tmp}/pc.XXXXXX")"; trap 'rm -f "$FOUNDF"' EXIT
finding() { log_warn "[policy.$1] $2"; echo x >> "$FOUNDF"; }
need() { for _f in "$@"; do [ -f "$_f" ] || { lg_fail '%s is missing, so nothing was judged' "${_f#"$ROOT"/}"; exit 3; }; done; }
# the first few of a list, or all of it
few() { if [ "$ALL" = 1 ]; then cat; else awk 'NR <= 5 { print } NR == 6 { print "  ... (--all lists every one)" }'; fi; }

# anchors FILE -> `<section><TAB><anchor>`, one per bold-led block, fenced code skipped
anchors() {
  awk '
  function norm(s) { gsub(/[ \t]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s }
  /^## / { sec = substr($0, 4); sub(/ ·.*/, "", sec); prevblank = 1; fence = 0; next }
  /^```/ { fence = !fence; prevblank = 0; next }
  fence { next }
  pend { e = index($0, "**"); if (e) { buf = buf " " substr($0, 1, e - 1); print sec "\t" norm(buf); pend = 0 } else buf = buf " " $0; prevblank = 0; next }
  /^[ \t]*$/ { prevblank = 1; next }
  { line = $0; marker = 0
    if (line ~ /^- /) { sub(/^- /, "", line); marker = 1 } else if (line ~ /^[0-9]+\. /) { sub(/^[0-9]+\. /, "", line); marker = 1 }
    if ((prevblank || marker) && substr(line, 1, 2) == "**") {
      t = substr(line, 3); e = index(t, "**")
      if (e == 0) { pend = 1; buf = t } else print sec "\t" norm(substr(t, 1, e - 1)) }
    prevblank = 0 }' "$1"
}
# blocks FILE -> `<anchor><TAB><the clause's whole block, whitespace-collapsed>`: what an amendment changes, not only its lead
blocks() {
  awk '
  function norm(s) { gsub(/[ \t]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s }
  function flush() { if (cur != "") print cur "\t" norm(txt); cur = ""; txt = "" }
  /^## / || /^---$/ { flush(); prevblank = 1; fence = 0; next }
  /^```/ { fence = !fence }
  pend { e = index($0, "**"); txt = txt " " $0
         if (e) { buf = buf " " substr($0, 1, e - 1); cur = norm(buf); pend = 0 } else buf = buf " " $0
         prevblank = 0; next }
  { line = $0; marker = 0
    if (!fence) {
      if (line ~ /^- /) { sub(/^- /, "", line); marker = 1 } else if (line ~ /^[0-9]+\. /) { sub(/^[0-9]+\. /, "", line); marker = 1 }
      if ((prevblank || marker) && substr(line, 1, 2) == "**") {
        t = substr(line, 3); e = index(t, "**")
        flush(); txt = $0; prevblank = 0
        if (e > 0) cur = norm(substr(t, 1, e - 1)); else { pend = 1; buf = t }
        next } }
    if (cur != "") txt = txt " " $0
    prevblank = ($0 ~ /^[ \t]*$/) }
  END { flush() }' "$1"
}
# rows FILE -> the data rows of a register, header row first, `#` lines dropped
rows() { awk '/^#/ || /^[ \t]*$/ { next } { print }' "$1"; }
# a column by name: col FILE NAME -> that column of every data row, in order
col() { rows "$1" | awk -F'\t' -v c="$2" 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == c) k = i; if (!k) { print "policy-check: no column " c > "/dev/stderr"; exit 3 } next } { print $k }'; }

do_census() {
  need "$CONST" "$CLAUSES"
  _a="$(mktemp "${TMPDIR:-/tmp}/pc.XXXXXX")"; _r="$(mktemp "${TMPDIR:-/tmp}/pc.XXXXXX")"; anchors "$CONST" | cut -f2 > "$_a"
  rows "$CLAUSES" | awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) { if ($i == "id") ci = i; if ($i == "anchor") ai = i } if (!ci || !ai) exit 3; next } { print $ci "\t" $ai }' > "$_r" \
    || { lg_fail 'policy/clauses.tsv has no id or anchor column'; rm -f "$_a" "$_r"; exit 3; }
  awk -F'\t' -v quiet="${QUIET:-0}" '
    FILENAME == ARGV[1] { n++; P[$0]++; ord[n] = $0; next }
    { R[$2]++; id[$2] = $1; rid[$1]++ }
    END {
      for (i = 1; i <= n; i++) { a = ord[i]; if (a in seen) continue; seen[a] = 1
        if (!quiet) printf "%s\t%s\n", (a in R) ? id[a] : "-", substr(a, 1, 78)
        if (P[a] > 1) printf "FIND\tduplicate-anchor\tthe anchor %c%s%c opens %d clauses in the prose; an anchor must be unique\n", 34, substr(a, 1, 60), 34, P[a]
        if (!(a in R)) printf "FIND\tclause-no-row\tthe prose clause %c%s%c has no row in policy/clauses.tsv\n", 34, substr(a, 1, 70), 34 }
      for (a in R) { if (!(a in P)) printf "FIND\trow-no-clause\trow %s anchors %c%s%c and no bold-led block of the prose opens with that text\n", id[a], 34, substr(a, 1, 60), 34
        if (R[a] > 1) printf "FIND\tduplicate-row\ttwo rows carry the anchor %c%s%c\n", 34, substr(a, 1, 60), 34 }
      for (i in rid) if (rid[i] > 1) printf "FIND\tduplicate-id\tthe id %s is on %d rows\n", i, rid[i]
      printf "SUM\t%d\t%d\n", n, length(R) }' "$_a" "$_r" > "$_a.out"
  grep -v '^FIND	\|^SUM	' "$_a.out" || :
  awk -F'\t' '$1 == "FIND" { print $2 "\t" $3 }' "$_a.out" | while IFS="$TAB" read -r _k _m; do finding "$_k" "$_m"; done
  _fn="$(grep -c '^FIND	' "$_a.out" || :)"
  awk -F'\t' '$1 == "SUM" { printf "policy-check: census: %d clause(s) in the prose, %d row(s) in the register", $2, $3 }' "$_a.out"
  printf ', %d finding(s)\n' "$_fn"
  rm -f "$_a" "$_r" "$_a.out"
}

do_deployed() {
  need "$CLAUSES"
  _d="${DEPLOYED_FILE:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/CLAUDE.md}"
  [ -f "$_d" ] || { lg_fail 'no deployed constitution at %s, so nothing was judged' "$_d"; exit 3; }
  _a="$(mktemp "${TMPDIR:-/tmp}/pc.XXXXXX")"; anchors "$_d" | cut -f2 > "$_a"
  _miss="$(col "$CLAUSES" anchor | awk -F'\t' 'NR == FNR { A[$0] = 1; next } !($0 in A) { print substr($0, 1, 70) }' "$_a" -)"
  _extra="$(rows "$CLAUSES" | awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == "anchor") k = i; next } { print $k }' | awk -F'\t' 'NR == FNR { R[$0] = 1; next } !($0 in R) { print substr($0, 1, 70) }' - "$_a")"
  _nm=0; _ne=0
  [ -z "$_miss" ] || _nm="$(printf '%s\n' "$_miss" | grep -c .)"
  [ -z "$_extra" ] || _ne="$(printf '%s\n' "$_extra" | grep -c .)"
  [ "$_nm" -eq 0 ] || { finding deployed-missing "$_nm row(s) anchor text the deployed constitution does not carry (it is behind the source: sh bin/policy-constitution-install.sh):"; printf '%s\n' "$_miss" | few | sed 's/^/    /'; }
  [ "$_ne" -eq 0 ] || { finding deployed-extra "$_ne bold-led block(s) of the deployed constitution have no row:"; printf '%s\n' "$_extra" | few | sed 's/^/    /'; }
  printf 'policy-check: deployed %s: %d row(s) without their anchor, %d clause(s) without a row\n' "$_d" "$_nm" "$_ne"
  rm -f "$_a"
}

# a closed set from terms.tsv: ids of the rows whose class list holds CLASS
term_ids() { awk -F'\t' -v c="$1" '/^#/ || $1 == "id" { next } { n = split($2, k, ","); for (i = 1; i <= n; i++) if (k[i] == c) print $1 }' "$TERMS"; }

do_shape() {
  need "$CLAUSES" "$TERMS"
  _t="$(mktemp "${TMPDIR:-/tmp}/pc.XXXXXX")"
  { term_ids strength | sed 's/^/S	/'; term_ids modality | sed 's/^/M	/'; term_ids relation | sed 's/^/R	/'; } > "$_t"
  [ "$(grep -c '^S	' "$_t" || :)" -gt 0 ] || { lg_fail 'terms.tsv has no term of class strength, so nothing was judged'; rm -f "$_t"; exit 3; }
  rows "$CLAUSES" | awk -F'\t' '
    FILENAME == ARGV[1] { K[$1 SUBSEP $2] = 1; next }
    FNR == 1 { for (i = 1; i <= NF; i++) H[$i] = i; next }
    { id = $H["id"]; s = $H["strength"]; b = $H["binding"]; m = $H["modality"]
      if (!(("S" SUBSEP s) in K)) printf "%s\tstrength %s is no term of class strength\n", id, s
      if (!(("M" SUBSEP m) in K)) printf "%s\tmodality %s is no term of class modality\n", id, m
      if (b !~ /^(box|every-repo|repo:[a-z0-9._-]+|surface:[a-z0-9._-]+|context:[a-z0-9._-]+)$/) printf "%s\tbinding %s is none of box, every-repo, repo:<name>, surface:<id>\n", id, b
      for (c in H) if ($H[c] == "" ) printf "%s\tcolumn %s is empty: write - for none\n", id, c
      nr = split($H["relation"], rl, ","); nn = split($H["min"], mn, ","); nx = split($H["max"], mx, ",")
      if (nn != nr || nx != nr) printf "%s\trelation, min and max hold %d, %d and %d value(s): one each per relation\n", id, nr, nn, nx
      if ($H["relation"] != "-") for (i = 1; i <= nr; i++) {
        if (!(("R" SUBSEP rl[i]) in K)) printf "%s\trelation %s is no term of class relation\n", id, rl[i]
        if (mn[i] !~ /^[0-9]+$/ || (mx[i] != "*" && mx[i] !~ /^[0-9]+$/)) printf "%s\tmin %s and max %s are not a count and a count or *\n", id, mn[i], mx[i] } }' "$_t" - \
    | while IFS="$TAB" read -r _i _m; do finding clause-shape "$_i: $_m"; done
  rm -f "$_t"
  printf 'policy-check: shape: %d clause row(s) judged\n' "$(col "$CLAUSES" id | grep -c .)"
}

do_trace() {
  need "$CLAUSES" "$CONTROLS"
  rows "$CLAUSES" | awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) H[$i] = i; next } { print $H["id"] "\t" $H["enforced_by"] }' > "${TMPDIR:-/tmp}/pc.$$.eb"
  rows "$CONTROLS" | awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) H[$i] = i; next } { print $H["id"]; if ($H["emitted"] != "-") print $H["emitted"] }' > "${TMPDIR:-/tmp}/pc.$$.ids"
  awk -F'\t' 'FILENAME == ARGV[1] { C[$1] = 1; next }
    { n = split($2, e, ",")
      if ($2 == "" || $2 == "-") { printf "%s\ttrace-down\tno control and no judgment: a rule with no mechanism is a wish\n", $1; next }
      for (i = 1; i <= n; i++) { if (e[i] == "judgment") { j++; continue } if (!(e[i] in C)) printf "%s\ttrace-dangling\tenforced_by names %s and controls.tsv has no such control\n", $1, e[i] } }' \
    "${TMPDIR:-/tmp}/pc.$$.ids" "${TMPDIR:-/tmp}/pc.$$.eb" | while IFS="$TAB" read -r _i _k _m; do finding "$_k" "$_i: $_m"; done
  _n="$(grep -c . "${TMPDIR:-/tmp}/pc.$$.eb" || :)"
  _j="$(awk -F'\t' '$2 ~ /(^|,)judgment(,|$)/ && $2 == "judgment" { n++ } END { print n + 0 }' "${TMPDIR:-/tmp}/pc.$$.eb")"
  printf 'policy-check: trace: %d clause(s), %d judgment-only\n' "$_n" "$_j"
  rm -f "${TMPDIR:-/tmp}/pc.$$.eb" "${TMPDIR:-/tmp}/pc.$$.ids"
}

do_trace_up() {
  need "$CLAUSES" "$CONTROLS"
  _u="$(mktemp "${TMPDIR:-/tmp}/pc.XXXXXX")"
  rows "$CLAUSES" | awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) H[$i] = i; next } { n = split($H["enforced_by"], e, ","); for (i = 1; i <= n; i++) print e[i] }' | sort -u > "$_u"
  rows "$CONTROLS" | awk -F'\t' 'FILENAME == ARGV[1] { U[$1] = 1; next } FNR == 1 { for (i = 1; i <= NF; i++) H[$i] = i; next }
    { id = $H["id"]; em = $H["emitted"]; if (!(id in U) && !(em in U)) print $H["type"] "\t" id }' "$_u" - > "$_u.out"
  _t="$(grep -c . "$_u.out" || :)"
  if [ "$_t" -gt 0 ]; then
    finding trace-up "$_t control(s) enforce no clause (by type: $(cut -f1 "$_u.out" | sort | uniq -c | awk '{ printf "%s%s %s", (NR > 1 ? ", " : ""), $2, $1 }'))"
    [ "$ALL" = 0 ] || cut -f2 "$_u.out" | sed 's/^/    /'
  fi
  printf 'policy-check: trace-up: %d of %d control(s) are named by a clause\n' "$(( $(col "$CONTROLS" id | grep -c .) - _t ))" "$(col "$CONTROLS" id | grep -c .)"
  rm -f "$_u" "$_u.out"
}

# motivation: clause id -> issues. Sources: commit subjects whose commit changed the clause's anchor text in the constitution
# (git log -S), and coverage-incidents.tsv rows whose mechanism resolves to a control the clause names.
do_motivation() {
  need "$CLAUSES"
  _inc="$ROOT/registries/coverage-incidents.tsv"; _o="$(mktemp "${TMPDIR:-/tmp}/pc.XXXXXX")"
  rows "$CLAUSES" | awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) H[$i] = i; next } { print $H["id"] "\t" $H["enforced_by"] "\t" $H["anchor"] }' > "$_o.c"
  : > "$_o"
  while IFS="$TAB" read -r _id _eb _an; do
    _is=''
    if [ "$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null)" = "$ROOT" ]; then
      _is="$(git -C "$ROOT" log --format=%s -S"$_an" -- policy/constitution.md CONSTITUTION.md 2>/dev/null | grep -oE '[A-Za-z0-9_-]*#[0-9]+' | sed 's/^#/harbor#/' | sort -u || :)"
    fi
    _ic=''
    if [ -f "$_inc" ]; then
      _ic="$(rows "$_inc" | awk -F'\t' -v eb="$_eb" -v ctl="$CONTROLS" '
        BEGIN { n = split(eb, e, ","); for (i = 1; i <= n; i++) E[e[i]] = 1
                while ((getline l < ctl) > 0) { if (l ~ /^#/) continue; split(l, c, "\t"); if (c[1] == "id") continue; M[c[1]] = c[1]; if (c[12] != "-" && c[12] != "") { x = c[12]; sub(/^[a-z]+:/, "", x); M[x] = c[1] } } }
        NR == 1 { next }
        { k = split($5, ms, ","); for (j = 1; j <= k; j++) { m = ms[j]; sub(/^[a-z]+:/, "", m); if ((m in M) && (M[m] in E)) { print $1; break } } }' | sort -u)"
    fi
    printf '%s\t%s\t%s\n' "$_id" "$(printf '%s\n' "$_is" | grep -c . || :)" "$(printf '%s\n' "$_ic" | grep -c . || :)" >> "$_o"
    [ -n "$_is$_ic" ] || finding clause-no-motive "$_id has no issue edge: no commit subject with an issue reference touched its anchor and no incident names its control"
  done < "$_o.c"
  awk -F'\t' '{ if ($2 + $3 > 0) w++; if ($2 > 0) s++; if ($3 > 0) i++; c++ } END { printf "policy-check: motivation: %d of %d clause(s) have an edge (%d from commit subjects, %d from incidents)\n", w, c, s, i }' "$_o"
  rm -f "$_o" "$_o.c"
}

do_why() {
  need "$CLAUSES" "$CONTROLS"
  _p="${ARG#./}"
  _ctl="$(rows "$CONTROLS" | awk -F'\t' -v p="$_p" 'NR == 1 { for (i = 1; i <= NF; i++) H[$i] = i; next } $H["engine"] == p { print $H["id"] }')"
  [ -n "$_ctl" ] || { printf 'policy-check: why %s: no control names this file as its engine (controls.tsv engine), so nothing traces down from it\n' "$_p"; exit 1; }
  _wn="$(mktemp "${TMPDIR:-/tmp}/pc.XXXXXX")"
  printf '%s\n' "$_ctl" | while read -r _c; do
    _cl="$(rows "$CLAUSES" | awk -F'\t' -v c="$_c" 'NR == 1 { for (i = 1; i <= NF; i++) H[$i] = i; next } { n = split($H["enforced_by"], e, ","); for (i = 1; i <= n; i++) if (e[i] == c) print $H["id"] "\t" $H["anchor"] }')"
    if [ -n "$_cl" ] || [ "$ALL" = 1 ]; then printf '%s  implements  %s\n' "$_p" "$_c"; fi
    if [ -z "$_cl" ]; then
      if [ "$ALL" = 1 ]; then printf '  %s  enforces  (no clause: policy no one approved, or a clause not yet registered)\n' "$_c"; else echo "$_c" >> "$_wn"; fi
      continue
    fi
    printf '%s\n' "$_cl" | while IFS="$TAB" read -r _i _a; do
      printf '  %s  enforces  %s: %s\n' "$_c" "$_i" "$(printf '%s' "$_a" | cut -c1-70)"
      _inc="$ROOT/registries/coverage-incidents.tsv"
      [ ! -f "$_inc" ] || rows "$_inc" | awk -F'\t' -v c="$_c" 'NR == 1 { next } { m = $5; sub(/^[a-z]+:/, "", m); if (m == c) print "    " $1 "  " substr($3, 1, 70) }' | head -3
      if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
        git -C "$ROOT" log --format=%s -S"$_a" -- policy/constitution.md CONSTITUTION.md 2>/dev/null | grep -E '#[0-9]+' | head -3 | sed 's/^/    commit  /'
      fi
    done
  done
  [ ! -s "$_wn" ] || printf 'policy-check: why %s: %d other control(s) run here enforce no clause (--all lists them)\n' "$_p" "$(grep -c . "$_wn")"
  rm -f "$_wn"
}

# the constitutional clauses an edit touches: a changed, added or removed row, or a changed prose block, of strength constitutional
do_amends() {
  _bd="$ARG"; _hd="$ARG2"
  need "$_bd/policy/clauses.tsv" "$_hd/policy/clauses.tsv" "$_bd/policy/constitution.md" "$_hd/policy/constitution.md"
  _o="$(mktemp "${TMPDIR:-/tmp}/pc.XXXXXX")"
  blocks "$_bd/policy/constitution.md" > "$_o.bb"; blocks "$_hd/policy/constitution.md" > "$_o.hb"
  { rows "$_bd/policy/clauses.tsv" | awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) H[$i] = i; next } { print "B\t" $H["id"] "\t" $H["strength"] "\t" $H["anchor"] "\t" $0 }'
    rows "$_hd/policy/clauses.tsv" | awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) H[$i] = i; next } { print "H\t" $H["id"] "\t" $H["strength"] "\t" $H["anchor"] "\t" $0 }'; } > "$_o.rows"
  awk -F'\t' '
    FILENAME == ARGV[1] { BB[$1] = $2; next }
    FILENAME == ARGV[2] { HB[$1] = $2; next }
    { side = $1; id = $2; if ($3 == "constitutional") C[id] = 1; R[side, id] = $0; A[side, id] = $4; ids[id] = 1 }
    END { for (id in ids) { if (!(id in C)) continue
        rb = ((("B", id) in R) ? R["B", id] : ""); rh = ((("H", id) in R) ? R["H", id] : "")
        sub(/^[BH]\t/, "", rb); sub(/^[BH]\t/, "", rh)
        ab = A["B", id]; ah = A["H", id]
        if (rb != rh) why = "its row changed"
        else if (!(ab in BB) || !(ah in HB)) why = "its prose block is missing on one side"
        else if (BB[ab] != HB[ah]) why = "its prose changed"
        else why = ""
        if (why != "") printf "%s\t%s\n", id, why } }' "$_o.bb" "$_o.hb" "$_o.rows" | sort > "$_o.out"
  # a constitutional prose block that has no row on either side is an amendment too: the rows are what name its strength
  while IFS="$TAB" read -r _i _w; do finding amendment "$_i: $_w"; done < "$_o.out"
  printf 'policy-check: amends: %d constitutional clause(s) differ\n' "$(grep -c . "$_o.out" || :)"
  rm -f "$_o" "$_o.bb" "$_o.hb" "$_o.rows" "$_o.out"
}

# the competency questions (research/15 section 6) as queries; a question the registers cannot yet answer says what it lacks
do_ask() {
  need "$CLAUSES" "$CONTROLS"
  case "$ARG" in
    1) printf 'Q1 what disables check X, and who is notified: unanswerable from the registers here; build/graph.tsv carries disabled-by and notifies (bin/doc-graph-generate.sh)\n' ;;
    2) printf 'Q2 clauses with no control and no judgment declaration:\n'; rows "$CLAUSES" | awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) H[$i] = i; next } $H["enforced_by"] == "" || $H["enforced_by"] == "-" { print "  " $H["id"] }' ;;
    3) printf 'Q3 controls that enforce no clause (counts by type):\n'; do_trace_up 2>&1 | sed 's/^/  /' ;;
    4) printf 'Q4 kinds governed by no clause: unanswerable until a clause target names a kinds.tsv id (targets are free words today)\n' ;;
    5) [ -n "$ARG2" ] || { lg_fail '--ask 5 needs a path'; exit 2; }; ARG="$ARG2"; do_why ;;
    6) [ -n "$ARG2" ] || { lg_fail '--ask 6 needs an id'; exit 2; }
       printf 'Q6 inbound references to %s (a register row naming it as a whole cell or list member):\n' "$ARG2"
       git -C "$ROOT" ls-files -co --exclude-standard '*.tsv' 2>/dev/null | grep -v '^fixtures/' | while read -r _t; do
         awk -F'\t' -v id="$ARG2" -v f="$_t" '/^#/ { next } { for (i = 1; i <= NF; i++) { n = split($i, m, /[, ]/); for (j = 1; j <= n; j++) if (m[j] == id && !($1 == id && i == 1)) { print "  " f ": row " $1 ", column " i; break } } }' "$ROOT/$_t"
       done ;;
    7) printf 'Q7 repo-tier rules contradicting a constitutional clause: unanswerable until policy/precedence.tsv exists (harbor#1027)\n' ;;
    8) printf 'Q8 controls that never went red (red_proof is -), by type:\n'
       rows "$CONTROLS" | awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) H[$i] = i; next } $H["red_proof"] == "-" || $H["red_proof"] == "" { c[$H["type"]]++ } END { for (t in c) printf "  %s %d\n", t, c[t] }' | sort ;;
    9) printf 'Q9 judgment-only share per strength:\n'
       rows "$CLAUSES" | awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) H[$i] = i; next } { t[$H["strength"]]++; if ($H["enforced_by"] == "judgment") j[$H["strength"]]++ } END { for (s in t) printf "  %s %d of %d\n", s, j[s] + 0, t[s] }' | sort ;;
    10) printf 'Q10 findings with no destination: unanswerable from the registers here; the findings-land-in relation is derived into build/graph.tsv\n' ;;
    *) lg_fail '--ask takes 1 to 10'; exit 2 ;;
  esac
}

do_notes() {
  [ -d "$ARG" ] || { lg_fail '%s is not a directory' "$ARG"; exit 2; }
  _n=0; _bad=0
  for _f in "$ARG"/*.md; do
    [ -f "$_f" ] || continue
    case "${_f##*/}" in MEMORY.md|INDEX-FULL.md) continue ;; esac
    grep -q '^type: *feedback' "$_f" || continue
    _n=$((_n+1))
    grep -q '^enforced_by:' "$_f" || { _bad=$((_bad+1)); finding note-unlinked "${_f##*/}: a feedback note with no enforced_by: line (a clause id, a control id or judgment); propose a mechanism, do not promote"; }
  done
  printf 'policy-check: notes: %d feedback note(s), %d with no clause or control link\n' "$_n" "$_bad"
}

# ── the enforcement matrix (harbor#1028) ─────────────────────────────────────────────────────────────────────────────────────────
ENFORCEMENT="$ROOT/policy/enforcement.tsv"
MOMENTS="write session commit pr merge schedule deploy judgment"
do_enforcement() {
  need "$ENFORCEMENT" "$CLAUSES" "$CONTROLS" "$TERMS"
  _today="${HARBOR_POLICY_TODAY:-$(date +%F)}"
  _m="$(term_ids moment | tr '\n' ' ')"
  { printf 'C\n'; rows "$CLAUSES" | awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) H[$i] = i; next } { print "C\t" $H["id"] }'
    rows "$CONTROLS" | awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) H[$i] = i; next } { print "K\t" $H["id"] "\t" $H["mode"] "\t" $H["red_proof"] }'
    rows "$ENFORCEMENT" | awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) H[$i] = i; next } { print "E\t" $H["id"] "\t" $H["clause"] "\t" $H["moment"] "\t" $H["mode"] "\t" $H["control"] "\t" $H["since"] "\t" $H["promoted_by"] "\t" $H["checkable_at"] "\t" $H["later_why"] }'; } \
  | awk -F'\t' -v only="$ONLY" -v today="$_today" -v moments="$MOMENTS" -v known="$_m" '
    function jdn(d,   y, m, dd, a, b) { if (d !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return -1; y = substr(d, 1, 4) + 0; m = substr(d, 6, 2) + 0; dd = substr(d, 9, 2) + 0
      a = int((14 - m) / 12); y = y + 4800 - a; m = m + 12 * a - 3; return dd + int((153 * m + 2) / 5) + 365 * y + int(y / 4) - int(y / 100) + int(y / 400) - 32045 }
    BEGIN { n = split(moments, mset, " "); for (i = 1; i <= n; i++) R[mset[i]] = i; k = split(known, kn, " "); for (i = 1; i <= k; i++) KN[kn[i]] = 1; T = jdn(today) }
    $1 == "C" && $2 != "" { CL[$2] = 1; next }
    $1 == "K" { KM[$2] = $3; KR[$2] = $4; next }
    $1 == "E" { id = $2; cl = $3; mo = $4; md = $5; ct = $6; sn = $7; pb = $8; ck = $9; lw = $10; HAS[cl] = 1
      if (only == "") {
        if (!(cl in CL)) print "enforcement-clause\t" id ": clause " cl " is no row of clauses.tsv"
        if (!(mo in R) || !(mo in KN)) print "enforcement-moment\t" id ": moment " mo " is not in the closed set (" moments ")"
        if (mo == "judgment") { if (ct != "-" || md != "-") print "enforcement-judgment\t" id ": a judgment pair names no control and no mode" }
        else {
          if (md !~ /^(shadow|warn|block)$/) print "enforcement-mode\t" id ": mode " md " is none of shadow, warn, block"
          if (!(ct in KM)) print "enforcement-control\t" id ": control " ct " is no row of controls.tsv"
          else if (KM[ct] != md && !(KM[ct] ~ /^(advisory|inform)$/ && md == "warn")) print "enforcement-mode-drift\t" id ": mode " md " and controls.tsv says " KM[ct] " for " ct ": promotion edits both cells" }
        if (ck in R && mo in R && R[mo] > R[ck] && lw == "-") print "enforcement-late\t" id ": binds at " mo " and is checkable at " ck "; say why it is later (later_why)" }
      if (md == "block") {
        if (pb == "" || pb == "-") print "promotion-unowned\t" id ": a block pair names no one who promoted it (promoted_by: a person, or grandfathered)"
        else if (pb != "grandfathered") {
          if (!(ct in KR) || KR[ct] == "-" || KR[ct] == "") print "promotion-no-red-proof\t" id ": promoted to block with no red proof on " ct " (red_proof names the suite that watched it go red)"
          j = jdn(sn); if (j < 0) print "promotion-no-date\t" id ": promoted to block and since is not a date"
          else if (T - j < 28) print "promotion-too-early\t" id ": in block " (T - j) " day(s); the rule is 28 days in a lower mode after it went red" } } }
    END { if (only == "") for (c in CL) if (!(c in HAS)) print "enforcement-missing\tclause " c " has no row in enforcement.tsv" }' \
  | sort | while IFS="$TAB" read -r _k _m2; do finding "$_k" "$_m2"; done
  printf 'policy-check: enforcement: %d pair(s) over %d clause(s)\n' "$(col "$ENFORCEMENT" id | grep -c .)" "$(col "$CLAUSES" id | grep -c .)"
}

gen_enforcement() {
  need "$ENFORCEMENT" "$CLAUSES" "$CONTROLS"
  { rows "$CLAUSES" | awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) H[$i] = i; next } { print "C\t" $H["id"] "\t" $H["strength"] }'
    rows "$CONTROLS" | awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) H[$i] = i; next } { print "K\t" $H["id"] "\t" $H["red_proof"] }'
    rows "$ENFORCEMENT" | awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) H[$i] = i; next } { print "E\t" $H["clause"] "\t" $H["moment"] "\t" $H["mode"] "\t" $H["control"] }'; } \
  | awk -F'\t' -v moments="$MOMENTS" '
    BEGIN { n = split(moments, mo, " ") }
    $1 == "C" { order[++nc] = $2; ST[$2] = $3; next }
    $1 == "K" { RP[$2] = $3; next }
    $1 == "E" { cell = $4; if ($3 == "judgment") cell = "judgment"
      key = $2 SUBSEP $3; if (index(" " X[key] " ", " " cell " ") == 0) X[key] = (X[key] == "" ? cell : X[key] " " cell)
      MC[$3 SUBSEP $4]++; cl = $2
      if ($3 != "judgment") { CTRL[cl]++; if (RP[$5] == "-" || RP[$5] == "") NR_[cl SUBSEP $5] = $3 }
      if ($3 == "judgment") J[cl] = 1 }
    END {
      print "---\nkind: generated-doc\nowner: harbor#1028\nstatus: generated\nsource: sh bin/policy-check.sh --gen enforcement\n---"
      print "<!-- generated-by: sh bin/policy-check.sh --gen enforcement -->"
      print "# Enforcement matrix — generated, do not edit\n"
      print "Which moment each clause binds at, and in which mode (policy/enforcement.tsv x policy/clauses.tsv). `judgment` is a moment: counted, never hidden. Regenerate with `sh bin/policy-check.sh --gen enforcement`; `--check` fails on a hand edit.\n"
      print "## Pairs per moment and mode\n"
      printf "| moment | shadow | warn | block |\n|---|---|---|---|\n"
      for (i = 1; i <= n; i++) { if (mo[i] == "judgment") continue; printf "| %s | %d | %d | %d |\n", mo[i], MC[mo[i] SUBSEP "shadow"] + 0, MC[mo[i] SUBSEP "warn"] + 0, MC[mo[i] SUBSEP "block"] + 0 }
      print "\n## Judgment share per strength\n"
      printf "| strength | clauses | judgment only | share |\n|---|---|---|---|\n"
      for (c = 1; c <= nc; c++) { s = ST[order[c]]; T[s]++; if (!(order[c] in CTRL)) JO[s]++ }
      m = 0; for (s in T) SS[++m] = s
      for (a = 1; a <= m; a++) for (b = a + 1; b <= m; b++) if (SS[b] < SS[a]) { t = SS[a]; SS[a] = SS[b]; SS[b] = t }
      for (a = 1; a <= m; a++) printf "| %s | %d | %d | %d%% |\n", SS[a], T[SS[a]], JO[SS[a]] + 0, int(100 * (JO[SS[a]] + 0) / T[SS[a]])
      print "\n## Clause x moment\n"
      printf "| clause | strength"; for (i = 1; i <= n; i++) printf " | %s", mo[i]; print " |"
      printf "|---|---"; for (i = 1; i <= n; i++) printf "|---"; print "|"
      for (c = 1; c <= nc; c++) { id = order[c]; printf "| %s | %s", id, ST[id]
        for (i = 1; i <= n; i++) { v = X[id SUBSEP mo[i]]; printf " | %s", (v == "" ? "" : v) }
        print " |" }
      print "\n## Pairs never seen red\n"
      print "A pair whose control has no red proof (controls.tsv red_proof is `-`): it cannot be promoted, and a person may retire it. Proposed here, never edited.\n"
      cnt = 0; for (k in NR_) { split(k, p, SUBSEP); L[++cnt] = p[1] " / " p[2] " (" NR_[k] ")" }
      for (a = 1; a <= cnt; a++) for (b = a + 1; b <= cnt; b++) if (L[b] < L[a]) { t = L[a]; L[a] = L[b]; L[b] = t }
      if (cnt == 0) print "None."; else for (a = 1; a <= cnt; a++) print "- " L[a] }'
}

do_gen() {
  case "$ARG" in
    enforcement) _out="$ROOT/docs/policy/enforcement.md" ;;
    *) lg_fail '--gen takes enforcement'; exit 2 ;;
  esac
  _g="$(mktemp "${TMPDIR:-/tmp}/pc.XXXXXX")"; gen_enforcement > "$_g"
  if [ "$GENCHECK" = 1 ]; then
    if [ -f "$_out" ] && cmp -s "$_g" "$_out"; then printf 'policy-check: %s is current\n' "${_out#"$ROOT"/}"
    else finding gen-stale "${_out#"$ROOT"/} is stale or hand-edited: run sh bin/policy-check.sh --gen $ARG"; fi
  else mkdir -p "$(dirname "$_out")"; cp "$_g" "$_out"; printf 'policy-check: wrote %s\n' "${_out#"$ROOT"/}"; fi
  rm -f "$_g"
}

# the batch report: pairs not earning their keep, as a proposal to a person (it never edits a mode)
do_report() {
  need "$ENFORCEMENT" "$CONTROLS"
  rows "$ENFORCEMENT" | awk -F'\t' -v ctl="$CONTROLS" '
    BEGIN { while ((getline l < ctl) > 0) { if (l ~ /^#/) continue; split(l, c, "\t"); if (c[1] == "id") continue; RP[c[1]] = c[11] } }
    NR == 1 { for (i = 1; i <= NF; i++) H[$i] = i; next }
    $H["control"] != "-" && (RP[$H["control"]] == "-" || RP[$H["control"]] == "") { printf "%s\t%s\t%s\n", $H["id"], $H["mode"], $H["moment"] }' \
  | sort | while IFS="$TAB" read -r _i _md _mo; do printf '  PROPOSE: [policy.enforcement-report] %s (%s at %s) was never seen red: prove it red or retire it with a successor\n' "$_i" "$_md" "$_mo"; done
  printf 'policy-check: report: a proposal to the person who reads checks.log; no mode was edited\n'
}

# every fixture under fixtures/policy/ names its arguments and the finding it must raise (or none): each arm red once, the pass arm green
do_selftest() {
  _fx="$ROOT/fixtures/policy"; _n=0; _f=0
  [ -d "$_fx" ] || { lg_fail 'no fixtures at fixtures/policy, so nothing was judged'; exit 3; }
  for _d in "$_fx"/*/; do
    [ -f "${_d}case" ] || continue
    IFS="$TAB" read -r _args _want < "${_d}case"; _n=$((_n+1)); _rc=0
    # shellcheck disable=SC2086 # _args is a word list by construction
    _out="$(cd "$_d" && sh "$HERE/policy-check.sh" --root "$_d" $_args 2>&1)" || _rc=$?
    if [ "$_want" = none ]; then
      [ "$_rc" -eq 0 ] || { _f=$((_f+1)); log_fail "${_d%/} should pass and exited $_rc"; log_nofix "harbor#1026"; }
    elif [ "$_rc" -ne 1 ] || ! printf '%s' "$_out" | grep -q "\[policy\.$_want\]"; then
      _f=$((_f+1)); log_fail "${_d%/} should raise policy.$_want (exit $_rc)"; log_nofix "harbor#1026"
    fi
  done
  printf 'policy-check: self-test: %d fixture(s), %d failed\n' "$_n" "$_f"
  [ "$_f" -eq 0 ] || exit 1
}

QUIET=0
case "$MODE" in
  census) do_census ;;
  deployed) do_deployed ;;
  shape) do_shape ;;
  trace) do_trace ;;
  trace-up) do_trace_up ;;
  motivation) do_motivation ;;
  why) do_why ;;
  notes) do_notes ;;
  amends) do_amends ;;
  ask) do_ask ;;
  enforcement) ONLY=''; do_enforcement ;;
  promotion) ONLY=promotion; do_enforcement ;;
  gen) do_gen ;;
  report) do_report ;;
  check) QUIET=1; do_census; do_shape; do_trace ;;
  self-test) do_selftest ;;
  *) lg_fail '--%s is not built yet' "$MODE"; exit 2 ;;
esac
log_end || :
[ ! -s "$FOUNDF" ] || exit 1
exit 0
