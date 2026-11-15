#!/usr/bin/env sh
# board.test.sh (harbor#1278) — the request, the acceptance judged as an approval is, what upterm is told, and that every way out ends it. Stub board, stub upterm.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/hub/fixtures/board-env.sh"
. "$T_ROOT/tests/hub/fixtures/support-env.sh"
se_up
ASK="expect Type update|send fix|expect the word allow|send allow"
steps() { _o="$IFS"; IFS='|'; # shellcheck disable=SC2086 # the steps are split on | by design
  set -- $ASK "$@"; IFS="$_o"; se_run "$@"; }
# no_accept <comment args after the login>: the member waits, this comment arrives, and no session may start.
never_accepted() { # <what it is> <login> <body-builder: a word or 'as-is'> [created] [updated] [type]
  _what="$1"; _login="$2"; _kind="$3"; _c="${4:-2026-11-07T10:00:00Z}"; _u="${5:-$_c}"; _t="${6:-User}"
  se_reset
  HARBOR_MEMBER_SUPPORT_WAIT_SECONDS=3
  (
    _i=0; while [ ! -f "$BE_ST/issues/1.json" ] && [ "$_i" -lt 100 ]; do sleep 0.1; _i=$((_i + 1)); done
    _id="$(se_id)"
    case "$_kind" in
      accept) _b="accept $_id" ;; prose) _b="accept $_id please" ;; other) _b='accept s-0000000000000000' ;; approve) _b="approve $_id" ;;
    esac
    be_comment 1 "$_login" "$_b" "$_c" "$_u" "$_t"
  ) &
  steps 'expect No admin answered'
  HARBOR_MEMBER_SUPPORT_WAIT_SECONDS=20
  t_eq "$_what: no session" no "$([ -e "$SE_UP.confirmed" ] && echo yes || echo no)"
  t_hasnt "$_what: upterm host never ran" "$(cat "$SE_UP" 2>/dev/null; echo none)" 'argv [host]'
}

t_section "1 - the request: closed fields only"
se_reset
HARBOR_MEMBER_SUPPORT_WAIT_SECONDS=2
steps 'expect No admin answered'
HARBOR_MEMBER_SUPPORT_WAIT_SECONDS=20
ID="$(se_id)"
t_eq "the title is support and the id" "support $ID" "$(jq -r .title "$BE_ST/issues/1.json")"
t_has "the id is s- and 16 hex" "$(printf '%s' "$ID" | grep -E '^s-[0-9a-f]{16}$')" s-
t_eq "the body is six closed lines" \
  "harbor-support: 1|id: $ID|member: alice|reason: fix|core: 0123456789ab|cc: @fixture-admin|" \
  "$(jq -j .body "$BE_ST/issues/1.json" | tr '\n' '|')"
t_eq "the token came from the secret child, as Bearer" 0 "$(jq -s '[.[] | select(.auth != "Bearer fixture_token_123")] | length' "$BE_ST/log.jsonl")"

t_section "2 - bounded: nobody answers, it closes itself"
t_has "the person is told" "$SE_OUT" 'No admin answered'
t_eq "it exits refused" 1 "$SE_RC"
t_eq "the request is closed" closed "$(jq -r .state "$BE_ST/issues/1.json")"
t_eq "with its closing comment" "closed $ID" "$(se_comments | tail -1)"
t_eq "the record says so" "requested unanswered " "$(se_events)"

se_reset
steps 'expect Waiting for them' 'wait 1' 'hup'
sleep 2
t_eq "closing the window while waiting closes the request" closed "$(jq -r .state "$BE_ST/issues/1.json")"
t_eq "and it reads as the person's no" "requested declined " "$(se_events)"

t_section "3 - an acceptance counts only as an approval would (contracts/hub.md conditions 1 to 4)"
se_reset
se_accept_soon
steps 'expect Start the session? [y/n]' 'send n' 'expect not started'
t_eq "CONTROL: a real admin's comment gets to upterm" 0 "$SE_RC"
t_has "and the person sees who" "$SE_OUT" 'fixture-admin has accepted'
never_accepted "the member's own token" alice accept
never_accepted "an author off the signed list" someone-else accept
never_accepted "a bot" fixture-admin accept 2026-11-07T10:00:00Z 2026-11-07T10:00:00Z Bot
never_accepted "an edited comment" fixture-admin accept 2026-11-07T10:00:00Z 2026-11-07T10:05:00Z
never_accepted "past its ttl by the Date header" fixture-admin accept 2026-11-06T10:00:00Z
never_accepted "a body with more in it" fixture-admin prose
never_accepted "another request's id" fixture-admin other
never_accepted "the approval verb" fixture-admin approve
# The member's login on the signed list still doesn't count: the check is on who wrote it.
se_reset '.approval.approvers += ["alice"]'
HARBOR_MEMBER_SUPPORT_WAIT_SECONDS=3
se_accept_soon alice
steps 'expect No admin answered'
HARBOR_MEMBER_SUPPORT_WAIT_SECONDS=20
t_eq "the member, even on the signed list, can't accept their own" 0 "$(cat "$SE_UP" 2>/dev/null | grep -c '^argv \[host\]' || :)"
se_reset
printf '200 read' > "$BE_ST/perm/fixture-admin"
HARBOR_MEMBER_SUPPORT_WAIT_SECONDS=3
se_accept_soon
steps 'expect No admin answered'
HARBOR_MEMBER_SUPPORT_WAIT_SECONDS=20
t_eq "a read-only admin can't accept (condition 2)" 0 "$(cat "$SE_UP" 2>/dev/null | grep -c '^argv \[host\]' || :)"
se_reset
( _i=0; while [ ! -f "$BE_ST/issues/1.json" ] && [ "$_i" -lt 100 ]; do sleep 0.1; _i=$((_i + 1)); done
  jq '.state = "closed"' "$BE_ST/issues/1.json" > "$T_TMP/i" && cp "$T_TMP/i" "$BE_ST/issues/1.json" ) &
steps 'expect closed the request'
t_eq "an admin closing it is a no (condition 5)" "requested declined " "$(se_events)"

t_section "4 - what upterm is told, from verified policy and nothing else"
se_reset '.support.max_minutes = 30'
se_accept_soon
steps 'expect Start the session? [y/n]' 'send y' 'wait 2.5' 'hup'
sleep 2
ARGV="$(grep '^argv \[host\]' "$SE_UP")"
t_has "--server is the hub relay policy names" "$ARGV" '[--server] [wss://relay.example]'
for _f in '--no-forwarding' '--no-sftp' '--no-exec' ; do t_has "$_f" "$ARGV" "[$_f]"; done
t_has "no way to detach" "$ARGV" '[--escape-char] [none]'
t_has "a named key file" "$ARGV" '[--authorized-keys]'
t_hasnt "never --accept" "$ARGV" 'accept]'
t_hasnt "never a GitHub key source" "$ARGV" 'authorized-user'
t_hasnt "never an unchecked relay" "$ARGV" 'skip-host-key-check'
t_has "only a key made for this session goes to the relay" "$ARGV" '[--private-key]'
t_eq "the keys are the policy's, exactly" "$SE_KEY" "$(cat "$SE_UP.keys")"
t_eq "the relay is pinned for wss on 443, by policy's relay_key" "@cert-authority [relay.example]:443 $SE_RELAY_KEY" "$(cat "$SE_UP.known")"
ENVS="$(grep '^env ' "$SE_UP" | cut -d= -f1 | sort -u | tr '\n' ' ')"
t_hasnt "no UPTERM_ variable reaches it" "$ENVS" 'UPTERM_'
t_hasnt "no ssh agent reaches it" "$ENVS" SSH_AUTH_SOCK

t_section "5 - a planted UPTERM_ACCEPT or config can't skip the question"
se_reset
mkdir -p "$HOME/.config/upterm"; printf 'accept: true\n' > "$HOME/.config/upterm/config.yaml"
se_accept_soon
UPTERM_ACCEPT=true; UPTERM_SKIP_HOST_KEY_CHECK=true; export UPTERM_ACCEPT UPTERM_SKIP_HOST_KEY_CHECK
steps 'expect Start the session? [y/n]' 'send n' 'expect not started'
unset UPTERM_ACCEPT UPTERM_SKIP_HOST_KEY_CHECK
t_hasnt "the variable was dropped" "$(cat "$SE_UP")" 'UPTERM_ACCEPT'
t_hasnt "and the config folder isn't the person's" "$(grep '^env XDG_CONFIG_HOME' "$SE_UP" | head -1)" "$HOME/.config"
t_has "it is the session's own, empty one" "$(grep '^env XDG_CONFIG_HOME' "$SE_UP" | head -1)" '/sup.'

t_section "6 - the session id goes to the board once it starts, and every way out closes it"
se_reset
se_accept_soon
steps 'expect Start the session? [y/n]' 'send y' 'wait 2.5' 'hup'
sleep 2
ID="$(se_id)"
t_eq "the id is posted, whole" "session $ID abc123:bm9kZQ==" "$(se_comments | grep '^session')"
t_eq "and the close follows" "closed $ID" "$(se_comments | tail -1)"
t_eq "the request is closed" closed "$(jq -r .state "$BE_ST/issues/1.json")"
t_eq "upterm was told to stop" yes "$([ -e "$SE_UP.stopped" ] && echo yes || echo no)"
t_eq "the record" "requested accepted started ended " "$(se_events)"
t_eq "the session's folder is gone" '' "$(find "$BE_HS" -maxdepth 1 -name 'sup.*')"

t_section "7 - the person says no at upterm's question"
se_reset
se_accept_soon
steps 'expect Start the session? [y/n]' 'send n' 'expect not started'
t_eq "no session id is posted" '' "$(se_comments | grep '^session' || :)"
t_eq "it closes" closed "$(jq -r .state "$BE_ST/issues/1.json")"
t_eq "the record says declined" "requested accepted declined " "$(se_events)"

t_section "8 - the clock ends it, answered or not"
se_reset
se_accept_soon
HARBOR_MEMBER_SUPPORT_LIMIT_SECONDS=3; export HARBOR_MEMBER_SUPPORT_LIMIT_SECONDS; steps 'expect Start the session? [y/n]' 'send y' 'expect time limit was reached'; unset HARBOR_MEMBER_SUPPORT_LIMIT_SECONDS
t_eq "it stopped the session" yes "$([ -e "$SE_UP.stopped" ] && echo yes || echo no)"
t_eq "the record says timed out" "requested accepted started timed-out " "$(se_events)"
t_eq "and the board is closed" closed "$(jq -r .state "$BE_ST/issues/1.json")"
se_reset
se_accept_soon
HARBOR_MEMBER_SUPPORT_LIMIT_SECONDS=2; export HARBOR_MEMBER_SUPPORT_LIMIT_SECONDS; steps 'expect Start the session? [y/n]' 'expect time limit was reached'; unset HARBOR_MEMBER_SUPPORT_LIMIT_SECONDS
t_eq "a question nobody answers ends too" "closed $(se_id)" "$(se_comments | tail -1)"

t_section "9 - killed outright, the lookout still ends it"
se_reset
se_accept_soon
printf '%s\n' 'expect Type update' 'send fix' 'expect the word allow' 'send allow' 'expect Start the session? [y/n]' 'send y' 'wait 2' > "$SE_STEPS"
python3 "$T_ROOT/tests/hub/fixtures/terminal_run.py" "$SE_STEPS" "$T_TMP/transcript" -- sh -c 'printf "%s" "$$" > "$1"; exec sh "$2"' sh "$T_TMP/main.pid" "$SE_SUPPORT" &
_pty=$!
_i=0; while [ ! -e "$SE_UP.confirmed" ] && [ "$_i" -lt 150 ]; do sleep 0.1; _i=$((_i + 1)); done
sleep 1
kill -9 "$(cat "$T_TMP/main.pid")" 2>/dev/null
_i=0; while [ "$(jq -r .state "$BE_ST/issues/1.json")" != closed ] && [ "$_i" -lt 60 ]; do sleep 0.2; _i=$((_i + 1)); done
t_eq "the request is closed by the lookout" closed "$(jq -r .state "$BE_ST/issues/1.json")"
t_eq "the session was stopped" yes "$([ -e "$SE_UP.stopped" ] && echo yes || echo no)"
wait "$_pty" 2>/dev/null || :

t_section "10 - only state changes are recorded"
t_eq "every support event is three closed fields" 0 \
  "$(jq -s '[.[] | select(.kind == "support") | select((keys - ["v","kind","ts","member","id","reason","outcome"]) != [])] | length' "$BE_HS/outbox.jsonl")"
t_eq "the board holds no terminal text" 0 "$(se_comments | grep -cvE '^(accept|session|closed) s-' || :)"

be_down
t_done
