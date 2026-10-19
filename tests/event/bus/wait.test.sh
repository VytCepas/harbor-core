#!/usr/bin/env sh
# bin/event-bus.sh wait (harbor#1043): 0 and the line on the first match, 3 at the deadline, never a
# hang — not on a torn line, not across a UTC midnight. Every wait runs under a watchdog, so a
# regression reads as a wrong exit code here rather than a stuck suite. sh, and dash where present.
. "$(dirname "$0")/../../lib/core.sh"; t_init
EB="$T_ROOT/bin/event-bus.sh"
# The bus clock is pinned to noon UTC today, so a suite never straddles a day file.
set -- $(date -u "+%s %Y-%m-%d"); D="$2"; NOON=$(( $1 / 86400 * 86400 + 43200 - $1 )); export HARBOR_EVENT_BUS_SKEW="$NOON"
SHELLS=sh; if command -v dash >/dev/null 2>&1; then SHELLS="sh dash"; else echo "  skip: dash is not on this host — sh only"; fi
waitfor() { # <out> <wait args…> → RC, SECS; the watchdog kills it at 25s
  _o="$1"; shift; _t0="$(date +%s)"
  $WAIT "$@" > "$_o" 2> "$_o.err" & _p=$!
  # Polls, never signals: a TERM to this subshell is swallowed if it lands before the subshell has its own
  # trap, because core.sh traps TERM in the parent and the fork inherits that (flaked as a 15 s wait at P=24).
  ( _n=0; while [ "$_n" -lt 250 ] && kill -0 "$_p" 2>/dev/null; do sleep 0.1; _n=$((_n + 1)); done; [ "$_n" -lt 250 ] || kill "$_p" 2>/dev/null ) >/dev/null 2>&1 &
  wait "$_p"; RC=$?
  SECS=$(( $(date +%s) - _t0 ))
}
later() { ( sleep "$1"; shift; $SH "$EB" emit "$@" >/dev/null ) & }  # <secs> <emit args…>

for SH in $SHELLS; do
  WAIT="$SH $EB wait"
  export HARBOR_EVENT_DIR="$T_TMP/bus-$SH"; W="$T_TMP/$SH"; mkdir -p "$W"
  t_section "$SH: a match is exit 0, the line on stdout"
  timers() { ps -A -o args 2>/dev/null | grep -cE '^sleep 9(0[89]|1[0-7])$'; }  # the timer of --timeout 917
  # The event lands once the wait's timer is seen (or after 20s), so the control holds on a loaded box.
  ( n=0; while [ "$n" -lt 40 ] && [ "$(timers)" -lt 1 ]; do n=$((n + 1)); sleep 0.5; done
    timers > "$W/timers-during"; $SH "$EB" emit ci.job.done 'o/r:42:build' >/dev/null ) &
  waitfor "$W/w1" '"kind":"ci\.job\.done","subject":"o/r:42:build"' --timeout 917
  wait
  t_eq "exit 0" 0 "$RC"
  t_eq "woke on the event, not the deadline" yes "$([ "$SECS" -le 22 ] && echo yes || echo no)"
  t_eq "printed the matching line" o/r:42:build "$(jq -r .subject "$W/w1")"
  t_eq "...and only it" 1 "$(grep -c . "$W/w1")"
  if ps -A -o args >/dev/null 2>&1; then
    t_eq "while it waited, its timer was running (the control)" 1 "$(cat "$W/timers-during")"
    t_eq "after the match, the timer is gone too" 0 "$(timers)"
  else echo "  skip: no ps on this host — the timer leak is unchecked"; fi

  t_section "$SH: the deadline is exit 3, on time, and said"
  $SH "$EB" emit ci.job.done 'o/r:old:build' >/dev/null
  waitfor "$W/w2" 'o/r:old:build' --timeout 2
  t_eq "an event from before the wait does not match: exit 3" 3 "$RC"
  t_eq "returned at the deadline, not after it" yes "$([ "$SECS" -ge 2 ] && [ "$SECS" -le 4 ] && echo yes || echo no)"
  t_eq "stdout stays empty" "" "$(cat "$W/w2")"
  t_has "stderr says what it waited for" "$(cat "$W/w2.err")" "FAIL: wait: no event matched 'o/r:old:build' within 2s"
  t_has "...then the fix line" "$(cat "$W/w2.err")" "fix: none automatic"

  t_section "$SH: --since-offset sees an event that landed before the wait started"
  $SH "$EB" since "$W/off" >/dev/null
  $SH "$EB" emit pr.merged 'VytCepas/harbor#9' >/dev/null
  waitfor "$W/w3" '"kind":"pr\.merged","subject":"VytCepas/harbor#9"' --timeout 5 --since-offset "$W/off"
  t_eq "matched" 0 "$RC"
  t_eq "...at once" yes "$([ "$SECS" -le 2 ] && echo yes || echo no)"
  t_eq "wait reads the offsets and never moves them" 1 "$($SH "$EB" since "$W/off" | grep -c 'VytCepas/harbor#9')"

  t_section "$SH: a torn line is not a match until it is whole"
  f="$HARBOR_EVENT_DIR/$D.jsonl"
  printf '{"id":"x","ts":"t","src":"cli","kind":"a.b","subject":"torn-subject"' >> "$f"
  waitfor "$W/w4" 'torn-subject' --timeout 1
  t_eq "half a line never matches: exit 3" 3 "$RC"
  ( sleep 1; printf ',"repo":"","cause":"","data":{}}\n' >> "$f" ) &
  waitfor "$W/w5" 'torn-subject' --timeout 10
  wait
  t_eq "the line half-written as the wait began matches once whole" 0 "$RC"
  t_eq "...and is printed whole" '"data":{}}' "$(grep -o '"data":{}}$' "$W/w5")"

  t_section "$SH: a wait across UTC midnight follows the new day's file"
  e="$(date -u +%s)"; export HARBOR_EVENT_BUS_SKEW=$(( (e / 86400 + 1) * 86400 - 2 - e ))  # 23:59:58 UTC
  later 4 session.stop after-midnight
  waitfor "$W/w6" '"subject":"after-midnight"' --timeout 14
  wait
  t_eq "matched the event written after midnight" 0 "$RC"
  t_eq "...when it landed, not at the deadline" yes "$([ "$SECS" -le 8 ] && echo yes || echo no)"
  t_eq "...and it was in the next day's file" "$(jq -r .ts "$W/w6" | cut -c1-10)" \
    "$(grep -l after-midnight "$HARBOR_EVENT_DIR"/*.jsonl | sed 's#.*/##; s#\.jsonl$##')"
  export HARBOR_EVENT_BUS_SKEW="$NOON"
done

t_section "the harbor verb, and usage errors"
WAIT="sh $T_ROOT/bin/harbor event wait"; waitfor "$T_TMP/h" nothing-matches --timeout 1
t_eq "harbor event wait passes the 3 through" 3 "$RC"
WAIT="sh $EB wait"
for args in '' 'p' 'p --timeout' 'p --timeout 0' 'p --timeout x' "'(' --timeout 1" 'p --timeout 1 --consumer a/b'; do
  eval "set -- $args"
  waitfor "$T_TMP/u" "$@"
  t_eq "wait $args: exit 2, not a wait" 2 "$RC"
done

if ps -A -o args >/dev/null 2>&1; then
  t_section "nothing is left running"
  t_has "ps sees this suite (the control)" "$(ps -A -o args)" "wait.test.sh"
  t_eq "no follower outlives its wait" "" "$(ps -A -o args | grep -F "$T_TMP" | grep -v grep)"
else echo "  skip: no ps on this host — leftover followers unchecked"; fi
t_done
