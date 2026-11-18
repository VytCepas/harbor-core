#!/usr/bin/env sh
# bin/event-dispatch.sh dispatch (2026-11-16): an event that waited longer than HARBOR_EVENT_DISPATCH_LAG_WARN for its
# rules writes the lag file alert-probe.sh reads, naming the rule that took the most ledger time, and raises one
# checks.log alarm an hour; an event on time again clears it; 0 turns it off. The wait is made with the bus clock: the
# events are emitted at the fixture's noon and dispatched with the clock 20 minutes on.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/event/dispatch/fixture.sh"
export HARBOR_EVENT_HANDLER_TIMEOUT=30
printf 'printf "%%s\\n" "$HARBOR_EVENT_SUBJECT" >> "%s"\n' "$OUT" > "$T_TMP/handler.sh"
register event.test-lag test.lag
handler default "$T_TMP/handler.sh"
LAGF="$CACHE/event-dispatch-lag.tsv"; CL="$CACHE/checks.log"
sh "$ED" on '"kind":"test\.lag"' --id event.test-lag --debounce 0 --rate 60 -- sh "$HND" 2>/dev/null
dispatch_once   # the first start: the offsets go to the end of the bus
late() { HARBOR_EVENT_BUS_SKEW=$((NOON + 1200)) dispatch_once; }   # dispatched 20 min after the event was written

t_section "an event 20 minutes old when its rules run: the lag file and one alarm"
emit test.lag a1 >/dev/null; late
t_eq "the rule still ran" a1 "$(cat "$OUT" 2>/dev/null)"
t_eq "the lag file is written" yes "$([ -s "$LAGF" ] && echo yes || echo no)"
_w="$(cut -f1 "$LAGF" 2>/dev/null)"; case "$_w" in ''|*[!0-9]*) _w=0 ;; esac
t_eq "...with the wait in seconds (20 min, a clock tick either way)" yes "$([ "$_w" -ge 1200 ] && [ "$_w" -lt 1260 ] && echo yes || echo "no ($_w)")"
t_eq "...and no rule named while the ledger holds no run from the last hour" - "$(cut -f3 "$LAGF" 2>/dev/null)"
t_has "checks.log says how far behind" "$(cat "$CL" 2>/dev/null)" "[check:event.dispatch] "
t_has "...in minutes" "$(cat "$CL" 2>/dev/null)" "dispatch is 20 min behind its events"
emit test.lag a2 >/dev/null; late
t_eq "a second late batch within the hour: still one alarm" 1 "$(grep -c 'min behind its events' "$CL" 2>/dev/null)"
t_eq "...and the lag file now names the rule that took the ledger's time" event.test-lag "$(cut -f3 "$LAGF" 2>/dev/null)"

t_section "behind a backlog the ledger is read once a minute, not once an event"
_b1="$(emit test.lag b1)"; _b2="$(emit test.lag b2)"; late
t_eq "two late events in one pass: the lag file still names the first" "$_b1" "$(cut -f2 "$LAGF" 2>/dev/null)"
t_eq "...though both ran" 4 "$(lines "$OUT")"

t_section "an event on time again clears it"
emit test.lag a3 >/dev/null; dispatch_once
t_eq "the lag file is gone" no "$([ -e "$LAGF" ] && echo yes || echo no)"

t_section "a backstop event is no lag: it is old by design"
emit rule.backstop event.test-lag >/dev/null; late
t_eq "a late rule.backstop writes no lag file" no "$([ -e "$LAGF" ] && echo yes || echo no)"
t_eq "...though its rule ran on it" 1 "$(grep -c '^event.test-lag$' "$OUT")"

t_section "HARBOR_EVENT_DISPATCH_LAG_WARN=0 turns it off"
emit test.lag a4 >/dev/null; HARBOR_EVENT_DISPATCH_LAG_WARN=0 late
t_eq "no lag file" no "$([ -e "$LAGF" ] && echo yes || echo no)"
t_eq "...and the rule ran every test.lag event" 6 "$(grep -c '^[ab]' "$OUT")"
t_done
