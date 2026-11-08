#!/usr/bin/env sh
# member-post.sh (harbor#1278) — after a call on a member laptop: closes what member-dispatch.sh opened. Never blocks, prints nothing.
#   <hook json> | sh member-post.sh     PostToolUse, PostToolUseFailure and Stop, told apart by hook_event_name
#
# A record is HUB_STATE/open/<tool_use_id>: session, asked 0|1, rule, tier, target, request id or -. Either post event means the person
# said yes and the call ran, so an ask closes as `proceeded` and an approval is spent. No event fires when a person says no (F21), so at
# Stop an open ask of this session is `not-run`, which is weaker than "chose to wait"; its approval is kept, since that call never ran (F8).
set -eu
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH='' cd -- "$HERE" && pwd)"
. "$HERE/library-log.sh"
. "$HERE/library-hub.sh"
log_init member-post
case "${1:-}" in -h|--help) sed -n '2,3p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
trap 'exit 0' EXIT
hub_env_clean

TAB="$(printf '\t')"
OPEN="$(hub_state_dir)/open"
event() { sh "$HERE/hub-events.sh" record "$@" </dev/null >/dev/null 2>&1 || :; }

close_ran() { # <record-file>
  IFS="$TAB" read -r _s _asked _rule _tier _target _rid < "$1" || :
  rm -f "$1"
  [ "${_asked:-0}" != 1 ] || event ask rule="$_rule" tier="$_tier" target="$_target" outcome=proceeded count=1
  case "${_rid:--}" in
    -) ;;
    *) sh "$HERE/hub-approval.sh" consume "$_rid" </dev/null >/dev/null 2>&1 || :
       event request id="$_rid" rule="$_rule" tier="$_tier" target="$_target" outcome=used ;;
  esac
}

close_unrun() { # <session>
  for _f in "$OPEN"/*; do
    [ -f "$_f" ] || continue
    IFS="$TAB" read -r _s _asked _rule _tier _target _rid < "$_f" || :
    [ "$_s" = "$1" ] || continue
    rm -f "$_f"
    [ "${_asked:-0}" != 1 ] || event ask rule="$_rule" tier="$_tier" target="$_target" outcome=not-run count=1
  done
}

IN="$(cat)" || exit 0
EVENT="$(printf '%s' "$IN" | jq -r '.hook_event_name // ""' 2>/dev/null)" || exit 0
case "$EVENT" in
  PostToolUse|PostToolUseFailure)
    ID="$(printf '%s' "$IN" | jq -r '.tool_use_id // ""')" || exit 0
    case "$ID" in ''|*[!A-Za-z0-9_-]*) exit 0 ;; esac
    [ ! -f "$OPEN/$ID" ] || close_ran "$OPEN/$ID" ;;
  Stop)
    SESSION="$(printf '%s' "$IN" | jq -r '.session_id // ""')" || exit 0
    [ -z "$SESSION" ] || close_unrun "$SESSION" ;;
esac
exit 0
