#!/usr/bin/env sh
# stream-lib.sh (harbor#1181 lane 3): harbor_emit writes one chained envelope line per call, spills instead of
# failing its caller, fails closed only under HARBOR_EMIT_STRICT, and stream_verify finds every edit and gap.
. "$(dirname "$0")/../lib/core.sh"; t_init
HERE="$(cd "$(dirname "$0")/../.." && pwd)/bin"; . "$HERE/log-lib.sh"; log_init stream-lib-test; . "$HERE/stream-lib.sh"
export HARBOR_SINK="$T_TMP/sink" HARBOR_WRITER=tw HARBOR_SESSION=s1
DAY="$(date -u +%Y-%m-%d)"; F="$HARBOR_SINK/run/$DAY/tw.s1.jsonl"

t_section "append"
harbor_emit run '{"k":1}'; harbor_emit run '{"k":2}'; harbor_emit run
t_eq "three calls write three lines to <root>/<stream>/<day>/<writer>.<session>.jsonl" 3 "$(wc -l < "$F" | tr -d ' ')"
t_eq "the envelope carries every key" "attrs,cause,id,prev,repo,seq,sess,src,stream,ts,v" \
  "$(head -n 1 "$F" | jq -r 'keys|join(",")')"
t_eq "attrs are carried as given" 2 "$(sed -n 2p "$F" | jq -r .attrs.k)"
t_eq "no attrs is an empty object" "{}" "$(sed -n 3p "$F" | jq -c .attrs)"
t_eq "seq counts per file" "1 2 3" "$(jq -r .seq "$F" | tr '\n' ' ' | sed 's/ $//')"
t_eq "the sink is 0600" "-rw-------" "$(ls -l "$F" | cut -c1-10)"
t_eq "an untouched file verifies clean" "" "$(stream_verify "$F")"

t_section "tamper evidence (same uid: accidents, not adversaries)"
sed '2s/"k":2/"k":9/' "$F" > "$T_TMP/edit.jsonl"   # no sed -i: BSD and GNU spell it differently
t_has "an edited line breaks the next line's prev" "$(stream_verify "$T_TMP/edit.jsonl")" 'line 3: prev'
sed '2d' "$F" > "$T_TMP/gap.jsonl"
t_has "a deleted line is a seq gap" "$(stream_verify "$T_TMP/gap.jsonl")" 'line 2: seq 3, want 2'

t_section "concurrent writers on one file are serialised"
i=0; while [ "$i" -lt 10 ]; do ( harbor_emit conc '{"n":1}' >/dev/null 2>&1 ) & i=$((i + 1)); done; wait
CF2="$(find "$HARBOR_SINK/conc" -name '*.jsonl' | head -n 1)"
t_eq "ten simultaneous emits are ten lines, seq 1 to 10" "1 2 3 4 5 6 7 8 9 10" "$(jq -r .seq "$CF2" | sort -n | tr '\n' ' ' | sed 's/ $//')"
t_eq "and the chain verifies (measured before the lock: every writer read seq 1)" "" "$(stream_verify "$CF2")"
t_eq "no lock is left behind" 0 "$(find "$HARBOR_SINK/conc" -name '*.lock' | grep -c .)"
mkdir "$CF2.lock"; touch -t 202001010000 "$CF2.lock"
t_eq "a stale lock from a crashed writer is broken, not waited on forever" 0 "$(harbor_emit conc '{}' >/dev/null 2>&1; echo $?)"
t_eq "and the line landed" 11 "$(grep -c . "$CF2")"

t_section "failure never exits the caller"
harbor_emit run 'not json' 2>/dev/null; t_eq "bad attrs return 0" 0 $?
t_eq "and are spilled, not written" 3 "$(wc -l < "$F" | tr -d ' ')"
t_eq "the drop is counted" 1 "$(cat "$HARBOR_SINK/.spill/run.dropped")"
harbor_emit 'Bad/Id' '{}' 2>/dev/null; t_eq "a bad stream id returns 0" 0 $?
t_eq "and nothing is created outside the root" no "$([ -e "$HARBOR_SINK/Bad" ] && echo yes || echo no)"
harbor_emit run "{\"x\":\"$(head -c 5000 /dev/zero | tr '\0' a)\"}" 2>/dev/null
t_eq "a line over 4096 bytes is spilled" 2 "$(cat "$HARBOR_SINK/.spill/run.dropped")"
t_has "a spill announces itself on stderr" "$(harbor_emit run '[1]' 2>&1)" '[check:stream.spill] run: attrs is not a JSON object'

t_section "strict streams fail closed"
mkdir -p "$T_TMP/ro"; chmod 0500 "$T_TMP/ro"
( HARBOR_SINK="$T_TMP/ro/sink" HARBOR_EMIT_STRICT=1; harbor_emit approvals "{}" 2>/dev/null )
t_eq "an unwritable strict stream returns 1" 1 $?
( HARBOR_SINK="$T_TMP/ro/sink"; harbor_emit events "{}" 2>/dev/null )
t_eq "the same failure on an ordinary stream returns 0" 0 $?
chmod 0700 "$T_TMP/ro"

t_section "default root"
unset HARBOR_SINK; export CLAUDE_CONFIG_DIR="$T_TMP/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR"
printf 'Box-1\n' > "$CLAUDE_CONFIG_DIR/.helm-obs-host"
t_eq "the root is the host's streams dir under the config dir" "$T_TMP/cfg/MEMORY/OBSERVABILITY/Box-1/streams" "$(stream_root)"
printf '../x\n' > "$CLAUDE_CONFIG_DIR/.helm-obs-host"
t_eq "a host token with a path in it is not followed" "$T_TMP/cfg/MEMORY/OBSERVABILITY/unknown-host/streams" "$(stream_root)"
t_done
