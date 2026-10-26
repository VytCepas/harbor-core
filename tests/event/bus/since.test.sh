#!/usr/bin/env sh
# bin/event-bus.sh since and tail (harbor#1043): a consumer resumes from its offsets — no line lost,
# none doubled — a torn last line is skipped until it is whole, and consumers never move each other.
. "$(dirname "$0")/../../lib/core.sh"; t_init
EB="$T_ROOT/bin/event-bus.sh"
# The bus clock is pinned to noon UTC today, so a suite never straddles a day file.
set -- $(date -u "+%s %Y-%m-%d"); D="$2"; NOON=$(( $1 / 86400 * 86400 + 43200 - $1 )); export HARBOR_EVENT_BUS_SKEW="$NOON"
export HARBOR_EVENT_DIR="$T_TMP/bus"
OFF="$T_TMP/state/offsets"
emit() { for _s in "$@"; do sh "$EB" emit test.since "$_s" >/dev/null; done; }
subjects() { jq -r .subject "$1" 2>/dev/null | tr '\n' ' '; }

t_section "offset resume: every line exactly once"
emit a b c
sh "$EB" since "$OFF" > "$T_TMP/r1"; rc=$?
t_eq "exit 0" 0 "$rc"
t_eq "a new consumer reads from the start of the bus" 'a b c ' "$(subjects "$T_TMP/r1")"
sh "$EB" since "$OFF" > "$T_TMP/r2"
t_eq "read again: nothing new, nothing repeated" '' "$(cat "$T_TMP/r2")"
emit d e
sh "$EB" since "$OFF" > "$T_TMP/r3"
t_eq "after two more emits: exactly those two" 'd e ' "$(subjects "$T_TMP/r3")"
t_eq "across the reads, no id twice and none missing" 5 "$(cat "$T_TMP/r1" "$T_TMP/r2" "$T_TMP/r3" | jq -r .id | sort -u | grep -c .)"
t_eq "the offsets file holds one row per day file" "default $D $(wc -c < "$T_TMP/bus/$D.jsonl" | tr -d ' ')" "$(cat "$OFF")"

t_section "a torn last line is skipped until it is whole"
f="$T_TMP/bus/$D.jsonl"
emit f; pre="$(wc -c < "$f" | tr -d " ")"
printf '{"id":"torn","ts":"t","src":"cli","kind":"test.since","subject":"g"' >> "$f"
sh "$EB" since "$OFF" > "$T_TMP/r4"
t_eq "the whole line before it is read, the half line is not" 'f ' "$(subjects "$T_TMP/r4")"
t_eq "...and the offset stops at the half line's first byte" "$pre" "$(awk '{ print $3 }' "$OFF")"
printf ',"repo":"","cause":"","data":{}}\n' >> "$f"
sh "$EB" since "$OFF" > "$T_TMP/r5"
t_eq "once whole, it is read exactly once" 'g ' "$(subjects "$T_TMP/r5")"
printf 'garbage that is not a record\n' >> "$f"; emit h
sh "$EB" since "$OFF" > "$T_TMP/r6"
t_eq "a line that is not a record is stepped over, not printed" 'h ' "$(subjects "$T_TMP/r6")"

t_section "consumers keep their own offsets"
sh "$EB" since "$OFF" --consumer other > "$T_TMP/r7"
t_eq "a second consumer reads everything" 'a b c d e f g h ' "$(subjects "$T_TMP/r7")"
t_eq "...and the first one did not move" '' "$(sh "$EB" since "$OFF")"
t_eq "one row each" 'default other' "$(awk '{ print $1 }' "$OFF" | sort | tr '\n' ' ' | sed 's/ $//')"
ino() { ls -i "$1" | awk '{ print $1 }'; }
i0="$(ino "$OFF")"; emit z; sh "$EB" since "$OFF" >/dev/null
t_eq "the offsets file is replaced, never rewritten in place (a new inode)" changed "$([ "$(ino "$OFF")" != "$i0" ] && echo changed || echo same)"

t_section "four consumers racing on one offsets file, while events land"
SH4="$T_TMP/shared"; : > "$T_TMP/emitting"; export HARBOR_EVENT_DIR="$T_TMP/racebus"
( i=0; while [ "$i" -lt 60 ]; do i=$((i + 1)); sh "$EB" emit test.race "r$i" >/dev/null; done; rm -f "$T_TMP/emitting" ) &
for c in c1 c2 c3 c4; do
  ( while [ -e "$T_TMP/emitting" ]; do sh "$EB" since "$SH4" --consumer "$c" >> "$T_TMP/$c.out"; done
    sh "$EB" since "$SH4" --consumer "$c" >> "$T_TMP/$c.out" ) &
done
wait
for c in c1 c2 c3 c4; do
  t_eq "$c read each race event exactly once" '60 60' \
    "$(jq -r 'select(.kind == "test.race") | .subject' "$T_TMP/$c.out" | awk '{ n++; u[$0] } END { m = 0; for (k in u) m++; print n + 0, m }')"
done
export HARBOR_EVENT_DIR="$T_TMP/bus"

t_section "a lock re-taken after its dead holder's pid was read is not taken over"
# Forced: as the waiter learns the old holder is dead, a live process takes the lock. The race above
# hits this window only by chance (hosted CI, 61 reads of 60).
L="$T_TMP/racelock"
verdict="$( eval "$(sed -n '/^offsets_lock() {/,/^}/p' "$EB")"
  sleep 30 > /dev/null & LIVE=$!
  ( exit 0 ) & DEAD=$!; wait "$DEAD"
  mkdir "$L"; echo "$DEAD" > "$L/pid"
  kill() {
    if [ "$1" = -0 ] && [ "$2" = "$DEAD" ] && [ ! -e "$L.swapped" ]; then
      : > "$L.swapped"; rm -rf "$L"; mkdir "$L"; echo "$LIVE" > "$L/pid"; return 1
    fi
    command kill "$@"
  }
  ( sleep 1; [ "$(cat "$L/pid" 2>/dev/null)" = "$LIVE" ] && echo intact > "$L.verdict"; rm -rf "$L" ) &
  REL=$!
  offsets_lock "$L" || echo timeout > "$L.verdict"
  wait "$REL"; command kill "$LIVE" 2>/dev/null
  cat "$L.verdict" 2>/dev/null || echo stolen )"
t_eq "the live holder keeps its lock; the waiter takes it once released" intact "$verdict"

t_section "a scan that cannot get the lock prints nothing, so the retry reads each line once"
# Forced: a live process holds the offsets lock for the whole wait. Before the fix the lines went out
# first and the offsets never moved, so the next scan printed them again (hosted CI: 71 reads of 60).
LB="$T_TMP/lockbus"; LO="$T_TMP/lockoff"
HARBOR_EVENT_DIR="$LB" sh "$EB" emit test.lock l1 >/dev/null; HARBOR_EVENT_DIR="$LB" sh "$EB" emit test.lock l2 >/dev/null
sleep 30 > /dev/null & HOLD=$!
mkdir "$LO.lock"; echo "$HOLD" > "$LO.lock/pid"
HARBOR_EVENT_DIR="$LB" HARBOR_EVENT_BUS_LOCK_TRIES=3 sh "$EB" since "$LO" > "$T_TMP/l1" 2>/dev/null; rc=$?
t_eq "the locked-out scan exits 1" 1 "$rc"
t_eq "...and prints no line" "" "$(cat "$T_TMP/l1")"
kill "$HOLD" 2>/dev/null; wait "$HOLD" 2>/dev/null; rm -rf "$LO.lock"
HARBOR_EVENT_DIR="$LB" sh "$EB" since "$LO" > "$T_TMP/l2"
t_eq "the retry reads each line once" 'l1 l2 ' "$(subjects "$T_TMP/l2")"
# uutils mkdir 0.10 (Ubuntu 26.04, ubuntu-latest) exits 0 when it loses a creation race; this one always loses.
UU="$T_TMP/uu"; mkdir -p "$UU"; MKD="$(command -v mkdir)"
printf '#!/bin/sh\ncase "$1" in -*) exec %s "$@" ;; esac\n%s -p -- "$@" && sleep 1\n' "$MKD" "$MKD" > "$UU/mkdir"; chmod +x "$UU/mkdir"
HARBOR_EVENT_DIR="$LB" sh "$EB" emit test.lock l3 >/dev/null
for k in 1 2; do HARBOR_EVENT_DIR="$LB" PATH="$UU:$PATH" sh "$EB" since "$LO" > "$T_TMP/uu$k" 2>/dev/null & done; wait
t_eq "two scans at once where mkdir cannot lock read the new line once between them (harbor#1378)" 'l3 ' \
  "$(cat "$T_TMP/uu1" "$T_TMP/uu2" > "$T_TMP/uu.both"; subjects "$T_TMP/uu.both")"

t_section "several day files, read in date order; a deleted day drops its row"
d1="$D"
printf '{"id":"old","ts":"t","src":"cli","kind":"test.since","subject":"yesterday"}\n' > "$T_TMP/bus/2000-01-01.jsonl"
sh "$EB" since "$T_TMP/fresh" > "$T_TMP/r8"
t_eq "the older day comes first" 'yesterday a' "$(subjects "$T_TMP/r8" | cut -d' ' -f1,2)"
t_eq "a row per day file" 2 "$(grep -c . "$T_TMP/fresh")"
rm -f "$T_TMP/bus/2000-01-01.jsonl"; sh "$EB" since "$T_TMP/fresh" >/dev/null
t_eq "the deleted day's row is gone" "default $d1" "$(cut -d' ' -f1,2 "$T_TMP/fresh")"

t_section "tail"
t_eq "tail 2: the last two whole lines" 'h z ' "$(sh "$EB" tail 2 | jq -r .subject | tr '\n' ' ')"
t_eq "tail: ten by default" 9 "$(sh "$EB" tail | grep -c .)"

t_section "errors"
sh "$EB" since > /dev/null 2>&1; rc=$?
t_eq "since with no offset file: exit 2" 2 "$rc"
sh "$EB" since "$OFF" --consumer 'a b' > /dev/null 2>&1; rc=$?
t_eq "a consumer name with a space: exit 2" 2 "$rc"
: > "$T_TMP/afile"
sh "$EB" since "$T_TMP/afile/offsets" > /dev/null 2> "$T_TMP/err"; rc=$?
t_eq "an offsets file that cannot be written: exit 1" 1 "$rc"
t_has "...said, then the fix" "$(cat "$T_TMP/err")" "the offsets did not move"
t_has "...with its fix line" "$(cat "$T_TMP/err")" "fix: ls -ld"
t_done
