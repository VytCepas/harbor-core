#!/usr/bin/env sh
# bin/alert-lib.sh (harbor#618): one notification helper, a fallback chain that is never silent and never an error.
# Every channel is a stub on a PATH without the host's own, so nothing is shown and nothing leaves the test.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/lib/linux-sim.sh"
P="$T_TMP/path"; linux_path "$P" osascript notify-send powershell.exe
LOGF="$T_TMP/sent.log"; : > "$LOGF"
stub() { # <name> <exit>: records its argv and the two text variables, then exits as told
  printf '#!/bin/sh\ncat >/dev/null 2>&1 &\nprintf "%%s|%%s|T=%%s|B=%%s|W=%%s\\n" "%s" "$*" "${HARBOR_NOTIFY_T:-}" "${HARBOR_NOTIFY_B:-}" "${WSLENV:-}" >> "%s"\nexit %s\n' "$1" "$LOGF" "$2" > "$P/$1"
  chmod +x "$P/$1"
}
unstub() { rm -f "$P/$1"; }
# one call in a child shell, as a notifier would make it: prints the channel and the exit
say() { PATH="$P" WSL_DISTRO_NAME="${WSLD:-}" ALERT_LIB_DIR="$T_ROOT/bin" sh -c '. "$1/bin/alert-lib.sh"; harbor_notify "$2" "$3"; echo "rc=$? sink=$NOTIFY_SINK"' _ "$T_ROOT" "$1" "$2" 2>"$T_TMP/err"; }
events() { cat "$HOME"/.local/state/harbor/events/*.jsonl 2>/dev/null | grep -c '"kind":"notify.unshown"'; }

t_section "the chain: the first channel that takes it"
t_eq "control: the stub PATH has none of the four channels" "" "$(PATH="$P" command -v osascript notify-send powershell.exe)"
stub osascript 0; stub notify-send 0
t_eq "osascript first" "rc=0 sink=osascript" "$(say 'sub' 'body')"
stub osascript 1
t_eq "osascript refuses: notify-send takes it" "rc=0 sink=notify-send" "$(say 'sub' 'body')"
unstub osascript
t_eq "no osascript: notify-send" "rc=0 sink=notify-send" "$(say 'sub' 'body')"
t_has "...titled Harbor" "$(tail -1 "$LOGF")" "notify-send|Harbor — sub body"
unstub notify-send; stub powershell.exe 0
t_eq "powershell.exe outside WSL is not a channel" "rc=0 sink=log" "$(say 'sub' 'body')"
WSLD=Ubuntu
t_eq "WSL2: a Windows toast" "rc=0 sink=wsl-toast" "$(say 'sub' 'body')"
_l="$(tail -1 "$LOGF")"
t_has "...the text travels in the environment" "$_l" "|T=sub|B=body|W=HARBOR_NOTIFY_T:HARBOR_NOTIFY_B"
stub powershell.exe 1
t_eq "WSL2 with no toast: logged" "rc=0 sink=log" "$(say 'sub' 'body')"
WSLD=; unstub powershell.exe

t_section "never silent, never an error"
_e0="$(events)"
t_eq "no channel at all: exit 0, sink=log" "rc=0 sink=log" "$(say 'pr 7' 'checks green')"
t_has "...a line on stderr" "$(cat "$T_TMP/err")" "harbor: pr 7 — checks green"
t_eq "...and one notify.unshown event on the bus" "$((_e0 + 1))" "$(events)"
t_has "...carrying the body as its title (the bus allowlist)" "$(cat "$HOME"/.local/state/harbor/events/*.jsonl | grep notify.unshown | tail -1)" '"title":"checks green"'
stub notify-send 1
t_eq "every channel refusing is still exit 0" "rc=0 sink=log" "$(say 'sub' 'body')"
unstub notify-send

t_section "the text is never code"
: > "$LOGF"; stub osascript 0
_evil='x"; rm -rf "$HOME'
say "$_evil" 'b' >/dev/null
t_has "osascript gets the subtitle as one argv item" "$(cat "$LOGF")" "osascript|- b $_evil|"
unstub osascript; stub powershell.exe 0; WSLD=Ubuntu; : > "$LOGF"
say "$_evil" 'b' >/dev/null
_l="$(cat "$LOGF")"
t_hasnt "powershell.exe's argv never holds the text" "${_l%%|T=*}" 'rm -rf'
t_has "...it is in the environment only" "$_l" "|T=$_evil|"
WSLD=; unstub powershell.exe
t_done
