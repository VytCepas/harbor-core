#!/usr/bin/env sh
# harbor#1181 end to end: every lane together, in one sandbox config dir, through the scenarios the epic exists for.
# Same uid throughout: the second-uid boundary, sudo, launchd and a live Claude Code exporter are NOT exercised here
# (docs/design/telemetry.md lists what only an install on the box can show).
. "$(dirname "$0")/../../lib/core.sh"; t_init
R="$(cd "$(dirname "$0")/../../.." && pwd)"; B="$R/bin"
CF="$T_TMP/cfg"; mkdir -p "$CF/bin"
cp "$B/library-admission.sh" "$B/floor-observe.sh" "$B/library-log.sh" "$B/audit-stream-lib.sh" "$B/library-fs.sh" "$CF/bin/"
printf '#!/bin/sh\n. "${0%%/*}/library-admission.sh"; FLOOR_OBS_SUBJECT="$2" FLOOR_TOOL=Bash floor_log_decision bash "$1" pipe-to-shell.flat\n' > "$CF/bin/guard-stub.sh"
ST="$T_TMP/collector"; BUS="$T_TMP/bus"; mkdir -p "$BUS"; KEY="$T_TMP/keys/release.key"
session() { CLAUDE_CONFIG_DIR="$CF" sh "$CF/bin/floor-observe.sh" </dev/null >/dev/null 2>&1; }
guard() { _gn=$((${_gn:-0} + 1)); CLAUDE_CONFIG_DIR="$CF" sh "$CF/bin/guard-stub.sh" "$1" "echo e2e-command-$_gn" >/dev/null 2>&1; }
H="$(. "$B/library-admission.sh" 2>/dev/null; floor_host_token)"; O="$CF/MEMORY/OBSERVABILITY"; OH="$O/$H"; L="$OH/guard-decisions.jsonl"
collect() { HARBOR_COLLECTOR_SRC="$O:$BUS" HARBOR_COLLECTOR_STORE="$ST" sh "$B/audit-collector.sh" "$@" >/dev/null 2>&1; echo $?; }
health() { CLAUDE_CONFIG_DIR="$CF" HARBOR_COLLECTOR_STORE="$ST" HARBOR_CHECK_RECEIPTS="$CF/cache/checks" sh "$B/audit-collector-check.sh" >/dev/null 2>&1; echo $?; }
events() { grep -c "\"kind\":\"$1\"" "$ST/events.jsonl" 2>/dev/null | tr -d ' '; }

t_section "1. a session starts and the floor records"
session
t_eq "the host dir is sealed 0500 for the session" "dr-x------" "$(ls -ld "$OH" | cut -c1-10)"
t_eq "the stream root inside it is writable" "drwx------" "$(ls -ld "$OH/streams" | cut -c1-10)"
guard allow; guard block; guard allow
t_eq "three guard calls are three ledger rows (plus the armed row)" 3 "$(grep -vc '"d":"armed"' "$L")"
t_eq "a stream line is written mid-session" 0 "$(CLAUDE_CONFIG_DIR="$CF" HARBOR_WRITER=e2e sh -c '. "$1/library-log.sh"; log_init e2e; HERE="$1"; . "$1/audit-stream-lib.sh"; harbor_emit fleet.snapshots "{\"repos\":3}"' _ "$CF/bin" >/dev/null 2>&1; echo $?)"
F="$(find "$OH/streams/fleet.snapshots" -name '*.jsonl' | head -n 1)"
t_eq "and its chain verifies" "" "$(. "$B/library-log.sh"; log_init v; HERE="$B"; . "$B/audit-stream-lib.sh"; stream_verify "$F")"

t_section "2. the collector copies everything, and survives rotation without a false alarm"
printf '{"id":"e1","ts":"2026-10-09T10:00:00Z","kind":"approval.open","subject":"a1","data":{}}\n' > "$BUS/2026-10-09.jsonl"
t_eq "a first pass" 0 "$(collect)"
t_eq "the guard rows and the bus are in the store" yes "$(cat "$ST"/data/*.jsonl | grep -q '"d":"block"' && cat "$ST"/data/*.jsonl | grep -q approval.open && echo yes || echo no)"
chmod 0700 "$OH"; head -c 5300000 /dev/zero | tr '\0' x >> "$L"; session   # oversize: the next SessionStart rotates
chmod 0700 "$OH"; head -c 5300000 /dev/zero | tr '\0' y >> "$L"; session   # and again: the first .1 is archived
t_eq "two rotations leave one archived generation" 1 "$(find "$OH/archive" -name 'guard-decisions.*.jsonl' | grep -c .)"
t_eq "a pass after rotation raises no tamper event" "0 0" "$(collect >/dev/null; events truncated) $(events edited)"
t_eq "and the check is green" 0 "$(health)"
guard allow; collect >/dev/null

t_section "3. tampering is caught, once"
chmod 0700 "$OH"; : > "$L"; chmod 0500 "$OH"
collect >/dev/null; collect >/dev/null
t_eq "a truncated ledger is one truncated event, however many passes see it" 1 "$(events truncated)"
t_eq "the check turns red" 1 "$(health)"
t_eq "and writes one checks.log line" 1 "$(grep -c '\[check:audit.collector-health\]' "$CF/cache/checks.log")"
t_eq "the next run, nothing new: green again" 0 "$(health)"
t_eq "the store still holds the truncated rows" yes "$(cat "$ST"/data/*.jsonl | grep -q '"d":"block"' && echo yes || echo no)"

t_section "4. signed checkpoints"
mkdir -p "$ST/key"; ssh-keygen -q -t ed25519 -N '' -C collector -f "$ST/key/collector" >/dev/null 2>&1
t_eq "a day is signed" 0 "$(collect --checkpoint 2026-10-09)"
t_eq "and verifies" 0 "$(collect --verify 2026-10-09)"
_d="$(ls "$ST"/data/*.jsonl | head -n 1)"; chflags nouappnd "$_d" 2>/dev/null || :; printf Z | dd of="$_d" bs=1 seek=0 conv=notrunc 2>/dev/null   # as root would: flag off, then edit
t_eq "an edit inside the store breaks it" 1 "$(collect --verify 2026-10-09)"

t_section "5. Claude Code's own telemetry, and a silent floor"
D="$(date -u +%Y-%m-%d)"; NS="$(( $(date -u +%s) ))000000000"
i=0; printf '{"resourceLogs":[{"scopeLogs":[{"logRecords":[' > "$T_TMP/otlp.json"
while [ "$i" -lt 25 ]; do [ "$i" -eq 0 ] || printf ',' >> "$T_TMP/otlp.json"
  printf '{"timeUnixNano":"%s","attributes":[{"key":"event.name","value":{"stringValue":"claude_code.tool_decision"}},{"key":"prompt","value":{"stringValue":"SECRET"}}]}' "$NS" >> "$T_TMP/otlp.json"; i=$((i + 1)); done
printf ']}]}]}\n' >> "$T_TMP/otlp.json"
t_eq "25 client decisions are received" 25 "$(python3 -I "$B/audit-otlp-receiver.py" --ingest "$T_TMP/otlp.json" --store "$ST" 2>/dev/null)"
t_eq "no prompt text was kept" 0 "$(cat "$ST"/cc/*.jsonl | grep -c SECRET)"
chmod 0500 "$OH"; guard allow   # a writable host dir is refused by design: the swap guard
t_eq "with guard rows today, the cross-check is quiet" 0 "$(collect >/dev/null; health >/dev/null; health)"
chmod 0700 "$OH"; grep '"d":"armed"' "$L" > "$T_TMP/armed" || :; cat "$T_TMP/armed" > "$L"; rm -f "$OH"/guard-decisions.jsonl.1
t_eq "with only session rows today, it is red: guard-silent" 1 "$(health)"
t_has "and says so" "$(jq -r '.subjects[]' "$CF/cache/checks/audit.collector-health.json" | tr '\n' ' ')" guard-silent

t_section "6. a release"
t_eq "the guard ledger exports through the scrub gate" 0 "$(python3 -I "$B/audit-stream-export.py" guard.decisions --out "$T_TMP/rel" --cfg "$CF" --key-file "$KEY" >/dev/null 2>&1; echo $?)"
find "$OH" -name "guard-decisions*.jsonl*" -type f -exec cat {} + 2>/dev/null | jq -r "select(type==\"object\") | .h // empty" 2>/dev/null | grep -v "^-$" | sort -u > "$T_TMP/raw-h"
t_eq "the ledger had raw digests to hide (control)" yes "$([ -s "$T_TMP/raw-h" ] && echo yes || echo no)"
t_eq "and not one of them is in the release" 0 "$(grep -c -F -f "$T_TMP/raw-h" "$T_TMP/rel/guard.decisions.jsonl" || true)"
chmod 0700 "$OH"; printf '{"v":1,"ts":"%sT10:00:00Z","stream":"fleet.snapshots","attrs":{"who":"%s"}}\n' "$D" "$(id -un)" >> "$F"
t_eq "a planted user name stops the release" 1 "$(python3 -I "$B/audit-stream-export.py" fleet.snapshots --out "$T_TMP/rel2" --cfg "$CF" --key-file "$KEY" >/dev/null 2>&1; echo $?)"

t_section "7. the reports"
printf '{"id":"e2","ts":"2026-10-09T10:05:00Z","kind":"approval.close","subject":"a1","data":{}}\n' >> "$BUS/2026-10-09.jsonl"
t_eq "approval latency comes out of the bus" 300 "$(sh "$B/status-telemetry-report.sh" approvals --bus "$BUS" 2>/dev/null | awk -F'\t' '$1=="a1"{print $4}')"
chmod -R u+w "$CF" 2>/dev/null || :
chflags -R nouappnd "$ST" 2>/dev/null || :   # append-only files cannot be unlinked: let the temp dir go
t_done
