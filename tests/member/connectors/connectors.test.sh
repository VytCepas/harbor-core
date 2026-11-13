#!/usr/bin/env sh
# connectors.test.sh (harbor#1278, lane I, control member.connectors) — a colleague's API key reaches only an MCP server that Claude Code starts through the managed
# launcher. The canary is made at run time (no secret-shaped literal in the repo); the store is the keychain stub, so nothing reaches a real Keychain.
#   1 the policy's connectors compose (and refuse what must not)   2 the person stores a key   3 the launcher hands it to exactly one server
#   4 every way the agent might reach it, and why each fails        5 the managed files protect the list
# The real sandbox cannot be started here, so what is shown for the agent's own shell is what the layers do: the launcher's refusals, the person-only put, the
# protected rows. docs/how-to/member-install.md ("Residual risk") says what the tests cannot show.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/../../cli/keychain-stub.sh"
unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT HARBOR_MEMBER_ROLE   # the cases that need them set them; a session running this suite has them
H="$T_TMP/home"; PORT="$H/port"; PV="$PORT/harbor-private"; mkdir -p "$H" "$PORT"   # the launcher derives both from member.conf home: it keeps no override
export HOME="$H" HARBOR_SCOPE_PRIVATE="$PV" PORT_ROOT="$PORT"
sh "$T_ROOT/bin/scope.sh" install --private-only >/dev/null 2>&1
# A managed root as it lands: bin beside connectors.json and member.conf. The two scripts are real copies (the root is found from where they sit); the store tools are links.
MR="$T_TMP/m/harbor"; mkdir -p "$MR/bin"
for f in member-mcp-launch.sh member-connectors.sh; do cp "$T_ROOT/bin/$f" "$MR/bin/$f"; done
for f in secret access.sh library-log.sh scope-roots.sh scope-repo-sources.sh library-fs.sh library-hub.sh; do [ -f "$T_ROOT/bin/$f" ] && ln -s "$T_ROOT/bin/$f" "$MR/bin/$f"; done
ln -s "$T_ROOT/contracts/roots.tsv" "$MR/bin/roots.tsv"
printf 'hub=o/n\nlogin=alice\nhome=%s\n' "$H" > "$MR/member.conf"
CO="$T_TMP/co"; SRV="$CO/acme"; mkdir -p "$SRV"; OUTF="$T_TMP/server.out"   # a connector's root-owned folder is <root>/<name>; the launcher takes the root from a seam only here
CANARY="canary$(openssl rand -hex 14)"; CANARY2="canary$(openssl rand -hex 14)"; VAL="$T_TMP/value"
# The server: records what it holds, never the value itself (the test compares it to the expected one).
cat > "$SRV/server.sh" <<'SERVER'
#!/bin/sh
{ if [ "${ACME_API_KEY:-}" = "$(cat @EXPECT@)" ]; then echo key-ok; else echo key-wrong-or-absent; fi; env | sed 's/=.*//' | sort | tr '\n' ' '; echo; pwd; echo "$HOME"; } > @OUT@
SERVER
sed -i.bak -e "s#@EXPECT@#$T_TMP/expect#" -e "s#@OUT@#$OUTF#" "$SRV/server.sh"; rm -f "$SRV/server.sh.bak"
chmod 555 "$SRV/server.sh"; chmod 555 "$SRV" "$CO"
mkdir -p "$T_TMP/cleantree"; printf x > "$T_TMP/cleantree/f"; chmod 444 "$T_TMP/cleantree/f"; chmod 555 "$T_TMP/cleantree"   # the trees the jail checks, in the suites: nothing writable
BWLOG="$T_TMP/bwrap.argv"   # a stand-in jail: it records its arguments, then starts what follows the first --; the real bwrap is proved in the sim (docs/how-to/member-install.md, Residual risk)
printf '#!/bin/sh\nprintf "%%s\\n" "$*" > "%s"\nwhile [ "$#" -gt 0 ] && [ "$1" != "--" ]; do shift; done\nshift\nexec "$@"\n' "$BWLOG" > "$T_TMP/bwrap.stub"; chmod 555 "$T_TMP/bwrap.stub"
printf '#!/bin/sh\nexit 1\n' > "$T_TMP/bwrap.fail"; chmod 555 "$T_TMP/bwrap.fail"; cp "$T_TMP/bwrap.stub" "$T_TMP/bwrap.rw"; chmod 755 "$T_TMP/bwrap.rw"
printf '#!/bin/sh\nexec sh "$@"\n' > "$T_TMP/interp.stub"; printf '#!/bin/sh\n[ "$1" = --no-install ] && shift\nexec sh "$@"\n' > "$T_TMP/bun.stub"
TRUST="$(CDPATH='' cd -P "$T_TMP" && pwd -P)"; SRVP="$(CDPATH='' cd -P "$SRV" && pwd -P)"; COP="$(CDPATH='' cd -P "$CO" && pwd -P)"
EXPECT="$T_TMP/expect"; export EXPECT OUT="$OUTF"
conn() { printf '%s' "$1" > "$MR/connectors.json"; }
GOOD="[{\"name\":\"acme\",\"ref\":\"acme-crm\",\"env\":\"ACME_API_KEY\",\"service\":\"Acme CRM\",\"command\":[\"$SRVP/server.sh\",\"--stdio\"]}]"
GOODC='[{"name":"acme","ref":"acme-crm","env":"ACME_API_KEY","service":"Acme CRM","command":["/opt/company-mcp/acme/server.sh","--stdio"]}]'
conn "$GOOD"
L="$MR/bin/member-mcp-launch.sh"; C="$MR/bin/member-connectors.sh"
launch() { rm -f "$OUTF"; LRC=0; LERR="$(HARBOR_MEMBER_LAUNCH_ROOT="$COP" HARBOR_MEMBER_LAUNCH_SYSDIRS="${SYSDIRS_T:-}" HARBOR_MEMBER_LAUNCH_BWRAP="${BWRAP_T-$T_TMP/bwrap.stub}" HARBOR_MEMBER_LAUNCH_TREES="${TREES_T-$T_TMP/cleantree}" HARBOR_MEMBER_LAUNCH_KEEP_ENV=KC_STUB HARBOR_MEMBER_LAUNCH_TRUST_UNDER="${TRUSTV-$TRUST}" sh "$L" "$@" 2>&1 >/dev/null </dev/null)" || LRC=$?; }
got() { [ -f "$OUTF" ] && head -n 1 "$OUTF" || echo not-started; }
putkey() { printf '%s\n' "$2" > "$VAL"; printf '%s' "$2" > "$EXPECT"; HARBOR_MEMBER_CONNECTOR_VALUE_FILE="$VAL" sh "$C" key "$1" 2>&1 || return $?; }

t_section "1 - the policy's connectors compose into managed-mcp.json, and a row that must not is refused"
printf '%s' "$GOODC" > "$T_TMP/good.json"
sh "$T_ROOT/bin/member-managed.sh" --mcp-servers "$T_TMP/good.json" --root /etc/claude-code/harbor > "$T_TMP/mcp.json" 2>/dev/null; t_eq "a good list composes" 0 "$?"
t_eq "each server starts from env -i with a pinned PATH, through the launcher, with its ref and its server" \
  "/usr/bin/env|-i|PATH=/usr/bin:/bin:/usr/sbin:/sbin|/bin/sh|/etc/claude-code/harbor/bin/member-mcp-launch.sh|acme-crm|--|/opt/company-mcp/acme/server.sh|--stdio" \
  "$(jq -r '.mcpServers.acme | ([.command] + .args) | join("|")' "$T_TMP/mcp.json")"
t_eq "no key and no \${VAR} is in the file" 0 "$(grep -c -e "$CANARY" -e '\${' "$T_TMP/mcp.json" || :)"
compose_rc() { printf '%s' "$2" > "$T_TMP/bad.json"; sh "$T_ROOT/bin/member-managed.sh" --mcp-servers "$T_TMP/bad.json" >/dev/null 2>&1; echo $?; }
t_eq "the hub token's name is refused (hub-*)" 2 "$(compose_rc x '[{"name":"a","ref":"hub-token","env":"A_KEY","service":"s","command":["/opt/company-mcp/a/s"]}]')"
t_eq "a variable that steers a program is refused" 2 "$(compose_rc x '[{"name":"a","ref":"acme","env":"PATH","service":"s","command":["/opt/company-mcp/a/s"]}]')"
t_eq "LD_PRELOAD is refused" 2 "$(compose_rc x '[{"name":"a","ref":"acme","env":"LD_PRELOAD","service":"s","command":["/opt/company-mcp/a/s"]}]')"
t_eq "an env name holding PROXY is refused" 2 "$(compose_rc x '[{"name":"a","ref":"acme","env":"ACME_PROXY_KEY","service":"s","command":["/opt/company-mcp/a/s"]}]')"
t_eq "a ref listed twice is refused" 2 "$(compose_rc x '[{"name":"a","ref":"acme","env":"A_KEY","service":"s","command":["/opt/company-mcp/a/s"]},{"name":"b","ref":"acme","env":"B_KEY","service":"s","command":["/opt/company-mcp/b/s"]}]')"
t_eq "an extra key in a row is refused" 2 "$(compose_rc x '[{"name":"a","ref":"acme","env":"A_KEY","service":"s","command":["/opt/company-mcp/a/s"],"shell":"1"}]')"
t_eq "CONTROL: the same row without the fault composes" 0 "$(compose_rc x '[{"name":"a","ref":"acme","env":"A_KEY","service":"s","command":["/opt/company-mcp/a/s"]}]')"
# The signed policy's own validator says the same.
P="$T_ROOT/tests/hub/fixtures/policy.json"
pol() { jq --argjson c "$1" '.connectors = $c' "$P" > "$T_TMP/p.json"; sh "$T_ROOT/bin/hub-format.sh" policy "$T_TMP/p.json" >/dev/null 2>&1; echo $?; }
t_eq "policy: a good connectors list passes the format" 0 "$(pol "$GOODC")"
t_eq "policy: a hub-* ref does not" 1 "$(pol '[{"name":"a","ref":"hub-token","env":"A_KEY","service":"s","command":["/opt/company-mcp/a/s"]}]')"
t_eq "policy: a ref listed twice does not" 1 "$(pol '[{"name":"a","ref":"acme","env":"A_KEY","service":"s","command":["/opt/company-mcp/a/s"]},{"name":"b","ref":"acme","env":"B_KEY","service":"s","command":["/opt/company-mcp/b/s"]}]')"

t_section "2 - the person stores a key: from the policy's own words, hidden, never argv, never the agent"
t_exit "a ref the policy does not list is refused" 1 sh -c "HARBOR_MEMBER_CONNECTOR_VALUE_FILE='$VAL' sh '$C' key other-ref </dev/null"
t_exit "the hub token's name is refused" 1 sh -c "HARBOR_MEMBER_CONNECTOR_VALUE_FILE='$VAL' sh '$C' key hub-token </dev/null"
t_exit "no terminal and no seam: nothing is asked, nothing stored" 1 sh -c "sh '$C' key acme-crm </dev/null"
printf '%s\n' "$CANARY" > "$VAL"
t_exit "inside a Claude Code session (CLAUDECODE) it refuses, even with a value ready" 1 sh -c "CLAUDECODE=1 HARBOR_MEMBER_CONNECTOR_VALUE_FILE='$VAL' sh '$C' key acme-crm"
t_exit "so does the managed settings' env (HARBOR_MEMBER_ROLE)" 1 sh -c "HARBOR_MEMBER_ROLE=member HARBOR_MEMBER_CONNECTOR_VALUE_FILE='$VAL' sh '$C' key acme-crm"
t_exit "the service words are the policy's: an argument cannot add or change them" 2 sh -c "HARBOR_MEMBER_CONNECTOR_VALUE_FILE='$VAL' sh '$C' key acme-crm --service 'x'"
printf 'abc\n' > "$VAL"
t_exit "a value too short to be a key is refused" 1 sh -c "HARBOR_MEMBER_CONNECTOR_VALUE_FILE='$VAL' sh '$C' key acme-crm"
t_eq "nothing was stored by any refusal" 0 "$(ls "$KC_STUB/items" | grep -c 'secret.acme-crm' || :)"
conn "$(printf '%s' "$GOOD" | jq -c '.[0].ref = "hub-token"')"
t_exit "even a tampered connectors.json that lists hub-token does not let the person command store it" 1 sh -c "HARBOR_MEMBER_CONNECTOR_VALUE_FILE='$VAL' sh '$C' key hub-token"
t_has "...it says the name is the company's" "$(HARBOR_MEMBER_CONNECTOR_VALUE_FILE="$VAL" sh "$C" key hub-token 2>&1)" 'keeps for itself'
t_exit "and a ref the list does not hold is refused even with a value ready" 1 sh -c "HARBOR_MEMBER_CONNECTOR_VALUE_FILE='$VAL' sh '$C' key stranger-ref"
conn "$GOOD"
putkey acme-crm "$CANARY" >/dev/null; t_eq "the person stores it" 0 "$?"
t_eq "the register names the ref, and the store holds a passphrase item" 1 "$(ls "$KC_STUB/items" | grep -c 'secret.acme-crm')"
t_eq "the canary is in no register, store item, blob or home file" 0 "$(grep -rl -- "$CANARY" "$PV" "$KC_STUB" "$H" "$MR" 2>/dev/null | wc -l | tr -d ' ')"
t_eq "the store tool's argv log never carried it" 0 "$(grep -c -- "$CANARY" "$KC_STUB/argv.log" || :)"
t_eq "list says stored, by name only" "acme	acme-crm	stored	Acme CRM" "$(sh "$C" list)"
putkey acme-crm "$CANARY2" >/dev/null; t_eq "storing again replaces it through the same checks" 0 "$?"
printf 'xxxxxxxxxx\n' > "$VAL"
t_exit "a second store with a bad ref still runs every check (v1's injection)" 1 sh -c "HARBOR_MEMBER_CONNECTOR_VALUE_FILE='$VAL' sh '$C' key 'acme-crm;touch $T_TMP/pwned'"
t_eq "...and nothing ran" no "$([ -e "$T_TMP/pwned" ] && echo yes || echo no)"
t_exit "a ref revoked in the register is not stored again" 1 sh -c "sh '$T_ROOT/bin/access.sh' revoke acme-crm >/dev/null 2>&1; HARBOR_MEMBER_CONNECTOR_VALUE_FILE='$VAL' sh '$C' key acme-crm"
# put it back for the launcher sections: a fresh register entry
sh "$C" list >/dev/null 2>&1
rm -rf "$KC_STUB/items"/* "$PV/access/register.md"; sh "$T_ROOT/bin/scope.sh" install --private-only >/dev/null 2>&1
putkey acme-crm "$CANARY" >/dev/null; t_eq "restored for the next section" 0 "$?"

t_section "3 - the launcher hands the key to exactly the server the policy names, and to nothing else"
launch acme-crm -- "$SRVP/server.sh" --stdio
t_eq "the server started and held the key (its variable equals the stored value)" key-ok "$(got)"
t_eq "the launcher's own output never carried the key" 0 "$(printf '%s' "$LERR" | grep -c -- "$CANARY" || :)"
t_eq "the server's environment is only the variable and a few plain names" "key-ok" "$(got)"
t_eq "...and its names are only PATH, HOME, USER, LANG-type names and the key's" "ACME_API_KEY HOME PATH USER XDG_CACHE_HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME " "$(sed -n 2p "$OUTF" | tr ' ' '\n' | grep -v -e '^$' -e '^PWD$' -e '^_$' -e '^SHLVL$' -e "^TMPDIR$" -e "^KC_STUB$" -e "^LANG$" -e '^LC_' -e '^OLDPWD$' | sort | tr '\n' ' ')"
t_eq "...running in /" / "$(sed -n 3p "$OUTF")"
t_eq "...with HOME / (root-owned, so no ~/.bunfig.toml, ~/.npmrc or ~/.config of the member's is read), not the member's home" / "$(sed -n 4p "$OUTF")"
# an inherited name does not reach the server
EVIL=evil BASH_ENV=/nope LD_PRELOAD=/nope launch acme-crm -- "$SRVP/server.sh" --stdio
t_eq "an inherited EVIL, BASH_ENV, LD_PRELOAD are not in the server's environment" 0 "$(sed -n 2p "$OUTF" | tr ' ' '\n' | grep -c -e '^EVIL$' -e '^BASH_ENV$' -e '^LD_PRELOAD$' || :)"
launch acme-crm -- "$SRVP/server.sh" --other
t_eq "another argument to the same server is refused" 1 "$LRC"; t_eq "...and the server never started" not-started "$(got)"
launch acme-crm -- "$SRVP/server.sh"
t_eq "the server with an argument fewer is refused" not-started "$(got)"
cp "$SRV/server.sh" "$T_TMP/other.sh" 2>/dev/null; chmod 555 "$T_TMP/other.sh"
launch acme-crm -- "$T_TMP/other.sh" --stdio; t_eq "another program with the same ref is refused" not-started "$(got)"
launch other-crm -- "$SRVP/server.sh" --stdio; t_eq "a ref the policy does not pair with this server is refused" not-started "$(got)"
launch hub-token -- "$SRVP/server.sh" --stdio; t_eq "the hub token's ref is refused" not-started "$(got)"
t_has "...by name" "$LERR" "keeps for itself"
conn "$(printf '%s' "$GOOD" | jq -c '.[0].ref = "hub-token"')"
launch hub-token -- "$SRVP/server.sh" --stdio; t_eq "even a connectors.json that named it (a tampered one) is refused" not-started "$(got)"
conn "$GOOD"
launch 'acme-crm;id' -- "$SRVP/server.sh" --stdio; t_eq "a ref with a shell character is refused" not-started "$(got)"
launch acme-crm "$SRVP/server.sh" --stdio; t_eq "no -- is a refusal" not-started "$(got)"
mv "$MR/connectors.json" "$MR/connectors.off"; launch acme-crm -- "$SRVP/server.sh" --stdio; t_eq "no connectors.json means no connector" not-started "$(got)"; mv "$MR/connectors.off" "$MR/connectors.json"
sh "$T_ROOT/bin/access.sh" has acme-crm >/dev/null 2>&1; _rf="$PV/access/register.md"; cp "$_rf" "$T_TMP/reg.bak"; : > "$_rf"
launch acme-crm -- "$SRVP/server.sh" --stdio; t_eq "a ref the access register does not name gets no key (the store's own gate)" not-started "$(got)"; cp "$T_TMP/reg.bak" "$_rf"
launch acme-crm -- "$SRVP/server.sh" --stdio; t_eq "CONTROL: with the register back the same call starts the server" key-ok "$(got)"

t_section "4 - the agent's ways to the key"
# 4a a server the agent can rewrite: the key would go to whatever it wrote
W="$T_TMP/wsrv"; mkdir -p "$W"; cp "$SRV/server.sh" "$W/server.sh"; chmod 755 "$W/server.sh"
conn "$(printf '%s' "$GOOD" | jq -c --arg p "$W/server.sh" '.[0].command[0] = $p')"
launch acme-crm -- "$W/server.sh" --stdio; t_eq "a server in a folder the agent can write is refused" not-started "$(got)"
WP="$(CDPATH='' cd -P "$W" && pwd -P)"; chmod 555 "$W/server.sh"
conn "$(printf '%s' "$GOOD" | jq -c --arg p "$WP/server.sh" '.[0].command[0] = $p')"
launch acme-crm -- "$WP/server.sh" --stdio; t_eq "a read-only server file in a writable folder is refused too (the folder lets it be swapped)" not-started "$(got)"
ln -s "$WP/server.sh" "$SRV/link.sh" 2>/dev/null || { chmod 755 "$SRV"; ln -s "$WP/server.sh" "$SRV/link.sh"; chmod 555 "$SRV"; }
conn "$(printf '%s' "$GOOD" | jq -c --arg p "$SRVP/link.sh" '.[0].command[0] = $p')"
launch acme-crm -- "$SRVP/link.sh" --stdio; t_eq "a link in a fixed folder to a writable server is refused (links are followed)" not-started "$(got)"
conn "$GOOD"
# 4f every way to start something other than the connector's own server, judged at all three layers: the composer, the signed policy's format and the launcher.
# @D@ is the connector's root-owned folder, @X@ a root-owned system folder. A launcher row is a real file, so a refusal is for the rule named and not for a missing file.
chmod 755 "$SRV" "$CO"; SYS="$T_TMP/sys"; mkdir -p "$SYS" "$SRV/src" "$SRV/bin" "$CO/other"
for _i in node python3 setsid stdbuf taskset flock uvx npx bunx sh env nohup; do cp "$T_TMP/interp.stub" "$SYS/$_i"; done
cp "$T_TMP/bun.stub" "$SYS/bun"; cp "$SRV/server.sh" "$SYS/other.js"; cp "$SRV/server.sh" "$CO/other/server.sh"
for _i in node sh bunx; do cp "$T_TMP/interp.stub" "$SRV/bin/$_i"; done; cp "$T_TMP/bun.stub" "$SRV/bin/bun"; cp "$T_TMP/interp.stub" "$SYS/deno"
for _i in i.ts s.js s.py; do cp "$SRV/server.sh" "$SRV/src/$_i"; done
chmod 555 "$SYS"/* "$SRV/src/"* "$SRV/bin/"* "$SRV/bin" "$SRV/src" "$CO/other/server.sh" "$CO/other" "$SYS" "$SRV" "$CO"; SYSP="$(CDPATH='' cd -P "$SYS" && pwd -P)"
# where an interpreter may be written (the launcher's /usr/bin, /usr/local/bin and /bin stand in as folders of this run), a member's folder with links into it, and an admin venv in the folder
SYS2="$TRUST/sys2"; SYS3="$TRUST/sys3"; mkdir -p "$SYS2" "$SYS3/bin"; SYSDIRS_T="$SYSP $SYS2 $SYS3/bin"
cp "$T_TMP/interp.stub" "$SYS2/python3"; printf 'home = /usr/bin\n' > "$SYS2/pyvenv.cfg"; cp "$T_TMP/interp.stub" "$SYS3/bin/python3"; printf 'home = /usr/bin\n' > "$SYS3/pyvenv.cfg"
chmod 555 "$SYS2/python3" "$SYS2/pyvenv.cfg" "$SYS3/bin/python3" "$SYS3/pyvenv.cfg" "$SYS3/bin" "$SYS3" "$SYS2"
mkdir -p "$W/venv/bin"; ln -s "$SYSP/python3" "$W/venv/bin/python3"; printf 'home = /usr/bin\n' > "$W/venv/pyvenv.cfg"; ln -s "$SYSP/node" "$W/node"; ln -s "$SYSP/node" "$W/hop2"; ln -s "$SYSP/bun" "$W/bun"; mkdir -p "$W/bin"; ln -s "$SYSP/python3" "$W/bin/python3"
chmod 755 "$SRV" "$SRV/bin"; mkdir -p "$SRV/venv/bin"; cp "$T_TMP/interp.stub" "$SRV/venv/bin/python3"; printf 'home = %s\n' "$SYSP" > "$SRV/venv/pyvenv.cfg"
mkdir -p "$SRV/chain" "$SRV/ok"; ln -s "$W/hop2" "$SRV/chain/node"; ln -s "$SYSP/node" "$SRV/ok/node"
ln -s "$SRVP/src/s.js" "$W/hopE"; ln -s "$W/hopE" "$SRV/chain/entry.js"   # an entry file whose written chain has a writable hop, though it resolves inside the folder
chmod 755 "$SYS"; mkdir -p "$SYS/lk"; cp "$T_TMP/interp.stub" "$SYS/lk/node"; chmod 555 "$SYS/lk/node" "$SYS/lk" "$SYS"   # a root-owned folder that is not a system one
chmod 555 "$SRV/venv/bin/python3" "$SRV/venv/pyvenv.cfg" "$SRV/venv/bin" "$SRV/venv" "$SRV/bin" "$SRV/chain" "$SRV/ok" "$SRV"
c3() { # <ok|no> <label> <command json with @D@ and @X@>
  _w="$1"; _l="$2"; _t="$3"
  _cj="$(printf '%s' "$_t" | sed -e 's#@D@#/opt/company-mcp/acme#g' -e 's#@O@#/opt/company-mcp/other#g' -e 's#@V@#/home/alice/port#g' -e 's#@R@#/opt/tools#g' -e 's#@X@#/usr/bin#g')"
  _row="[{\"name\":\"acme\",\"ref\":\"acme-crm\",\"env\":\"ACME_API_KEY\",\"service\":\"s\",\"command\":$_cj}]"
  _lj="$(printf '%s' "$_t" | sed -e "s#@D@#$SRVP#g" -e "s#@O@#$COP/other#g" -e "s#@V@#$W#g" -e "s#@R@#$SYSP/lk#g" -e "s#@X@#$SYSP#g")"
  conn "[{\"name\":\"acme\",\"ref\":\"acme-crm\",\"env\":\"ACME_API_KEY\",\"service\":\"s\",\"command\":$_lj}]"
  eval "set -- $(printf '%s' "$_lj" | jq -r '.[] | @sh' | tr '\n' ' ')"
  launch acme-crm -- "$@"
  if [ "$_w" = ok ]; then
    t_eq "$_l: the composer takes it" 0 "$(compose_rc x "$_row")"; t_eq "$_l: the policy format takes it" 0 "$(pol "$_row")"; t_eq "$_l: the launcher starts it" key-ok "$(got)"
  else
    t_eq "$_l: the composer refuses it" 2 "$(compose_rc x "$_row")"; t_eq "$_l: the policy format refuses it" 1 "$(pol "$_row")"
    t_eq "$_l: the launcher refuses it and the server never starts" "1 not-started" "$LRC $(got)"
    t_eq "$_l: ...by the connector rule, not by a missing pair" 0 "$(printf '%s' "$LERR" | grep -c 'no connector of this laptop' || :)"
  fi
}
c3 ok "CONTROL: a server file in the folder" '["@D@/server.sh","--stdio"]'
c3 ok "CONTROL: bun --no-install and an entry file in the folder" '["@X@/bun","--no-install","@D@/src/i.ts"]'
c3 ok "CONTROL: node and an entry file in the folder" '["@X@/node","@D@/src/s.js","--stdio"]'
c3 ok "CONTROL: python3 and an entry file in the folder" '["@X@/python3","@D@/src/s.py","--stdio"]'
c3 no "env npx -y <package>" '["@X@/env","npx","-y","@evil/pkg"]'
c3 no "env as a wrapper of the folder's own server" '["@X@/env","@D@/server.sh"]'
c3 no "setsid" '["@X@/setsid","@D@/server.sh"]'
c3 no "stdbuf" '["@X@/stdbuf","-o0","@D@/server.sh"]'
c3 no "taskset" '["@X@/taskset","1","@D@/server.sh"]'
c3 no "flock" '["@X@/flock","-n","/tmp/l","@D@/server.sh"]'
c3 no "nohup" '["@X@/nohup","@D@/server.sh"]'
c3 no "a shell" '["@X@/sh","@D@/server.sh"]'
c3 no "uvx" '["@X@/uvx","mcp-x"]'
c3 no "npx" '["@X@/npx","-y","x"]'
c3 no "bunx" '["@X@/bunx","pkg"]'
c3 no "a relative npx" '["npx","-y","x"]'
c3 no "a relative server" '["server.sh"]'
c3 no "python3 -m uv tool run" '["@X@/python3","-m","uv","tool","run","mcp-x"]'
c3 no "node -e" '["@X@/node","-e","1"]'
c3 no "node with an entry file and --eval=" '["@X@/node","@D@/src/s.js","--eval=1"]'
c3 no "node with -r an outside file" '["@X@/node","@D@/src/s.js","-r","@X@/other.js"]'
c3 no "node --require=" '["@X@/node","--require=@X@/other.js","@D@/src/s.js"]'
c3 no "node --import" '["@X@/node","--import","@X@/other.js","@D@/src/s.js"]'
c3 no "bun --preload" '["@X@/bun","--no-install","--preload","@D@/src/i.ts","@D@/src/i.ts"]'
c3 no "bun --print" '["@X@/bun","--no-install","--print","1","@D@/src/i.ts"]'
c3 no "python3 -c" '["@X@/python3","@D@/src/s.py","-c","1"]'
c3 no "python3 -m after the entry file" '["@X@/python3","@D@/src/s.py","-m","x"]'
c3 no "a flag on the folder's own server" '["@D@/server.sh","-e","1"]'
c3 ok "CONTROL: plain tokens and --name=value flags after the server" '["@D@/server.sh","--stdio","zzplain","--mode=fast"]'
c3 no "node in the folder and a relative entry (the third audit: cwd is / and the word becomes a file the agent can write)" '["@D@/bin/node","home/alice/port/evil.js"]'
c3 no "node in the folder and ./ entry" '["@D@/bin/node","./home/alice/port/evil.js"]'
c3 no "a plain relative path after the server" '["@D@/server.sh","home/alice/port/evil.js"]'
c3 no "a dotted relative word" '["@D@/server.sh",".hidden"]'
c3 no "a ../ word" '["@D@/server.sh","../x"]'
c3 no "a single-dash flag" '["@D@/server.sh","-x"]'
c3 no "a flag whose value is an absolute path" '["@D@/server.sh","--config=/etc/hosts"]'
c3 no "a flag whose value is a ./ path" '["@D@/server.sh","--config=./x"]'
c3 no "a flag whose value starts with a dot" '["@D@/server.sh","--config=.x"]'
c3 no "a flag name with a slash" '["@D@/server.sh","--a/b"]'
c3 no "bun --cwd= after the entry" '["@X@/bun","--no-install","@D@/src/i.ts","--cwd=/home/alice"]'
c3 no "bun in the folder without --no-install (form A skips nothing)" '["@D@/bin/bun","@D@/src/i.ts"]'
c3 no "bun in the folder: x <package>" '["@D@/bin/bun","x","pkg"]'
c3 no "bun in the folder: run <package>" '["@D@/bin/bun","run","pkg"]'
c3 no "bun in the folder: --no-install then x <package>" '["@D@/bin/bun","--no-install","x","pkg"]'
c3 no "bun in the folder: add" '["@D@/bin/bun","--no-install","@D@/src/i.ts","add"]'
c3 no "bun in the folder, entry after a flag" '["@D@/bin/bun","--no-install","--smol","@D@/src/i.ts"]'
c3 ok "CONTROL: bun in the folder with --no-install and an entry file" '["@D@/bin/bun","--no-install","@D@/src/i.ts"]'
c3 ok "CONTROL: node in the folder and an entry file" '["@D@/bin/node","@D@/src/s.js"]'
c3 no "node in the folder and a relative entry beside it" '["@D@/bin/node","src/s.js"]'
c3 no "a shell in the folder" '["@D@/bin/sh","@D@/server.sh"]'
c3 no "bunx in the folder" '["@D@/bin/bunx","pkg"]'
c3 no "deno" '["@X@/deno","@D@/src/s.js"]'
c3 no "python3 through a link in the member's venv (the fourth audit: pyvenv.cfg and an agent .pth file)" '["@V@/venv/bin/python3","@D@/src/s.py"]'
c3 no "node through a link in the member's folder (a swap race)" '["@V@/node","@D@/src/s.js"]'
c3 no "bun through a link in the member's folder" '["@V@/bun","--no-install","@D@/src/i.ts"]'
c3 no "node in a root-owned folder that is not a system folder or the connector's" '["@R@/node","@D@/src/s.js"]'
c3 no "an interpreter written in a folder that is not a system one" '["@V@/bin/python3","@D@/src/s.py"]'
c3 ok "CONTROL: an admin venv inside the connector's folder (root-owned, with its pyvenv.cfg)" '["@D@/venv/bin/python3","@D@/src/s.py"]'
c3 no "bun x <package>" '["@X@/bun","x","pkg"]'
c3 no "bun run <package>" '["@X@/bun","run","pkg"]'
c3 no "bun -e" '["@X@/bun","-e","1"]'
c3 no "bun without --no-install" '["@X@/bun","@D@/src/i.ts"]'
c3 no "bun --no-install, an entry file and a later absolute path outside the folder" '["@X@/bun","--no-install","@D@/src/i.ts","@X@/other.js"]'
c3 no "bun run <an entry file> without --no-install" '["@X@/bun","run","@D@/src/i.ts"]'
c3 no "another connector's folder, no .." '["@O@/server.sh"]'
c3 no "node and an entry file in another connector's folder" '["@X@/node","@O@/server.sh"]'
c3 no "bun --no-install and no entry file" '["@X@/bun","--no-install"]'
c3 no "bun alone" '["@X@/bun"]'
c3 no "node with no entry file" '["@X@/node"]'
c3 no "python3 with no entry file" '["@X@/python3"]'
c3 no "node and an entry file outside the folder" '["@X@/node","@X@/other.js"]'
c3 no "bun --no-install and an entry file outside the folder" '["@X@/bun","--no-install","@X@/other.js"]'
c3 no "a server file outside the folder" '["@X@/other.js"]'
c3 no "the folder's server and an extra absolute path outside it" '["@D@/server.sh","--stdio","@X@/other.js"]'
c3 no "an absolute path outside the folder as a later word of node" '["@X@/node","@D@/src/s.js","@X@/other.js"]'
c3 no "a .. segment leading to another connector's folder" '["@D@/../other/server.sh"]'
c3 no "an expansion \${HOME}" '["@D@/server.sh","${HOME}"]'
# 4h the launcher alone: what only the file system shows
ln -s "$SYSP/other.js" "$SRV/leaving.sh" 2>/dev/null || { chmod 755 "$SRV"; ln -s "$SYSP/other.js" "$SRV/leaving.sh"; chmod 555 "$SRV"; }
conn "$(printf '%s' "$GOOD" | jq -c --arg p "$SRVP/leaving.sh" '.[0].command = [$p]')"
launch acme-crm -- "$SRVP/leaving.sh"; t_eq "a link inside the folder that leads out of it is refused (links are followed)" "1 not-started" "$LRC $(got)"
ln -s "$SYSP/env" "$SRV/runner-link.sh" 2>/dev/null || { chmod 755 "$SRV"; ln -s "$SYSP/env" "$SRV/runner-link.sh"; chmod 555 "$SRV"; }
conn "$(printf '%s' "$GOOD" | jq -c --arg p "$SRVP/runner-link.sh" '.[0].command = [$p, "x"]')"
launch acme-crm -- "$SRVP/runner-link.sh" x; t_eq "a link in the folder named like a server that leads to env is refused" "1 not-started" "$LRC $(got)"
mkdir -p "$SYS/lk" 2>/dev/null || { chmod 755 "$SYS"; mkdir -p "$SYS/lk"; chmod 555 "$SYS"; }
ln -s "$SYSP/env" "$SYS/lk/bun" 2>/dev/null || { chmod 755 "$SYS/lk"; ln -s "$SYSP/env" "$SYS/lk/bun"; chmod 555 "$SYS/lk"; }
conn "$(printf '%s' "$GOOD" | jq -c --arg b "$SYSP/lk/bun" --arg e "$SRVP/src/i.ts" '.[0].command = [$b, "--no-install", $e]')"
launch acme-crm -- "$SYSP/lk/bun" --no-install "$SRVP/src/i.ts"; t_eq "a link NAMED bun that leads to env is refused (the resolved name counts)" "1 not-started" "$LRC $(got)"
# an interpreter the member can swap, with an entry file that is the root's
mkdir -p "$W/sys"; cp "$T_TMP/bun.stub" "$W/sys/bun"; chmod 555 "$W/sys/bun"
conn "$(printf '%s' "$GOOD" | jq -c --arg b "$W/sys/bun" --arg e "$SRVP/src/i.ts" '.[0].command = [$b, "--no-install", $e]')"
launch acme-crm -- "$W/sys/bun" --no-install "$SRVP/src/i.ts"; t_eq "a bun in a folder the member can write is refused, though the entry file is the root's" "1 not-started" "$LRC $(got)"
t_has "...saying the interpreter must be the root's own" "$LERR" "root's own"
# a file the member can write, in a folder that is fixed
# a file the member can write, in a folder that is the root's: made for these cases only (the folder is scanned for anything writable at every start)
chmod 755 "$SRV" "$SRV/src"; cp "$SRV/server.sh" "$SRV/w.sh"; cp "$SRV/server.sh" "$SRV/src/w.js"; chmod 755 "$SRV/w.sh" "$SRV/src/w.js"; chmod 555 "$SRV" "$SRV/src"
conn "$(printf '%s' "$GOOD" | jq -c --arg p "$SRVP/w.sh" '.[0].command = [$p]')"
launch acme-crm -- "$SRVP/w.sh"; t_eq "a server file the member can write is refused, though its folder is the root's" "1 not-started" "$LRC $(got)"
conn "$(printf '%s' "$GOOD" | jq -c --arg b "$SYSP/node" --arg e "$SRVP/src/w.js" '.[0].command = [$b, $e]')"
launch acme-crm -- "$SYSP/node" "$SRVP/src/w.js"; t_eq "an entry file the member can write is refused, though its folder is the root's" "1 not-started" "$LRC $(got)"
chmod 755 "$SRV" "$SRV/src"; rm -f "$SRV/w.sh" "$SRV/src/w.js"; chmod 555 "$SRV" "$SRV/src"
conn "$(printf '%s' "$GOOD" | jq -c --arg b "$SYSP/node" --arg e "$SYSP/other.js" '.[0].command = [$b, $e]')"
launch acme-crm -- "$SYSP/node" "$SYSP/other.js"; t_has "an entry file outside the folder: refused by the entry rule, in its words" "$LERR" "the entry file"
# a plain token or a flag value that names something at / (the launcher runs in /, so the word would resolve there)
for _t in '"tmp"' '"--mode=tmp"' '"etc"' '"--mode=etc"'; do
  conn "$(printf '%s' "$GOOD" | jq -c --arg p "$SRVP/server.sh" --argjson t "$_t" '.[0].command = [$p, $t]')"
  launch acme-crm -- "$SRVP/server.sh" "$(printf '%s' "$_t" | jq -r .)"; t_eq "the word $_t names something that exists at /: refused" "1 not-started" "$LRC $(got)"
  t_has "...saying it exists" "$LERR" "which exists"
done
# a link named like a server that leads to bun: the resolved name counts, so bun's own rules apply
ln -s "$SYSP/bun" "$SRV/server-link" 2>/dev/null || { chmod 755 "$SRV"; ln -s "$SYSP/bun" "$SRV/server-link"; chmod 555 "$SRV"; }
conn "$(printf '%s' "$GOOD" | jq -c --arg p "$SRVP/server-link" '.[0].command = [$p, "x", "pkg"]')"
launch acme-crm -- "$SRVP/server-link" x pkg; t_eq "a link in the folder that leads to bun gets bun's rules (x pkg refused)" "1 not-started" "$LRC $(got)"
# a link chain: every hop is judged as written, so one hop in a writable folder is refused though the target is the root's; a chain of fixed hops is fine
conn "$(printf '%s' "$GOOD" | jq -c --arg b "$SRVP/chain/node" --arg e "$SRVP/src/s.js" '.[0].command = [$b, $e]')"
launch acme-crm -- "$SRVP/chain/node" "$SRVP/src/s.js"; t_eq "a link chain with one writable hop is refused, though its target is node" "1 not-started" "$LRC $(got)"
t_has "...saying the link or its folder is writable" "$LERR" "a link on the way"
conn "$(printf '%s' "$GOOD" | jq -c --arg b "$SRVP/ok/node" --arg e "$SRVP/src/s.js" '.[0].command = [$b, $e]')"
launch acme-crm -- "$SRVP/ok/node" "$SRVP/src/s.js"; t_eq "CONTROL: a link in the root's folder to the root's node starts" key-ok "$(got)"
conn "$(printf '%s' "$GOOD" | jq -c --arg b "$SYSP/node" --arg e "$SRVP/chain/entry.js" '.[0].command = [$b, $e]')"
launch acme-crm -- "$SYSP/node" "$SRVP/chain/entry.js"; t_eq "an entry file that resolves inside the folder through a writable hop is refused" "1 not-started" "$LRC $(got)"
# a pyvenv.cfg beside a python in a system folder, or one folder up: refused; the admin's own venv inside the folder was the control above
for _py in "$SYS2/python3" "$SYS3/bin/python3"; do
  conn "$(printf '%s' "$GOOD" | jq -c --arg b "$_py" --arg e "$SRVP/src/s.py" '.[0].command = [$b, $e]')"
  launch acme-crm -- "$_py" "$SRVP/src/s.py"; t_eq "a pyvenv.cfg beside $_py (or one folder up) is refused" "1 not-started" "$LRC $(got)"
  t_has "...naming it" "$LERR" "pyvenv.cfg"
done
# an admin venv whose base python (home =) is the member's own, or a root's folder that is not a system one: its stdlib would come from there
for _hm in "$W/pyhome/bin" "$SYSP/lk" ""; do
  chmod 755 "$SRV/venv"; rm -f "$SRV/venv/pyvenv.cfg"; printf 'home = %s\n' "$_hm" > "$SRV/venv/pyvenv.cfg"; chmod 444 "$SRV/venv/pyvenv.cfg"; chmod 555 "$SRV/venv"
  conn "$(printf '%s' "$GOOD" | jq -c --arg b "$SRVP/venv/bin/python3" --arg e "$SRVP/src/s.py" '.[0].command = [$b, $e]')"
  launch acme-crm -- "$SRVP/venv/bin/python3" "$SRVP/src/s.py"; t_eq "an admin venv with home = '$_hm' is refused" "1 not-started" "$LRC $(got)"
  t_has "...naming home" "$LERR" "home"
done
# home = a folder that IS in the system list but the member can write (a link or folder they own): refused at every hop, though the name matches
mkdir -p "$W/pyhome/bin"; SYSDIRS_T="$SYSP $SYS2 $SYS3/bin $W/pyhome/bin"
chmod 755 "$SRV/venv"; rm -f "$SRV/venv/pyvenv.cfg"; printf 'home = %s\n' "$W/pyhome/bin" > "$SRV/venv/pyvenv.cfg"; chmod 444 "$SRV/venv/pyvenv.cfg"; chmod 555 "$SRV/venv"
launch acme-crm -- "$SRVP/venv/bin/python3" "$SRVP/src/s.py"; t_eq "an admin venv whose home = names a writable folder is refused even when the name is in the list" "1 not-started" "$LRC $(got)"
t_has "...saying it is writable" "$LERR" "writable"
SYSDIRS_T="$SYSP $SYS2 $SYS3/bin"
chmod 755 "$SRV/venv"; rm -f "$SRV/venv/pyvenv.cfg"; printf 'home = %s\n' "$SYSP" > "$SRV/venv/pyvenv.cfg"; chmod 444 "$SRV/venv/pyvenv.cfg"; chmod 555 "$SRV/venv"
launch acme-crm -- "$SRVP/venv/bin/python3" "$SRVP/src/s.py"; t_eq "CONTROL: the admin venv with home in a system folder starts" key-ok "$(got)"
# the folder itself
chmod 755 "$SRV"; conn "$GOOD"
launch acme-crm -- "$SRVP/server.sh" --stdio; t_eq "a connector folder the member can write is refused, though every file in it is the root's" "1 not-started" "$LRC $(got)"
t_has "...saying so (the folder rule's own words)" "$LERR" "root-owned folder of their own"
chmod 555 "$SRV"; chmod 755 "$CO"
launch acme-crm -- "$SRVP/server.sh" --stdio; t_eq "a folder above the connector's that the member can write is refused" "1 not-started" "$LRC $(got)"
chmod 555 "$CO"
chmod 755 "$CO"; mv "$SRV" "$CO/acme.off"; chmod 555 "$CO"
launch acme-crm -- "$SRVP/server.sh" --stdio; t_eq "a missing connector folder is refused" "1 not-started" "$LRC $(got)"
chmod 755 "$CO"; mv "$CO/acme.off" "$SRV"; chmod 555 "$CO"
launch acme-crm -- "$SRVP/server.sh" --stdio; t_eq "CONTROL: with the folder back and fixed the server starts" key-ok "$(got)"
conn "$GOOD"
# 4b the launcher run by hand from the agent's shell
CLAUDECODE=1 launch acme-crm -- "$SRVP/server.sh" --stdio
t_eq "a hand run whose environment names Claude Code is refused" not-started "$(got)"
t_has "...and says why" "$LERR" "Claude Code"
# the layer that matters is the store: a sandboxed shell cannot read it. Modelled by taking the store from the caller, as sandbox.credentials does.
mv "$KC_STUB/items" "$KC_STUB/items.away"; mkdir "$KC_STUB/items"
launch acme-crm -- "$SRVP/server.sh" --stdio
t_eq "with the store unreadable (what the sandbox gives a hand run) no server starts and no key is handed over" not-started "$(got)"
rmdir "$KC_STUB/items"; mv "$KC_STUB/items.away" "$KC_STUB/items"
# 4c the agent adds or edits an MCP entry: its own file (a project .mcp.json, ~/.claude.json) is not an authority, because the launcher believes only <root>/connectors.json
mkdir -p "$PORT/proj"; printf '{"mcpServers":{"mine":{"command":"/bin/sh","args":["%s","acme-crm","--","/bin/sh","-c","echo x"]}}}\n' "$L" > "$PORT/proj/.mcp.json"
launch acme-crm -- /bin/sh -c 'echo x'; t_eq "a server the agent pairs with the ref in its own file is refused by the launcher" 1 "$LRC"
# 4d the hub token by ref
launch hub-token -- /usr/bin/env; t_eq "the hub token cannot be reached by ref through the launcher" not-started "$(got)"
t_exit "nor stored over through the person's command" 1 sh -c "HARBOR_MEMBER_CONNECTOR_VALUE_FILE='$VAL' sh '$C' key hub-token"
# 4e the key in the agent's reach after all of it
t_eq "after every attack the canary is in no file the agent can read (home, port, the test's output)" 0 "$(grep -rl -e "$CANARY" -e "$CANARY2" "$H" "$PORT" "$SRV" "$MR" "$OUTF" 2>/dev/null | wc -l | tr -d ' ')"

t_section "4i - the jail: the server runs in a view that holds nothing the member can write, and without a jail it does not run"
unset CLAUDECODE; conn "$GOOD"
launch acme-crm -- "$SRVP/server.sh" --stdio; t_eq "the server starts through the jail and holds the key" key-ok "$(got)"
_ja="$(cat "$BWLOG" 2>/dev/null)"
FRP="$(CDPATH='' cd -P "$SRV" && pwd -P)"
for _f in "--unshare-pid" "--die-with-parent" "--new-session" "--cap-drop ALL" "--proc /proc" "--dev /dev" "--tmpfs /tmp" "--ro-bind /usr /usr" "--ro-bind /etc /etc" "--ro-bind $FRP $SRVP" "--chdir /"; do
  t_has "the jail has $_f" "$_ja" "$_f"
done
t_eq "the network is shared (the server needs it)" 0 "$(printf '%s' "$_ja" | grep -c -e '--unshare-net' || :)"
t_eq "nothing is bound writable" 0 "$(printf '%s' "$_ja" | grep -c -e '--bind ' -e '--bind-try ' || :)"
# the view is an allowlist of the root's own trees: every bound source is one of them, so no /home, /root, /mnt, /var, /run/user, /dev/shm
_bad="$(printf '%s' "$_ja" | tr ' ' '\n' | awk '$0 == "--ro-bind" || $0 == "--ro-bind-try" { getline; print }' | grep -v -x -e /usr -e /etc -e /bin -e /sbin -e /lib -e /lib32 -e /lib64 -e /libx32 -e /run/systemd/resolve -e "$FRP" | tr '\n' ' ')"
t_eq "every source bound into the view is the root's: /usr, /etc, the /bin /sbin /lib* trees, the resolver folder, this connector's folder" "" "$_bad"
t_eq "...and no member-writable place is named at all" 0 "$(printf '%s' "$_ja" | sed -e "s#$FRP##g" -e "s#$SRVP##g" | grep -c -e '/home' -e '/root' -e '/mnt' -e '/Users' -e '/var' -e '/run/user' -e '/dev/shm' || :)"
BWRAP_T="$T_TMP/no-such-bwrap"; launch acme-crm -- "$SRVP/server.sh" --stdio; unset BWRAP_T
t_eq "no bwrap: the server does not start (fail closed)" "1 not-started" "$LRC $(got)"; t_has "...saying a jail is needed" "$LERR" "bwrap"
BWRAP_T="$T_TMP/bwrap.fail"; launch acme-crm -- "$SRVP/server.sh" --stdio; unset BWRAP_T
t_eq "a bwrap that fails to start the view: the server does not start (never run bare)" "1 not-started" "$LRC $(got)"
BWRAP_T="$T_TMP/bwrap.rw"; launch acme-crm -- "$SRVP/server.sh" --stdio; unset BWRAP_T
t_eq "a bwrap the member can write is refused: it would be theirs" "1 not-started" "$LRC $(got)"
TREES_T="$W"; launch acme-crm -- "$SRVP/server.sh" --stdio; unset TREES_T
t_eq "a tree the view would bind that the member can write is refused (/usr and /etc are checked at every start)" "1 not-started" "$LRC $(got)"
mkdir -p "$T_TMP/tree/sub"; chmod 755 "$T_TMP/tree/sub"; chmod 555 "$T_TMP/tree"
TREES_T="$T_TMP/tree"; launch acme-crm -- "$SRVP/server.sh" --stdio; unset TREES_T
t_eq "a writable folder UNDER a bound tree (an npm -g or Homebrew /usr/local handed to the user) is refused" "1 not-started" "$LRC $(got)"
t_has "...naming the path" "$LERR" "$T_TMP/tree/sub"
chmod 555 "$T_TMP/tree/sub"; TREES_T="$T_TMP/tree"; launch acme-crm -- "$SRVP/server.sh" --stdio; unset TREES_T
t_eq "CONTROL: the same tree with nothing writable under it starts the server" key-ok "$(got)"
chmod 755 "$SRV" "$SRV/src"; cp "$SRV/server.sh" "$SRV/src/w.js"; chmod 755 "$SRV/src/w.js"; chmod 555 "$SRV" "$SRV/src"
launch acme-crm -- "$SRVP/server.sh" --stdio; t_eq "...and a connector folder that holds a writable file (src/w.js here) is refused, though the server named is the root's" "1 not-started" "$LRC $(got)"
t_has "...naming it" "$LERR" "w.js"
chmod 755 "$SRV" "$SRV/src"; rm -f "$SRV/src/w.js"; chmod 555 "$SRV" "$SRV/src"
launch acme-crm -- "$SRVP/server.sh" --stdio; t_eq "CONTROL: with that file gone, the server starts" key-ok "$(got)"
launch acme-crm -- "$SRVP/server.sh" --stdio; t_eq "CONTROL: with the right stand-in the server starts again" key-ok "$(got)"

t_section "5 - the managed files protect the list, and the settings keep the store denied"
HARBOR_MEMBER_OS=Linux; export HARBOR_MEMBER_OS
sh "$T_ROOT/bin/member-managed.sh" --hub o/n --login alice > "$T_TMP/ms.json" 2>/dev/null
t_eq "the Edit tool is denied on managed-mcp.json" 1 "$(jq '[.permissions.deny[] | select(. == "Edit(//etc/claude-code/managed-mcp.json)")] | length' "$T_TMP/ms.json")"
t_eq "the sandbox denies writes to it" 1 "$(jq '[.sandbox.filesystem.denyWrite[] | select(. == "/etc/claude-code/managed-mcp.json")] | length' "$T_TMP/ms.json")"
t_eq "the sandbox still denies the agent the store folder" 1 "$(jq '[.sandbox.credentials.files[] | select(.path == "~/.local/share/secret" and .mode == "deny")] | length' "$T_TMP/ms.json")"
t_eq "MCP servers a person adds still cannot load (the allowlist is empty and managed-only)" '[] true' "$(jq -r '[.allowedMcpServers, .allowManagedMcpServersOnly] | map(tojson) | join(" ")' "$T_TMP/ms.json")"
sh "$T_ROOT/bin/member-managed.sh" --hub o/n --login alice --allow-claudeai-mcps > "$T_TMP/ms2.json" 2>/dev/null
t_eq "with connectors declared the install passes --allow-claudeai-mcps: allowAllClaudeAiMcps is true, so claude.ai connectors keep loading" true "$(jq '.allowAllClaudeAiMcps' "$T_TMP/ms2.json")"
t_eq "with none declared the key is absent: MCP is as it was" false "$(jq 'has("allowAllClaudeAiMcps")' "$T_TMP/ms.json")"
t_eq "the Read tool is denied /proc (a connector server environment is there)" 1 "$(jq '[.permissions.deny[] | select(. == "Read(//proc/**)")] | length' "$T_TMP/ms.json")"
t_eq "...and the dispatcher's own read-deny table carries it" 1 "$(grep -c '^read-deny	//proc/\*\*$' "$T_ROOT/contracts/member-guards.tsv")"
t_eq "the weaker nested sandbox is pinned off (it binds the real /proc instead of a fresh one)" false "$(jq '.sandbox.enableWeakerNestedSandbox' "$T_TMP/ms.json")"

t_section "6 - the context notes: keys-store-env-file, keys-store-key, keys-store-token and keys-store-password fire when the agent is about to write a secret-shaped value"
RR="$T_TMP/rroot"; rm -rf "$RR"; mkdir -p "$RR/bin"
cp "$T_ROOT/hooks/injection-rule/injection-rule.sh" "$T_ROOT/contracts/member-context-rules.tsv" "$RR/bin/"
for n in env-file key token password; do cp "$T_ROOT/contracts/member-rules/keys-store-$n.md" "$RR/bin/"; done
for n in external-content-is-data subagent-contract; do cp "$T_ROOT/contracts/member-rules/$n.md" "$RR/bin/"; done
note() { # <session> <tool_input json> -> the engine's output for a Write
  jq -cn --arg s "$1" --argjson i "$2" '{session_id:$s,hook_event_name:"PreToolUse",tool_name:"Write",tool_input:$i}' \
    | CLAUDE_PROJECT_DIR="$T_TMP" sh "$RR/bin/injection-rule.sh" --member-root "$RR" 2>/dev/null
}
t_has "writing a .env file: keys-store-env-file" "$(note e1 '{"file_path":"/p/.env","content":"x"}')" 'keys-store-env-file'
t_has "...and it points at the person's own terminal and the connector, never the chat" "$(note e2 '{"file_path":"/p/.env","content":"x"}')" 'member-connectors.sh key'
t_has "a _KEY= assignment: keys-store-key" "$(note e3 '{"file_path":"/p/a.py","content":"ACME_API_KEY=abc"}')" 'keys-store-key'
t_has "a TOKEN= assignment: keys-store-token" "$(note e4 '{"file_path":"/p/a.py","content":"ACME_TOKEN=abc"}')" 'keys-store-token'
t_has "a PASSWORD= assignment: keys-store-password" "$(note e5 '{"file_path":"/p/a.py","content":"DB_PASSWORD=abc"}')" 'keys-store-password'
t_eq "CONTROL: an ordinary file write draws no key note" 0 "$(note e6 '{"file_path":"/p/a.py","content":"print(1)"}' | grep -c 'keys-store')"
t_done
