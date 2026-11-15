#!/usr/bin/env sh
# member-support.sh (harbor#1278) — a person on a member laptop asks an admin for help, and watches them work. Format: contracts/hub.md, "Remote support".
#   sh member-support.sh     run by a person, from a terminal or the Harbor Support shortcut. It asks everything it needs on screen
# Exit 0 finished, 1 refused or not started, 2 usage, 3 the board could not be reached.
#
# Consent runs through every step: the person types `allow` after being told what the admin can do, the admin accepts on the board, the
# person sees who and answers upterm's own question. Nothing here starts on its own, and nothing outlives this run: no autostart, no
# service, and the session's keys and records sit in one folder that goes when it ends. Only state changes are recorded, never terminal content.
# upterm reads UPTERM_* and a user-writable config file, and either can turn on --accept, so it runs with a scrubbed environment and an empty config.
# HARBOR_MEMBER_SUPPORT_POLL_SECONDS, HARBOR_MEMBER_SUPPORT_WAIT_SECONDS and HARBOR_MEMBER_SUPPORT_LIMIT_SECONDS are test seams, dead beside the member marker.
set -eu
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH='' cd -- "$HERE" && pwd)"
. "$HERE/library-hub.sh"
. "$HERE/library-log.sh"
. "$HERE/library-board.sh"
LOG_FD=2
log_init member-support

WAIT_SECONDS=1800; POLL_SECONDS=15; SESSION=hs
UPTERM="$HERE/upterm"
# W4: the managed settings sit one above the root on every platform today.
SETTINGS="${HERE%/*}/../managed-settings.json"

say() { printf '%s\n' "$@"; }
stop_here() { say '' "$1"; [ -z "${2:-}" ] || say "$2"; exit "${3:-1}"; }

case "${1:-}" in
  --help|-h) sed -n '2,3p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  '') ;;
  *) sed -n '2,3p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac

# Started by a person, or not at all. The agent's shell has no terminal, and this says why a person's slip was refused.
[ -t 0 ] && [ -t 1 ] || stop_here 'This needs a real terminal window, because you have to watch it and answer it.' 'Open the Harbor Support shortcut.'
if support_in_agent; then stop_here 'This can only be started by you, outside Claude Code.' 'Open the Harbor Support shortcut, or a terminal of your own.'; fi
[ -z "${UPTERM_SESSION_NAME:-}" ] || stop_here 'You are already inside a support session.'

# A person's terminal has no managed env, so on a member box member.conf says who this is, through hub_env_clean (contracts/hub.md). No env value can move that.
if [ -e "$HERE/harbor-member-mode" ]; then
  hub_env_clean || stop_here "This laptop's member settings could not be read." 'Ask IT.'
else
  WAIT_SECONDS="${HARBOR_MEMBER_SUPPORT_WAIT_SECONDS:-$WAIT_SECONDS}"
  POLL_SECONDS="${HARBOR_MEMBER_SUPPORT_POLL_SECONDS:-$POLL_SECONDS}"
fi
MEMBER="${HARBOR_MEMBER_LOGIN:-}"; HUB="${HARBOR_HUB_REPO:-}"
hub_is_member && valid_login "$MEMBER" && valid_repo "$HUB" || stop_here 'This computer is not set up as a member of a company hub.' 'Ask IT.'

HS="$(hub_state_dir)"
(umask 077; mkdir -p "$HS")
find "$HS" -maxdepth 1 -type d -name 'sup.*' -mmin +300 -exec rm -rf {} + 2>/dev/null || :
# Under the state folder, which the agent can't write, so nothing can swap a key file between here and the host. Short: a socket path has a limit.
S="$HS/sup.$$"
(umask 077; mkdir -p "$S/w" "$S/config" "$S/state" "$S/run")
W="$S/w"

ID=''; ISSUE=''; REASON=''; LOOKOUT=''; MAIN=$$
event() { sh "$HERE/hub-events.sh" record support "id=$ID" "reason=$REASON" "outcome=$1" </dev/null >/dev/null 2>&1 || :; }

# up: upterm, with nothing from this environment that could change what it does. UP_PID names a file for its pid, which lets the clock end
# a question nobody answers: the foreground process has to keep the terminal, so it can't simply be put in the background.
UP_PID=/dev/null
up() {
  sh -c 'printf "%s" "$$" > "$1"; shift; exec "$@"' sh "$UP_PID" env -i HOME="$HOME" USER="${USER:-$MEMBER}" LOGNAME="${LOGNAME:-$MEMBER}" \
    TERM="${TERM:-xterm-256color}" PATH=/usr/bin:/bin LANG="${LANG:-C.UTF-8}" \
    XDG_CONFIG_HOME="$S/config" XDG_STATE_HOME="$S/state" XDG_RUNTIME_DIR="$S/run" "$UPTERM" "$@"
}

host_gone() {
  [ -e "$S/host.pid" ] || return 0
  up session stop "$SESSION" </dev/null >/dev/null 2>&1 || :
  _hp="$(cat "$S/host.pid" 2>/dev/null)" || _hp=''
  case "$_hp" in ''|*[!0-9]*) ;; *) kill "$_hp" 2>/dev/null || : ;; esac
}

# The one way out, reached by the main run or by the lookout if the main run was killed. The mark makes it run once.
finish() {
  mkdir "$S/finished" 2>/dev/null || return 0
  [ -z "$LOOKOUT" ] || kill "$LOOKOUT" 2>/dev/null || :
  host_gone
  if [ -n "$ISSUE" ]; then
    if [ -e "$S/asked-limit" ]; then event timed-out
    elif [ -e "$S/started" ]; then event ended
    elif [ -e "$S/accepted" ]; then event declined
    elif [ -e "$S/filed" ] && [ ! -e "$S/recorded" ]; then event declined; fi
    jq -n --arg b "closed $ID" '{body: $b}' > "$W/closed.json" 2>/dev/null && board POST "/repos/$HUB/issues/$ISSUE/comments" "$W/closed.json" || :
    printf '{"state":"closed"}' > "$W/close.json" 2>/dev/null && board PATCH "/repos/$HUB/issues/$ISSUE" "$W/close.json" || :
    sh "$HERE/hub-events.sh" send </dev/null >/dev/null 2>&1 || :
  fi
  rm -rf "$S"
}
trap 'finish' EXIT
trap 'exit 130' INT HUP TERM

policy_read || stop_here 'The company settings on this computer could not be read.' 'Ask IT.'
sh "$HERE/hub-sync.sh" fetch </dev/null >/dev/null 2>&1 || :
policy_read || stop_here 'The company settings on this computer could not be read.' 'Ask IT.'
[ "$(sh "$HERE/hub-sync.sh" state 2>/dev/null)" != revoked ] || stop_here 'This computer has left the company hub.' 'Ask IT.'
jq -e '.support | type == "object"' "$POL" >/dev/null 2>&1 || stop_here 'Remote support is not turned on for your company.'
[ -x "$UPTERM" ] || stop_here 'The support program is not installed on this computer.' 'Ask IT to run the install again.'
# Only the company's own relay: a public one could read the session and claim any key joined (contracts/hub.md, "What the relay sees").
_rc=0; support_relay "$POL" || _rc=$?
case "$_rc" in
  0) ;;
  2) stop_here 'The company settings name the public support service, which is never used: it could read the session.' 'Tell your admin.' ;;
  *) stop_here 'Remote support is off until your company runs its own support service.' 'Tell your admin.' ;;
esac
# The relay must already be closed to the agent. A move in policy needs the install run again, and until then this refuses (contracts/hub.md).
jq -e --arg h "$RHOST" '(.sandbox.network.deniedDomains // []) | index($h) != null' "$SETTINGS" >/dev/null 2>&1 \
  || stop_here 'Remote support moved to a new service, and this computer has not caught up.' 'Ask IT to run the install again.'

MINUTES="$(jq -r '.support.max_minutes // 60' "$POL")"
LIMIT=$((MINUTES * 60))
[ -e "$HERE/harbor-member-mode" ] || LIMIT="${HARBOR_MEMBER_SUPPORT_LIMIT_SECONDS:-$LIMIT}"

# Each key is proved one by one, so a line ssh-keygen can't read never reaches the file upterm trusts.
jq -r '.support.keys[]' "$POL" > "$W/keys"
: > "$S/authorized_keys"
while IFS= read -r _key; do
  printf '%s\n' "$_key" > "$W/one.pub"
  ssh-keygen -l -f "$W/one.pub" >/dev/null 2>&1 || stop_here 'The company settings hold a key that can not be read.' 'Tell your admin.'
  printf '%s\n' "$_key" >> "$S/authorized_keys"
done < "$W/keys"
printf '@cert-authority %s %s\n' "$RPATTERN" "$RKEY" > "$S/known_hosts"
# A key for this session alone, so none of the person's own keys is offered to the relay.
ssh-keygen -q -t ed25519 -N '' -C harbor-support -f "$S/session-key" </dev/null

say '' 'REMOTE SUPPORT' '' \
  'This asks your admin to help you on this computer. If they accept and you say yes:' '' \
  '  - Your admin gets a terminal here, working as you.' \
  '  - They can read and change anything your account can: your files, your documents,' \
  '    anything saved under your name. Close anything private before you start.' \
  '  - You see everything they type, in this window, as it happens.' \
  "  - It ends when you close this window, or after $MINUTES minutes, whichever comes first." \
  "  - They can't change the company's safety settings, because those aren't yours to change." \
  '  - The session travels through your company'"'"'s own support service, which can read' \
  '    what passes through it. Don'"'"'t show passwords on screen.' \
  '' 'Nothing is listening on this computer now, and nothing stays after it ends.' ''

printf 'What do you need? Type update, fix or question: '
IFS= read -r REASON || exit 1
case "$REASON" in update|fix|question) ;; *) stop_here 'Nothing was sent. Run this again and type one of the three words.' ;; esac
printf 'To ask your admin, type the word allow: '
IFS= read -r _yes || exit 1
[ "$_yes" = allow ] || stop_here 'Nothing was sent, and nothing was started.'

ID="s-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
CORE="$(jq -r '.core.commit[0:12]' "$POL")"
{
  printf 'harbor-support: 1\nid: %s\nmember: %s\nreason: %s\ncore: %s\ncc:' "$ID" "$MEMBER" "$REASON" "$CORE"
  # An @mention is the only mail a Read-role token can cause (R18).
  jq -r --arg m "$MEMBER" '.approval.approvers[] | select(ascii_downcase != ($m | ascii_downcase))' "$POL" \
    | while IFS= read -r _a; do printf ' @%s' "$_a"; done
  printf '\n'
} > "$W/issue-body"
grep -q '^cc: @' "$W/issue-body" || stop_here 'Your company has no admin who could answer this.' 'Tell IT.'
jq -n --arg t "support $ID" --rawfile b "$W/issue-body" '{title: $t, body: $b}' > "$W/create.json"
_rc=0; board POST "/repos/$HUB/issues" "$W/create.json" || _rc=$?
{ [ "$_rc" = 0 ] && status_is 201; } || stop_here 'Your admin could not be told just now.' 'Check your connection, then try again.' 3
ISSUE="$(jq -r .number "$W/body")"
case "$ISSUE" in ''|*[!0-9]*) ISSUE=''; stop_here 'Your admin could not be told just now.' 'Try again later.' 3 ;; esac
: > "$S/filed"
event requested

# accepted: 0 an admin's comment counts, 1 not yet, 3 down, 4 the request was closed. Conditions: contracts/hub.md, "The board".
accepted() {
  _rc=0; board_find_issue "support $ID" "$ISSUE" || _rc=$?
  [ "$_rc" = 0 ] || return "$_rc"
  [ "$(jq -r .state "$W/issue.json")" = open ] || return 4
  support_issue_valid "$W/issue.json" "$ID" "$MEMBER" || return 1
  board_signed_comment "$ISSUE" "$MEMBER" accept "$ID" '[]'
}

say '' "Your admin has been told (request $ID). Waiting for them to accept. Keep this window open, or close it to cancel."
_until=$(($(date +%s) + WAIT_SECONDS))
while :; do
  _rc=0; accepted || _rc=$?
  [ "$_rc" != 0 ] || break
  if [ "$_rc" = 4 ]; then
    event declined; : > "$S/recorded"
    stop_here 'Your admin closed the request.' 'Nothing was started.'
  fi
  if [ "$(date +%s)" -ge "$_until" ]; then
    event unanswered; : > "$S/recorded"
    stop_here 'No admin answered in time, so the request was closed.' 'Nothing was started.'
  fi
  sleep "$POLL_SECONDS"
done
ADMIN="$BC_LOGIN"
: > "$S/accepted"
event accepted

# The person's last word is upterm's own question. The lookout watches the clock and posts the session once it starts.
say '' "$ADMIN has accepted, and will get a terminal as you for up to $MINUTES minutes." \
  'You will now be asked "Start the session?". Press y to let them in, or n to stop.' \
  'Everything they do will appear in this window. To end it at any time, close this window.' ''

lookout() {
  trap '' HUP INT
  W="$S/lookout"; mkdir -p "$W"
  _end=$(($(date +%s) + LIMIT)); _posted=0
  while :; do
    [ -d "$S" ] || exit 0
    if ! kill -0 "$MAIN" 2>/dev/null; then finish; exit 0; fi
    if [ "$(date +%s)" -ge "$_end" ]; then
      : > "$S/asked-limit"
      host_gone
      exit 0
    fi
    if [ "$_posted" = 0 ]; then
      _sid="$(up session info "$SESSION" -o json </dev/null 2>/dev/null \
        | jq -r 'select(.startConfirmed == true and .status == "ready") | .joinCommand | capture("://(?<u>[^@ ]+)@").u' 2>/dev/null)" || _sid=''
      case "$_sid" in
        ''|*[!A-Za-z0-9+/=:_-]*) ;;
        *)
          if [ ! -e "$S/started" ]; then : > "$S/started"; event started; fi
          jq -n --arg b "session $ID $_sid" '{body: $b}' > "$W/session.json"
          _rc=0; board POST "/repos/$HUB/issues/$ISSUE/comments" "$W/session.json" || _rc=$?
          if [ "$_rc" = 0 ] && status_is 201; then _posted=1; fi ;;
      esac
    fi
    sleep 1
  done
}
( lookout ) </dev/null >/dev/null 2>&1 &
LOOKOUT=$!

SH=/bin/sh
case "${SHELL:-}" in /bin/*|/usr/bin/*) [ ! -x "$SHELL" ] || SH="$SHELL" ;; esac
# --no-exec keeps a guest's commands in this window, and --escape-char none takes away ~. : a detached session would run on unseen.
UP_PID="$S/host.pid"
up host --server "$RELAY" --known-hosts "$S/known_hosts" --private-key "$S/session-key" --authorized-keys "$S/authorized_keys" \
  --no-forwarding --no-sftp --no-exec --escape-char none --name "$SESSION" \
  -- /usr/bin/env -u XDG_CONFIG_HOME -u XDG_STATE_HOME -u XDG_RUNTIME_DIR "$SH" -l || :
UP_PID=/dev/null
if [ -e "$S/asked-limit" ]; then say '' 'The time limit was reached, so the session ended.'
elif [ -e "$S/started" ]; then say '' 'The session has ended. Nobody can reach this computer through it now.'
else say '' 'The session was not started.'; fi
exit 0
