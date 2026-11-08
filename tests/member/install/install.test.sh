#!/usr/bin/env sh
# member-install.sh end to end, up to what only a real laptop can show (harbor#1278): managed root, ledger, deploy as the member, token, leaving.
# Root's tools are stubs, so this proves the commands and the bytes, never that root ran them. Not proved here: docs/how-to/member-install.md, "Not verified".
. "$(dirname "$0")/../../lib/core.sh"; t_init
T_TMP="$(cd "$T_TMP" && pwd -P)"
. "$T_ROOT/tests/member/fixture.sh"
. "$T_ROOT/bin/library-fs.sh"
core_checkout; root_stubs
HARBOR_MEMBER_OS=Linux; export HARBOR_MEMBER_OS
ARGS="--user alice --hub fixture-org/fixture-hub --login alice-gh --signers $SIGNERS --pin $PIN"
go() { RC=0; sh "$CORE/bin/member-install.sh" --user alice --hub fixture-org/fixture-hub --login alice-gh --signers "$SIGNERS" --pin "$PIN" "$@" >"$OUT" 2>&1 </dev/null || RC=$?; }
clean() { chmod -R u+w "$SYS" 2>/dev/null; rm -rf "$SYS"; mkdir -p "$SYS"; rm -rf "$MHOME" "$STORE"; mkdir -p "$MHOME" "$STORE"; : > "$CALLS"; }

t_section "refusals come before any write"
RC=0; env -u HARBOR_SCOPE_MANAGED_SETTINGS sh "$CORE/bin/member-install.sh" --user alice --uninstall >"$OUT" 2>&1 || RC=$?
t_eq "a member can't uninstall: not root, no override (M2)" 1 "$RC"; t_has "...and is told who can" "$(cat "$OUT")" 'IT runs this'
t_exit "--help answers with no root" 0 env -u HARBOR_SCOPE_MANAGED_SETTINGS sh "$CORE/bin/member-install.sh" --help
install --user root --hub o/n --login a --signers "$SIGNERS" --pin "$PIN"; t_eq "root is no member" 2 "$RC"
install --user nosuch --hub o/n --login a --signers "$SIGNERS" --pin "$PIN"; t_eq "an unknown account" 1 "$RC"
install --user 'al;ice' --hub o/n --login a --signers "$SIGNERS" --pin "$PIN"; t_eq "a name with a shell character" 2 "$RC"
for _n in .. . .x 1001 abcdefghijabcdefghijabcdefghijabc; do
  install --user "$_n" --hub o/n --login a --signers "$SIGNERS" --pin "$PIN"; t_eq "a name useradd mangles or reads as a uid: '$_n'" 2 "$RC"
done
install --user alice --hub o/n; t_eq "half the arguments" 2 "$RC"
install --user alice --hub o/n --login a --signers "$SIGNERS" --pin abc; t_eq "a short pin" 2 "$RC"
ID_GROUPS='alice sudo'; export ID_GROUPS; go; t_eq "a member who is an admin" 1 "$RC"; t_has "...named as such" "$(cat "$OUT")" 'is in the group sudo'; unset ID_GROUPS
ID_GROUPS='alice docker'; export ID_GROUPS; go; t_eq "the docker group is root by another name" 1 "$RC"; t_has "...named as such" "$(cat "$OUT")" 'is in the group docker'; unset ID_GROUPS
for _g in lxd incus incus-admin libvirt libvirtd microk8s disk; do
  ID_GROUPS="alice $_g"; export ID_GROUPS; go; t_eq "the $_g group is root by another name" 1 "$RC"; t_has "...named as such" "$(cat "$OUT")" "is in the group $_g"
done
ID_GROUPS='alice staff dialout'; export ID_GROUPS; go; t_hasnt "CONTROL: an ordinary group is no admin" "$(cat "$OUT")" 'is in the group'; unset ID_GROUPS
SUDO_GRANT='(ALL : ALL) ALL'; export SUDO_GRANT; go; t_eq "a per-user sudoers grant, with no group" 1 "$RC"; t_has "...named as such" "$(cat "$OUT")" 'has a sudoers grant ((ALL : ALL) ALL)'
SUDO_GRANT='(root) NOPASSWD: /usr/bin/apt-get'; go; t_eq "a narrow grant is still a grant" 1 "$RC"
SUDO_GRANT="(root) NOPASSWD: /bin/sh $(printf '%s' "$MROOT/bin/member-prereqs.sh" | sed 's/ /\\\\ /g')\n    (root) NOPASSWD: /bin/sh /tmp/evil.sh"; go; t_eq "the install's own rule hides no second line" 1 "$RC"; t_has "...naming the second" "$(cat "$OUT")" '/tmp/evil.sh'
SUDO_GRANT="(root) NOPASSWD: /bin/sh $(printf '%s' "$MROOT/bin/member-prereqs.sh" | sed 's/ /\\\\ /g')"; go; t_eq "CONTROL: the install's own rule alone, on a re-run, is no grant: the run reaches the token" 4 "$RC"
unset SUDO_GRANT; clean
printf 'someone ssh-ed25519 AAAA\n' > "$T_TMP/badsigners"
install --user alice --hub o/n --login a --signers "$T_TMP/badsigners" --pin "$PIN"; t_eq "signers with no hub principal" 1 "$RC"
install --user alice --hub o/n --login a --signers "$SIGNERS" --pin 0000000000000000000000000000000000000000; t_eq "a pin this checkout isn't at (R10)" 1 "$RC"
printf x >> "$CORE/contracts/hub.md"; go; t_eq "a dirty checkout would become the floor" 1 "$RC"; git -C "$CORE" checkout -q contracts/hub.md
mkdir -p "$SYS/managed-settings.d"; printf '{}\n' > "$SYS/managed-settings.d/50.json"; go
t_eq "a drop-in that outranks the file refuses (F10)" 1 "$RC"; t_has "...naming it" "$(cat "$OUT")" 'drop-in files'
t_eq "...and nothing was written" no "$([ -e "$MFILE" ] || [ -e "$MROOT" ] && echo yes || echo no)"
rm -rf "$SYS/managed-settings.d"
printf '{"model":"opus"}\n' > "$MFILE"; go; t_eq "a file another writer owns refuses" 1 "$RC"
t_eq "...and it is left as it was" '{"model":"opus"}' "$(cat "$MFILE")"; rm -f "$MFILE"
mv "$CORE/bin/hub-tier.sh" "$T_TMP/held"; git -C "$CORE" -c user.name=t -c user.email=t@t commit -qam drop; P2="$(git -C "$CORE" rev-parse HEAD)"
RC=0; sh "$CORE/bin/member-install.sh" --user alice --hub o/n --login a --signers "$SIGNERS" --pin "$P2" >"$OUT" 2>&1 </dev/null || RC=$?
t_eq "a listed file the checkout lacks refuses: no half floor" 1 "$RC"; t_has "...naming it" "$(cat "$OUT")" 'bin/hub-tier.sh'
t_eq "...before the settings file exists" no "$([ -e "$MFILE" ] && echo yes || echo no)"
git -C "$CORE" reset -q --hard "$PIN"

t_section "prerequisites, no prompt"
clean; go; t_eq "a clean run with no token lands the floor and stops at the token" 4 "$RC"
t_eq "stdin was never asked for: the run above had none, and got that far" 4 "$RC"
t_has "apt installs jq (M9)" "$(cat "$CALLS")" ' jq '
for p in curl openssh-client bubblewrap socat; do t_has "apt installs $p" "$(grep '^apt-get install' "$CALLS")" " $p"; done
APT_RC=1; export APT_RC; clean; go; t_eq "a failed install stops the run" 1 "$RC"; unset APT_RC
t_eq "...before the floor" no "$([ -e "$MROOT" ] && echo yes || echo no)"

t_section "the managed root"
clean; go
n=0; for f in $(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$T_ROOT/contracts/member-files.txt" | awk '{ print ($2 != "" ? $2 : $1) }' | sed 's|.*/||'); do
  n=$((n + 1)); [ -f "$MROOT/bin/$f" ] || t_fail "$f did not land"
done
t_eq "every listed file landed, flat" "$n" "$(ls "$MROOT/bin" | grep -vc -e '^harbor-member-mode$' -e '^upterm$')"   # upterm is fetched by digest, not listed
t_eq "bytes are the checkout's" same "$(cmp -s "$CORE/standards/naming/controls.tsv" "$MROOT/bin/controls.tsv" && echo same)"
t_eq "harbor-member-mode is there, empty" 0 "$(wc -c < "$MROOT/bin/harbor-member-mode" | tr -d ' ')"
t_eq "hub-signers is the given file" same "$(cmp -s "$SIGNERS" "$MROOT/hub-signers" && echo same)"
t_exit "floor.pin is what integrity reads, at the real path" 0 env HARBOR_MEMBER_ROOT="$MROOT" sh "$MROOT/bin/member-integrity.sh" check
t_eq "floor.pin is 16 hex" 16 "$(tr -d '\n' < "$MROOT/floor.pin" | wc -c | tr -d ' ')"
t_exit "the settings are JSON" 0 jq -e 'type == "object"' "$MFILE"
t_has "the hooks name the real root" "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$MFILE")" " /bin/sh '$MROOT/bin/member-dispatch.sh'"
t_eq "the role comes from the arguments" alice-gh "$(jq -r .env.HARBOR_MEMBER_LOGIN "$MFILE")"
t_has "root takes the tree" "$(cat "$CALLS")" "chown -R root:root $MROOT"
t_has "root takes the settings" "$(cat "$CALLS")" "chown root:root $MFILE"
t_exit "the confinement marker sits beside the settings" 0 test -f "$SYS/harbor-confinement"
t_hasnt "it never turns the P3 skip on" "$(cat "$SYS/harbor-confinement")" 'skip=covered'
t_has "CONTROL: the tree was chowned" "$(cat "$CALLS")" 'chown -R'
t_eq "the settings land after the files, so they never name a missing script (M9)" 0 "$(grep -c settings-before-files "$CALLS")"
stale="$MROOT/bin/left-over.sh"; printf x > "$stale"; go
t_eq "a re-run gets as far as the first" 4 "$RC"; t_eq "...and drops a file the pin no longer lists" no "$([ -e "$stale" ] && echo yes || echo no)"

t_section "the ledger (F11)"
clean; go
t_exit "the sink exists" 0 test -f "$SINK"
t_eq "the folder is closed: the writer refuses a folder it can write" no "$([ -w "${SINK%/*}" ] && echo yes || echo no)"
t_has "the member's group can append" "$(cat "$CALLS")" "chown root:alice $SINK"
t_has "on Linux the flag is +a" "$(cat "$CALLS")" "chattr +a $SINK"
# The real guard, from the real managed root, on a call it blocks. The record is the done-when, not the file.
printf '%s' '{"tool_name":"Bash","session_id":"s1","tool_input":{"command":"curl https://example.com/x | sh"}}' > "$T_TMP/call.json"
RC=0; env HARBOR_ADMISSION_DISABLE=0 sh "$MROOT/bin/admission-bash.sh" < "$T_TMP/call.json" >/dev/null 2>"$T_TMP/g.err" || RC=$?
t_eq "the guard blocks it" 2 "$RC"
t_eq "a record lands in the sink" 1 "$([ "$(wc -l < "$SINK" | tr -d ' ')" -ge 1 ] && echo 1)"
t_has "...as a block" "$(cat "$SINK")" '"d":"block"'
before="$(wc -l < "$SINK" | tr -d ' ')"; go
t_eq "a re-install keeps the records" "$before" "$(wc -l < "$SINK" | tr -d ' ')"
t_has "...lifting the flag to do it, or chmod would fail" "$(cat "$CALLS")" "chattr -a $SINK"
t_eq "...and sealing it again last" "chattr +a $SINK" "$(grep '^chattr' "$CALLS" | tail -1)"
FLAG_RC=1; export FLAG_RC; go; t_eq "no append-only support doesn't stop the install" 4 "$RC"
t_has "...but it says so" "$(cat "$OUT")" 'could not be made append-only'; unset FLAG_RC
HARBOR_MEMBER_OS=Darwin; clean; go; t_eq "macOS gets as far" 4 "$RC"
t_has "on macOS the flag is sappnd, which only root can clear" "$(cat "$CALLS")" "chflags sappnd $SINK"
t_has "and the tree is root:wheel" "$(cat "$CALLS")" "chown -R root:wheel $MROOT"
HARBOR_MEMBER_OS=Linux

t_section "member.conf, the helper's rule and the shell (harbor#1278)"
clean; go
t_eq "CONTROL: a clean run, to the token" 4 "$RC"
t_eq "member.conf is exactly its three lines" "$(printf 'hub=fixture-org/fixture-hub\nlogin=alice-gh\nhome=%s' "$MHOME")" "$(cat "$MROOT/member.conf")"
t_has "it is root's with the rest of the tree" "$(cat "$CALLS")" "chown -R root:root $MROOT"
t_eq "and the member can read it" 644 "$(fs_mode "$MROOT/member.conf")"
clean; go
SR="$SYS/etc/sudoers.d/harbor-member-prereqs"
t_eq "the rule names one command and no wildcard" "alice ALL=(root) NOPASSWD: /bin/sh $(printf '%s' "$MROOT/bin/member-prereqs.sh" | sed 's/ /\\ /g')" "$(sed -n 2p "$SR")"
t_eq "and nothing else" 2 "$(wc -l < "$SR" | tr -d ' ')"
t_eq "sudo's own mode" 440 "$(fs_mode "$SR")"
t_has "visudo read it first" "$(cat "$CALLS")" 'visudo -c -q -f'
t_has "root's" "$(cat "$CALLS")" "chown root:root $SR"
if [ -x /usr/sbin/visudo ]; then t_exit "the real visudo takes the rule, a space in the path and all" 0 /usr/sbin/visudo -c -q -f "$SR"
else echo "install-test: SKIPPED the real visudo (absent here)"; fi
clean; VISUDO_RC=1; export VISUDO_RC; go; t_eq "a rule visudo refuses stops the run" 1 "$RC"; unset VISUDO_RC
t_exit "...and never lands" 1 test -e "$SR"
clean; go
t_exit "the install made ~/port" 0 test -d "$MHOME/port"
SP="$SYS/etc/profile.d/harbor-member.sh"; mkdir -p "$MHOME/elsewhere"
shell_in() { ( cd "$1" && HOME="$MHOME" sh -ic '. "$0"; pwd' "$SP" 2>/dev/null ); }
t_eq "an interactive shell in the home folder starts in ~/port" "$MHOME/port" "$(shell_in "$MHOME")"
t_eq "one opened elsewhere stays" "$MHOME/elsewhere" "$(shell_in "$MHOME/elsewhere")"
t_eq "a script is left alone" "$MHOME" "$( cd "$MHOME" && HOME="$MHOME" sh -c '. "$0"; pwd' "$SP" )"
t_eq "another user is left alone" "$T_TMP" "$( cd "$T_TMP" && HOME="$T_TMP" sh -ic '. "$0"; pwd' "$SP" 2>/dev/null )"
RC=0; sh "$CORE/bin/member-install.sh" --user alice --uninstall >"$OUT" 2>&1 </dev/null || RC=$?
t_eq "leaving exits 0" 0 "$RC"
t_exit "and takes the rule" 1 test -e "$SR"
t_exit "and the shell line" 1 test -e "$SP"
HARBOR_MEMBER_OS=Darwin; export HARBOR_MEMBER_OS; clean; go
t_exit "macOS has no package manager to call, so no rule" 1 test -e "$SR"
HARBOR_MEMBER_OS=Linux; export HARBOR_MEMBER_OS

t_section "the user tier runs as the member"
clean; go
t_eq "every user step went through sudo -u alice -H" 0 "$(grep '^sudo' "$CALLS" | grep -cv '^sudo -u alice -H$')"
t_has "deploy takes the member path at the pin" "$(cat "$CALLS")" "deploy --apply --live --member --pin $PIN --unattended unattended=1 snapshot-empty=yes"
t_exit "the member owns a copy of the checkout at the pin" 0 test -d "$MHOME/port/harbor/.git"
t_eq "...at the pin" "$PIN" "$(git -C "$MHOME/port/harbor" rev-parse HEAD)"
t_eq "...clean" '' "$(git -C "$MHOME/port/harbor" status --porcelain)"
t_exit "harbor scope install seeded settings.json" 0 test -f "$MHOME/.claude/settings.json"
t_exit "...and the register" 0 test -f "$MHOME/port/harbor-private/access/register.md"
DEPLOY_RC=1; export DEPLOY_RC; clean; go; t_eq "a failed deploy fails the run" 1 "$RC"
t_exit "...and the managed floor stays on" 0 test -f "$MFILE"; unset DEPLOY_RC

t_section "the token (R7), with the real access.sh from the flat folder"
clean; go; t_has "with no token the run says what to do next" "$(cat "$OUT")" '--token-stdin'
t_eq "and isn't finished: no token is no policy, and a joined laptop with none refuses every call" 4 "$RC"
t_has "...in plain words" "$(cat "$OUT")" 'every Claude Code step is refused'
t_hasnt "...and it fetched nothing" "$(cat "$CALLS")" 'hub-sync fetch'
t_eq "and stored nothing" 0 "$(ls "$STORE" | wc -l | tr -d ' ')"
tok() { RC=0; printf 'github_pat_fixture\n' | sh "$CORE/bin/member-install.sh" --user alice --token-stdin >"$OUT" 2>&1 || RC=$?; }
tok; t_eq "the token step exits 0" 0 "$RC"
t_eq "the value reached bin/secret, newline gone" github_pat_fixture "$(cat "$STORE/hub-token")"
t_has "the register names it" "$(cat "$MHOME/port/harbor-private/access/register.md")" 'secret: hub-token'
t_has "the first fetch ran with the managed env" "$(cat "$CALLS")" 'hub-sync fetch repo=fixture-org/fixture-hub'
t_has "and the policy it fetched was checked" "$(cat "$CALLS")" 'hub-sync check repo=fixture-org/fixture-hub'
t_hasnt "the old words are gone: no core defaults apply to a joined laptop" "$(cat "$OUT")" 'core defaults'
tok; t_eq "a second token replaces the value" 0 "$RC"; t_eq "...once" github_pat_fixture "$(cat "$STORE/hub-token")"
cp "$MROOT/bin/hub-sync.sh" "$T_TMP/sync.keep"; printf '{}\n' > "$T_TMP/p.json"; : > "$T_TMP/p.json.sig"
stub "$MROOT/bin/hub-sync.sh" 'printf "hub-sync %s\n" "$*" >> "$CALLS"; [ "$1" != path ] || printf "%s\n" "$P_JSON"; exit 0'
P_JSON="$T_TMP/p.json"; export P_JSON; tok; unset P_JSON
t_eq "the token step alone reads a fetched policy's hosts, with a work folder to read them in" 0 "$RC"
t_has "...and says the copy didn't verify, so no host was added" "$(cat "$OUT")" 'none of its hosts or its relay are applied'
cat "$T_TMP/sync.keep" > "$MROOT/bin/hub-sync.sh"
go; t_eq "a re-run with a token already stored fetches, and finishes" 0 "$RC"
SYNC_RC=3; export SYNC_RC; tok; t_eq "hub unreachable: not finished, its own exit" 5 "$RC"
t_has "...telling IT what to look at" "$(cat "$OUT")" 'Check that this laptop reaches github.com'
t_has "...and the token's grant" "$(cat "$OUT")" 'Contents read, not expired'
t_has "...and how to finish" "$(cat "$OUT")" 'hub-sync.sh'"'"' check, both exit 0'
t_hasnt "...never that defaults apply" "$(cat "$OUT")" 'core defaults'
go; t_eq "the full install, unreachable, isn't finished either" 5 "$RC"
SYNC_RC=1; tok; t_eq "a refused policy is a failure: wrong key" 1 "$RC"; unset SYNC_RC
CHECK_RC=2; export CHECK_RC; tok; t_eq "fetched but nothing verifies: not finished" 5 "$RC"; t_has "...said" "$(cat "$OUT")" 'no policy on this laptop verifies'
CHECK_RC=1; tok; t_eq "present but none verifies: the same" 5 "$RC"; unset CHECK_RC
rm -f "$STORE/hub-token"; NO_STORE=1; export NO_STORE; tok
t_eq "no secret store: its own exit" 4 "$RC"; t_has "...stated" "$(cat "$OUT")" 'Nothing was written in its place'
unset NO_STORE
t_eq "no file anywhere holds the token" '' "$(grep -rl github_pat_fixture "$MHOME" "$SYS" "$STORE" 2>/dev/null)"
t_exit "the floor is still on" 0 test -f "$MFILE"
RC=0; printf 'x' | sh "$CORE/bin/member-install.sh" --user alice --token-stdin >"$OUT" 2>&1 || RC=$?; t_eq "CONTROL: that grep can see a stored value" 0 "$RC"
t_eq "CONTROL: it finds this one" "$STORE/hub-token" "$(grep -rl x "$STORE" 2>/dev/null)"

t_section "the token reaches the member's own session bus (W7): sudo drops it, so it is derived from the uid"
RUN="$T_TMP/run"; ME="$(/usr/bin/id -u)"; mkdir -p "$RUN/$ME"; chmod 700 "$RUN/$ME"
bus() { MEMBER_INSTALL_LIB=1 sh -c '. "$0"; member_bus_env "$1" "$2"' "$CORE/bin/member-install.sh" "$@" 2>/dev/null; }
t_eq "no bus socket: nothing, so the store says what it says today" '' "$(bus "$ME" "$RUN")"
if python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$RUN/$ME/bus" 2>/dev/null; then
  t_eq "the member's bus: both names, from the uid" "$(printf 'XDG_RUNTIME_DIR=%s\nDBUS_SESSION_BUS_ADDRESS=unix:path=%s/bus' "$RUN/$ME" "$RUN/$ME")" "$(bus "$ME" "$RUN")"
  mkdir -p "$RUN/4242"; ln -s "$RUN/$ME/bus" "$RUN/4242/bus"
  t_eq "another uid's folder, or a link to a bus, is never this member's bus" '' "$(bus 4242 "$RUN")"
  t_has "CONTROL: with the caller's own bus in env, the member's is named..." "$(DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/caller XDG_RUNTIME_DIR=/tmp bus "$ME" "$RUN")" "unix:path=$RUN/$ME/bus"
  t_hasnt "...and the caller's never is" "$(DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/caller XDG_RUNTIME_DIR=/tmp bus "$ME" "$RUN")" '/tmp/caller'
else echo "install-test: SKIPPED the bus socket cases (no unix socket can be made here, as in a sandbox: run outside it)"; fi
rm -f "$RUN/$ME/bus"; ln -s "$T_TMP" "$RUN/$ME/bus"; t_eq "a link where the socket should be: nothing" '' "$(bus "$ME" "$RUN")"

t_section "the first policy's hosts and relay land in the same run (N5), never from an older serial (N6)"
ssh-keygen -q -t ed25519 -N '' -C hub -f "$T_TMP/hubkey"; KEEP_SIGNERS="$SIGNERS"; SIGNERS="$T_TMP/real-signers"
printf 'hub namespaces="harbor-hub" %s\n' "$(cut -d' ' -f1,2 "$T_TMP/hubkey.pub")" > "$SIGNERS"
mkpolicy() { # <serial> [key]: a signed policy adding one host and naming the hub's relay
  mkdir -p "$T_TMP/pol"; P_JSON="$T_TMP/pol/policy.json"; export P_JSON
  jq -n --argjson s "$1" '{schema: 1, serial: $s, hosts: ["pypi.example-company.com"], support: {relay: "wss://relay.example-company.com:443"}}' > "$P_JSON"
  rm -f "$P_JSON.sig"; ssh-keygen -q -Y sign -f "${2:-$T_TMP/hubkey}" -n harbor-hub "$P_JSON" 2>/dev/null
}
allowed() { jq -r --arg h "$1" '.sandbox.network.allowedDomains | index($h) != null' "$MFILE"; }
denied() { jq -r --arg h "$1" '.sandbox.network.deniedDomains | index($h) != null' "$MFILE"; }
clean; mkpolicy 3; go
t_eq "CONTROL: a first run with no token stops there" 4 "$RC"
t_eq "...and its settings can't hold the policy's host yet: none was fetched" false "$(allowed pypi.example-company.com)"
tok; t_eq "the token step finishes" 0 "$RC"
t_eq "the policy's host is allowed, in the same run" true "$(allowed pypi.example-company.com)"
t_eq "the policy's relay is denied, in the same run" true "$(denied relay.example-company.com)"
t_hasnt "nothing asks for a second run" "$(cat "$OUT")" 'run this install again'
t_exit "the floor is pinned again over the new settings" 0 env HARBOR_MEMBER_ROOT="$MROOT" sh "$MROOT/bin/member-integrity.sh" check
t_eq "and the serial it applied is recorded" 3 "$(cat "$MROOT/pin.serial")"
t_eq "the MCP list is the landed file's own" '[]' "$(jq -c .allowedMcpServers "$MFILE")"
cp "$MFILE" "$T_TMP/ms.keep"; go
t_eq "a full re-run keeps them: the stage composes from the verified copy" 0 "$RC"
t_eq "...the host" true "$(allowed pypi.example-company.com)"
printf '5\n' > "$MROOT/pin.serial"; go
t_eq "a policy below the serial already applied refuses a re-run (N6)" 1 "$RC"
t_has "...named as an old signed file" "$(cat "$OUT")" 'serial 3, below the 5 already applied'
t_eq "...and the settings are as they were" same "$(cmp -s "$MFILE" "$T_TMP/ms.keep" && echo same)"
tok; t_eq "the token step refuses it too" 1 "$RC"
printf '3\n' > "$MROOT/pin.serial"; ssh-keygen -q -t ed25519 -N '' -f "$T_TMP/strangerkey"; mkpolicy 4 "$T_TMP/strangerkey"
clean; go; tok
t_eq "a policy another key signed (hub-sync is stubbed to pass it): the token step ends" 0 "$RC"
t_has "...saying root's own check refused it" "$(cat "$OUT")" 'does not verify against'
t_eq "...and none of its hosts reach the settings" false "$(allowed pypi.example-company.com)"
unset P_JSON; SIGNERS="$KEEP_SIGNERS"

t_section "the Windows half"
clean; HARBOR_MEMBER_OS=WSL; PS="$T_TMP/harbor-member.ps1"; go --windows-out "$PS"
t_eq "first run stops for the administrator" 3 "$RC"
t_has "...saying what to run" "$(cat "$OUT")" 'ExecutionPolicy Bypass'
t_eq "...having written nothing to the Windows folder" no "$([ -e "$MFILE" ] && echo yes || echo no)"
t_hasnt "...and deployed nothing yet" "$(cat "$CALLS") -" 'deploy --apply'
fake_ps "$PS" "$SYS"
go --windows-out "$PS"; t_eq "after it ran, the same command goes on, to the token" 4 "$RC"
t_has "...reading it back byte for byte" "$(cat "$OUT")" 'byte for byte'
t_has "...and deploys" "$(cat "$CALLS")" 'deploy --apply'
printf x >> "$MROOT/bin/library-admission.sh"; go --windows-out "$PS"
t_eq "a changed byte under the Windows folder is not landed" 3 "$RC"
HARBOR_MEMBER_OS=Linux

t_section "bwrap's AppArmor profile (R8)"
# deploy-confinement.sh pins PATH past any stub, and its probe has its own suite, so here the probe's answer is what is stubbed.
AP="$T_TMP/apparmor"; mkdir -p "$AP"
PREFLIGHT="$T_TMP/pf"; export PREFLIGHT; : > "$PREFLIGHT"
aa() { RC=0; MEMBER_INSTALL_LIB=1 sh -c '. "$0"; MEMBER=alice; OS=Linux; member_apparmor "$1"' "$CORE/bin/member-install.sh" "$AP" >"$OUT" 2>&1 || RC=$?; }
stub "$CORE/bin/deploy-confinement.sh" '[ -s "$PREFLIGHT" ]'
stub "$T_BIN/apparmor_parser" 'printf "apparmor_parser %s\n" "$*" >> "$CALLS"; echo ok > "$PREFLIGHT"'
aa; t_eq "a blocked bwrap gets the profile and passes" 0 "$RC"
t_has "...the profile names userns" "$(cat "$AP/bwrap")" 'userns'
t_has "...and is loaded" "$(cat "$CALLS")" "apparmor_parser -r $AP/bwrap"
: > "$PREFLIGHT"; stub "$T_BIN/apparmor_parser" 'exit 0'; aa; t_eq "still blocked after it: refused" 1 "$RC"
rm -rf "$AP"; aa; t_eq "no AppArmor folder to fix it with: refused" 1 "$RC"
git -C "$CORE" checkout -q bin/deploy-confinement.sh; unset PREFLIGHT

t_section "leaving (M2, F27)"
clean; go; printf 'tok' | sh "$CORE/bin/member-install.sh" --user alice --token-stdin >/dev/null 2>&1
mkdir -p "$MHOME/.local/state/harbor/hub"; : > "$MHOME/.local/state/harbor/hub/policy.json"
install --user alice --uninstall; t_eq "--uninstall exits 0" 0 "$RC"
t_eq "the managed root is gone" no "$([ -e "$MROOT" ] && echo yes || echo no)"
t_eq "the settings are gone" no "$([ -e "$MFILE" ] && echo yes || echo no)"
t_eq "the marker is gone" no "$([ -e "$SYS/harbor-confinement" ] && echo yes || echo no)"
t_eq "the hub state is gone" no "$([ -e "$MHOME/.local/state/harbor/hub" ] && echo yes || echo no)"
t_eq "the token is gone" no "$([ -e "$STORE/hub-token" ] && echo yes || echo no)"
t_has "the flag was lifted first" "$(cat "$CALLS")" "chattr -a"
printf '{"model":"opus"}\n' > "$MFILE"; install --user alice --uninstall
t_eq "someone else's settings file stays" '{"model":"opus"}' "$(cat "$MFILE")"; rm -f "$MFILE"
HARBOR_MEMBER_OS=WSL; install --user alice --uninstall --windows-out "$PS"
t_has "on WSL leaving is PowerShell too" "$(cat "$PS")" 'disableWslSessions'
HARBOR_MEMBER_OS=Linux

t_section "overrides under root"
rr() { env "$1=x" MEMBER_INSTALL_LIB=1 sh -c '. "$0"; member_refuse_override 0' "$CORE/bin/member-install.sh" >/dev/null 2>&1; echo $?; }
t_eq "the settings override is refused" 1 "$(rr HARBOR_SCOPE_MANAGED_SETTINGS)"
t_eq "the OS override is refused" 1 "$(rr HARBOR_MEMBER_OS)"
t_done
