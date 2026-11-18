#!/usr/bin/env sh
# hub-events.sh (harbor#1278) — the only sender of member events. Closed vocabulary, contracts/hub.md "Events".
#   sh hub-events.sh record <kind> <key=value>...   validates, appends to HUB_STATE/outbox.jsonl (activity and session: tally.jsonl,
#                                                   ts the day, folded in place when full). A record that fails is dropped
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
# activity and session (D9) come once per call, so they have a file of their own: a busy day can't crowd a refusal out of the outbox.
TALLY="$HS/tally.jsonl"
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

usage() { sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
drop() { printf x >> "$DROPPED" 2>/dev/null || :; }
work() { W="$(mktemp -d "${TMPDIR:-/tmp}/hub-events.XXXXXX")"; }

cmd_record() {
  hub_is_member || exit 0
  [ $# -ge 1 ] || usage
  _kind="$1"; shift
  (umask 077; mkdir -p "$HS") 2>/dev/null || exit 0
  work || exit 0
  # D4: a count per person is kept per day, everything else per hour.
  case "$_kind" in
    # R11: no count is kept, let alone sent, until IT has the signed receipt of the notice. Not a drop: nothing was refused.
    activity|session) notice_received || exit 0; _ts="$(date -u +%Y-%m-%dT00:00:00Z)"; _dst="$TALLY" ;;
    *) _ts="$(date -u +%Y-%m-%dT%H:00:00Z)"; _dst="$OUTBOX" ;;
  esac
  # ts, v, member and kind are this script's to set: passed in, they become an unknown key and the validator refuses them.
  jq -cn --arg kind "$_kind" --arg ts "$_ts" --arg m "$MEMBER" '
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
  if [ -f "$_dst" ]; then _size="$(wc -c < "$_dst" | tr -d ' ')"; fi
  if [ "$_size" -ge "$OUTBOX_MAX" ] && [ "$_dst" = "$TALLY" ]; then
    fold_tally || :
    _size=0; if [ -f "$_dst" ]; then _size="$(wc -c < "$_dst" | tr -d ' ')"; fi
  fi
  [ "$_size" -lt "$OUTBOX_MAX" ] || { drop; exit 0; }
  cat "$W/event.json" >> "$_dst" 2>/dev/null || drop
  exit 0
}

# fold_tally: a full tally folded in place to one line per distinct count, so a day of calls costs what its kinds of call cost.
# The rename gives concurrent records a fresh file; a fold that died is picked up by the next one after two minutes.
fold_tally() {
  mkdir "$HS/tally.lock" 2>/dev/null || return 1
  if ! mv "$TALLY" "$HS/tally.folding.$$" 2>/dev/null; then rmdir "$HS/tally.lock" 2>/dev/null; return 1; fi
  find "$HS" -maxdepth 1 -name 'tally.folding.*' ! -name "tally.folding.$$" -mmin +2 -exec cat {} + >> "$HS/tally.folding.$$" 2>/dev/null || :
  find "$HS" -maxdepth 1 -name 'tally.folding.*' ! -name "tally.folding.$$" -mmin +2 -exec rm -f {} + 2>/dev/null || :
  jq -R -c 'fromjson? // empty' "$HS/tally.folding.$$" 2>/dev/null | jq -s -c --arg m "$MEMBER" "$FOLD | .[]" >> "$TALLY" 2>/dev/null || drop
  rm -f "$HS/tally.folding.$$"; rmdir "$HS/tally.lock" 2>/dev/null || :
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
policy_file() { _pf="$(sh "$HERE/hub-sync.sh" path 2>/dev/null)" || _pf=''; [ -f "$_pf" ] || _pf=/dev/null; printf '%s' "$_pf"; }
heartbeat_event() { # <refusals> <asks> <requests> [sealed]
  _pol="$(policy_file)"
  _floor="$(sh "$HERE/member-integrity.sh" hash 2>/dev/null)" || _floor=''
  case "$_floor" in ????????????????) ;; *) _floor=0000000000000000 ;; esac
  case "$_floor" in *[!0123456789abcdef]*) _floor=0000000000000000 ;; esac
  jq -cs --arg ts "$(date -u +%Y-%m-%dT%H:00:00Z)" --arg m "$MEMBER" --arg floor "$_floor" --arg sealed "${4:-}" \
     --argjson r "$1" --argjson a "$2" --argjson q "$3" '
    (.[0] // {}) as $p
    | {v: 1, kind: "heartbeat", ts: $ts, member: $m, core: (($p.core.commit // "000000000000")[0:12]),
       contract: ($p.core.contract // 0), floor: $floor, serial: ($p.serial // 0), mode: ($p.rollout.mode // "enforce"),
       refusals: $r, asks: $a, requests: $q, packs: [($p.packs // [])[].id]}
      + (if $sealed != "" then {sealed: $sealed} else {} end)' "$_pol"
}

# ── the logs payload (harbor#1278, "Log scope", level 2; legal/dpia.md R10, R11) ──
# notice_received: IT wrote <managed root>/notice-received after the member's signed receipt. Root-owned, so no agent sets it.
notice_received() { [ -f "$HERE/../notice-received" ] && [ ! -L "$HERE/../notice-received" ]; }
# seal <events-file>: the account's random id and its activity and session counts, encrypted to the loader's age key from the signed
# policy, as base64 on stdout. The id file sits beside the managed root (member-install.sh). Nothing is sealed, and so nothing reaches
# Harbor's logs, without the marker, the key, age and a valid id. The id never goes in an argument: jq reads it from its file.
seal() {
  notice_received || return 1
  command -v age >/dev/null 2>&1 || return 1
  _sr="$(jq -r '.logs.recipient // empty' "$(policy_file)" 2>/dev/null)" || return 1
  case "$_sr" in age1*) ;; *) return 1 ;; esac
  case "$_sr" in *[!0123456789abcdefghijklmnopqrstuvwxyz]*) return 1 ;; esac
  _sid="$HERE/../../harbor-ids/$(id -un).id"
  [ -f "$_sid" ] && [ ! -L "$_sid" ] || return 1
  jq -cn --rawfile id "$_sid" --slurpfile ev "$1" '($id | rtrimstr("\n")) as $i
    | if ($i | test("^[0-9a-f]{32}$")) then {v: 1, id: $i, events: $ev[0]} else error("no id") end' > "$W/seal.json" 2>/dev/null || return 1
  age -r "$_sr" < "$W/seal.json" > "$W/seal.age" 2>/dev/null || return 1
  base64 < "$W/seal.age" | tr -d '\n'
}
SEAL_MAX=100   # sealed counts per comment: with BATCH_MAX clear events it stays inside GitHub's 65536 characters

# fold: one line per distinct fact, counts summed, so a noisy session costs what its distinct rules cost. Any heartbeat in the
# stream is dropped: this sender builds the one that goes out, and only this member's events pass.
FOLD='
  map(select(type == "object" and .kind != "heartbeat" and .member == $m))
  | group_by([.kind, .ts, .rule, .tier, .target, .outcome, .id, .check, .tool, .verb_class, .verdict])
  | map(if (.[0] | has("count")) then .[0] + {count: (map(.count | numbers) | add)} else .[0] end)'

# gate: everything leaving passes the validator here too, because the outbox is a user-owned file. A whole-batch pass is the
# usual path; on a failure each event is judged alone and only the bad ones go.
gate() { # <array-file> [board] -> the same file holding only valid events; `board` also refuses activity and session in clear
  _gv="${2:-event}"
  sh "$HERE/hub-format.sh" "$_gv" "$1" 2>/dev/null && return 0
  : > "$W/keep.jsonl"
  _i=0; _len="$(jq 'length' "$1")"
  while [ "$_i" -lt "$_len" ]; do
    jq -c --argjson i "$_i" '.[$i]' "$1" > "$W/one.json"
    if sh "$HERE/hub-format.sh" "$_gv" "$W/one.json" 2>/dev/null; then cat "$W/one.json" >> "$W/keep.jsonl"; else drop; fi
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
  if [ -f "$TALLY" ]; then mv "$TALLY" "$HS/tally.sending.$$"; fi
  cat "$PENDING" "$HS"/outbox.sending.* "$HS"/tally.sending.* 2>/dev/null > "$W/raw.jsonl" || :
  jq -R -c 'fromjson? // empty' "$W/raw.jsonl" > "$W/parsed.jsonl" 2>/dev/null || :
  _lines="$(wc -l < "$W/parsed.jsonl" | tr -d ' ')"
  _raw="$(wc -l < "$W/raw.jsonl" | tr -d ' ')"
  _bad=$((_raw - _lines)); while [ "$_bad" -gt 0 ]; do drop; _bad=$((_bad - 1)); done
  jq -s -c --arg m "$MEMBER" "$FOLD" "$W/parsed.jsonl" > "$W/all.json" || printf '[]' > "$W/all.json"
  gate "$W/all.json"
  # The counts go sealed, never in clear (R10); without the marker they are not kept at all (R11).
  jq -c '[.[] | select(.kind == "activity" or .kind == "session")]' "$W/all.json" > "$W/tally.json"
  jq -c '[.[] | select(.kind != "activity" and .kind != "session")]' "$W/all.json" > "$W/clear.json"
  jq -c --argjson n "$SEAL_MAX" '.[:$n]' "$W/tally.json" > "$W/tally.send.json"
  _sealed="$(seal "$W/tally.send.json")" || _sealed=''
  if [ -n "$_sealed" ]; then jq -c --argjson n "$SEAL_MAX" '.[$n:]' "$W/tally.json" > "$W/tally.rest.json"
  elif notice_received; then cp "$W/tally.json" "$W/tally.rest.json"
  else printf '[]' > "$W/tally.rest.json"; fi

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

  # The marker, and so the receipt, is there but nothing could be sealed: said in clear by a fixed word, the counts kept for the next send.
  if [ -z "$_sealed" ] && notice_received; then
    _extra="$(printf '%s' "$_extra" | jq -c --arg ts "$_ts" --arg m "$MEMBER" '. + [{v: 1, kind: "check", ts: $ts, member: $m, check: "hub-logs-seal", outcome: "failed"}]')"
  fi

  jq -c --argjson x "$_extra" --argjson n "$BATCH_MAX" '(. + $x) | .[:($n - 1)]' "$W/clear.json" > "$W/slice.json"
  jq -c --argjson x "$_extra" --argjson n "$BATCH_MAX" '(. + $x) | .[($n - 1):]' "$W/clear.json" > "$W/rest.json"
  _sum='def n($k): [.[] | select(.kind == $k) | (.count // 1)] | add // 0;'
  _hb="$(heartbeat_event "$(jq "$_sum n(\"refusal\")" "$W/slice.json")" "$(jq "$_sum n(\"ask\")" "$W/slice.json")" \
    "$(jq "$_sum n(\"request\")" "$W/slice.json")" "$_sealed")" || exit 3
  jq -c --argjson h "$_hb" '[$h] + .' "$W/slice.json" > "$W/batch.json"
  gate "$W/batch.json" board

  { printf '```json\n'; cat "$W/batch.json"; printf '```'; } > "$W/comment.md"
  jq -n --rawfile b "$W/comment.md" '{body: $b}' > "$W/comment.json" || exit 3
  _rc=0; board POST "/repos/$HUB/issues/$HB_ISSUE/comments" "$W/comment.json" || _rc=$?
  if [ "$_rc" = 0 ] && status_is 201; then
    jq -c '.[]' "$W/rest.json" "$W/tally.rest.json" > "$W/keep.jsonl"
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
  rm -f "$HS"/outbox.sending.* "$HS"/tally.sending.*
  exit "$_exit"
}

verb="${1:-}"; [ -n "$verb" ] || usage
shift
case "$verb" in
  record) cmd_record "$@" ;;
  send) cmd_send ;;
  --help|-h) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) usage ;;
esac
