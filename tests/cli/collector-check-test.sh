#!/usr/bin/env sh
# collector-check.sh (harbor#1181 lane 5): stood down with no collector, green on a fresh clean heartbeat, red on a
# stale one, an unreadable source or a new event, and a new event is reported once, not on every run after.
. "$(dirname "$0")/../lib/core.sh"; t_init
K="$(cd "$(dirname "$0")/../.." && pwd)/bin/collector-check.sh"
CF="$T_TMP/cfg"; ST="$T_TMP/store"; mkdir -p "$CF/cache"
run() { CLAUDE_CONFIG_DIR="$CF" HARBOR_COLLECTOR_STORE="$ST" HARBOR_RECEIPTS="$CF/cache/checks" sh "$K" >/dev/null 2>&1; echo $?; }
rec() { jq -r .status "$CF/cache/checks/collector.health.json" 2>/dev/null; }
stat_json() { mkdir -p "$ST"; printf '{"ts":"x","files":3,"bytes_this_pass":0,"unreadable":%s,"events_total":%s}\n' "$1" "$2" > "$ST/status.json"; }

t_eq "no collector: exit 0" 0 "$(run)"
t_eq "and the receipt stands down" stood-down "$(rec)"
stat_json 0 0
t_eq "a fresh clean heartbeat is green" 0 "$(run)"
t_eq "green receipt" green "$(rec)"
touch -t 202001010000 "$ST/status.json"
t_eq "a stale heartbeat is red" 1 "$(run)"
t_has "and says so in checks.log" "$(cat "$CF/cache/checks.log")" '[check:collector.health]'
touch "$ST/pass.started"
t_eq "a pass that started recently is alive, however old the last end is" 0 "$(run)"
touch -t 202001010000 "$ST/pass.started"
t_eq "...and a pass that started long ago and never ended is stale" 1 "$(run)"
rm -f "$ST/pass.started"
stat_json 1 0
t_eq "an unreadable source is red" 1 "$(run)"
stat_json 0 2
t_eq "a new event is red" 1 "$(run)"
t_eq "and red once: the same events next run are green" 0 "$(run)"
stat_json 0 3
t_eq "one more event is red again" 1 "$(run)"
_b="$(grep -c unreadable-source "$CF/cache/checks.log")"
stat_json 1 3; run >/dev/null; run >/dev/null; run >/dev/null
t_eq "a standing outage is one checks.log line, not one per tick" 1 "$(( $(grep -c unreadable-source "$CF/cache/checks.log") - _b ))"
t_section "the cross-check: client decisions with no guard row (lane 5b)"
D="$(date -u +%Y-%m-%d)"; G="$CF/MEMORY/OBSERVABILITY/h"; mkdir -p "$G"; stat_json 0 3
printf "{\"%s\":{\"claude_code.tool_decision\":25}}\n" "$D" > "$ST/cc-summary.json"
printf "{\"ts\":\"%sT01:00:00Z\",\"d\":\"armed\"}\n" "$D" > "$G/guard-decisions.jsonl"
t_eq "25 client decisions and only a session row is red" 1 "$(run)"
t_has "and names it" "$(jq -r .subjects[] "$CF/cache/checks/collector.health.json" | tr "\n" " ")" guard-silent
printf "{\"ts\":\"%sT01:05:00Z\",\"d\":\"allow\"}\n" "$D" >> "$G/guard-decisions.jsonl"
t_eq "one tool-call row today is green" 0 "$(run)"
printf "{\"%s\":{\"claude_code.tool_decision\":5}}\n" "$D" > "$ST/cc-summary.json"; : > "$G/guard-decisions.jsonl"
t_eq "below the minimum it does not judge" 0 "$(run)"
t_section "the off-host anchor (tier 3)"
rm -f "$ST/cc-summary.json"; stat_json 0 3; printf 'Box-9\n' > "$CF/.helm-obs-host"; mkdir -p "$ST/checkpoints"
printf '# day=2026-10-08\nf1\t10\tabc\n' > "$ST/checkpoints/2026-10-08.tsv"; printf 'SIG\n' > "$ST/checkpoints/2026-10-08.tsv.sig"
t_eq "a published checkpoint is anchored and the run is green" 0 "$(run)"
t_eq "its copy lands in MEMORY/CHECKPOINTS/<host>, beside its signature" "2026-10-08.tsv 2026-10-08.tsv.sig" "$(ls "$CF/MEMORY/CHECKPOINTS/Box-9" | tr '\n' ' ' | sed 's/ $//')"
t_eq "a second run anchors nothing new and stays green" 0 "$(run)"
printf '# day=2026-10-08\nf1\t10\tFORGED\n' > "$ST/checkpoints/2026-10-08.tsv"
t_eq "a signed day rewritten in the store is red" 1 "$(run)"
t_has "and names it" "$(jq -r '.subjects[]' "$CF/cache/checks/collector.health.json" | tr '\n' ' ')" checkpoint-changed
t_eq "the anchored copy keeps the original" abc "$(cut -f3 "$CF/MEMORY/CHECKPOINTS/Box-9/2026-10-08.tsv" | tail -n 1)"
t_done
