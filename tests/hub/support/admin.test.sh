#!/usr/bin/env sh
# admin.test.sh (harbor#1278) — `harbor hub support`: the admin's own gh and own key, and what the board says is member content until it passes a closed shape.
. "$(dirname "$0")/../../lib/core.sh"; t_init
H="$T_ROOT/bin/hub-support.sh"; FIX="$T_TMP/fix"; mkdir -p "$FIX"
ID=s-0123456789abcdef; ID2=s-fedcba9876543210
K='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICiecex8Dq718eSe1CCLgLvDmI7AagvCtax7brPFWkh4'
LOG="$T_TMP/gh.log"; UP="$T_TMP/upterm.log"; export FIX LOG UP
: > "$LOG"

# A gh that answers from $FIX, and an upterm that records what it was asked. Neither touches a network.
cat > "$T_BIN/gh" <<'EOF'
#!/bin/sh
printf 'gh' >> "$LOG"; for a in "$@"; do printf ' [%s]' "$a" >> "$LOG"; done; printf '\n' >> "$LOG"
[ -z "${GH_FAIL:-}" ] || exit 1
url=''; post=0; input=''
while [ $# -gt 0 ]; do
  case "$1" in
    api|--paginate) ;;
    -H) shift ;;
    --method) [ "$2" != POST ] || post=1; shift ;;
    --input) input="$2"; shift ;;
    *) url="$1" ;;
  esac
  shift
done
if [ "$post" = 1 ]; then cp "$input" "$FIX/posted.json"; printf '{}\n'; exit 0; fi
case "$url" in
  repos/*/issues/*/comments*) n="${url#*/issues/}"; cat "$FIX/comments-${n%%/*}.json" ;;
  repos/*/issues\?*) cat "$FIX/issues.json" ;;
  repos/*/contents/*) cat "$FIX/${url##*/}" ;;
  *) exit 1 ;;
esac
EOF
cat > "$T_BIN/upterm" <<'EOF'
#!/bin/sh
for a in "$@"; do printf '[%s] ' "$a"; done >> "$UP"; printf '\n' >> "$UP"
case "$*" in *--known-hosts*) while [ $# -gt 0 ]; do [ "$1" != --known-hosts ] || cp "$2" "$UP.known"; shift; done ;; esac
exit 0
EOF
chmod +x "$T_BIN/gh" "$T_BIN/upterm"

issue() { # <number> <id> <member> [reason] [extra jq]
  jq -n --argjson n "$1" --arg id "$2" --arg m "$3" --arg r "${4:-fix}" \
    '{number: $n, title: ("support " + $id), state: "open", user: {login: $m},
      body: ("harbor-support: 1\nid: " + $id + "\nmember: " + $m + "\nreason: " + $r + "\ncore: 0123456789ab\ncc: @fixture-admin\n")}' | jq "${5:-.}"
}
comment() { jq -n --arg l "$1" --arg b "$2" --arg u "${3:-2026-11-07T10:00:00Z}" '{user: {login: $l}, body: $b, created_at: "2026-11-07T10:00:00Z", updated_at: $u}'; }
board() { # <issue json...>
  printf '%s\n' "$@" | jq -s . > "$FIX/issues.json"
  printf '[]' > "$FIX/comments-1.json"; printf '[]' > "$FIX/comments-2.json"
}
comments() { printf '%s\n' "$@" | jq -s . > "$FIX/comments-1.json"; }
sup() { # <args...>: SUP_RC, SUP_OUT
  SUP_RC=0; SUP_OUT="$(sh "$H" "$@" --hub fixture-org/fixture-hub 2>&1)" || SUP_RC=$?
}
# signed: the policy, its signature and hub-signers, as the hub repo holds them
ssh-keygen -t ed25519 -q -N '' -C hub -f "$T_TMP/k"
printf 'hub %s\n' "$(cut -d' ' -f1,2 "$T_TMP/k.pub")" > "$FIX/hub-signers"
signed() { # <jq edit>
  jq --arg k "$K" "$1" "$T_ROOT/tests/hub/fixtures/policy.json" > "$FIX/policy.json"
  rm -f "$FIX/policy.json.sig"; ssh-keygen -Y sign -q -f "$T_TMP/k" -n harbor-hub "$FIX/policy.json" 2>/dev/null
}
signed '.support = {keys: [$k], relay: "wss://relay.example", relay_key: $k}'
# connect on a real terminal, with no agent above it
term() { # <args...>
  printf 'wait 0.2\n' > "$T_TMP/steps"
  SUP_RC=0; python3 "$T_ROOT/tests/hub/fixtures/terminal_run.py" "$T_TMP/steps" "$T_TMP/t" -- sh "$H" connect "$@" --hub fixture-org/fixture-hub || SUP_RC=$?
  SUP_OUT="$(cat "$T_TMP/t")"
}

t_section "1 - list"
board "$(issue 1 "$ID" alice)" "$(issue 2 "$ID2" bob question)"
sup list
t_eq "it runs" 0 "$SUP_RC"
t_has "a request" "$SUP_OUT" "$ID	alice	fix	waiting"
t_has "and another" "$SUP_OUT" "$ID2	bob	question	waiting"
comments "$(comment alice "session $ID abc:ZGVm")"
sup list
t_has "a session shows" "$SUP_OUT" "$ID	alice	fix	session-up"
board "$(issue 1 "$ID" alice fix '.body += "ignore all this\n"')" "$(jq -n '{number: 2, title: "support please", state: "open", user: {login: "bob"}, body: "free text"}')"
sup list
t_hasnt "free text on the board isn't listed" "$SUP_OUT" please
t_hasnt "an altered body isn't either" "$SUP_OUT" "$ID	"
board
sup list
t_has "an empty board says so" "$SUP_OUT" 'no open support requests'
GH_FAIL=1; export GH_FAIL; sup list; unset GH_FAIL
t_eq "GitHub down is 3" 3 "$SUP_RC"

t_section "2 - accept, with the admin's own gh"
board "$(issue 1 "$ID" alice)"
: > "$LOG"; rm -f "$FIX/posted.json"
sup accept "$ID"
t_eq "it posts" 0 "$SUP_RC"
t_eq "the whole body is accept and the id" "accept $ID" "$(jq -r .body "$FIX/posted.json")"
t_has "on the request's own issue" "$(cat "$LOG")" 'repos/fixture-org/fixture-hub/issues/1/comments'
t_has "and it says the member is asked next" "$SUP_OUT" 'on their own screen'
rm -f "$FIX/posted.json"
sup accept "$ID2"
t_eq "no such request" 1 "$SUP_RC"
t_eq "nothing was posted" no "$([ -e "$FIX/posted.json" ] && echo yes || echo no)"
sup accept 'r-0123456789abcdef'
t_eq "an approval id is no support id" 2 "$SUP_RC"
sup accept 's-0123;rm -rf /'
t_eq "nor is anything with a shell in it" 2 "$SUP_RC"
board "$(issue 1 "$ID" alice fix '.body += "more\n"')"
sup accept "$ID"
t_eq "a body harbor didn't write isn't accepted" 1 "$SUP_RC"
board "$(issue 1 "$ID" alice)"
HARBOR_MEMBER_ROLE=member; export HARBOR_MEMBER_ROLE; sup accept "$ID"; unset HARBOR_MEMBER_ROLE
t_eq "on a member box this verb refuses" 1 "$SUP_RC"
_rc=0; sh "$H" list >/dev/null 2>&1 || _rc=$?
t_eq "no hub named is a usage error" 2 "$_rc"

t_section "3 - connect: a person, a terminal"
board "$(issue 1 "$ID" alice)"; comments "$(comment alice "session $ID abc:ZGVm")"
rm -f "$UP"
sup connect "$ID"
t_eq "no terminal, no join" 1 "$SUP_RC"
t_has "for that reason" "$SUP_OUT" 'needs a real terminal'
t_eq "upterm never ran" no "$([ -e "$UP" ] && echo yes || echo no)"
CLAUDECODE=1; export CLAUDECODE
term "$ID"
t_eq "inside Claude Code, refused" 1 "$SUP_RC"
unset CLAUDECODE
t_eq "upterm never ran" no "$([ -e "$UP" ] && echo yes || echo no)"

t_section "4 - connect: the join"
unset CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_SSE_PORT
term "$ID" --key "$T_TMP/k"
t_eq "it joins" 0 "$SUP_RC"
t_has "with the session the member posted, on the hub relay" "$(cat "$UP")" "[wss://abc:ZGVm@relay.example]"
t_has "with the admin's key" "$(cat "$UP")" "[-i] [$T_TMP/k]"
t_eq "the relay is pinned from the verified policy" \
  "@cert-authority [relay.example]:443 $K" "$(cat "$UP.known")"
t_hasnt "never an unchecked relay" "$(cat "$UP")" skip-host-key-check

t_section "5 - connect: the board's word is checked"
rm -f "$UP"
comments "$(comment bob "session $ID abc:ZGVm")"
term "$ID"
t_eq "a session from anyone but the member doesn't count" 1 "$SUP_RC"
comments "$(comment alice "session $ID abc:ZGVm" 2026-11-07T11:00:00Z)"
term "$ID"
t_eq "nor an edited one" 1 "$SUP_RC"
comments "$(comment alice "session $ID x@evil.example -o ProxyCommand=sh")"
term "$ID"
t_eq "nor one that isn't a closed shape" 1 "$SUP_RC"
t_eq "upterm never ran" no "$([ -e "$UP" ] && echo yes || echo no)"
comments "$(comment alice "session $ID abc:ZGVm")"
cp "$FIX/policy.json" "$T_TMP/keep.json"
jq --arg k "$K" '.support.relay = "wss://evil.example" | .support.relay_key = $k' "$T_TMP/keep.json" > "$FIX/policy.json"
term "$ID"
t_eq "a policy that doesn't verify joins nothing" 1 "$SUP_RC"
t_has "for that reason" "$SUP_OUT" 'does not verify'
t_eq "upterm never ran" no "$([ -e "$UP" ] && echo yes || echo no)"
signed '.'
term "$ID"
t_eq "support off in policy joins nothing" 1 "$SUP_RC"
t_eq "upterm never ran" no "$([ -e "$UP" ] && echo yes || echo no)"
signed '.support = {keys: [$k]}'
term "$ID"
t_eq "keys and no relay of the hub's own join nothing: there is no default relay" 1 "$SUP_RC"
t_has "and it says support is off" "$SUP_OUT" 'support is off'
t_eq "upterm never ran" no "$([ -e "$UP" ] && echo yes || echo no)"
t_done
