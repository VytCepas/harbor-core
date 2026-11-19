#!/usr/bin/env sh
# network.test.sh (harbor#1582) — bin/status-network.sh, check status.network: on a metered network the jobs that pull megabytes are
# paused, any other process over the line is reported, bulk-download commands ask first; unmetered again, what was paused resumes.
# Measured 2026-11-19: Colima's CI runners pulled 753 MB in 33 min over an Android hotspot. route, ipconfig, arp, nettop, launchctl
# and colima are SHIMS reading fixture files; nothing real is read or changed.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/status-network.sh"
D="$T_TMP/shimdata"; SH_DIR="$T_TMP/shims"; mkdir -p "$D" "$SH_DIR" "$HOME/Library/LaunchAgents"
NET="$HOME/.local/state/harbor/net"; BUS="$T_TMP/bus"
HARBOR_EVENT_DIR="$BUS"; export HARBOR_EVENT_DIR
for c in route arp nettop; do
  printf '#!/bin/sh\n[ -f "%s/%s" ] || exit 1\ncat "%s/%s"\n' "$D" "$c" "$D" "$c" > "$SH_DIR/$c"; chmod +x "$SH_DIR/$c"
done
# ipconfig getpacket <if>: the lease in $D/lease.<if>, else exit 1 (no lease on that interface).
printf '#!/bin/sh\n[ -f "%s/lease.$2" ] || exit 1\ncat "%s/lease.$2"\n' "$D" "$D" > "$SH_DIR/ipconfig"; chmod +x "$SH_DIR/ipconfig"
# launchctl: print/bootout/bootstrap against $D/loaded (one label per line); every call is logged.
cat > "$SH_DIR/launchctl" <<EOF
#!/bin/sh
echo "\$*" >> "$D/launchctl.log"
L="\${2##*/}"
case "\$1" in
  print) grep -qxF "\$L" "$D/loaded" 2>/dev/null; exit \$? ;;
  bootout) grep -vxF "\$L" "$D/loaded" > "$D/loaded.n" 2>/dev/null; mv "$D/loaded.n" "$D/loaded" ;;
  bootstrap) b="\${3##*/}"; echo "\${b%.plist}" >> "$D/loaded" ;;
esac
exit 0
EOF
printf '#!/bin/sh\necho "colima $*" >> "%s/launchctl.log"\n' "$D" > "$SH_DIR/colima"; chmod +x "$SH_DIR/launchctl" "$SH_DIR/colima"
PATH="$SH_DIR:$PATH"; export PATH

hotspot() { printf '  gateway: 10.244.221.221\n  interface: en0\n' > "$D/route"
  printf 'server_identifier (ip): 10.244.221.221\nvendor_specific (opaque): \n0000  41 4e 44 52 4f 49 44 5f  4d 45 54 45 52 45 44     ANDROID_METERED \n' > "$D/lease.en0"; }
home_wifi() { printf '  gateway: 192.168.0.1\n  interface: en0\n' > "$D/route"; printf 'server_identifier (ip): 192.168.0.1\n' > "$D/lease.en0"; }
reset() { rm -rf "$NET" "$BUS" "$D"/lease.* "$D/launchctl.log"; printf 'sh.brew.colima\ncom.google.keystone.agent\ncom.harbor.event.dispatch\n' > "$D/loaded"
  for l in sh.brew.colima com.google.keystone.agent; do : > "$HOME/Library/LaunchAgents/$l.plist"; done
  rm -f "$D/nettop"; }
run() { sh "$TOOL" "$@" > "$T_TMP/out" 2>&1; echo "exit $?"; }
events() { cat "$BUS"/*.jsonl 2>/dev/null | jq -r '.kind + " " + .subject'; }

t_section "detection: what makes a network metered"
reset; hotspot
t_eq "Android hotspot (ANDROID_METERED in the lease): metered, exit 1" "exit 1" "$(run status)"
t_has "and it says why" "$(cat "$T_TMP/out")" "metered (android-hotspot:en0)"
printf 'server_identifier (ip): 172.20.10.1\n' > "$D/lease.en0"
t_has "iPhone hotspot (lease from 172.20.10.1): metered" "$(run status; cat "$T_TMP/out")" "metered (iphone-hotspot:en0)"
home_wifi
t_eq "home Wi-Fi: unmetered, exit 0" "exit 0" "$(run status)"
printf '? (192.168.0.1) at 0:5f:67:d0:82:6c on en0 ifscope [ethernet]\n' > "$D/arp"
printf '# the office tether\n00:5F:67:D0:82:6C\n' > "$CLAUDE_CONFIG_DIR/metered-networks"
t_has "a gateway listed in metered-networks: metered (MAC case and padding normalised)" "$(run status; cat "$T_TMP/out")" "metered (listed-gateway)"
rm -f "$CLAUDE_CONFIG_DIR/metered-networks"
printf '  gateway: 10.8.0.1\n  interface: utun4\n' > "$D/route"; rm -f "$D/lease.en0"; hotspot; printf '  gateway: 10.8.0.1\n  interface: utun4\n' > "$D/route"
mv "$D/lease.en0" "$D/lease.en1"
t_has "behind a VPN the hotspot lease underneath still counts" "$(run status; cat "$T_TMP/out")" "metered (android-hotspot:en1)"
rm -f "$D/route"
t_has "no route: offline, unmetered" "$(run status; cat "$T_TMP/out")" "unmetered (offline)"
home_wifi; sh "$TOOL" force metered >/dev/null
t_has "force metered wins over the lease" "$(run status; cat "$T_TMP/out")" "metered (forced)"
sh "$TOOL" force auto >/dev/null
t_has "force auto returns to detection" "$(run status; cat "$T_TMP/out")" "unmetered (en0)"
t_exit "force with no mode is a usage error" 2 sh "$TOOL" force

t_section "guard on a metered network: heavy jobs pause, hogs are reported, bulk commands ask"
reset; hotspot
printf ',bytes_in,bytes_out,\nlimactl.4317,10,1,\n,bytes_in,bytes_out,\nlimactl.4317,16000000,8000,\nGoogle Chrome H.2277,9000000,1,\ncom.microsoft.t.2320,5000000,1,\ngh.94317,96000,2900,\n' > "$D/nettop"
t_eq "a hog was found: exit 1" "exit 1" "$(run guard)"
t_has "colima is stopped before its job is unloaded" "$(cat "$D/launchctl.log")" "colima stop"
t_has "colima is disabled, so a login does not restart it" "$(cat "$D/launchctl.log")" "disable gui/"
t_eq "the paused list holds what it paused, and only that" "sh.brew.colima com.google.keystone.agent" "$(tr '\n' ' ' < "$NET/paused" | sed 's/ $//')"
t_has "harbor's own low-data jobs keep running" "$(cat "$D/loaded")" "com.harbor.event.dispatch"
t_hasnt "a heavy label that is not loaded is not touched" "$(grep -v "^print " "$D/launchctl.log")" "com.microsoft.update.agent"
t_has "limactl at ~3 MB/s is a hog" "$(cat "$NET/hogs")" "limactl	3126"
t_hasnt "Chrome is a browser: never reported" "$(cat "$NET/hogs")" "Google Chrome"
t_hasnt "Teams, truncated by nettop to com.microsoft.t, is a call app: never reported" "$(cat "$NET/hogs")" "com.microsoft"
t_hasnt "gh at 19 KB/s is under the line" "$(cat "$NET/hogs")" "gh"
t_has "the ask rules are on" "$(cat "$NET/ask-rules")" "Bash(docker pull *)"
t_has "events: metered" "$(events)" "network.metered android-hotspot:en0"
t_has "events: paused" "$(events)" "network.paused sh.brew.colima"
t_has "events: hog" "$(events)" "network.hog limactl"
run guard >/dev/null
t_eq "a hog still there on the next tick is not emitted again" 1 "$(events | grep -c 'network.hog limactl')"
t_eq "a second tick pauses nothing twice" 1 "$(grep -c '^sh.brew.colima$' "$NET/paused")"
t_eq "a second metered tick emits no second network.metered" 1 "$(events | grep -c '^network.metered')"

t_section "allow: the operator's yes for one job on this metered network"
t_eq "allow resumes it now" "exit 0" "$(run allow sh.brew.colima)"
t_has "it is loaded again" "$(cat "$D/loaded")" "sh.brew.colima"
t_hasnt "and no longer in the paused list" "$(cat "$NET/paused")" "sh.brew.colima"
: > "$D/launchctl.log"; rm -f "$D/nettop"; run guard >/dev/null
t_hasnt "the next tick leaves an allowed job alone" "$(cat "$D/launchctl.log"; echo .)" "sh.brew.colima"
t_eq "no hog this tick: exit 0, hogs cleared" "exit 0 absent" "$(run guard) $([ -e "$NET/hogs" ] && echo present || echo absent)"
sh "$TOOL" forbid sh.brew.colima >/dev/null; run guard >/dev/null
t_has "forbid: paused again at the next tick" "$(cat "$NET/paused")" "sh.brew.colima"
t_exit "allow with a label that is not a label is a usage error" 2 sh "$TOOL" allow 'x;rm -rf /'

t_section "guard on an unmetered network: what it paused resumes"
: > "$NET/allow/com.example.left"; home_wifi; : > "$D/launchctl.log"
t_eq "exit 0" "exit 0" "$(run guard)"
t_has "colima resumes from its plist" "$(cat "$D/launchctl.log")" "bootstrap gui/"
t_has "it is enabled again" "$(cat "$D/launchctl.log")" "enable gui/"
t_eq "the paused list is empty" "" "$(cat "$NET/paused")"
t_eq "the ask rules are off" absent "$([ -e "$NET/ask-rules" ] && echo present || echo absent)"
t_eq "an allow ends with the metered network" absent "$([ -e "$NET/allow/com.example.left" ] && echo present || echo absent)"
t_has "events: unmetered, resumed" "$(events)" "network.resumed sh.brew.colima"
t_has "events: unmetered" "$(events)" "network.unmetered en0"
: > "$D/launchctl.log"; run guard >/dev/null
t_eq "unmetered with nothing paused touches nothing" "" "$(cat "$D/launchctl.log")"

t_section "the tick lock"
mkdir -p "$NET/lock"
t_eq "a live lock: the second tick exits at once" "exit 0" "$(run guard)"
t_eq "and wrote nothing" "" "$(cat "$T_TMP/out")"
rmdir "$NET/lock"
t_done
