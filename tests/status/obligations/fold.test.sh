#!/usr/bin/env sh
# fold.test.sh (harbor#1050) — bin/status-obligations.sh fold: transitions, replay, kill, rollover.
# Every bus is a fixture day file written by hand; no event bus runs here.
. "$(dirname "$0")/../../lib/core.sh"; t_init

BIN="$T_ROOT/bin/status-obligations.sh"
EV="$T_TMP/w/ev"; OB="$T_TMP/w/ob"; NOW=2026-10-06T02:00:00Z; N=0; LAST=""; D=2026-10-06.jsonl
fresh() { rm -rf "$T_TMP/w"; mkdir -p "$EV" "$OB"; N=0; NOW=2026-10-06T02:00:00Z; unset KINDS; }
EMPTY='{}'
ev() { # <ts> <kind> <subject> [data-json] [day-file] — appends one bus line, sets LAST to its id
  N=$((N + 1)); LAST="e$N"
  printf '{"id":"%s","ts":"%s","src":"cli","kind":"%s","subject":"%s","repo":"harbor","cause":"","data":%s}\n' \
    "$LAST" "$1" "$2" "$3" "${4:-$EMPTY}" >> "$EV/${5:-$D}"
}
scenario() { # the bus the kill cases share: a session, its Monitor, a PR, then the stop
  fresh; ev 2026-10-06T01:00:00Z session.start S1; ev 2026-10-06T01:01:00Z tool.background.start S1:T1 '{"tool":"Monitor"}'
  ev 2026-10-06T01:02:00Z pr.opened VytCepas/harbor#9; ev 2026-10-06T01:03:00Z session.stop S1
}
fold() { # the real script, on this bus and this state; combined output
  env HARBOR_EVENT_DIR="$EV" HARBOR_OBLIGATION_DIR="$OB" HARBOR_STATUS_OBLIGATION_NOW="$NOW" HARBOR_STATUS_OBLIGATION_ON_OVERDUE=off \
    ${KINDS:+HARBOR_STATUS_OBLIGATION_KINDS="$KINDS"} ${FAULT:+HARBOR_STATUS_OBLIGATION_FAULT="$FAULT"} sh "$BIN" fold 2>&1
}
cur() { jq -r --arg id "$1" ".obligations[] | select(.id == \$id) | .$2" "$OB/current.json"; }
count() { jq -r '.obligations | length' "$OB/current.json"; }
lines() { wc -l < "$OB/ledger.jsonl" | tr -d ' '; }

t_section "open and close: a terminal event closes the row it names"
fresh; ev 2026-10-06T01:00:00Z session.start S1 '{"title":"harbor night"}'; fold >/dev/null
t_eq "state after start" open "$(cur session:S1 state)"
t_eq "title from data.title" "harbor night" "$(cur session:S1 title)"
t_eq "owner is the session itself" session:S1 "$(cur session:S1 owner)"
t_eq "opened_ts is the event ts" 2026-10-06T01:00:00Z "$(cur session:S1 opened_ts)"
t_eq "a session has no deadline (harbor#1115)" "" "$(cur session:S1 deadline_ts)"
ev 2026-10-06T01:30:00Z session.stop S1; fold >/dev/null
t_eq "state after stop" closed "$(cur session:S1 state)"
t_eq "closed_by is the terminal event id" "$LAST" "$(cur session:S1 closed_by)"
t_eq "closed_ts is the terminal event ts" 2026-10-06T01:30:00Z "$(cur session:S1 closed_ts)"
t_eq "ledger holds both transitions" 2 "$(lines)"

t_section "idempotent: a replay of the same events changes nothing"
fresh; ev 2026-10-06T01:00:00Z session.start S1; ev 2026-10-06T01:01:00Z pr.opened VytCepas/harbor#9 '{"session_id":"S1"}'
ev 2026-10-06T01:02:00Z pr.merged VytCepas/harbor#9; ev 2026-10-06T01:03:00Z session.stop S1; fold >/dev/null
cp "$OB/ledger.jsonl" "$T_TMP/ledger.1"; cp "$OB/current.json" "$T_TMP/current.1"
fold >/dev/null; cmp -s "$OB/ledger.jsonl" "$T_TMP/ledger.1" && t_pass || t_fail "a second fold changed the ledger"
rm "$OB/offset"; fold >/dev/null
cmp -s "$OB/ledger.jsonl" "$T_TMP/ledger.1" && t_pass || t_fail "a fold from offset 0 doubled the ledger"
t_eq "current.json rows survive the replay" "$(jq -c .obligations "$T_TMP/current.1")" "$(jq -c .obligations "$OB/current.json")"
ev 2026-10-06T01:10:00Z pr.opened VytCepas/harbor#9; fold >/dev/null
t_eq "the same subject opened again is a new transition" open "$(cur pr:VytCepas/harbor#9 state)"
t_eq "which makes five" 5 "$(lines)"
rm "$OB/offset"; fold >/dev/null
t_eq "a replay does not close the reopened row with the old merge" open "$(cur pr:VytCepas/harbor#9 state)"
t_eq "or add a line" 5 "$(lines)"

t_section "resume after kill: nothing lost, nothing doubled"
scenario; mkdir -p "$T_TMP/ref/ev" "$T_TMP/ref/ob"; cp "$EV/$D" "$T_TMP/ref/ev/$D"
HARBOR_EVENT_DIR="$T_TMP/ref/ev" HARBOR_OBLIGATION_DIR="$T_TMP/ref/ob" HARBOR_STATUS_OBLIGATION_NOW="$NOW" sh "$BIN" fold >/dev/null 2>&1
t_eq "the unkilled reference holds five transitions" 5 "$(wc -l < "$T_TMP/ref/ob/ledger.jsonl" | tr -d ' ')"
FAULT=before-offset; ( fold ) >/dev/null 2>&1; rc=$?; unset FAULT
t_eq "killed after the ledger, before the offset" 137 "$rc"
t_eq "the kill left no offset" no "$([ -e "$OB/offset" ] && echo yes || echo no)"
t_eq "the kill left its lock behind" yes "$([ -L "$OB/.fold.lock" ] && echo yes || echo no)"
fold >/dev/null; rc=$?
t_eq "the resumed run exits 0" 0 "$rc"
cmp -s "$OB/ledger.jsonl" "$T_TMP/ref/ob/ledger.jsonl" && t_pass || t_fail "resume ledger differs from an unkilled run"
t_eq "resume current.json equals an unkilled run" "$(jq -c .obligations "$T_TMP/ref/ob/current.json")" "$(jq -c .obligations "$OB/current.json")"
t_eq "resume committed the offset" "$D	$(wc -c < "$EV/$D" | tr -d ' ')" "$(cat "$OB/offset")"
scenario; FAULT=mid-ledger; ( fold ) >/dev/null 2>&1; rc=$?; unset FAULT
t_eq "killed halfway through a ledger append" 137 "$rc"
t_eq "the ledger was left with a torn last line" torn "$([ "$(tail -c 1 "$OB/ledger.jsonl" | od -An -tx1 | tr -d ' \n')" = 0a ] && echo whole || echo torn)"
out="$(fold)"; t_has "the torn tail is named and cut" "$out" "torn ledger tail"
cmp -s "$OB/ledger.jsonl" "$T_TMP/ref/ob/ledger.jsonl" && t_pass || t_fail "ledger after a torn append differs from an unkilled run"
t_eq "every ledger line parses" 0 "$(jq -c . "$OB/ledger.jsonl" >/dev/null 2>&1; echo $?)"
t_eq "the abandoned row survived the torn append" abandoned "$(cur tool.background:S1:T1 state)"

t_section "lock: a live fold is not raced, a dead one's lock is taken over"
fresh; ev 2026-10-06T01:00:00Z session.start S1
sleep 30 >/dev/null 2>&1 & SP=$!; ln -s "$SP" "$OB/.fold.lock"
out="$(fold)"; rc=$?; held="$(readlink "$OB/.fold.lock")"; kill "$SP" 2>/dev/null; wait "$SP" 2>/dev/null
t_eq "a live holder makes the run a no-op that exits 0" 0 "$rc"
t_has "it says who holds the lock" "$out" "holds"
t_eq "nothing was written under a held lock" no "$([ -e "$OB/ledger.jsonl" ] && echo yes || echo no)"
t_eq "and the holder's lock is still its own after the run" "$SP" "$held"
fold >/dev/null
t_eq "a dead holder's lock is taken over" open "$(cur session:S1 state)"
t_eq "and released at the end of the run" no "$([ -L "$OB/.fold.lock" ] && echo yes || echo no)"

t_section "rollover: a new day file, a late write to an old one"
fresh; ev 2026-10-05T23:50:00Z pr.opened VytCepas/harbor#7 '{}' 2026-10-05.jsonl; fold >/dev/null
t_eq "the row opens from day 1" open "$(cur pr:VytCepas/harbor#7 state)"
ev 2026-10-06T00:10:00Z pr.merged VytCepas/harbor#7 '{}' 2026-10-06.jsonl; fold >/dev/null
t_eq "day 2 closes it" closed "$(cur pr:VytCepas/harbor#7 state)"
t_eq "the offset names both day files" 2 "$(wc -l < "$OB/offset" | tr -d ' ')"
ev 2026-10-05T23:55:00Z pr.opened VytCepas/harbor#8 '{}' 2026-10-05.jsonl; fold >/dev/null
t_eq "a line appended to yesterday's file is still read" open "$(cur pr:VytCepas/harbor#8 state)"
t_eq "and the closed row is not reopened" closed "$(cur pr:VytCepas/harbor#7 state)"
rm "$EV/2026-10-05.jsonl"; fold >/dev/null
t_eq "a pruned day file leaves the offset line" 1 "$(wc -l < "$OB/offset" | tr -d ' ')"

t_section "torn bus line: left for the next run, not consumed"
fresh; ev 2026-10-06T01:00:00Z session.start S1; GOOD="$(wc -c < "$EV/$D" | tr -d ' ')"
printf '{"id":"e9","ts":"2026-10-06T01:01:00Z","src":"cli","kind":"session.start","subj' >> "$EV/$D"; fold >/dev/null
t_eq "the offset stops at the last newline" "$D	$GOOD" "$(cat "$OB/offset")"
t_eq "the torn line opened nothing" 1 "$(count)"
printf 'ect":"S2","repo":"harbor","cause":"","data":{}}\n' >> "$EV/$D"; fold >/dev/null
t_eq "the completed line opens once" open "$(cur session:S2 state)"
t_eq "and is not doubled" 2 "$(count)"
printf 'not json at all\n[1,2]\n{"id":"e10"}\n' >> "$EV/$D"; ev 2026-10-06T01:05:00Z session.start S3; out="$(fold)"
t_eq "complete lines that are not events are skipped" open "$(cur session:S3 state)"
t_has "and counted" "$out" "read 4 lines (1 events)"

t_section "register: an unregistered kind opens nothing, never guessed"
fresh; ev 2026-10-06T01:00:00Z deploy.start prod; ev 2026-10-06T01:01:00Z pr.merged VytCepas/harbor#1; ev 2026-10-06T01:02:00Z git.commit abc123
out="$(fold)"; t_eq "no row opens for an event no row names" 0 "$(count)"
t_has "the unmatched events are counted, not silently dropped" "$out" "2 matched no register row"
ev 2026-10-06T01:03:00Z pr.opened VytCepas/harbor#2; fold >/dev/null; t_eq "a registered kind opens" 1 "$(count)"
fresh; KINDS="$T_TMP/kinds-nopr.tsv"; grep -v '^pr	' "$T_ROOT/contracts/obligation-kinds.tsv" > "$KINDS"
ev 2026-10-06T01:00:00Z pr.opened VytCepas/harbor#2; ev 2026-10-06T01:01:00Z session.start S1; fold >/dev/null
t_eq "a kind deleted from the register stops opening" 1 "$(count)"
ev 2026-10-06T01:02:00Z session.stop SX; fold >/dev/null
t_eq "a terminal event with no open row creates none" 0 "$(cur session:SX state | grep -c .)"
fresh; KINDS="$T_TMP/kinds-bad.tsv"; sed 's/	4h	data-session/	4h/' "$T_ROOT/contracts/obligation-kinds.tsv" > "$KINDS"
ev 2026-10-06T01:00:00Z session.start S1; out="$(fold)"; rc=$?
t_eq "a malformed register row is refused with exit 2" 2 "$rc"
t_has "and named by its line" "$out" "columns, want 9"
t_eq "and nothing is written" no "$([ -e "$OB/ledger.jsonl" ] && echo yes || echo no)"
fresh; KINDS="$T_TMP/kinds-dl.tsv"; sed 's/	4h	data-session/	soon	data-session/' "$T_ROOT/contracts/obligation-kinds.tsv" > "$KINDS"
ev 2026-10-06T01:00:00Z session.start S1; out="$(fold)"; rc=$?
t_eq "a deadline that is not a duration is refused" 2 "$rc"

t_section "abandoned: a session stop takes its background work with it"
fresh; ev 2026-10-06T01:00:00Z session.start S1; ev 2026-10-06T01:00:00Z session.start S2
ev 2026-10-06T01:01:00Z tool.background.start S1:T1 '{"tool":"Monitor"}'; ev 2026-10-06T01:01:00Z tool.background.start S1:T2 '{"tool":"Workflow"}'
ev 2026-10-06T01:01:00Z tool.background.start S1:T3 '{"tool":"CronCreate"}'; ev 2026-10-06T01:01:00Z tool.background.start S2:T9 '{"tool":"Monitor"}'
ev 2026-10-06T01:01:00Z tool.background.start S1:T4 '{"tool":"Monitor"}'; ev 2026-10-06T01:02:00Z tool.background.done S1:T4 '{}'
ev 2026-10-06T01:03:00Z pr.opened VytCepas/harbor#3 '{"session_id":"S1"}'; ev 2026-10-06T01:10:00Z session.stop S1; STOP="$LAST"; fold >/dev/null
t_eq "the stopped session's Monitor is abandoned" abandoned "$(cur tool.background:S1:T1 state)"
t_eq "closed_by names the stop event" "$STOP" "$(cur tool.background:S1:T1 closed_by)"
t_eq "closed_ts is the stop ts" 2026-10-06T01:10:00Z "$(cur tool.background:S1:T1 closed_ts)"
t_eq "a Workflow outlives its session" open "$(cur tool.background:S1:T2 state)"
t_eq "so does a CronCreate" open "$(cur tool.background:S1:T3 state)"
t_eq "another session's work is untouched" open "$(cur tool.background:S2:T9 state)"
t_eq "work that finished before the stop stays closed, not abandoned" closed "$(cur tool.background:S1:T4 state)"
t_eq "a PR the session opened is not abandoned by its stop" open "$(cur pr:VytCepas/harbor#3 state)"
ev 2026-10-06T01:20:00Z tool.background.done S1:T1 '{}'; fold >/dev/null
t_eq "a late done does not rewrite an abandoned row" abandoned "$(cur tool.background:S1:T1 state)"
fresh; ev 2026-10-06T01:01:00Z tool.background.start SZ:T1 '{"tool":"Monitor"}'; ev 2026-10-06T01:10:00Z session.stop SZ; fold >/dev/null
t_eq "a stop with no recorded session.start still abandons" abandoned "$(cur tool.background:SZ:T1 state)"

t_section "states: open, overdue, closed, abandoned, and the way back"
fresh; ev 2026-10-06T01:00:00Z ci.job.start VytCepas/harbor:7:suites; fold >/dev/null
t_eq "inside its deadline a row is open" open "$(cur ci:VytCepas/harbor:7:suites state)"
NOW=2026-10-06T03:00:01Z; fold >/dev/null
t_eq "past its deadline a row is overdue" overdue "$(cur ci:VytCepas/harbor:7:suites state)"
t_eq "overdue is written once" 2 "$(lines)"; fold >/dev/null; t_eq "and not again on the next run" 2 "$(lines)"
t_eq "overdue has no closer" "" "$(cur ci:VytCepas/harbor:7:suites closed_by)"
ev 2026-10-06T03:05:00Z ci.job.done VytCepas/harbor:7:suites; fold >/dev/null
t_eq "an overdue row still closes on its terminal event" closed "$(cur ci:VytCepas/harbor:7:suites state)"
ev 2026-10-06T04:00:00Z ci.job.start VytCepas/harbor:7:suites; fold >/dev/null
t_eq "an open event after a close opens the row again" open "$(cur ci:VytCepas/harbor:7:suites state)"
t_eq "with a fresh opened_ts" 2026-10-06T04:00:00Z "$(cur ci:VytCepas/harbor:7:suites opened_ts)"
fresh; ev 2026-10-06T01:00:00Z session.start S1; NOW=2027-10-06T00:00:00Z; fold >/dev/null
t_eq "a kind with no deadline is never overdue: a session, a year on, against the REAL register (harbor#1115)" open "$(cur session:S1 state)"
t_eq "and carries an empty deadline_ts" "" "$(cur session:S1 deadline_ts)"
fresh; KINDS="$T_TMP/kinds-24h.tsv"; TAB="$(printf '\t')"   # the control: the register as it was before #1115, a session due in 24h
awk 'BEGIN { FS = OFS = "\t" } $1 == "session" { $4 = "24h" } { print }' "$T_ROOT/contracts/obligation-kinds.tsv" > "$KINDS"
t_eq "the control register really gives a session 24h" 1 "$(grep -c "^session${TAB}.*${TAB}24h${TAB}self" "$KINDS")"
ev 2026-10-06T01:00:00Z session.start S1; NOW=2026-10-07T02:00:00Z; fold >/dev/null
t_eq "CONTROL: under that register the same session, 25h on, is overdue (so the test above can fail)" overdue "$(cur session:S1 state)"
unset KINDS

t_section "fields: id, owner, link and deadline come from the event and the register"
fresh; ev 2026-10-06T01:00:00Z obligation.open intent:ship-it '{"title":"ship it","deadline_ts":"2026-10-06T05:00:00Z","session_id":"S1"}'
ev 2026-10-06T01:00:00Z obligation.open plain-id '{}'; ev 2026-10-06T01:00:00Z pr.opened VytCepas/harbor#5 '{"session_id":"S1"}'
ev 2026-10-06T01:00:00Z agent.spawn S1:tu1 '{}'; ev 2026-10-06T01:30:00Z pr.opened VytCepas/harbor#5 '{}'; fold >/dev/null
t_eq "an open event while the row is open keeps the first opened_ts" 2026-10-06T01:00:00Z "$(cur pr:VytCepas/harbor#5 opened_ts)"
t_eq "a declared id keeps its intent: prefix once" "ship it" "$(cur intent:ship-it title)"
t_eq "a declared id without the prefix gets it" intent:plain-id "$(cur intent:plain-id id)"
t_eq "data.deadline_ts beats the register default" 2026-10-06T05:00:00Z "$(cur intent:ship-it deadline_ts)"
t_eq "the register default applies without it" 2026-10-07T01:00:00Z "$(cur intent:plain-id deadline_ts)"
t_eq "data.session_id owns a declared row" session:S1 "$(cur intent:ship-it owner)"
t_eq "no session_id means the operator owns it" operator "$(cur intent:plain-id owner)"
t_eq "a PR gets its GitHub link" https://github.com/VytCepas/harbor/pull/5 "$(cur pr:VytCepas/harbor#5 link)"
t_eq "a title defaults to the subject" S1:tu1 "$(cur agent:S1:tu1 title)"
t_eq "a PR is owned by the session that opened it" session:S1 "$(cur pr:VytCepas/harbor#5 owner)"
t_eq "current.json row keys" "closed_by,closed_ts,deadline_ts,id,kind,link,opened_ts,owner,repo,state,subject,title" \
  "$(jq -r '[.obligations[0] | keys[]] | join(",")' "$OB/current.json")"
t_eq "current.json carries the run clock" "$NOW" "$(jq -r .generated_ts "$OB/current.json")"
ev 2026-10-06T02:30:00Z obligation.close plain-id; fold >/dev/null
t_eq "obligation.close closes a declared row" closed "$(cur intent:plain-id state)"

t_done
