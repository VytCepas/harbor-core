#!/usr/bin/env sh
# member-windows-access.sh (harbor#1581) — what a WSL member's distro may reach on the Windows side, set in /etc/wsl.conf.
#   sudo sh member-windows-access.sh status                  what is set now
#   sudo sh member-windows-access.sh default                 lock what nobody has chosen yet (member-install.sh runs this)
#   sudo sh member-windows-access.sh files   on|off          C: writable from WSL, or read-only (the default)
#   sudo sh member-windows-access.sh programs on|off         Windows programs (powershell.exe, explorer.exe) runnable from WSL, or not (the default)
# Exit 0 done, 1 refused, 2 usage. A change applies after WSL restarts, which it says.
# The person overrides by asking the agent, which runs this with sudo outside the sandbox after their Yes (harbor#1581, decision 6).
# C: stays MOUNTED either way: Claude Code on WSL reads the floor's managed settings under /mnt/c/Program Files/ClaudeCode, and without the
# mount it would fall back to /etc/claude-code, which root here writes. So read-only is a remount at boot, and if that remount fails C: stays
# writable and the floor stays read: the safe way to fail. `default` locks only what the person never chose: each choice is kept in
# <wsl.conf>.harbor-choice, because "unlocked" and "never set" look the same in wsl.conf itself.
# HARBOR_MEMBER_WINDOWS_ACCESS_FILE is a test seam, refused under root.
set -eu
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH='' cd -- "$HERE" && pwd -P)"
LOG_FD=2; export LOG_FD
. "$HERE/library-log.sh"
log_init member-windows-access
refuse() { log_fail "$1"; log_nofix 'docs/how-to/member-install.md, "Windows from WSL"'; log_end || :; exit "${2:-1}"; }
usage() { awk 'NR<2{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit "${1:-2}"; }

RO_CMD='mount -o remount,ro /mnt/c'
if [ -n "${HARBOR_MEMBER_WINDOWS_ACCESS_FILE:-}" ]; then
  [ "$(id -u)" -ne 0 ] || refuse 'HARBOR_MEMBER_WINDOWS_ACCESS_FILE is set under root: refusing a caller-chosen target'
  CONF="$HARBOR_MEMBER_WINDOWS_ACCESS_FILE"
else
  [ "$(id -u)" -eq 0 ] || refuse 'run it with sudo: /etc/wsl.conf is root'"'"'s'
  CONF=/etc/wsl.conf
fi

# ini_get <section> <key> -> the value, or nothing when unset. Keys and sections as WSL reads them: indented, any case, CRLF tolerated.
ini_get() {
  [ -f "$CONF" ] || return 0
  tr -d '\r' < "$CONF" | awk -v s="$1" -v k="$2" '
    /^[[:space:]]*\[/ { sec = $0; gsub(/^[[:space:]]*\[|\][[:space:]]*$/, "", sec); in_s = (tolower(sec) == tolower(s)); next }
    in_s && index($0, "=") { key = substr($0, 1, index($0, "=") - 1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      if (tolower(key) == tolower(k)) { v = substr($0, index($0, "=") + 1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); gsub(/^"|"$/, "", v); out = v } }
    END { if (out != "") print out }'
}
# ini_set <section> <key> <value|-> : sets the key in its section (adding either), or deletes it with -. Written by temp file and rename.
ini_set() {
  _new="$CONF.new.$$"
  # Blank lines inside the section are held back, so a new key lands before the blank line that separates it from the next section.
  { [ -f "$CONF" ] && tr -d '\r' < "$CONF" || :; } | awk -v s="$1" -v k="$2" -v v="$3" '
    function emit() { if (!done && v != "-") { print k "=" v; done = 1 } }
    function flush() { while (nb > 0) { print ""; nb-- } }
    /^[[:space:]]*\[/ { if (in_s) emit(); flush(); sec = $0; gsub(/^[[:space:]]*\[|\][[:space:]]*$/, "", sec); in_s = (tolower(sec) == tolower(s)); if (in_s) seen = 1; print; next }
    in_s && /^[[:space:]]*$/ { nb++; next }
    in_s && index($0, "=") { key = substr($0, 1, index($0, "=") - 1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      if (tolower(key) == tolower(k)) { flush(); emit(); next } }
    { flush(); print }
    END { if (in_s) emit(); flush(); if (!seen && v != "-") { print ""; print "[" s "]"; print k "=" v } }' > "$_new"
  chmod 0644 "$_new"; mv "$_new" "$CONF"
}
CHOICE="$CONF.harbor-choice"
chosen() { [ -f "$CHOICE" ] && grep -qx "$1 .*" "$CHOICE"; }
record() { { [ -f "$CHOICE" ] && grep -v "^$1 " "$CHOICE" || :; printf '%s %s\n' "$1" "$2"; } > "$CHOICE.new.$$"; chmod 0644 "$CHOICE.new.$$"; mv "$CHOICE.new.$$" "$CHOICE"; }
files_state() { [ "$(ini_get boot command)" = "$RO_CMD" ] && echo off || echo on; }
programs_state() { case "$(ini_get interop enabled)" in false|False|FALSE|0) echo off ;; *) echo on ;; esac; }
restart_note() { log_note 'this applies after WSL restarts: close Claude and every Ubuntu window, then restart Windows (or, in PowerShell, wsl --shutdown)'; }

set_files() { # on|off
  _cur="$(ini_get boot command)"
  if [ "$1" = off ]; then
    [ -z "$_cur" ] || [ "$_cur" = "$RO_CMD" ] || refuse "[boot] command is already '$_cur', and WSL runs only one: C: stays writable"
    ini_set boot command "$RO_CMD"; log_ok 'C: will be read-only from WSL'
  else
    [ "$_cur" != "$RO_CMD" ] || ini_set boot command -
    log_ok 'C: will be writable from WSL'
  fi
}
set_programs() { # on|off
  _b=true; [ "$1" = on ] || _b=false
  ini_set interop enabled "$_b"; ini_set interop appendWindowsPath "$_b"
  log_ok "Windows programs will $([ "$1" = on ] && echo 'run' || echo 'not run') from WSL"
}

[ $# -ge 1 ] || usage 2
case "$1" in
  --help|-h) usage 0 ;;
  status) [ $# -eq 1 ] || usage 2; printf 'files    %s\nprograms %s\n' "$(files_state)" "$(programs_state)"; exit 0 ;;
  default)
    [ $# -eq 1 ] || usage 2
    _ch=0
    if chosen files; then log_note "C: stays as the person chose: $(files_state)"
    elif [ -z "$(ini_get boot command)" ]; then set_files off; _ch=1
    elif [ "$(files_state)" = on ]; then log_note "[boot] command is '$(ini_get boot command)', so C: stays writable"; fi
    if chosen programs; then log_note "Windows programs stay as the person chose: $(programs_state)"
    elif [ -z "$(ini_get interop enabled)" ]; then set_programs off; _ch=1; fi
    [ "$_ch" -eq 0 ] || restart_note
    log_end; exit $? ;;
  files|programs)
    [ $# -eq 2 ] || usage 2
    case "$2" in on|off) ;; *) usage 2 ;; esac
    if [ "$1" = files ]; then set_files "$2"; else set_programs "$2"; fi
    record "$1" "$2"
    restart_note; log_end; exit $? ;;
  *) usage 2 ;;
esac
