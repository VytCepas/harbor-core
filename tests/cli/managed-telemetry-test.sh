#!/usr/bin/env sh
# managed-telemetry.sh (harbor#1181 lane 6): merges the five telemetry env keys without clobbering another
# installer's keys, sets no content flag, refuses while no receiver is installed, and removes only its own keys.
. "$(dirname "$0")/../lib/core.sh"; t_init
S="$(cd "$(dirname "$0")/../.." && pwd)/bin/managed-telemetry.sh"
M="$T_TMP/m/managed-settings.json"; P="$T_TMP/receiver.plist"
run() { HARBOR_MANAGED_SETTINGS="$M" HARBOR_RECEIVER_PLIST="$P" sh "$S" "$@" >/dev/null 2>&1; echo $?; }
key() { jq -c "$1" "$M" 2>/dev/null; }

t_eq "no receiver installed: refused" 1 "$(run)"
t_eq "and nothing written" no "$([ -e "$M" ] && echo yes || echo no)"
: > "$P"; mkdir -p "$T_TMP/m"
printf '{"cleanupPeriodDays":365,"env":{"KEEP_ME":"x"}}\n' > "$M"
t_eq "with a receiver it installs" 0 "$(run)"
t_eq "the endpoint is the local receiver, JSON over HTTP" '"http://127.0.0.1:4318/v1/logs" "http/json"' \
  "$(key .env.OTEL_EXPORTER_OTLP_LOGS_ENDPOINT) $(key .env.OTEL_EXPORTER_OTLP_PROTOCOL)"
t_eq "telemetry is on" '"1"' "$(key .env.CLAUDE_CODE_ENABLE_TELEMETRY)"
t_eq "no content flag is set" 0 "$(jq -r '.env | keys[]' "$M" | grep -c -E 'USER_PROMPTS|ASSISTANT|TOOL_DETAILS|TOOL_CONTENT|RAW_API')"
t_eq "another installer's keys survive, inside env and out" '"x" 365' "$(key .env.KEEP_ME) $(key .cleanupPeriodDays)"
t_has "a dry run prints, and writes nothing" "$(HARBOR_MANAGED_SETTINGS="$M" HARBOR_RECEIVER_PLIST="$P" sh "$S" --dry-run 2>/dev/null)" 'OTEL_LOGS_EXPORTER'
t_eq "uninstall exits 0" 0 "$(run --uninstall)"
t_eq "and leaves exactly what was there before" '{"cleanupPeriodDays":365,"env":{"KEEP_ME":"x"}}' "$(key .)"
printf '{}\n' > "$M"; run >/dev/null; run --uninstall >/dev/null
t_eq "an env it created and then emptied is removed, not left as {}" '{}' "$(key .)"
printf 'not json' > "$M"
t_eq "a non-object file is refused and untouched" "1 not json" "$(run) $(cat "$M")"
t_done
