#!/usr/bin/env sh
# member-session.sh (harbor#1278) — the managed SessionStart and SessionEnd hook on a member laptop. Format: contracts/hub.md.
#   start  install a missing prerequisite (member-prereqs.sh), sync the policy and hub packs (bin/hub.sh sync), check the floor (member-integrity.sh check), say what an approval brings
#          (hub-approval.sh note), count a session start and send events (hub-events.sh send builds the heartbeat itself)
#   end    count a session end, send events
# The event comes from the first argument (start | end), else the hook's JSON on stdin. It never blocks a session: every step is
# bounded and best effort, the exit is always 0, and a failed integrity check is recorded as a `check` event and said in the
# session's context. On a box that is not a member it does nothing.
set -eu
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH= cd -- "$HERE" && pwd -P)"
. "$HERE/library-log.sh"
. "$HERE/library-hub.sh"
# A managed hook entry, so env goes first (harbor#1278). With no marker there is no managed hook, only a test's seams.
FAULT=0
if hub_marker; then hub_env_clean || FAULT=1; fi
log_init member-session
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh; stdout is the hook's reply, so the log goes to stderr
LOG_FD=2

case "${1:-}" in -h|--help) awk 'NR < 2 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;; esac
EVENT="${1:-}"
if [ -z "$EVENT" ] && [ ! -t 0 ]; then
  EVENT="$(jq -r '.hook_event_name // empty' 2>/dev/null | tr 'A-Z' 'a-z' | sed 's/^session//')" || EVENT=''
fi
TIMEOUT="${HARBOR_HUB_TIMEOUT:-8}"
case "$TIMEOUT" in ''|*[!0-9]*) TIMEOUT=8 ;; esac

# The dispatcher refuses every call on this fault, so the session says why, once, at its start. Nothing else here can run: the facts are gone.
if [ "$FAULT" -eq 1 ]; then
  case "$EVENT" in
    start|startup|resume|clear|compact)
      jq -n --arg c "Harbor: this laptop's member settings could not be read, so every step will be stopped. Your admin needs to look at this laptop." \
        '{systemMessage: $c, hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}' 2>/dev/null || : ;;
  esac
  exit 0
fi
hub_is_member || exit 0

# bounded <seconds> <command...>: no timeout(1) on BSD. A hung network must not hold a session.
bounded() {
  _bsec="$1"; shift
  "$@" & _bp=$!
  ( sleep "$_bsec"; pkill -P "$_bp" 2>/dev/null; kill "$_bp" 2>/dev/null ) > /dev/null 2>&1 < /dev/null & _bw=$!
  _brc=0; wait "$_bp" 2>/dev/null || _brc=$?
  kill "$_bw" 2>/dev/null || :
  wait "$_bw" 2>/dev/null || :
  return "$_brc"
}
ev() { if [ -f "$HERE/hub-events.sh" ]; then sh "$HERE/hub-events.sh" record "$@" > /dev/null 2>&1 || :; fi; }
send() { if [ -f "$HERE/hub-events.sh" ]; then bounded "$TIMEOUT" sh "$HERE/hub-events.sh" send > /dev/null 2>&1 || :; fi; }

NOTES=''
note() { NOTES="${NOTES:+$NOTES }$1"; }
AGENT_NOTE=''

# W5: the helper is the one root path a member has, so this is whether it works from a hook at all. Root's process can't be killed from here,
# so the wait ends and the helper is left to finish: a file says how it ended, and a session is never held by it.
PREREQ_SUDO=/usr/bin/sudo
PREREQ_WAIT=90
PREREQ_OS="$(uname -s)"   # the list's Linux runtime is never on macOS, which has no package manager to call: its tools are the install's check, and IT's
prereqs_missing() {
  [ -f "$HERE/member-prereqs.txt" ] || return 0
  for _pt in $(awk '/^[[:space:]]*#/ || !NF || $1 == "-" { next } { print $1 }' "$HERE/member-prereqs.txt"); do
    command -v "$_pt" > /dev/null 2>&1 || printf '%s ' "$_pt"
  done
}
prereqs() {
  [ "$PREREQ_OS" != Darwin ] || return 0
  _pm="$(prereqs_missing)"; [ -n "$_pm" ] || return 0
  _pd="$(mktemp -d "${TMPDIR:-/tmp}/harbor-prereqs.XXXXXX")" || _pd=''
  if [ -n "$_pd" ]; then
    ( _pr=0; "$PREREQ_SUDO" -n /bin/sh "$HERE/member-prereqs.sh" > /dev/null 2>&1 < /dev/null || _pr=$?; printf '%s\n' "$_pr" > "$_pd/rc" ) > /dev/null 2>&1 &
    _pw=0
    while [ ! -s "$_pd/rc" ] && [ "$_pw" -lt "$PREREQ_WAIT" ]; do sleep 1; _pw=$((_pw + 1)); done
  fi
  if [ -n "$_pd" ] && [ ! -s "$_pd/rc" ]; then
    note "Harbor: these tools are missing and are still being installed: ${_pm% }. Some steps may fail until that finishes."
    return 0
  fi
  [ -z "$_pd" ] || rm -rf "$_pd"
  _pm="$(prereqs_missing)"; [ -n "$_pm" ] || return 0
  ev check check=member-prereqs outcome=failed
  note "Harbor: these tools are missing and could not be installed: ${_pm% }. Some steps may fail. Tell IT."
}
# W10: a WSL session opens in the home folder and no setting moves it, so the agent is told where work belongs. Whether Desktop keeps a chosen folder is the Windows test.
home_note() {
  [ -d "$HOME/port" ] && [ "$(pwd -P)" = "$(CDPATH='' cd -- "$HOME" && pwd -P)" ] || return 0
  AGENT_NOTE="This session opened in the home folder. Work belongs in ~/port: read, create and change files there, and run commands from there."
}

# harbor#1278 (yard start rule): each git checkout directly under ~/port that harbor does not govern, said at every session start. It lives here, in
# the managed hook, because allowManagedHooksOnly keeps the user tier's context rules from running on this laptop, and the member can't remove this one.
# The list is scope-repo-sources.sh --not-adopted's (the same disk scan the Mac's rule reads); a member registers a project with harbor hub project register.
repos_note() {
  [ -f "$HERE/scope-repo-sources.sh" ] || return 0
  _rd="$(mktemp -d "${TMPDIR:-/tmp}/member-repos.XXXXXX" 2>/dev/null)" || return 0
  _rr=0
  bounded 6 sh -c 'sh "$1" --not-adopted > "$2/list" 2>/dev/null' sh "$HERE/scope-repo-sources.sh" "$_rd" > /dev/null 2>&1 || _rr=$?
  # A list that can't be made (a registry the member broke, a scan that timed out) must not read as nothing to say: every git checkout is then named.
  if [ "$_rr" -ne 0 ] || [ ! -f "$_rd/list" ]; then
    _pr="$(sh "$HERE/scope-roots.sh" --port-root 2>/dev/null)" || _pr=''
    [ -n "$_pr" ] || _pr="$HOME/port"
    for _d in "$_pr"/*/; do
      [ -e "${_d}.git" ] || continue
      { [ -f "${_d}bin/harbor" ] && [ -f "${_d}contracts/roots.tsv" ]; } && continue
      _b="${_d%/}"; _b="${_b##*/}"; [ "$_b" = harbor-private ] && continue
      printf '%s\t-\tunregistered\n' "$_b"
    done > "$_rd/list"
  fi
  _rn="$(awk -F'\t' 'NF >= 3 && $1 ~ /^[A-Za-z0-9][A-Za-z0-9._-]*$/ { printf "%s%s", (n++ ? ", " : ""), $1 }' "$_rd/list" 2>/dev/null)" || _rn=''
  rm -rf "$_rd"
  [ -n "$_rn" ] || return 0
  note "Harbor: these folders in ~/port are git repos Harbor does not govern yet: $_rn. Ask your agent to register each one."
  AGENT_NOTE="${AGENT_NOTE:+$AGENT_NOTE }Repos under ~/port that Harbor does not govern yet (company rule): $_rn. Tell the person, and register each with: sh ~/port/harbor/bin/harbor hub project register <name>. Registering writes into ~/port/harbor-private, so leave the run to them."
}

start() {
  # Fetch once. A refusal or an unreachable hub changes nothing and is not a session problem. Only a verified revocation leaves.
  _frc=0; sh "$HERE/hub-sync.sh" fetch > /dev/null 2>&1 || _frc=$?
  # 3 is an unreachable hub (a 401, a 403 and a dead network look alike, and none is a revocation): the session starts and the last good packs stay, and a finding
  # waits in the outbox until the hub can be heard again (harbor#1278).
  [ "$_frc" -ne 3 ] || ev check check=hub-fetch outcome=failed
  if [ "$(sh "$HERE/hub-sync.sh" state 2>/dev/null)" = revoked ]; then
    if sh "$HERE/hub.sh" leave --apply --live > /dev/null 2>&1; then
      note "Harbor: your login was revoked on the hub, so the hub packs and policy were dropped from this laptop. IT removes the managed files."
    else
      ev check check=hub-leave outcome=failed
      note "Harbor: your login was revoked on the hub, but the hub packs and policy could not all be dropped from this laptop. The next session tries again. Tell IT."
    fi
    return 0
  fi
  # A failure here is a pack or hook this policy names and the laptop lacks: every call may then be refused, so it is said, not hidden (#1278).
  if ! sh "$HERE/hub.sh" sync --no-fetch --live > /dev/null 2>&1; then
    ev check check=hub-sync outcome=failed
    note "Harbor: the hub's packs or hooks could not be brought up to date, so steps may be refused. Tell IT."
  fi
  # The floor. A missing verifier on a member box is a failed check, not a pass.
  _ok=0
  if [ -f "$HERE/member-integrity.sh" ]; then sh "$HERE/member-integrity.sh" check > /dev/null 2>&1 && _ok=1 || _ok=0; fi
  if [ "$_ok" -ne 1 ]; then
    ev check check=floor-integrity outcome=failed
    note "Harbor: the integrity check of the managed floor FAILED, so the limits on this laptop may not be the ones IT installed. Tell IT before relying on them."
  fi
  # An approval that arrived, or a token that ended, is told to the person once. The heartbeat is built by the sender, not here.
  if [ -f "$HERE/hub-approval.sh" ]; then
    _an="$(sh "$HERE/hub-approval.sh" note SessionStart 2>/dev/null | jq -r '.systemMessage // empty' 2>/dev/null)" || _an=''
    [ -z "$_an" ] || note "$_an"
  fi
  repos_note
  send
}

main() {
  # First, and on an unreadable event too: with jq itself missing, the event can't be read and every step below needs it.
  [ "$EVENT" = end ] || prereqs
  # D9: a count of session starts and ends per day (D4), never which session. A resume or compact is a SessionStart too, and counts.
  case "$EVENT" in
    start|startup|resume|clear|compact) ev session outcome=started count=1; home_note; start ;;
    end) ev session outcome=ended count=1; send ;;
    *) log_note "no session event given: nothing to do" ;;
  esac
  [ "$EVENT" != end ] && [ -n "$NOTES$AGENT_NOTE" ] || return 0
  if command -v jq > /dev/null 2>&1; then
    jq -n --arg n "$NOTES" --arg c "${NOTES:+$NOTES }$AGENT_NOTE" \
      '(if $n != "" then {systemMessage: $n} else {} end) + {hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}' 2>/dev/null || :
  else
    printf '{"systemMessage":"%s"}\n' "$(printf '%s' "$NOTES" | sed 's/[\\"]/\\&/g')"
  fi
}
main || :
log_end || :
exit 0
