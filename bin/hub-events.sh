#!/usr/bin/env sh
# hub-events.sh (harbor#1278) — the only sender of member events. Closed vocabulary, contracts/hub.md "Events".
#   sh hub-events.sh record <kind> <key=value>...   validates, appends to HUB_STATE/outbox.jsonl. A record that fails is dropped
#                                                   and counted, never sent. Always exit 0: it runs inside hooks
#   sh hub-events.sh send                           one comment on the member's heartbeat issue, at most every 15 minutes.
#                                                   Exit 0 sent or not due, 3 not sent; the events wait for the next send
# Events are claims from an agent-reachable laptop, not attestation. Only this sender's vocabulary is covered (F29, F30).
set -eu
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/library-hub.sh"
. "$HERE/library-log.sh"
LOG_FD=2
log_init hub-events

HS="$(hub_state_dir)"
MEMBER="${HARBOR_MEMBER_LOGIN:-}"; HUB="${HARBOR_HUB_REPO:-}"
OUTBOX="$HS/outbox.jsonl"; PENDING="$HS/outbox.pending.jsonl"; DROPPED="$HS/dropped"
# R20: 500 content writes an hour is GitHub's limit, so one member sends at most 4. Hours and keys fold before sending.
SEND_EVERY=900
OUTBOX_MAX=1048576    # bytes between sends; past it a record is counted, not kept
BATCH_MAX=250         # events a comment holds, well inside GitHub's 65536 characters
PENDING_MAX=2000      # folded events kept through a long outage
TOKEN_WARN_DAYS=14

W=''; LOCK=''
cleanup() { [ -z "$W" ] || rm -rf "$W"; [ -z "$LOCK" ] || rmdir "$LOCK" 2>/dev/null; :; }
trap cleanup EXIT
trap 'exit 130' INT HUP TERM

usage() { sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
drop() { printf x >> "$DROPPED" 2>/dev/null || :; }
work() { W="$(mktemp -d "${TMPDIR:-/tmp}/hub-events.XXXXXX")"; }

cmd_record() {
  hub_is_member || exit 0
  [ $# -ge 1 ] || usage
  _kind="$1"; shift
  (umask 077; mkdir -p "$HS") 2>/dev/null || exit 0
  work || exit 0
  # ts, v, member and kind are this script's to set: passed in, they become an unknown key and the validator refuses them.
  jq -cn --arg kind "$_kind" --arg ts "$(date -u +%Y-%m-%dT%H:00:00Z)" --arg m "$MEMBER" '
    {v: 1, kind: $kind, ts: $ts, member: $m} + ($ARGS.positional | map(
      (index("=")) as $i
      | if $i == null then {("no-value"): .}
        else .[:$i] as $k | .[$i + 1:] as $x
          | if ($k == "v" or $k == "kind" or $k == "ts" or $k == "member") then {("reserved-" + $k): $x}
            elif ($k == "contract" or $k == "serial" or $k == "refusals" or $k == "asks" or $k == "requests"
                  or $k == "count" or $k == "days_left") then {($k): ($x | tonumber? // $x)}
            elif $k == "packs" then {($k): ($x | split(",") | map(select(length > 0)))}
            else {($k): $x} end
        end) | add // {})' --args "$@" > "$W/event.json" 2>/dev/null || { drop; exit 0; }
  sh "$HERE/hub-format.sh" event "$W/event.json" 2>/dev/null || { drop; exit 0; }
  _size=0
  if [ -f "$OUTBOX" ]; then _size="$(wc -c < "$OUTBOX" | tr -d ' ')"; fi
  [ "$_size" -lt "$OUTBOX_MAX" ] || { drop; exit 0; }
  cat "$W/event.json" >> "$OUTBOX" 2>/dev/null || drop
  exit 0
}

board() { sh "$HERE/hub-board.sh" call "$W" "$@" </dev/null 2>/dev/null; }
status_is() { [ "$(cat "$W/status")" = "$1" ]; }

# The heartbeat issue, made once. The cached number is only a hint: the title and author are checked against GitHub's answer.
heartbeat_issue() {
  _t="heartbeat $MEMBER"
  _n="$(cat "$HS/heartbeat-issue" 2>/dev/null)" || _n=''
  case "$_n" in ''|*[!0-9]*) _n='' ;; esac
  if [ -n "$_n" ]; then
    board GET "/repos/$HUB/issues/$_n" || return 3
    status_is 200 && jq -e --arg t "$_t" '.title == $t' "$W/body" >/dev/null 2>&1 && { HB_ISSUE="$_n"; return 0; }
    case "$(cat "$W/status")" in 401|403|429|5??) return 3 ;; esac
  fi
  board GET "/repos/$HUB/issues?state=all&creator=$MEMBER&sort=created&direction=asc&per_page=100" || return 3
  status_is 200 || return 3
  _n="$(jq -r --arg t "$_t" '[.[] | select(.title == $t)][0].number // empty' "$W/body" 2>/dev/null)" || return 3
  if [ -z "$_n" ]; then
    jq -n --arg t "$_t" --arg m "$MEMBER" '{title: $t, body: ("harbor-heartbeat: 1\nmember: " + $m + "\n")}' > "$W/create.json" || return 3
    board POST "/repos/$HUB/issues" "$W/create.json" || return 3
    status_is 201 || return 3
    _n="$(jq -r .number "$W/body")" || return 3
  fi
  case "$_n" in ''|*[!0-9]*) return 3 ;; esac
  printf '%s\n' "$_n" > "$HS/heartbeat-issue"
  HB_ISSUE="$_n"
}

# Days left from GitHub's own header and Date. An absent header means no alarm, and a 401 still reports the end (F25).
token_days() {
  LC_ALL=C jq -rn --arg e "$(cat "$W/expires")" --arg d "$(cat "$W/date")" '
    def when: (try strptime("%Y-%m-%d %H:%M:%S UTC") catch (try strptime("%Y-%m-%d %H:%M:%S %z") catch null));
    ($e | when) as $x | ($d | try strptime("%a, %d %b %Y %H:%M:%S GMT") catch null) as $n
    | if $x == null or $n == null then empty
      else ((($x | mktime) - ($n | mktime)) / 86400 | floor | if . < 0 then 0 else . end) end' 2>/dev/null
}

# The heartbeat is built here, in a hook the managed tier runs, so a removed floor reads as silence (F30). packs come from the
# signed policy, never a name the member chose (M8). With no policy: serial 0 and the core defaults, which are enforced.
heartbeat_event() { # <refusals> <asks> <requests>
  _pol="$(sh "$HERE/hub-sync.sh" path 2>/dev/null)" || _pol=''
  [ -f "$_pol" ] || _pol=/dev/null
  _floor="$(sh "$HERE/member-integrity.sh" hash 2>/dev/null)" || _floor=''
  case "$_floor" in ????????????????) ;; *) _floor=0000000000000000 ;; esac
  case "$_floor" in *[!0123456789abcdef]*) _floor=0000000000000000 ;; esac
  jq -cs --arg ts "$(date -u +%Y-%m-%dT%H:00:00Z)" --arg m "$MEMBER" --arg floor "$_floor" \
     --argjson r "$1" --argjson a "$2" --argjson q "$3" '
    (.[0] // {}) as $p
    | {v: 1, kind: "heartbeat", ts: $ts, member: $m, core: (($p.core.commit // "000000000000")[0:12]),
       contract: ($p.core.contract // 0), floor: $floor, serial: ($p.serial // 0), mode: ($p.rollout.mode // "enforce"),
       refusals: $r, asks: $a, requests: $q, packs: [($p.packs // [])[].id]}' "$_pol"
}

# fold: one line per distinct fact, counts summed, so a noisy session costs what its distinct rules cost. Any heartbeat in the
# stream is dropped: this sender builds the one that goes out, and only this member's events pass.
FOLD='
  map(select(type == "object" and .kind != "heartbeat" and .member == $m))
  | group_by([.kind, .ts, .rule, .tier, .target, .outcome, .id, .check])
  | map(if (.[0] | has("count")) then .[0] + {count: (map(.count | numbers) | add)} else .[0] end)'

# gate: everything leaving passes the validator here too, because the outbox is a user-owned file. A whole-batch pass is the
# usual path; on a failure each event is judged alone and only the bad ones go.
gate() { # <array-file> -> the same file holding only valid events
  sh "$HERE/hub-format.sh" event "$1" 2>/dev/null && return 0
  : > "$W/keep.jsonl"
  _i=0; _len="$(jq 'length' "$1")"
  while [ "$_i" -lt "$_len" ]; do
    jq -c --argjson i "$_i" '.[$i]' "$1" > "$W/one.json"
    if sh "$HERE/hub-format.sh" event "$W/one.json" 2>/dev/null; then cat "$W/one.json" >> "$W/keep.jsonl"; else drop; fi
    _i=$((_i + 1))
  done
  jq -s -c . "$W/keep.jsonl" > "$1"
}

cmd_send() {
  hub_is_member || exit 0
  case "$MEMBER" in ''|-*|*[!A-Za-z0-9-]*) exit 3 ;; esac
  case "$HUB" in ''|/*|*/|*/*/*|*..*|*[!A-Za-z0-9._/-]*) exit 3 ;; */*) ;; *) exit 3 ;; esac
  (umask 077; mkdir -p "$HS") 2>/dev/null || exit 3
  _now="$(date +%s)"
  _last="$(cat "$HS/last-send" 2>/dev/null)" || _last=''
  case "$_last" in ''|*[!0-9]*) _last=0 ;; esac
  if [ "$_last" -le "$_now" ] && [ $((_now - _last)) -lt "$SEND_EVERY" ]; then exit 0; fi
  find "$HS/send.lock" -maxdepth 0 -mmin +2 -exec rmdir {} + 2>/dev/null || :
  mkdir "$HS/send.lock" 2>/dev/null || exit 0
  LOCK="$HS/send.lock"
  work || exit 3

  heartbeat_issue || exit 3
  _days="$(token_days)" || _days=''

  # The rename gives new records a fresh file while this batch is read. A crash leaves a .sending file the next send picks up.
  if [ -f "$OUTBOX" ]; then mv "$OUTBOX" "$HS/outbox.sending.$$"; fi
  cat "$PENDING" "$HS"/outbox.sending.* 2>/dev/null > "$W/raw.jsonl" || :
  jq -R -c 'fromjson? // empty' "$W/raw.jsonl" > "$W/parsed.jsonl" 2>/dev/null || :
  _lines="$(wc -l < "$W/parsed.jsonl" | tr -d ' ')"
  _raw="$(wc -l < "$W/raw.jsonl" | tr -d ' ')"
  _bad=$((_raw - _lines)); while [ "$_bad" -gt 0 ]; do drop; _bad=$((_bad - 1)); done
  jq -s -c --arg m "$MEMBER" "$FOLD" "$W/parsed.jsonl" > "$W/all.json" || printf '[]' > "$W/all.json"
  gate "$W/all.json"

  # Drops are told by count and never by value, so a refused record can't reach the board through its own report.
  _extra='[]'
  _ts="$(date -u +%Y-%m-%dT%H:00:00Z)"
  if [ -s "$DROPPED" ]; then
    _extra="$(jq -cn --arg ts "$_ts" --arg m "$MEMBER" '[{v: 1, kind: "check", ts: $ts, member: $m, check: "hub-events-dropped", outcome: "failed"}]')"
  fi
  case "$_days" in
    ''|*[!0-9]*) rm -f "$HS/token-days-left" ;;
    *) if [ "$_days" -le "$TOKEN_WARN_DAYS" ]; then
         printf '%s\n' "$_days" > "$HS/token-days-left"
         _extra="$(printf '%s' "$_extra" | jq -c --arg ts "$_ts" --arg m "$MEMBER" --argjson d "$_days" \
           '. + [{v: 1, kind: "token", ts: $ts, member: $m, days_left: $d, outcome: "expiring"}]')"
       else rm -f "$HS/token-days-left"; fi ;;
  esac

  jq -c --argjson x "$_extra" --argjson n "$BATCH_MAX" '(. + $x) | .[:($n - 1)]' "$W/all.json" > "$W/slice.json"
  jq -c --argjson x "$_extra" --argjson n "$BATCH_MAX" '(. + $x) | .[($n - 1):]' "$W/all.json" > "$W/rest.json"
  _sum='def n($k): [.[] | select(.kind == $k) | (.count // 1)] | add // 0;'
  _hb="$(heartbeat_event "$(jq "$_sum n(\"refusal\")" "$W/slice.json")" "$(jq "$_sum n(\"ask\")" "$W/slice.json")" \
    "$(jq "$_sum n(\"request\")" "$W/slice.json")")" || exit 3
  jq -c --argjson h "$_hb" '[$h] + .' "$W/slice.json" > "$W/batch.json"
  gate "$W/batch.json"

  { printf '```json\n'; cat "$W/batch.json"; printf '```'; } > "$W/comment.md"
  jq -n --rawfile b "$W/comment.md" '{body: $b}' > "$W/comment.json" || exit 3
  _rc=0; board POST "/repos/$HUB/issues/$HB_ISSUE/comments" "$W/comment.json" || _rc=$?
  if [ "$_rc" = 0 ] && status_is 201; then
    jq -c '.[]' "$W/rest.json" > "$W/keep.jsonl"
    date +%s > "$HS/last-send"
    rm -f "$DROPPED"
    _exit=0
  else
    # Unsent: back into pending, without the heartbeat, which is rebuilt, and capped against a long outage.
    jq -c --argjson n "$PENDING_MAX" '.[(-$n):] | .[]' "$W/all.json" > "$W/keep.jsonl"
    _over=$(($(jq length "$W/all.json") - PENDING_MAX))
    while [ "$_over" -gt 0 ]; do drop; _over=$((_over - 1)); done
    _exit=3
  fi
  mv "$W/keep.jsonl" "$PENDING"
  rm -f "$HS"/outbox.sending.*
  exit "$_exit"
}

verb="${1:-}"; [ -n "$verb" ] || usage
shift
case "$verb" in
  record) cmd_record "$@" ;;
  send) cmd_send ;;
  --help|-h) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) usage ;;
esac
