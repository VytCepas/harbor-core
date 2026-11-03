#!/usr/bin/env sh
# bin/status-fleet-watch.sh (harbor#1437): the fleet controller's watch pass, hourly, on harbor's schedule. The controller is a stub
# that records its argv and prints a --json report. Proves: the alerts become one receipt (red, then green), only the delta is
# reported, a controller that judged nothing is stood-down and never green, no pass can reach a webhook, --if-due makes it hourly,
# a hung controller is cut off, and the snapshot refresher is what calls it.
. "$(dirname "$0")/../../lib/core.sh"; t_init
S="$T_ROOT/bin/status-fleet-watch.sh"
W="$T_TMP/w"; CFG="$W/cfg"; mkdir -p "$W/bin" "$CFG"
cp "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/status-fleet-watch.sh" "$T_ROOT/bin/scope-roots.sh" "$W/bin/"
: > "$W/fleet.yaml"
# the stub controller: argv appended to calls, the report taken from report.json, the exit from rc
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/calls"\ncat "%s/report.json"\nexit "$(cat "%s/rc")"\n' "$W" "$W" "$W" > "$W/orch"; chmod +x "$W/orch"
report() { printf '{"checks":[],"text":"x","alerts":[%s]}\n' "$1" > "$W/report.json"; printf '%s\n' "${2:-1}" > "$W/rc"; }
alert() { printf '{"project":"%s","level":"critical","category":"%s","message":"m"}' "$1" "$2"; }
run() { CLAUDE_CONFIG_DIR="$CFG" HARBOR_SCOPE_FLEET_CONTROLLER_BIN="$W/orch" HARBOR_SCOPE_FLEET_FILE="$W/fleet.yaml" sh "$W/bin/status-fleet-watch.sh" "$@" 2>&1; }
rcpt() { jq -r '[.status] + .subjects | join(",")' "$CFG/cache/checks/status.fleet-watch.json" 2>/dev/null || echo none; }

t_section "an alert becomes a receipt, once"
report "$(alert alpha ci),$(alert beta lint)" 1
CLAUDE_CONFIG_DIR="$CFG" HARBOR_SCOPE_FLEET_CONTROLLER_BIN="$W/orch" HARBOR_SCOPE_FLEET_FILE="$W/fleet.yaml" sh "$W/bin/status-fleet-watch.sh" >/dev/null 2>&1; _rc=$?
t_eq "a new alert exits 1" 1 "$_rc"
rm -rf "$CFG/cache"; out="$(run)"
t_eq "the receipt is red over the subjects" "red,alpha ci,beta lint" "$(rcpt)"
t_has "the report names the new alerts" "$out" "2 alert(s): 2 new, 0 fixed, 0 standing"
t_has "...by project and category" "$out" "new      alpha ci"
t_has "one checks.log line for a run that changed something" "$(cat "$CFG/cache/checks.log")" "[check:status.fleet-watch]"
t_has "the controller was asked for --json, --changed-only, --interval 3600 and the lint gate" "$(tail -n 1 "$W/calls")" "watch --fleet $W/fleet.yaml --json --changed-only --interval 3600 --task lint"
t_hasnt "...and never for a webhook, in any call" "$(cat "$W/calls")" "webhook"
out="$(run)"
t_has "the same alerts again: nothing new" "$out" "nothing new"
CLAUDE_CONFIG_DIR="$CFG" HARBOR_SCOPE_FLEET_CONTROLLER_BIN="$W/orch" HARBOR_SCOPE_FLEET_FILE="$W/fleet.yaml" sh "$W/bin/status-fleet-watch.sh" >/dev/null 2>&1; _rc=$?
t_eq "...and exit 0" 0 "$_rc"
t_eq "...while the receipt stays red until they are fixed" "red,alpha ci,beta lint" "$(rcpt)"
report "$(alert alpha ci)" 1
out="$(run)"
t_has "one fixed" "$out" "1 alert(s): 0 new, 1 fixed, 1 standing"
report "" 0
out="$(run)"
t_eq "a clean pass writes a green receipt" "green" "$(rcpt)"
t_has "...and reports the last alert fixed" "$out" "fixed    alpha ci"

t_section "a pass that judged nothing is never green"
printf '2\n' > "$W/rc"; report "" 2
out="$(run)"; t_eq "watch exit 2 (no fleet found): stood-down" "stood-down" "$(rcpt)"
t_has "...and says what to run" "$out" "watch judged nothing (exit 2)"
printf '{"checks":[]}\n' > "$W/report.json"; printf '0\n' > "$W/rc"
run >/dev/null; t_eq "output with no alert list: stood-down" "stood-down" "$(rcpt)"
report "" 0
out="$(CLAUDE_CONFIG_DIR="$CFG" HARBOR_SCOPE_FLEET_CONTROLLER_BIN="$W/none" HARBOR_SCOPE_FLEET_FILE="$W/fleet.yaml" sh "$W/bin/status-fleet-watch.sh" 2>&1)"
t_has "no controller binary: says so" "$out" "no fleet controller binary"
t_eq "...and a stood-down receipt" "stood-down" "$(rcpt)"

t_section "--if-due: one pass an hour"
rm -f "$W/calls" "$CFG/cache/status-fleet-watch.stamp"
run --if-due >/dev/null; run --if-due >/dev/null; run --if-due >/dev/null
t_eq "three ticks, one pass" 1 "$(wc -l < "$W/calls" | tr -d ' ')"
touch -t 202001010000 "$CFG/cache/status-fleet-watch.stamp"
run --if-due >/dev/null
t_eq "a stamp older than the hour runs again" 2 "$(wc -l < "$W/calls" | tr -d ' ')"
run >/dev/null
t_eq "without --if-due it always runs" 3 "$(wc -l < "$W/calls" | tr -d ' ')"

t_section "a hung controller is cut off"
printf '#!/bin/sh\nsleep 30\n' > "$W/hang"; chmod +x "$W/hang"
_t0="$(date +%s)"
out="$(CLAUDE_CONFIG_DIR="$CFG" HARBOR_SCOPE_FLEET_CONTROLLER_BIN="$W/hang" HARBOR_SCOPE_FLEET_FILE="$W/fleet.yaml" sh "$W/bin/status-fleet-watch.sh" --timeout 1 2>&1)"; _rc=$?
_t1="$(date +%s)"
t_eq "the bound kills it: exit 3" 3 "$_rc"
t_eq "...in a few seconds, not thirty" yes "$([ $((_t1 - _t0)) -lt 15 ] && echo yes || echo no)"
t_eq "...and the receipt is stood-down" "stood-down" "$(rcpt)"

t_section "the snapshot refresher is what calls it"
R="$T_TMP/r"; mkdir -p "$R/bin" "$R/cfg" "$R/cache"
cp "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/status-fleet-snapshot-refresh.sh" "$R/bin/"
printf '#!/bin/sh\nprintf "[{\\"id\\":1}]"\n' > "$R/orch"; chmod +x "$R/orch"
printf 'printf "%%s\\n" "$*" >> "%s/watch-calls"\n' "$R" > "$R/bin/status-fleet-watch.sh"
CLAUDE_CONFIG_DIR="$R/cfg" HARBOR_SCOPE_CACHE_DIR="$R/cache" HARBOR_SCOPE_FLEET_CONTROLLER_BIN="$R/orch" HARBOR_SCOPE_FLEET_FILE="$R/fleet.yaml" \
  sh "$R/bin/status-fleet-snapshot-refresh.sh" >/dev/null 2>&1
t_eq "one refresh calls it with --if-due" "--if-due" "$(cat "$R/watch-calls" 2>/dev/null || echo none)"
t_eq "...after writing the snapshot" "[{\"id\":1}]" "$(cat "$R/cache/fleet-snapshot.json")"
rm -f "$R/bin/status-fleet-watch.sh"
t_exit "a box without the script still refreshes" 0 env CLAUDE_CONFIG_DIR="$R/cfg" HARBOR_SCOPE_CACHE_DIR="$R/cache" HARBOR_SCOPE_FLEET_CONTROLLER_BIN="$R/orch" HARBOR_SCOPE_FLEET_FILE="$R/fleet.yaml" sh "$R/bin/status-fleet-snapshot-refresh.sh"
t_done
