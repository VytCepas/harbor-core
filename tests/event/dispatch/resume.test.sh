#!/usr/bin/env sh
# bin/event-dispatch.sh dispatch (harbor#1044): its position is the bus offset, committed only after a batch is
# acted on, so killed mid-batch it resumes with no event lost or doubled. A first start replays no history; a
# running follower wakes on a new event; one follower per bus; dispatch.off stops it.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/event/dispatch/fixture.sh"
export HARBOR_EVENT_HANDLER_TIMEOUT=30
cat > "$T_TMP/handler.sh" <<EOF
if [ "\$HARBOR_EVENT_SUBJECT" = s10 ] && [ ! -e "$T_TMP/released" ]; then
  printf '%s\n' "\$\$" > "$T_TMP/blocked"; while [ ! -e "$T_TMP/released" ]; do sleep 0.1; done
fi
printf '%s %s\n' "\$HARBOR_EVENT_ID" "\$HARBOR_EVENT_SUBJECT" >> "$OUT"
EOF
register event.test-resume test.resume
handler default "$T_TMP/handler.sh"

t_section "a first start begins at the end of the bus: no rule fires on history"
emit test.resume old >/dev/null
sh "$ED" on '"kind":"test\.resume"' --id event.test-resume --debounce 0 --rate 60 -- sh "$HND" 2>/dev/null
dispatch_once; rc=$?
t_eq "dispatch --once exits 0" 0 "$rc"
t_eq "the event from before the first start ran nothing" 0 "$(lines "$OUT")"
t_eq "the offsets stand at the end of today's file" "dispatch $D $(wc -c < "$BUSDIR/$D.jsonl" | tr -d ' ')" "$(cat "$ST/offsets")"
first="$(cat "$ST/offsets")"

t_section "killed mid-batch, with a handler blocked: it resumes, every event once"
i=0; while [ "$i" -lt 20 ]; do i=$((i + 1)); emit test.resume "s$i" >/dev/null; done
before="$(cat "$ST/offsets")"
if command -v perl >/dev/null 2>&1; then
  perl -e 'setpgrp(0, 0); exec @ARGV' sh "$ED" dispatch --once 2>/dev/null & DP=$!
else sh "$ED" dispatch --once 2>/dev/null & DP=$!; fi
# A state-wait, not a bound: it returns the moment s10 blocks. 15 s gave up with s5 mid-run on a loaded pool (P=24),
# and the kill then landed between a handler's append and its ledger line, re-running that event once (21 runs, not 20).
until_file "$T_TMP/blocked" 180
t_eq "the handler for s10 is running" yes "$([ -s "$T_TMP/blocked" ] && echo yes || echo no)"
t_eq "...after s1-s9 ran" 9 "$(lines "$OUT")"
if command -v perl >/dev/null 2>&1; then kill -s KILL -- "-$DP" 2>/dev/null; else kill -9 "$DP" 2>/dev/null; fi
kill -9 "$(cat "$T_TMP/blocked")" 2>/dev/null; wait "$DP" 2>/dev/null
t_eq "the dispatcher died, its pid file left naming it" "$DP" "$(cat "$ST/dispatch.pid" 2>/dev/null)"
t_eq "the committed offsets did not move" "$before" "$(cat "$ST/offsets")"
: > "$T_TMP/released"
dispatch_once; rc=$?
t_eq "the restart takes the lock past the dead one's leftovers and exits 0" 0 "$rc"
t_eq "20 handler runs in all" 20 "$(lines "$OUT")"
t_eq "20 distinct events, none doubled" 20 "$(awk '{ print $1 }' "$OUT" | sort -u | grep -c .)"
t_eq "s10 ran exactly once, after the restart" "s10" "$(awk '$2 == "s10" { print $2 }' "$OUT")"
t_eq "every subject s1-s20 is there" "$(i=0; while [ $i -lt 20 ]; do i=$((i + 1)); echo "s$i"; done | sort)" "$(awk '{ print $2 }' "$OUT" | sort)"
t_eq "the offsets moved to the end once the batch was acted on" "dispatch $D $(wc -c < "$BUSDIR/$D.jsonl" | tr -d ' ')" "$(cat "$ST/offsets")"
t_eq "no pid file left behind" no "$([ -e "$ST/dispatch.pid" ] && echo yes || echo no)"

t_section "a re-read acts on nothing twice (idempotent by event id)"
printf '%s\n' "$first" > "$ST/offsets"
dispatch_once
t_eq "the batch read again from the same offsets: still 20 handler runs" 20 "$(lines "$OUT")"
t_eq "the ledger holds one line per (event, rule)" "done:0=20 " "$(outcomes event.test-resume)"


t_section "one follower however many start at once, past a dead holder's leftovers (review #3)"
register event.test-race test.race
printf 'sleep 0.3; printf "%%s\\n" "$HARBOR_EVENT_SUBJECT" >> "%s"\n' "$T_TMP/race.out" > "$T_TMP/race.sh"
handler event.test-race "$T_TMP/race.sh"
sh "$ED" on '"kind":"test\.race"' --id event.test-race --debounce 0 --rate 60 -- sh "$HND" 2>/dev/null
sleep 30 & DEAD=$!; kill "$DEAD"; wait "$DEAD" 2>/dev/null   # a pid that was real and is gone
printf '%s\t0\tseed\tevent.test-agent\tdone:0\tseed\t4.7500\n' "$((NOON + $(date -u +%s)))" >> "$LEDGER"
# Each trial: a dead holder's leftovers (a lock dir with its pid, or one it died before writing the pid
# into), then 12 dispatchers released at one instant by a barrier file.
for trial in 1 2 3 4; do
  rm -rf "$ST/run.lock" "$T_TMP/go"; mkdir -p "$ST/run.lock"; printf '%s\n' "$DEAD" > "$ST/dispatch.pid"
  [ $((trial % 2)) = 0 ] || printf '%s\n' "$DEAD" > "$ST/run.lock/pid"
  emit test.race "race$trial" >/dev/null
  pids=""; i=0
  while [ "$i" -lt 12 ]; do
    i=$((i + 1))
    ( while [ ! -e "$T_TMP/go" ]; do sleep 0.01; done; exec sh "$ED" dispatch --once 2>/dev/null ) & pids="$pids $!"
  done
  sleep 0.5; : > "$T_TMP/go"
  for p in $pids; do wait "$p" 2>/dev/null; done
done
t_eq "12 dispatchers at once, four times: each event ran exactly once" "race1 race2 race3 race4" "$(sort "$T_TMP/race.out" | tr '\n' ' ' | sed 's/ $//')"
t_eq "...and the ledger holds one line each" "done:0=4 " "$(outcomes event.test-race)"
t_eq "the \$4.75 already spent survived every racing prune" 1 "$(grep -c '	seed	4.7500$' "$LEDGER")"
rm -rf "$ST/run.lock"

t_section "a running follower wakes on a new event"
sh "$ED" dispatch 2>/dev/null & FP=$!
sleep 1; emit test.resume live >/dev/null
_n=0; while ! grep -q ' live$' "$OUT" 2>/dev/null && [ "$_n" -lt 100 ]; do sleep 0.1; _n=$((_n + 1)); done
t_has "the live event was handled without a restart" "$(cat "$OUT")" " live"

t_section "one follower per bus"
t_exit "a second dispatcher is refused while the first runs" 1 sh "$ED" dispatch --once
sh "$ED" dispatch --once 2>"$T_TMP/second.err" || :
t_has "...and says who holds it" "$(cat "$T_TMP/second.err")" "another dispatcher (pid $FP)"
kill "$FP"; wait "$FP"; rc=$?
t_eq "TERM ends the follower (143)" 143 "$rc"
t_eq "...and it removes its pid file" no "$([ -e "$ST/dispatch.pid" ] && echo yes || echo no)"


t_section "dispatch.off stops a follower that is asleep waiting for the next event"
rm -f "$ST/dispatch.off"
sh "$ED" dispatch 2>/dev/null & FP=$!
sleep 1; : > "$ST/dispatch.off"
n=0; while kill -0 "$FP" 2>/dev/null && [ "$n" -lt 60 ]; do sleep 0.1; n=$((n + 1)); done
t_eq "it exits within 6 s, not at the next event" no "$(kill -0 "$FP" 2>/dev/null && echo yes || echo no)"
kill "$FP" 2>/dev/null; wait "$FP"; rc=$?
t_eq "...with 0, so launchd leaves it down" 0 "$rc"

t_section "dispatch.off stops it"
: > "$ST/dispatch.off"; emit test.resume off >/dev/null
sh "$ED" dispatch 2>"$T_TMP/off.err"; rc=$?
t_eq "exit 0 at once (launchd's SuccessfulExit=false leaves it down)" 0 "$rc"
t_hasnt "nothing ran" "$(cat "$OUT")" " off"
t_has "it says why" "$(cat "$T_TMP/off.err")" "dispatch.off is present"
t_section "dispatch.off stops a batch that is running, before its next event (review r2 #4)"
rm -f "$ST/dispatch.off"
register event.test-slow test.slow
printf 'printf "%%s\\n" "$HARBOR_EVENT_SUBJECT" >> "%s"; sleep 1\n' "$T_TMP/slow.out" > "$T_TMP/slow.sh"
handler event.test-slow "$T_TMP/slow.sh"
sh "$ED" on '"kind":"test\.slow"' --id event.test-slow --debounce 0 --rate 60 -- sh "$HND" 2>/dev/null
for i in 1 2 3 4 5; do emit test.slow "x$i" >/dev/null; done
sh "$ED" dispatch 2>"$T_TMP/slow.err" & FP=$!
until_file "$T_TMP/slow.out" 180; : > "$ST/dispatch.off"
wait "$FP"; rc=$?
t_eq "it exits 0" 0 "$rc"
t_eq "the handler running when it appeared finished, and no later event in the batch ran" "x1" "$(cat "$T_TMP/slow.out" | tr '\n' ' ' | sed 's/ $//')"
t_has "...it says so" "$(cat "$T_TMP/slow.err")" "dispatch.off appeared mid-batch"
rm -f "$ST/dispatch.off"; dispatch_once
t_eq "the next start runs the rest of the batch, each event once" "x1 x2 x3 x4 x5" "$(sort "$T_TMP/slow.out" | tr '\n' ' ' | sed 's/ $//')"

t_section "a bus that does not pass the cause on: the dispatcher refuses to follow (review r2 #3)"
# follow_rc <cmd...>: the follower's exit code, or 124 if it is still following after 10 s (then it is killed).
follow_rc() {
  "$@" >/dev/null 2>&1 </dev/null & _fp=$!
  _n=0; while kill -0 "$_fp" 2>/dev/null && [ "$_n" -lt 100 ]; do sleep 0.1; _n=$((_n + 1)); done
  if kill -0 "$_fp" 2>/dev/null; then kill "$_fp" 2>/dev/null; wait "$_fp" 2>/dev/null; echo 124; return 0; fi
  _r=0; wait "$_fp" || _r=$?; echo "$_r"
}
# The bus from before #1044, made by taking its one cause line out of today's: the capability, not a version.
# It replaces the installed bus in place, as floor-install from an older checkout would (review r3 #3).
cp "$EB" "$T_TMP/bus.keep"
sed 's/_cause="${HARBOR_EVENT_CAUSE:-}"/_cause=""/' "$T_TMP/bus.keep" > "$T_TMP/oldbus.sh"
t_eq "the old bus differs from today's in that line only" 1 "$(diff "$EB" "$T_TMP/oldbus.sh" | grep -c '^>')"
register event.test-echo test.echo
printf 'printf "run\\n" >> "%s"; sh "%s" emit test.echo "n$$" >/dev/null 2>&1\n' "$T_TMP/echo.out" "$EB" > "$T_TMP/echo.sh"
handler event.test-echo "$T_TMP/echo.sh"
sh "$ED" on '"kind":"test\.echo"' --id event.test-echo --debounce 0 --rate 60 -- sh "$HND" 2>/dev/null
cp "$T_TMP/oldbus.sh" "$EB"
sh "$EB" emit test.echo seed >/dev/null 2>&1
rc=0; sh "$ED" dispatch --once 2>"$T_TMP/old.err" || rc=$?
t_eq "dispatch --once beside it: refused (4)" 4 "$rc"
t_has "...naming the missing capability" "$(cat "$T_TMP/old.err")" "does not pass HARBOR_EVENT_CAUSE on"
i=0; while [ $i -lt 4 ]; do i=$((i + 1)); sh "$ED" dispatch --once 2>/dev/null; done
t_eq "a rule that emits its own trigger ran 0 times in 5 passes (r2 probe skew: 5 with the old bus)" 0 "$(lines "$T_TMP/echo.out")"
t_eq "as the follower launchd runs: exit 0, so it is left down, not restarted every 10 s" 0 "$(follow_rc sh "$ED" dispatch)"
t_has "...with a checks.log line that says it is not following" "$(cat "$CACHE/checks.log")" "NOT FOLLOWING: $EB does not pass"
t_eq "...and a receipt pulse reads: down" down "$(jq -r .status "$CACHE/event-dispatch-state.json" 2>/dev/null)"
t_has "...carrying the reason" "$(jq -r .reason "$CACHE/event-dispatch-state.json" 2>/dev/null)" "does not pass HARBOR_EVENT_CAUSE"
t_eq "...which pulse's dispatch row reports as crit, so pulse-notify speaks" crit \
  "$(HARBOR_CACHE_DIR="$CACHE" sh "$T_ROOT/bin/alert-probe.sh" --json 2>/dev/null | jq -r '.checks.dispatch.verdict')"
cp "$T_TMP/bus.keep" "$EB"
dispatch_once
t_eq "the bus restored: the held seed runs once, its echo is a loop" 1 "$(lines "$T_TMP/echo.out")"

t_section "the bus swapped under a running follower: asked again before the next fire (review r3 #3)"
# The r3 probe swap.sh: a follower checked the bus once at start; an old bus copied in after ran a self-
# triggering rule 30 times in 12 s. Now the bus's bytes are compared before every fire and batch.
: > "$T_TMP/echo.out"
sh "$ED" dispatch 2>"$T_TMP/swap.err" & FP=$!
sleep 1; cp "$T_TMP/oldbus.sh" "$EB"; sleep 1
sh "$EB" emit test.echo swapped >/dev/null 2>&1
n=0; while kill -0 "$FP" 2>/dev/null && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
t_eq "the follower stopped by itself" no "$(kill -0 "$FP" 2>/dev/null && echo yes || echo no)"
kill "$FP" 2>/dev/null; wait "$FP"; rc=$?
t_eq "...with 0: down until the bus is redeployed" 0 "$rc"
t_eq "the echo rule ran 0 times on the swapped bus" 0 "$(lines "$T_TMP/echo.out")"
t_has "...and it said why" "$(cat "$T_TMP/swap.err")" "does not pass HARBOR_EVENT_CAUSE on"
cp "$T_TMP/bus.keep" "$EB"
dispatch_once
t_eq "redeployed: the held event runs once, and its echo is caught as a loop" 1 "$(lines "$T_TMP/echo.out")"

t_section "the bus is asked again before every spawn, not only when its bytes change (review r3 #3)"
# A library the bus sources, swapped under a running follower: event-bus.sh's bytes are the same, so only
# the per-spawn probe sees that the cause is now dropped.
register event.test-spawnbus test.spawnbus
sh "$ED" on '"kind":"test\.spawnbus"' --id event.test-spawnbus --debounce 0 --rate 60 --spawn 'Summarise.' 2>/dev/null
: > "$GT/spawn.on"; : > "$T_TMP/claude.starts"; cp "$CFG/bin/library-log.sh" "$T_TMP/loglib.keep"
sh "$ED" dispatch 2>"$T_TMP/sb.err" & FP=$!
sleep 1; { cat "$T_TMP/loglib.keep"; printf 'unset HARBOR_EVENT_CAUSE\n'; } > "$CFG/bin/library-log.sh"
emit test.spawnbus sb1 >/dev/null
n=0; while kill -0 "$FP" 2>/dev/null && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
kill "$FP" 2>/dev/null; wait "$FP"; rc=$?
t_eq "no agent was spawned" 0 "$(lines "$T_TMP/claude.starts")"
t_eq "the follower went down by itself, exit 0" 0 "$rc"
t_has "...saying the bus does not pass the cause on" "$(cat "$T_TMP/sb.err")" "does not pass HARBOR_EVENT_CAUSE on"
cp "$T_TMP/loglib.keep" "$CFG/bin/library-log.sh"; dispatch_once 2>/dev/null
t_eq "the library restored: the held event spawns once" 1 "$(lines "$T_TMP/claude.starts")"
rm -f "$GT/spawn.on"; sh "$ED" on --off event.test-spawnbus 2>/dev/null

t_section "a probe that cannot write is not an old bus: exit 1 with the real reason (review r3 #4)"
chmod 500 "$ST"
rc=0; sh "$ED" dispatch --once 2>"$T_TMP/ro.err" || rc=$?
chmod 700 "$ST"
t_eq "an unwritable state dir: exit 1, so launchd tries again" 1 "$rc"
t_has "...saying it cannot write" "$(cat "$T_TMP/ro.err")" "cannot write the bus probe"
t_hasnt "...not that the bus lacks the cause" "$(cat "$T_TMP/ro.err")" "does not pass HARBOR_EVENT_CAUSE"
sh "$ED" on --off event.test-echo 2>/dev/null

t_section "no jq: the follower stays down with a NOT FOLLOWING line (review r3 #11)"
# A PATH of the system dirs and perl, with every jq left out.
NJ="$T_TMP/nojq"; mkdir -p "$NJ"
for d in /bin /usr/bin /usr/sbin /sbin; do
  [ -d "$d" ] || continue
  for f in "$d"/*; do b="${f##*/}"; case "$b" in jq*) continue ;; esac; [ -e "$NJ/$b" ] || ln -s "$f" "$NJ/$b"; done
done
if env PATH="$NJ" /bin/sh -c 'command -v jq' >/dev/null 2>&1; then echo "  skip: jq is still reachable here — not run"; t_pass
else
  : > "$CACHE/checks.log"
  rc=0; env PATH="$NJ" /bin/sh "$ED" dispatch --once 2>"$T_TMP/nj.err" || rc=$?
  t_eq "dispatch --once: refused (4)" 4 "$rc"
  t_has "...saying jq is missing" "$(cat "$T_TMP/nj.err")" "jq is not on PATH"
  t_eq "the follower launchd runs: exit 0, so KeepAlive SuccessfulExit=false leaves it down" 0 "$(follow_rc env PATH="$NJ" /bin/sh "$ED" dispatch)"
  t_has "...and checks.log says it is not following" "$(cat "$CACHE/checks.log")" "NOT FOLLOWING: jq is not on PATH"
fi

t_section "no perl: an accurate message, and an exit launchd does not restart (review r2 #6)"
# A PATH of the system dirs with perl left out, plus jq: no lock without perl, so no follower.
NP="$T_TMP/noperl"; mkdir -p "$NP"
for d in /bin /usr/bin /usr/sbin /sbin; do
  [ -d "$d" ] || continue
  for f in "$d"/*; do b="${f##*/}"; case "$b" in perl*) continue ;; esac; [ -e "$NP/$b" ] || ln -s "$f" "$NP/$b"; done
done
[ -e "$NP/jq" ] || ln -s "$(command -v jq)" "$NP/jq"
if env PATH="$NP" /bin/sh -c 'command -v perl' >/dev/null 2>&1; then echo "  skip: perl is still reachable here — not run"; t_pass
else
  rc=0; env PATH="$NP" /bin/sh "$ED" dispatch --once 2>"$T_TMP/np.err" || rc=$?
  t_eq "dispatch --once: refused (4)" 4 "$rc"
  t_has "...saying perl is missing" "$(cat "$T_TMP/np.err")" "perl is not on PATH"
  t_hasnt "...not that another dispatcher holds the lock" "$(cat "$T_TMP/np.err")" "another dispatcher"
  t_eq "the follower launchd runs: exit 0, so KeepAlive SuccessfulExit=false leaves it down" 0 "$(follow_rc env PATH="$NP" /bin/sh "$ED" dispatch)"
  t_has "...and checks.log says it is not following" "$(cat "$CACHE/checks.log")" "NOT FOLLOWING: perl is not on PATH"
fi
t_done
