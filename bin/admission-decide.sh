#!/usr/bin/env sh
# admission-decide.sh (harbor#1030) — the one decision function of the floor: a fired rule's mode is read from its controls.tsv row.
#
#   sh admission-decide.sh <guard> <rule> [--shadow 0|1] [--enforcing 0|1] [--register FILE]
#       stdout  one line: <verdict> TAB <control-id> TAB <source>      verdict: block | shadow | warn
#                                                                      source: register | norow | unreadable
#       stderr  the stamp `(control:<id> mode:<mode> verdict:<verdict>)`, and when the register could not decide, the remedy
#   sh admission-decide.sh --self-test        every row of the admission controls returns the verdict its mode declares, each arm red on a fixture
#
#   --shadow 1     the session runs under HARBOR_ADMISSION_SHADOW=1 (the operator's launch-time switch)
#   --enforcing 1  floor_shadow_enforces says this rule keeps blocking in a shadow session (a surface, a switch, the API route)
#   --register     the controls register (default: ../standards/naming/controls.tsv beside this script's tree, or $FLOOR_CONTROLS)
#
# THE TABLE. A row's mode is the rule's mode (D-64): block enforces, warn prints and allows, shadow records and allows. A shadow session
# turns a block row into shadow unless the rule is one that keeps enforcing; a row can never loosen an enforcing rule.
# FAIL CLOSED (harbor#1030, decided as recommended): a register that cannot be read, or has no row for the rule, decides as a block row
# would and says so with its remedy. The floor is never left off silently for want of a file. It is the mode a rule had before rows, so
# no verdict changes when the register is absent.
# THE DETECTION STAYS IN THE GUARD. A guard parses its event, decides that a rule fired, and asks here what that means; the predicate
# of a rule is code and is not a row. The stamp is printed by this function only (harbor#957).
# POSIX sh and awk (the floor's layer rule); it forks nothing but awk, and only on a block path.
# Not a gate: the guard that calls this has already honoured the kill switch. Named first so B6's first-live-line check holds for a pinned file.
: "${HARBOR_ADMISSION_DISABLE:-0}"
set -eu
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

decide() { # <guard> <rule> <shadow> <enforcing> <register>
  _g="$1"; _r="$2"; _sh="$3"; _en="$4"; _reg="$5"; _id="admission.$2"
  _mode=''; _src=register
  if [ ! -r "$_reg" ] || [ ! -s "$_reg" ]; then _src=unreadable
  else
    _mode="$(awk -F'\t' -v id="$_id" '/^#/ { next } $1 == id && $3 == "admission" { print $2; exit }' "$_reg" 2>/dev/null)" || _src=unreadable
    [ "$_src" = unreadable ] || [ -n "$_mode" ] || _src=norow
  fi
  case "$_mode" in advisory|inform) _mode=warn ;; esac
  case "$_mode" in shadow|warn|block) ;; *) _mode=block ;; esac
  case "$_mode" in
    block)  if [ "$_sh" = 1 ] && [ "$_en" != 1 ]; then _v=shadow; else _v=block; fi ;;
    shadow) if [ "$_en" = 1 ]; then _v=block; else _v=shadow; fi ;;
    warn)   if [ "$_en" = 1 ]; then _v=block; else _v=warn; fi ;;
  esac
  case "$_src" in
    unreadable) printf '(control:%s mode:%s verdict:%s) the controls register is unreadable at %s, so the rule is decided as a block row: it fails closed. Remedy: restore standards/naming/controls.tsv beside the floor (the floor installer copies it)\n' "$_id" "$_mode" "$_v" "$_reg" >&2 ;;
    norow)      printf '(control:%s mode:%s verdict:%s) the controls register has no admission row for this rule, so it is decided as a block row. Remedy: add the row to standards/naming/controls.tsv\n' "$_id" "$_mode" "$_v" >&2 ;;
    *)          printf '(control:%s mode:%s verdict:%s)\n' "$_id" "$_mode" "$_v" >&2 ;;
  esac
  printf '%s\t%s\t%s\n' "$_v" "$_id" "$_src"
}

case "${1:-}" in
  --help|-h) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
if [ "${1:-}" = --self-test ]; then
  REG_LIVE="${FLOOR_CONTROLS:-$HERE/../standards/naming/controls.tsv}"
  _n=0; _f=0
  T="$(mktemp -d "${TMPDIR:-/tmp}/ad.XXXXXX")"; trap 'rm -rf "$T"' EXIT
  printf 'id\tmode\ttype\tengine\n' > "$T/reg"
  for _m in block warn shadow; do printf 'admission.r-%s\t%s\tadmission\tbin/admission-egress.sh\n' "$_m" "$_m" >> "$T/reg"; done
  chk() { # <label> <want-verdict> <want-source> <rule> <shadow> <enforcing> [register]
    _n=$((_n+1)); _got="$(sh "$0" egress "$4" --shadow "$5" --enforcing "$6" --register "${7:-$T/reg}" 2>/dev/null | cut -f1,3 | tr '\t' ' ')" || _got=error
    [ "$_got" = "$2 $3" ] || { _f=$((_f+1)); printf '  mismatch: %s: want %s %s, got %s\n' "$1" "$2" "$3" "$_got"; }
  }
  chk "block row, plain session"                block   register r-block 0 0
  chk "block row, shadow session"               shadow  register r-block 1 0
  chk "block row, shadow session, enforcing"    block   register r-block 1 1
  chk "warn row"                                warn    register r-warn  0 0
  chk "warn row cannot loosen an enforcing rule" block  register r-warn  1 1
  chk "shadow row"                              shadow  register r-shadow 0 0
  chk "shadow row, enforcing rule stays block"  block   register r-shadow 0 1
  chk "no row decides as block"                 block   norow    r-none  0 0
  chk "no row, shadow session, as a block row"  shadow  norow    r-none  1 0
  chk "unreadable register fails closed"        block   unreadable r-block 0 0 "$T/missing"
  chk "unreadable register in a shadow session" shadow  unreadable r-block 1 0 "$T/missing"
  : > "$T/empty"; chk "an empty register is unreadable" block unreadable r-block 0 0 "$T/empty"
  # every admission row of the live register returns the verdict its own mode declares
  if [ -r "$REG_LIVE" ]; then
    awk -F'\t' '/^#/ { next } $3 == "admission" { print $1 "\t" $2 }' "$REG_LIVE" | while IFS="$(printf '\t')" read -r _cid _cm; do
      _rule="${_cid#admission.}"; case "$_cm" in block) _w=block ;; warn) _w=warn ;; shadow) _w=shadow ;; *) _w=block ;; esac
      _got="$(sh "$0" egress "$_rule" --register "$REG_LIVE" 2>/dev/null | cut -f1)"
      [ "$_got" = "$_w" ] || printf '  mismatch: %s: mode %s should decide %s, got %s\n' "$_cid" "$_cm" "$_w" "$_got"
    done > "$T/live"
    _n=$((_n+1)); [ ! -s "$T/live" ] || { _f=$((_f+1)); cat "$T/live"; }
  else _n=$((_n+1)); _f=$((_f+1)); printf '  mismatch: the live register %s is unreadable, so no row was swept\n' "$REG_LIVE"; fi
  # the stamp: printed here, once, naming the control
  _n=$((_n+1)); sh "$0" egress r-block --register "$T/reg" 2>&1 >/dev/null | grep -q '^(control:admission.r-block mode:block verdict:block)$' \
    || { _f=$((_f+1)); printf '  mismatch: the stamp line is missing or malformed\n'; }
  printf 'admission-decide: self-test: %d arm(s), %d failed\n' "$_n" "$_f"
  [ "$_f" -eq 0 ] || exit 1
  exit 0
fi

_guard="${1:-}"; _rule="${2:-}"; [ -n "$_guard" ] && [ -n "$_rule" ] || { printf 'usage: admission-decide.sh <guard> <rule> [--shadow 0|1] [--enforcing 0|1] [--register FILE]\n' >&2; exit 2; }
shift 2
_shadow=0; _enf=0; _reg="${FLOOR_CONTROLS:-$HERE/../standards/naming/controls.tsv}"
while [ $# -gt 0 ]; do
  case "$1" in
    --shadow) _shadow="${2:-0}"; shift ;;
    --enforcing) _enf="${2:-0}"; shift ;;
    --register) _reg="${2:-}"; shift ;;
    *) printf 'admission-decide: unknown argument %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done
decide "$_guard" "$_rule" "$_shadow" "$_enf" "$_reg"
