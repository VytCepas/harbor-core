#!/usr/bin/env sh
# prove (skills/test-strength/bin/prove.sh), part 5: P11 a watchdog kill reaches the whole process tree it
# started (harbor#743), in the engine and in trigger-probe.sh: at a timeout, at an early stop, and on a
# TERM mid-run. Each tree writes down its own pids, so "none alive" is scoped to this run and never vacuous.
. "$(dirname "$0")/../lib/core.sh"; t_init
. "$T_ROOT/tests/skills/prove-fixture.sh"
PROBE="$T_ROOT/skills/test-strength/bin/trigger-probe.sh"

_alive() { # <pidfile> — the pids still alive after up to 2s to settle (a zombie answers kill -0 until reaped)
  _al=x; _ai=0
  while [ -n "$_al" ] && [ "$_ai" -lt 20 ]; do
    _al=""; for _ap in $(cat "$1" 2>/dev/null); do kill -0 "$_ap" 2>/dev/null && _al="$_al $_ap"; done
    [ -z "$_al" ] || sleep 0.1; _ai=$((_ai + 1))
  done
  printf '%s' "${_al# }"
}
_named() { ps -A -o command= | awk -v d="$1" 'index($0, d) && $1 != "awk"' | wc -l | tr -d ' '; }  # <dir>
_npids() { wc -l < "$1" 2>/dev/null | tr -d ' '; }
_reap() { for _rp in $(cat "$1" 2>/dev/null); do kill -9 "$_rp" 2>/dev/null; done; }  # a red run leaks nothing
_await() { _wi=0; while [ "$(_npids "$1")" != "$2" ] && [ "$_wi" -lt 100 ]; do sleep 0.1; _wi=$((_wi + 1)); done; }

# Both hanging fixtures are three deep (script, a child of its own, that child's sleep), and write both
# pids BEFORE they hang or answer, so no kill can land ahead of the record.
WD="$T/watchdog"; _mk3 "$WD"; PTS="$WD/tree.pids"
cat > "$WD/tree.sh" <<'TREE'
#!/usr/bin/env sh
set -u
[ -s "$1" ] || exit 1
[ "$(/usr/bin/grep -c '^## ' "$1")" = 3 ] && exit 0
sh -c 'while :; do sleep 1; done' grandchild "${0%/*}" &
printf '%s\n' "$$" "$!" >> "${0%/*}/tree.pids"
while :; do sleep 1; done
TREE
_base watchdog | sed 's|\$TDIR/check.sh|$TDIR/tree.sh|' > "$WD/watchdog.target"

TP="$T/tprobe"; mkdir -p "$TP"; TPS="$TP/stub.pids"
printf -- '---\nname: wdprobe\ndescription: a card for the watchdog cases\n---\n\n# wdprobe\n' > "$TP/SKILL.md"
printf '+ route this one\n- not this one\n' > "$TP/queries"
cat > "$TP/claude" <<'STUB'
#!/usr/bin/env sh
sh -c 'while :; do sleep 1; done' grandchild "${0%/*}" &
printf '%s\n' "$$" "$!" >> "${0%/*}/stub.pids"
[ "${STUB_SILENT:-0}" = 1 ] || printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"no skill"}]}}'
while :; do sleep 1; done
STUB
chmod +x "$TP/claude"
export TRIGGER_PROBE_CLAUDE="$TP/claude"

t_section "P11 · a watchdog kill reaches the whole tree it started (harbor#743)"
: > "$PTS"; export PROVE_RUN_TIMEOUT=1
PT="$WD" _prove --all
unset PROVE_RUN_TIMEOUT
rc 4 'P11-1 a checker that never returns is COULD-NOT-LOOK'
t_has 'P11-2 and the report names the bound that fired' "$O" 'PROVE_RUN_TIMEOUT=1s'
t_eq 'P11-3 the hanging checker recorded its tree, or P11-4 is vacuous' 2 "$(_npids "$PTS")"
t_eq 'P11-4 no process of that tree survives the timeout' '' "$(_alive "$PTS")"
t_eq 'P11-5 and nothing naming its fixture dir is left in the process table' 0 "$(_named "$WD")"
_reap "$PTS"

# `env … &`, never a function: `f &` backgrounds a subshell, and $! would be the subshell, not the engine.
: > "$PTS"
env HARBOR_ROOT="$T_ROOT" PROVE_TARGETS="$WD" PROVE_WORK="$T/work" PROVE_RUN_TIMEOUT=60 \
  sh "$ENGINE" --all > "$OUT" 2> "$ERR" &
_pp=$!; _await "$PTS" 2
kill -TERM "$_pp"; RC=0; wait "$_pp" || RC=$?
t_eq 'P11-6 the TERM case reached its hang, or P11-8 is vacuous' 2 "$(_npids "$PTS")"
rc 143 'P11-7 a TERM mid-run exits 143'
t_eq 'P11-8 and the checker in flight dies with the engine' '' "$(_alive "$PTS")"
_reap "$PTS"

: > "$TPS"
sh "$PROBE" --card "$TP/SKILL.md" --queries "$TP/queries" > "$OUT" 2> "$ERR"; O="$(cat "$OUT")"
t_eq 'P11-9 trigger-probe stopped both sessions at the decision, having recorded both trees' 4 "$(_npids "$TPS")"
t_has 'P11-10 and counts both as truncated, so the early stop is the path that ran' "$O" 'truncated 2  errors 0'
t_eq 'P11-11 no process of a session stopped early survives it' '' "$(_alive "$TPS")"
t_eq 'P11-12 and nothing naming its fixture dir is left in the process table' 0 "$(_named "$TP")"
_reap "$TPS"

: > "$TPS"; export STUB_SILENT=1
sh "$PROBE" --card "$TP/SKILL.md" --queries "$TP/queries" --no-early-stop --session-timeout 1 > "$OUT" 2> "$ERR"; O="$(cat "$OUT")"
t_eq 'P11-13 both silent sessions ran to --session-timeout, having recorded both trees' 4 "$(_npids "$TPS")"
t_has 'P11-14 and counts both as errors, so the bound is the path that ran' "$O" 'truncated 0  errors 2'
t_eq 'P11-15 no process of a session killed at its bound survives it' '' "$(_alive "$TPS")"
_reap "$TPS"

: > "$TPS"
sh "$PROBE" --card "$TP/SKILL.md" --queries "$TP/queries" --no-early-stop --session-timeout 60 > "$OUT" 2> "$ERR" &
_pp=$!; _await "$TPS" 2
kill -TERM "$_pp"; RC=0; wait "$_pp" || RC=$?
t_eq 'P11-16 the TERM case reached its session, or P11-18 is vacuous' 2 "$(_npids "$TPS")"
rc 143 'P11-17 a TERM mid-session exits 143'
t_eq 'P11-18 and the session in flight dies with the probe' '' "$(_alive "$TPS")"
_reap "$TPS"
t_eq 'P11-19 this suite leaves nothing naming its fixtures running, whatever went red above' 0 "$(_named "$T")"
t_done
