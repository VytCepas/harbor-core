#!/usr/bin/env sh
# tiers.test.sh (harbor#1278) — member-dispatch.sh decides a call once: each tier, the highest of several, shadow, integrity, no human, and a denied call stays denied.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/hub/fixtures/member-root.sh"
DD='dd if=/dev/zero of=/dev/sda'   # bash:dd-to-device, a block row: very-high by default
RESET='git reset --hard'           # destroy:git-reset-hard, a warn row: high
SELF="$(m_tool Edit "$(jq -cn --arg p "$CLAUDE_CONFIG_DIR/settings.json" '{file_path:$p,old_string:"a",new_string:"b"}')")"

t_section "1 - no rule fired: silence, and no allow"
m_reset; m_enforce
m_call "$(m_bash 'ls -la')"
t_eq "exit" 0 "$M_RC"
t_eq "nothing on stdout" "" "$M_OUT"
t_eq "the board was not consulted" "" "$(m_approvals)"

t_section "2 - very-high: denied, one consultation, one request, plain words"
m_reset; m_enforce
m_call "$(m_bash "$DD")"
t_eq "denied" deny "$M_DEC"
t_eq "status once, then file once" "status file " "$(m_approvals)"
RID="$(sed -n 's/^status //p' "$MB/stub-approval.log")"
t_eq "the id is a request id" 1 "$(printf '%s\n' "$RID" | grep -cE '^r-[0123456789abcdef]{16}$')"
t_has "the words name the id" "$M_WHY" "$RID"
t_has "the words say the admin has been told" "$M_WHY" "Your admin has been told"
t_has "and that a changed call starts over (F23)" "$M_WHY" "a changed call needs a new approval"
t_has "the label is the one lookup prints, for hub-approval.sh" "$(sed -n 's/^file //p' "$MB/stub-approval.log")" "$(sh "$MB/hub-tier.sh" lookup admission.dd-to-device | cut -f3)"
t_has "file carries rule, tier, target and label" "$(sed -n 's/^file //p' "$MB/stub-approval.log")" "$RID admission.dd-to-device very-high command"
t_has "a refusal event" "$(m_events)" "refusal rule=admission.dd-to-device tier=very-high target=command count=1"
t_has "a request event" "$(m_events)" "request id=$RID rule=admission.dd-to-device tier=very-high target=command outcome=opened"
m_call "$(m_bash "$DD")"
t_eq "a denied call stays denied on retry" deny "$M_DEC"
t_eq "the opened event is not repeated" 1 "$(m_events | grep -c 'outcome=opened')"

t_section "3 - very-high with no way to tell the admin says so"
m_reset; m_enforce; echo 3 > "$MB/stub-status"; echo 3 > "$MB/stub-file"
m_call "$(m_bash "$DD")"
t_eq "GitHub down stays denied" deny "$M_DEC"
t_has "and doesn't claim the admin was told" "$M_WHY" "could not be told"
t_hasnt "...in those words" "$M_WHY" "has been told"

m_reset; m_enforce; echo 2 > "$MB/stub-file"
m_call "$(m_bash "$DD")"
t_eq "a refused request stays denied" deny "$M_DEC"
t_hasnt "...and doesn't claim otherwise" "$M_WHY" "has been told"

t_section "4 - an approved call gets silence, never allow"
m_reset; m_enforce; echo 0 > "$MB/stub-status"
m_call "$(m_bash "$DD")"
t_eq "exit" 0 "$M_RC"
t_eq "no output at all" "" "$M_OUT"
t_eq "status once, nothing filed" "status " "$(m_approvals)"
t_has "the approval waits for PostToolUse" "$(cat "$HOME/.local/state/harbor/hub/open/toolu_1")" "$(printf 's-1\t0\tadmission.dd-to-device\tvery-high\tcommand\tr-')"
t_hasnt "and was not spent here" "$(m_approvals)x" "consume"

t_section "5 - a changed call is a new request"
m_reset; m_enforce
m_call "$(m_bash "$DD")"; R1="$(sed -n 's/^status //p' "$MB/stub-approval.log")"
m_reset; m_enforce
m_call "$(m_bash "$DD bs=1")"; R2="$(sed -n 's/^status //p' "$MB/stub-approval.log")"
[ "$R1" != "$R2" ] && t_pass || t_fail "a changed command got the same id $R1"

t_section "6 - high and medium ask, and open a record"
m_reset; m_enforce
m_call "$(m_bash "$RESET")"
t_eq "a warn row asks" ask "$M_DEC"
t_eq "no board call" "" "$(m_approvals)"
t_has "an open record keyed on tool_use_id" "$(cat "$HOME/.local/state/harbor/hub/open/toolu_1")" "$(printf 's-1\t1\tadmission.git-reset-hard\thigh\tfile\t-')"
m_reset; m_enforce '.tiers = {"admission.dd-to-device":"medium"}'
m_call "$(m_bash "$DD")"
t_eq "a medium row asks" ask "$M_DEC"

t_section "7 - low runs, logged"
m_reset; m_enforce '.tiers = {"admission.dd-to-device":"low"}'
m_call "$(m_bash "$DD")"
t_eq "silent" silent "$M_DEC"
t_eq "exit" 0 "$M_RC"
t_has "logged" "$(m_events)" "check check=admission.dd-to-device outcome=passed"

t_section "8 - no human: an ask is a deny (M6)"
for _e in '.permission_mode = "bypassPermissions"' '.transcript_path = "/t/subagents/a.jsonl"' '.agent_type = "general-subagent"'; do
  m_reset; m_enforce
  m_call "$(m_bash "$RESET" "$_e")"
  t_eq "denied under: $_e" deny "$M_DEC"
done
t_hasnt "no ask record is left open" "$(ls "$HOME/.local/state/harbor/hub/open" 2>/dev/null)x" "toolu_1"
m_reset; m_enforce
m_call "$(m_bash "$DD" '.agent_type = "general-subagent"')"
t_eq "very-high in a subagent is still a request" "status file " "$(m_approvals)"

t_section "8b - W3: one setting turns every ask into a deny"
m_reset; m_enforce
cp "$MB/member-dispatch.sh" "$T_TMP/dispatch.keep"
sed 's/^ASK_VERDICT=ask$/ASK_VERDICT=deny/' "$T_TMP/dispatch.keep" > "$MB/member-dispatch.sh"
t_eq "CONTROL: the copy's setting moved" 1 "$(grep -c '^ASK_VERDICT=deny$' "$MB/member-dispatch.sh")"
m_call "$(m_bash "$RESET")"
t_eq "denied, with a person present" deny "$M_DEC"
cp "$T_TMP/dispatch.keep" "$MB/member-dispatch.sh"

t_section "9 - integrity: no route, in any mode, and approval can't reach it"
m_reset; m_enforce; echo 0 > "$MB/stub-status"
m_call "$SELF"
t_eq "denied" deny "$M_DEC"
t_eq "no approval is consulted" "" "$(m_approvals)"
t_has "says no approval changes it" "$M_WHY" "no approval can change it"
m_reset; m_policy '.'
m_call "$SELF"
t_eq "denied in shadow" deny "$M_DEC"
m_reset; m_enforce '.tiers = {"admission.baseline-surface":"low"}'
m_call "$SELF"
t_eq "a hub can't lower it" deny "$M_DEC"

t_section "10 - shadow records the would-be verdict and enforces nothing else"
m_reset; m_policy '.'
m_call "$(m_bash "$DD")"
t_eq "very-high runs" silent "$M_DEC"
t_eq "no board call" "" "$(m_approvals)"
t_has "recorded" "$(m_events)" "refusal rule=admission.dd-to-device tier=very-high target=command count=1"
m_reset; m_policy '.'
m_call "$(m_bash "$RESET")"
t_eq "an ask row runs" silent "$M_DEC"
t_has "recorded at its tier" "$(m_events)" "refusal rule=admission.git-reset-hard tier=high"

t_section "11 - the highest tier of every fired rule decides"
m_reset; m_enforce '.tiers = {"admission.dd-to-device":"low"}'
m_call "$(m_bash "$DD; $RESET")"
t_eq "a low rule first doesn't hide a later high" ask "$M_DEC"
m_reset; m_enforce
m_call "$(m_bash "$RESET; $DD")"
t_eq "a high rule doesn't hide a very-high" deny "$M_DEC"
t_eq "...which is the one filed" "status file " "$(m_approvals)"
m_reset; m_enforce '.tiers = {"admission.dd-to-device":"low"}'
m_call "$(m_bash "$DD > $CLAUDE_CONFIG_DIR/settings.json")"
t_eq "a low rule doesn't hide an integrity rule in the same guard" deny "$M_DEC"
t_has "...named as such" "$M_WHY" "no approval can change it"

t_section "12 - hub rules add to the guards"
m_reset; m_enforce
m_call "$(m_bash 'gsutil ls gs://prod-data')"
t_eq "a hub very-high rule denies a call no guard minds" deny "$M_DEC"
t_has "under its own id, tier and target" "$(sed -n 's/^file //p' "$MB/stub-approval.log")" "prod-bucket very-high cloud Touches the production bucket"
m_reset; m_enforce '.rules[0].tier = "high"'
m_call "$(m_bash 'gsutil ls gs://prod-data')"
t_eq "a hub high rule asks" ask "$M_DEC"
t_has "...with its label" "$M_WHY" "Touches the production bucket"
m_reset; m_enforce '.rules[0].tier = "low" | .rules[0].when[0].value = "of=/dev/sda"'
m_call "$(m_bash "$DD")"
t_eq "a low hub rule can't lower a very-high core rule" deny "$M_DEC"

t_section "13 - bad policy fails closed"
m_reset; printf '%s\n' "$T_TMP/garbage.json" > "$MB/stub-policy"; printf '{not json' > "$T_TMP/garbage.json"
m_call "$(m_bash 'ls')"
t_eq "an unreadable policy stops the call" deny "$M_DEC"
t_has "...in plain words" "$M_WHY" "could not be read"
m_reset; m_policy '.schema = 2'
m_call "$(m_bash "$RESET")"
t_eq "a newer schema is not read as shadow" deny "$M_DEC"
m_reset; m_policy '.tiers = {"admission.dd-to-device":"none"}'
m_call "$(m_bash "$DD")"
t_eq "a bad tier value is a bad policy" deny "$M_DEC"
m_reset; echo 1 > "$MB/stub-check"
m_call "$(m_bash 'ls')"
t_eq "policy files that none verify aren't \"no hub\"" deny "$M_DEC"
m_reset
m_call "$(m_bash 'ls')"
t_eq "no policy at all on a marker box: any call stops, since a policy could raise it" deny "$M_DEC"
t_has "...as settings that can't be read" "$M_WHY" "could not be read"
t_eq "...with no route, since no approvers are known" "" "$(m_approvals)"

t_section "14 - fail closed"
m_reset; m_enforce
printf 'not json' > "$MIN"
_rc=0; sh "$MB/member-dispatch.sh" < "$MIN" > "$T_TMP/o" 2> "$T_TMP/e" || _rc=$?
t_eq "a payload jq refuses" 2 "$_rc"
t_has "plain words on stderr" "$(cat "$T_TMP/e")" "could not finish"
_gone() { # <file> <label>: take a file away, the call must not pass
  mv "$MB/$1" "$MB/$1.away"
  m_call "$(m_bash 'ls')"
  if [ "$M_RC" != 0 ] || [ "$M_DEC" = deny ]; then t_pass; else t_fail "$2 (rc $M_RC, $M_DEC)"; fi
  mv "$MB/$1.away" "$MB/$1"
}
_gone member-guards.tsv "no guard table"
_gone harbor-member-mode "no member marker"
_gone library-admission.sh "no library"
_gone library-hub.sh "no hub library"
_gone admission-bash.sh "a guard in the table is missing"
_gone hub-tier.sh "no tier lookup"
_gone hub-sync.sh "no policy reader"
mv "$MB/risk-tiers.tsv" "$MB/risk-tiers.tsv.away"
m_call "$(m_bash "$DD")"
t_eq "no core list: a fired rule is denied" deny "$M_DEC"
t_eq "...with no route, since nothing was decided" "" "$(m_approvals)"
mv "$MB/risk-tiers.tsv.away" "$MB/risk-tiers.tsv"
printf '#!/bin/sh\nexit 7\n' > "$T_TMP/crash.sh"
cp "$MB/admission-cloud.sh" "$T_TMP/cloud.keep"; cp "$T_TMP/crash.sh" "$MB/admission-cloud.sh"
m_reset; m_enforce
m_call "$(m_bash 'ls')"
t_eq "a crashed ask-layer guard is a refusal here, unlike standalone" deny "$M_DEC"
cp "$T_TMP/cloud.keep" "$MB/admission-cloud.sh"
m_call "$(m_bash 'ls')"
t_eq "CONTROL: restored, the same call runs" silent "$M_DEC"

t_red admission.member-dispatch
t_done
