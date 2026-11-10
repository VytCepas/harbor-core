#!/usr/bin/env sh
# harness-floor.test.sh (harbor#1278) — harness.test.sh's second half, on the same laptop (fixture.sh): the updater, the session install, a pack
# a flat root can't serve, the standalone guards, the Read and Grep tier path, the marker box, and a cut-short JSON deny. Needs a loopback port.
#   sh harness-floor.test.sh            every section, in order
#   sh harness-floor.test.sh s13 s14    those sections alone: each sets its own policy
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/member/e2e/fixture.sh"

e_scene

s10() {
t_section "10 - the updater runs from its template, and moves the data with the code"
# A copy of the laptop, so the seamed files above stay. The core repo is the real tree's rows at their real paths.
_c="$T_TMP/core"; _u="$T_TMP/upd/ClaudeCode"; mkdir -p "$_c/contracts" "${_u%/*}"; cp -R "$SYS" "$_u"
git -C "$_c" init -q -b main; git -C "$_c" config uploadpack.allowAnySHA1InWant true
# The composer and what it reads, whole: the updater composes the settings again with the commit's own member-managed.sh (N7).
cp -R "$T_ROOT/bin" "$T_ROOT/contracts" "$_c/"; mkdir -p "$_c/standards"; cp -R "$T_ROOT/standards/naming" "$_c/standards/"
sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^[[:space:]]*$/d' "$T_ROOT/contracts/member-files.txt" | while read -r _s _d; do
  mkdir -p "$_c/${_s%/*}"; cp "$T_ROOT/$_s" "$_c/$_s"
done
cp "$T_ROOT/contracts/member-files.txt" "$_c/contracts/"
_cg() { git -C "$_c" -c user.name=t -c user.email=t@t "$@"; }
printf 'admission.fixture-new-row\tvery-high\tfixed\tA row this pin brings\n' >> "$_c/contracts/risk-tiers.tsv"
printf '# fixture-row this pin brings\n' >> "$_c/contracts/member-guards.tsv"
printf 'outcome\tfixture-word\ta word this pin brings\n' >> "$_c/contracts/hub-vocabulary.tsv"
printf '# a floor file this pin changes\n' >> "$_c/bin/hub-tier.sh"
_cg add -A; _cg commit -qm 'the pinned core'
_pin="$(_cg rev-parse HEAD)"
# A policy naming the pin, signed, in the state the laptop holds. Serial above the last one so the session keeps it.
e_policy "$RULES | .core.commit = \"$_pin\" | .hosts = [\"pkg.e2e-fixture.example\"]"
e_session start
t_eq "CONTROL: the laptop took the pin" "$_pin" "$(jq -r .core.commit "$HS/policy.json")"
# What a template gives it: PATH alone. HOME is root's, not the member's, and the role, hub and state come from member.conf.
_rc=0; env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=/var/empty HARBOR_MEMBER_ROOT="$_u/harbor" HARBOR_MEMBER_CORE_SOURCE="file://$_c" \
  sh "$_u/harbor/bin/member-update.sh" > "$T_TMP/upd.out" 2>&1 || _rc=$?
t_eq "it runs with no role in the environment: $(grep -m1 FAIL "$T_TMP/upd.out" | cut -c1-120)" 0 "$_rc"
t_eq "the pin moved" "$_pin" "$(cat "$_u/harbor/core.commit" 2>/dev/null)"
_stale=''
sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^[[:space:]]*$/d' "$_c/contracts/member-files.txt" > "$T_TMP/urows"
while read -r _s _d; do cmp -s "$_c/$_s" "$_u/harbor/bin/${_d:-${_s##*/}}" || _stale="$_stale ${_d:-${_s##*/}}"; done < "$T_TMP/urows"
t_eq "every row of the list is the pin's bytes, the data with the code" '' "$_stale"
t_has "the tiers moved" "$(cat "$_u/harbor/bin/risk-tiers.tsv")" 'admission.fixture-new-row'
t_has "and the guard table" "$(cat "$_u/harbor/bin/member-guards.tsv")" 'fixture-row'
t_has "and the vocabulary" "$(cat "$_u/harbor/bin/hub-vocabulary.tsv")" 'fixture-word'
t_eq "the marker stayed" 0 "$(wc -c < "$_u/harbor/bin/harbor-member-mode" | tr -d ' ')"
t_exit "and the floor checks at its new pin" 0 env HARBOR_MEMBER_ROOT="$_u/harbor" sh "$_u/harbor/bin/member-integrity.sh" check
t_eq "the settings were composed again by the pin's composer: the hooks name this root" "/bin/sh '$_u/harbor/bin/member-dispatch.sh'" "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$_u/managed-settings.json" | sed -n "s/^.* \(\/bin\/sh '.*'\)$/\1/p")"
t_eq "and the policy's host reached the sandbox without IT" true "$(jq -r '.sandbox.network.allowedDomains | index("pkg.e2e-fixture.example") != null' "$_u/managed-settings.json")"
_rc=0; env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=/var/empty HARBOR_MEMBER_ROOT="$_u/harbor" sh "$_u/harbor/bin/member-update.sh" > /dev/null 2>&1 || _rc=$?
t_eq "a second run finds nothing to do" 0 "$_rc"
mv "$_u/harbor/member.conf" "$T_TMP/conf.off"; printf '%s\n' 0000000000000000000000000000000000000000 > "$_u/harbor/core.commit"
_rc=0; env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=/var/empty HARBOR_MEMBER_ROOT="$_u/harbor" sh "$_u/harbor/bin/member-update.sh" > "$T_TMP/upd.out" 2>&1 || _rc=$?
t_eq "no member.conf: refused, not guessed" 1 "$_rc"
t_has "named" "$(cat "$T_TMP/upd.out")" 'member.conf'

}

s11() {
t_section "11 - a session installs what is missing, and is never held by it"
e_policy "$RULES"
e_session start
_list="$MB/member-prereqs.txt"; cp "$_list" "$T_TMP/list.keep"; _tool="$T_TMP/tools/fixture-tool"; mkdir -p "${_tool%/*}"
printf '#!/bin/sh\ncase "$1" in install) if [ -e "%s/apt.fail" ]; then exit 1; fi; printf "#!/bin/sh\\n" > "%s"; chmod +x "%s" ;; esac\n' "$T_TMP" "$_tool" "$_tool" > "$T_BIN/apt-get"; chmod +x "$T_BIN/apt-get"
: > "$T_TMP/sudo.log"
e_session start
t_eq "nothing missing: the helper isn't called" '' "$(cat "$T_TMP/sudo.log")"
printf '%s fixture-tool fixture-tool\n' "$_tool" >> "$_list"; sh "$MB/member-integrity.sh" hash > "$MR/floor.pin"
e_session start
t_eq "something missing: exactly the helper, no argument" "-n /bin/sh $(cd "$MB" && pwd -P)/member-prereqs.sh" "$(cat "$T_TMP/sudo.log")"
t_exit "and the real helper installed it" 0 test -x "$_tool"
t_eq "with nothing said" '' "$E_OUT"
: > "$T_TMP/sudo.log"
e_session start
t_eq "the next session finds nothing to do" '' "$(cat "$T_TMP/sudo.log")"
rm -f "$_tool"
# macOS never has the list's Linux runtime, so a session there calls nothing and says nothing.
cp "$MB/member-session.sh" "$T_TMP/session.keep"; sed 's/^PREREQ_OS=.*/PREREQ_OS=Darwin/' "$T_TMP/session.keep" > "$MB/member-session.sh"
sh "$MB/member-integrity.sh" hash > "$MR/floor.pin"; : > "$T_TMP/sudo.log"
e_session start
t_eq "macOS: the helper isn't called" '' "$(cat "$T_TMP/sudo.log")"
t_eq "and nothing is said" '' "$E_OUT"
cp "$T_TMP/session.keep" "$MB/member-session.sh"; sh "$MB/member-integrity.sh" hash > "$MR/floor.pin"
: > "$T_TMP/apt.fail"
e_session start
t_eq "the install fails: the session goes on" 0 "$E_RC"
t_has "and the session note says so" "$(printf '%s' "$E_OUT" | jq -r .systemMessage)" 'could not be installed'
t_has "naming what is missing" "$(printf '%s' "$E_OUT" | jq -r .systemMessage)" "$_tool"
rm -f "$T_TMP/apt.fail"; : > "$T_TMP/sudo.refuse"
e_session start
t_has "no sudoers rule behaves the same" "$(printf '%s' "$E_OUT" | jq -r .systemMessage)" 'could not be installed'
t_eq "and the session still went on" 0 "$E_RC"
rm -f "$T_TMP/sudo.refuse"
# Root's helper can't be killed from the member's hook, so a hang is a wait that ends, never a held session.
cp "$MB/member-session.sh" "$T_TMP/session.keep"
sed 's/^PREREQ_WAIT=.*/PREREQ_WAIT=2/' "$T_TMP/session.keep" > "$MB/member-session.sh"
printf '#!/bin/sh\nsleep 30\n' > "$T_BIN/apt-get"; sh "$MB/member-integrity.sh" hash > "$MR/floor.pin"
_t0="$(date +%s)"; e_session start; _t1="$(date +%s)"
t_eq "a hung install doesn't hold the session" 1 "$([ $((_t1 - _t0)) -lt 30 ] && echo 1)"
t_has "and the note says it is still running" "$(printf '%s' "$E_OUT" | jq -r .systemMessage)" 'still'
cp "$T_TMP/session.keep" "$MB/member-session.sh"; cp "$T_TMP/list.keep" "$_list"; rm -f "$T_BIN/apt-get"; sh "$MB/member-integrity.sh" hash > "$MR/floor.pin"

t_section "11b - the home folder sends the agent to ~/port"
e_session start
t_eq "CONTROL: a project folder hears nothing" '' "$E_OUT"
mkdir -p "$HOME/port"; E_CWD="$HOME"
e_session start
E_CWD=''
t_has "a session opened in the home folder is told where to work" "$(printf '%s' "$E_OUT" | jq -r .hookSpecificOutput.additionalContext)" '~/port'
t_eq "the agent is told, and the person isn't bothered" null "$(printf '%s' "$E_OUT" | jq -r .systemMessage)"

t_section "11c - a git repo under ~/port that harbor does not govern is named by the managed hook (yard start rule, harbor#1278)"
# The user tier's context rule can't run here (allowManagedHooksOnly), so the finding is member-session.sh's own, from the same disk scan.
mkdir -p "$HOME/port/harbor-private" "$HOME/port/fresh" "$HOME/port/plain"; git -C "$HOME/port/fresh" init -q
printf 'id\tpath\tkind\tremote\n' > "$HOME/port/harbor-private/repos.tsv"
e_session start
t_has "a fresh git init is named for the agent, with the register command" "$(printf '%s' "$E_OUT" | jq -r .hookSpecificOutput.additionalContext)" 'fresh'
t_has "...and for the person" "$(printf '%s' "$E_OUT" | jq -r .systemMessage)" 'fresh'
t_hasnt "a folder with no .git is not named" "$E_OUT" 'plain'
printf 'fresh\tfresh\tworkload\t-\t-\t-\t-\t-\tyes\t-\t-\n' >> "$HOME/port/harbor-private/repos.tsv"
e_session start
t_eq "registered, it is named no more and the session says nothing" '' "$E_OUT"
printf 'not a registry\n' > "$HOME/port/harbor-private/repos.tsv"
e_session start
t_has "a registry the member broke does not mute it: the repo is still named" "$(printf '%s' "$E_OUT" | jq -r .systemMessage)" 'fresh'

}

s12() {
t_section "12 - a hub pack a flat root can't serve is refused by name"
# What composes into a core register reads paths a managed root doesn't have. Each one, alone in a pack, through the real sync.
_ext() { jq -n --arg i "$1" '{schema: 1, id: $i, version: "1.0.0", harbor_version: ">=1", provides: ["script"], files: []}' > "$HUBDIR/packs/$1/extension.json"; }
for _f in checks.md controls.tsv terms.tsv; do
  _id="fixture-$(printf '%s' "$_f" | tr -d '.')"; _p="$HUBDIR/packs/$_id/harbor-pack"; mkdir -p "$_p"
  printf 'name = "%s"\nversion = "1.0.0"\nharbor_version = ">=1"\ndescription = "a pack with a register row"\n' "$_id" > "$_p/pack.toml"
  printf 'x\n' > "$_p/$_f"
  _ext "$_id"
  e_git add -A; e_git commit -qm "$_id"
  e_policy "$RULES | .packs = [{id:\"$_id\",commit:\"$(e_git rev-parse HEAD)\"}]"
  e_session start
  t_has "$_f: the session says the sync failed" "$(printf '%s' "$E_OUT" | jq -r .systemMessage)" "could not be brought up to date"
  sh "$MB/pack.sh" install "$_id" --hub --apply --live > "$T_TMP/pk.out" 2>&1 || :
  t_has "$_f: refused for what it is" "$(cat "$T_TMP/pk.out")" "$_f composes into a core register"
  t_exit "$_f: nothing of it landed" 1 test -e "$CLAUDE_CONFIG_DIR/.harbor-packs/hub-$_id.tsv"
done
# And what a flat root does serve still installs.
_id=fixture-keys; _p="$HUBDIR/packs/$_id/harbor-pack"; mkdir -p "$_p/bin"
printf 'name = "%s"\nversion = "1.0.0"\nharbor_version = ">=1"\ndescription = "keys and a command"\n' "$_id" > "$_p/pack.toml"
printf 'fixture_key\n' > "$_p/conf-keys.txt"; printf '#!/bin/sh\n' > "$_p/bin/fixture-keys-tool.sh"
printf 'name\trel\nfixture-keys-tool\tbin/fixture-keys-tool.sh\n' > "$_p/shims.tsv"
_ext "$_id"
e_git add -A; e_git commit -qm "$_id"
e_policy "$RULES | .packs = [{id:\"$_id\",commit:\"$(e_git rev-parse HEAD)\"}]"
e_session start
t_eq "CONTROL: conf-keys.txt and shims.tsv install on a flat root" '' "$E_OUT"
t_exit "and landed" 0 test -e "$CLAUDE_CONFIG_DIR/.harbor-packs/hub-$_id.tsv"
e_policy "$RULES"
e_session start

}

s7() {
t_section "7 - a standalone guard is standalone, whatever env says"
SA="$CLAUDE_CONFIG_DIR/bin"; mkdir -p "$SA"
while read -r _s _d; do cp "$T_ROOT/$_s" "$SA/${_d:-${_s##*/}}"; done < "$T_TMP/rows"
: > "$T_TMP/records"
for _v in $(sed 's/=.*//' "$T_TMP/env.list"); do unset "$_v"; done
guard_run() { # <argv of a table row> <payload> [VAR=value...]: rc, stdout and stderr, as one comparable text
  _argv="$1"; printf '%s' "$2" > "$T_TMP/g.in"; shift 2
  _a=''; for _w in $_argv; do case "$_w" in -*) _a="$_a $_w" ;; *) _a="$_a $SA/$_w" ;; esac; done
  # shellcheck disable=SC2086 # the row is words from the table
  ( cd "$W" && env "$@" sh $_a < "$T_TMP/g.in" 2>&1; printf 'rc=%s\n' "$?" )
}
_pay() { jq -cn --arg t "$1" --arg w "$W" --argjson i "$2" '{session_id:"s-1",transcript_path:"/t/main.jsonl",cwd:$w,permission_mode:"default",hook_event_name:"PreToolUse",tool_name:$t,tool_input:$i,tool_use_id:"toolu_0"}'; }
_cases=0; _same=0; _fired=0
while IFS="$(printf '\t')" read -r _m _argv; do
  case "$_m" in Bash*) ;; *) continue ;; esac
  for _c in "$DD" 'git reset --hard' "$KEYOUT" 'gcloud projects delete fixture-a' 'ls -la'; do
    _p="$(_pay Bash "$(jq -cn --arg c "$_c" '{command:$c}')")"
    _plain="$(guard_run "$_argv" "$_p" X=1)"
    _env="$(guard_run "$_argv" "$_p" HARBOR_MEMBER_ROLE=member HARBOR_MEMBER_LOGIN=alice HARBOR_HUB_REPO="$REPO" HARBOR_MEMBER_ROOT="$MR" HARBOR_ADMISSION_MEMBER_RECORDS="$T_TMP/records")"
    _cases=$((_cases + 1))
    [ "$_plain" = "$_env" ] && _same=$((_same + 1)) || printf 'differs: %s on %s\n' "$_argv" "$_c" >&2
    [ "$_plain" = 'rc=0' ] || _fired=$((_fired + 1))
  done
done < "$SA/member-guards.tsv"
t_eq "every guard said the same with member env as without" "$_cases" "$_same"
t_eq "CONTROL: the rows ran" 1 "$([ "$_cases" -ge 20 ] && echo 1)"
t_eq "CONTROL: some of them really blocked" 1 "$([ "$_fired" -ge 3 ] && echo 1)"
t_eq "and no guard wrote a member record" '' "$(cat "$T_TMP/records")"
t_has "a standalone refusal keeps its remedy" "$(guard_run 'admission-hook.sh admission-bash.sh' "$(_pay Bash "$(jq -cn --arg c "$DD" '{command:$c}')")" HARBOR_MEMBER_ROLE=member)" "if this refusal is wrong"
t_eq "the standalone wiring has no Read row" '' "$(sed -n "/^floor_hooks() { cat <<'ROWS'/,/^ROWS\$/p" "$T_ROOT/bin/admission-install.sh" | grep '^PreToolUse;Read')"
_rp="$(_pay Read "$(jq -cn --arg p "$HOME/.ssh/id_rsa" '{file_path:$p}')")"
t_eq "and a Read handed to the guard by hand is the exit it always was" 'rc=0' "$(guard_run 'admission-hook.sh admission-egress.sh' "$_rp" HARBOR_MEMBER_ROLE=member HARBOR_ADMISSION_MEMBER_RECORDS="$T_TMP/records")"
t_eq "and writes no record" '' "$(cat "$T_TMP/records")"
}

s13() {
t_section "13 - the Read and Grep tools reach the tier path, because managed rules drop the Read deny rows"
e_policy "$RULES"
e_session start
mkdir -p "$HOME/.ssh" "$HOME/.aws" "$W/secrets" "$W/certs"
printf 'k\n' > "$HOME/.ssh/id_rsa"; printf 'k\n' > "$HOME/.aws/credentials"; printf 'k\n' > "$W/.env"; printf 'k\n' > "$W/README.md"
ln -sf "$HOME/.ssh/id_rsa" "$W/notes.txt"; ln -sfn "$HOME/.ssh" "$W/keys"
# A link then `..`: the disk says elsewhere/.ssh, a harness that resolves the text first says ~/.ssh. Both are asked.
mkdir -p "$T_TMP/elsewhere/sub" "$T_TMP/elsewhere/.ssh"; ln -sfn "$T_TMP/elsewhere/sub" "$HOME/dodge"
for _p in "$HOME/.ssh/id_rsa" "$HOME/.ssh/config" "$HOME/.aws/credentials" "$W/.env" "$W/.env.local" "$W/certs/server.pem" "$W/certs/a.p12" "$W/secrets/token.txt" \
          '.env' '~/.ssh/id_rsa' "$W/certs/../.env" "/no-such-dir/..$HOME/.ssh/id_rsa" "$W/notes.txt" "$W/keys/id_rsa" "$HOME/dodge/../.ssh/config" "$HOME/.SSH/id_rsa" "$W/.ENV"; do
  e_read "$_p"
  t_eq "denied: $_p" deny "$E_DEC"
done
for _p in "$W/README.md" "$W/my.env" "$W/.envrc" "$W/id_rsa.pub" "$W/secrets.md" "$W/certs/pem.txt"; do
  e_read "$_p"
  t_eq "runs: $_p" silent "$E_DEC"
done
# Grep reads what it matches into the session, so the same rows hold it: the folder searched, a folder whose search walks into one, and a filter that picks one out.
mkdir -p "$HOME/.local/share/secret" "$HOME/.local/share/keyrings"; printf 'k\n' > "$HOME/.local/share/secret/other.enc"; printf 'k\n' > "$HOME/.local/share/keyrings/login.keyring"
for _p in "$HOME/.local/share/secret/hub-token.enc" "$HOME/.local/share/secret/hub-token.key" "$HOME/.local/share/secret/other.enc" "$HOME/.local/share/keyrings/login.keyring"; do
  e_read "$_p"
  t_eq "the token store, Read: $_p" deny "$E_DEC"
  e_grep "$_p"
  t_eq "and Grep" deny "$E_DEC"
done
for _p in "$HOME/.ssh/id_rsa" "$HOME/.ssh" "$HOME/.aws/credentials" "$W/.env" "$W/certs/server.pem" "$W/secrets" "$W/secrets/token.txt" '~/.ssh' "$W/certs/../.env" \
          "$W/notes.txt" "$W/keys" "$HOME/dodge/../.ssh" "$HOME/.SSH" "$HOME/.local/share/secret" "$HOME" "$HOME/.local" '~' /; do
  e_grep "$_p"
  t_eq "a search of $_p: denied" deny "$E_DEC"
done
for _g in '.env*' '**/.env' '*.{pem,crt}' 'secrets/**' '**/id_rsa' 'keys/*'; do
  e_grep "$W" "$_g"
  t_eq "a search of the project filtered to $_g: denied" deny "$E_DEC"
done
e_grep "$W/certs/.." '*.p?m'
t_eq "a key filter judged where the search really runs" deny "$E_DEC"
e_grep "$W"; t_eq "a search of the project runs" silent "$E_DEC"
e_grep ''; t_eq "and from the cwd, which is the project" silent "$E_DEC"
e_grep "$W/README.md"; t_eq "a search of an ordinary file runs" silent "$E_DEC"
for _g in '*.ts' '*' '**/*.md' '*.{ts,js}' 'src/**' 'my.env'; do
  e_grep "$W" "$_g"
  t_eq "a search of the project filtered to $_g runs" silent "$E_DEC"
done
e_read "$HOME/.ssh/id_rsa"; IDR="$E_ID"
t_has "it waits for an admin, as the fixed row" "$E_WHY" "Your admin has been told"
t_has "in the row's words" "$E_WHY" "Reading key material"
e_say fixture-admin "$(e_issue_of "$IDR")" "approve $IDR"
e_read "$HOME/.ssh/id_rsa"
t_eq "an admin can approve one Read" silent "$E_DEC"
e_post
e_read "$HOME/.ssh/id_rsa"
t_eq "one" deny "$E_DEC"
e_policy "$RULES | .tiers = {\"admission.key-material-read\":\"low\"}"
e_session start
e_read "$W/.env"
t_eq "a hub can't lower it" deny "$E_DEC"
t_has "and it still goes to the admin" "$E_WHY" "Your admin has been told"
mv "$MB/member-guards.tsv" "$T_TMP/table.keep"; grep -v '^read-deny' "$T_TMP/table.keep" > "$MB/member-guards.tsv"
e_read "$W/README.md"
t_eq "a table with no Read rows judges nothing, so nothing is read" deny "$E_DEC"
mv "$T_TMP/table.keep" "$MB/member-guards.tsv"
rm -f "$W/notes.txt" "$W/keys" "$W/.env" "$W/README.md" "$HOME/dodge"

}

s14() {
t_section "14 - on a marker box the root-owned file speaks and env doesn't"
e_policy "$RULES | .tiers = {\"admission.dd-to-device\":\"low\"}"
cp "$HUBDIR/policy.json" "$T_TMP/older.json"; cp "$HUBDIR/policy.json.sig" "$T_TMP/older.sig"
e_policy "$RULES"
e_session start
mkdir -p "$T_TMP/evil"
for _b in curl git jq ssh-keygen; do printf '#!/bin/sh\necho %s >> "%s/evil.used"\nexit 0\n' "$_b" "$T_TMP" > "$T_TMP/evil/$_b"; chmod +x "$T_TMP/evil/$_b"; done
e_bash "$CMD --evil"
rm -f "$HS/requests/.last-note"
E_PATH="$T_TMP/evil:$PATH"
e_session start; e_prompt "anything new?"; e_bash "$CMD --evil"; e_post; e_stop; e_flush
E_PATH=''
t_eq "no hook entry ran a binary from a planted PATH" '' "$(sort -u "$T_TMP/evil.used" 2>/dev/null | tr '\n' ' ')"
# curl alone, with the real jq, so the hook gets as far as the board: a shim that keeps what it is handed, which is where the token would be.
mkdir -p "$T_TMP/evil-curl"
printf '#!/bin/sh\n{ printf "%%s\\n" "$*"; cat; } >> "%s/curl.saw"\nexit 0\n' "$T_TMP" > "$T_TMP/evil-curl/curl"; chmod +x "$T_TMP/evil-curl/curl"
: > "$T_TMP/curl.saw"
rm -f "$HS/last-send"; _sent="$(wc -l < "$ST/log.jsonl")"
E_PATH="$T_TMP/evil-curl:$PATH"; e_session start; E_PATH=''
t_eq "the session hook never hands the token to a planted curl" '' "$(cat "$T_TMP/curl.saw")"
t_eq "CONTROL: it did reach the board" 1 "$([ "$(wc -l < "$ST/log.jsonl")" -gt "$_sent" ] && echo 1)"
e_bash "$CMD --curl"; rm -f "$HS/requests/.last-note"; _sent="$(wc -l < "$ST/log.jsonl")"
E_PATH="$T_TMP/evil-curl:$PATH"; e_prompt "anything new?"; E_PATH=''
t_eq "nor does the prompt hook" '' "$(cat "$T_TMP/curl.saw")"
t_eq "CONTROL: it did reach the board" 1 "$([ "$(wc -l < "$ST/log.jsonl")" -gt "$_sent" ] && echo 1)"
# A second hub with this hub's own key and a higher serial: only the address keeps it out, so git config from env or ~/.gitconfig must not move that address.
_o="$T_TMP/steer-hub"; rm -rf "$_o"; mkdir -p "$_o"; git -C "$_o" init -q -b main
jq --argjson s "$((E_SERIAL + 70))" '.serial = $s' "$HUBDIR/policy.json" > "$_o/policy.json"
ssh-keygen -q -Y sign -f "$KEY" -n harbor-hub "$_o/policy.json" 2>/dev/null
git -C "$_o" add -A; git -C "$_o" -c user.name=x -c user.email=x@x.test commit -qm steer
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$_o.insteadOf" GIT_CONFIG_VALUE_0="$HUBDIR"; export GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0
e_session start
unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0
t_eq "git config in env can't move the hub's address" "$E_SERIAL" "$(jq .serial "$HS/policy.json")"
git config --file "$HOME/.gitconfig" "url.$_o.insteadOf" "$HUBDIR"
e_session start
t_eq "nor can ~/.gitconfig" "$E_SERIAL" "$(jq .serial "$HS/policy.json")"
rm -f "$HOME/.gitconfig"
mkdir -p "$T_TMP/moved/harbor/hub"
cp "$T_TMP/older.json" "$T_TMP/moved/harbor/hub/policy.json"; cp "$T_TMP/older.sig" "$T_TMP/moved/harbor/hub/policy.json.sig"
XDG_STATE_HOME="$T_TMP/moved"; export XDG_STATE_HOME
e_bash "$DD"
t_eq "a state folder named by env can't bring an older signed policy back" deny "$E_DEC"
XDG_STATE_HOME="$T_TMP/nothing-here"
e_bash "cat gs://prod-data/moved"
t_eq "and an empty one doesn't read as no hub" deny "$E_DEC"
t_has "the hub's rule still bites" "$E_WHY" "Touches the production bucket"
unset XDG_STATE_HOME
_role="$HARBOR_MEMBER_ROLE"; unset HARBOR_MEMBER_ROLE
e_bash "cat gs://prod-data/role"
t_eq "the role unset, hub rules stay" deny "$E_DEC"
t_has "by name" "$E_WHY" "Touches the production bucket"
HARBOR_MEMBER_ROLE=standalone; export HARBOR_MEMBER_ROLE
e_bash "cat gs://prod-data/role2"
t_eq "the role set to standalone, too" deny "$E_DEC"
t_has "by name" "$E_WHY" "Touches the production bucket"
HARBOR_MEMBER_ROLE="$_role"
_login="$HARBOR_MEMBER_LOGIN"; _repo="$HARBOR_HUB_REPO"
HARBOR_MEMBER_LOGIN=fixture-admin; HARBOR_HUB_REPO=evil-org/evil-hub
e_bash "cat gs://prod-data/who"; IDW="$E_ID"
t_eq "a login or repo in env changes nothing about the request" 1 "$(e_request_count "$IDW")"
t_has "it is alice's" "$(jq -r .body "$ST/issues/$(e_issue_of "$IDW").json")" "member: alice"
t_eq "and nothing went to the other repo" 0 "$(grep -c evil-org "$ST/log.jsonl")"
HARBOR_MEMBER_LOGIN="$_login"; HARBOR_HUB_REPO="$_repo"
mkdir -p "$HOME/.ssh"; printf 'k\n' > "$HOME/.ssh/id_rsa"
_home="$HOME"; HOME="$T_TMP/fakehome"; mkdir -p "$HOME"
e_read "$_home/.ssh/id_rsa"
t_eq "a HOME in env doesn't move what ~ means" deny "$E_DEC"
HOME="$_home"

t_section "14b - a marker with no readable member.conf fails closed"
_conf="$MR/member.conf"; cp "$_conf" "$T_TMP/conf.keep"
conf_fault() { # <label>
  e_bash "ls -la"
  t_eq "$1: refused" 2 "$E_RC"
  t_eq "$1: no decision is claimed" '' "$E_OUT"
}
rm -f "$_conf"
conf_fault "no file"
e_session start
t_eq "a session still starts" 0 "$E_RC"
t_has "and says so" "$E_OUT" "could not be read"
e_prompt "anything new?"
t_eq "a prompt still goes through" 0 "$E_RC"
t_eq "and says nothing" '' "$E_OUT"
e_post
t_eq "a post hook never blocks" 0 "$E_RC"
: > "$_conf"; conf_fault "an empty file"
printf 'hub=not-a-slug\nlogin=alice\nhome=%s\n' "$HOME" > "$_conf"; conf_fault "a hub that isn't owner/name"
printf 'hub=%s\nlogin=-x\nhome=%s\n' "$REPO" "$HOME" > "$_conf"; conf_fault "a login that isn't one"
printf 'hub=%s\nlogin=alice\nhome=relative\n' "$REPO" > "$_conf"; conf_fault "a home that isn't absolute"
printf 'hub=%s\nhome=%s\n' "$REPO" "$HOME" > "$_conf"; conf_fault "a missing line"
rm -f "$_conf"; ln -s "$T_TMP/conf.keep" "$_conf"; conf_fault "a link"
rm -f "$_conf"; cp "$T_TMP/conf.keep" "$_conf"; chmod 000 "$_conf"; conf_fault "unreadable"
chmod 644 "$_conf"
cmp -s "$_conf" "$T_TMP/conf.keep" && t_pass || t_fail "the conf did not come back"
e_bash "ls -la"
t_eq "put back, work goes on" silent "$E_DEC"

t_section "14c - joined with no policy on disk is never lower than the last good policy"
rm -f "$HS/policy.json" "$HS/policy.json.sig" "$HS/last-good/policy.json" "$HS/last-good/policy.json.sig"
e_bash "cat gs://prod-data/gone"
t_eq "a hub rule's call stays stopped" deny "$E_DEC"
t_has "as settings that can't be read" "$E_WHY" "could not be read"
t_eq "the laptop says bad, not enforce" bad "$(sh "$MB/hub-tier.sh" mode)"
e_bash "ls -la"
t_eq "and so does any other call, since a policy could raise any call" deny "$E_DEC"
e_session start
e_bash "ls -la"
t_eq "the next session fetches it back" silent "$E_DEC"

}

s15() {
t_section "15 - output that opens as JSON and doesn't parse is a deny, at both places"
e_policy "$RULES | .packs = [$PACKS] | .hooks = [{pack:\"fixture-pack\",path:\"hooks/half.sh\",sha256:\"$E_HALF_SHA\"}]"
e_session start
t_eq "CONTROL: the hook arrived" "$E_HALF_SHA" "$(e_sha < "$HS/hooks/fixture-pack/hooks/half.sh")"
e_bash "ls -la"
t_eq "a hub hook's JSON cut short is a deny" deny "$E_DEC"
t_has "in its own words" "$E_WHY" "Your company's own check"
e_policy "$RULES"
e_session start
e_bash "ls -la"
t_eq "CONTROL: without it, the same call runs" silent "$E_DEC"
cp "$MB/admission-cloud.sh" "$T_TMP/cloud.keep"
printf '#!/bin/sh\nprintf %%s %s\n' "'{\"hookSpecificOutput\":{\"permissionDe'" > "$MB/admission-cloud.sh"
e_bash "ls -la"
t_eq "a guard's JSON cut short is a deny" deny "$E_DEC"
cat "$T_TMP/cloud.keep" > "$MB/admission-cloud.sh"

}

for _s in ${*:-s10 s11 s12 s13 s14 s15 s7}; do "$_s"; done
e_gh_down
t_done
