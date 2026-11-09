#!/usr/bin/env sh
# hub-digest.sh (harbor#1278) — one digest of the hub's heartbeat issues, in the closed vocabulary of contracts/hub.md. Reads files, prints, writes nothing.
#   sh hub-digest.sh --issues FILE --policy FILE [--now UTC] [--members FILE] [--silent]
#     --issues   JSON array, one entry per heartbeat issue, flattened by the workflow from the API:
#                [{"title":"heartbeat alice","author":"alice","comments":[{"author":"alice","created_at":"2026-11-07T09:00:00Z","body":"```json\n[...]\n```"}]}]
#     --policy   the hub's policy.json (silent_days, approvers, revoked)
#     --now      the time to judge by (default: now); --members one login per line, the people expected, so a member who never sent one shows
#     --silent   print only the logins past silent_days, one per line
# A digest is printed on EVERY run, empty or not: its absence is the signal that the schedule stopped (R19). It holds a fixed word, a login, a time
# this script computed, or a field hub-format.sh event accepted; anything else is counted and never shown. Silent is silent_days or more.
# Exit 0 printed, 2 usage, an unreadable input or a policy that fails hub-format.sh policy (then nothing is printed).
set -eu
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
LOG_FD=2; export LOG_FD
. "$HERE/library-log.sh"
log_init hub-digest
die() { log_fail "$1"; log_nofix "the header of bin/hub-digest.sh"; log_end || :; exit 2; }
usage() { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

ISSUES=""; POLICY=""; NOW=""; MEMBERS=""; SILENT=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --issues) [ "$#" -ge 2 ] || usage; ISSUES="$2"; shift ;;
    --policy) [ "$#" -ge 2 ] || usage; POLICY="$2"; shift ;;
    --now) [ "$#" -ge 2 ] || usage; NOW="$2"; shift ;;
    --members) [ "$#" -ge 2 ] || usage; MEMBERS="$2"; shift ;;
    --silent) SILENT=1 ;;
    *) usage ;;
  esac
  shift
done
[ -n "$ISSUES" ] && [ -n "$POLICY" ] || usage
[ -n "$NOW" ] || NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
case "$NOW" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;; *) die "--now wants UTC as 2026-11-07T08:00:00Z" ;; esac
for _f in "$ISSUES" "$POLICY"; do [ -r "$_f" ] || { die "cannot read $_f"; }; done
[ -z "$MEMBERS" ] || [ -r "$MEMBERS" ] || { die "cannot read $MEMBERS"; }
command -v jq >/dev/null 2>&1 || { die "jq is missing"; }
jq -e 'type == "array"' "$ISSUES" >/dev/null 2>&1 || { die "$ISSUES is not a JSON array"; }
sh "$HERE/hub-format.sh" policy "$POLICY" >/dev/null 2>&1 || { die "$POLICY fails hub-format.sh policy, so silent_days cannot be trusted"; }

T="$(mktemp -d "${TMPDIR:-/tmp}/hub-digest.XXXXXX")" || exit 2
trap 'rm -rf "$T"' EXIT INT TERM

# 1 · the heartbeat issues and each member's own newest comments (20), the event array of each parsed or null.
jq -c '
  .[] | select(type == "object")
  | ((.title // "") | capture("^heartbeat (?<l>[A-Za-z0-9][A-Za-z0-9-]{0,38})$")? // null) as $m
  | select($m != null and ((.author // "") | ascii_downcase) == ($m.l | ascii_downcase))
  | $m.l as $l | (.comments // []) as $all
  # GitHub keeps a login in its own case and the managed setting in the one IT typed; hub-approval.sh folds them the same way.
  | ($all | map(select(type == "object" and ((.author // "") | ascii_downcase) == ($l | ascii_downcase)))) as $own
  | ($own | sort_by(.created_at) | reverse | .[:20]) as $mine
  | {k: "issue", login: $l, foreign: (($all | length) - ($own | length))},
    ($mine[] | {k: "c", login: $l, created_at: .created_at,
                events: ((.body // "" | capture("^\\s*```json\\s*\\n(?<j>[\\s\\S]*?)\\n```\\s*$")? | .j | fromjson? | select(type == "array")) // null)})' \
  "$ISSUES" > "$T/raw" || { die "could not read the issues"; }

# 2 · each comment's events pass hub-format.sh event, and name the author as their member, or the comment is invalid.
: > "$T/checked"; n=0
while IFS= read -r line; do
  case "$line" in
    '{"k":"issue"'*) printf '%s\n' "$line" >> "$T/checked" ;;
    *) n=$((n + 1))
       if printf '%s' "$line" | jq -e '.events != null and (.events | length) > 0 and (.created_at | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))' >/dev/null 2>&1 \
          && printf '%s' "$line" | jq '.events' > "$T/ev.$n" \
          && sh "$HERE/hub-format.sh" event "$T/ev.$n" >/dev/null 2>&1 \
          && [ "$(printf '%s' "$line" | jq '.login as $l | .events | all(.[]; .member == $l)')" = true ]; then
         printf '%s' "$line" | jq -c '. + {ok: true}' >> "$T/checked"
       else
         printf '%s' "$line" | jq -c '{k: "c", login, ok: false}' >> "$T/checked"
       fi ;;
  esac
done < "$T/raw"

# 3 · the members expected: the people with an issue, plus the list when given, less the revoked.
if [ -n "$MEMBERS" ]; then
  jq -R -s -c 'split("\n") | map(select(test("^[A-Za-z0-9][A-Za-z0-9-]{0,38}$")))' "$MEMBERS" > "$T/members"
else printf '[]' > "$T/members"; fi

# 4 · the digest.
jq -s -r --arg now "$NOW" --argjson silent_only "$SILENT" --slurpfile pol "$POLICY" --slurpfile mem "$T/members" '
  ($pol[0]) as $p | ($p.silent_days) as $sd | ($now | fromdateiso8601) as $ns
  | ($p.revoked // []) as $rev
  | ([.[] | select(.k == "issue") | .login] + $mem[0] | unique | map(select(. as $x | $rev | index($x) | not))) as $logins
  | (map(select(.k == "c" and .ok == false)) | length) as $bad
  | (map(select(.k == "issue") | .foreign) | add // 0) as $foreign
  | . as $all
  | ($logins | map(. as $l
      | ($all | map(select(.k == "c" and .login == $l and .ok == true)) | sort_by(.created_at) | reverse) as $cs
      | (($cs | map(.events | map(select(.kind == "heartbeat")) | last) | map(select(. != null)) | first) // null) as $hb
      | (if ($cs | length) == 0 then null else $cs[0].created_at end) as $seen
      | {login: $l, seen: $seen, hb: $hb,
         state: (if $seen == null then "never" elif ($ns - ($seen | fromdateiso8601)) >= ($sd * 86400) then "silent" else "ok" end)})) as $rows
  | if $silent_only == 1 then ($rows | map(select(.state != "ok") | .login) | .[])
    else
      ["harbor-digest: 1",
       "hub: " + $p.hub,
       "date: " + ($now[0:10]),
       "silent_days: " + ($sd | tostring),
       "members: " + ($rows | length | tostring),
       "silent: " + ($rows | map(select(.state != "ok")) | length | tostring),
       "invalid-comments: " + ($bad | tostring),
       "foreign-comments: " + ($foreign | tostring),
       "cc: " + ($p.approval.approvers | map("@" + .) | join(" ")),
       ""]
      + (if ($rows | length) == 0 then ["no member has sent a heartbeat"]
         else ["| member | last seen | core | contract | floor | serial | mode | refusals | asks | requests | state |",
               "|---|---|---|---|---|---|---|---|---|---|---|"]
              + ($rows | map("| " + .login + " | " + (.seen // "-")
                   + " | " + (.hb.core // "-") + " | " + ((.hb.contract // "-") | tostring) + " | " + (.hb.floor // "-")
                   + " | " + ((.hb.serial // "-") | tostring) + " | " + (.hb.mode // "-")
                   + " | " + ((.hb.refusals // "-") | tostring) + " | " + ((.hb.asks // "-") | tostring)
                   + " | " + ((.hb.requests // "-") | tostring) + " | " + .state + " |")) end)
      | .[] end' "$T/checked"
