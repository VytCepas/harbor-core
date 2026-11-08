#!/usr/bin/env sh
# post.test.sh (harbor#1278, F21, F8) — member-post.sh closes what the dispatcher opened: an ask at PostToolUse or its failure, an unresolved one as not-run at Stop,
# and an approval is spent only by a call that really ran.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/hub/fixtures/member-root.sh"
OPEN="$HOME/.local/state/harbor/hub/open"
post() { # <event> [tool_use_id] [session]
  jq -cn --arg e "$1" --arg i "${2:-toolu_1}" --arg s "${3:-s-1}" '{hook_event_name:$e,tool_use_id:$i,session_id:$s}' > "$MIN"
  P_RC=0; sh "$MB/member-post.sh" < "$MIN" > "$T_TMP/p.out" 2>&1 || P_RC=$?
  P_OUT="$(cat "$T_TMP/p.out")"
}
asked() { m_reset; m_enforce; m_call "$(m_bash 'git reset --hard' "${1:-.}")"; }
approved() { m_reset; m_enforce; echo 0 > "$MB/stub-status"; m_call "$(m_bash 'dd if=/dev/zero of=/dev/sda' "${1:-.}")"; }

t_section "1 - the ask ran"
asked; post PostToolUse
t_eq "exit" 0 "$P_RC"
t_eq "silent" "" "$P_OUT"
t_has "proceeded" "$(m_events)" "ask rule=admission.git-reset-hard tier=high target=file outcome=proceeded count=1"
t_eq "the record is gone" "" "$(ls "$OPEN")"
asked; post PostToolUseFailure
t_has "a failed call ran too" "$(m_events)" "outcome=proceeded"
asked; post PostToolUse toolu_other
t_hasnt "another call's post closes nothing" "$(m_events)x" "outcome=proceeded"
t_eq "...and the record stays" toolu_1 "$(ls "$OPEN")"

t_section "2 - the ask didn't run"
asked; post Stop
t_has "not-run at Stop" "$(m_events)" "ask rule=admission.git-reset-hard tier=high target=file outcome=not-run count=1"
t_eq "the record is gone" "" "$(ls "$OPEN")"
asked; post Stop toolu_1 s-other
t_hasnt "another session's Stop leaves it" "$(m_events)x" "not-run"
t_eq "...open" toolu_1 "$(ls "$OPEN")"
asked; post PostToolUse; post Stop
t_eq "closed once" 1 "$(m_events | grep -c 'ask rule=')"

t_section "3 - an approval is spent once the call has run, never before (F8)"
approved
t_hasnt "not at PreToolUse" "$(m_approvals)x" "consume"
post PostToolUse
t_has "consume at PostToolUse" "$(m_approvals)" "consume"
t_eq "with the id of the status call" "$(sed -n 's/^status //p' "$MB/stub-approval.log")" "$(sed -n 's/^consume //p' "$MB/stub-approval.log")"
t_has "used is recorded" "$(m_events)" "outcome=used"
t_hasnt "and no ask event: nobody was asked" "$(m_events)x" "ask rule="
approved; post PostToolUseFailure
t_has "a failed call ran, so it is spent" "$(m_approvals)" "consume"
approved; post Stop
t_hasnt "stopped before it ran: the approval is kept" "$(m_approvals)x" "consume"
t_eq "...and the record is cleared" "" "$(ls "$OPEN")"

t_section "4 - it never blocks and takes nothing from the payload as a path"
m_reset; m_enforce
mkdir -p "$OPEN"; printf 'x' > "$T_TMP/outside"
post PostToolUse "../../../../../../outside"
t_eq "a traversal id" 0 "$P_RC"
t_eq "...touches nothing" x "$(cat "$T_TMP/outside")"
printf 'not json' > "$MIN"
_rc=0; sh "$MB/member-post.sh" < "$MIN" >/dev/null 2>&1 || _rc=$?
t_eq "bad input" 0 "$_rc"
mv "$MB/hub-events.sh" "$MB/events.away"; asked; post PostToolUse
t_eq "no events script" 0 "$P_RC"
mv "$MB/events.away" "$MB/hub-events.sh"
_rc=0; HARBOR_ADMISSION_DISABLE=1 sh "$MB/member-post.sh" < /dev/null > /dev/null 2>&1 || _rc=$?
t_eq "empty stdin" 0 "$_rc"
t_done
