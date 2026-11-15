#!/usr/bin/env sh
# member-windows.sh (harbor#1278). No PowerShell runs here, so nothing below shows the script works on Windows: it decodes every payload and compares
# the bytes, pins the fixed lines, and proves the refusals. docs/how-to/member-install.md lists what stays unverified.
. "$(dirname "$0")/../../lib/core.sh"; t_init
T_TMP="$(cd "$T_TMP" && pwd -P)"
. "$T_ROOT/tests/member/fixture.sh"
W="$T_ROOT/bin/member-windows.sh"
HARBOR_MEMBER_OS=WSL; export HARBOR_MEMBER_OS
stub "$T_BIN/reg.exe" 'exit "${REG_RC:-1}"'
ST="$T_TMP/stage"; mkdir -p "$ST/harbor/bin" "$ST/harbor/MEMORY/OBSERVABILITY/member"
printf '{"env":{"HARBOR_MEMBER_ROLE":"member"}}\n' > "$ST/managed-settings.json"
printf 'confinement\n' > "$ST/harbor-confinement"
printf '#!/bin/sh\necho "a $b" `c` \047q\047\n' > "$ST/harbor/bin/member-dispatch.sh"
head -c 4096 /dev/urandom > "$ST/harbor/bin/binary-bytes.bin"
: > "$ST/harbor/bin/harbor-member-mode"
printf 'hub namespaces="harbor-hub" ssh-ed25519 AAAA\n' > "$ST/harbor/hub-signers"
printf '0123456789abcdef\n' > "$ST/harbor/floor.pin"
: > "$ST/harbor/MEMORY/OBSERVABILITY/member/guard-decisions.jsonl"
PS="$T_TMP/out.ps1"
sh "$W" --stage "$ST" > "$PS" 2>"$T_TMP/err"; t_eq "prints a script" 0 "$?"

t_section "the payload, decoded"
B="$T_TMP/base"; mkdir -p "$B"; fake_ps "$PS" "$B"
t_eq "every staged file, byte for byte" '' "$(diff -r "$ST" "$B" 2>&1)"
t_eq "the row count is the file count" "$(find "$ST" -type f | wc -l | tr -d ' ')" "$(grep -c "^Put '\|^Keep '" "$PS")"
t_has "paths use backslashes" "$(cat "$PS")" "Put 'harbor\\bin\\member-dispatch.sh'"
printf 'a record\n' > "$B/harbor/MEMORY/OBSERVABILITY/member/guard-decisions.jsonl"; fake_ps "$PS" "$B"
t_eq "a re-run keeps the ledger" 'a record' "$(cat "$B/harbor/MEMORY/OBSERVABILITY/member/guard-decisions.jsonl")"

t_section "order and fixed lines"
last="$(grep -n "^Put '\|^Keep '" "$PS" | tail -1)"
t_has "managed-settings.json lands last (M9)" "$last" "Put 'managed-settings.json'"
guard="$(grep -n 'Policies.ClaudeCode' "$PS" | head -1 | cut -d: -f1)"; first="$(grep -n "^Put '" "$PS" | head -1 | cut -d: -f1)"
t_eq "the HKLM refusal runs before the first write (F10)" 1 "$([ "$guard" -lt "$first" ] && echo 1)"
t_has "...and reads the Settings value" "$(cat "$PS")" "GetValue('Settings')"
t_has "...and stops" "$(sed -n "${guard}p;$((guard + 1))p" "$PS")" 'exit 1'
t_has "it stops on any error" "$(cat "$PS")" "\$ErrorActionPreference = 'Stop'"
t_has "writes bytes, so no line ending changes a script" "$(cat "$PS")" 'WriteAllBytes'
t_has "under C:\\Program Files\\ClaudeCode" "$(cat "$PS")" "'C:\\Program Files\\ClaudeCode'"
t_has "disableWslSessions is the DWord 0 (R5, F16)" "$(cat "$PS")" '-Name disableWslSessions -PropertyType DWord -Value 0'
t_has "...under the Desktop key" "$(cat "$PS")" 'HKLM:\SOFTWARE\Policies\Claude'
t_hasnt "New-Item -Force would wipe that key's other values" "$(grep 'desktop' "$PS")" 'New-Item -Force'
t_has "the ledger is append-only for Users" "$(cat "$PS")" '*S-1-5-32-545:(AD)'
t_eq "exactly one branch of logic beyond Put and Keep" 3 "$(grep -c '^if \|^function Keep' "$PS")"
t_hasnt "nothing evaluates a string" "$(cat "$PS")" 'Invoke-Expression'

t_section "the file carries no plain text from outside"
printf 'injected$(calc)\n' > "$ST/harbor/hub-signers"
t_hasnt "a file's content can't reach PowerShell as code" "$(sh "$W" --stage "$ST" 2>/dev/null)" 'injected$(calc)'
: > "$ST/harbor/bin/bad'name"
RC=0; sh "$W" --stage "$ST" >/dev/null 2>"$T_TMP/err" || RC=$?
t_eq "a path with a quote refuses" 1 "$RC"; t_has "...naming it" "$(cat "$T_TMP/err")" "bad'name"
rm -f "$ST/harbor/bin/bad'name"

t_section "the Start Menu shortcut"
SM="$(sh "$W" --stage "$ST" --member alice 2>/dev/null | grep '^\$lnk.Arguments')"
t_has "opens Ubuntu as the member, in ~/port, like the desktop ones" "$SM" "-d Ubuntu -u alice --cd /home/alice""/port --exec /bin/sh"
t_exit "--member .. refuses" 2 sh "$W" --stage "$ST" --member ..

t_section "refusals (F10)"
RC=0; REG_RC=0 sh "$W" --stage "$ST" > "$T_TMP/o" 2>"$T_TMP/err" || RC=$?
t_eq "an HKLM policy: no script" 1 "$RC"
t_eq "...not one byte of it" 0 "$(wc -c < "$T_TMP/o" | tr -d ' ')"
t_has "...and says why" "$(cat "$T_TMP/err")" 'HKLM policy'
mkdir -p "$SYS/managed-settings.d"; printf '{}\n' > "$SYS/managed-settings.d/10.json"
t_exit "a drop-in already there" 1 sh "$W" --stage "$ST"
rm -rf "$SYS/managed-settings.d"
printf '{"model":"opus"}\n' > "$MFILE"
t_exit "another writer's file" 1 sh "$W" --stage "$ST"
rm -f "$MFILE"
t_exit "CONTROL: clean again" 0 sh "$W" --stage "$ST"
printf 'not json\n' > "$ST/managed-settings.json"
t_exit "settings that aren't JSON never ship: Claude Code refuses to start on them (M9)" 1 sh "$W" --stage "$ST"
t_exit "no mode is a usage error" 2 sh "$W"
t_exit "--help answers" 0 sh "$W" --help
t_has "the header says it has never run" "$(sh "$W" --help)" 'HAS NEVER RUN'

t_section "the whole laptop in one script (harbor#1278)"
PIN40=0123456789abcdef0123456789abcdef01234567
SUP="$T_TMP/setup.ps1"; SARGS="--setup --pin $PIN40 --user alice --hub fixture-org/fixture-hub --login alice-gh --signers $SIGNERS"
# shellcheck disable=SC2086 # the words above
sh "$W" $SARGS > "$SUP" 2>"$T_TMP/err"; t_eq "prints a script, with no distro to ask" 0 "$?"
S="$(cat "$SUP")"
at() { grep -n -F -- "$1" "$SUP" | head -n 1 | cut -d: -f1; }
t_has "it needs an administrator" "$S" 'WindowsBuiltInRole]::Administrator'
t_has "it reads what is installed" "$S" '& wsl.exe --list --quiet'
t_has "WSL and the distro when absent, and it opens no first-run prompt" "$S" '--install --distribution $distro --no-launch'
t_has "...for Ubuntu" "$S" "\$distro = 'Ubuntu'"
t_eq "...only when absent" 1 "$(grep -F -- '--install --distribution' "$SUP" | grep -c '^if (\$held -notcontains \$distro)')"
t_has "a restart WSL wants is said, and the script can run again" "$S" 'exit 3010'
t_has "a restart by exit code, 3010 or its HRESULT read as an Int32, is not a failure" "$S" '$irc -ne 3010 -and $irc -ne -2147023422'
t_has "a restart asked once and taken, and still no distro, is a failure and not a second ask" "$S" 'if (Restarted) {'
t_has "...told apart by the boot it noted, outside Program Files" "$S" "Join-Path \$env:ProgramData 'harbor-setup-restart.txt'"
t_eq "the HKLM refusal comes before the first write (F10)" 1 "$([ "$(at 'Policies\ClaudeCode')" -lt "$(at "Put 'setup")" ] && echo 1)"
t_eq "and before WSL is touched" 1 "$([ "$(at 'Policies\ClaudeCode')" -lt "$(at '--install --distribution')" ] && echo 1)"
t_eq "the install runs as root inside" 2 "$(grep -c -F -- '-u root --exec /bin/sh $inner' "$SUP")"
t_eq "and its Windows half runs between the two" 1 "$(l1="$(grep -n -F -- '-u root --exec /bin/sh $inner' "$SUP" | sed -n 1p | cut -d: -f1)"; l2="$(grep -n -F -- '-u root --exec /bin/sh $inner' "$SUP" | sed -n 2p | cut -d: -f1)"; l3="$(at '-File $half')"; [ "$l1" -lt "$l3" ] && [ "$l3" -lt "$l2" ] && echo 1)"
t_has "exit 3 from inside is what starts the Windows half" "$S" 'if ($rc -eq 3) {'
t_hasnt "nothing prompts: no Read-Host" "$S" 'Read-Host'
t_hasnt "nothing evaluates a string" "$S" 'Invoke-Expression'
t_hasnt "and no path through \\\\wsl.localhost, unproved from an elevated shell" "$S" 'wsl.localhost'
t_has "the distro restarts so its default user takes" "$S" '--terminate $distro'
t_eq "and only after the shortcuts" 1 "$([ "$(at "Shortcut 'Harbor support'")" -lt "$(at '--terminate')" ] && echo 1)"
SB="$T_TMP/setup-base"; mkdir -p "$SB"; fake_ps "$SUP" "$SB"
t_eq "the bootstrap goes in byte for byte" same "$(cmp -s "$T_ROOT/bin/member-bootstrap.sh" "$SB/setup/member-bootstrap.sh" && echo same)"
t_eq "and the signers" same "$(cmp -s "$SIGNERS" "$SB/setup/hub-signers" && echo same)"
t_has "the setup shortcut opens ~/port" "$S" "Shortcut 'Harbor setup' '-d Ubuntu -u alice --cd /home/alice""/port'"
t_has "and so does the support one" "$S" "Shortcut 'Harbor support' '-d Ubuntu -u alice --cd /home/alice""/port --exec"
t_has "the shortcut target is wsl.exe" "$S" "System32\\wsl.exe"
for _bad in "--pin abc" "--user root" "--user -x" "--user .." "--user .alice" "--user 12345" "--user abcdefghijabcdefghijabcdefghijabc" "--hub x" "--login a;b" "--signers /no/such/file"; do
  # shellcheck disable=SC2086 # a flag and its value
  t_exit "$_bad refuses" 2 sh "$W" $SARGS $_bad
done
t_exit "a member with a quote refuses: it lands in a string" 2 sh "$W" --setup --pin "$PIN40" --user "al'ice" --hub o/n --login a --signers "$SIGNERS"
t_eq "and the script is not half printed" '' "$(sh "$W" --setup --pin abc --user alice --hub o/n --login a --signers "$SIGNERS" 2>/dev/null)"

t_section "root's script inside the distro"
IN="$T_TMP/inner.sh"; sed -e "s|/etc/wsl.conf|$T_TMP/wsl.conf|g" -e "s|exec /bin/sh '.*member-bootstrap.sh'|exec /bin/sh $T_TMP/boot.sh|" -e "s|'/mnt/c/Program Files/ClaudeCode/setup/hub-signers'|signers|" "$SB/setup/member-wsl-setup.sh" > "$IN"
stub "$T_TMP/boot.sh" 'printf "bootstrap %s\n" "$*" >> "$CALLS"; exit "${BOOT_RC:-0}"'
stub "$T_BIN/useradd" 'printf "useradd %s\n" "$*" >> "$CALLS"'
stub "$T_BIN/id" 'case "$*" in "-u alice") [ -z "${NO_ALICE:-}" ] || exit 1; echo 1001 ;; *) exec /usr/bin/id "$@" ;; esac'
: > "$CALLS"; NO_ALICE=1 sh "$IN"; t_eq "a clean distro: exit 0" 0 "$?"
t_has "the member is made, and joins no group" "$(cat "$CALLS")" 'useradd -m -s /bin/bash alice'
t_eq "and is the default user: with none a session runs as root" "$(printf '\n[user]\ndefault=alice')" "$(cat "$T_TMP/wsl.conf")"
t_has "then the bootstrap, with every value" "$(cat "$CALLS")" "bootstrap --pin $PIN40 --user alice --hub fixture-org/fixture-hub --login alice-gh --signers signers"
: > "$CALLS"; sh "$IN"; t_eq "a second run: exit 0" 0 "$?"
t_hasnt "makes no member twice" "$(cat "$CALLS")" 'useradd'
t_eq "and writes no second default" 1 "$(grep -c '^default=' "$T_TMP/wsl.conf")"
BOOT_RC=3 sh "$IN"; t_eq "the bootstrap's exit 3 reaches the PowerShell" 3 "$?"
printf '[user]\ndefault=someone\n' > "$T_TMP/wsl.conf"; : > "$CALLS"; RC=0; sh "$IN" 2>/dev/null || RC=$?
t_eq "another default user refuses: sessions would sit outside the floor" 1 "$RC"
t_eq "before the bootstrap" '' "$(cat "$CALLS")"
for _c in 'default = someone' '  default=someone'; do
  printf '[user]\n%s\n' "$_c" > "$T_TMP/wsl.conf"; : > "$CALLS"; RC=0; sh "$IN" 2>/dev/null || RC=$?
  t_eq "[$_c] is another default user too: WSL reads it" 1 "$RC"; t_eq "[$_c] ...before the bootstrap" '' "$(cat "$CALLS")"
done
printf '[user]\ndefault = alice\r\n' > "$T_TMP/wsl.conf"; RC=0; sh "$IN" 2>/dev/null || RC=$?
t_eq "the member already named, spaced and CRLF: exit 0" 0 "$RC"; t_eq "...and no second default" 1 "$(grep -c default "$T_TMP/wsl.conf")"

t_section "leaving"
U="$(sh "$W" --uninstall)"
t_has "removes the floor" "$U" "'harbor'"
t_has "removes the settings" "$U" "'managed-settings.json'"
t_has "removes what it set in the registry" "$U" 'Remove-ItemProperty'
t_hasnt "and only that: the whole key stays" "$U" 'Remove-Item -Recurse -Force $base'
t_has "removes the shortcuts" "$U" 'Harbor setup.lnk'
t_has "and the restart note" "$U" 'harbor-setup-restart.txt'
t_has "both of them" "$U" 'Harbor support.lnk'
t_section "the install inside ends at the token step (exit 4): setup still finishes, and says so"
t_has "exit 4 is not a failure of the install" "$S" 'if ($rc -ne 0 -and $rc -ne 4)'
t_has "the shortcuts still land, and the person is told the token is next" "$S" 'if ($rc -eq 4) {'
t_has "and the script ends with 4, so nobody reads it as finished" "$S" 'exit 4 }'
t_done

