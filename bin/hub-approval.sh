#!/usr/bin/env sh
# hub-approval.sh (harbor#1278) — asks the board whether an admin approved this exact call. Format: contracts/hub.md, "The board".
#   sh hub-approval.sh status <id>     exit 0 approved and valid, 1 not approved, 3 GitHub unreachable. 1 and 3 keep the call denied
#   sh hub-approval.sh file <id> <rule> <tier> <target> <label>   opens the request once per id. Exit 0, 3 unreachable, 2 refused
#   sh hub-approval.sh consume <id>    marks used, comments, closes the issue. Always exit 0
#   sh hub-approval.sh note [<event>]  what the member should hear now, as text or as <event> hook JSON. Always exit 0
set -eu
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/library-hub.sh"
. "$HERE/library-log.sh"
. "$HERE/library-board.sh"
LOG_FD=2
log_init hub-approval

# `note` is a managed hook entry, so env goes first (harbor#1278). The other verbs run under the dispatcher, which already cleaned it; with no marker, only a test's seams.
if [ "${1:-}" = note ] && hub_marker; then hub_env_clean || exit 0; fi

HS="$(hub_state_dir)"
MEMBER="${HARBOR_MEMBER_LOGIN:-}"; HUB="${HARBOR_HUB_REPO:-}"
REQ="$HS/requests"; USED="$HS/used"
W=''; LOCK=''
cleanup() { [ -z "$W" ] || rm -rf "$W"; [ -z "$LOCK" ] || rmdir "$LOCK" 2>/dev/null; :; }
trap cleanup EXIT
trap 'exit 130' INT HUP TERM

usage() { sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
valid_id() {
  [ "${#1}" = 18 ] || return 1
  case "$1" in r-*) ;; *) return 1 ;; esac
  case "${1#r-}" in *[!0123456789abcdef]*) return 1 ;; esac
}
# Only a member box with its managed facts set reaches the board at all.
ready() {
  hub_is_member && valid_login "$MEMBER" && valid_repo "$HUB" || return 1
  (umask 077; mkdir -p "$REQ" "$USED") 2>/dev/null || return 1
  W="$(mktemp -d "${TMPDIR:-/tmp}/hub-approval.XXXXXX")" || return 1
}

event() { # <id> <outcome>: the transition, from the local request record
  _r="$REQ/$1.json"
  [ -f "$_r" ] || return 0
  sh "$HERE/hub-events.sh" record request "id=$1" "rule=$(jq -r .rule "$_r")" "tier=$(jq -r .tier "$_r")" \
    "target=$(jq -r .target "$_r")" "outcome=$2" >/dev/null 2>&1 || :
}

# find_issue <id>: the local number is only a hint, and board_find_issue checks the title against it.
find_issue() {
  _hint="$(jq -r '.issue // empty' "$REQ/$1.json" 2>/dev/null)" || _hint=''
  board_find_issue "request $1" "$_hint"
}

# Condition 5 and the whole-body shape: nine closed lines, so added prose or a changed id or member fails.
issue_valid() {
  jq -e --arg id "$1" --arg m "$MEMBER" '
    ($m | ascii_downcase) as $m
    | ((.body // "") | gsub("\r"; "") | sub("\n+$"; "") | split("\n")) as $l
    | .state == "open" and ((.user.login // "") | ascii_downcase) == $m
      and ($l | length) == 9
      and $l[0] == "harbor-request: 1" and $l[1] == ("id: " + $id) and ($l[2] | ascii_downcase) == ("member: " + $m)
      and ($l[3] | test("^rule: [a-z0-9][a-z0-9.-]{0,63}$")) and ($l[4] | test("^label: .{1,60}$"))
      and ($l[5] | test("^tier: [a-z-]+$")) and ($l[6] | test("^target: [a-z-]+$"))
      and ($l[7] | test("^core: [0-9a-f]{12}$")) and ($l[8] | test("^cc:( @[A-Za-z0-9-]+)*$"))' "$W/issue.json" >/dev/null 2>&1
}

# check_approved <id>: every numbered condition of contracts/hub.md. 0 approved with AC_COMMENT set, 1 not, 3 down.
check_approved() {
  AC_COMMENT=''
  _rc=0; find_issue "$1" || _rc=$?
  [ "$_rc" = 0 ] || return "$_rc"
  issue_valid "$1" || return 1
  _num="$(jq -r .number "$W/issue.json")" || return 1
  case "$_num" in ''|*[!0-9]*) return 1 ;; esac
  _opener="$(jq -r .user.login "$W/issue.json")" || return 1
  # A used approval is a comment id, not the request id: a later identical call can be approved afresh (the mark is advisory).
  _used="$(jq -R -s -c 'split("\n") | map(tonumber? // empty)' "$USED/$1" 2>/dev/null)" || _used='[]'
  _rc=0; board_signed_comment "$_num" "$_opener" approve "$1" "$_used" || _rc=$?
  if [ "$_rc" = 0 ]; then AC_COMMENT="$BC_COMMENT"; return 0; fi
  [ "$_rc" = 1 ] || return "$_rc"
  if [ "$BC_LAPSED" = 1 ] && [ ! -e "$REQ/$1.lapsed" ]; then : > "$REQ/$1.lapsed"; event "$1" expired; fi
  return 1
}

# The record is rewritten from the issue just verified, so consume closes the right one even if the local copy was lost or moved.
adopt_record() { # <id>
  jq --arg id "$1" '((.body // "") | gsub("\r"; "") | split("\n")) as $l
    | def v($i): $l[$i] | sub("^[a-z]+: "; "");
      {id: $id, issue: .number, rule: v(3), label: v(4), tier: v(5), target: v(6)}' "$W/issue.json" > "$W/record.json" 2>/dev/null \
    && cp "$W/record.json" "$REQ/$1.json"
}

mark_approved() { # <id>: first sight of an approval goes on the board once
  adopt_record "$1" || :
  if [ ! -e "$REQ/$1.approved" ]; then _new=1; else _new=0; fi
  printf '%s\n' "$AC_COMMENT" > "$REQ/$1.approved"
  [ "$_new" = 0 ] || event "$1" approved
}

cmd_status() {
  valid_id "${1:-}" || exit 1
  ready || exit 1
  policy_read || exit 1
  _rc=0; check_approved "$1" || _rc=$?
  if [ "$_rc" = 0 ]; then mark_approved "$1"; fi
  exit "$_rc"
}

# A label comes from the signed policy or the core tier list, never the caller's word: a free field here would put content
# on a board every member reads (F29). Each closed field goes through the event validator, the same one the sender uses.
known_label() { # <rule> <label>
  case "$2" in *[[:cntrl:]]*) return 1 ;; esac
  [ "${#2}" -ge 1 ] && [ "${#2}" -le 60 ] || return 1
  _l="$(jq -r --arg r "$1" '.rules // [] | map(select(.id == $r))[0].label // empty' "$POL")" || return 1
  if [ -z "$_l" ]; then
    _l="$(sh "$HERE/hub-tier.sh" lookup "$1" 2>/dev/null | cut -f3)" || _l=''
  fi
  [ -n "$_l" ] && [ "$_l" = "$2" ]
}
fields_valid() { # <id> <rule> <tier> <target>
  jq -n --arg id "$1" --arg r "$2" --arg t "$3" --arg g "$4" --arg m "$MEMBER" \
    '{v: 1, kind: "request", ts: "2000-01-01T00:00:00Z", member: $m, id: $id, rule: $r, tier: $t, target: $g, outcome: "opened"}' \
    > "$W/fields.json" && sh "$HERE/hub-format.sh" event "$W/fields.json" 2>/dev/null
}

request_body() { # <id> <rule> <tier> <target> <label>: the closed lines of contracts/hub.md, the only text an issue carries
  printf 'harbor-request: 1\nid: %s\nmember: %s\nrule: %s\nlabel: %s\ntier: %s\ntarget: %s\ncore: %s\ncc:' \
    "$1" "$MEMBER" "$2" "$5" "$3" "$4" "$(jq -r '.core.commit[0:12]' "$POL")"
  # An @mention is the only mail a Read-role token can cause: labels and assignees are dropped silently (R18).
  jq -r --arg m "$MEMBER" '.approval.approvers[] | select(ascii_downcase != ($m | ascii_downcase))' "$POL" \
    | while IFS= read -r _a; do printf ' @%s' "$_a"; done
  printf '\n'
}

take_lock() { # <id>: two hooks filing one call race to a single issue. A lock older than a minute is a crash's
  find "$REQ/$1.lock" -maxdepth 0 -mmin +1 -exec rmdir {} + 2>/dev/null || :
  mkdir "$REQ/$1.lock" 2>/dev/null || return 1
  LOCK="$REQ/$1.lock"
}

cmd_file() {
  [ $# = 5 ] || usage
  valid_id "$1" || exit 2
  ready || exit 2
  fields_valid "$1" "$2" "$3" "$4" || { log_fail "a field is not closed vocabulary"; log_nofix "contracts/hub.md, The board"; log_end || :; exit 2; }
  # No signed policy means no approver to mention and none who could count.
  policy_read || exit 3
  known_label "$2" "$5" || { log_fail "the label is not the rule's own"; log_nofix "contracts/hub.md, The board"; log_end || :; exit 2; }
  take_lock "$1" || exit 0
  find "$REQ" "$USED" -type f -mtime +30 -exec rm -f {} + 2>/dev/null || :
  _rc=0; find_issue "$1" || _rc=$?
  [ "$_rc" = 3 ] && exit 3
  if [ "$_rc" = 0 ]; then
    if [ "$(jq -r .state "$W/issue.json")" = open ]; then adopt_record "$1" || :; exit 0; fi
    # Closed and never used is the admin saying no: a retry mustn't reopen it by mail. Reopening is theirs (F23).
    [ -s "$USED/$1" ] || exit 0
  fi
  request_body "$1" "$2" "$3" "$4" "$5" > "$W/issue-body"
  jq -n --arg t "request $1" --rawfile b "$W/issue-body" '{title: $t, body: $b}' > "$W/create.json" || exit 3
  _rc=0; board POST "/repos/$HUB/issues" "$W/create.json" || _rc=$?
  { [ "$_rc" = 0 ] && status_is 201; } || exit 3
  _n="$(jq -r .number "$W/body")" || exit 3
  jq -n --arg id "$1" --argjson n "$_n" --arg r "$2" --arg t "$3" --arg g "$4" --arg l "$5" \
    '{id: $id, issue: $n, rule: $r, tier: $t, target: $g, label: $l}' > "$REQ/$1.json" || exit 3
  rm -f "$REQ/$1.approved" "$REQ/$1.lapsed" "$REQ/$1.noted"
  event "$1" opened
  exit 0
}

cmd_consume() {
  valid_id "${1:-}" || exit 0
  ready || exit 0
  cat "$REQ/$1.approved" >> "$USED/$1" 2>/dev/null || :
  event "$1" used
  _n="$(jq -r '.issue // empty' "$REQ/$1.json" 2>/dev/null)" || _n=''
  case "$_n" in ''|*[!0-9]*) exit 0 ;; esac
  jq -n --arg b "used $1" '{body: $b}' > "$W/used.json" || exit 0
  board POST "/repos/$HUB/issues/$_n/comments" "$W/used.json" || exit 0
  printf '{"state":"closed"}' > "$W/close.json"
  board PATCH "/repos/$HUB/issues/$_n" "$W/close.json" || :
  exit 0
}

# The member's only signal that an admin answered (F23). No open request means no network, so it is free on every prompt.
note_lines() {
  # A token warning is said once a day, not on every prompt.
  _said="$HS/.token-note"
  if [ -z "$(find "$_said" -mmin -1440 2>/dev/null)" ]; then
    _bs="$(cat "$HS/board-state" 2>/dev/null)" || _bs=''
    _dl="$(cat "$HS/token-days-left" 2>/dev/null)" || _dl=''
    if [ "$_bs" = token-expired ]; then
      printf 'The hub token has ended, so approvals and reports have stopped. Ask IT for a new one.\n'
      : > "$_said"
    else
      case "$_dl" in
        ''|*[!0-9]*) ;;
        *) printf 'The hub token ends in %s days. Ask IT for a new one before then.\n' "$_dl"; : > "$_said" ;;
      esac
    fi
  fi
  _stamp="$REQ/.last-note"
  [ -z "$(find "$_stamp" -mmin -1 2>/dev/null)" ] || return 0
  _start="$(date +%s)"; _asked=0; _touched=0
  # Newest first, so old lapsed requests can't use up the three looks.
  _names="$(ls -t "$REQ" 2>/dev/null | grep '^r-[0-9a-f]*\.json$')" || _names=''
  for _f in $_names; do
    _id="${_f%.json}"; _f="$REQ/$_f"
    valid_id "$_id" || continue
    [ ! -e "$REQ/$_id.noted" ] && [ ! -s "$USED/$_id" ] || continue
    [ "$_asked" -lt 3 ] && [ $(($(date +%s) - _start)) -lt 15 ] || break
    if [ "$_touched" = 0 ]; then
      policy_read || return 0
      : > "$_stamp"; _touched=1
    fi
    _asked=$((_asked + 1))
    _rc=0; check_approved "$_id" || _rc=$?
    [ "$_rc" != 3 ] || break
    [ "$_rc" = 0 ] || continue
    mark_approved "$_id"; : > "$REQ/$_id.noted"
    printf 'An admin approved: %s. Ask the agent to try the same action again (%s).\n' "$(jq -r .label "$_f")" "$_id"
  done
  return 0
}

cmd_note() {
  ready || exit 0
  _msg="$(note_lines)" || _msg=''
  [ -n "$_msg" ] || exit 0
  if [ -n "${1:-}" ]; then
    # systemMessage reaches the person, additionalContext the agent.
    jq -n --arg m "$_msg" --arg e "$1" '{systemMessage: $m, hookSpecificOutput: {hookEventName: $e, additionalContext: $m}}'
  else
    printf '%s\n' "$_msg"
  fi
  exit 0
}

verb="${1:-}"; [ -n "$verb" ] || usage
shift
case "$verb" in
  status) cmd_status "$@" ;;
  file) cmd_file "$@" ;;
  consume) cmd_consume "$@" ;;
  note) cmd_note "$@" ;;
  --help|-h) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) usage ;;
esac
