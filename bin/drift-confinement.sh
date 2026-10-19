#!/usr/bin/env sh
# drift-confinement.sh (harbor#1299, #555 P2) — the check drift.confinement: the installed `sandbox` block of the
# root-owned managed-settings.json against what deploy-confinement.sh --compose builds from core and private now.
# A moved PORT_ROOT, a new private host, a strict or credentials key flipped in harbor.toml, or a hand edit all read
# as drift. Lists compare as sets: the order of rows is not policy.
#   sh drift-confinement.sh            exit 0 matched or not installed, 1 drift, 3 unchecked (D-29, never a green)
#   sh drift-confinement.sh --state    the same, plus one word on stdout: match | drift | not-installed | unchecked,
#                                      and no receipt (floor-verify's read; a verifier writes nothing)
# Read-only: it never writes managed settings; the fix is the operator's `sudo sh deploy-confinement.sh`.
# Every finding line carries [check:drift.confinement]; the receipt goes to log_receipt's dir (CHECKS.md).
# HARBOR_MANAGED_SETTINGS moves the target, as in deploy-confinement.sh (tests, no root).
set -u
case "${1:-}" in -h|--help) awk 'NR<2{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;; esac
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
. "$HERE/log-lib.sh"
log_init drift-confinement
STATE=0
case "${1:-}" in
  --state) STATE=1; LOG_FD=2 ;;
  '') ;;
  *) log_fail "unknown argument $1"; log_fix "sh $0 --help"; exit 2 ;;
esac
ID=drift.confinement; P="[check:$ID]"
if [ -n "${HARBOR_MANAGED_SETTINGS:-}" ]; then MF="$HARBOR_MANAGED_SETTINGS"
elif [ "$(uname -s)" = Darwin ]; then MF='/Library/Application Support/ClaudeCode/managed-settings.json'
else MF=/etc/claude-code/managed-settings.json; fi
MK="$(dirname "$MF")/harbor-confinement"
FIX="sudo sh $HERE/deploy-confinement.sh"
# finish <receipt status> <state word> <exit> [subject...]
finish() {
  _fs="$1"; _fw="$2"; _fx="$3"; shift 3
  # --state is floor-verify's read, and a verifier writes nothing: only a direct run leaves the receipt.
  [ "$STATE" = 1 ] || log_receipt "$(receipt_dir)" "$ID" "$_fs" "$@" || log_warn "$P no receipt written to $(receipt_dir)"
  [ "$STATE" = 0 ] || printf '%s\n' "$_fw"
  log_end || :
  exit "$_fx"
}
unchecked() { log_warn "$P unchecked: $1"; log_fix "$2"; finish stood-down unchecked 3; }

command -v jq >/dev/null 2>&1 || unchecked "jq is required to read $MF" "$(pkg_hint jq)"
SB=0
if [ -f "$MF" ]; then
  jq -e . "$MF" >/dev/null 2>&1 || unchecked "$MF is unreadable or not JSON" "read it as the operator; $FIX rewrites it"
  ! jq -e 'has("sandbox")' "$MF" >/dev/null 2>&1 || SB=1
fi
MKP=0; [ ! -f "$MK" ] || MKP=1
if [ "$SB" = 0 ] && [ "$MKP" = 0 ]; then
  log_skip "$P not installed: no sandbox block in $MF and no marker beside it"
  finish stood-down not-installed 0
fi

ERR="$(mktemp "${TMPDIR:-/tmp}/drift-confinement.XXXXXX")" || unchecked "mktemp under ${TMPDIR:-/tmp} failed" "set TMPDIR to a writable dir"
WANT="$(sh "$HERE/deploy-confinement.sh" --compose 2>"$ERR")"; _rc=$?
_e="$(grep 'FAIL' "$ERR" | head -1)"; rm -f "$ERR"
[ "$_rc" = 0 ] && [ -n "$WANT" ] || unchecked "the compose failed${_e:+ ($_e)}, so there is nothing to compare against" "sh $HERE/deploy-confinement.sh --compose"

# One line per leaf, array positions dropped, each line once: `network.allowedDomains[]=github.com`. Not paths(scalars):
# that filter is falsy on a `false` leaf, so a key flipped to false would never be compared.
FLAT='[paths(type != "object" and type != "array") as $p | ($p | map(if type == "number" then "[]" else tostring end) | join(".") | gsub("\\.\\[\\]"; "[]")) + "=" + (getpath($p) | tostring)] | unique[]'
W="$(mktemp "${TMPDIR:-/tmp}/drift-confinement.XXXXXX")" || unchecked "mktemp under ${TMPDIR:-/tmp} failed" "set TMPDIR to a writable dir"
H="$(mktemp "${TMPDIR:-/tmp}/drift-confinement.XXXXXX")" || { rm -f "$W"; unchecked "mktemp under ${TMPDIR:-/tmp} failed" "set TMPDIR to a writable dir"; }
printf '%s' "$WANT" | jq -r "$FLAT" > "$W" 2>/dev/null || { rm -f "$W"; unchecked "the composed block is not JSON" "sh $HERE/deploy-confinement.sh --compose"; }
jq -r ".sandbox // {} | $FLAT" "$MF" > "$H" 2>/dev/null || : > "$H"
LACKS="$(awk 'FILENAME == ARGV[1] { h[$0] = 1; next } $0 != "" && !($0 in h)' "$H" "$W")"
EXTRA="$(awk 'FILENAME == ARGV[1] { h[$0] = 1; next } $0 != "" && !($0 in h)' "$W" "$H")"
rm -f "$W" "$H"

N=0; SUBJ=""
add() { N=$((N + 1)); SUBJ="$SUBJ
$1"; }
[ "$SB" = 1 ] || { log_note "$P the marker is present but $MF holds no sandbox block: the ledger reads every call as confined"; add marker-without-block; }
[ "$MKP" = 1 ] || { log_note "$P $MF holds a sandbox block but the marker is missing: the ledger reads every call as off"; add block-without-marker; }
# The marker's one policy line is the P3 skip (harbor#1300): harbor.toml flipped since the install reads as drift.
if [ "$MKP" = 1 ]; then
  _wm="$(sh "$HERE/deploy-confinement.sh" --marker 2>/dev/null)" || unchecked "harbor.toml cannot be read for the marker" "sh $HERE/deploy-confinement.sh --marker"
  _hm="$(cat "$MK" 2>/dev/null)" || _hm=""
  if [ "$_hm" != "$_wm" ]; then
    case "$_wm" in *skip=covered*) _ws=on ;; *) _ws=off ;; esac
    log_note "$P the marker's P3 skip is not what harbor.toml asks for now (the install would write it $_ws)"; add marker-skip
  fi
fi
_ifs=$IFS; IFS='
'
for _l in $LACKS; do log_note "$P the installed block lacks: $_l"; add "lacks:$_l"; done
for _l in $EXTRA; do log_note "$P the installed block has what the compose does not: $_l"; add "extra:$_l"; done
IFS=$_ifs
if [ "$N" = 0 ]; then
  log_ok "$P the installed sandbox block matches the compose ($(printf '%s\n' "$WANT" | jq -r '[paths(type != "object" and type != "array")] | length') leaves)"
  finish green match 0
fi
log_fail "$P the installed confinement differs from the compose in $N place(s), listed above"
log_fix "$FIX (re-composes and writes; review the rows above first: a hand edit there is lost)"
set -f; IFS='
'
# shellcheck disable=SC2086
finish red drift 1 $SUBJ
