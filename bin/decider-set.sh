#!/usr/bin/env sh
# decider-set.sh (harbor#954 PR B, from #1003) -- the ONE set of wired hook scripts that the two
# switches (HARBOR_ADMISSION_DISABLE, HARBOR_ADMISSION_SHADOW) have to answer for, and what each one does about them.
#   sh decider-set.sh            every decider: script TAB disable TAB shadow TAB reason
#   sh decider-set.sh --switch   the deciders whose first live line is the HARBOR_ADMISSION_DISABLE check
#   sh decider-set.sh --exempt   the deciders that do not carry it, each with a reason (--table has them)
#   sh decider-set.sh --records  the deciders whose refusals record under HARBOR_ADMISSION_SHADOW
#   sh decider-set.sh --check    exit 1, one FAIL line per drift between the wiring and the table below
#
# WHERE THE SET COMES FROM. The scripts in floor-install.sh's wiring table (floor_hooks) are the floor's
# hooks, read from that file and not copied. Three other installers wire a hook into the same settings.json
# (SIBLINGS below); they carry no table of their own, so they are named here and --check proves, in a
# checkout, that each installer still names its script and that no other *-install.sh has started wiring
# hooks unlisted. Consumers: lint F1, floor-test, floor-verify (they call this), B6 (its
# NO-KILLSWITCH list is diffed against --exempt by floor-test).
#
# THE DISPOSITIONS BELOW ARE THE ONLY HAND-WRITTEN PART. Each wired script needs a row, and a row whose
# script is no longer wired is stale: both are FAIL lines, so the table cannot lag the wiring.
#   disable  first   line 1 of the script is the kill-switch check (docs/explanation/admission-baseline.md)
#            exempt  it is not, and the reason says why
#   shadow   records its refusals go through floor_block (or read the switch) and record under shadow
#            enforces it can refuse and does not read shadow
#            none    it cannot refuse
set -u
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH= cd -- "${HERE:-/}" && pwd)"
FI="$HERE/floor-install.sh"

# <installer> <script it wires into settings.json>
SIBLINGS='context-injection-install.sh injection-rule.sh
context-injection-install.sh govern-token.sh
prod-guard-install.sh prod-guard-ambient.sh
deploy-runtime-install.sh context-resolve.sh'

# script|disable|shadow|reason
DISPOSITIONS="floor-hook.sh|first|enforces|fail-closed wrapper: its deny means a guard could not evaluate
guard-bash.sh|first|records|
guard-egress.sh|first|records|
guard-selfedit.sh|first|records|
guard-deliverables.sh|first|records|
annotate-web.sh|first|none|
guard-cloud.sh|first|enforces|irreversible deletes of shared client infrastructure: nothing to measure, everything to lose
guard-destroy.sh|first|enforces|irreversible local work destruction
govern-hook.sh|first|enforces|its verdict is the repo's own merge-check, not a floor rule
guard-apiroute.sh|first|none|a repair, not a deny
context-resolve.sh|first|none|
guard-integrity.sh|first|enforces|floor drift
guard-stop.sh|first|enforces|refuses once per state and blocks no tool call
floor-observe.sh|exempt|none|records the override itself, so it has to run when the switch is set; cannot refuse
event-hook.sh|exempt|none|a recorder, exit 0 on every path, cannot refuse
govern-token.sh|exempt|none|announces the provenance token, cannot refuse
injection-rule.sh|exempt|enforces|rule packs are each repo's own governance and its run: deny is the repo's, not the floor's
prod-guard-ambient.sh|exempt|enforces|defers to prod_guard.py, the cloud and data destruction deny that the switch does not lift (floor-deny.sh:34-35)"

wired() { # the scripts floor-install.sh's table wires, then the siblings'
  if [ -f "$FI" ]; then
    sed -n "/^floor_hooks() { cat <<'ROWS'/,/^ROWS\$/p" "$FI" | grep -vE '^(#|floor_hooks|ROWS|[[:space:]]*$)' \
      | cut -d';' -f3 | tr ' ' '\n' | grep -E '\.sh$'
  fi
  printf '%s\n' "$SIBLINGS" | awk '{print $2}'
}
WIRED="$(wired | sort -u)"

table() { printf '%s\n' "$DISPOSITIONS" | awk -F'|' '{printf "%s\t%s\t%s\t%s\n", $1, $2, $3, $4}' | sort; }

case "${1:-}" in
  ''|--table) table ;;
  --switch)  table | awk -F'\t' '$2 == "first" {print $1}' ;;
  --exempt)  table | awk -F'\t' '$2 == "exempt" {print $1}' ;;
  --records) table | awk -F'\t' '$3 == "records" {print $1}' ;;
  --check)
    F=""
    add() { F="$F$1
"; }
    for s in $WIRED; do
      table | awk -F'\t' -v s="$s" '$1 == s {f=1} END {exit !f}' \
        || add "$s is wired into settings.json and has no row in decider-set.sh DISPOSITIONS"
    done
    for s in $(table | cut -f1); do
      printf '%s\n' "$WIRED" | grep -qx "$s" || add "decider-set.sh has a row for $s and nothing wires it"
    done
    _rows="$(table | awk -F'\t' '
      $2 != "first" && $2 != "exempt" {printf "%s has disable=%s (first or exempt)\n", $1, $2}
      $3 != "records" && $3 != "enforces" && $3 != "none" {printf "%s has shadow=%s (records, enforces or none)\n", $1, $3}
      ($2 == "exempt" || $3 == "enforces") && $4 == "" {printf "%s is exempt or enforcing and gives no reason\n", $1}')"
    [ -z "$_rows" ] || add "$_rows"
    # in a checkout: the sibling installers still name their scripts, and no installer wires hooks unlisted
    if [ -f "$HERE/context-injection-install.sh" ]; then
      while read -r i s; do
        [ -f "$HERE/$i" ] || continue
        grep -q "$s" "$HERE/$i" || add "$i no longer names $s, which decider-set.sh says it wires"
      done <<SIB
$SIBLINGS
SIB
      for i in "$HERE"/*-install.sh; do
        b="${i##*/}"; [ "$b" = floor-install.sh ] && continue
        [ -L "$i" ] && continue   # a rename shim (harbor#961) is an old name of an installer judged under its own
        grep -q '\.hooks' "$i" || continue
        printf '%s\n' "$SIBLINGS" | awk '{print $1}' | grep -qx "$b" \
          || add "$b writes settings hooks and is not in decider-set.sh SIBLINGS"
      done
    fi
    [ -n "$F" ] || exit 0
    . "$HERE/library-log.sh"; log_init decider-set
    while IFS= read -r l; do
      [ -n "$l" ] || continue
      log_fail "$l"; log_nofix "bin/decider-set.sh (the wiring is floor-install.sh's table; the rows are DISPOSITIONS)"
    done <<FEOF
$F
FEOF
    log_end || :
    exit 1 ;;
  -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) printf 'usage: decider-set.sh [--table|--switch|--exempt|--records|--check]\n' >&2; exit 2 ;;
esac
