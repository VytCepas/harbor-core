#!/usr/bin/env sh
# drift-launchd-wall.sh (harbor#1442, #1440) — the check drift.launchd-wall: every installed com.harbor.* launchd job runs code
# from outside the confinement's write list. A job whose executable or script sits inside it runs, later and unconfined
# as the operator, whatever a confined command or the Edit tool wrote there: a persistence route out of the wall.
#   sh drift-launchd-wall.sh            exit 0 every job clear, 1 a job runs code from the write list, 3 unchecked (D-29, never a green)
#   sh drift-launchd-wall.sh --state    the same, plus one word on stdout: match | drift | unchecked | not-applicable, and no receipt
# Reads each job's Program and ProgramArguments (`plutil -extract ProgramArguments json -o - <plist>`), the write list from
# `deploy-confinement.sh --compose` (core, then the private layer), and exemption rows from contracts/launchd-wall-exempt.tsv.
# Read-only. The fix for a red job is to install a copy of its script under ~/.claude/bin (write-denied), as the hooks and the
# other jobs do, and point the plist at it: the operator's `launchctl` step, never a session's.
# platform: macOS-only — reads launchd plists with plutil; a host without plutil stands down as not-applicable (Linux has no launchd).
# HARBOR_DRIFT_LAUNCHD_DIR moves the plist folder (default ~/Library/LaunchAgents), for tests.
# Every finding line carries [check:drift.launchd-wall]; the receipt goes to log_receipt's dir (docs/reference/checks.md).
set -u
case "${1:-}" in -h|--help) awk 'NR<2{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;; esac
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
. "$HERE/library-log.sh"
log_init drift-launchd-wall
STATE=0
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
case "${1:-}" in
  --state) STATE=1; LOG_FD=2 ;;
  '') ;;
  *) log_fail "unknown argument $1"; log_fix "sh $0 --help"; exit 2 ;;
esac
ID=drift.launchd-wall; P="[check:$ID]"
CORE="$HERE/../contracts"
DIR="${HARBOR_DRIFT_LAUNCHD_DIR:-$HOME/Library/LaunchAgents}"
finish() { # <receipt status> <state word> <exit> [subject...]
  _fs="$1"; _fw="$2"; _fx="$3"; shift 3
  [ "$STATE" = 1 ] || log_receipt "$(receipt_dir)" "$ID" "$_fs" "$@" || log_warn "$P no receipt written to $(receipt_dir)"
  [ "$STATE" = 0 ] || printf '%s\n' "$_fw"
  log_end || :
  exit "$_fx"
}
unchecked() { log_warn "$P unchecked: $1"; log_fix "$2"; finish stood-down unchecked 3; }

command -v plutil >/dev/null 2>&1 || { log_skip "$P not applicable: no plutil, so no launchd on this host"; finish stood-down not-applicable 0; }
[ -d "$DIR" ] || { log_skip "$P not applicable: no $DIR"; finish stood-down not-applicable 0; }
command -v jq >/dev/null 2>&1 || unchecked "jq is required to read the plists" "$(pkg_hint jq)"

# The write list, as the confinement composes it; ~ expanded. An unreadable compose judges nothing.
ERR="$(mktemp "${TMPDIR:-/tmp}/drift-launchd-wall.XXXXXX")" || unchecked "mktemp under ${TMPDIR:-/tmp} failed" "set TMPDIR to a writable dir"
ZONE="$(sh "$HERE/deploy-confinement.sh" --compose 2>"$ERR" | jq -r '.filesystem.allowWrite[]' 2>/dev/null)"; _rc=$?
_e="$(grep 'FAIL' "$ERR" | head -1)"; rm -f "$ERR"
[ "$_rc" = 0 ] && [ -n "$ZONE" ] || unchecked "the write list did not compose${_e:+ ($_e)}" "sh $HERE/deploy-confinement.sh --compose"
ZONE="$(printf '%s\n' "$ZONE" | sed "s|^~/|$HOME/|")"

# Exemption rows: <label> TAB <path prefix> TAB <reason>. A row without a reason judges nothing (a row that explains
# nothing is how an exemption outlives its cause).
EX="$(mktemp "${TMPDIR:-/tmp}/drift-launchd-wall.XXXXXX")" || unchecked "mktemp under ${TMPDIR:-/tmp} failed" "set TMPDIR to a writable dir"
_priv="$(sh "$HERE/scope-roots.sh" --private 2>/dev/null || :)"
for _f in "$CORE/launchd-wall-exempt.tsv" ${_priv:+"$_priv/launchd-wall-exempt.tsv"}; do
  [ -f "$_f" ] && sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$_f" >> "$EX"
done
_badx="$(awk -F'\t' 'NF < 3 || $1 == "" || $2 == "" || $3 == "" { print NR ": " $0 }' "$EX" | head -1)"
[ -z "$_badx" ] || { rm -f "$EX"; unchecked "an exemption row lacks its label, path or reason ($_badx)" "edit contracts/launchd-wall-exempt.tsv (format: its own header)"; }

# physical <path> -> the path with its directory (and a symlinked file) resolved, when it exists
physical() {
  _pp="$1"
  if [ -L "$_pp" ]; then
    _lt="$(readlink "$_pp")"; case "$_lt" in /*) _pp="$_lt" ;; *) _pp="$(dirname -- "$_pp")/$_lt" ;; esac
  fi
  _pd="$(CDPATH= cd -P -- "$(dirname -- "$_pp")" 2>/dev/null && pwd)" && printf '%s/%s\n' "$_pd" "$(basename -- "$_pp")" || printf '%s\n' "$_pp"
}
# in_zone <path> -> 0 and the zone row when the path is a write-list row or below one
in_zone() {
  _iz=0
  while IFS= read -r _z; do
    [ -n "$_z" ] || continue
    case "$1" in "$_z"|"$_z"/*) _izr="$_z"; _iz=1; break ;; esac
  done <<EOF
$ZONE
EOF
  [ "$_iz" = 1 ] && printf '%s\n' "$_izr"
}
# exempt <label> <path> -> 0 and the reason when a row covers the job and the path
exempt() { awk -F'\t' -v l="$1" -v p="$2" '$1 == l && (p == $2 || index(p, $2 "/") == 1) { print $3; f = 1; exit } END { exit !f }' "$EX"; }

N=0; SUBJ=""; JOBS=0; EXEMPT=0
for _plist in $(find "$DIR" -maxdepth 1 -name 'com.harbor.*.plist' | sort); do
  _label="$(basename "$_plist" .plist)"; JOBS=$((JOBS + 1))
  _args="$(plutil -extract ProgramArguments json -o - "$_plist" 2>/dev/null | jq -r '.[]' 2>/dev/null)" || _args=""
  _prog="$(plutil -extract Program raw -o - "$_plist" 2>/dev/null || :)"
  _wd="$(plutil -extract WorkingDirectory raw -o - "$_plist" 2>/dev/null || :)"
  [ -n "$_args$_prog" ] || { log_note "$P $_label: no Program or ProgramArguments to read"; continue; }
  while IFS= read -r _a; do
    [ -n "$_a" ] || continue
    case "$_a" in
      /*) _c="$_a" ;;
      '~/'*) _c="$HOME/${_a#'~/'}" ;;
      # a relative script runs from the working directory
      *.py|*.ts|*.js|*.mjs|*.sh|*.rb|*.pl) [ -n "$_wd" ] && _c="$_wd/$_a" || continue ;;
      *) continue ;;
    esac
    _hit=""
    for _cand in "$_c" "$(physical "$_c")"; do
      _zr="$(in_zone "$_cand")" && { _hit="$_cand"; break; }
    done
    [ -n "$_hit" ] || continue
    if _why="$(exempt "$_label" "$_hit")"; then
      EXEMPT=$((EXEMPT + 1)); log_note "$P $_label: $_hit is inside the write list ($_zr), exempt: $_why"; continue
    fi
    N=$((N + 1)); SUBJ="$SUBJ
$_label:$_hit"
    log_note "$P $_label runs $_hit, inside the write list ($_zr): anything written there runs later, unconfined, as the operator"
  done <<EOF
$_prog
$_args
EOF
  if [ -n "$_wd" ]; then
    _zr="$(in_zone "$_wd")" && log_note "$P $_label: working directory $_wd is inside the write list ($_zr); not a finding, but an interpreter reads project files from it"
  fi
done
rm -f "$EX"

if [ "$JOBS" = 0 ]; then log_skip "$P no com.harbor.* job in $DIR"; finish stood-down not-applicable 0; fi
if [ "$N" = 0 ]; then
  log_ok "$P $JOBS com.harbor.* job(s): none runs code from the write list ($EXEMPT exempt)"
  finish green match 0
fi
log_fail "$P $N path(s) in $JOBS com.harbor.* job(s) run from the write list, listed above"
log_fix "install a copy of each script outside the write list (as ~/.claude/bin is), point the job's plist at it, reload it with launchctl; or add a row with a reason to contracts/launchd-wall-exempt.tsv"
set -f; IFS='
'
# shellcheck disable=SC2086
finish red drift 1 $SUBJ
