#!/usr/bin/env sh
# standard-fleet-names.sh (harbor#967, harbor#957) — the weekly naming check over the whole fleet: check id standard.fleet-names.
#
#   sh bin/standard-fleet-names.sh [--registry FILE] [--gh PATH] [--config-dir DIR] [--today YYYY-MM-DD]
#
# For every repo `scope-roots.sh --repos` lists (or FILE: name TAB checkout path) it runs, read only:
#   names    bin/lint-name.sh over the repo's tracked names, against this checkout's registry (rules name.*)
#   vendor   bin/standard-vendor.sh --check <repo>, for a repo that vendors the package (one that does not is not judged)
#   release  bin/ci-release-names.sh once over the same repos: the release tag, the release title, the Keep a Changelog heading
# `gh` is used by the release part alone, and only for `release list` and a file read.
#
# THE REPORT IS THE DELTA AND THE AGES, NEVER THE CENSUS. A finding is a stable subject line (rule, repo, name). The previous
# run's subjects are kept in <config>/cache/standard-fleet-names.tsv with the day each was first seen; the report prints what is
# new, what is fixed, and one line for what stands (count, oldest age). A repo or part that could not be judged keeps its
# earlier subjects as standing: not seen is never fixed (contracts/finding.md).
#
# WHERE FINDINGS GO. The check tier of the existing findings channel: one receipt, <config>/cache/checks/standard.fleet-names.json
# (log-lib's log_receipt, fresh for 9 days because the check is weekly), which the daily `lint.findings` reconcile files as the issue
# `check/standard.fleet-names` on harbor and closes as fixed when a fresh receipt is green. A run that changed something also
# appends one [check:standard.fleet-names] line to <config>/cache/checks.log.
#
# Exit 0 nothing new (clean, or only findings already standing) · 1 at least one new finding · 2 usage ·
# 3 unchecked: no repo could be judged, so no receipt claims green.
# Writes only under <config>/cache. --config-dir defaults to $CLAUDE_CONFIG_DIR, else ~/.claude.
set -u
LC_ALL=C; export LC_ALL

case "$0" in */*) _SRC="${0%/*}" ;; *) _SRC=. ;; esac
ROOT="${HARBOR_SCOPE_ROOT:-${HARBOR_ROOT:-$(CDPATH= cd -- "$_SRC/.." && pwd)}}"
LOG_FD=2
. "$ROOT/bin/library-log.sh"
log_init standard-fleet-names
ID="standard.fleet-names"
REG=""; GH=""; CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; TODAY=""

usage_err() { log_fail "$1"; log_fix "sh bin/standard-fleet-names.sh --help"; log_end || :; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --registry) [ $# -ge 2 ] || usage_err "--registry takes a file"; REG="$2"; shift 2 ;;
    --gh) [ $# -ge 2 ] || usage_err "--gh takes a path"; GH="$2"; shift 2 ;;
    --config-dir) [ $# -ge 2 ] || usage_err "--config-dir takes a directory"; CFG="$2"; shift 2 ;;
    --today) [ $# -ge 2 ] || usage_err "--today takes YYYY-MM-DD"; TODAY="$2"; shift 2 ;;
    -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); print; next } {exit}' "$0"; exit 0 ;;
    *) usage_err "unknown argument: $1" ;;
  esac
done
[ -n "$TODAY" ] || TODAY="$(date -u +%Y-%m-%d)"
case "$TODAY" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) usage_err "--today takes YYYY-MM-DD, not: $TODAY" ;; esac

T="$(mktemp -d "${TMPDIR:-/tmp}/standard-fleet-names.XXXXXX")" || usage_err "cannot make a temp dir"
trap 'rm -rf "$T"' EXIT INT TERM HUP
TAB="$(printf '\t')"
CACHE="$CFG/cache"; STATE="$CACHE/standard-fleet-names.tsv"; CHECKS_LOG="$CACHE/checks.log"

# ── the repos ────────────────────────────────────────────────────────────────
if [ -n "$REG" ]; then
  [ -r "$REG" ] || usage_err "registry not readable: $REG"
  cp "$REG" "$T/reg"
else
  sh "$ROOT/bin/scope-roots.sh" --repos > "$T/reg" 2>/dev/null || : > "$T/reg"
fi
grep -v '^#' "$T/reg" | awk -F'\t' 'NF >= 2 && $1 != ""' > "$T/repos"
if [ ! -s "$T/repos" ]; then
  log_fail "[check:$ID] no repo registry: nothing was read, so nothing is judged"; log_fix "sh bin/scope-roots.sh --repos"
  log_end || :; exit 3
fi

# → $T/cur: `unit TAB subject` per current finding; $T/unjudged: units that could not be read, one per line
: > "$T/cur"; : > "$T/unjudged"; : > "$T/notes"; JUDGED=0; NREPO=0; NOVENDOR=0
while IFS="$TAB" read -r _name _path; do
  NREPO=$((NREPO + 1))
  case "$_path" in "~/"*) _path="$HOME/${_path#\~/}" ;; esac
  if [ ! -d "$_path" ]; then
    printf 'names@%s\nvendor@%s\n' "$_name" "$_name" >> "$T/unjudged"
    printf '%s: no checkout at its registry path\n' "$_name" >> "$T/notes"; continue
  fi

  # names: only records whose subject is a tracked path of this repo (the registry's own rows are harbor's, not the repo's)
  if git -C "$_path" ls-files > "$T/tracked" 2>/dev/null && [ -s "$T/tracked" ]; then
    sh "$ROOT/bin/lint-name.sh" --root "$_path" --registry "$ROOT/standards/naming" --format findings > "$T/ln.out" 2> "$T/ln.err" < /dev/null
    _rc=$?
    if [ "$_rc" -ge 2 ]; then
      printf 'names@%s\n' "$_name" >> "$T/unjudged"; printf '%s: lint-name.sh exited %s\n' "$_name" "$_rc" >> "$T/notes"
    else
      awk -F'\t' -v repo="$_name" -v OFS='\t' 'FILENAME == ARGV[1] { t[$0] = 1; next }
        ($1 == "A" || $1 == "V") && ($3 in t) { print "names@" repo, $2 " " repo ": " $3 }' "$T/tracked" "$T/ln.out" >> "$T/cur"
      JUDGED=$((JUDGED + 1))
    fi
  else
    printf 'names@%s\n' "$_name" >> "$T/unjudged"; printf '%s: not a git checkout with tracked files\n' "$_name" >> "$T/notes"
  fi

  # vendor: a repo that does not vendor the package is not judged (exit 3 of --check)
  sh "$ROOT/bin/standard-vendor.sh" --check --source "$ROOT" "$_path" > /dev/null 2> "$T/sv.err" < /dev/null
  _rc=$?
  case "$_rc" in
    0) ;;
    1) sed -n 's/^  FAIL: //p' "$T/sv.err" | sed -e 's/^standard_version: pinned .*/standard_version is behind harbor/' \
         | awk -v repo="$_name" -v OFS='\t' '{ print "vendor@" repo, "standard.vendor " repo ": " $0 }' >> "$T/cur" ;;
    3) NOVENDOR=$((NOVENDOR + 1)) ;;
    *) printf 'vendor@%s\n' "$_name" >> "$T/unjudged"; printf '%s: standard-vendor.sh exited %s\n' "$_name" "$_rc" >> "$T/notes" ;;
  esac
done < "$T/repos"

# release: one call over the whole fleet
set -- --registry "$T/reg"; [ -z "$GH" ] || set -- "$@" --gh "$GH"
sh "$ROOT/bin/ci-release-names.sh" "$@" > "$T/rn.out" 2>&1 < /dev/null
_rc=$?
if [ "$_rc" -eq 3 ] || [ "$_rc" -eq 2 ]; then
  printf 'release\n' >> "$T/unjudged"; printf 'release names: ci-release-names.sh exited %s\n' "$_rc" >> "$T/notes"
else
  JUDGED=$((JUDGED + 1))
  sed -n -e 's/^  WARN: //p' -e 's/^  FAIL: //p' "$T/rn.out" \
    | sed -E 's/: [0-9]+ release\(s\) and no CHANGELOG/: release(s) and no CHANGELOG/' \
    | awk -v OFS='\t' '{ print "release", "ci.release-names " $0 }' >> "$T/cur"
fi

if [ "$JUDGED" -eq 0 ]; then
  log_fail "[check:$ID] none of the $NREPO repos could be judged, so no result is claimed"; log_fix "the notes below name each repo and why"
  while IFS= read -r _n; do log_note "$_n"; done < "$T/notes"
  log_receipt "$(receipt_dir "$CFG")" "$ID" stood-down >/dev/null 2>&1 || :
  log_end || :; exit 3
fi

# ── the delta against the last run ───────────────────────────────────────────
# state: first_seen TAB unit TAB subject. A unit that could not be read keeps its earlier rows, standing.
mkdir -p "$CACHE" 2>/dev/null || :
[ -f "$STATE" ] || : > "$STATE"
if [ -s "$T/unjudged" ]; then
  awk -F'\t' 'FILENAME == ARGV[1] { u[$1] = 1; next } ($2 in u) { print $2 "\t" $3 }' "$T/unjudged" "$STATE" >> "$T/cur"
fi
LC_ALL=C sort -u "$T/cur" -o "$T/cur"
# next = the current subjects with the day each was first seen
awk -F'\t' -v today="$TODAY" -v OFS='\t' 'FILENAME == ARGV[1] { old[$3] = $1; next }
  { print (($2 in old) ? old[$2] : today), $1, $2 }' "$STATE" "$T/cur" > "$T/next"
awk -F'\t' 'FILENAME == ARGV[1] { cur[$2] = 1; next } !($3 in cur) { print $3 }' "$T/cur" "$STATE" | LC_ALL=C sort > "$T/fixed"
awk -F'\t' 'FILENAME == ARGV[1] { s[$3] = 1; next } !($3 in s) { print $3 }' "$STATE" "$T/next" | LC_ALL=C sort > "$T/new"
NNEW="$(grep -c . "$T/new" | tr -d ' ')"; NFIX="$(grep -c . "$T/fixed" | tr -d ' ')"
NCUR="$(grep -c . "$T/next" | tr -d ' ')"; NSTAND=$((NCUR - NNEW))

_days() { awk -v a="$1" -v b="$2" 'function jd(s,  y, m, d) { y = substr(s,1,4)+0; m = substr(s,6,2)+0; d = substr(s,9,2)+0
    if (m <= 2) { y--; m += 12 } return int(365.25*y) + int(30.6001*(m+1)) + d }
  BEGIN { print jd(b) - jd(a) }'; }

# ── write the state and the receipt ──────────────────────────────────────────
mkdir -p "$CACHE" 2>/dev/null || :
_tmp="$(mktemp "$CACHE/.standard-fleet-names.XXXXXX" 2>/dev/null)" || _tmp=""
if [ -n "$_tmp" ] && cp "$T/next" "$_tmp" && mv -f "$_tmp" "$STATE"; then :; else
  [ -z "$_tmp" ] || rm -f "$_tmp"; log_warn "the state could not be written at $STATE, so the next run will report this one's findings as new again"
fi
if [ "$NCUR" -eq 0 ]; then _st=green; else _st=red; fi
set --; while IFS="$TAB" read -r _fs _u _s; do set -- "$@" "$_s"; done < "$T/next"
LOG_RECEIPT_FRESH_DAYS=9 log_receipt "$(receipt_dir "$CFG")" "$ID" "$_st" "$@" \
  || log_warn "no receipt could be written under $(receipt_dir "$CFG"), so the findings channel does not see this run"

# ── the report: delta and ages ───────────────────────────────────────────────
printf '[check:%s] %s: %s repo(s) read, %s finding(s): %s new, %s fixed, %s standing\n' \
  "$ID" "$TODAY" "$NREPO" "$NCUR" "$NNEW" "$NFIX" "$NSTAND"
CAP=20
_show() { # <label> <file>
  [ -s "$2" ] || return 0
  _h="$1"; _i=0
  while IFS= read -r _x; do
    _i=$((_i + 1)); [ "$_i" -le "$CAP" ] || break
    printf '  %-8s %s\n' "$_h" "$_x"; _h=""
  done < "$2"
  _more=$(($(grep -c . "$2" | tr -d ' ') - CAP)); [ "$_more" -le 0 ] || printf '  %-8s ... and %s more\n' "" "$_more"
}
if [ "$NNEW" -eq 0 ] && [ "$NFIX" -eq 0 ]; then printf '  nothing new\n'; fi
_show "new" "$T/new"
_show "fixed" "$T/fixed"
if [ "$NSTAND" -gt 0 ]; then
  awk -F'\t' 'FILENAME == ARGV[1] { n[$1] = 1; next } !($3 in n) { print $1 "\t" $3 }' "$T/new" "$T/next" | LC_ALL=C sort | head -n 1 > "$T/oldest"
  printf '  standing %s finding(s) already filed, oldest %s day(s): %s\n' "$NSTAND" \
    "$(_days "$(cut -f1 "$T/oldest")" "$TODAY")" "$(cut -f2 "$T/oldest" | cut -c1-120)"
fi
[ ! -s "$T/unjudged" ] || printf '  not judged this run (their earlier findings stand): %s\n' "$(tr '\n' ' ' < "$T/unjudged")"
[ "$NOVENDOR" -eq 0 ] || printf '  %s of %s repo(s) do not vendor the naming package (not judged for it)\n' "$NOVENDOR" "$NREPO"
while IFS= read -r _n; do log_note "$_n"; done < "$T/notes"

# one line in checks.log for a run that changed something, as lint-findings-run.sh does: the delta, never the census
if [ "$NNEW" -gt 0 ] || [ "$NFIX" -gt 0 ]; then
  if [ ! -e "$CHECKS_LOG" ] || { [ -f "$CHECKS_LOG" ] && [ ! -L "$CHECKS_LOG" ] && [ "$(ls -ln "$CHECKS_LOG" | awk '{ print $2 }')" = 1 ]; }; then
    printf '[check:%s] %s %s new, %s fixed, %s standing\n' "$ID" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$NNEW" "$NFIX" "$NSTAND" >> "$CHECKS_LOG" 2>/dev/null || :
  fi
fi
log_end || :
[ "$NNEW" -eq 0 ] || exit 1
exit 0
