#!/usr/bin/env sh
# L0-5 (harbor#1032): the statusline BOX row (row 3 here: the config is pinned, so no YOU row), the machine
# (CPU, GPU, RAM, disk, swap) and then CI (2026-10-16 four-row layout). ioreg, vm_stat, sysctl, df,
# ps and iostat are SHIMS that cat a data file, so a source goes missing by deleting its file.
# `--dash` runs the subjects under dash.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/../../hooks/statusline-fixture.sh"
D="$TMP/shimdata"; SHIMS="$TMP/shims"; CPUC="$CFG/cache/machine-cpu"
mkdir -p "$D" "$SHIMS"
for _c in ioreg vm_stat sysctl df ps iostat route arp socketfilterfw; do
  printf '#!/bin/sh\n[ -f "%s/%s" ] || exit 127\ncat "%s/%s"\n' "$D" "$_c" "$D" "$_c" > "$SHIMS/$_c"; chmod +x "$SHIMS/$_c"
done
# One reading of every source; each test then changes only the file it is about.
reset() {
  printf '  | |   "PerformanceStatistics" = {"Device Utilization %%"=8,"Renderer Utilization %%"=5}\n' > "$D/ioreg"
  printf 'Mach Virtual Memory Statistics: (page size of 16384 bytes)\nPages wired down:   196984.\nPages purgeable:   15158.\nAnonymous pages:   794243.\nPages occupied by compressor:   198605.\n' > "$D/vm_stat"
  sysctl_set 1 434.31M
  printf '  0.5 /usr/sbin/mDNSResponder\n310.2 /usr/local/bin/python3.12\n 12.0 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome Helper\n' > "$D/ps"
  df_set 209715200
  printf '%s 63\n' "$NOW" > "$CPUC"
}
# 970000000 KiB volume; the argument is the KiB available (209715200 = 200G free, 21%).
df_set() { printf "Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/disk3s5 970000000 1 %s 79%% /System/Volumes/Data\n" "$1" > "$D/df"; }
sysctl_set() { # <pressure level> <swap used, with unit>
  printf 'kern.memorystatus_vm_pressure_level: %s\nvm.swapusage: total = 8192.00M  used = %s  free = 100.00M  (encrypted)\nvm.loadavg: { 12.41 11.20 10.10 }\nhw.memsize: 25769803776\n' "$1" "$2" > "$D/sysctl"
}
m() { printf '%s' "$1" | PATH="$SHIMS:$PATH" CLAUDE_CONFIG_DIR="$CFG" HARBOR_CACHE_DIR="$CFG/cache" HARBOR_NOW="$NOW" \
  HARBOR_GLYPH_MACHINE=1 HARBOR_GLYPH_MACHINE_REFRESH="${REFRESH:-0}" HARBOR_GLYPH_FW="$SHIMS/socketfilterfw" "$SH" "$SRC/status-fleet-glyph.sh" 2>/dev/null; }
# The fleet tile closes BOX and is the fleet suite.s subject: with no fleet cache here it reads `fleet: unknown`.
nofleet() { sed "s/ │ fleet: unknown$//; s/^fleet: unknown$//"; }
row3() { m "$@" | plain | sed -n 3p | nofleet; }
raw3() { m "$@" | sed -n 3p | nofleet; }
pin "$CFG"
P='{"model":{"display_name":"Opus 5"},'"$WS"'}'

t_section "row 3: the normal row, every segment"
reset
t_eq "the whole row, golden" "CPU 63% ·load 12.4 │ GPU 8% │ RAM 17.9/24G │ SSD 725/925G │ swap 0.4/8G" "$(row3 "$P")"
t_eq "row 1 is still SESSION" "Opus 5" "$(m "$P" | plain | sed -n 1p)"
t_hasnt "a normal row carries no yellow" "$(raw3 "$P")" "${ESC}[33m"
t_hasnt "a normal row carries no red" "$(raw3 "$P")" "${ESC}[31m"
t_hasnt "healthy is plain: no green anywhere (2026-10-16)" "$(raw3 "$P")" "${ESC}[32m"
t_hasnt "no double space on row 3" "$(row3 "$P")" '  '
t_eq "no top process under 70%" 0 "$(row3 "$P" | grep -c 'python')"

t_section "row 3: CPU at or over 70% is yellow and names the top process"
printf '%s 75\n' "$NOW" > "$CPUC"
t_eq "the top process is appended, path stripped" "CPU 75% ·load 12.4 ·python3.12 │ GPU 8% │ RAM 17.9/24G │ SSD 725/925G │ swap 0.4/8G" "$(row3 "$P")"
t_has "the CPU segment is yellow, name inside the span" "$(raw3 "$P")" "${ESC}[33mCPU 75% ·load 12.4 ·python3.12${ESC}[0m"
printf '%s 69\n' "$NOW" > "$CPUC"
t_hasnt "69% is under the line: no process, no colour" "$(raw3 "$P")" "${ESC}[33m"
printf '%s 70\n' "$NOW" > "$CPUC"
t_has "exactly 70% is over it" "$(row3 "$P")" "·python3.12"
t_has "exactly 70% is yellow" "$(raw3 "$P")" "${ESC}[33mCPU 70%"
printf '  0.5 /usr/sbin/mDNSResponder\n 12.0 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome Helper\n' > "$D/ps"
t_has "a name with spaces survives whole" "$(row3 "$P")" "·Google Chrome Help"
printf '  0.5 /usr/sbin/mDNSResponder\n' > "$D/ps"
t_has "the busiest of what ps lists, however small" "$(row3 "$P")" "·mDNSResponder"
rm -f "$D/ps"
t_hasnt "no ps: no process name" "$(row3 "$P")" 'python'
t_has "no ps: CPU still renders" "$(row3 "$P")" "CPU 70% ·load 12.4 │"

t_section "row 3: crit — everything red, pressure colours the RAM tile"
reset; printf '%s 95\n' "$NOW" > "$CPUC"
printf '  | |   "PerformanceStatistics" = {"Device Utilization %%"=95}\n' > "$D/ioreg"
sysctl_set 4 7000.00M
O="$(raw3 "$P")"
t_has "CPU is red" "$O" "${ESC}[31mCPU 95% ·load 12.4 ·python3.12${ESC}[0m"
t_has "GPU is red" "$O" "${ESC}[31mGPU 95%${ESC}[0m"
t_has "RAM is red under crit pressure" "$O" "${ESC}[31mRAM 17.9/24G${ESC}[0m"
t_has "swap is red at 6.8G" "$O" "${ESC}[31mswap 6.8/8G${ESC}[0m"
printf '%s 89\n' "$NOW" > "$CPUC"; t_has "89% is yellow" "$(raw3 "$P")" "${ESC}[33mCPU 89%"
printf '%s 90\n' "$NOW" > "$CPUC"; t_has "90% is red" "$(raw3 "$P")" "${ESC}[31mCPU 90%"

t_section "row 3: warn — yellow, pressure colours the RAM tile"
reset; printf '%s 75\n' "$NOW" > "$CPUC"
printf '  | |   "PerformanceStatistics" = {"Device Utilization %%"=75}\n' > "$D/ioreg"
sysctl_set 2 3000.00M
O="$(raw3 "$P")"
printf '  | |   "PerformanceStatistics" = {"Device Utilization %%"=70}\n' > "$D/ioreg"
t_has "GPU is yellow at exactly 70%" "$(raw3 "$P")" "${ESC}[33mGPU 70%"
printf '  | |   "PerformanceStatistics" = {"Device Utilization %%"=90}\n' > "$D/ioreg"
t_has "GPU is red at exactly 90%" "$(raw3 "$P")" "${ESC}[31mGPU 90%"
printf '  | |   "PerformanceStatistics" = {"Device Utilization %%"=75}\n' > "$D/ioreg"
t_has "GPU is yellow at 75%" "$O" "${ESC}[33mGPU 75%${ESC}[0m"
t_has "RAM is yellow under warn pressure" "$O" "${ESC}[33mRAM 17.9/24G${ESC}[0m"
t_has "swap is yellow at 2.9G" "$O" "${ESC}[33mswap 2.9/8G${ESC}[0m"
sysctl_set 1 6143.00M
t_has "6143M of swap is still yellow" "$(raw3 "$P")" "${ESC}[33mswap 6.0/8G"
sysctl_set 1 6144.00M
t_has "6144M of swap is red" "$(raw3 "$P")" "${ESC}[31mswap 6.0/8G"
sysctl_set 1 1.50G
t_has "a G-unit swap reading converts" "$(row3 "$P")" "swap 1.5/8G"
t_hasnt "1.5G is under the swap line" "$(raw3 "$P")" "${ESC}[33mswap"

t_section "row 3: a measured zero renders (swap aside), an absent value does not"
reset; printf '  | |   "PerformanceStatistics" = {"Device Utilization %%"=0}\n' > "$D/ioreg"
t_has "GPU 0% renders" "$(row3 "$P")" "GPU 0%"
printf '%s 0\n' "$NOW" > "$CPUC"
t_has "CPU 0% renders" "$(row3 "$P")" "CPU 0% ·load 12.4"
sysctl_set 1 0.00M
t_has "swap at zero still reads used/total (2026-10-16)" "$(row3 "$P")" "swap 0.0/8G"

t_section "row 3: a missing source omits its own segment and nothing else"
reset; rm -f "$D/ioreg"; O="$(row3 "$P")"
t_hasnt "no ioreg: no GPU" "$O" "GPU"
t_eq "no ioreg: the rest is intact" "CPU 63% ·load 12.4 │ RAM 17.9/24G │ SSD 725/925G │ swap 0.4/8G" "$O"
reset; rm -f "$D/vm_stat"; O="$(row3 "$P")"
t_eq "no vm_stat: no RAM tile (pressure only colours the size)" "CPU 63% ·load 12.4 │ GPU 8% │ SSD 725/925G │ swap 0.4/8G" "$O"
reset; rm -f "$D/sysctl"; O="$(row3 "$P")"
t_eq "no sysctl: load, RAM and swap go; disk stays" "CPU 63% │ GPU 8% │ SSD 725/925G" "$O"
reset; rm -f "$CPUC"; O="$(row3 "$P")"
t_eq "no CPU cache: load alone, no invented percentage" "load 12.4 │ GPU 8% │ RAM 17.9/24G │ SSD 725/925G │ swap 0.4/8G" "$O"
reset; printf '%s 63\n' "$((NOW - 121))" > "$CPUC"
t_hasnt "a stale CPU reading is not shown" "$(row3 "$P")" "CPU 6"
printf '%s 63\n' "$((NOW + 60))" > "$CPUC"
t_hasnt "a reading from the future is not shown" "$(row3 "$P")" "CPU 6"
printf '%s 63\n' "$((NOW - 120))" > "$CPUC"
t_has "120 s old is the last good age" "$(row3 "$P")" 'CPU 63%'

t_section "row 3: garbage in, nothing out"
reset; printf 'not a cache\n' > "$CPUC"; printf 'Device Utilization banana\n' > "$D/ioreg"
printf 'vm.loadavg: { nan }\nhw.memsize: lots\nvm.swapusage: ???\nkern.memorystatus_vm_pressure_level: 9\n' > "$D/sysctl"
printf 'what\n' > "$D/vm_stat"; printf 'Filesystem\n/dev/x lots none 9%%\n' > "$D/df"
O="$(m "$P" | plain)"
t_eq "garbage everywhere: BOX carries no machine segment" "" "$(row3 "$P")"
t_eq "and nothing from the machine leaks into any row" 0 "$(printf '%s\n' "$O" | grep -cE "CPU|GPU|RAM|SSD|swap|load")"
t_eq "nothing is printed to stderr" "" "$(printf '%s' "$P" | PATH="$SHIMS:$PATH" CLAUDE_CONFIG_DIR="$CFG" HARBOR_CACHE_DIR="$CFG/cache" HARBOR_NOW="$NOW" HARBOR_GLYPH_MACHINE=1 HARBOR_GLYPH_MACHINE_REFRESH=0 "$SH" "$SRC/status-fleet-glyph.sh" 2>&1 >/dev/null)"

t_section "row 3: no source at all (a Linux CI container) is no machine segment, no error"
reset; for _c in ioreg vm_stat sysctl df ps iostat; do rm -f "$D/$_c"; done; rm -f "$CPUC"
O="$(m "$P" | plain)"
t_eq "every shim failing: BOX holds no machine segment" "" "$(row3 "$P")"
t_eq "every shim failing: SESSION, PLACE, BOX" 3 "$(printf '%s\n' "$O" | wc -l | tr -d ' ')"
t_has "row 1 is untouched" "$O" "Opus 5"
BARE="$TMP/bare"; mkdir -p "$BARE"
for _c in jq date cat awk sed head tail stat tr grep cut sort wc sha256sum shasum git basename dirname mkdir ls uname id readlink env; do
  _p="$(command -v "$_c" 2>/dev/null || true)"; case "$_p" in /*) ln -sf "$_p" "$BARE/$_c" ;; esac
done
O="$(printf '%s' "$P" | PATH="$BARE" CLAUDE_CONFIG_DIR="$CFG" HARBOR_CACHE_DIR="$CFG/cache" HARBOR_NOW="$NOW" HARBOR_GLYPH_MACHINE=1 "$SH" "$SRC/status-fleet-glyph.sh" 2>&1 | plain)"
t_eq "with no ioreg/vm_stat/sysctl/df/ps/iostat on PATH at all: no machine segment" "" "$(printf '%s\n' "$O" | sed -n 3p | nofleet)"
t_has "control: a missing command in that PATH does say 'not found'" "$(PATH="$BARE" "$SH" -c 'nosuchcmd_x' 2>&1)" 'not found'
t_hasnt "no 'not found' noise" "$O" 'not found'
t_has "row 1 survives" "$O" "Opus 5"
t_eq "no stdin: PLACE and BOX only" 2 "$(printf '' | PATH="$BARE" CLAUDE_CONFIG_DIR="$CFG" HARBOR_CACHE_DIR="$CFG/cache" "$SH" "$SRC/status-fleet-glyph.sh" 2>&1 | wc -l | tr -d ' ')"

t_section "row 3: the off switch"
reset
t_eq "HARBOR_GLYPH_MACHINE=0 prints no machine segment" "" "$(printf '%s' "$P" | PATH="$SHIMS:$PATH" CLAUDE_CONFIG_DIR="$CFG" HARBOR_CACHE_DIR="$CFG/cache" HARBOR_NOW="$NOW" HARBOR_GLYPH_MACHINE=0 "$SH" "$SRC/status-fleet-glyph.sh" 2>/dev/null | plain | sed -n 3p | nofleet)"

t_section "BOX: CI inventory follows the machine; CI alarms go to YOU"
reset
CQ="$CFG/cache/ci-queue.json"; RS="$CFG/cache/runner-switch.json"; MT="$CFG/cache/main-tip-verdict.json"
printf '{"at":%s,"repos":[{"repo":"o/r","runners":4,"left":2,"eta":%s}]}\n' "$NOW" "$((NOW + 300))" > "$CQ"
printf '{"at":%s,"runner":"self-hosted","fallback":true,"percent":100,"unread":false}\n' "$NOW" > "$RS"
t_eq "machine, then CI, golden BOX" "CPU 63% ·load 12.4 │ GPU 8% │ RAM 17.9/24G │ SSD 725/925G │ swap 0.4/8G │ ⏳2 ·~5m │ CI→local 100%" "$(row3 "$P")"
t_hasnt "PLACE carries neither the queue nor the runner token" "$(m "$P" | plain | sed -n 2p)" 'CI'
printf '{"at":%s,"tip":{"sha":"abc","verdict":"failed","at":%s,"red":true}}\n' "$NOW" "$((NOW - 7200))" > "$MT"
box() { m "$@" | plain | tail -1 | nofleet; }
t_eq "a CI alarm is the YOU row, between PLACE and BOX" "MAIN RED 2h" "$(row3 "$P")"
t_has "MAIN RED is red" "$(m "$P" | sed -n 3p)" "${ESC}[31mMAIN RED 2h"
t_eq "and BOX keeps the machine and the CI inventory" "CPU 63% ·load 12.4 │ GPU 8% │ RAM 17.9/24G │ SSD 725/925G │ swap 0.4/8G │ ⏳2 ·~5m │ CI→local 100%" "$(box "$P")"
O="$(printf '%s' "$P" | HARBOR_GLYPH_COLS=60 PATH="$SHIMS:$PATH" CLAUDE_CONFIG_DIR="$CFG" HARBOR_CACHE_DIR="$CFG/cache" HARBOR_NOW="$NOW" HARBOR_GLYPH_MACHINE=1 HARBOR_GLYPH_MACHINE_REFRESH=0 "$SH" "$SRC/status-fleet-glyph.sh" 2>/dev/null | plain)"
t_eq "narrow: the alarm keeps its YOU row" "MAIN RED 2h" "$(printf '%s\n' "$O" | sed -n 3p)"
t_eq "narrow: BOX keeps the machine and drops the CI inventory" "CPU 63% ·load 12.4 │ GPU 8% │ RAM 17.9/24G │ SSD 725/925G │ swap 0.4/8G" "$(printf '%s\n' "$O" | sed -n 4p)"
off() { printf '%s' "$P" | PATH="$SHIMS:$PATH" CLAUDE_CONFIG_DIR="$CFG" HARBOR_CACHE_DIR="$CFG/cache" HARBOR_NOW="$NOW" HARBOR_GLYPH_MACHINE=0 "$SH" "$SRC/status-fleet-glyph.sh" 2>/dev/null | plain; }
t_eq "MACHINE=0 keeps the CI inventory on BOX and drops the machine" "⏳2 ·~5m │ CI→local 100%" "$(off | tail -1 | nofleet)"
rm -f "$CQ" "$RS" "$MT"
t_eq "MACHINE=0 and no CI: BOX holds only the fleet tile" "fleet: unknown" "$(off | tail -1)"
t_eq "machine alone, no CI: BOX is the machine" "CPU 63% ·load 12.4 │ GPU 8% │ RAM 17.9/24G │ SSD 725/925G │ swap 0.4/8G" "$(row3 "$P")"

t_section "BOX: SSD used/total, coloured by the share left (2026-10-16)"
reset; df_set 140000000
t_has "14% free is yellow" "$(raw3 "$P")" "${ESC}[33mSSD 791/925G${ESC}[0m"
df_set 145500000
t_hasnt "15% free is not coloured" "$(raw3 "$P")" "${ESC}[33mSSD"
df_set 300000000
t_has "30%+ free reads used/total" "$(row3 "$P")" "SSD 638/925G"
t_hasnt "30%+ free is not coloured" "$(raw3 "$P")" "${ESC}[33mSSD"
df_set 280000000
t_hasnt "28% free is not red" "$(raw3 "$P")" "${ESC}[31mSSD"
df_set 60000000
t_has "6% free is red" "$(raw3 "$P")" "${ESC}[31mSSD 867/925G${ESC}[0m"
rm -f "$D/df"
t_hasnt "no df: no disk tile, the rest intact" "$(row3 "$P")" "SSD"
t_has "no df: CPU still renders" "$(row3 "$P")" "CPU 63%"

t_section "row 3: is the internet safe, is Remote Control on (operator request 2026-10-12)"
reset
net() { # <firewall State> <interface>
  printf 'Firewall is enabled. (State = %s)\n' "$1" > "$D/socketfilterfw"
  printf '   route to: one.one.one.one\n    gateway: 192.168.0.1\n  interface: %s\n' "$2" > "$D/route"
  printf '? (192.168.0.1) at 0:5f:67:d0:82:6c on en0 ifscope [ethernet]\n' > "$D/arp"
}
TN="$CFG/trusted-networks"; rm -f "$TN"
GOLD="CPU 63% ·load 12.4 │ GPU 8% │ RAM 17.9/24G │ SSD 725/925G │ swap 0.4/8G"
net 1 en0
t_eq "untrusted Wi-Fi, no VPN: open lock, leftmost" "🔓 │ $GOLD" "$(row3 "$P")"
printf '# home\n00:5F:67:D0:82:6C\n' > "$TN"
t_eq "trusted gateway: house (case and zero padding normalised)" "🏠 │ $GOLD" "$(row3 "$P")"
printf '00:5f:67:d0:82:6d  # a neighbour\n' > "$TN"
t_has "a different gateway is not trusted" "$(row3 "$P")" "🔓 │"
rm -f "$D/arp"; printf '0:5f:67:d0:82:6c\n' > "$TN"
t_has "no arp: trust is unproven, so open" "$(row3 "$P")" "🔓 │"
net 1 utun4; rm -f "$TN"
t_has "default route through a tunnel: lock" "$(row3 "$P")" "🔒 │"
net 2 en0; printf '0:5f:67:d0:82:6c\n' > "$TN"
t_has "State = 2 is still a firewall on" "$(row3 "$P")" "🏠 │"
net 0 utun4
t_has "firewall off beats a VPN" "$(row3 "$P")" "🔓 │"
net 0 en0
t_has "firewall off beats a trusted network" "$(row3 "$P")" "🔓 │"
net 1 en0; rm -f "$D/socketfilterfw"
t_eq "no firewall reading: no safety icon, never a guess" "$GOLD" "$(row3 "$P")"
net 1 en0; rm -f "$D/route"
t_eq "no route (offline): no safety icon" "$GOLD" "$(row3 "$P")"
net 1 en0; rm -f "$TN"
mkdir -p "$CFG/sessions"; SP='{"session_id": "abc-123",'"${P#\{}"
printf '{"pid":1,"sessionId":"abc-123","bridgeSessionId":"session_01X"}\n' > "$CFG/sessions/1.json"
printf '{"pid":2,"sessionId":"zzz-999"}\n' > "$CFG/sessions/2.json"
t_eq "Remote Control linked: phone" "🔓 📱 │ $GOLD" "$(row3 "$SP")"
printf '{"pid":1,"sessionId":"abc-123"}\n' > "$CFG/sessions/1.json"
t_has "this session not linked: phone off" "$(row3 "$SP")" "🔓 📵 │"
t_hasnt "another session's link is not ours" "$(row3 '{"session_id":"zzz-999",'"${P#\{}")" "📱"
t_eq "no session_id in the payload: no RC icon" "🔓 │ $GOLD" "$(row3 "$P")"
t_eq "a session with no file: no RC icon" "🔓 │ $GOLD" "$(row3 '{"session_id":"nope",'"${P#\{}")"
O="$(printf '%s' "$SP" | HARBOR_GLYPH_COLS=60 PATH="$SHIMS:$PATH" CLAUDE_CONFIG_DIR="$CFG" HARBOR_CACHE_DIR="$CFG/cache" HARBOR_NOW="$NOW" HARBOR_GLYPH_MACHINE=1 HARBOR_GLYPH_MACHINE_REFRESH=0 HARBOR_GLYPH_FW="$SHIMS/socketfilterfw" "$SH" "$SRC/status-fleet-glyph.sh" 2>/dev/null | plain | sed -n 3p)"
t_has "narrow tier keeps the icons" "$O" "🔓 📵"
t_eq "MACHINE=0 drops the icons with the machine" "fleet: unknown" "$(printf "%s" "$SP" | PATH="$SHIMS:$PATH" CLAUDE_CONFIG_DIR="$CFG" HARBOR_CACHE_DIR="$CFG/cache" HARBOR_NOW="$NOW" HARBOR_GLYPH_MACHINE=0 HARBOR_GLYPH_FW="$SHIMS/socketfilterfw" "$SH" "$SRC/status-fleet-glyph.sh" 2>/dev/null | plain | tail -1)"
rm -rf "$CFG/sessions" "$D/socketfilterfw" "$D/route" "$D/arp"

t_section "row 3: the CPU sampler is detached, rate-limited and never blocks a render"
reset; rm -f "$CPUC"
printf ' us sy id 1m 5m 15m\n 17 20 63 4.83 3.75 5.09\n 43  2 55 4.83 3.75 5.09\n' > "$D/iostat"
REFRESH=1 m "$P" >/dev/null
_i=0; while [ ! -s "$CPUC" ] && [ "$_i" -lt 20 ]; do sleep 0.2; _i=$((_i + 1)); done
t_eq "the sampler writes 'epoch busy' from the LAST iostat line (100-idle)" "$NOW 45" "$(cat "$CPUC" 2>/dev/null)"
printf '%s 10\n' "$((NOW - 30))" > "$CPUC"; printf '%s\n' "$NOW" > "$CPUC.try"
REFRESH=1 m "$P" >/dev/null; sleep 1
t_eq "a stale cache within 5 s of the last spawn is NOT re-sampled" "$((NOW - 30)) 10" "$(cat "$CPUC")"
printf '%s 10\n' "$NOW" > "$CPUC"; printf '0\n' > "$CPUC.try"
REFRESH=1 m "$P" >/dev/null; sleep 1
t_eq "a fresh cache is not re-sampled either" "$NOW 10" "$(cat "$CPUC")"
printf '#!/bin/sh\nsleep 2\n: > "%s/iostat.done"\n' "$D" > "$SHIMS/iostat"
printf '%s 10\n' "$((NOW - 30))" > "$CPUC"; printf '0\n' > "$CPUC.try"; rm -f "$D/iostat.done"
REFRESH=1 m "$P" >/dev/null
t_eq "a 2 s iostat has not finished when the render returns" no "$(yn [ -f "$D/iostat.done" ])"
t_has "and the render showed the LAST value meanwhile" "$(REFRESH=0 row3 "$P")" "CPU 10%"
sleep 3

t_done
