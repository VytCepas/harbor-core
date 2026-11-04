#!/usr/bin/env sh
# admission-decide.sh (harbor#1030) — the one decision function of the floor: a fired rule's mode is read from its controls.tsv row.
#
#   sh admission-decide.sh <guard> <rule> [--shadow 0|1] [--enforcing 0|1] [--ask 0|1] [--escalate 0|1] [--register FILE]
#       stdout  one line: <verdict> TAB <control-id> TAB <source>      verdict: block | shadow | warn | ask | off
#                                                                      source: register | norow | unreadable
#       stderr  the stamp `(control:<id> mode:<mode> verdict:<verdict>)`, and when the register could not decide, the remedy
#   sh admission-decide.sh --self-test        every row of the admission controls returns the verdict its mode declares, each arm red on a fixture
#
#   --shadow 1     the session runs in the operator's launch-time shadow mode
#   --enforcing 1  floor_shadow_enforces says this rule keeps blocking in a shadow session (a surface, a switch, the API route)
#   --ask 1        the guard answers a person (cloud, destroy): a warn row asks, a block row denies
#   --escalate 1   no human is present, or the posture is deny: an ask becomes a deny
#   --fallback M   the mode to assume when the register cannot answer (default block: fail closed); an ask-tier guard passes warn
#   --register     the controls register (default: ../standards/naming/controls.tsv beside this script's tree, or $FLOOR_CONTROLS)
#
# THE TABLE. A row's mode is the rule's mode (D-64): block enforces, warn prints and allows, shadow records and allows, off skips
# the rule and records that it was skipped (the per-control disable: one cell, edited by a person's PR). A shadow session turns a
# block row into shadow unless the rule is one that keeps enforcing; no row, shadow or off, can loosen an enforcing rule.
# A rule is found by the `<guard>:<rule>` its guard emits (the emitted cell), else by its id `admission.<rule>`.
# FAIL CLOSED (harbor#1030, decided as recommended): a register that cannot be read, or has no row for the rule, decides as a block row
# would and says so with its remedy. The floor is never left off silently for want of a file. It is the mode a rule had before rows, so
# no verdict changes when the register is absent. A mode that is not one of the four decides as block.
# THE DETECTION STAYS IN THE GUARD. A guard parses its event, decides that a rule fired, and asks here what that means; the predicate
# of a rule is code and is not a row. The stamp is printed by this function only (harbor#957).
# POSIX sh and awk (the floor's layer rule); it forks nothing but awk, and only on a block path.
# Not a gate: the guard that calls this has already honoured the kill switch. Named first so B6's first-live-line check holds for a pinned file.
: "${HARBOR_ADMISSION_DISABLE:-0}"
set -eu
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

decide() { # <guard> <rule> <shadow> <enforcing> <register> <ask> <escalate> <fallback>
  _g="$1"; _r="$2"; _sh="$3"; _en="$4"; _reg="$5"; _ask="$6"; _esc="$7"; _fb="$8"; _id="admission.$2"
  _mode=''; _src=register
  if [ ! -r "$_reg" ] || [ ! -s "$_reg" ]; then _src=unreadable
  else
    # A rule is found by what the guard emits (`<guard>:<rule>`, the emitted cell) and, when no row emits it, by its id.
    _hit="$(awk -F'\t' -v k="$_g:$_r" -v fid="$_id" '/^#/ { next } $3 != "admission" { next }
      $12 == k { i = $1; m = $2; f = 1; exit } $1 == fid && ($12 == "-" || $12 == "") && !b { bi = $1; bm = $2; b = 1 }
      END { if (f) print i "\t" m; else if (b) print bi "\t" bm }' "$_reg" 2>/dev/null)" || _src=unreadable
    if [ "$_src" = unreadable ] || [ -z "$_hit" ]; then [ "$_src" = unreadable ] || _src=norow
    else _id="${_hit%%	*}"; _mode="${_hit#*	}"; fi
  fi
  [ "$_src" = register ] || [ -z "$_fb" ] || _mode="$_fb"   # no row to read: the mode the guard held before rows (a warning-layer guard asked, it did not deny)
  case "$_mode" in advisory|inform) _mode=warn ;; esac
  case "$_mode" in off|shadow|warn|block) ;; *) _mode=block ;; esac
  # An ask-tier guard (cloud, destroy) answers a person: its warn row asks, its block row denies, and the guard's own
  # escalation (no human present, a deny posture) turns an ask into a deny. A rule that keeps enforcing is never loosened.
  case "$_mode" in
    block)  if [ "$_sh" = 1 ] && [ "$_en" != 1 ]; then _v=shadow; else _v=block; fi ;;
    shadow) if [ "$_en" = 1 ]; then _v=block; else _v=shadow; fi ;;
    off)    if [ "$_en" = 1 ]; then _v=block; else _v=off; fi ;;
    warn)   if [ "$_en" = 1 ]; then _v=block
            elif [ "$_ask" = 1 ]; then if [ "$_esc" = 1 ]; then _v=block; else _v=ask; fi
            else _v=warn; fi ;;
  esac
  case "$_src" in
    unreadable) _st="$(printf '(control:%s mode:%s verdict:%s) the controls register is unreadable at %s, so the rule is decided as a block row: it fails closed. Remedy: restore standards/naming/controls.tsv beside the floor (the floor installer copies it)' "$_id" "$_mode" "$_v" "$_reg")" ;;
    norow)      _st="$(printf '(control:%s mode:%s verdict:%s) the controls register has no admission row for this rule, so it is decided as a block row. Remedy: add the row to standards/naming/controls.tsv' "$_id" "$_mode" "$_v")" ;;
    *)          _st="$(printf '(control:%s mode:%s verdict:%s)' "$_id" "$_mode" "$_v")" ;;
  esac
  # --defer-stamp: the guard owns its stderr order (its refusal reads first), so the stamp rides as a fourth field and the guard prints it
  if [ "$_defer" = 1 ]; then printf '%s\t%s\t%s\t%s\n' "$_v" "$_id" "$_src" "$_st"
  else printf '%s\n' "$_st" >&2; printf '%s\t%s\t%s\n' "$_v" "$_id" "$_src"; fi
}

case "${1:-}" in
  --help|-h) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
if [ "${1:-}" = --self-test ]; then
  REG_LIVE="${FLOOR_CONTROLS:-$HERE/../standards/naming/controls.tsv}"
  _n=0; _f=0
  T="$(mktemp -d "${TMPDIR:-/tmp}/ad.XXXXXX")"; trap 'rm -rf "$T"' EXIT
  printf 'id\tmode\ttype\tengine\n' > "$T/reg"
  for _m in block warn shadow off; do printf 'admission.r-%s\t%s\tadmission\tbin/admission-egress.sh\n' "$_m" "$_m" >> "$T/reg"; done
  printf 'admission.renamed-slug\twarn\tadmission\tbin/admission-cloud.sh\t-\t-\t-\t-\t-\t-\t-\tcloud:old-name\n' >> "$T/reg"
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
  chkx() { # <label> <want-verdict> <guard> <rule> <flags...>: an arm that names the guard and the ask/escalate flags
    _l="$1"; _w="$2"; _gd="$3"; _rl="$4"; shift 4; _n=$((_n+1))
    _got="$(sh "$0" "$_gd" "$_rl" "$@" --register "$T/reg" 2>/dev/null | cut -f1)" || _got=error
    [ "$_got" = "$_w" ] || { _f=$((_f+1)); printf '  mismatch: %s: want %s, got %s\n' "$_l" "$_w" "$_got"; }
  }
  chkx "off row skips the rule"                      off    egress r-off
  chkx "off row cannot loosen an enforcing rule"     block  egress r-off --enforcing 1
  chkx "off row, shadow session"                     off    egress r-off --shadow 1
  chkx "an ask-tier guard: a warn row asks"          ask    cloud  r-warn --ask 1
  chkx "...a block row denies"                       block  cloud  r-block --ask 1
  chkx "...and escalation turns an ask into a deny"  block  cloud  r-warn --ask 1 --escalate 1
  chkx "a rule is found by its emitted cell"         ask    cloud  old-name --ask 1
  chkx "...and not by another guard's emitted cell"  block  destroy old-name --ask 1
  chkx "no row, an ask-tier guard falls back to its old mode"  ask    cloud  no-such-rule --ask 1 --fallback warn
  chkx "...and a row that exists is not overridden by it"       block  cloud  r-block --ask 1 --fallback warn
  # every admission row of the live register returns the verdict its own mode declares
  if [ -r "$REG_LIVE" ]; then
    awk -F'\t' '/^#/ { next } $3 == "admission" { print $1 "\t" $2 "\t" $12 }' "$REG_LIVE" | while IFS="$(printf '\t')" read -r _cid _cm _ce; do
      case "$_ce" in *:*) _gd="${_ce%%:*}"; _rule="${_ce#*:}" ;; *) _gd=x; _rule="${_cid#admission.}" ;; esac
      case "$_cm" in block) _w=block; _wa=block ;; warn) _w=warn; _wa=ask ;; shadow) _w=shadow; _wa=shadow ;; off) _w=off; _wa=off ;; *) _w=block; _wa=block ;; esac
      _got="$(sh "$0" "$_gd" "$_rule" --register "$REG_LIVE" 2>/dev/null | cut -f1)"
      [ "$_got" = "$_w" ] || printf '  mismatch: %s: mode %s should decide %s, got %s\n' "$_cid" "$_cm" "$_w" "$_got"
      _got="$(sh "$0" "$_gd" "$_rule" --ask 1 --register "$REG_LIVE" 2>/dev/null | cut -f1)"
      [ "$_got" = "$_wa" ] || printf '  mismatch: %s: mode %s should decide %s for an ask-tier guard, got %s\n' "$_cid" "$_cm" "$_wa" "$_got"
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
_shadow=0; _enf=0; _ask=0; _esc=0; _fb=""; _defer=0; _reg="${FLOOR_CONTROLS:-$HERE/../standards/naming/controls.tsv}"
while [ $# -gt 0 ]; do
  case "$1" in
    --shadow) _shadow="${2:-0}"; shift ;;
    --enforcing) _enf="${2:-0}"; shift ;;
    --ask) _ask="${2:-0}"; shift ;;
    --escalate) _esc="${2:-0}"; shift ;;
    --fallback) _fb="${2:-}"; shift ;;
    --defer-stamp) _defer="${2:-0}"; shift ;;
    --register) _reg="${2:-}"; shift ;;
    *) printf 'admission-decide: unknown argument %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done
decide "$_guard" "$_rule" "$_shadow" "$_enf" "$_reg" "$_ask" "$_esc" "$_fb"
