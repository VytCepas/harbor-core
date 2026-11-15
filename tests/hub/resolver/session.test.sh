#!/usr/bin/env sh
# session.test.sh (harbor#1278) — member-session.sh: SessionStart syncs, checks the floor, counts a session start and sends; SessionEnd
# counts a session end and sends (D9); neither blocks a session, and a failed floor check is a `check` event and a line in the session's context.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/hub/fixtures/resolver.sh"
member_env; mkinst; hub_init
export HARBOR_HUB_TIMEOUT=2
# member-session.sh syncs into the live config dir: HOME is the suite's own temp home, so that is a throwaway.
mkdir -p "$HOME/.claude"
ms() { printf '%s' "$2" | sh "$INST/bin/member-session.sh" $1 2> "$T_TMP/ms.err"; }
START='{"hook_event_name":"SessionStart","source":"startup"}'; END='{"hook_event_name":"SessionEnd"}'
: > "$T_TMP/events.log"

t_section "1 - a standalone box does nothing"
_o="$(HARBOR_MEMBER_ROLE= ms '' "$START")"; _rc=$?
t_eq "exit 0" 0 "$_rc"; t_eq "no output" "" "$_o"; t_eq "no event" 0 "$(wc -l < "$T_TMP/events.log" | tr -d ' ')"

t_section "2 - SessionStart on a healthy member"
_o="$(ms '' "$START")"; _rc=$?
t_eq "exit 0" 0 "$_rc"
t_eq "the policy was fetched and is held" joined "$(sh "$HS" state 2>/dev/null)"
t_has "the outbox is sent (the sender builds the heartbeat)" "$(cat "$T_TMP/events.log")" "send"
t_eq "...and no heartbeat is recorded here: the sender discards one" 0 "$(grep -c 'heartbeat' "$T_TMP/events.log")"
t_has "a session start is counted (D9)" "$(cat "$T_TMP/events.log")" "record session outcome=started count=1"
t_eq "...once, before the send" "record session outcome=started count=1" "$(grep -m1 -E 'session|send' "$T_TMP/events.log")"
t_eq "a clean floor says nothing in the session's context" "" "$_o"

t_section "3 - a failed integrity check is an event and a line in the context"
: > "$T_TMP/events.log"; echo 1 > "$T_TMP/integrity.rc"
_o="$(ms start "")"; _rc=$?
t_eq "still exit 0" 0 "$_rc"
t_has "a check event is recorded" "$(cat "$T_TMP/events.log")" "record check check=floor-integrity outcome=failed"
t_has "the reply is SessionStart context" "$_o" '"hookEventName": "SessionStart"'
t_has "...naming the failed check" "$_o" "integrity check of the managed floor FAILED"
t_has "the reply also carries a systemMessage the person sees" "$_o" '"systemMessage"'
t_has "...and the outbox is still sent" "$(cat "$T_TMP/events.log")" "send"
rm -f "$T_TMP/integrity.rc"

t_section "3b - an approval that arrived is told to the person at SessionStart"
: > "$T_TMP/events.log"; printf 'An admin approved request r-0123456789abcdef.\n' > "$T_TMP/approval.note"
_o="$(ms start "")"
t_has "the note from hub-approval.sh is in the reply" "$(printf '%s' "$_o" | jq -r .systemMessage)" "An admin approved request r-0123456789abcdef."
t_has "...and in the agent's context" "$(printf '%s' "$_o" | jq -r .hookSpecificOutput.additionalContext)" "approved request"
rm -f "$T_TMP/approval.note"

t_section "4 - a missing verifier is a failed check, not a pass"
mv "$INST/bin/member-integrity.sh" "$INST/bin/member-integrity.off"; : > "$T_TMP/events.log"
_o="$(ms start "")"
t_has "recorded as failed" "$(cat "$T_TMP/events.log")" "check check=floor-integrity outcome=failed"
mv "$INST/bin/member-integrity.off" "$INST/bin/member-integrity.sh"

t_section "5 - the network never blocks it"
printf '#!/bin/sh\nsleep 30\n' > "$T_BIN/git"; chmod +x "$T_BIN/git"
_t0="$(date +%s)"; _o="$(ms start "")"; _rc=$?; _t1="$(date +%s)"
t_eq "a hung hub: exit 0" 0 "$_rc"
t_eq "...within the bound (under 20 s for a 2 s timeout)" yes "$([ $((_t1 - _t0)) -lt 20 ] && echo yes || echo no)"
t_eq "...and the held policy is untouched" joined "$(sh "$HS" state 2>/dev/null)"
printf '#!/bin/sh\necho "fatal: HTTP 401" >&2\nexit 128\n' > "$T_BIN/git"
_o="$(ms start "")"; _rc=$?
t_eq "a 401: exit 0, joined" "0 joined" "$_rc $(sh "$HS" state 2>/dev/null)"
rm -f "$T_BIN/git"

t_section "6 - SessionEnd counts the end and sends, nothing else"
: > "$T_TMP/events.log"
_o="$(ms '' "$END")"; _rc=$?
t_eq "exit 0" 0 "$_rc"; t_eq "the end is counted, then the send runs" "$(printf 'record session outcome=ended count=1\nsend')" "$(cat "$T_TMP/events.log")"; t_eq "no context" "" "$_o"

t_section "7 - a verified revocation leaves, says so, and sends nothing"
publish '.serial = 2 | .revoked = ["alice"]'
: > "$T_TMP/events.log"
_o="$(ms start "")"; _rc=$?
t_eq "exit 0" 0 "$_rc"
t_has "the context says the login was revoked" "$_o" "revoked on the hub"
t_eq "the hub policy is gone from the laptop" none "$(sh "$HS" state 2>/dev/null)"
t_eq "no heartbeat went to a hub that let go" 0 "$(grep -c heartbeat "$T_TMP/events.log")"
t_done
