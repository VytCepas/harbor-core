#!/usr/bin/env sh
# drift-confinement.sh (harbor#1299, #555 P2) — the check drift.confinement: the installed `sandbox` block of the
# root-owned managed-settings.json against what deploy-confinement.sh --compose builds from core and private now.
# A moved PORT_ROOT, a new private host, a strict or credentials key flipped in harbor.toml, or a hand edit all read
# as drift. Lists compare as sets: the order of rows is not policy.
#   sh drift-confinement.sh            exit 0 matched or not installed, 1 drift, 3 unchecked (D-29, never a green)
#   sh drift-confinement.sh --state    the same, plus one word on stdout: match | drift | not-installed | unchecked,
#                                      and no receipt (floor-verify's read; a verifier writes nothing)
#   sh drift-confinement.sh --status   the reconcile records (contracts/reconcile.md): a row per leaf that differs, its age; 3 unchecked
# Read-only: it never writes managed settings; the fix is the operator's `sudo sh deploy-confinement.sh`.
# Every finding line carries [check:drift.confinement]; the receipt goes to log_receipt's dir (docs/reference/checks.md).
# HARBOR_SCOPE_MANAGED_SETTINGS moves the target, as in deploy-confinement.sh (tests, no root).
set -u
case "${1:-}" in -h|--help) awk 'NR<2{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;; esac
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
. "$HERE/library-log.sh"
log_init drift-confinement
STATE=0; STATUS=0
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
for _a in "$@"; do
  case "$_a" in
    --state) STATE=1; LOG_FD=2 ;;
    --status) STATUS=1; LOG_FD=2 ;;   # stdout is data
    *) LOG_FD=2; log_fail "unknown argument $_a"; log_fix "sh $0 --help"; exit 2 ;;
  esac
done
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh (harbor#1392)
[ "$STATE$STATUS" != 11 ] || { LOG_FD=2; log_fail "--state and --status are two different reads"; log_fix "sh $0 --help"; exit 2; }
ID=drift.confinement; P="[check:$ID]"
[ "$STATUS" = 0 ] || status_init "$ID" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" || exit 3
if [ -n "${HARBOR_SCOPE_MANAGED_SETTINGS:-${HARBOR_MANAGED_SETTINGS:-}}" ]; then MF="${HARBOR_SCOPE_MANAGED_SETTINGS:-$HARBOR_MANAGED_SETTINGS}"
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
  [ "$STATUS" = 0 ] || [ "$_fx" = 3 ] || status_end || :   # a run that judged closes its report; one that could not already has
  log_end || :
  exit "$_fx"
}
unchecked() { log_warn "$P unchecked: $1"; log_fix "$2"; [ "$STATUS" = 0 ] || status_unjudged "$1" || :; finish stood-down unchecked 3; }

command -v jq >/dev/null 2>&1 || unchecked "jq is required to read $MF" "$(pkg_hint jq)"
SB=0
if [ -f "$MF" ]; then
  jq -e . "$MF" >/dev/null 2>&1 || unchecked "$MF is unreadable or not JSON" "read it as the operator; $FIX rewrites it"
  ! jq -e 'has("sandbox")' "$MF" >/dev/null 2>&1 || SB=1
fi
MKP=0; [ ! -f "$MK" ] || MKP=1
# allowAppleEvents is never policy (DE-40, #1442): at any depth, with any value but false, in the managed file.
AE=''
[ ! -f "$MF" ] || AE="$(jq -r '[paths as $p | select($p[-1] == "allowAppleEvents") | select(getpath($p) != false) | $p | map(tostring) | join(".")][]' "$MF" 2>/dev/null || :)"
if [ "$SB" = 0 ] && [ "$MKP" = 0 ]; then
  if [ -z "$AE" ]; then
    log_skip "$P not installed: no sandbox block in $MF and no marker beside it"
    finish stood-down not-installed 0
  fi
  # No confinement installed, yet the key is planted: that alone is the finding (nothing to compare the rest against).
  for _l in $AE; do log_note "$P $MF sets $_l: allowAppleEvents removes the sandbox's code-execution isolation and is never policy (DE-40)"; done
  log_fail "$P the managed file sets allowAppleEvents, which is never policy"
  log_fix "remove the key from $MF as root; no installer in this repo writes it"
  # shellcheck disable=SC2086
  finish red drift 1 apple-events:$AE
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
$1"; [ "$STATUS" = 0 ] || status_drift "$1" "the installed sandbox block equals the compose" "it differs: $1" "$FIX"; }
[ "$STATUS" = 0 ] || status_ok "$(printf '%s\n' "$WANT" | jq -r '[paths(type != "object" and type != "array")] | length' 2>/dev/null || echo 0)"
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
for _l in $AE; do log_note "$P $MF sets $_l: allowAppleEvents removes the sandbox's code-execution isolation and is never policy (DE-40)"; add "apple-events:$_l"; done
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
