#!/usr/bin/env sh
# standard-seams-fresh.sh (harbor#1425) — the weekly seam freshness check: check id standard.seam-fresh.
#
#   sh bin/standard-seams-fresh.sh [--register FILE] [--root SYSTEM=DIR]... [--fleet DIR] [--ref REF] [--checker CMD]
#                                  [--config-dir DIR] [--today YYYY-MM-DD]
#
# Every row of contracts/seams.tsv that names check.seam-fresh has its copy compared with its producer's checkout (a vendored tree
# by file hash, a vendored schema by what constrains data), and a copy that no row names is a finding. The comparison is fleet's
# projects_orchestrator.seams, run read only over local checkouts: it generalises fleet's contract-freshness, which compared one
# contract with the network. --root defaults to this checkout (harbor) and the scope-roots checkouts for yard and fleet.
#
# THE REPORT IS THE DELTA AND THE AGES, NEVER THE CENSUS (contracts/finding.md). The last run's subjects are kept in
# <config>/cache/standard-seams-fresh.tsv with the day each was first seen; the report prints what is new, what is fixed and one line
# for what stands. A run that could not read a checkout keeps the earlier findings, never fixed.
#
# WHERE FINDINGS GO: a TICKET, never a red PR. One receipt, <config>/cache/checks/standard.seam-fresh.json (fresh 9 days), which the
# daily `lint.findings` reconcile files as the issue `check/standard.seam-fresh` on harbor and closes as fixed when a fresh receipt is
# green. Upstream moving is a reason to re-vendor on purpose, not to block a consumer's PR.
#
# Exit 0 nothing new · 1 at least one new finding · 2 usage · 3 unchecked: nothing could be judged, so no receipt claims green.
set -u
LC_ALL=C; export LC_ALL

case "$0" in */*) _SRC="${0%/*}" ;; *) _SRC=. ;; esac
ROOT="${HARBOR_SCOPE_ROOT:-$(CDPATH= cd -- "$_SRC/.." && pwd)}"
LOG_FD=2
. "$ROOT/bin/library-log.sh"
log_init standard-seams-fresh
ID="standard.seam-fresh"
REG=""; FLEET=""; REF=""; CHECKER=""; CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; TODAY=""; ROOTS=""
TAB="$(printf '\t')"

usage_err() { log_fail "$1"; log_fix "sh bin/standard-seams-fresh.sh --help"; log_end || :; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --register) [ $# -ge 2 ] || usage_err "--register takes a file"; REG="$2"; shift 2 ;;
    --root) [ $# -ge 2 ] || usage_err "--root takes SYSTEM=DIR"; ROOTS="$ROOTS $2"; shift 2 ;;
    --fleet) [ $# -ge 2 ] || usage_err "--fleet takes a directory"; FLEET="$2"; shift 2 ;;
    --ref) [ $# -ge 2 ] || usage_err "--ref takes a ref"; REF="$2"; shift 2 ;;
    --checker) [ $# -ge 2 ] || usage_err "--checker takes a command"; CHECKER="$2"; shift 2 ;;
    --config-dir) [ $# -ge 2 ] || usage_err "--config-dir takes a directory"; CFG="$2"; shift 2 ;;
    --today) [ $# -ge 2 ] || usage_err "--today takes YYYY-MM-DD"; TODAY="$2"; shift 2 ;;
    -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); print; next } {exit}' "$0"; exit 0 ;;
    *) usage_err "unknown argument: $1" ;;
  esac
done
[ -n "$TODAY" ] || TODAY="$(date -u +%Y-%m-%d)"
case "$TODAY" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) usage_err "--today takes YYYY-MM-DD, not: $TODAY" ;; esac
[ -n "$REG" ] || REG="$ROOT/contracts/seams.tsv"
[ -r "$REG" ] || usage_err "no seams register at $REG"

T="$(mktemp -d "${TMPDIR:-/tmp}/standard-seams-fresh.XXXXXX")" || usage_err "cannot make a temp dir"
trap 'rm -rf "$T"' EXIT INT TERM HUP
CACHE="$CFG/cache"; STATE="$CACHE/standard-seams-fresh.tsv"; CHECKS_LOG="$CACHE/checks.log"

# ── the checkouts: this one is harbor; yard and fleet come from the one reader of where repos live ──
case " $ROOTS " in *" harbor="*) ;; *) ROOTS="$ROOTS harbor=$ROOT" ;; esac
_get() { env -u HARBOR_SCOPE_ROOT sh "$ROOT/bin/scope-roots.sh" --get "$1" 2>/dev/null || :; }
case " $ROOTS " in *" yard="*) ;; *) _y="$(_get HARBOR_SCOPE_SCAFFOLDER)"; [ -z "$_y" ] || ROOTS="$ROOTS yard=$_y" ;; esac
case " $ROOTS " in *" fleet="*) ;; *) _f="$(_get HARBOR_SCOPE_FLEET_CONTROLLER)"; [ -z "$_f" ] || ROOTS="$ROOTS fleet=$_f" ;; esac
[ -n "$FLEET" ] || for _r in $ROOTS; do [ "${_r%%=*}" = fleet ] && FLEET="${_r#*=}"; done

# ── the comparison ───────────────────────────────────────────────────────────
# → $T/found: `seam TAB kind TAB detail` per finding; exit 3 of the checker is "nothing could be judged"
if [ -n "$CHECKER" ]; then
  sh -c "$CHECKER" > "$T/found" 2> "$T/err" < /dev/null; _rc=$?
else
  [ -n "$FLEET" ] && [ -f "$FLEET/src/projects_orchestrator/seams.py" ] || {
    log_fail "[check:$ID] no fleet checkout with projects_orchestrator/seams.py: the comparison cannot run, so no result is claimed"
    log_fix "sh bin/standard-seams-fresh.sh --fleet <a projects-orchestrator checkout>"; log_end || :; exit 3; }
  set -- --no-scan harbor; for _r in $ROOTS; do set -- "$@" --root "$_r"; done
  [ -z "$REF" ] || set -- "$@" --ref "$REF"
  PYTHONPATH="$FLEET/src" python3 -m projects_orchestrator.seams --register "$REG" "$@" > "$T/found" 2> "$T/err" < /dev/null; _rc=$?
fi
if [ "$_rc" -ge 2 ]; then
  log_fail "[check:$ID] the comparison exited $_rc, so nothing is judged: $(head -n 1 "$T/err")"; log_fix "run it by hand: PYTHONPATH=<fleet>/src python3 -m projects_orchestrator.seams --register $REG --root harbor=$ROOT ..."
  log_receipt "$(receipt_dir "$CFG")" "$ID" stood-down >/dev/null 2>&1 || :
  log_end || :; exit 3
fi

# subject: stable across runs (a commit count in the detail would make every run's finding new)
awk -F'\t' -v OFS='\t' 'NF >= 3 && $2 != "unchecked" { print $1, "check.seam-fresh " $1 ": " $2 }' "$T/found" > "$T/cur"
awk -F'\t' '$2 == "unchecked" { print $1 ": " $3 }' "$T/found" > "$T/notes"
awk -F'\t' '$2 == "unchecked" { print "seam@" $1 }' "$T/found" > "$T/unjudged"
LC_ALL=C sort -u "$T/cur" -o "$T/cur"

# ── the delta against the last run ───────────────────────────────────────────
# state: first_seen TAB unit TAB subject. A seam that could not be read keeps its earlier rows, standing.
mkdir -p "$CACHE" 2>/dev/null || :
[ -f "$STATE" ] || : > "$STATE"
awk -F'\t' '{ print "seam@" $1 "\t" $2 }' "$T/cur" > "$T/cur.u"; mv "$T/cur.u" "$T/cur"
if [ -s "$T/unjudged" ]; then
  awk -F'\t' 'FILENAME == ARGV[1] { u[$1] = 1; next } ($2 in u) { print $2 "\t" $3 }' "$T/unjudged" "$STATE" >> "$T/cur"
fi
LC_ALL=C sort -u "$T/cur" -o "$T/cur"
awk -F'\t' -v today="$TODAY" -v OFS='\t' 'FILENAME == ARGV[1] { old[$3] = $1; next }
  { print (($2 in old) ? old[$2] : today), $1, $2 }' "$STATE" "$T/cur" > "$T/next"
awk -F'\t' 'FILENAME == ARGV[1] { cur[$2] = 1; next } !($3 in cur) { print $3 }' "$T/cur" "$STATE" | LC_ALL=C sort > "$T/fixed"
awk -F'\t' 'FILENAME == ARGV[1] { s[$3] = 1; next } !($3 in s) { print $3 }' "$STATE" "$T/next" | LC_ALL=C sort > "$T/new"
NNEW="$(grep -c . "$T/new" | tr -d ' ')"; NFIX="$(grep -c . "$T/fixed" | tr -d ' ')"
NCUR="$(grep -c . "$T/next" | tr -d ' ')"; NSTAND=$((NCUR - NNEW))
NSEAM="$(awk -F'\t' '!/^#/ && $1 != "id" && $8 == "check.seam-fresh"' "$REG" | grep -c . | tr -d ' ')"

_days() { awk -v a="$1" -v b="$2" 'function jd(s,  y, m, d) { y = substr(s,1,4)+0; m = substr(s,6,2)+0; d = substr(s,9,2)+0
    if (m <= 2) { y--; m += 12 } return int(365.25*y) + int(30.6001*(m+1)) + d }
  BEGIN { print jd(b) - jd(a) }'; }

# ── the state and the receipt ────────────────────────────────────────────────
_tmp="$(mktemp "$CACHE/.standard-seams-fresh.XXXXXX" 2>/dev/null)" || _tmp=""
if [ -n "$_tmp" ] && cp "$T/next" "$_tmp" && mv -f "$_tmp" "$STATE"; then :; else
  [ -z "$_tmp" ] || rm -f "$_tmp"; log_warn "the state could not be written at $STATE, so the next run will report this one's findings as new again"
fi
if [ "$NCUR" -eq 0 ]; then _st=green; else _st=red; fi
set --; while IFS="$TAB" read -r _fs _u _s; do set -- "$@" "$_s"; done < "$T/next"
LOG_RECEIPT_FRESH_DAYS=9 log_receipt "$(receipt_dir "$CFG")" "$ID" "$_st" "$@" \
  || log_warn "no receipt could be written under $(receipt_dir "$CFG"), so the findings channel does not see this run"

# ── the report: delta and ages ───────────────────────────────────────────────
printf '[check:%s] %s: %s seam(s) with a freshness check, %s finding(s): %s new, %s fixed, %s standing\n' \
  "$ID" "$TODAY" "$NSEAM" "$NCUR" "$NNEW" "$NFIX" "$NSTAND"
if [ "$NNEW" -eq 0 ] && [ "$NFIX" -eq 0 ]; then printf '  nothing new\n'; fi
# the detail of a new finding is on the line: the subject stays stable, the detail carries this run's counts
while IFS= read -r _x; do
  _seam="${_x#check.seam-fresh }"; _seam="${_seam%%:*}"
  printf '  new      %s\n' "$_x"; awk -F'\t' -v s="$_seam" '$1 == s { print "           " $3 }' "$T/found" | cut -c1-240
done < "$T/new"
while IFS= read -r _x; do printf '  fixed    %s\n' "$_x"; done < "$T/fixed"
if [ "$NSTAND" -gt 0 ]; then
  awk -F'\t' 'FILENAME == ARGV[1] { n[$1] = 1; next } !($3 in n) { print $1 "\t" $3 }' "$T/new" "$T/next" | LC_ALL=C sort | head -n 1 > "$T/oldest"
  printf '  standing %s finding(s) already filed, oldest %s day(s): %s\n' "$NSTAND" \
    "$(_days "$(cut -f1 "$T/oldest")" "$TODAY")" "$(cut -f2 "$T/oldest" | cut -c1-120)"
fi
[ ! -s "$T/notes" ] || while IFS= read -r _n; do log_note "not judged (earlier findings stand): $_n"; done < "$T/notes"

if [ "$NNEW" -gt 0 ] || [ "$NFIX" -gt 0 ]; then
  if [ ! -e "$CHECKS_LOG" ] || { [ -f "$CHECKS_LOG" ] && [ ! -L "$CHECKS_LOG" ] && [ "$(ls -ln "$CHECKS_LOG" | awk '{ print $2 }')" = 1 ]; }; then
    printf '[check:%s] %s %s new, %s fixed, %s standing\n' "$ID" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$NNEW" "$NFIX" "$NSTAND" >> "$CHECKS_LOG" 2>/dev/null || :
  fi
fi
log_end || :
[ "$NNEW" -eq 0 ] || exit 1
exit 0
