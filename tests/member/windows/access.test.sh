#!/usr/bin/env sh
# access.test.sh (harbor#1581) — bin/member-windows-access.sh: what a WSL member's distro reaches on Windows, in /etc/wsl.conf.
# Defaults lock only what nobody chose, a person's choice survives a later default, C: is never unmounted, and the rest of wsl.conf is kept.
. "$(dirname "$0")/../../lib/core.sh"; t_init
S="$T_ROOT/bin/member-windows-access.sh"; C="$T_TMP/wsl.conf"
W() { HARBOR_MEMBER_WINDOWS_ACCESS_FILE="$C" sh "$S" "$@" 2>"$T_TMP/err"; }
val() { tr -d '\r' < "$C" | awk -v s="$1" -v k="$2" '/^\[/ { in_s = ($0 == "[" s "]"); next } in_s && index($0, k "=") == 1 { print substr($0, length(k) + 2) }'; }

t_section "1 - default locks a fresh distro and keeps what was there"
printf '[boot]\r\nsystemd=true\r\n\r\n[user]\r\ndefault=gintare\r\n' > "$C"
t_eq "a fresh distro reads as open" "$(printf 'files    on\nprograms on')" "$(W status)"
t_exit "default runs" 0 env HARBOR_MEMBER_WINDOWS_ACCESS_FILE="$C" sh "$S" default
t_eq "C: becomes read-only" "$(printf 'files    off\nprograms off')" "$(W status)"
t_eq "by a remount at boot, so C: stays mounted for the floor's settings" 'mount -o remount,ro /mnt/c' "$(val boot command)"
t_eq "no automount row: unmounting C: would drop the floor" '' "$(val automount enabled)"
t_eq "interop off" false "$(val interop enabled)"
t_eq "and Windows PATH out" false "$(val interop appendWindowsPath)"
t_eq "systemd kept" true "$(val boot systemd)"
t_eq "the default user kept" gintare "$(val user default)"
t_eq "a key added to an existing section lands before its blank line, not glued to the next section" \
  "$(printf '[boot]\nsystemd=true\ncommand=mount -o remount,ro /mnt/c\n\n[user]\ndefault=gintare\n\n[interop]\nenabled=false\nappendWindowsPath=false')" "$(tr -d '\r' < "$C")"

t_section "2 - the person's choice survives a later default"
W files on; W programs on
t_eq "both opened" "$(printf 'files    on\nprograms on')" "$(W status)"
W default
t_eq "a re-install's default leaves the choice alone" "$(printf 'files    on\nprograms on')" "$(W status)"
W files off
t_eq "and the person can lock again" "$(printf 'files    off\nprograms on')" "$(W status)"
t_eq "CONTROL: without a recorded choice, default does lock" "$(printf 'files    off\nprograms off')" \
  "$(rm -f "$C.harbor-choice"; printf '[user]\ndefault=g\n' > "$C"; W default; W status)"

t_section "3 - refusals"
printf '[boot]\ncommand=service docker start\n' > "$C"; rm -f "$C.harbor-choice"
t_exit "another boot command is never overwritten" 1 env HARBOR_MEMBER_WINDOWS_ACCESS_FILE="$C" sh "$S" files off
t_eq "and it is still there" 'service docker start' "$(val boot command)"
t_exit "a bad value is usage" 2 env HARBOR_MEMBER_WINDOWS_ACCESS_FILE="$C" sh "$S" files maybe
t_exit "no verb is usage" 2 env HARBOR_MEMBER_WINDOWS_ACCESS_FILE="$C" sh "$S"
if [ "$(id -u)" -ne 0 ]; then
  t_exit "without the seam and without root it refuses, never touching /etc" 1 env -u HARBOR_MEMBER_WINDOWS_ACCESS_FILE sh "$S" status
fi
t_done
