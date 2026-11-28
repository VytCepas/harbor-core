#!/usr/bin/env sh
# disk.test.sh (harbor#1060) — bin/status-disk.sh, check status.disk (operator decision 2026-11-23): free space on the data volume under a floor.
# Measured 2026-11-23: the Mac fell to 23 GB free of 460 GB and nothing said so. df is a SHIM printing a chosen free figure; nothing real is read.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/status-disk.sh"
CACHE="$T_TMP/cache"; mkdir -p "$CACHE"
DFB="$T_TMP/df"
# df -Pk <path>: the fixture's free KB in the fourth field of the second line (the header is df's own)
printf '#!/bin/sh\n[ -f "%s/free" ] || exit 1\nprintf "Filesystem 1024-blocks Used Available Capacity Mounted on\\n/dev/disk3s1 482000000 400000000 %%s 85%% /\\n" "$(cat "%s/free")"\n' "$T_TMP" "$T_TMP" > "$DFB"
chmod +x "$DFB"
GB=1048576
free() { echo "$(($1 * GB + ${2:-0}))" > "$T_TMP/free"; }   # <whole GB> [extra KB]
reset() { rm -f "$CACHE"/disk-free.json "$CACHE"/checks.log "$T_TMP/free"; }
run() { HARBOR_SCOPE_CACHE_DIR="$CACHE" HARBOR_STATUS_DISK_DF="$DFB" HARBOR_STATUS_DISK_PATH="$T_TMP" HARBOR_TEST_NOW=1790000000 sh "$TOOL" "$@" 2>&1; }
nlog() { if [ -f "$CACHE/checks.log" ]; then grep -c 'check:status.disk' "$CACHE/checks.log"; else echo 0; fi; }
EXIT() { run "$@" >/dev/null; echo $?; }

t_section "the floor: 30 GB, both sides of it"
reset; free 29 1000000
t_eq "29.9 GB free is under 30: exit 1" 1 "$(EXIT check)"
t_eq "...and the cache says low" true "$(jq -r .low "$CACHE/disk-free.json")"
reset; free 30
t_eq "exactly 30 GB is not under it: exit 0" 0 "$(EXIT check)"
t_eq "...and the cache says not low" false "$(jq -r .low "$CACHE/disk-free.json")"
reset; free 103
t_eq "103 GB free: exit 0" 0 "$(EXIT check)"
t_eq "...the cache carries the figure" 103 "$(jq -r '.free_gb | floor' "$CACHE/disk-free.json")"
t_eq "...the floor" 30 "$(jq -r .min_gb "$CACHE/disk-free.json")"
t_eq "...and the time" 1790000000 "$(jq -r .at "$CACHE/disk-free.json")"
t_eq "a floor from the environment: 103 GB is low under 200" 1 "$(HARBOR_STATUS_DISK_MIN_GB=200 EXIT check)"
t_eq "a decimal floor: 103 GB is fine over 102.5" 0 "$(HARBOR_STATUS_DISK_MIN_GB=102.5 EXIT check)"
t_eq "a junk floor falls back to 30: 29 GB is low" 1 "$(free 29; HARBOR_STATUS_DISK_MIN_GB=lots EXIT check)"

t_section "one line on a change, never one per tick"
reset; free 103; run check >/dev/null
t_eq "a first reading that is fine says nothing" 0 "$(nlog)"
free 24; run check >/dev/null
t_eq "fine to low: one line" 1 "$(nlog)"
t_has "...carrying the check id" "$(cat "$CACHE/checks.log")" "[check:status.disk] 2026-"
t_has "...the figure and the floor" "$(cat "$CACHE/checks.log")" "LOW: 24.0 GB free on $T_TMP, under the 30 GB floor"
t_has "...and where to look first" "$(cat "$CACHE/checks.log")" "sh bin/ci-runners.sh tidy"
run check >/dev/null; free 23; run check >/dev/null
t_eq "still low, the figure moving: no second line" 1 "$(nlog)"
free 41; run check >/dev/null
t_eq "low to fine: a second line" 2 "$(nlog)"
t_has "...says cleared and what it was" "$(tail -n 1 "$CACHE/checks.log")" "cleared (was low): 41.0 GB free"
run check >/dev/null
t_eq "fine again: nothing more" 2 "$(nlog)"
reset; free 12; run check >/dev/null
t_eq "a first reading that is low is said" 1 "$(nlog)"

t_section "status reads and writes nothing; off means off; an unreadable volume is not a calm one"
reset; free 12; OUT="$(run status)"
t_has "status prints the figure and the verdict" "$OUT" "12.0 GB free on $T_TMP, floor 30 GB: LOW"
t_eq "...writes no cache" no "$([ -e "$CACHE/disk-free.json" ] && echo yes || echo no)"
t_eq "...writes no log" 0 "$(nlog)"
t_eq "...exit 1 when low" 1 "$(EXIT status)"
reset; free 12; run check >/dev/null
OUT="$(HARBOR_STATUS_DISK_MIN_GB=0 run check)"; RC=$?
t_eq "a floor of 0 is off: exit 0" 0 "$RC"
t_eq "...and the cache goes, so the statusline shows nothing" no "$([ -e "$CACHE/disk-free.json" ] && echo yes || echo no)"
reset; OUT="$(run check)"; RC=$?
t_eq "df giving nothing: exit 2, not 0" 2 "$RC"
t_has "...and it says what could not be read" "$OUT" "could not be read"
t_eq "...no cache claimed" no "$([ -e "$CACHE/disk-free.json" ] && echo yes || echo no)"
t_exit "an unknown command is a usage error" 2 sh "$TOOL" frobnicate
t_red check.status.disk   # 4 planted defects each went red, 2026-11-23: floor < to <=, change-only logging, the 0 switch, the cleared line (and 3 in row2.test.sh for the statusline word)

t_done
