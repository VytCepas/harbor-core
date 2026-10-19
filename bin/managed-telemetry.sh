#!/usr/bin/env sh
# MANAGED TELEMETRY (harbor#1181 lane 6) — pins Claude Code's own OTLP log events, sent to the collector's receiver
# on 127.0.0.1:4318, in the root-owned managed-settings.json `env`, which no user, project, local or session setting
# overrides. Content stays off: no prompt, response or tool-detail flag is set, and the receiver drops them anyway.
#   sudo sh managed-telemetry.sh              merge the five env keys into any existing managed file
#   sh managed-telemetry.sh --dry-run         print the target path and the merged JSON, write nothing
#   sudo sh managed-telemetry.sh --uninstall  remove exactly those keys, keep the rest
# Refuses while the receiver is not installed (collector-setup.sh): an exporter aimed at nothing is a silent
# config. HARBOR_MANAGED_SETTINGS and HARBOR_RECEIVER_PLIST move the files for tests and are refused under root.
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/log-lib.sh"
log_init managed-telemetry
for v in HARBOR_MANAGED_SETTINGS HARBOR_RECEIVER_PLIST; do
  eval "_v=\${$v:-}"
  if [ "$(id -u)" -eq 0 ] && [ -n "$_v" ]; then
    log_fail "$v is set under root: refusing a caller-chosen path"; log_fix "sudo env -u $v sh $0"; exit 1
  fi
done
if [ -n "${HARBOR_MANAGED_SETTINGS:-}" ]; then FILE="$HARBOR_MANAGED_SETTINGS"
else case "$(uname -s)" in
  Darwin) FILE='/Library/Application Support/ClaudeCode/managed-settings.json' ;;
  *) FILE='/etc/claude-code/managed-settings.json' ;;
esac; fi
RECV="${HARBOR_RECEIVER_PLIST:-/Library/LaunchDaemons/com.harbor.otlp-receiver.plist}"
BASE="$(dirname -- "$FILE")"
MODE=install
for a in "$@"; do case "$a" in
  --dry-run) MODE=dry ;; --uninstall) MODE=uninstall ;;
  -h|--help) awk 'NR<2{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;;
  *) log_fail "unknown argument $a"; log_nofix "sh bin/managed-telemetry.sh --help"; exit 2 ;;
esac; done
command -v jq >/dev/null 2>&1 || { log_fail "jq not found on the pinned PATH ($PATH)"; log_nofix "install jq at /usr/bin"; exit 1; }
ENV='{"CLAUDE_CODE_ENABLE_TELEMETRY":"1","OTEL_LOGS_EXPORTER":"otlp","OTEL_METRICS_EXPORTER":"none",
      "OTEL_EXPORTER_OTLP_PROTOCOL":"http/json","OTEL_EXPORTER_OTLP_LOGS_ENDPOINT":"http://127.0.0.1:4318/v1/logs"}'
if [ "$MODE" = install ] && [ ! -f "$RECV" ]; then
  log_fail "the OTLP receiver is not installed ($RECV): telemetry would be sent to nothing"
  log_fix "sudo sh $HERE/collector-setup.sh, then run this again"; exit 1
fi
CUR='{}'
if [ -f "$FILE" ]; then
  CUR="$(cat "$FILE")"
  printf '%s' "$CUR" | jq -e 'type == "object"' >/dev/null 2>&1 \
    || { log_fail "$FILE is not a JSON object; not touching it"; log_nofix "fix or remove $FILE by hand"; exit 1; }
fi
if [ "$MODE" = uninstall ]; then
  NEW="$(printf '%s' "$CUR" | jq --argjson e "$ENV" '.env = ((.env // {}) | with_entries(select(.key as $k | $e | has($k) | not)))
    | if .env == {} then del(.env) else . end')"
else
  NEW="$(printf '%s' "$CUR" | jq --argjson e "$ENV" '.env = ((.env // {}) + $e)')"
fi
log_note "target: $FILE"
if [ "$MODE" = dry ]; then printf '%s\n' "$NEW"; log_note "dry run: nothing written"; exit 0; fi
if [ -z "${HARBOR_MANAGED_SETTINGS:-}" ] && [ "$(id -u)" -ne 0 ]; then
  log_fail "not root: this file is root-owned by design"
  log_fix "sudo sh $0$([ "$MODE" = uninstall ] && echo ' --uninstall')"; exit 1
fi
mkdir -p "$BASE"
TMPF="$(mktemp "$BASE/.managed-settings.XXXXXX")"; trap 'rm -f "$TMPF"' EXIT
printf '%s\n' "$NEW" > "$TMPF"
if [ "$(id -u)" -eq 0 ]; then grp=wheel; [ "$(uname -s)" = Darwin ] || grp=root; chown root:"$grp" "$TMPF"; fi
chmod 0644 "$TMPF"; mv "$TMPF" "$FILE"; trap - EXIT
# Read back: "telemetry is pinned" closes on the file, not on the write having returned.
_got="$(jq -r '.env.OTEL_EXPORTER_OTLP_LOGS_ENDPOINT // "absent"' "$FILE" 2>/dev/null || echo unreadable)"
_want="http://127.0.0.1:4318/v1/logs"; [ "$MODE" = install ] || _want=absent
[ "$_got" = "$_want" ] || { log_fail "$FILE reads endpoint=$_got after the write, want $_want"; log_nofix "inspect $FILE"; exit 1; }
log_ok "$MODE: $FILE telemetry endpoint=$_got (new sessions only: restart Claude Code)"; log_end
