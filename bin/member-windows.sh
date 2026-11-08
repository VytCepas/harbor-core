#!/usr/bin/env sh
# member-windows.sh (harbor#1278) — prints the PowerShell an administrator runs on a member's Windows laptop.
#   sh member-windows.sh --stage <dir> [--member <name>]    the script that writes a staged tree (member-install.sh builds it) under C:\Program Files\ClaudeCode;
#                                         with --member, also the Harbor Support shortcut that person starts remote support from
#   sh member-windows.sh --uninstall      the script that removes it
#   sh member-windows.sh --setup --pin <commit> --user <member> --hub <owner/name> --login <github login> --signers <file>
#                                         the whole laptop in one script: WSL and Ubuntu when absent, then the install inside as root, then the --stage script it prints
#
# THIS POWERSHELL HAS NEVER RUN. No PowerShell exists where it was built, so nothing here proves it on Windows. tests/member/windows reads
# the text back, decodes every file and compares the bytes; that proves the payload, not the commands around it. So all logic stays in this
# POSIX sh and the output is a dumb writer: fixed lines, one Put row per file, base64 only, nothing from outside in a string it evaluates.
# Its one branch is the F10 refusal: the HKLM value can change between printing and running, and only that moment is authoritative.
# --setup adds the branches only Windows can answer (is the distro there, did it want a restart, did the install ask for its Windows half). All else goes in as a file.
# Files land first and managed-settings.json last: settings that name a missing script would block every call (M9).
# Run from WSL it asks reg.exe first and refuses to print at all when a higher policy source exists.
set -eu
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
LOG_FD=2; export LOG_FD   # stdout is the PowerShell
. "$HERE/library-log.sh"
log_init member-windows
BASE='C:\Program Files\ClaudeCode'
# W4: the same folder as root in the distro sees it, and the only place an admin writes and a member can't, so root runs nothing from a folder a member can plant in.
WSL_BASE='/mnt/c/Program Files/ClaudeCode'
WSL_DISTRO=Ubuntu
# W4: the managed root as WSL sees it, in the shortcut's command line.
WSL_SUPPORT='/mnt/c/Program Files/ClaudeCode/harbor/bin/member-support.sh'
SHORTCUT='Microsoft\Windows\Start Menu\Programs\Harbor Support.lnk'
# The ledger is the one file a member appends to. A re-run must keep its records, so it is created only when absent.
SINK_RE='^harbor/MEMORY/OBSERVABILITY/[^/]*/guard-decisions\.jsonl$'

win_head() {
  printf '%s\n' \
    '# Written by bin/member-windows.sh (harbor#1278). Run as administrator. Untested on Windows: see that file.' \
    "\$ErrorActionPreference = 'Stop'" \
    "\$base = '$BASE'"
}
win_put_functions() {
  printf '%s\n' \
    "\$policy = 'HKLM:\\SOFTWARE\\Policies\\ClaudeCode'" \
    "if ((Test-Path \$policy) -and ((Get-Item \$policy).GetValue('Settings') -ne \$null)) { Write-Error 'refused: an HKLM policy outranks managed-settings.json, so this file would be silently ignored'; exit 1 }" \
    "function Put(\$rel, \$b64) { \$p = Join-Path \$base \$rel; New-Item -ItemType Directory -Force (Split-Path \$p) | Out-Null; [IO.File]::WriteAllBytes(\"\$p.new\", [Convert]::FromBase64String(\$b64)); Move-Item -Force \"\$p.new\" \$p }" \
    "function Keep(\$rel) { \$p = Join-Path \$base \$rel; if (-not (Test-Path \$p)) { Put \$rel '' } }"
}
# Registry: New-Item -Force on an existing key would drop its other values, so the key is made only when absent.
win_registry() {
  printf '%s\n' \
    "\$desktop = 'HKLM:\\SOFTWARE\\Policies\\Claude'" \
    "if (-not (Test-Path \$desktop)) { New-Item \$desktop | Out-Null }" \
    "New-ItemProperty -Force -Path \$desktop -Name disableWslSessions -PropertyType DWord -Value 0 | Out-Null"
}
# A person's way in (harbor#1278): a visible console window, because member-support.sh refuses anything else. Nothing autostarts.
win_shortcut() { # <member>
  printf '%s\n' \
    "\$lnk = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path \$env:ProgramData '$SHORTCUT'))" \
    "\$lnk.TargetPath = (Join-Path \$env:SystemRoot 'System32\\wsl.exe')" \
    "\$lnk.Arguments = '-d $WSL_DISTRO -u $1 --cd /home/$1/port --exec /bin/sh \"$WSL_SUPPORT\"'" \
    "\$lnk.Description = 'Ask your admin for help on this computer'" \
    "\$lnk.WindowStyle = 1" \
    "\$lnk.Save()"
}
# name_ok <account>: what useradd on the distro takes and a quoted string carries. A leading dot lets `..` through to /home/.., and
# all digits or over 32 would fail only on the laptop, after WSL is installed (tests/member/windows/sim-windows.sh).
name_ok() {
  case "$1" in ''|-*|.*|*[!A-Za-z0-9._-]*) return 1 ;; esac
  case "$1" in *[!0-9]*) ;; *) return 1 ;; esac
  [ "${#1}" -le 32 ]
}
# win_rel <path under the stage> -> the same path with backslashes; refuses anything but plain path characters, since it lands in a quoted string.
win_rel() {
  case "$1" in ''|*[!A-Za-z0-9._/-]*) return 1 ;; esac
  printf '%s' "$1" | tr '/' '\\'
}
win_stage() { # <stage dir>
  [ -f "$1/managed-settings.json" ] || { log_fail "$1 holds no managed-settings.json: not a staged tree"; log_nofix "bin/member-install.sh builds it"; return 1; }
  jq -e 'type == "object"' "$1/managed-settings.json" >/dev/null 2>&1 \
    || { log_fail "$1/managed-settings.json is not a JSON object, and Claude Code refuses to start on one (M9)"; log_nofix "bin/member-managed.sh"; return 1; }
  win_head; win_put_functions
  ( cd "$1" && find . -type f | sed 's|^\./||' | LC_ALL=C sort ) | grep -vx 'managed-settings.json' > "$_T/files"
  printf 'managed-settings.json\n' >> "$_T/files"
  while IFS= read -r _f; do
    _w="$(win_rel "$_f")" || { log_fail "a staged path carries a character the PowerShell can't quote: $_f"; log_nofix "contracts/member-files.txt"; return 1; }
    if printf '%s\n' "$_f" | grep -qE "$SINK_RE"; then
      printf "Keep '%s'\n" "$_w"
      # W4: AD is append-only for Users, so a member's hooks can add a record and never rewrite one. Whether drvfs opens it that way is W4.
      printf "& icacls.exe (Join-Path \$base '%s') /grant '*S-1-5-32-545:(AD)' | Out-Null\n" "$_w"
    else
      printf "Put '%s' '%s'\n" "$_w" "$(base64 < "$1/$_f" | tr -d '\n')"
    fi
  done < "$_T/files"
  win_registry
  [ -z "$MEMBER" ] || win_shortcut "$MEMBER"
  printf "Write-Output 'harbor: written. Return to the distro and run member-install.sh again.'\n"
}
# win_desktop: the shared desktop, because the administrator running this isn't the member who clicks.
win_desktop() { printf '%s\n' "\$desktop = [Environment]::GetFolderPath('CommonDesktopDirectory')"; }
# win_shortcuts <member>: W10: wsl.exe --cd is the one start folder Windows can set. The path is absolute, because the docs promise `~` alone, not `~/port`.
win_shortcuts() {
  _cd="-d $WSL_DISTRO -u $1 --cd /home/$1/port"
  printf '%s\n' \
    "function Shortcut(\$name, \$arguments) { \$l = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path \$desktop \"\$name.lnk\")); \$l.TargetPath = (Join-Path \$env:SystemRoot 'System32\\wsl.exe'); \$l.Arguments = \$arguments; \$l.Save() }" \
    "Shortcut 'Harbor setup' '$_cd'" \
    "Shortcut 'Harbor support' '$_cd --exec /bin/sh \"$WSL_BASE/harbor/bin/member-support.sh\"'"
}
# win_inner <pin> <member> <hub> <login>: root's script inside the distro, so what can be sh stays sh. Every value here passed the parser's checks.
win_inner() {
  printf '%s\n' \
    '#!/bin/sh' \
    '# Written by bin/member-windows.sh --setup (harbor#1278). Root, inside the distro. It asks nothing.' \
    'set -eu' \
    "id -u '$2' >/dev/null 2>&1 || useradd -m -s /bin/bash '$2'" \
    '# wsl --install --no-launch leaves no default user, and a session would then run as root, where nothing here holds.' \
    '# WSL reads `default = bob`, an indented key and a CRLF line too, so each counts as naming one (tests/member/windows/sim-windows.sh).' \
    "_d=\"\$(cat /etc/wsl.conf 2>/dev/null | tr -d '\\r' | sed -n 's/^[[:space:]]*default[[:space:]]*=[[:space:]]*//p' | sed 's/[[:space:]]*\$//')\"" \
    "if [ -z \"\$_d\" ]; then printf '\\n[user]\\ndefault=%s\\n' '$2' >> /etc/wsl.conf" \
    "elif [ \"\$_d\" != '$2' ]; then echo 'harbor: /etc/wsl.conf names another default user, and a session there sits outside this floor' >&2; exit 1; fi" \
    "exec /bin/sh '$WSL_BASE/setup/member-bootstrap.sh' --pin '$1' --user '$2' --hub '$3' --login '$4' --signers '$WSL_BASE/setup/hub-signers'"
}
win_setup() { # <pin> <member> <hub> <login> <signers> <bootstrap>
  win_head
  printf '%s\n' \
    "if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Write-Error 'refused: run this in PowerShell as administrator'; exit 1 }"
  win_put_functions
  printf '%s\n' \
    "\$distro = '$WSL_DISTRO'" \
    "\$inner = '$WSL_BASE/setup/member-wsl-setup.sh'" \
    "\$held = @(); try { \$held = @(& wsl.exe --list --quiet) -replace \"\`0\", '' | ForEach-Object { \$_.Trim() } } catch { \$held = @() }" \
    "if (\$held -notcontains \$distro) { & wsl.exe --install --distribution \$distro --no-launch; if (\$LASTEXITCODE -ne 0) { Write-Error \"harbor: wsl --install stopped with exit \$LASTEXITCODE\"; exit 1 } }" \
    "& wsl.exe -d \$distro -u root --exec /bin/true" \
    "if (\$LASTEXITCODE -ne 0) { Write-Output 'harbor: WSL needs a restart to finish. Restart Windows, then run this same script again.'; exit 3010 }"
  printf "Put 'setup\\member-bootstrap.sh' '%s'\n" "$(base64 < "$6" | tr -d '\n')"
  printf "Put 'setup\\hub-signers' '%s'\n" "$(base64 < "$5" | tr -d '\n')"
  printf "Put 'setup\\member-wsl-setup.sh' '%s'\n" "$(win_inner "$1" "$2" "$3" "$4" | base64 | tr -d '\n')"
  # Exit 3 is the install asking for its Windows half. cat, not \\wsl.localhost: whether an elevated shell reads that path is unproved.
  printf '%s\n' \
    "& wsl.exe -d \$distro -u root --exec /bin/sh \$inner" \
    "\$rc = \$LASTEXITCODE" \
    "if (\$rc -eq 3) {" \
    "  \$half = Join-Path \$base 'setup\\harbor-member.ps1'" \
    "  & wsl.exe -d \$distro -u root --exec cat /opt/harbor-member.ps1 | Set-Content -Encoding ASCII \$half" \
    "  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File \$half" \
    "  if (\$LASTEXITCODE -ne 0) { Write-Error 'harbor: the Windows half stopped'; exit 1 }" \
    "  & wsl.exe -d \$distro -u root --exec /bin/sh \$inner" \
    "  \$rc = \$LASTEXITCODE" \
    "}" \
    "if (\$rc -ne 0 -and \$rc -ne 4) { Write-Error \"harbor: the install inside \$distro stopped with exit \$rc\"; exit 1 }"
  win_desktop
  win_shortcuts "$2"
  printf '%s\n' \
    "& wsl.exe --terminate \$distro" \
    "Remove-Item -Recurse -Force (Join-Path \$base 'setup')" \
    "if (\$rc -eq 4) { Write-Output 'harbor: the floor is on, but not finished: every Claude Code step is refused until the token is stored with the member beside you (docs/how-to/member-install.md, The token).'; exit 4 }" \
    "Write-Output 'harbor: done.'"
}
win_uninstall() {
  win_head
  win_desktop
  printf '%s\n' \
    "Remove-Item -Force (Join-Path \$desktop 'Harbor setup.lnk') -ErrorAction SilentlyContinue" \
    "Remove-Item -Force (Join-Path \$desktop 'Harbor support.lnk') -ErrorAction SilentlyContinue" \
    "Remove-Item -Force (Join-Path \$env:ProgramData '$SHORTCUT') -ErrorAction SilentlyContinue" \
    "Remove-Item -Force (Join-Path \$base 'managed-settings.json') -ErrorAction SilentlyContinue" \
    "Remove-Item -Force (Join-Path \$base 'harbor-confinement') -ErrorAction SilentlyContinue" \
    "Remove-Item -Recurse -Force (Join-Path \$base 'harbor') -ErrorAction SilentlyContinue" \
    "Remove-ItemProperty -Path 'HKLM:\\SOFTWARE\\Policies\\Claude' -Name disableWslSessions -ErrorAction SilentlyContinue" \
    "Write-Output 'harbor: removed.'"
}

MODE=''; STAGE=''; PIN=''; MEMBER=''; HUB=''; LOGIN=''; SIGNERS=''
while [ $# -gt 0 ]; do
  case "$1" in
    --stage) [ $# -ge 2 ] || { log_fail "--stage needs a directory"; log_nofix "sh $0 --help"; exit 2; }; MODE=stage; STAGE="$2"; shift ;;
    --member)
      [ $# -ge 2 ] || { log_fail "--member needs a name"; log_nofix "sh $0 --help"; exit 2; }
      name_ok "$2" || { log_fail "--member wants an account name, got '$2'"; log_nofix "sh $0 --help"; exit 2; }
      MEMBER="$2"; shift ;;
    --uninstall) MODE=uninstall ;;
    --setup) MODE=setup ;;
    --pin|--user|--hub|--login|--signers)
      [ $# -ge 2 ] || { log_fail "$1 needs a value"; log_nofix "sh $0 --help"; exit 2; }
      case "$1" in --pin) PIN="$2" ;; --user) MEMBER="$2" ;; --hub) HUB="$2" ;; --login) LOGIN="$2" ;; --signers) SIGNERS="$2" ;; esac
      shift ;;
    -h|--help) awk 'NR<2{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;;
    *) log_fail "unknown argument $1"; log_nofix "sh $0 --help"; exit 2 ;;
  esac
  shift
done
[ -n "$MODE" ] || { log_fail "say --stage <dir>, --setup or --uninstall"; log_nofix "sh $0 --help"; exit 2; }
if [ "$MODE" = uninstall ]; then win_uninstall; log_end; exit $?; fi
# Every value here lands in a string the script runs, so each is held to its own alphabet. The HKLM check is the script's: no reg.exe is in reach of whoever prints it.
if [ "$MODE" = setup ]; then
  bad() { log_fail "$1"; log_nofix "sh $0 --help"; exit 2; }
  case "$PIN" in *[!0123456789abcdef]*|'') bad "--pin wants a 40-hex commit, got '$PIN'" ;; esac
  [ "${#PIN}" -eq 40 ] || bad "--pin wants a 40-hex commit, got '$PIN'"
  [ "$MEMBER" != root ] && name_ok "$MEMBER" || bad "--user wants the member's account name, got '$MEMBER'"
  slug_valid "$HUB" || bad "--hub wants owner/name, got '$HUB'"
  case "$LOGIN" in ''|-*|*[!A-Za-z0-9-]*) bad "--login wants a GitHub login, got '$LOGIN'" ;; esac
  [ -f "$SIGNERS" ] || bad "--signers: no file at $SIGNERS"
  [ -f "$HERE/member-bootstrap.sh" ] || { log_fail "no member-bootstrap.sh beside this script"; log_nofix "bin/member-bootstrap.sh"; exit 1; }
  win_setup "$PIN" "$MEMBER" "$HUB" "$LOGIN" "$SIGNERS" "$HERE/member-bootstrap.sh"; log_end; exit $?
fi
command -v jq >/dev/null 2>&1 || { log_fail "jq is missing"; log_fix "$(pkg_hint jq)"; exit 1; }
# F10: a higher source would make every byte below silently ignored, so there is no script to print.
_rc=0; _found="$(sh "$HERE/member-managed.sh" --higher-source)" || _rc=$?
if [ "$_rc" -ne 0 ]; then
  printf '%s\n' "$_found" | while IFS= read -r _l; do [ -z "$_l" ] || log_note "a higher policy source: $_l"; done
  log_fail 'refused: the script would write a file Claude Code silently ignores'
  log_nofix "remove that source, or move this policy into it; docs/how-to/member-install.md"
  exit 1
fi
_T="$(mktemp -d "${TMPDIR:-/tmp}/harbor.XXXXXX")"; trap 'rm -rf "$_T"' EXIT INT TERM
win_stage "$STAGE" || { log_end || :; exit 1; }
log_end
