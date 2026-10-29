#!/usr/bin/env sh
# alert-lib.sh (harbor#618) — one desktop notification helper with a fallback chain, sourced by every notifier.
#
#   . bin/alert-lib.sh
#   notify_sink                       the first channel this machine has: osascript | notify-send | wsl-toast | log
#   harbor_notify <subtitle> <body>   say it on the first channel that takes it; sets NOTIFY_SINK to that channel
#
# THE CHAIN. A macOS notification, else notify-send, else a Windows toast from WSL2, else a line on stderr and a
# `notify.unshown` event on the bus (bin/event-bus.sh). It is never silent and never an error: harbor_notify
# returns 0 whatever happened, and NOTIFY_SINK=log says no desktop channel took it, so a caller that must say an
# edge again later (pulse-notify) can tell a banner from a line nobody saw.
# NO INTERPOLATION. The text reaches osascript as argv and PowerShell through the environment (WSLENV), never
# inside a script string, so a subtitle cannot become code.
# platform: the one place an osascript call lives (lint.platform-calls refuses it anywhere else).
# Sourced, never run: it sets no shell option, and every function is safe under the caller's set -eu.

_notify_here="${ALERT_LIB_DIR:-}"
if [ -z "$_notify_here" ]; then
  case "$0" in */*) _notify_here="${0%/*}" ;; *) _notify_here=. ;; esac
fi

# WSL2 is Linux with a Windows host: powershell.exe on PATH and the kernel saying so.
_notify_wsl() {
  command -v powershell.exe >/dev/null 2>&1 || return 1
  [ -n "${WSL_DISTRO_NAME:-}" ] && return 0
  grep -qi microsoft /proc/version 2>/dev/null
}

notify_sink() {
  if command -v osascript >/dev/null 2>&1; then echo osascript
  elif command -v notify-send >/dev/null 2>&1; then echo notify-send
  elif _notify_wsl; then echo wsl-toast
  else echo log; fi
}

_notify_osascript() {
  command -v osascript >/dev/null 2>&1 || return 1
  osascript - "$2" "$1" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
  display notification (item 1 of argv) with title "Harbor" subtitle (item 2 of argv)
end run
APPLESCRIPT
}

_notify_send() {
  command -v notify-send >/dev/null 2>&1 || return 1
  notify-send "Harbor — $1" "$2" >/dev/null 2>&1
}

# A balloon from the Windows host. The sleep keeps the icon alive long enough to be seen.
_notify_wsl_toast() {
  _notify_wsl || return 1
  HARBOR_NOTIFY_T="$1" HARBOR_NOTIFY_B="$2" WSLENV="HARBOR_NOTIFY_T:HARBOR_NOTIFY_B${WSLENV:+:$WSLENV}" \
    powershell.exe -NoProfile -NonInteractive -Command '
      Add-Type -AssemblyName System.Windows.Forms
      $n = New-Object System.Windows.Forms.NotifyIcon
      $n.Icon = [System.Drawing.SystemIcons]::Information
      $n.BalloonTipTitle = "Harbor - " + $env:HARBOR_NOTIFY_T
      $n.BalloonTipText = $env:HARBOR_NOTIFY_B
      $n.Visible = $true
      $n.ShowBalloonTip(5000)
      Start-Sleep -Seconds 6
      $n.Dispose()' >/dev/null 2>&1
}

_notify_log() {
  printf 'harbor: %s — %s\n' "$1" "$2" >&2
  [ -f "$_notify_here/event-bus.sh" ] || return 0
  if command -v jq >/dev/null 2>&1; then
    sh "$_notify_here/event-bus.sh" emit notify.unshown "$1" --src alert-lib --data "$(jq -cn --arg b "$2" '{title: $b}')" >/dev/null 2>&1 || :
  else
    sh "$_notify_here/event-bus.sh" emit notify.unshown "$1" --src alert-lib >/dev/null 2>&1 || :
  fi
}

harbor_notify() { # <subtitle> <body>
  NOTIFY_SINK=log
  if _notify_osascript "$1" "$2"; then NOTIFY_SINK=osascript
  elif _notify_send "$1" "$2"; then NOTIFY_SINK=notify-send
  elif _notify_wsl_toast "$1" "$2"; then NOTIFY_SINK=wsl-toast
  else _notify_log "$1" "$2"; fi
  return 0
}
