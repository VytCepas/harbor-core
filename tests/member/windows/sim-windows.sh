#!/usr/bin/env sh
# sim-windows.sh (harbor#1278) — the Windows path of bin/member-windows.sh run in real PowerShell 7, with Windows stubbed, before any Windows test.
#   sh tests/member/windows/sim-windows.sh       SIM_WINDOWS_TEST_MD=<windows-test.md> and SIM_WINDOWS_COLLEAGUE=<folder of send-to-colleagues/ and zips/> add the operator's blocks and the colleague launcher and guide; unset, named as unchecked
# Not *.test.sh, like real-upterm.sh: needs docker (none: FAIL, exit 2, never a skip). The first run builds sim-windows-pwsh:local with network (PowerShell 7 +
# PSScriptAnalyzer over ubuntu:24.04, dash as on WSL; docker rmi removes it); the run has none. The container is the laptop: PowerShell runs the printed script
# as written; the distro half runs as root for real (useradd, sudo, visudo, /etc/wsl.conf, git, the bootstrap, member-install.sh). Stubbed: wsl.exe, powershell.exe,
# icacls.exe, reg.exe, HKLM, WScript.Shell, the admin check, apt-get, curl (a fake upterm by digest), bwrap, socat, the tests/member/fixture.sh lanes; and
# CommonDesktopDirectory, '' off Windows, reads C:\Users\Public\Desktop. Unproven by any stub: real wsl.exe (exit codes, --no-launch, restart), WSL honouring wsl.conf, NTFS/drvfs, .lnk, Claude Desktop reading HKLM, PS 5.1, CRLF.
# shellcheck disable=SC2016 # the stub bodies and the Dockerfile are written out verbatim
if [ "${1:-}" = --inner ]; then INNER=1; else INNER=0; fi

if [ "$INNER" = 0 ]; then
  ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)"
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 || { echo "sim-windows: no docker daemon; refusing to substitute a weaker check" >&2; exit 2; }
  IMAGE=sim-windows-pwsh:local
  if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    case "$(docker info --format '{{.Architecture}}')" in
      x86_64|amd64) PWSH_IMAGE=mcr.microsoft.com/powershell:7.5-azurelinux-3.0 ;;
      aarch64|arm64) PWSH_IMAGE=mcr.microsoft.com/powershell:7.5-azurelinux-3.0-arm64 ;;
      *) echo "sim-windows: no PowerShell image for this architecture" >&2; exit 2 ;;
    esac
    printf '%s\n' \
      'ARG PWSH_IMAGE' 'FROM ${PWSH_IMAGE} AS ps' \
      'RUN pwsh -NoProfile -c "Set-PSRepository PSGallery -InstallationPolicy Trusted; Install-Module PSScriptAnalyzer -Scope AllUsers -Force"' \
      'FROM ubuntu:24.04' \
      'COPY --from=ps /opt/microsoft/powershell/7 /opt/microsoft/powershell/7' \
      'COPY --from=ps /usr/share/dotnet /usr/share/dotnet' \
      'COPY --from=ps /usr/local/share/powershell /usr/local/share/powershell' \
      'RUN apt-get update -q && DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends libicu74 libssl3t64 zlib1g jq git sudo openssh-client xxd ca-certificates >/dev/null && rm -rf /var/lib/apt/lists/* && ln -s /opt/microsoft/powershell/7/pwsh /usr/bin/pwsh' \
      'ENV DOTNET_ROOT=/usr/share/dotnet' \
      | docker build -q --build-arg PWSH_IMAGE="$PWSH_IMAGE" -t "$IMAGE" - >/dev/null || { echo "sim-windows: building $IMAGE failed" >&2; exit 2; }
  fi
  MD="${SIM_WINDOWS_TEST_MD:-}"
  [ -z "$MD" ] || [ -f "$MD" ] || { echo "sim-windows: SIM_WINDOWS_TEST_MD names no file: $MD" >&2; exit 2; }
  _x="$(mktemp -d "${TMPDIR:-/tmp}/sim-windows.XXXXXX")"; trap 'rm -rf "$_x"' EXIT
  [ -z "$MD" ] || cp "$MD" "$_x/windows-test.md"
  CO="${SIM_WINDOWS_COLLEAGUE:-}"
  [ -z "$CO" ] || [ -d "$CO/send-to-colleagues" ] || { echo "sim-windows: SIM_WINDOWS_COLLEAGUE has no send-to-colleagues/: $CO" >&2; exit 2; }
  [ -z "$CO" ] || { mkdir -p "$_x/colleague"; cp -R "$CO/send-to-colleagues" "$CO/zips" "$_x/colleague/"; }
  NAME="sim-windows-$$"
  COPYFILE_DISABLE=1 tar -C "$ROOT" -cf - bin contracts standards tests/lib tests/member -C "$_x" . 2>/dev/null \
    | docker run --rm -i --network none --name "$NAME" --entrypoint sh "$IMAGE" -c \
      'mkdir -p /src/repo && tar -xf - -C /src/repo 2>/dev/null; exec sh /src/repo/tests/member/windows/sim-windows.sh --inner'
  exit $?
fi

[ "$(id -u)" -eq 0 ] && [ -x /usr/bin/pwsh ] || { echo "sim-windows: --inner runs as root in the sim-windows image" >&2; exit 2; }
. "$(dirname "$0")/../../lib/core.sh"; t_init sim-windows
. "$T_ROOT/tests/member/fixture.sh"
unset HARBOR_SCOPE_MANAGED_SETTINGS   # the fixture's test seam: the distro half here runs as root, where it is refused
core_checkout
SIM=/sim; C="$SIM/C"; CC="$C/Program Files/ClaudeCode"; REG="$SIM/reg/HKLM/SOFTWARE/Policies"; LOG="$SIM/calls"
DESK="$C/Users""/Public/Desktop"; MENU="$C/ProgramData/Microsoft/Windows/Start Menu/Programs"; ADMIN="$C/Users""/admin"
mkdir -p "$C" "$REG" "$DESK" "$MENU" "$ADMIN" "$C/Windows/System32" "$SIM/state"
ln -s "$C" "$SIM/C:"          # .NET reads C:/x relative to /sim, the provider's C: drive reads /sim/C: one file, both views
mkdir -p /mnt; ln -s "$C" /mnt/c
git config --system url."$CORE".insteadOf https://github.com/VytCepas/harbor-core.git   # the bootstrap's own clone, offline
cp "$T_TMP/upterm.tar.gz" "$SIM/upterm.tar.gz"

# ── Windows, stubbed ───────────────────────────────────────────────────────────────────────────────────────────────────
# wsl.exe: state in $SIM/state. feature and distro are absent, pending (until a restart) or on. Lists print UTF-16LE, as wsl.exe does.
stub /usr/local/bin/wsl.exe \
  'S=/sim/state; printf "wsl.exe %s\n" "$*" >> /sim/calls' \
  'u16() { iconv -f UTF-8 -t UTF-16LE; }' \
  'feat="$(cat $S/feature 2>/dev/null || echo absent)"; dist="$(cat $S/distro 2>/dev/null || echo absent)"' \
  'case " $* " in *" --install "*)' \
  '  [ "${SIM_INSTALL_RC:-0}" = 0 ] || exit "$SIM_INSTALL_RC"' \
  '  if [ "$feat" = on ]; then if [ -n "${SIM_NOREG:-}" ]; then echo unregistered > $S/distro; else echo on > $S/distro; fi; else echo pending > $S/feature; echo pending > $S/distro; printf "Changes will not be effective until the system is rebooted.\r\n" | u16; fi; exit 0 ;; esac' \
  'case "$1" in' \
  '  --list|-l) if [ "$feat" != on ] || [ "$dist" != on ]; then printf "Windows Subsystem for Linux has no installed distributions.\r\n" | u16; exit 1; fi; printf "Ubuntu\r\n" | u16; exit 0 ;;' \
  '  --terminate) exit 0 ;;' \
  'esac' \
  '[ "$1 $2" = "-d Ubuntu" ] || { echo "wsl.exe stub: unknown call $*" >&2; exit 2; }; shift 2' \
  '[ "$feat" = on ] && [ "$dist" = on ] || { printf "There is no distribution with the supplied name.\r\n" | u16; exit 1; }' \
  'u=""; [ "$1" != -u ] || { u="$2"; shift 2; }; [ "$1" = --exec ] || [ "$1" = -- ] || { echo "wsl.exe stub: unknown call" >&2; exit 2; }; shift' \
  'sh=0; [ "$1" != /bin/sh ] || sh=1' \
  'set -- env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root WSL_DISTRO_NAME=Ubuntu CALLS=/sim/distro-calls "$@"' \
  '[ -z "$u" ] || [ "$u" = root ] || set -- sudo -u "$u" -H "$@"' \
  'if [ "$sh" = 1 ]; then n=$(( $(cat $S/n 2>/dev/null || echo 0) + 1 )); echo $n > $S/n' \
  '  "$@" > /sim/inner-$n.log 2>&1; rc=$?; cat /sim/inner-$n.log; printf "wsl.exe exit %s\n" $rc >> /sim/calls; exit $rc; fi' \
  'exec "$@"'
ln -s wsl.exe /usr/local/bin/wsl   # what a person types; Windows finds wsl.exe by PATHEXT
stub /usr/local/bin/powershell.exe \
  'printf "powershell.exe %s\n" "$*" >> /sim/calls; f=""' \
  'while [ $# -gt 0 ]; do case "$1" in -File) f="$2"; shift 2; break ;; -Command) shift; exec pwsh -NoProfile -NonInteractive -Command "$*" ;; -ExecutionPolicy) shift ;; esac; shift; done' \
  '[ "${SIM_HALF_RC:-0}" = 0 ] || exit "$SIM_HALF_RC"' \
  'f="$(printf "%s" "$f" | tr "\\\\" /)"; case "$f" in .*) f="$PWD/$f"; exec pwsh -NonInteractive -File "$f" "$@" ;; esac' \
  'cd /sim && exec pwsh -NonInteractive -File "$f" "$@"'
stub /usr/local/bin/icacls.exe 'printf "icacls.exe %s\n" "$*" >> /sim/calls'
stub /usr/local/bin/whoami.exe 'printf "whoami.exe %s\n" "$*" >> /sim/calls; [ "$1" = /groups ] || exit 2; printf "S-1-1-0\n"; [ -n "${SIM_NOADMIN:-}" ] || printf "S-1-5-32-544\n"'
echo 2026-11-09T08:00:00 > "$SIM/boot"; echo 0 > "$SIM/bootn"
reboot() { _n=$(( $(cat "$SIM/bootn") + 1 )); echo "$_n" > "$SIM/bootn"; printf '2026-11-09T08:%02d:00\n' "$_n" > "$SIM/boot"; }   # Windows restarted
# reg.exe where WSL finds it: the distro half's F10 check (member-managed.sh --higher-source) asks it.
stub "$C/Windows/System32/reg.exe" 'printf "reg.exe %s\n" "$*" >> /sim/calls' \
  '[ "$1" = query ] && [ "$3" = /v ] || exit 1; [ -f "/sim/reg/$(printf "%s" "$2" | tr "\\\\" /)/$4" ]'
# The distro's root tools that would reach the network or the kernel.
stub /usr/bin/apt-get 'printf "apt-get %s\n" "$*" >> /sim/distro-calls'
stub /usr/bin/bwrap 'exit 0'
stub /usr/bin/socat 'exit 0'
stub /usr/bin/curl 'while [ $# -gt 0 ]; do [ "$1" != --output ] || { cp /sim/upterm.tar.gz "$2"; exit 0; }; shift; done; exit 1'

# The profile every pwsh here loads: the C: drive, HKLM as folders, WScript.Shell, the admin check. Each stub records its call in $LOG.
PSHOME_DIR="$(dirname "$(readlink -f /usr/bin/pwsh)")"
cat > "$PSHOME_DIR/profile.ps1" <<'PS'
$PSStyle.OutputRendering = 'PlainText'
$null = New-PSDrive -Name C -PSProvider FileSystem -Root '/sim/C' -Scope Global
[Environment]::CurrentDirectory = '/sim'; Set-Location /sim
$env:ProgramData = 'C:\ProgramData'; $env:SystemRoot = 'C:\Windows'
function global:SimLog([string]$s) { [IO.File]::AppendAllText('/sim/calls', "$s`n") }
function global:SimReg([string]$p) { '/sim/reg/' + (($p -replace '^HKLM:\\?', 'HKLM/') -replace '\\', '/') }
class SimIdentity { static [object] GetCurrent() { return [pscustomobject]@{ Name = $(if ($env:SIM_ME) { $env:SIM_ME } else { 'SIMPC\admin' }) } } }
class SimPrincipal {
  [object]$Who
  SimPrincipal([object]$w) { $this.Who = $w }
  [bool] IsInRole([object]$r) { [IO.File]::AppendAllText('/sim/calls', "IsInRole $r`n"); return $env:SIM_ADMIN -ne '0' }
}
class SimRole { static [string] $Administrator = 'Administrator' }
$ta = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
$ta::Add('Security.Principal.WindowsIdentity', [SimIdentity]); $ta::Add('Security.Principal.WindowsPrincipal', [SimPrincipal]); $ta::Add('Security.Principal.WindowsBuiltInRole', [SimRole])
function global:Test-Path {
  if ("$($args[0])" -like 'HKLM:*') { SimLog "Test-Path $($args[0])"; return [IO.Directory]::Exists((SimReg $args[0])) }
  Microsoft.PowerShell.Management\Test-Path @args
}
function global:Get-Item {
  if ("$($args[0])" -like 'HKLM:*') {
    $d = SimReg $args[0]; SimLog "Get-Item $($args[0])"
    if (-not [IO.Directory]::Exists($d)) { Write-Error "Cannot find path '$($args[0])' because it does not exist."; return }
    $o = [pscustomobject]@{ PSPath = $args[0]; SimDir = $d }
    $o | Add-Member -MemberType ScriptMethod -Name GetValue -Value { param($n) $f = [IO.Path]::Combine($this.SimDir, $n); if ([IO.File]::Exists($f)) { ([IO.File]::ReadAllText($f) -split ':', 2)[1] } else { $null } }
    return $o
  }
  Microsoft.PowerShell.Management\Get-Item @args
}
function global:New-Item {
  $hk = @($args | Where-Object { "$_" -like 'HKLM:*' })
  if ($hk.Count) {
    $d = SimReg $hk[0]; SimLog "New-Item $($args -join ' ')"
    if ([IO.Directory]::Exists($d)) {
      if (@($args | Where-Object { "$_" -eq '-Force' }).Count) { Get-ChildItem -LiteralPath $d -File | Remove-Item; return }   # what -Force does to a key: its values go
      Write-Error "A key at this path already exists."; return
    }
    if (-not [IO.Directory]::Exists([IO.Path]::GetDirectoryName($d))) { Write-Error "The parent of $($hk[0]) does not exist."; return }
    [void][IO.Directory]::CreateDirectory($d); return [pscustomobject]@{ Name = $hk[0] }
  }
  Microsoft.PowerShell.Management\New-Item @args
}
function global:New-ItemProperty {
  [CmdletBinding()] param([string]$Path, [string]$Name, [string]$PropertyType, [object]$Value, [switch]$Force)
  if ($Path -notlike 'HKLM:*') { throw "sim: New-ItemProperty outside HKLM: $Path" }
  $d = SimReg $Path; SimLog "New-ItemProperty $Path $Name $PropertyType $Value force=$Force"
  if (-not [IO.Directory]::Exists($d)) { Write-Error "Cannot find path '$Path' because it does not exist."; return }
  $f = [IO.Path]::Combine($d, $Name)
  if ([IO.File]::Exists($f) -and -not $Force) { Write-Error "The property already exists."; return }
  [IO.File]::WriteAllText($f, "${PropertyType}:$Value"); [pscustomobject]@{ $Name = $Value }
}
function global:Remove-ItemProperty {
  [CmdletBinding()] param([string]$Path, [string]$Name)
  SimLog "Remove-ItemProperty $Path $Name"
  $f = [IO.Path]::Combine((SimReg $Path), $Name)
  if (-not [IO.File]::Exists($f)) { Write-Error "Property $Name does not exist at path $Path."; return }
  [IO.File]::Delete($f)
}
function global:New-Object {
  [CmdletBinding()] param([Parameter(Position = 0)][string]$TypeName, [Parameter(Position = 1)][object[]]$ArgumentList, [string]$ComObject)
  if (-not $ComObject) { return Microsoft.PowerShell.Utility\New-Object @PSBoundParameters }
  SimLog "New-Object -ComObject $ComObject"
  if ($ComObject -ne 'WScript.Shell') { throw "sim: no COM object $ComObject" }
  $sh = [pscustomobject]@{}
  $sh | Add-Member -MemberType ScriptMethod -Name CreateShortcut -Value {
    param($p)
    if ($p -notlike '*.lnk') { throw "sim: a shortcut path ends in .lnk, got $p" }
    $l = [pscustomobject]@{ FullName = $p; TargetPath = ''; Arguments = ''; Description = ''; WindowStyle = 1; WorkingDirectory = '' }
    $l | Add-Member -MemberType ScriptMethod -Name Save -Value {
      $dir = Split-Path $this.FullName
      if (-not (Microsoft.PowerShell.Management\Test-Path -LiteralPath $dir)) { throw "sim: no folder $dir" }
      SimLog "Shortcut.Save $($this.FullName)"
      [ordered]@{ TargetPath = $this.TargetPath; Arguments = $this.Arguments; Description = $this.Description; WindowStyle = $this.WindowStyle } | ConvertTo-Json | Microsoft.PowerShell.Management\Set-Content -LiteralPath $this.FullName
    }
    $l
  }
  $sh
}
# A restart-needed wsl --install that exits non-zero: Linux keeps only the low byte of an exit code (3010 is 194), so PowerShell's $LASTEXITCODE is set here.
if ($env:SIM_INSTALL_REBOOT_RC) {
  function global:wsl.exe { & /usr/local/bin/wsl.exe @args; if ("$args" -match '--install') { $global:LASTEXITCODE = [int]$env:SIM_INSTALL_REBOOT_RC } }
}
# Windows' last boot, read from /sim/boot: a restart is a new value there.
function global:Get-CimInstance {
  param([string]$ClassName)
  SimLog "Get-CimInstance $ClassName"
  [pscustomobject]@{ LastBootUpTime = [datetime]::Parse(([IO.File]::ReadAllText('/sim/boot')).Trim(), [cultureinfo]::InvariantCulture) }
}
# The launcher's elevation: the encoded command runs in this process, with its closing `exit $rc` turned into a variable, so a 32-bit exit code survives Linux.
function global:Start-Process {
  [CmdletBinding()] param([string]$FilePath, [string]$Verb, [switch]$Wait, [switch]$PassThru, [string]$ArgumentList)
  SimLog "Start-Process $FilePath verb=$Verb"
  if ($FilePath -ne 'powershell.exe' -or $Verb -ne 'RunAs') { throw "sim: Start-Process $FilePath $Verb" }
  if ($env:SIM_UAC -eq 'no') { throw [InvalidOperationException]::new('This command cannot be run due to the error: The operation was canceled by the user.', [ComponentModel.Win32Exception]::new(1223)) }
  $txt = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($ArgumentList.Split(' ')[-1]))
  if ([regex]::Matches($txt, '(?m)^exit \$rc\s*$').Count -ne 1) { throw 'sim: the elevated command no longer ends in exit $rc' }
  $global:SimRc = $null
  # An error that stops the elevated command ends that process at once: exit 1, no result file, the transcript closed by the exit.
  try { & ([scriptblock]::Create([regex]::Replace($txt, '(?m)^exit \$rc\s*$', '$global:SimRc = $rc'))) | Out-Host }
  catch { $global:SimRc = 1; Write-Host ($_ | Out-String); try { Stop-Transcript | Out-Null } catch { $null = $_ } }
  [pscustomobject]@{ ExitCode = $global:SimRc }
}
PS

# ── helpers ────────────────────────────────────────────────────────────────────────────────────────────────────────────
PIN40="$PIN"; HUB=fixture-org/fixture-hub; LOGIN=alice-gh
SETUP="$ADMIN/harbor-setup.ps1"; UNINST="$ADMIN/uninstall.ps1"
# runnable <src> <dst>: the one rewrite, counted first, so a script that stops calling it fails here instead of passing untouched.
DESK_CALL="[Environment]::GetFolderPath('CommonDesktopDirectory')"
runnable() { _n="$(grep -c -F "$DESK_CALL" "$1")"; [ "$_n" -le 1 ] || return 1; sed "s/\[Environment\]::GetFolderPath('CommonDesktopDirectory')/'C:\\\\Users\\\\Public\\\\Desktop'/" "$1" > "$2"; }
RUN=0
ps_run() { # <script> -> RC, OUT; the operator's command, under the profile
  RUN=$((RUN + 1)); OUT="$T_TMP/run-$RUN.out"; RC=0
  ( cd "$SIM" && pwsh -NonInteractive -File "$1" ) > "$OUT" 2>&1 || RC=$?
  printf -- '--- run %s exit %s\n' "$RUN" "$RC" >> "$LOG"
}
# Windows keeps a 32-bit exit code, Linux its low byte (3010 is 194 here), so the full one is read from inside PowerShell too.
full_rc() { ( cd "$SIM" && pwsh -NonInteractive -Command "& '$1' *> \$null; [IO.File]::WriteAllText('/sim/rc', \"\$LASTEXITCODE\")" ) >/dev/null 2>&1; cat "$SIM/rc"; }
calls() { grep -v '^---' "$LOG" 2>/dev/null; }
seq_of() { calls | sed -n -e 's/^\(wsl\.exe [^/]*\).*/\1/p' -e 's/^\(powershell\.exe\).*/\1/p' | sed 's/ *$//' | tr '\n' '|'; }
win_reset() { rm -f "$C/ProgramData/harbor-setup-restart.txt"; rm -rf "$SIM"/inner-*.log "$CC" "$DESK"/*.lnk "$MENU"/*.lnk "$SIM/state" "$SIM/reg/HKLM/SOFTWARE/Policies/Claude" "$SIM/reg/HKLM/SOFTWARE/Policies/ClaudeCode"; mkdir -p "$SIM/state"; : > "$LOG"; : > "$SIM/distro-calls"; }
distro_reset() { userdel -r alice >/dev/null 2>&1; rm -rf /home/alice /opt/harbor-core /opt/harbor-member.ps1 /etc/wsl.conf /etc/sudoers.d/harbor-member-prereqs /etc/profile.d/harbor-member.sh; }
snap() { find "$C" "$SIM/reg" /etc/wsl.conf /etc/sudoers.d /etc/profile.d/harbor-member.sh -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r _f; do printf '%s %s\n' "$(sha256sum < "$_f" | cut -c1-16)" "$_f"; done; }
lnks() { find "$DESK" "$MENU" -name '*.lnk'; }
regval() { cat "$SIM/reg/HKLM/SOFTWARE/Policies/$1" 2>/dev/null; }
lnk() { jq -r ".$2" "$1" 2>/dev/null; }
bad_bytes() { # <file>: CR, a UTF-8 BOM, or any byte outside printable ASCII, tab and LF; prints what it found
  _h="$(head -c 3 "$1" | od -An -tx1 | tr -d ' \n')"; [ "$_h" != efbbbf ] || echo bom
  [ "$(tr -d '\r' < "$1" | wc -c)" = "$(wc -c < "$1")" ] || echo cr
  [ "$(LC_ALL=C tr -d '\t\n -~' < "$1" | wc -c | tr -d ' ')" = 0 ] || echo non-ascii
}
printf 'hub namespaces="harbor-hub" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFixture $(calc) `id` "q" '"'"'s'"'"'\n' > "$SIGNERS"   # every quote PowerShell or sh would act on
gen_setup() { sh "$T_ROOT/bin/member-windows.sh" --setup --pin "$PIN40" --user alice --hub "$HUB" --login "$LOGIN" --signers "$SIGNERS" > "$ADMIN/printed.ps1" 2>/dev/null && runnable "$ADMIN/printed.ps1" "$SETUP"; }

# ── 1. the script parses, in PowerShell 7 and against Windows PowerShell 5.1's rules ─────────────────────────────────────
t_section "it parses, and lints clean for PowerShell 7 and 5.1"
gen_setup; t_eq "member-windows.sh --setup prints" 0 "$?"
sh "$T_ROOT/bin/member-windows.sh" --uninstall > "$ADMIN/uninstall-printed.ps1" 2>/dev/null; runnable "$ADMIN/uninstall-printed.ps1" "$UNINST"
mkdir -p "$SIM/lint"; cp "$ADMIN/printed.ps1" "$SIM/lint/setup.ps1"; cp "$ADMIN/uninstall-printed.ps1" "$SIM/lint/uninstall.ps1"
ST="$T_TMP/stage"; mkdir -p "$ST/harbor/bin" "$ST/harbor/MEMORY/OBSERVABILITY/member"
printf '{"env":{"HARBOR_MEMBER_ROLE":"member"}}\n' > "$ST/managed-settings.json"
printf '#!/bin/sh\necho "a $b" `c` \047q\047 $(d)\n' > "$ST/harbor/bin/hook.sh"
printf 'crlf\r\nstays\r\n' > "$ST/harbor/bin/crlf.txt"
printf '\357\273\277bom stays\n' > "$ST/harbor/bin/bom.txt"
printf 'l\303\244bas\n' > "$ST/harbor/bin/utf8.txt"
: > "$ST/harbor/bin/empty"
head -c 12582912 /dev/urandom > "$ST/harbor/bin/upterm"   # as large as the real binary, so its base64 is one 16 MB line
: > "$ST/harbor/MEMORY/OBSERVABILITY/member/guard-decisions.jsonl"
sh "$T_ROOT/bin/member-windows.sh" --stage "$ST" --member alice > "$SIM/lint/stage.ps1" 2>/dev/null
t_eq "member-windows.sh --stage prints" 0 "$?"
if [ -f "$T_ROOT/windows-test.md" ]; then
  awk '/^```powershell/{f=1;n++;next} /^```/{f=0;next} f{print > ("'"$SIM"'/lint/windows-test-" n ".ps1")}' "$T_ROOT/windows-test.md"
  t_eq "windows-test.md carries its three PowerShell blocks" 3 "$(find "$SIM/lint" -name 'windows-test-*.ps1' | wc -l | tr -d ' ')"
else
  printf '  note: windows-test.md not given (SIM_WINDOWS_TEST_MD), so its blocks are unchecked\n'
fi
printf '%s\n' '$a = $null ?? 1' '1..2 | ForEach-Object -Parallel { $_ }' '& wsl.exe x && Write-Output y' > "$SIM/lint/zz-redprobe.ps1"
cat > "$SIM/lint.ps1" <<'PS'
$p51 = 'win-48_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework'
$compat = @{ Rules = @{ PSUseCompatibleSyntax = @{ Enable = $true; TargetVersions = @('5.1') }
  PSUseCompatibleCommands = @{ Enable = $true; TargetProfiles = @($p51) }; PSUseCompatibleTypes = @{ Enable = $true; TargetProfiles = @($p51) } } }
foreach ($f in Get-ChildItem /sim/lint/*.ps1) {
  $t = $null; $e = $null; [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$t, [ref]$e)
  "$($f.Name) parse $($e.Count)"
  $e | ForEach-Object { "$($f.Name) parse-error L$($_.Extent.StartLineNumber) $($_.Message)" }
  Invoke-ScriptAnalyzer -Path $f.FullName | ForEach-Object { "$($f.Name) pssa $($_.Severity) $($_.RuleName) L$($_.Line)" }
  Invoke-ScriptAnalyzer -Path $f.FullName -Settings $compat -IncludeRule PSUseCompatibleSyntax, PSUseCompatibleCommands, PSUseCompatibleTypes | ForEach-Object { "$($f.Name) compat51 $($_.RuleName) L$($_.Line) $($_.Message)" }
}
PS
pwsh -NoProfile -NonInteractive -File "$SIM/lint.ps1" > "$T_TMP/lint.out" 2>&1
for _f in "$SIM"/lint/*.ps1; do
  _b="${_f##*/}"; [ "$_b" != zz-redprobe.ps1 ] || continue
  t_eq "$_b: no parse error in PowerShell 7" "$_b parse 0" "$(grep "^$_b parse " "$T_TMP/lint.out")"
  t_eq "$_b: no PSScriptAnalyzer error" '' "$(grep "^$_b pssa Error" "$T_TMP/lint.out")"
  t_eq "$_b: nothing PowerShell 5.1 lacks" '' "$(grep "^$_b compat51" "$T_TMP/lint.out")"
  t_eq "$_b: ASCII and LF only, no BOM, so 5.1's ANSI read of a BOM-less file changes nothing" '' "$(bad_bytes "$_f")"
done
t_eq "CONTROL: the 5.1 rules catch ??, -Parallel and && (the check can fail)" 3 "$(grep -c '^zz-redprobe.ps1 compat51' "$T_TMP/lint.out")"
grep ' pssa \(Warning\|Information\) ' "$T_TMP/lint.out" | grep -v '^zz-' | sed 's/^/  note: /' | sort -u

# ── 2. run orders, traced ──────────────────────────────────────────────────────────────────────────────────────────────
t_section "first run, no WSL: exit 3010 and nothing written"
win_reset; distro_reset; ps_run "$SETUP"
t_eq "exit 3010: the process keeps 194, its low byte, on Linux" 194 "$RC"; t_has "...saying restart, then the same script" "$(cat "$OUT")" 'Restart Windows, then run this same script again'
t_eq "the call order" 'wsl.exe --list --quiet|wsl.exe --install --distribution Ubuntu --no-launch|wsl.exe -d Ubuntu -u root --exec|' "$(seq_of)"
t_has "the admin check ran first" "$(calls | head -n 1)" 'IsInRole Administrator'
t_eq "the HKLM refusal ran before WSL was touched (F10)" 'Test-Path HKLM:\SOFTWARE\Policies\ClaudeCode' "$(calls | sed -n 2p)"
t_eq "nothing under C:\\Program Files\\ClaudeCode" no "$([ -e "$CC" ] && echo yes || echo no)"
t_eq "no registry value, no shortcut" '' "$(regval Claude/disableWslSessions)$(lnks)"
t_eq "...and the exit is 3010 in full" 3010 "$(win_reset; full_rc "$SETUP")"

t_section "after the restart: the whole laptop"
reboot; echo on > "$SIM/state/feature"; [ "$(cat "$SIM/state/distro")" != pending ] || echo on > "$SIM/state/distro"   # optimistic: the restart registers it
: > "$LOG"; ps_run "$SETUP"
t_eq "exit 4: the floor is on, the token step is next (no token in the sim)" 4 "$RC"; t_has "...and it says so" "$(cat "$OUT")" 'not finished'
[ "$RC" = 4 ] || sed -n '1,60p' "$OUT" | sed 's/^/  | /'
t_eq "the call order: inside, its Windows half, inside again, terminate" \
  'wsl.exe --list --quiet|wsl.exe -d Ubuntu -u root --exec|wsl.exe -d Ubuntu -u root --exec|wsl.exe exit 3|wsl.exe -d Ubuntu -u root --exec cat|powershell.exe|wsl.exe -d Ubuntu -u root --exec|wsl.exe exit 4|wsl.exe --terminate Ubuntu|' "$(seq_of)"
t_hasnt "WSL is not installed twice" "$(calls)" '--install'
t_has "the first bootstrap stops for the Windows half" "$(cat "$SIM/inner-1.log")" 'the Windows half'
t_has "...and the second reads it back byte for byte" "$(cat "$SIM/inner-2.log")" 'byte for byte'
t_eq "the Windows half ran from the folder only an admin writes" 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:/Program Files/ClaudeCode/setup/harbor-member.ps1' "$(calls | grep '^powershell.exe')"
t_eq "the setup folder is gone at the end" no "$([ -e "$CC/setup" ] && echo yes || echo no)"
t_eq "the member exists in the distro" 0 "$(id -u alice >/dev/null 2>&1; echo $?)"
t_eq "and is not an admin there" '' "$(id -Gn alice | tr ' ' '\n' | grep -x 'sudo\|admin\|root\|docker')"
t_eq "and is the default user" "$(printf '\n[user]\ndefault=alice')" "$(cat /etc/wsl.conf)"
t_eq "HKLM disableWslSessions is the DWord 0" 'DWord:0' "$(regval Claude/disableWslSessions)"
t_eq "no HKLM ClaudeCode policy was written" no "$([ -e "$REG/ClaudeCode" ] && echo yes || echo no)"
t_has "the ledger is append-only for Users" "$(calls | grep '^icacls.exe')" 'guard-decisions.jsonl /grant *S-1-5-32-545:(AD)'
t_eq "the floor's files are root's checkout, byte for byte" '' "$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' /opt/harbor-core/contracts/member-files.txt | while read -r _s _d; do cmp -s "/opt/harbor-core/$_s" "$CC/harbor/bin/${_d:-${_s##*/}}" || echo "$_s"; done)"
t_eq "the signers, byte for byte, quotes and all" same "$(cmp -s "$SIGNERS" "$CC/harbor/hub-signers" && echo same)"
t_eq "the bootstrap went in byte for byte" same "$(sh "$T_ROOT/bin/member-windows.sh" --setup --pin "$PIN40" --user alice --hub "$HUB" --login "$LOGIN" --signers "$SIGNERS" 2>/dev/null | sed -n "s/^Put 'setup\\\\member-bootstrap.sh' '\(.*\)'$/\1/p" | base64 -d | cmp -s - "$T_ROOT/bin/member-bootstrap.sh" && echo same)"

t_section "the managed settings are what Linux expects"
MS="$CC/managed-settings.json"
WANT="$(env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root WSL_DISTRO_NAME=Ubuntu sh /opt/harbor-core/bin/member-managed.sh --hub "$HUB" --login "$LOGIN" --user alice 2>/dev/null | jq -S .)"
t_eq "the same JSON member-managed.sh composes for these inputs" "$WANT" "$(jq -S . "$MS")"
t_eq "with wslInheritsWindowsSettings" true "$(jq '.wslInheritsWindowsSettings' "$MS")"
t_eq "every hook names a script that landed, as WSL sees it" '' "$(jq -r '.. | .command? // empty' "$MS" | sed -n "s|^.* /bin/sh '\([^']*\)'.*|\1|p" | while IFS= read -r _p; do [ -f "$_p" ] || echo "$_p"; done)"
t_eq "...and at least the dispatcher's" 1 "$(jq -r '.. | .command? // empty' "$MS" | grep -c "member-dispatch.sh'$")"
t_eq "the workspace is ~/port" '["/home/alice''/port"]' "$(jq -c '.permissions.additionalDirectories' "$MS")"
t_eq "...and the install made it" yes "$([ -d /home/alice''/port ] && echo yes)"

t_section "bytes: LF and no BOM where Linux reads, valid where Windows reads"
for _f in managed-settings.json harbor-confinement harbor/bin/member-dispatch.sh harbor/bin/member-install.sh harbor/hub-signers harbor/member.conf harbor/floor.pin; do
  [ -f "$CC/$_f" ] || [ "$_f" = harbor/bin/member-install.sh ] || t_fail "$_f is missing"
  [ ! -f "$CC/$_f" ] || t_eq "$_f: no CR, no BOM" '' "$(bad_bytes "$CC/$_f" | grep -v non-ascii)"
done
t_eq "no landed text file carries a CR or a BOM" '' "$(find "$CC/harbor" -type f ! -name upterm | while IFS= read -r _f; do bad_bytes "$_f" | grep -v non-ascii | sed "s|^|${_f#"$CC"/}: |"; done)"
printf '  bytes, managed-settings.json:\n'; head -c 48 "$MS" | xxd | sed 's/^/    /'
printf '  bytes, harbor/bin/member-support.sh:\n'; head -c 48 "$CC/harbor/bin/member-support.sh" | xxd | sed 's/^/    /'
t_eq "/opt/harbor-member.ps1, the Windows half: ASCII and LF, no BOM" '' "$(bad_bytes /opt/harbor-member.ps1)"
cp /opt/harbor-member.ps1 "$SIM/lint/zz-half.ps1"
t_eq "...and it parses" 0 "$(pwsh -NoProfile -c '$e = $null; $t = $null; [void][System.Management.Automation.Language.Parser]::ParseFile("/sim/lint/zz-half.ps1", [ref]$t, [ref]$e); $e.Count')"
t_eq "...and lints clean against 5.1" '' "$(pwsh -NoProfile -c '$p = "win-48_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework"; Invoke-ScriptAnalyzer -Path /sim/lint/zz-half.ps1 -Settings @{ Rules = @{ PSUseCompatibleSyntax = @{ Enable = $true; TargetVersions = @("5.1") }; PSUseCompatibleCommands = @{ Enable = $true; TargetProfiles = @($p) } } } -IncludeRule PSUseCompatibleSyntax,PSUseCompatibleCommands,PSUseCompatibleTypes | ForEach-Object RuleName')"

t_section "shortcuts: wsl.exe, the Ubuntu distro, the member, ~/port"
for _s in "$DESK/Harbor setup.lnk" "$DESK/Harbor support.lnk" "$MENU/Harbor Support.lnk"; do
  _n="${_s##*/}"
  t_eq "$_n: exists" yes "$([ -f "$_s" ] && echo yes)"
  t_eq "$_n: runs wsl.exe" 'C:/Windows/System32/wsl.exe' "$(lnk "$_s" TargetPath)"
  t_has "$_n: in Ubuntu, as the member, starting in ~/port" "$(lnk "$_s" Arguments)" '-d Ubuntu -u alice --cd /home/alice''/port'
done
t_has "the support shortcuts run the landed member-support.sh" "$(lnk "$DESK/Harbor support.lnk" Arguments)$(lnk "$MENU/Harbor Support.lnk" Arguments)" '"/mnt/c/Program Files/ClaudeCode/harbor/bin/member-support.sh"'
t_eq "...which is there" yes "$([ -f "$CC/harbor/bin/member-support.sh" ] && echo yes)"
t_eq "the Start Menu one opens a visible window" 1 "$(lnk "$MENU/Harbor Support.lnk" WindowStyle)"

t_section "a second run on the installed laptop changes nothing"
BEFORE="$(snap)"; : > "$LOG"; ps_run "$SETUP"
t_eq "exit 4: the floor is on, the token step is next (no token in the sim)" 4 "$RC"
t_eq "no install, no Windows half: inside once, terminate" 'wsl.exe --list --quiet|wsl.exe -d Ubuntu -u root --exec|wsl.exe -d Ubuntu -u root --exec|wsl.exe exit 4|wsl.exe --terminate Ubuntu|' "$(seq_of)"
t_eq "every file and registry value as it was" "$BEFORE" "$(snap)"
t_eq "one default user line" 1 "$(grep -c '^default=' /etc/wsl.conf)"

t_section "WSL and Ubuntu already there, Ubuntu's own wsl.conf"
win_reset; distro_reset; echo on > "$SIM/state/feature"; echo on > "$SIM/state/distro"; printf '[boot]\nsystemd=true\n' > /etc/wsl.conf
ps_run "$SETUP"
t_eq "exit 4: the floor is on, the token step is next (no token in the sim)" 4 "$RC"
t_hasnt "WSL is not installed" "$(calls)" '--install'
t_eq "its section stays, the member's is added" "$(printf '[boot]\nsystemd=true\n\n[user]\ndefault=alice')" "$(cat /etc/wsl.conf)"
t_eq "the floor landed" yes "$([ -f "$CC/managed-settings.json" ] && echo yes)"

t_section "another default user in /etc/wsl.conf stops before anything lands"
for _conf in '[user]\ndefault=bob\n' '[user]\ndefault = bob\n' '[user]\n  default=bob\n' '[user]\ndefault=bob\r\n'; do
  win_reset; distro_reset; echo on > "$SIM/state/feature"; echo on > "$SIM/state/distro"
  # shellcheck disable=SC2059 # the loop value is the format, on purpose: it carries the escapes
  printf "$_conf" > /etc/wsl.conf; _was="$(od -An -c /etc/wsl.conf | tr -s ' ')"
  ps_run "$SETUP"
  t_eq "[$_conf] exit 1" 1 "$RC"
  t_has "[$_conf] ...saying why" "$(cat "$OUT")" 'names another default user'
  t_eq "[$_conf] the bootstrap never ran" '' "$(grep -l 'member-bootstrap\|member-install' "$SIM"/inner-*.log 2>/dev/null)"
  t_eq "[$_conf] no floor, no settings, no registry value, no shortcut" '' "$(ls "$CC/harbor" "$CC/managed-settings.json" 2>/dev/null)$(regval Claude/disableWslSessions)$(lnks)"
  t_eq "[$_conf] wsl.conf untouched" "$_was" "$(od -An -c /etc/wsl.conf | tr -s ' ')"
done
win_reset; distro_reset; echo on > "$SIM/state/feature"; echo on > "$SIM/state/distro"; printf '[user]\ndefault = alice\n' > /etc/wsl.conf
ps_run "$SETUP"; t_eq "CONTROL: the member already named, with spaces: exit 4 (the token is next)" 4 "$RC"
t_eq "...and no second default" 1 "$(grep -c 'default' /etc/wsl.conf)"

t_section "refusals before anything is touched"
win_reset; mkdir -p "$REG/ClaudeCode"; printf 'String:{}' > "$REG/ClaudeCode/Settings"; ps_run "$SETUP"
t_eq "an HKLM ClaudeCode policy: exit 1 (F10)" 1 "$RC"; t_has "...naming it" "$(cat "$OUT")" 'HKLM policy outranks'
t_eq "...before WSL is asked" '' "$(seq_of)"
win_reset; SIM_ADMIN=0; export SIM_ADMIN; ps_run "$SETUP"; unset SIM_ADMIN
t_eq "not an administrator: exit 1" 1 "$RC"; t_eq "...before WSL is asked" '' "$(seq_of)"
win_reset; distro_reset; echo on > "$SIM/state/feature"; echo on > "$SIM/state/distro"
SIM_HALF_RC=1; export SIM_HALF_RC; ps_run "$SETUP"; unset SIM_HALF_RC
t_eq "the Windows half failing stops the script: exit 1" 1 "$RC"; t_has "...saying so" "$(cat "$OUT")" 'the Windows half stopped'
t_eq "...with no shortcut" '' "$(lnks)"
win_reset; SIM_INSTALL_RC=1; export SIM_INSTALL_RC; ps_run "$SETUP"; unset SIM_INSTALL_RC
t_eq "wsl --install failing: exit 1" 1 "$RC"; t_has "...saying so" "$(cat "$OUT")" 'wsl --install stopped with exit 1'
t_eq "...and nothing written" no "$([ -e "$CC" ] && echo yes || echo no)"

t_section "wsl --install asks for the restart by its exit code: 3010, or 0x80070BC2 as the Int32 PowerShell reads"
# Microsoft's WSL install code treats ERROR_SUCCESS_REBOOT_REQUIRED (3010) as success needing a restart; whether the laptop's wsl.exe returns it is unproven here.
for _rc in 3010 -2147023422; do
  win_reset; distro_reset; SIM_INSTALL_REBOOT_RC="$_rc"; export SIM_INSTALL_REBOOT_RC; ps_run "$SETUP"
  t_eq "[$_rc] exit 3010 (194 here), not 1" 194 "$RC"; t_has "[$_rc] ...saying restart, then the same script" "$(cat "$OUT")" 'Restart Windows, then run this same script again'
  t_hasnt "[$_rc] ...and not a failure" "$(cat "$OUT")" 'stopped with exit'
  t_eq "[$_rc] nothing under C:\\Program Files\\ClaudeCode" no "$([ -e "$CC" ] && echo yes || echo no)"
  t_eq "[$_rc] ...and the exit is 3010 in full" 3010 "$(win_reset; full_rc "$SETUP")"
  unset SIM_INSTALL_REBOOT_RC
done
win_reset; distro_reset; SIM_INSTALL_RC=5; export SIM_INSTALL_RC; ps_run "$SETUP"; unset SIM_INSTALL_RC
t_eq "CONTROL: any other non-zero exit is still a failure: exit 1" 1 "$RC"

t_section "the restart is asked once: --no-launch can leave Ubuntu unregistered after it"
RESTART_FLAG="$C/ProgramData/harbor-setup-restart.txt"
win_reset; distro_reset; ps_run "$SETUP"
t_eq "run 1: 3010" 194 "$RC"; t_eq "...and the boot it asked on is kept, outside Program Files" yes "$([ -s "$RESTART_FLAG" ] && echo yes)"
ps_run "$SETUP"; t_eq "run again without a restart: 3010 again, the same advice" 194 "$RC"
reboot; echo on > "$SIM/state/feature"   # Windows restarted; the distro stays unregistered
SIM_NOREG=1; export SIM_NOREG; ps_run "$SETUP"; unset SIM_NOREG
t_eq "after a restart with Ubuntu still unregistered: exit 1, never 3010 again" 1 "$RC"
t_has "...saying what is wrong" "$(cat "$OUT")" 'not registered'; t_hasnt "...and not asking for a restart" "$(cat "$OUT")" 'Restart Windows'
t_eq "...with nothing written" no "$([ -e "$CC" ] && echo yes || echo no)"
ps_run "$SETUP"; t_eq "CONTROL: Ubuntu registers on the next try: exit 4" 4 "$RC"
t_eq "...and the restart note is gone" no "$([ -e "$RESTART_FLAG" ] && echo yes || echo no)"

# ── 3. the payload through real PowerShell: bytes, quoting, a 16 MB line ────────────────────────────────────────────────
t_section "Put and Keep in real PowerShell, byte for byte"
# Through the setup script's own hand-off lines: cat in the distro, piped into Set-Content, then powershell.exe -File. A 16 MB line included.
win_reset; echo on > "$SIM/state/feature"; echo on > "$SIM/state/distro"; cp "$SIM/lint/stage.ps1" /opt/harbor-member.ps1
{ sed -n '1,3p' "$ADMIN/printed.ps1"; printf '%s\n' "\$distro = 'Ubuntu'" "New-Item -ItemType Directory -Force (Join-Path \$base 'setup') | Out-Null"
  grep -F -e "\$half = " -e 'cat /opt/harbor-member.ps1' -e '-File $half' "$ADMIN/printed.ps1" | sed 's/^  //'; } > "$ADMIN/handoff.ps1"
t_eq "the hand-off is the printed script's three lines" 3 "$(grep -c -F -e "\$half = " -e 'cat /opt/harbor-member.ps1' -e '-File $half' "$ADMIN/handoff.ps1")"
ps_run "$ADMIN/handoff.ps1"
t_eq "exit 0" 0 "$RC"
cp "$SIM/lint/stage.ps1" "$ADMIN/stage.ps1"
t_eq "every staged file, byte for byte: CRLF, BOM, UTF-8, empty, binary, and \$ \` ' in a script" '' "$(diff -r -x setup "$ST" "$CC" 2>&1)"
printf 'a record\n' > "$CC/harbor/MEMORY/OBSERVABILITY/member/guard-decisions.jsonl"; ps_run "$ADMIN/stage.ps1"
t_eq "a re-run keeps the ledger" 'a record' "$(cat "$CC/harbor/MEMORY/OBSERVABILITY/member/guard-decisions.jsonl")"
t_eq "a re-run leaves no .new file behind" '' "$(find "$CC" -name '*.new')"

t_section "argument values that would break a quoted string are refused, whole"
for _v in 'al ice' "al'ice" 'al"ice' 'al$ice' 'al`ice' '.' '..' '.alice' '12345' 'abcdefghijabcdefghijabcdefghijabc'; do
  RC=0; _o="$(sh "$T_ROOT/bin/member-windows.sh" --setup --pin "$PIN40" --user "$_v" --hub "$HUB" --login "$LOGIN" --signers "$SIGNERS" 2>/dev/null)" || RC=$?
  t_eq "--user [$_v] refuses" 2 "$RC"; t_eq "--user [$_v] ...and prints nothing" '' "$_o"
  RC=0; _o="$(sh "$T_ROOT/bin/member-windows.sh" --stage "$ST" --member "$_v" 2>/dev/null)" || RC=$?
  t_eq "--member [$_v] refuses" 2 "$RC"
done
for _v in 'o/n x' "o/n'" 'o/$n' 'o/`n`'; do
  t_exit "--hub [$_v] refuses" 2 sh "$T_ROOT/bin/member-windows.sh" --setup --pin "$PIN40" --user alice --hub "$_v" --login "$LOGIN" --signers "$SIGNERS"
done
for _v in 'a b' "a'b" 'a$b' 'a`b'; do
  t_exit "--login [$_v] refuses" 2 sh "$T_ROOT/bin/member-windows.sh" --setup --pin "$PIN40" --user alice --hub "$HUB" --login "$_v" --signers "$SIGNERS"
done
t_exit "--pin with a space refuses" 2 sh "$T_ROOT/bin/member-windows.sh" --setup --pin "$PIN40 " --user alice --hub "$HUB" --login "$LOGIN" --signers "$SIGNERS"
cp "$SIGNERS" "$T_TMP/it's a \$file \`x\`"
t_exit "a --signers path with quotes is fine: only its bytes land" 0 sh "$T_ROOT/bin/member-windows.sh" --setup --pin "$PIN40" --user alice --hub "$HUB" --login "$LOGIN" --signers "$T_TMP/it's a \$file \`x\`"
t_exit "CONTROL: a plain member with a dot is still taken" 0 sh "$T_ROOT/bin/member-windows.sh" --setup --pin "$PIN40" --user al.ice --hub "$HUB" --login "$LOGIN" --signers "$SIGNERS"

. "$(dirname "$0")/sim-colleague.sh"   # 3b. the launcher the colleagues run, twice (3010, then 4), and the colleague guide

# ── 4. uninstall ───────────────────────────────────────────────────────────────────────────────────────────────────────
t_section "uninstall"
win_reset; distro_reset; echo on > "$SIM/state/feature"; echo on > "$SIM/state/distro"; ps_run "$SETUP"; t_eq "CONTROL: installed first (exit 4: the token is next)" 4 "$RC"
mkdir -p "$REG/Claude"; printf 'DWord:1' > "$REG/Claude/someOtherValue"
printf '2026-11-09T08:00:00\n' > "$RESTART_FLAG"
: > "$LOG"; ps_run "$UNINST"
t_eq "exit 0" 0 "$RC"
t_eq "the floor, the settings and the marker are gone" '' "$(ls "$CC/harbor" "$CC/managed-settings.json" "$CC/harbor-confinement" 2>/dev/null)"
t_eq "all three shortcuts are gone" '' "$(lnks)"
t_eq "...and so is the restart note" no "$([ -e "$RESTART_FLAG" ] && echo yes || echo no)"
t_eq "disableWslSessions is gone" '' "$(regval Claude/disableWslSessions)"
t_eq "...and only it: the key and its other values stay" 'DWord:1' "$(regval Claude/someOtherValue)"
ps_run "$UNINST"; t_eq "a second uninstall: exit 0, nothing to remove" 0 "$RC"

# ── 5. the operator's Windows test ─────────────────────────────────────────────────────────────────────────────────────
if [ -f "$SIM/lint/windows-test-2.ps1" ]; then
  t_section "windows-test.md: the test policy, as written from a Windows editor (CRLF) and as pasted (LF)"
  for _form in crlf lf; do
    win_reset
    if [ "$_form" = crlf ]; then sed 's/$/\r/' "$SIM/lint/windows-test-2.ps1" > "$ADMIN/wt2.ps1"; else cp "$SIM/lint/windows-test-2.ps1" "$ADMIN/wt2.ps1"; fi
    ps_run "$ADMIN/wt2.ps1"; t_eq "[$_form] exit 0" 0 "$RC"
    H="$CC/harbor/test-hook.sh"
    t_eq "[$_form] test-hook.sh: no CR, no BOM, ASCII" '' "$(bad_bytes "$H")"
    t_eq "[$_form] ...starts with its shebang" '#!/bin/sh' "$(head -n 1 "$H")"
    rm -f /tmp/harbor-hook-test
    t_eq "[$_form] ...runs under sh and asks" ask "$(sh "$H" | jq -r '.hookSpecificOutput.permissionDecision')"
    t_eq "[$_form] ...and leaves its mark" hit "$(cat /tmp/harbor-hook-test)"
    t_eq "[$_form] managed-settings.json: valid JSON, no BOM" true "$(jq '.wslInheritsWindowsSettings and .allowManagedHooksOnly' "$CC/managed-settings.json")"
    t_eq "[$_form] ...whose hook names that file as WSL sees it" yes "$(f="$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$CC/managed-settings.json" | sed "s/^sh '\(.*\)'$/\1/")"; [ -f "$f" ] && echo yes)"
    t_eq "[$_form] disableWslSessions is the DWord 0" 'DWord:0' "$(regval Claude/disableWslSessions)"
    ps_run "$ADMIN/wt2.ps1"; t_eq "[$_form] run twice: exit 0" 0 "$RC"
  done
  printf '  note: on Windows, Set-Content ends each JSON line in CRLF; JSON allows it, and the sim writes LF\n'
  cp "$SIM/lint/windows-test-3.ps1" "$ADMIN/wt3.ps1"; ps_run "$ADMIN/wt3.ps1"
  t_eq "clean-up: exit 0" 0 "$RC"
  t_eq "...and C:\\Program Files\\ClaudeCode and the value are gone" '' "$(ls -d "$CC" 2>/dev/null)$(regval Claude/disableWslSessions)"
  win_reset; echo on > "$SIM/state/feature"; echo on > "$SIM/state/distro"
  cp "$SIM/lint/windows-test-1.ps1" "$ADMIN/wt1.ps1"; ps_run "$ADMIN/wt1.ps1"
  t_eq "the WSL block, after its restart: exit 0" 0 "$RC"
  t_eq "...its three wsl calls" 'wsl.exe --install -d Ubuntu|wsl.exe -d Ubuntu -- sudo apt-get update|wsl.exe -d Ubuntu -- sudo apt-get install -y git jq|' "$(calls | grep '^wsl.exe' | tr '\n' '|')"
fi
t_done
