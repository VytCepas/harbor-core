#!/usr/bin/env sh
# No producer can fail or slow its caller (harbor#1043, PR 2). Each producer is run with the bus
# broken in every way a box can break it, and must exit 0 and print nothing; then timed, because a
# hook that is correct and slow is the other way to fail a caller. The ms figures are printed.
. "$(dirname "$0")/../../lib/core.sh"; t_init
EH="$T_ROOT/bin/event-hook.sh"
START="{\"session_id\":\"s-1\",\"cwd\":\"$T_TMP\",\"hook_event_name\":\"SessionStart\",\"source\":\"startup\"}"
SUB='{"session_id":"s-1","agent_id":"a-1","hook_event_name":"SubagentStop","last_assistant_message":"x"}'
END='{"session_id":"s-1","hook_event_name":"SessionEnd","reason":"other"}'

SUBSTART='{"session_id":"s-1","agent_id":"a-1","hook_event_name":"SubagentStart","agent_type":"Explore"}'
POST='{"session_id":"s-1","hook_event_name":"PostToolUse","tool_name":"Monitor","tool_input":{"command":"x"},"tool_response":"ok","tool_use_id":"tu-1"}'
printf '%s' "$SUBSTART" > "$T_TMP/in.SubagentStart"; printf '%s' "$POST" > "$T_TMP/in.PostToolUse"
printf '%s' "$START" > "$T_TMP/in.SessionStart"; printf '%s' "$SUB" > "$T_TMP/in.SubagentStop"; printf '%s' "$END" > "$T_TMP/in.SessionEnd"
bounded() { # <stdin file | -> <cmd…> → RC; stdout and stderr in $T_TMP/o and $T_TMP/e; killed at 15 s (RC 143)
  _in="$1"; shift
  if [ "$_in" = - ]; then "$@" <&- >"$T_TMP/o" 2>"$T_TMP/e" & _p=$!; else "$@" <"$_in" >"$T_TMP/o" 2>"$T_TMP/e" & _p=$!; fi
  # Polls, never signals: a TERM to this subshell is swallowed if it lands before the subshell has its own
  # trap, because core.sh traps TERM in the parent and the fork inherits that (flaked as a 15 s wait at P=24).
  ( _n=0; while [ "$_n" -lt 150 ] && kill -0 "$_p" 2>/dev/null; do sleep 0.1; _n=$((_n + 1)); done; [ "$_n" -lt 150 ] || kill "$_p" 2>/dev/null ) >/dev/null 2>&1 &
  wait "$_p"; RC=$?
  return 0
}
quiet() { t_eq "$1: exit 0 and nothing printed" "0" "$RC$(cat "$T_TMP/o")$(cat "$T_TMP/e")"; }  # <label> after bounded
run_hook() { # <label> <env args…> — every event through the hook
  _l="$1"; shift
  for _e in SessionStart SubagentStart SubagentStop PostToolUse SessionEnd; do
    bounded "$T_TMP/in.$_e" env "$@" sh "$EH"; quiet "$_l ($_e)"
  done
}

t_section "the bus dir is broken"
: > "$T_TMP/afile"
run_hook "the bus dir is a file" HARBOR_EVENT_DIR="$T_TMP/afile"
run_hook "the bus dir is under a file" HARBOR_EVENT_DIR="$T_TMP/afile/events"
mkdir -p "$T_TMP/ro"; chmod 500 "$T_TMP/ro"
if [ -w "$T_TMP/ro" ]; then echo "  skip: running as root, which can write a read-only dir"
else run_hook "the bus dir is read-only" HARBOR_EVENT_DIR="$T_TMP/ro/events"; fi
mkdir -p "$T_TMP/rod"; chmod 500 "$T_TMP/rod"
[ -w "$T_TMP/rod" ] || run_hook "the bus dir exists and is read-only" HARBOR_EVENT_DIR="$T_TMP/rod"
chmod 700 "$T_TMP/ro" "$T_TMP/rod"
run_hook "the bus dir is an empty string and HOME is unset" -u HOME HARBOR_EVENT_DIR=

t_section "the bus tool is broken or missing"
mkdir -p "$T_TMP/bare"; cp "$EH" "$T_TMP/bare/"
run_hook_at() { # <hook path> <label>
  for _e in SessionStart SubagentStart SubagentStop PostToolUse SessionEnd; do
    bounded "$T_TMP/in.$_e" env HARBOR_EVENT_DIR="$T_TMP/bus-x" sh "$1"; quiet "$2 ($_e)"
  done
}
run_hook_at "$T_TMP/bare/event-hook.sh" "event-bus.sh is missing"
mkdir -p "$T_TMP/nolib"; cp "$EH" "$T_ROOT/bin/event-bus.sh" "$T_TMP/nolib/"
run_hook_at "$T_TMP/nolib/event-hook.sh" "library-log.sh is missing beside the bus"
t_eq "...and the bus wrote nothing, since it could not run" 0 "$(find "$T_TMP/bus-x" -name '*.jsonl' 2>/dev/null | wc -l | tr -d ' ')"
mkdir -p "$T_TMP/junk/bin"; cp "$EH" "$T_TMP/junk/bin/"; printf 'exit 7\n' > "$T_TMP/junk/bin/event-bus.sh"
run_hook_at "$T_TMP/junk/bin/event-hook.sh" "event-bus.sh exits 7"
printf 'printf "noise\\n"; printf "noise\\n" >&2; exit 1\n' > "$T_TMP/junk/bin/event-bus.sh"
run_hook_at "$T_TMP/junk/bin/event-hook.sh" "event-bus.sh prints and fails"

t_section "the payload is broken"
for bad in '' 'not json' '{' '{"hook_event_name":"SessionStart"'; do
  printf '%s' "$bad" > "$T_TMP/in.bad"
  bounded "$T_TMP/in.bad" env HARBOR_EVENT_DIR="$T_TMP/bus-y" sh "$EH"; quiet "payload '$bad'"
done
bounded /dev/null env HARBOR_EVENT_DIR="$T_TMP/bus-y" sh "$EH"; quiet "an empty stdin"

t_section "the git hooks run directly with the bus broken: exit 0, nothing printed"
R="$T_TMP/g/repo"; mkdir -p "$R"; git -C "$R" init -q
printf x > "$R/f"; git -C "$R" add f; git -C "$R" -c user.name=t -c user.email=t@t.invalid -c commit.gpgsign=false commit -q -m m
for h in post-commit post-merge; do
  for env in "HARBOR_EVENT_DIR=$T_TMP/afile" "HARBOR_EVENT_DIR=$T_TMP/afile/x"; do
    (cd "$R" && bounded /dev/null env "$env" sh "$T_ROOT/hooks/$h"; echo "$RC" > "$T_TMP/rc"); RC="$(cat "$T_TMP/rc")"
    quiet "$h with $(printf '%s' "$env" | sed "s#$T_TMP#T#")"
  done
done
mkdir -p "$T_TMP/g/hooks"; cp "$T_ROOT/hooks/post-commit" "$T_ROOT/hooks/lib.sh" "$T_TMP/g/hooks/"
(cd "$R" && bounded /dev/null sh "$T_TMP/g/hooks/post-commit"; echo "$RC" > "$T_TMP/rc"); RC="$(cat "$T_TMP/rc")"
quiet "post-commit with no event-bus.sh beside hooks/"

t_section "the added wall time per invocation, in ms (printed; bounded only against a hang)"
# perl, not date +%N: BSD date has no sub-second field. N runs of the hook with a real, healthy bus.
ms() { # <n> <shell snippet> → average ms per run
  perl -MTime::HiRes=time -e '$n = shift; $c = shift; $t = time; system($c) for 1 .. $n; printf "%.0f", (time - $t) / $n * 1000' "$1" "$2"
}
export HARBOR_EVENT_DIR="$T_TMP/bus-t"
printf '%s' "$START" > "$T_TMP/p.json"
EMPTY="$(ms 20 "sh -c : < '$T_TMP/p.json'")"
HOOK="$(ms 20 "sh '$EH' < '$T_TMP/p.json'")"
COMMIT="$(ms 20 "cd '$R' && sh '$T_ROOT/hooks/post-commit'")"
printf '  empty sh: %s ms · event-hook.sh (SessionStart, bus on): %s ms · hooks/post-commit: %s ms (per invocation, mean of 20)\n' "$EMPTY" "$HOOK" "$COMMIT"
t_eq "the hook ran against a live bus (20 events were written)" 20 "$(cat "$HARBOR_EVENT_DIR"/*.jsonl | grep -c session.start)"
t_eq "event-hook.sh adds under 1000 ms" yes "$([ "$HOOK" -lt 1000 ] && echo yes || echo no)"
t_eq "post-commit adds under 1000 ms" yes "$([ "$COMMIT" -lt 1000 ] && echo yes || echo no)"
t_done
