#!/usr/bin/env sh
# bin/event-bus.sh emit under contention (harbor#1043): writers racing on one day file leave only
# whole lines — every line parses, none is lost, and every id is unique. Near-cap lines on purpose:
# the bigger the write, the likelier a split write tears.
. "$(dirname "$0")/../../lib/core.sh"; t_init
EB="$T_ROOT/bin/event-bus.sh"
export HARBOR_EVENT_DIR="$T_TMP/bus"
WRITERS=12; EACH=50
pad="$(awk 'BEGIN { while (n++ < 3500) printf "p" }')"

t_section "$WRITERS writers x $EACH near-cap emits on one file"
w=0
while [ "$w" -lt "$WRITERS" ]; do
  w=$((w + 1))
  ( i=0; while [ "$i" -lt "$EACH" ]; do i=$((i + 1))
      sh "$EB" emit test.race "w$w-$i" --data "{\"title\":\"$pad\"}" >/dev/null 2>&1
    done ) &
done
wait
f="$(find "$T_TMP/bus" -name '*.jsonl' | head -n 1)"
total=$((WRITERS * EACH))
t_eq "every emit landed as a line" "$total" "$(grep -c . "$f")"
t_eq "every line is a whole record: it starts and ends one object" "$total" "$(grep -c '^{"id":".*}$' "$f")"
t_eq "every line parses as JSON" "$total" "$(jq -c .subject "$f" 2>/dev/null | grep -c .)"
t_eq "every line is under the cap" 0 "$(awk 'length($0) + 1 > 4096' "$f" | grep -c .)"
t_eq "no id repeats" "$total" "$(jq -r .id "$f" 2>/dev/null | sort -u | grep -c .)"
t_eq "no subject is lost or doubled" "$total" "$(jq -r .subject "$f" 2>/dev/null | sort -u | grep -c .)"
t_done
