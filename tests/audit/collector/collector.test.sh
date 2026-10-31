#!/usr/bin/env sh
# audit-collector.sh (harbor#1181 lane 5): copies only new bytes, survives rotation without a false alarm, reports a
# truncation, an edit and an unreadable source, and signs a checkpoint that stops verifying once the store changes.
. "$(dirname "$0")/../../lib/core.sh"; t_init
C="$(cd "$(dirname "$0")/../../.." && pwd)/bin/audit-collector.sh"
S="$T_TMP/src"; ST="$T_TMP/store"; mkdir -p "$S/h" "$ST/key"
run() { HARBOR_COLLECTOR_SRC="$S" HARBOR_COLLECTOR_STORE="$ST" sh "$C" "$@" >/dev/null 2>&1; echo $?; }
ev() { grep -c "\"kind\":\"$1\"" "$ST/events.jsonl" 2>/dev/null | tr -d ' '; }
copied() { cat "$ST"/data/*.jsonl 2>/dev/null; }
L="$S/h/guard-decisions.jsonl"

t_section "ingest"
printf 'a1\na2\n' > "$L"
t_eq "a pass exits 0" 0 "$(run)"
t_eq "the store holds the source's bytes" "$(printf 'a1\na2')" "$(copied)"
printf 'a3\n' >> "$L"; run >/dev/null
t_eq "a second pass copies only the new bytes" "$(printf 'a1\na2\na3')" "$(copied)"
run >/dev/null
t_eq "an unchanged source copies nothing more" 3 "$(copied | grep -c .)"
t_eq "status.json is world-readable, for harbor's check" "-rw-r--r--" "$(ls -l "$ST/status.json" | cut -c1-10)"
t_eq "and the store itself is not" "drwx------" "$(ls -ld "$ST/data" | cut -c1-10)"

t_section "rotation is not tampering"
mv "$L" "$L.1"; printf 'b1\n' > "$L"; run >/dev/null
t_eq "a renamed generation and a fresh sink raise no event" "0 0" "$(ev truncated) $(ev edited)"
t_eq "and the fresh sink is copied" yes "$(copied | grep -qx b1 && echo yes || echo no)"
mkdir -p "$S/h/archive"; mv "$L.1" "$S/h/archive/guard-decisions.20261009T000000Z.jsonl"; run >/dev/null
t_eq "archiving the old generation raises no event and copies nothing twice" "0 4" "$(ev edited) $(copied | grep -c .)"

t_section "tampering is reported"
printf 'x\n' > "$L"; run >/dev/null
t_eq "a truncated sink is a truncated event" 1 "$(ev truncated)"
printf 'b1\nb2\n' > "$S/h/tool-failures.jsonl"; run >/dev/null
sed 's/b1/B1/' "$S/h/tool-failures.jsonl" > "$T_TMP/tf" && cat "$T_TMP/tf" > "$S/h/tool-failures.jsonl"; run >/dev/null
t_eq "rewriting copied bytes in place is an edited event" 1 "$(ev edited)"
t_eq "and the store keeps the original bytes" yes "$(copied | grep -qx b1 && echo yes || echo no)"
printf 'c1\n' > "$S/h/locked.jsonl"; chmod 000 "$S/h/locked.jsonl"; run >/dev/null
t_eq "an unreadable source is reported" 1 "$(ev unreadable)"
t_eq "and counted in status.json" 1 "$(jq -r .unreadable "$ST/status.json")"
chmod 600 "$S/h/locked.jsonl"

t_section "events are the delta, not the census"
run >/dev/null; run >/dev/null
t_eq "a standing edit is logged once, not once per pass" 1 "$(ev edited)"
chmod 000 "$S/h/locked.jsonl"; run >/dev/null; run >/dev/null
t_eq "a standing unreadable file is logged once" 2 "$(ev unreadable)"
chmod 600 "$S/h/locked.jsonl"; run >/dev/null; chmod 000 "$S/h/locked.jsonl"; run >/dev/null
t_eq "cleared and back again, it is logged again" 3 "$(ev unreadable)"
chmod 600 "$S/h/locked.jsonl"

t_section "many sources, wherever the writer keeps them (lane 4)"
mkdir -p "$T_TMP/bus"; printf "e1\n" > "$T_TMP/bus/2026-10-09.jsonl"; printf "[check:x] t m\n" > "$T_TMP/checks.log"
multi() { HARBOR_COLLECTOR_SRC="$S:$T_TMP/bus:$T_TMP/checks.log:$T_TMP/never" HARBOR_COLLECTOR_STORE="$ST" sh "$C" >/dev/null 2>&1; }
multi
t_eq "a second source dir is copied" yes "$(copied | grep -qx e1 && echo yes || echo no)"
t_eq "a single-file source is copied" yes "$(copied | grep -qxF "[check:x] t m" && echo yes || echo no)"
t_eq "a source that does not exist is reported once" 1 "$(multi; ev missing)"

t_section "the fast path, and its daily backstop"
printf 'q1\nq2\n' > "$S/h/quiet.jsonl"; touch -t 202001010000 "$S/h/quiet.jsonl"; run >/dev/null   # a closed file: idle for years
_e0="$(ev edited)"
# a same-size edit with the mtime put back: the 5-minute pass trusts size and mtime, by design
touch -r "$S/h/quiet.jsonl" "$T_TMP/ref"; printf 'Q1\nq2\n' > "$T_TMP/q" && cat "$T_TMP/q" > "$S/h/quiet.jsonl"; touch -r "$T_TMP/ref" "$S/h/quiet.jsonl"
run >/dev/null
t_eq "a size- and mtime-preserving edit passes the quick pass" "$_e0" "$(ev edited)"
HARBOR_COLLECTOR_SRC="$S" HARBOR_COLLECTOR_STORE="$ST" HARBOR_COLLECTOR_FULL=1 sh "$C" >/dev/null 2>&1
t_eq "and is caught by the full pass the daily checkpoint runs" "$((_e0 + 1))" "$(ev edited)"

t_section "signed checkpoints"
ssh-keygen -q -t ed25519 -N '' -C collector -f "$ST/key/collector" >/dev/null 2>&1
t_eq "a checkpoint is signed" 0 "$(run --checkpoint 2026-10-08)"
t_eq "it verifies" 0 "$(run --verify 2026-10-08)"
t_eq "a second checkpoint for the same day is refused" 1 "$(run --checkpoint 2026-10-08)"
printf 'later\n' >> "$S/h/locked.jsonl"; run >/dev/null
t_eq "appends after the checkpoint still verify" 0 "$(run --verify 2026-10-08)"
_d="$(ls "$ST"/data/*.jsonl | head -n 1)"
if [ "$(uname -s)" = Darwin ]; then
  t_has "a store file is append-only once written" "$(ls -lO "$_d")" uappnd
  t_eq "and an in-place edit is refused" 1 "$(printf Z | dd of="$_d" bs=1 seek=0 conv=notrunc 2>/dev/null; echo $?)"
  t_eq "while an append still works" 0 "$(printf x >> "$_d" 2>/dev/null; echo $?)"
fi
# the attack this tier admits: root (or the owner) clears the flag first, then edits
chflags nouappnd "$_d" 2>/dev/null || :; chmod u+w "$_d"; printf Z | dd of="$_d" bs=1 seek=0 conv=notrunc 2>/dev/null
t_eq "an edited store file fails verification" 1 "$(run --verify 2026-10-08)"
printf '# forged\n' >> "$ST/checkpoints/2026-10-08.tsv"
t_eq "an edited checkpoint fails its signature" 1 "$(run --verify 2026-10-08)"
t_eq "an unknown argument is a usage error" 2 "$(run --bogus)"
chflags -R nouappnd "$ST" 2>/dev/null || :   # append-only files cannot be unlinked: let the temp dir go
t_done
