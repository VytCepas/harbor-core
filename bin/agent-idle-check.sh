#!/usr/bin/env sh
# agent-idle-check.sh (harbor#1437) — a subagent that is running and has written nothing for an hour (check id agent.idle).
#
#   sh agent-idle-check.sh            report each idle subagent; leave the receipt agent.idle; exit 1 when any is idle
#   sh agent-idle-check.sh --quiet    the receipt and the exit code only
#
# Measured 2026-11-02: a background agent sat idle 7.5 hours waiting on a background run that no longer existed, and nothing
# said so. READ-ONLY over what harbor already records: the event bus (agent.spawn with no agent.done for the same agent id, in
# the last three day files), the session record (~/.local/state/harbor/sessions/<session_id>.json, which exists while the
# session does) and the agent's transcript (<config>/projects/*/<session_id>/subagents/agent-<agent_id>.jsonl). A running agent
# is IDLE when its transcript's mtime (its spawn time when it has none) is older than HARBOR_AGENT_IDLE_SECS (default 3600)
# while its session has a record and no session.stop. Destination: the receipt `cache/checks/agent.idle.json`
# that `lint-findings.sh reconcile` files as finding check/agent.idle (contracts/finding.md); scheduled by launchd
# com.harbor.agent.idle (docs/reference/checks.md, agent.idle), whose Disable lines name the launchctl bootout and the plist.
# platform: macOS-only — launchctl appears only in a fix line the operator reads; the reads (bus, sessions, transcripts) are portable.
# Exit 0 none idle, 1 at least one idle, 2 usage. It kills and messages nothing: ending an agent is the session's.
set -u
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH='' cd -- "$HERE" && pwd)"
. "$HERE/library-log.sh"
. "$HERE/library-fs.sh"
log_init agent-idle
ID='[check:agent.idle]'
QUIET=0
case "${1-}" in -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; '') ;; --quiet) QUIET=1 ;; *) echo "agent-idle-check: usage: agent-idle-check.sh [--quiet]" >&2; exit 2 ;; esac
command -v jq >/dev/null 2>&1 || { log_fail "$ID jq is required"; log_fix "$(pkg_hint jq)"; log_end || :; exit 1; }
BUS="${HARBOR_EVENT_DIR:-$HOME/.local/state/harbor/events}"
STATE="${HARBOR_STATUS_DIR:-$HOME/.local/state/harbor}"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
MAX="${HARBOR_AGENT_IDLE_SECS:-3600}"
case "$MAX" in ''|*[!0-9]*) MAX=3600 ;; esac
NOW="$(date +%s)"
mtime_of() { fs_mtime "$1"; }
T="$(mktemp -d "${TMPDIR:-/tmp}/agent-idle.XXXXXX")" || exit 1
trap 'rm -rf "$T"' EXIT INT TERM HUP

# The last three day files (the bus keeps 14 days; an agent older than that is not a live one).
FILES="$(find "$BUS" -maxdepth 1 -name '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].jsonl' 2>/dev/null | sort | tail -3)"
if [ -z "$FILES" ]; then
  log_ok "$ID no event bus here ($BUS): no agent to judge"
  log_receipt "$(receipt_dir)" agent.idle green || log_warn "$ID no receipt written"
  log_end; exit $?
fi
# agent id, session id, spawn epoch: spawned, not done, its session not stopped since.
# shellcheck disable=SC2086 # FILES: day-file paths, one per word, none holding a space
cat $FILES | jq -R 'fromjson? | select(.kind == "agent.spawn" or .kind == "agent.done" or .kind == "session.stop")' | jq -rs '
  ([.[] | select(.kind == "agent.done") | .subject] | unique) as $done
  | ([.[] | select(.kind == "session.stop") | {s: .subject, t: .ts}]) as $stops
  | .[] | select(.kind == "agent.spawn") | select(.subject as $a | ($done | index($a)) | not)
  | . as $sp | select(([$stops[] | select(.s == ($sp.data.session_id // "") and .t >= $sp.ts)] | length) == 0)
  | [.subject, (.data.session_id // ""), ((.ts | fromdateiso8601?) // 0)] | @tsv' > "$T/running" 2>/dev/null || {
  log_fail "$ID could not read the event bus at $BUS"; log_fix "ls -l '$BUS'"; log_end || :; exit 1; }

n=0; idle_list=""
while IFS='	' read -r aid sid spawned; do
  [ -n "$aid" ] || continue
  case "$aid$sid" in *[!A-Za-z0-9._:-]*) continue ;; esac   # an id is [A-Za-z0-9._:-]; nothing else reaches find
  [ -n "$sid" ] && [ -f "$STATE/sessions/$sid.json" ] || continue       # no session record: the session is gone
  n=$((n + 1))
  tr_f="$(find "$CFG/projects" -maxdepth 4 -name "agent-$aid.jsonl" -path "*/$sid/subagents/*" 2>/dev/null | head -1)"
  last="$spawned"
  if [ -n "$tr_f" ]; then _m="$(mtime_of "$tr_f")"; [ -z "$_m" ] || last="$_m"; fi
  idle=$((NOW - last))
  [ "$idle" -gt "$MAX" ] || continue
  s8="$(printf '%s' "$sid" | cut -c1-8)"
  idle_list="$idle_list $s8/$aid:$((idle / 60))m"
  if [ "$QUIET" != 1 ]; then
    log_fail "$ID agent $aid of session $s8 is running and has written nothing for $((idle / 60)) minutes"
    log_fix "ask that session what it waits on, or end the agent (the session's own act)"
  fi
done < "$T/running"

if [ -z "$idle_list" ]; then
  log_ok "$ID $n running subagent(s) in a live session, none idle over $((MAX / 60)) minutes"
  log_receipt "$(receipt_dir)" agent.idle green || log_warn "$ID no receipt written"
else
  # shellcheck disable=SC2086 # one subject per word, none holding a space
  log_receipt "$(receipt_dir)" agent.idle red $idle_list || log_warn "$ID no receipt written"
fi
log_end || :
[ -z "$idle_list" ]; exit $?   # the exit is the finding, also under --quiet, which logs no FAIL line
