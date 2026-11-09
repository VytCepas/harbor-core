#!/usr/bin/env sh
# install.test.sh (harbor#1278) — upterm lands by digest or not at all, inside what floor.pin covers; the relay in policy reaches deniedDomains; Windows gets its shortcut.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/member/fixture.sh"
HARBOR_MEMBER_OS=Linux; export HARBOR_MEMBER_OS
# A real signing key, so the policy the install reads its hosts from can be signed and checked (contracts/hub.md, signing key).
ssh-keygen -q -t ed25519 -N '' -C hub -f "$T_TMP/hub-key"
printf 'hub namespaces="harbor-hub" %s\n' "$(cut -d' ' -f1,2 "$T_TMP/hub-key.pub")" > "$SIGNERS"
core_checkout
root_stubs
cp "$T_ROOT/bin/member-support.sh" "$CORE/bin/" 2>/dev/null
# shellcheck disable=SC2046 # one flag or value per line
go() { install $(FULL); }

t_section "1 - the pinned binary lands"
go
t_eq "the install lands the floor, and stops at the token (exit 4)" 4 "$RC"
t_eq "upterm is in the managed bin" yes "$([ -x "$MROOT/bin/upterm" ] && echo yes || echo no)"
t_eq "byte for byte the release's" "$(cat "$T_TMP/release/upterm")" "$(cat "$MROOT/bin/upterm")"
t_has "from the pinned version's release" "$(grep '^curl' "$CALLS")" 'github.com/owenthereal/upterm/releases/download/v0.41.1/upterm_linux_'
t_has "over https only" "$(grep '^curl' "$CALLS")" '--proto =https'
t_has "the person's own support script lands too" "$(ls "$MROOT/bin")" member-support.sh
t_has "and the pin file" "$(ls "$MROOT/bin")" support-upterm.tsv
_before="$(cat "$MROOT/floor.pin")"

t_section "2 - a mismatch refuses, and writes nothing"
chmod -R u+w "$SYS"; rm -rf "$SYS"; mkdir -p "$SYS"
printf 'something else\n' > "$T_TMP/other.tar.gz"
RELEASE_TAR="$T_TMP/other.tar.gz"; go; RELEASE_TAR="$T_TMP/upterm.tar.gz"
t_eq "refused" 1 "$RC"
t_has "and it says why" "$(cat "$OUT")" 'not the pinned one'
t_eq "no managed settings were written" no "$([ -e "$MFILE" ] && echo yes || echo no)"
t_eq "no upterm landed" no "$([ -e "$MROOT/bin/upterm" ] && echo yes || echo no)"

t_section "3 - a failed download refuses too"
CURL_RC=22; export CURL_RC; go; unset CURL_RC
t_eq "refused" 1 "$RC"
t_has "and it says why" "$(cat "$OUT")" 'could not be downloaded'

t_section "4 - floor.pin covers the binary"
go
t_eq "installed, to the token" 4 "$RC"
t_eq "the same bytes give the same pin" "$_before" "$(cat "$MROOT/floor.pin")"
printf '#!/bin/sh\necho swapped\n' > "$T_TMP/release/upterm"
tar -czf "$T_TMP/upterm2.tar.gz" -C "$T_TMP/release" upterm
_d="$(shasum -a 256 "$T_TMP/upterm2.tar.gz" 2>/dev/null || sha256sum "$T_TMP/upterm2.tar.gz")"; _d="${_d%% *}"
sed -e "s/^sha256-linux-amd64\t.*/sha256-linux-amd64\t$_d/" -e "s/^sha256-linux-arm64\t.*/sha256-linux-arm64\t$_d/" "$CORE/contracts/support-upterm.tsv" > "$T_TMP/pin"
cp "$T_TMP/pin" "$CORE/contracts/support-upterm.tsv"
git -C "$CORE" add -A; git -C "$CORE" -c user.name=t -c user.email=t@t commit -q -m pin; PIN="$(git -C "$CORE" rev-parse HEAD)"
RELEASE_TAR="$T_TMP/upterm2.tar.gz"; go
t_eq "a new pin installs, to the token" 4 "$RC"
_new="$(cat "$MROOT/floor.pin")"
[ "$_new" != "$_before" ] && t_pass || t_fail "floor.pin did not change with the binary: the integrity hash doesn't see it"

t_section "5 - the relay in policy reaches the managed settings at install"
_first_allow="$(jq -r '.sandbox.network.allowedDomains | join(" ")' "$MFILE")"
t_eq "the first install denies the public relay" uptermd.upterm.dev "$(jq -r '.sandbox.network.deniedDomains | join(" ")' "$MFILE")"
printf '{"serial":2,"support":{"relay":"wss://relay.example:8443"},"hosts":["pkg.example.com","*.corp.example"]}\n' > "$T_TMP/policy-moved.json"
ssh-keygen -Y sign -q -f "$T_TMP/hub-key" -n harbor-hub "$T_TMP/policy-moved.json"
cat > "$MROOT/bin/hub-sync.sh" <<EOF
#!/bin/sh
printf 'hub-sync %s\n' "\$*" >> "\$CALLS"
[ "\$1" != path ] || printf '%s\n' "$T_TMP/policy-moved.json"
exit 0
EOF
cp "$MROOT/bin/hub-sync.sh" "$T_TMP/hub-sync.stub"   # the install lands the real one over it
# Run where a file matches the *. row, so a glob would turn it into that file's name.
mkdir -p "$T_TMP/glob"; : > "$T_TMP/glob/bait.corp.example"; _here="$(pwd)"; cd "$T_TMP/glob"
RELEASE_TAR="$T_TMP/upterm2.tar.gz"; go
cd "$_here"
t_eq "re-run after the policy moved, to the token" 4 "$RC"
t_eq "the hub relay is denied, and the public one stays" 'relay.example uptermd.upterm.dev' "$(jq -r '.sandbox.network.deniedDomains | join(" ")' "$MFILE")"
t_eq "the policy's hosts reach the allowlist, a *. row as one word, not a glob" '*.corp.example pkg.example.com' \
  "$(jq -r '[.sandbox.network.allowedDomains[] | select(test("example"))] | sort | join(" ")' "$MFILE")"
t_eq "CONTROL: the first install had neither" 0 "$(printf '%s' "$_first_allow" | grep -c example || :)"
# The same file with a host added after signing: the install's own check refuses all of its hosts.
jq -c '.hosts += ["evil.example.net"]' "$T_TMP/policy-moved.json" > "$T_TMP/p.tmp" && cp "$T_TMP/p.tmp" "$T_TMP/policy-moved.json"
cp "$T_TMP/hub-sync.stub" "$MROOT/bin/hub-sync.sh"
_here="$(pwd)"; cd "$T_TMP/glob"; go; cd "$_here"
t_eq "the install still lands, to the token" 4 "$RC"
t_eq "a policy changed after signing adds no host" '' "$(jq -r '[.sandbox.network.allowedDomains[] | select(test("example"))] | join(" ")' "$MFILE")"
t_has "and the install says why" "$(cat "$OUT")" 'does not verify'

t_section "6 - macOS has no pinned binary, and says so"
HARBOR_MEMBER_OS=Darwin; : > "$CALLS"
chmod -R u+w "$SYS"; rm -rf "$SYS"; mkdir -p "$SYS"
RELEASE_TAR="$T_TMP/upterm2.tar.gz"; go
t_eq "the install still lands, to the token" 4 "$RC"
t_has "it says what it skipped" "$(cat "$OUT")" 'upterm is not installed here'
t_eq "nothing was downloaded" 0 "$(grep -c '^curl' "$CALLS" || :)"
HARBOR_MEMBER_OS=Linux

t_section "7 - the Windows shortcut (text only: PowerShell has never run here)"
mkdir -p "$T_TMP/stage/harbor/bin"; printf '{}' > "$T_TMP/stage/managed-settings.json"; printf 'x' > "$T_TMP/stage/harbor/bin/f"
PS="$(HARBOR_MEMBER_OS=WSL sh "$T_ROOT/bin/member-windows.sh" --stage "$T_TMP/stage" --member alice 2>/dev/null)"
t_has "it lands in the Start Menu" "$PS" 'Start Menu\Programs\Harbor Support.lnk'
t_has "it runs wsl.exe" "$PS" "System32\\wsl.exe"
t_has "as the member, in the named distro, from the start folder, on the managed copy" "$PS" "'-d Ubuntu -u alice --cd /home/alice""/port --exec /bin/sh \"/mnt/c/Program Files/ClaudeCode/harbor/bin/member-support.sh\"'"
t_has "a window the person sees" "$PS" 'WindowStyle = 1'
t_hasnt "never hidden, never a startup entry" "$PS" 'Startup'
t_hasnt "and no task" "$PS" 'Register-ScheduledTask'
_rc=0; HARBOR_MEMBER_OS=WSL sh "$T_ROOT/bin/member-windows.sh" --stage "$T_TMP/stage" --member "a'b" >/dev/null 2>&1 || _rc=$?
t_eq "a name that could break the quote is refused" 2 "$_rc"
t_hasnt "without --member, no shortcut" "$(HARBOR_MEMBER_OS=WSL sh "$T_ROOT/bin/member-windows.sh" --stage "$T_TMP/stage" 2>/dev/null)" 'CreateShortcut'
t_has "the uninstall removes it" "$(sh "$T_ROOT/bin/member-windows.sh" --uninstall 2>/dev/null)" 'Harbor Support.lnk'
t_done
