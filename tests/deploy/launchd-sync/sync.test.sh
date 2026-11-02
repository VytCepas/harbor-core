#!/usr/bin/env sh
# sync.test.sh (harbor#1437) — bin/deploy-launchd-sync.sh: a deploy restarts the running jobs whose bytes changed, and only those.
# Also: it installs the plists that carry harbor:deploy-installs, and the live verify fails on a job running code older
# than its installed copy. launchctl is a stub; the "job" is a real sleep so ps has a start time to read.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/deploy-launchd-sync.sh"
LA="$HOME/Library/LaunchAgents"; mkdir -p "$LA" "$HOME/.claude/bin"
CALLS="$T_TMP/ctl.log"; : > "$CALLS"
# launchctl stub: `print` reports the pid kept in $T_TMP/pid.<label> (none = not running); `kickstart -k` replaces that
# process with a fresh sleep, as launchd would; bootout/bootstrap are logged.
cat > "$T_BIN/launchctl" <<STUB
#!/bin/sh
echo "\$*" >> "$CALLS"
case "\$1" in
  print) l="\${2##*/}"; [ -f "$T_TMP/pid.\$l" ] || exit 113; printf 'gui/501/%s = {\n\tpid = %s\n}\n' "\$l" "\$(cat "$T_TMP/pid.\$l")" ;;
  kickstart) l="\${3##*/}"; kill "\$(cat "$T_TMP/pid.\$l")" 2>/dev/null; sleep 300 >/dev/null 2>&1 & echo \$! > "$T_TMP/pid.\$l" ;;
esac
exit 0
STUB
chmod +x "$T_BIN/launchctl"
cleanup_kids() { for _k in $(cat "$T_TMP"/pid.* 2>/dev/null); do kill "$_k" 2>/dev/null; done; }
job() { # <name> <running 0|1> — an installed job com.harbor.<name> running $HOME/.claude/bin/<name>.sh
  printf '#!/bin/sh\necho v1\n' > "$HOME/.claude/bin/$1.sh"
  cat > "$LA/com.harbor.$1.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>Label</key><string>com.harbor.$1</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>$HOME/.claude/bin/$1.sh</string>
  </array>
</dict>
</plist>
PL
  if [ "$2" = 1 ]; then sleep 300 >/dev/null 2>&1 & echo $! > "$T_TMP/pid.com.harbor.$1"; fi
}
future() { touch -t "$(date -v+2M +%Y%m%d%H%M.%S 2>/dev/null || date -d '+2 min' +%Y%m%d%H%M.%S)" "$1"; }
job chg 1; job same 1; job idle 0
SNAP="$T_TMP/snap.tsv"

t_section "restart exactly the running jobs whose bytes changed"
sh "$TOOL" snapshot "$SNAP" > "$T_TMP/o" 2>&1; t_eq "snapshot exits 0" 0 "$?"
t_eq "...and records the three installed jobs" 3 "$(grep -c . "$SNAP")"
printf '#!/bin/sh\necho v2\n' > "$HOME/.claude/bin/chg.sh"       # new bytes
printf '#!/bin/sh\necho v2\n' > "$HOME/.claude/bin/idle.sh"      # new bytes, but not running
cp "$HOME/.claude/bin/same.sh" "$T_TMP/same.copy"; cp "$T_TMP/same.copy" "$HOME/.claude/bin/same.sh"   # a re-copy: same bytes
OLD_CHG="$(cat "$T_TMP/pid.com.harbor.chg")"; OLD_SAME="$(cat "$T_TMP/pid.com.harbor.same")"
: > "$CALLS"
sh "$TOOL" plan "$SNAP" > "$T_TMP/o" 2>&1; t_has "plan names the restart" "$(cat "$T_TMP/o")" "would restart com.harbor.chg"
t_eq "...and a plan calls no kickstart" 0 "$(grep -c kickstart "$CALLS")"
sh "$TOOL" apply "$SNAP" > "$T_TMP/o" 2>&1; t_eq "apply exits 0" 0 "$?"
t_eq "the changed running job is kickstarted -k" 1 "$(grep -c '^kickstart -k gui/[0-9]*/com.harbor.chg$' "$CALLS")"
t_hasnt "an unchanged job is not restarted" "$(grep kickstart "$CALLS")" "com.harbor.same"
t_hasnt "a changed job that is not running is not started" "$(grep kickstart "$CALLS")" "com.harbor.idle"
t_has "...and says its next run uses the new bytes" "$(cat "$T_TMP/o")" "com.harbor.idle changed and is not running"
t_eq "the restarted job has a new process" yes "$([ "$(cat "$T_TMP/pid.com.harbor.chg")" != "$OLD_CHG" ] && echo yes || echo no)"
t_eq "the untouched job keeps its process" "$OLD_SAME" "$(cat "$T_TMP/pid.com.harbor.same")"

t_section "verify: a job running a script older than its installed copy is red"
sh "$TOOL" verify > "$T_TMP/o" 2>&1; t_eq "right after apply every running job is current" 0 "$?"
# the file is newer than the process and its bytes changed since the ledger: the 2026-10 dispatcher case
printf '#!/bin/sh\necho v3\n' > "$HOME/.claude/bin/chg.sh"; future "$HOME/.claude/bin/chg.sh"
sh "$TOOL" verify > "$T_TMP/o" 2>&1; _rc=$?
t_eq "newer bytes under an older process: exit 1" 1 "$_rc"
t_has "...naming the job and the file" "$(cat "$T_TMP/o")" "com.harbor.chg"
t_has "...and the fix" "$(cat "$T_TMP/o")" "launchctl kickstart -k"
# identical bytes, newer mtime (a deploy re-copies every file): not stale, the ledger saw these bytes on this process
future "$HOME/.claude/bin/same.sh"
sh "$TOOL" verify > "$T_TMP/o" 2>&1
t_has "a re-copy of identical bytes is not a stale job" "$(grep 'com.harbor.same' "$T_TMP/o")" "runs the bytes installed"
sh "$TOOL" snapshot "$SNAP" >/dev/null 2>&1; sh "$TOOL" apply "$SNAP" > "$T_TMP/o" 2>&1
sh "$TOOL" verify > "$T_TMP/o" 2>&1; t_eq "after the restart verify is green again" 0 "$?"

t_section "the plists marked harbor:deploy-installs are installed when missing"
rm -f "$LA/com.harbor.event.dispatch.plist"
: > "$CALLS"; sh "$TOOL" plan "$SNAP" > "$T_TMP/o" 2>&1
t_has "plan names the install" "$(cat "$T_TMP/o")" "would install com.harbor.event.dispatch.plist"
t_eq "...and writes nothing" no "$([ -e "$LA/com.harbor.event.dispatch.plist" ] && echo yes || echo no)"
sh "$TOOL" apply "$SNAP" > "$T_TMP/o" 2>&1; t_eq "apply exits 0" 0 "$?"
t_eq "the plist is written" yes "$([ -f "$LA/com.harbor.event.dispatch.plist" ] && echo yes || echo no)"
t_has "...rendered for this HOME" "$(cat "$LA/com.harbor.event.dispatch.plist")" "$HOME/.claude/bin/event-dispatch.sh"
t_hasnt "...with no placeholder left" "$(cat "$LA/com.harbor.event.dispatch.plist")" "@HOME@"
t_eq "...and bootstrapped" 1 "$(grep -c '^bootstrap gui/[0-9]* .*com.harbor.event.dispatch.plist$' "$CALLS")"
: > "$CALLS"; sh "$TOOL" apply "$SNAP" > "$T_TMP/o" 2>&1
t_eq "a second apply installs and loads nothing" 0 "$(grep -c 'bootstrap\|bootout' "$CALLS")"

t_section "usage"
t_exit "no mode is a usage error" 2 sh "$TOOL"
t_exit "apply without a snapshot file is a usage error" 2 sh "$TOOL" apply
t_exit "apply with a snapshot that does not exist is exit 1" 1 sh "$TOOL" apply "$T_TMP/none.tsv"
cleanup_kids
t_done
