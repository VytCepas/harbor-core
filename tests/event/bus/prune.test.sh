#!/usr/bin/env sh
# bin/event-bus.sh prune (harbor#1043, docs/reference/checks.md event.retention): a day file dated more than 14
# days before today (UTC) is deleted, every younger one kept; the sweep rides the first emit of
# each day unless prune.off is in the bus dir, and a file it cannot delete is said, with its fix.
. "$(dirname "$0")/../../lib/core.sh"; t_init
EB="$T_ROOT/bin/event-bus.sh"
# The bus clock is fixed at 2026-10-06T12:00:00Z, so the boundary is a date this file can name.
export HARBOR_EVENT_BUS_SKEW=$(( 1791288000 - $(date -u +%s) ))
plant() { mkdir -p "$1"; shift; for _d in "$@"; do printf '{"id":"%s"}\n' "$_d" > "$BUS/$_d.jsonl"; done; }
left() { find "$BUS" -name '*.jsonl' | sed 's#.*/##; s#\.jsonl$##' | sort | tr '\n' ' '; }

t_section "the 14-day boundary"
BUS="$T_TMP/b1"; export HARBOR_EVENT_DIR="$BUS"
plant "$BUS" 2026-08-01 2026-09-20 2026-09-21 2026-09-22 2026-10-05 2026-10-06
sh "$EB" prune > "$T_TMP/out" 2> "$T_TMP/err"; rc=$?
t_eq "exit 0" 0 "$rc"
t_eq "15 days old and older are gone; 14 days old is kept" '2026-09-22 2026-10-05 2026-10-06 ' "$(left)"
t_has "the run is stamped with its docs/reference/checks.md id" "$(cat "$T_TMP/err")" "ok: [check:event.retention] removed 3 day file(s) dated before 2026-09-22, kept 3"
t_eq "stdout stays clean" '' "$(cat "$T_TMP/out")"
sh "$T_ROOT/bin/harbor" event prune >/dev/null 2>&1; rc=$?
t_eq "harbor event prune: exit 0 on a bus already in retention" 0 "$rc"

t_section "the sweep rides the first emit of each UTC day"
BUS="$T_TMP/b2"; export HARBOR_EVENT_DIR="$BUS"
plant "$BUS" 2026-09-01
sh "$EB" emit a.b first >/dev/null 2>&1
t_eq "the first emit of the day swept the expired file" '2026-10-06 ' "$(left)"
t_eq "...and stamped the day" 2026-10-06 "$(cat "$BUS/prune.day")"
plant "$BUS" 2026-09-02
sh "$EB" emit a.b second >/dev/null 2>&1
t_eq "a second emit that day does not sweep again" '2026-09-02 2026-10-06 ' "$(left)"

t_section "prune.off turns the sweep off; an explicit prune still runs"
BUS="$T_TMP/b3"; export HARBOR_EVENT_DIR="$BUS"
plant "$BUS" 2026-09-01; : > "$BUS/prune.off"
sh "$EB" emit a.b off >/dev/null 2>&1
t_eq "the emit left the expired file alone" '2026-09-01 2026-10-06 ' "$(left)"
sh "$EB" prune >/dev/null 2>&1
t_eq "a typed prune removes it" '2026-10-06 ' "$(left)"

if [ "$(id -u)" != 0 ]; then
  t_section "a file it cannot delete is red, with its fix"
  BUS="$T_TMP/b4"; export HARBOR_EVENT_DIR="$BUS"
  plant "$BUS" 2026-09-01 2026-10-06; chmod 500 "$BUS"
  sh "$EB" prune > /dev/null 2> "$T_TMP/err"; rc=$?
  t_eq "exit 1" 1 "$rc"
  t_has "the FAIL names the file" "$(cat "$T_TMP/err")" "FAIL: [check:event.retention] $BUS/2026-09-01.jsonl is older than 14 days and could not be deleted"
  t_has "...and the fix is the command" "$(cat "$T_TMP/err")" "fix: rm -f '$BUS/2026-09-01.jsonl'"
  sh "$EB" emit a.b still-emits >/dev/null 2>&1; rc=$?
  t_eq "an emit whose sweep fails still exits 0" 0 "$rc"
  chmod 700 "$BUS"
else echo "  skip: running as root, which can delete from a read-only dir — the red case is unprovable here"; fi
t_done
