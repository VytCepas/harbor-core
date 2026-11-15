#!/usr/bin/env sh
# person.test.sh (harbor#1278) — member-support.sh starts only from a person: a real terminal, outside Claude Code, told in plain words, and a typed yes.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/hub/fixtures/board-env.sh"
. "$T_ROOT/tests/hub/fixtures/support-env.sh"
se_up
filed() { ls "$BE_ST/issues" 2>/dev/null | wc -l | tr -d ' '; }

t_section "1 - no terminal, no start"
se_reset
_o="$(sh "$SE_SUPPORT" </dev/null 2>&1)" && _rc=0 || _rc=$?
t_eq "refused" 1 "$_rc"
t_has "and says why" "$_o" 'real terminal'
t_eq "nothing reached the board" 0 "$(filed)"
_o="$(printf 'fix\nallow\n' | sh "$SE_SUPPORT" 2>&1)" && _rc=0 || _rc=$?
t_eq "a pipe is no terminal, however good its answers" 1 "$_rc"
t_eq "nothing reached the board" 0 "$(filed)"

t_section "2 - never inside Claude Code"
se_reset
CLAUDECODE=1; export CLAUDECODE
se_run 'expect outside Claude Code'
t_eq "the session's variable refuses" 1 "$SE_RC"
unset CLAUDECODE
t_eq "nothing reached the board" 0 "$(filed)"
# With the variable gone the tree still says so: a program named claude is an ancestor. exec -a names it: macOS kills a copied system shell.
printf 'expect outside Claude Code\n' > "$SE_STEPS"
_rc=0; python3 "$T_ROOT/tests/hub/fixtures/terminal_run.py" "$SE_STEPS" "$T_TMP/transcript" -- bash -c 'exec -a /opt/agent/claude bash -c "sh \"\$0\"; exit \$?" "$0"' "$SE_SUPPORT" || _rc=$?
t_eq "an ancestor named claude refuses, with no variable set" 1 "$_rc"
_rc=0; python3 "$T_ROOT/tests/hub/fixtures/terminal_run.py" "$SE_STEPS" "$T_TMP/transcript" -- bash -c 'exec -a /opt/agent/plain bash -c "sh \"\$0\"; exit \$?" "$0"' "$SE_SUPPORT" || _rc=$?
t_eq "CONTROL: any other name doesn't" 124 "$_rc"
UPTERM_SESSION_NAME=hs; export UPTERM_SESSION_NAME
se_run 'expect already inside'
t_eq "from inside a session, a second one is refused" 1 "$SE_RC"
unset UPTERM_SESSION_NAME

t_section "3 - told in plain words, then asked"
se_reset
se_run 'expect Type update' 'send fix' 'expect the word allow' 'send no' 'expect Nothing was sent'
t_eq "anything but allow stops it" 1 "$SE_RC"
t_eq "and nothing reached the board" 0 "$(filed)"
t_eq "upterm never ran" no "$([ -e "$SE_UP" ] && echo yes || echo no)"
for _say in 'working as you' 'read and change anything your account can' 'You see everything they type' \
            "after 60 minutes" "can't change the company's safety settings" "your company's own support service, which can read"; do
  t_has "it says: $_say" "$SE_OUT" "$_say"
done
se_reset
se_run 'expect Type update' 'send please-help' 'expect Nothing was sent'
t_eq "a reason off the closed list stops it" 1 "$SE_RC"
t_eq "and nothing reached the board" 0 "$(filed)"

t_section "4 - it refuses a laptop that isn't ready, before asking anything"
se_reset 'del(.support)'
se_run 'expect not turned on'
t_eq "no support key: support is off" 1 "$SE_RC"
se_reset 'del(.support.relay, .support.relay_key)'
se_run 'expect off until your company runs its own'
t_eq "keys and no relay of the hub's own: support is off, said plainly" 1 "$SE_RC"
t_eq "and the public relay is no fallback: upterm never ran" no "$([ -e "$SE_UP" ] && echo yes || echo no)"
# hub-format.sh refuses it first, so the policy doesn't read; support_relay's own refusal is in tests/hub/support/format.test.sh.
se_reset '.support.relay = "wss://uptermd.upterm.dev"'
se_run 'expect could not be read'
t_eq "a policy naming the public relay is refused, even signed and with a key" 1 "$SE_RC"
se_reset '.support.relay = "ssh://eu.uptermd.upterm.dev:22"'
se_run 'expect could not be read'
t_eq "and any name under it" 1 "$SE_RC"
t_eq "upterm never ran for either" no "$([ -e "$SE_UP" ] && echo yes || echo no)"
se_reset; rm -f "$T_TMP/state-policy.json.sig"
se_run 'expect could not be read'
t_eq "a policy with no signature is no policy" 1 "$SE_RC"
se_reset; se_settings uptermd.upterm.dev
se_run 'expect has not caught up'
t_eq "a relay the managed settings don't deny is refused" 1 "$SE_RC"
se_settings uptermd.upterm.dev relay.example
se_run 'expect Type update' 'send fix' 'expect the word allow' 'send no' 'expect Nothing was sent'
t_eq "CONTROL: denied, it goes on" 1 "$SE_RC"
t_has "and reached the questions" "$SE_OUT" 'REMOTE SUPPORT'
se_reset; mv "$BE_BIN/upterm" "$T_TMP/upterm.away"
se_run 'expect not installed'
t_eq "no upterm, no start" 1 "$SE_RC"
mv "$T_TMP/upterm.away" "$BE_BIN/upterm"
se_reset '.support.keys = ["ssh-ed25519 AAAAnotarealkey"]'
se_run 'expect can not be read'
t_eq "a key ssh-keygen can't read never reaches upterm" 1 "$SE_RC"

t_section "5 - on a member box member.conf says who this is, and the seams are dead"
se_reset
: > "$BE_BIN/harbor-member-mode"
printf 'hub=managed-org/managed-hub\nlogin=alice\nhome=%s\n' "$HOME" > "$BE_ROOT/member.conf"
jq -n '{env: {HARBOR_MEMBER_ROLE: "member", HARBOR_HUB_REPO: "settings-org/settings-hub", HARBOR_MEMBER_LOGIN: "alice", HARBOR_MEMBER_ROOT: "/r"},
        sandbox: {network: {deniedDomains: ["relay.example", "uptermd.upterm.dev"]}}}' > "$BE_ROOT/../managed-settings.json"
mv "$BE_BIN/hub-board.sh" "$T_TMP/board.real"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/board.log"\nprintf 201 > "$2/status"; printf 0 > "$2/limited"; printf "{\\"number\\":7}" > "$2/body"\n' "$T_TMP" > "$BE_BIN/hub-board.sh"
HARBOR_HUB_REPO=wrong-org/wrong-hub HARBOR_MEMBER_SUPPORT_WAIT_SECONDS=0 HARBOR_MEMBER_ROLE=standalone \
  se_run 'expect Type update' 'send fix' 'expect the word allow' 'send allow' 'expect Waiting' 'wait 1' 'hup'
t_has "the repo is the managed one" "$(cat "$T_TMP/board.log")" '/repos/managed-org/managed-hub/issues'
t_hasnt "never the environment's" "$(cat "$T_TMP/board.log")" wrong-org
t_hasnt "nor the settings env, which a launch environment can beat" "$(cat "$T_TMP/board.log")" settings-org
t_hasnt "a zero-second wait in env does not end the wait" "$SE_OUT" 'No admin answered'
mv "$T_TMP/board.real" "$BE_BIN/hub-board.sh"; rm -f "$BE_BIN/harbor-member-mode" "$BE_ROOT/member.conf"

be_down
t_done
