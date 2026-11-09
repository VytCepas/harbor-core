#!/usr/bin/env sh
# hub-support.sh (harbor#1278; `harbor hub support`) — the admin's side of remote support. Format: contracts/hub.md, "Remote support".
#   harbor hub support list [--hub OWNER/NAME]                       the open requests: id, member, reason, whether a session is up
#   harbor hub support accept <id> [--hub OWNER/NAME]                accept on the board, with your own gh; the member is asked next, on their screen
#   harbor hub support connect <id> [--hub OWNER/NAME] [--key FILE]  join the session with your own key, from a terminal of your own
# Exit 0 done, 1 refused, 2 usage, 3 GitHub could not be reached.
# Runs on the admin's box as the admin. What the board says is member content, so an id or a session string passes a closed shape before use.
set -eu
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH='' cd -- "$HERE" && pwd)"
. "$HERE/library-hub.sh"
. "$HERE/library-log.sh"
. "$HERE/library-board.sh"
LOG_FD=2
log_init hub-support

usage() { sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; }
die() { log_fail "$1"; if [ -n "${2:-}" ]; then log_fix "$2"; else log_nofix 'docs/how-to/member-support.md'; fi; log_end || :; exit "${3:-1}"; }
valid_id() {
  [ "${#1}" = 18 ] || return 1
  case "$1" in s-*) ;; *) return 1 ;; esac
  case "${1#s-}" in *[!0123456789abcdef]*) return 1 ;; esac
}

verb="${1:-}"; [ $# -eq 0 ] || shift
case "$verb" in
  list|accept|connect) ;;
  -h|--help|help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
ID=''; KEY=''; HUB="${HARBOR_HUB_REPO:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --hub) [ $# -ge 2 ] || die '--hub needs owner/name' '' 2; HUB="$2"; shift ;;
    --key) [ $# -ge 2 ] || die '--key needs a private key file' '' 2; KEY="$2"; shift ;;
    -*) die "unknown flag: $1" '' 2 ;;
    *) [ -z "$ID" ] || die "one id, not two: $1" '' 2; ID="$1" ;;
  esac
  shift
done
# A member's own token can't accept and its login can't count, so this verb has nothing to do on a member box.
! hub_is_member || die 'this is the admin side: on a member laptop, open Harbor Support instead'
valid_repo "$HUB" || die 'no hub named: pass --hub owner/name' 'harbor hub support list --hub owner/name' 2
[ "$verb" = list ] || valid_id "$ID" || die "'$ID' is not a support id" 'harbor hub support list' 2
command -v gh >/dev/null 2>&1 || die 'gh is missing, and this uses your own GitHub login' "$(pkg_hint gh)"

W="$(mktemp -d "${TMPDIR:-/tmp}/hub-support.XXXXXX")"
trap 'rm -rf "$W"' EXIT
trap 'exit 130' INT HUP TERM

open_issues() { # -> $W/issues.json: the open support requests, closed title shape only
  gh api --paginate "repos/$HUB/issues?state=open&per_page=100" > "$W/raw.json" 2>/dev/null || die 'GitHub could not be reached' 'gh auth status' 3
  jq -s '[.[][] | select((.title // "") | test("^support s-[0-9a-f]{16}$")) | select(has("pull_request") | not)]' "$W/raw.json" > "$W/issues.json"
}
# the_issue: $W/issue.json, the open request for ID, its body proved against its own opener. MEMBER and NUM are set.
the_issue() {
  open_issues
  jq -e --arg t "support $ID" '[.[] | select(.title == $t)] | .[0] // error("none")' "$W/issues.json" > "$W/issue.json" 2>/dev/null || die "no open request $ID" 'harbor hub support list'
  MEMBER="$(jq -r '.user.login // ""' "$W/issue.json")"; NUM="$(jq -r .number "$W/issue.json")"
  valid_login "$MEMBER" || die 'the request has no usable author'
  case "$NUM" in ''|*[!0-9]*) die 'the request has no usable number' ;; esac
  support_issue_valid "$W/issue.json" "$ID" "$MEMBER" || die "the request $ID is not in the closed format, so it was not written by harbor" 'read it on the board'
}
comments() { # -> $W/comments.json
  gh api --paginate "repos/$HUB/issues/$1/comments?per_page=100" > "$W/raw.json" 2>/dev/null || die 'GitHub could not be reached' 'gh auth status' 3
  jq -s 'add // []' "$W/raw.json" > "$W/comments.json"
}
session_of() { # <issue> <member> -> the session string the member posted, never edited, in a closed shape
  comments "$1"
  jq -r --arg want "session $ID " --arg m "$2" '
    [.[] | select((.user.login // "" | ascii_downcase) == ($m | ascii_downcase) and .updated_at == .created_at)
         | (.body // "") | select(startswith($want)) | .[($want | length):]
         | select(test("^[A-Za-z0-9+/=:_-]{1,200}$") and (test("[[:cntrl:]]") | not))] | last // empty' "$W/comments.json"
}

cmd_list() {
  open_issues
  _n="$(jq length "$W/issues.json")"
  _i=0; _shown=0
  while [ "$_i" -lt "$_n" ]; do
    jq --argjson i "$_i" '.[$i]' "$W/issues.json" > "$W/issue.json"
    _i=$((_i + 1))
    ID="$(jq -r '.title[8:]' "$W/issue.json")"; MEMBER="$(jq -r '.user.login // ""' "$W/issue.json")"; NUM="$(jq -r .number "$W/issue.json")"
    valid_login "$MEMBER" && support_issue_valid "$W/issue.json" "$ID" "$MEMBER" || continue
    _reason="$(jq -r '.body | capture("reason: (?<r>[a-z]+)").r' "$W/issue.json")"
    _state=waiting
    [ -z "$(session_of "$NUM" "$MEMBER")" ] || _state=session-up
    printf '%s\t%s\t%s\t%s\n' "$ID" "$MEMBER" "$_reason" "$_state"
    _shown=1
  done
  [ "$_shown" = 1 ] || printf 'no open support requests\n'
}

cmd_accept() {
  the_issue
  jq -n --arg b "accept $ID" '{body: $b}' > "$W/accept.json"
  gh api --method POST "repos/$HUB/issues/$NUM/comments" --input "$W/accept.json" >/dev/null 2>&1 || die 'the comment was not posted' 'gh auth status' 3
  log_ok "accepted $ID for $MEMBER. They are asked next, on their own screen, and their session id appears here once they say yes"
  log_note "then: harbor hub support connect $ID"
  log_end || :
}

# policy_from_hub -> $W/policy.json: the signed policy, proved against the hub's own signers file. The key list and the relay come from here.
policy_from_hub() {
  for _f in policy.json policy.json.sig hub-signers; do
    gh api -H 'Accept: application/vnd.github.raw+json' "repos/$HUB/contents/$_f" > "$W/$_f" 2>/dev/null || die "could not read $_f from $HUB" 'gh auth status' 3
  done
  ssh-keygen -Y verify -f "$W/hub-signers" -I hub -n harbor-hub -s "$W/policy.json.sig" < "$W/policy.json" >/dev/null 2>&1 \
    || die 'the hub policy does not verify against its hub-signers' 'harbor hub check'
  sh "$HERE/hub-format.sh" policy "$W/policy.json" 2>/dev/null || die 'the hub policy fails its format' 'harbor hub check'
  jq -e '.support | type == "object"' "$W/policy.json" >/dev/null 2>&1 || die 'support is off: the hub policy has no support key' 'docs/how-to/member-support.md'
}

cmd_connect() {
  # The same two rules as the member's side: a session is a person's act, so an agent on the admin's box doesn't get one either.
  [ -t 0 ] && [ -t 1 ] || die 'connect needs a real terminal' 'run it in a terminal of your own'
  if support_in_agent; then die 'connect is for a person, outside Claude Code' 'run it in a terminal of your own'; fi
  command -v upterm >/dev/null 2>&1 || die 'upterm is missing on this box' 'install the release named in contracts/support-upterm.tsv'
  [ -z "$KEY" ] || [ -r "$KEY" ] || die "--key: can't read $KEY"
  the_issue
  _sid="$(session_of "$NUM" "$MEMBER")"
  [ -n "$_sid" ] || die "no session yet for $ID: the member hasn't said yes" "harbor hub support list --hub $HUB"
  policy_from_hub
  support_relay "$W/policy.json" || die 'support is off: the hub policy names no relay of its own, with its key' 'docs/how-to/member-support.md, the relay'
  printf '@cert-authority %s %s\n' "$RPATTERN" "$RKEY" > "$W/known_hosts"
  _a="${RELAY#*://}"
  set -- join --known-hosts "$W/known_hosts"
  [ -z "$KEY" ] || set -- "$@" -i "$KEY"
  log_note "joining $MEMBER's session. Everything you type is on their screen. ~. leaves"
  _rc=0; upterm "$@" "${RELAY%%://*}://$_sid@$_a" || _rc=$?
  return "$_rc"
}

case "$verb" in
  list) cmd_list ;;
  accept) [ -n "$ID" ] || die 'accept needs an id' 'harbor hub support list' 2; cmd_accept ;;
  connect) [ -n "$ID" ] || die 'connect needs an id' 'harbor hub support list' 2; cmd_connect ;;
esac
