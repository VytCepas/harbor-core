#!/usr/bin/env sh
# The managed settings a member laptop gets (harbor#1278): one case per property of the floor, read from the composed JSON (F1, F4, F13, M10).
. "$(dirname "$0")/../../lib/core.sh"; t_init
M="$T_ROOT/bin/member-managed.sh"
J="$T_TMP/m.json"
compose() { sh "$M" --hub fixture-org/fixture-hub --login alice "$@" 2>"$T_TMP/err"; }
q() { jq -r "$1" "$J"; }

t_section "the keys"
HARBOR_MEMBER_OS=WSL; export HARBOR_MEMBER_OS
compose > "$J"; t_eq "composes with no root" 0 "$?"
for k in wslInheritsWindowsSettings allowManagedHooksOnly allowManagedPermissionRulesOnly allowManagedMcpServersOnly disableSideloadFlags; do
  t_eq "$k is the JSON true" true "$(jq -c ".$k" "$J")"
done
t_eq "bypass mode is off" disable "$(q .permissions.disableBypassPermissionsMode)"
t_eq "the version floor is the one onFailure needs" 2.1.295 "$(q .requiredMinimumVersion)"
t_eq "the MCP allowlist is empty by default" '[]' "$(jq -c .allowedMcpServers "$J")"
t_eq "Local stays on: the docs grey out WSL with it (#1278), so a Local session fails closed instead" false "$(jq 'has("disableDesktopLocalSessions")' "$J")"
t_eq "...which needs every tool through the blocking hook" '*:block' "$(jq -r '.hooks.PreToolUse[0] | .matcher + ":" + .hooks[0].onFailure' "$J")"
t_has "an arrived approval reaches the person at the next prompt" "$(jq -r '.hooks.UserPromptSubmit[0].hooks[0].command' "$J")" 'hub-approval.sh'"'"' note UserPromptSubmit'
t_eq "SSH sessions are off: the floor doesn't reach them (F15)" '[]' "$(jq -c .sshHostAllowlist "$J")"
printf '[{"serverName":"github"}]\n' > "$T_TMP/mcp.json"
t_eq "an allowlist argument lands" '[{"serverName":"github"}]' "$(compose --mcp-allow "$T_TMP/mcp.json" | jq -c .allowedMcpServers)"
printf '[{"serverName":"a","serverUrl":"b"}]\n' > "$T_TMP/bad.json"
t_exit "an entry with two keys refuses" 2 sh "$M" --hub o/n --login alice --mcp-allow "$T_TMP/bad.json"
t_exit "a bad hub refuses" 2 sh "$M" --hub 'o/n/x' --login alice
t_exit "a bad login refuses" 2 sh "$M" --hub o/n --login 'a;b'

t_section "the managed env of contracts/hub.md"
t_eq "role" member "$(q .env.HARBOR_MEMBER_ROLE)"
t_eq "hub" fixture-org/fixture-hub "$(q .env.HARBOR_HUB_REPO)"
t_eq "login" alice "$(q .env.HARBOR_MEMBER_LOGIN)"
t_eq "root" '/mnt/c/Program Files/ClaudeCode/harbor' "$(q .env.HARBOR_MEMBER_ROOT)"
n=0; for v in $(awk -F'\t' '$3 == "kill-switch" { print $1 }' "$T_ROOT/contracts/env.tsv"); do
  n=$((n + 1)); got="$(q ".env.$v")"
  case "$got" in 1|''|null) t_fail "$v is pinned to '$got'" ;; *) t_pass "$v is pinned, to $got" ;; esac
done
t_eq "every kill switch was looked at" 1 "$([ "$n" -ge 3 ] && echo 1)"
t_eq "the floor's own switch is 0" 0 "$(q .env.HARBOR_ADMISSION_DISABLE)"
t_eq "a mode has no 0, so it holds its default" warn "$(q .env.HARBOR_ADMISSION_SG3)"

t_section "the managed hooks"
t_eq "four commands, whatever the event count" 4 "$(jq -r '[.hooks[][].hooks[].command] | unique | length' "$J")"
t_has "PreToolUse is the dispatcher" "$(q '.hooks.PreToolUse[0].hooks[0].command')" " /bin/sh '/mnt/c/Program Files/ClaudeCode/harbor/bin/member-dispatch.sh'"
t_eq "...for every tool" '*' "$(q '.hooks.PreToolUse[0].matcher')"
t_eq "...and blocks when it fails" block "$(q '.hooks.PreToolUse[0].hooks[0].onFailure')"
t_eq "...the only hook that does" 1 "$(jq '[.hooks[][].hooks[] | select(.onFailure)] | length' "$J")"
for e in PostToolUse PostToolUseFailure Stop; do t_has "$e runs member-post" "$(q ".hooks.$e[0].hooks[0].command")" member-post.sh; done
for e in SessionStart SessionEnd; do t_has "$e runs member-session" "$(q ".hooks.$e[0].hooks[0].command")" member-session.sh; done
t_exit "a root with a quote can't reach a hook command" 1 sh "$M" --hub o/n --login alice --root "/tmp/it's"

t_eq "every hook starts from an empty environment at an absolute /bin/sh: a bare sh resolves from a PATH the settings env can set, and bash imports functions from env (N2)" 0 "$(jq -r '.hooks[][].hooks[].command' "$J" | grep -cv "^/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin [^']* /bin/sh '")"
t_eq "SessionEnd has its own timeout, past member-session.sh's 8-second bound and within the 60 the docs allow" 15 "$(q '.hooks.SessionEnd[0].hooks[0].timeout')"
t_eq "no other hook takes it: each keeps its own default" 1 "$(jq '[.hooks[][].hooks[] | select(.timeout)] | length' "$J")"

t_section "the network: one setting, both ways (W6)"
net() { env HARBOR_DEPLOY_CONFINEMENT_OS=Linux MEMBER_MANAGED_LIB=1 sh -c '. "$0"; [ "$1" = default ] || MEMBER_NETWORK="$1"; member_compose WSL /r fixture-org/fixture-hub alice "" "[]"' "$M" "$1" 2>/dev/null; }
net default > "$T_TMP/net.default"; net open > "$T_TMP/net.open"; net allowlist > "$T_TMP/net.allowlist"
t_eq "allowlist is the default (2026-11-07, reversing open)" "$(jq -S . "$T_TMP/net.allowlist")" "$(jq -S . "$T_TMP/net.default")"
t_eq "allowlist: no WebFetch allow rule" null "$(jq -c .permissions.allow "$T_TMP/net.allowlist")"
t_eq "open: sandboxed commands reach any host, through the one rule" '["WebFetch(domain:*)"]' "$(jq -c .permissions.allow "$T_TMP/net.open")"
t_eq "and nothing else differs between the two" "$(jq -S 'del(.permissions.allow)' "$T_TMP/net.open")" "$(jq -S . "$T_TMP/net.allowlist")"
t_eq "allowManagedDomainsOnly stays on: no lower file adds a host or a rule" true "$(jq .sandbox.network.allowManagedDomainsOnly "$T_TMP/net.default")"
t_eq "the sandbox stays on" true "$(jq .sandbox.enabled "$T_TMP/net.default")"
t_eq "no way round it" false "$(jq .sandbox.allowUnsandboxedCommands "$T_TMP/net.default")"
t_has "CONTROL: credential rows are there in both" "$(jq -c .sandbox.credentials.files "$T_TMP/net.open")" '.local/share/secret'
t_exit "a third value refuses, rather than reading as open" 1 env HARBOR_DEPLOY_CONFINEMENT_OS=Linux MEMBER_MANAGED_LIB=1 sh -c '. "$0"; MEMBER_NETWORK=wide; member_compose WSL /r o/n alice "" "[]"' "$M"
t_eq "the setting is one line" 1 "$(grep -c '^MEMBER_NETWORK=allowlist$' "$M")"
t_has "and carries its W6 mark" "$(grep -B2 '^MEMBER_NETWORK=allowlist$' "$M")" '# W6:'
t_has "the how-to says how a person reports a blocked host" "$(tr '\n' ' ' < "$T_ROOT/docs/how-to/member-install.md")" 'If a site is blocked'

t_section "the workspace (W10)"
t_eq "~/port is a working directory, from the composed workspace" "$(q '.sandbox.filesystem.allowWrite[0]')" "$(q '.permissions.additionalDirectories[0]')"
t_eq "and the only one" 1 "$(jq '.permissions.additionalDirectories | length' "$J")"
t_has "it carries the mark" "$(cat "$M")" '# W10:'

t_section "Edit rows, never Write rows, and no very-high row (M10, F8)"
t_eq "no Write row" 0 "$(jq '[.permissions.deny[] | select(startswith("Write"))] | length' "$J")"
t_eq "every deny row is an Edit row, so nothing an admin approves sits here" 0 "$(jq '[.permissions.deny[] | select(startswith("Edit(") | not)] | length' "$J")"
t_eq "no ask row is composed" 0 "$(jq '[.permissions.ask[]?] | length' "$J")"
t_eq "and no allow row: the network is an allowlist" null "$(jq -c .permissions.allow "$J")"
protected='~/.claude/settings.json ~/.claude/settings.local.json ~/.claude.json ~/.bashrc ~/.zshenv ~/.profile ~/.gitconfig'
for p in $protected; do
  t_has "Edit denies $p" "$(q '.permissions.deny[]')" "Edit($p)"
  t_has "denyWrite names $p" "$(q '.sandbox.filesystem.denyWrite[]')" "$p"
done
for p in .claude/settings.json .claude/settings.local.json .mcp.json .git/config; do
  t_has "Edit denies any project's $p" "$(q '.permissions.deny[]')" "Edit(//**/$p)"
done
for p in '~/.claude/hooks' '~/.local/state/harbor/hub' '~/.local/share/secret'; do
  t_has "Edit denies under $p" "$(q '.permissions.deny[]')" "Edit($p/**)"
  t_has "denyWrite names $p" "$(q '.sandbox.filesystem.denyWrite[]')" "$p"
done
t_has "the managed root is denied, spaces and all" "$(q '.permissions.deny[]')" 'Edit(//mnt/c/Program Files/ClaudeCode/harbor/**)'
t_has "and the settings file" "$(q '.permissions.deny[]')" 'Edit(//mnt/c/Program Files/ClaudeCode/managed-settings.json)'
t_has "and the private layer, which holds the register" "$(q '.permissions.deny[]')" "harbor-private/**)"
# One list feeds both, so a row in one and not the other is a defect in the composer.
rows="$(MEMBER_MANAGED_LIB=1 sh -c '. "$0"; member_protected /r /p' "$M" | wc -l | tr -d ' ')"
t_eq "every protected row became an Edit row" "$rows" "$(jq '.permissions.deny | length' "$J")"
miss="$(MEMBER_MANAGED_LIB=1 sh -c '. "$0"; member_protected "$1" "$2" | member_sandbox_rows "$2"' "$M" "$(q .env.HARBOR_MEMBER_ROOT)" "$(q '.sandbox.filesystem.allowWrite[0]')" \
  | while IFS= read -r p; do jq -e --arg p "$p" '.sandbox.filesystem.denyWrite | index($p)' "$J" >/dev/null || printf '%s\n' "$p"; done)"
t_eq "every protected row is in denyWrite" '' "$miss"

t_section "the strict sandbox, composed by deploy-confinement.sh"
t_eq "the retry is closed" false "$(q .sandbox.allowUnsandboxedCommands)"
t_eq "it can't start unconfined" true "$(q .sandbox.failIfUnavailable)"
t_has "credential rows are on" "$(q '.sandbox.credentials.files[].path')" '~/.ssh'
t_has "the secret store's blobs are hidden too" "$(q '.sandbox.credentials.files[].path')" '~/.local/share/secret'
t_eq "they deny" 0 "$(jq '[.sandbox.credentials.files[] | select(.mode != "deny")] | length' "$J")"
want="$(HARBOR_DEPLOY_CONFINEMENT_OS=Linux sh "$T_ROOT/bin/deploy-confinement.sh" --compose --member | jq -c .network)"
t_eq "the network block is the confinement's own, plus the member hosts" "$want" "$(jq -c '.sandbox.network | del(.deniedDomains) | .allowedDomains |= .[0:($want | fromjson | .allowedDomains | length)]' --arg want "$want" "$J")"
mkdir -p "$HOME/port/harbor-private"
printf 'confinement_strict = "false"\nconfinement_credentials = "false"\n' > "$HOME/port/harbor-private/harbor.toml"
printf 'write /evil\n' > "$HOME/port/harbor-private/confinement-paths.txt"
got="$(compose)"
t_eq "harbor.toml can't reopen the retry (R11)" false "$(printf '%s' "$got" | jq .sandbox.allowUnsandboxedCommands)"
t_hasnt "the private layer adds no row on a member (R11)" "$(printf '%s' "$got" | jq -r '.sandbox.filesystem.allowWrite[]')" /evil
rm -rf "$HOME/port/harbor-private"

t_section "where it lands"
t_eq "macOS" '/Library/Application Support/ClaudeCode/harbor' "$(HARBOR_MEMBER_OS=Darwin sh "$M" --where | head -1)"
t_eq "Linux" /etc/claude-code/harbor "$(HARBOR_MEMBER_OS=Linux sh "$M" --where | head -1)"
t_eq "WSL reads the Windows folder, which only an admin writes" '/mnt/c/Program Files/ClaudeCode/managed-settings.json' "$(sh "$M" --where | tail -1)"
t_eq "an override moves the root with the file" "$T_TMP/x/harbor" "$(HARBOR_SCOPE_MANAGED_SETTINGS="$T_TMP/x/managed-settings.json" sh "$M" --where | head -1)"
t_has "Darwin keeps Seatbelt's network key" "$(HARBOR_MEMBER_OS=Darwin compose | jq -c .sandbox)" enableWeakerNetworkIsolation

t_section "overrides under root"
rr() { env "$1=x" MEMBER_MANAGED_LIB=1 sh -c '. "$0"; member_refuse_override 0' "$M" >/dev/null 2>&1; echo $?; }
for v in HARBOR_SCOPE_MANAGED_SETTINGS HARBOR_MANAGED_SETTINGS HARBOR_MEMBER_OS HARBOR_MEMBER_PREFS_DIR HARBOR_MEMBER_ROOT; do t_eq "$v is refused under root" 1 "$(rr "$v")"; done
t_eq "CONTROL: none set is allowed" 0 "$(env -u HARBOR_MEMBER_OS MEMBER_MANAGED_LIB=1 sh -c '. "$0"; member_refuse_override 0' "$M" >/dev/null 2>&1; echo $?)"
t_eq "CONTROL: a non-root run keeps its override" 0 "$(HARBOR_MEMBER_OS=WSL MEMBER_MANAGED_LIB=1 sh -c '. "$0"; member_refuse_override 501' "$M" >/dev/null 2>&1; echo $?)"

t_section "higher policy sources (F10)"
S="$T_TMP/sys"; mkdir -p "$S"; F="$S/managed-settings.json"
hs() { HARBOR_SCOPE_MANAGED_SETTINGS="$F" sh "$M" --higher-source 2>/dev/null; }
HARBOR_MEMBER_OS=Linux
t_exit "a clean box has none" 0 sh -c 'HARBOR_SCOPE_MANAGED_SETTINGS="$1" sh "$0" --higher-source' "$M" "$F"
mkdir -p "$S/managed-settings.d"; printf '{}\n' > "$S/managed-settings.d/20-x.json"
t_has "a drop-in merges over the file" "$(hs)" 'drop-in files'
rm -rf "$S/managed-settings.d"
printf '{"model":"opus"}\n' > "$F"
t_has "another writer's file is named" "$(hs)" 'did not write'
printf '{"env":{"HARBOR_MEMBER_ROLE":"member"}}\n' > "$F"
t_eq "our own file on a re-run is not one" '' "$(hs)"
rm -f "$F"
HARBOR_MEMBER_OS=Darwin; P="$T_TMP/prefs"; mkdir -p "$P/alice"; HARBOR_MEMBER_PREFS_DIR="$P"; export HARBOR_MEMBER_PREFS_DIR
t_eq "CONTROL: no profile" '' "$(hs)"
: > "$P/alice/com.anthropic.claudecode.plist"
t_has "an MDM profile, per user too" "$(hs)" 'MDM profile'
unset HARBOR_MEMBER_PREFS_DIR
HARBOR_MEMBER_OS=WSL
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$REG_LOG"; exit "${REG_RC:-1}"\n' > "$T_BIN/reg.exe"; chmod +x "$T_BIN/reg.exe"
REG_LOG="$T_TMP/reg"; export REG_LOG
t_eq "no HKLM value: none" '' "$(hs)"
t_has "it asked the policy key" "$(cat "$REG_LOG")" 'HKLM\SOFTWARE\Policies\ClaudeCode /v Settings'
t_has "an HKLM value is named" "$(REG_RC=0 hs)" 'HKLM policy'
t_done
