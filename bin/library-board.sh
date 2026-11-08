#!/usr/bin/env sh
# library-board.sh (harbor#1278) — reading the hub board, shared by hub-approval.sh and member-support.sh. Sourced, never run, so it sets no shell option.
# The caller sets HERE, HUB, MEMBER and a private work folder W. Format: contracts/hub.md, "The board". What makes a comment count is here once, so an
# approval and a support acceptance can't drift apart.

valid_login() {
  [ "${#1}" -le 39 ] || return 1
  case "$1" in ''|-*|*[!A-Za-z0-9-]*) return 1 ;; esac
}
valid_repo() {
  case "$1" in ''|/*|*/|*/*/*|*..*|*[!A-Za-z0-9._/-]*) return 1 ;; */*) return 0 ;; *) return 1 ;; esac
}

board() { sh "$HERE/hub-board.sh" call "$W" "$@" </dev/null 2>/dev/null; }
# After a call: no usable answer, so the caller reports unreachable. A token GitHub refused is the same to a member.
board_down() {
  [ "$1" = 0 ] || return 0
  [ "$(cat "$W/limited")" = 1 ] && return 0
  case "$(cat "$W/status")" in 401|5??) return 0 ;; esac
  return 1
}
status_is() { [ "$(cat "$W/status")" = "$1" ]; }

# The signature is checked here too: the file sits in a user-owned folder, and condition 1 says signed.
policy_read() {
  _p="$(sh "$HERE/hub-sync.sh" path 2>/dev/null)" || return 1
  [ -n "$_p" ] && [ -f "$_p" ] && [ -f "$_p.sig" ] && [ -f "$HERE/../hub-signers" ] || return 1
  POL="$W/policy.json"
  cp "$_p" "$POL" && cp "$_p.sig" "$POL.sig" || return 1
  ssh-keygen -Y verify -f "$HERE/../hub-signers" -I hub -n harbor-hub -s "$POL.sig" < "$POL" >/dev/null 2>&1 || return 1
  sh "$HERE/hub-format.sh" policy "$POL" 2>/dev/null
}

# board_find_issue <title> <number hint>: leaves the issue in $W/issue.json. 0 found, 1 none, 3 down. The hint is only a hint: the
# title must still match, so a tampered record can't move an approval to another issue (F6).
board_find_issue() {
  _t="$1"; _n="$2"
  case "$_n" in ''|*[!0-9]*) _n='' ;; esac
  if [ -n "$_n" ]; then
    _rc=0; board GET "/repos/$HUB/issues/$_n" || _rc=$?
    board_down "$_rc" && return 3
    if status_is 200 && jq -e --arg t "$_t" '.title == $t' "$W/body" >/dev/null 2>&1; then
      cp "$W/body" "$W/issue.json"; return 0
    fi
  fi
  _rc=0; board GET "/repos/$HUB/issues?state=all&creator=$MEMBER&sort=created&direction=desc&per_page=100" || _rc=$?
  board_down "$_rc" && return 3
  status_is 200 || return 1
  jq -e --arg t "$_t" '[.[] | select(.title == $t)] | (map(select(.state == "open"))[0] // .[0])
    | if . == null then error("none") else . end' "$W/body" > "$W/issue.json" 2>/dev/null || return 1
}

resp_epoch() { # the same response's Date header, never this laptop's clock (condition 4)
  LC_ALL=C jq -rn --arg d "$(cat "$W/date")" '$d | strptime("%a, %d %b %Y %H:%M:%S GMT") | mktime' 2>/dev/null
}

# Condition 2. 0 counts, 1 refused, 3 down. A rate-limited 403 is not a refusal for this token, so the list doesn't decide it.
permission_ok() {
  valid_login "$1" || return 1
  _rc=0; board GET "/repos/$HUB/collaborators/$1/permission" || _rc=$?
  [ "$_rc" = 0 ] || return 3
  [ "$(cat "$W/limited")" = 1 ] && return 3
  case "$(cat "$W/status")" in
    200) jq -e '.permission == "admin" or .permission == "maintain" or .permission == "write"' "$W/body" >/dev/null 2>&1 ;;
    403|404) return 0 ;;
    401|5??) return 3 ;;
    *) return 1 ;;
  esac
}

# board_signed_comment <issue> <opener> <verb> <id> <spent json>: conditions 1 to 4 of contracts/hub.md for a comment whose whole
# body is `<verb> <id>`. 0 counts, with BC_COMMENT and BC_LOGIN set; 1 none does, with BC_LAPSED 1 when one ran out; 3 down.
board_signed_comment() {
  _num="$1"; _opener="$2"; _verb="$3"; _bid="$4"; _used="$5"
  BC_COMMENT=''; BC_LOGIN=''; BC_LAPSED=0
  _ttl="$(jq -r .approval.ttl_hours "$POL")" || return 1
  _appr="$(jq -c '[.approval.approvers[] | ascii_downcase]' "$POL")" || return 1
  _cand="$W/candidates"; : > "$_cand"
  _page=1
  while [ "$_page" -le 5 ]; do
    _rc=0; board GET "/repos/$HUB/issues/$_num/comments?per_page=100&page=$_page" || _rc=$?
    board_down "$_rc" && return 3
    status_is 200 || return 1
    _now="$(resp_epoch)" || return 1
    case "$_now" in ''|*[!0-9]*) return 1 ;; esac
    jq -c --arg want "$_verb $_bid" --arg m "$MEMBER" --arg o "$_opener" --argjson appr "$_appr" --argjson used "$_used" \
       --argjson ttl "$_ttl" --argjson now "$_now" '
      ($m | ascii_downcase) as $m | ($o | ascii_downcase) as $o
      | .[]
      | select(((.body // "") | gsub("^[ \t\r\n]+|[ \t\r\n]+$"; "")) == $want)
      | select(.user.type == "User")
      | ((.user.login // "") | ascii_downcase) as $a
      | select(($appr | index($a)) != null and $a != $m and $a != $o)
      | select((.created_at | type) == "string" and .updated_at == .created_at)
      | select((.id as $c | $used | index($c)) == null)
      | {id, login: .user.login, live: (((.created_at | fromdateiso8601) + $ttl * 3600) > $now)}' \
      "$W/body" >> "$_cand" 2>/dev/null || return 1
    [ "$(jq 'length' "$W/body" 2>/dev/null)" = 100 ] || break
    _page=$((_page + 1))
  done
  _down=0
  while IFS= read -r _c; do
    if [ "$(printf '%s' "$_c" | jq -r .live)" != true ]; then BC_LAPSED=1; continue; fi
    _login="$(printf '%s' "$_c" | jq -r .login)"
    _rc=0; permission_ok "$_login" || _rc=$?
    if [ "$_rc" = 0 ]; then BC_COMMENT="$(printf '%s' "$_c" | jq -r .id)"; BC_LOGIN="$_login"; return 0; fi
    [ "$_rc" = 3 ] && _down=1
  done < "$_cand"
  [ "$_down" = 0 ] || return 3
  return 1
}

# support_pin <key>: one value of support-upterm.tsv. Installed copies sit beside this script, a checkout keeps them under contracts/.
support_pin() {
  _sf="$HERE/support-upterm.tsv"; [ -f "$_sf" ] || _sf="$HERE/../contracts/support-upterm.tsv"
  awk -F'\t' -v k="$1" '/^#/ { next } $1 == k { print $2; found = 1; exit } END { exit !found }' "$_sf"
}
# support_relay <policy>: sets RELAY, RHOST, RKEY and RPATTERN, the relay's known_hosts name. A known_hosts pattern matches the port
# exactly, and wss is keyed by its port, so 443 is spelled out (upterm etc/known_hosts).
# Only the hub's own relay, with its key: no default (contracts/hub.md). 1 none named, so support is off; 2 it names the public relay.
support_relay() {
  RELAY="$(jq -r '.support.relay // empty' "$1")" || return 1
  RKEY="$(jq -r '.support.relay_key // empty' "$1")" || return 1
  [ -n "$RELAY" ] && [ -n "$RKEY" ] || return 1
  _ra="${RELAY#*://}"; RHOST="${_ra%%:*}"
  _pub="$(support_pin public-relay)" || return 2
  case "$RHOST" in "$_pub"|*".$_pub") return 2 ;; esac
  _rp="${_ra##*:}"
  if [ "$_rp" = "$_ra" ]; then case "$RELAY" in wss://*) _rp=443 ;; *) _rp=22 ;; esac; fi
  RPATTERN="[$RHOST]:$_rp"; [ "$_rp" != 22 ] || RPATTERN="$RHOST"
}

# support_issue_valid <file> <id> <member>: the whole body is the six closed lines of contracts/hub.md, from that member, open.
support_issue_valid() {
  jq -e --arg id "$2" --arg m "$3" '
    ($m | ascii_downcase) as $m
    | ((.body // "") | gsub("\r"; "") | sub("\n+$"; "") | split("\n")) as $l
    | .state == "open" and ((.user.login // "") | ascii_downcase) == $m
      and .title == ("support " + $id) and ($l | length) == 6
      and $l[0] == "harbor-support: 1" and $l[1] == ("id: " + $id) and ($l[2] | ascii_downcase) == ("member: " + $m)
      and ($l[3] | test("^reason: (update|fix|question)$")) and ($l[4] | test("^core: [0-9a-f]{12}$"))
      and ($l[5] | test("^cc:( @[A-Za-z0-9-]+)+$"))' "$1" >/dev/null 2>&1
}

# support_in_agent: 0 when this process belongs to an agent session. The variables can be unset, so the process tree is read too.
# A sandbox with its own pid namespace hides that tree, so its pid 1 is read as well. Only a refusal: the deny rule and the relay's
# deniedDomains row are what stop an agent, and this one stops a person's slip (contracts/hub.md).
support_in_agent() {
  [ -z "${CLAUDECODE:-}${CLAUDE_CODE_ENTRYPOINT:-}" ] || return 0
  case "$(cat /proc/1/comm 2>/dev/null)" in bwrap) return 0 ;; esac
  _ap=$$; _ai=0
  while [ "$_ap" -gt 1 ] 2>/dev/null && [ "$_ai" -lt 40 ]; do
    _al="$(ps -o ppid= -o args= -p "$_ap" 2>/dev/null)" || return 1
    [ -n "$_al" ] || return 1
    # shellcheck disable=SC2086 # the words of one ps line
    set -f; set -- $_al; set +f
    _ap="$1"; _a1="${2:-}"; _a2="${3:-}"
    case "${_a1##*/}" in claude|claude.exe|bwrap) return 0 ;; esac
    case "${_a1##*/}:$_a2" in node:*/claude|node:*/claude-code/*|bun:*/claude|bun:*/claude-code/*) return 0 ;; esac
    _ai=$((_ai + 1))
  done
  return 1
}
