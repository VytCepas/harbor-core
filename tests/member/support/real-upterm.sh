#!/usr/bin/env sh
# real-upterm.sh (harbor#1278) — member-support.sh and hub-support.sh against the real upterm and a real uptermd on loopback, with a stub board. Never the public relay.
# The uptermd is the hub relay as relay/install.sh lays it out: its binary, its settings file and its unit's ExecStart, under a temp root.
#   sh tests/member/support/real-upterm.sh     SUPPORT_REAL_BIN=<dir> reads the release archives from there instead of downloading them
# Not *.test.sh on purpose, as tests/install/stranger-ubuntu.sh isn't: it fetches a release, and uptermd ships for Linux only, so a Mac needs docker. The suite
# pool has neither. On Linux it runs here; elsewhere in a throwaway container with no network. With no way to run it, it FAILS (exit 2), never skips.
# SUPPORT_REAL_IMAGE names the image: it needs jq, ssh-keygen, ssh, python3 and git.
if [ "${1:-}" = --inner ]; then INNER=1; else INNER=0; fi
REAL_HOME="$HOME"
. "$(dirname "$0")/../../lib/core.sh"; t_init real-upterm
PIN="$T_ROOT/contracts/support-upterm.tsv"
pin() { awk -F'\t' -v k="$1" '$1 == k { print $2; exit }' "$PIN"; }
sum() { { sha256sum "$1" 2>/dev/null || shasum -a 256 "$1"; } | cut -d' ' -f1; }

if [ "$INNER" = 0 ]; then
  IMAGE="${SUPPORT_REAL_IMAGE:-port-linux-runner:local}"
  export DOCKER_CONFIG="${DOCKER_CONFIG:-$REAL_HOME/.docker}"
  if [ "$(uname -s)" = Linux ]; then ARCH="$(uname -m)"
  else
    command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 || { echo "real-upterm: not Linux and no docker daemon; refusing to substitute a weaker check" >&2; exit 2; }
    ARCH="$(docker info --format '{{.Architecture}}')"
  fi
  case "$ARCH" in x86_64|amd64) ARCH=amd64 ;; aarch64|arm64) ARCH=arm64 ;; *) echo "real-upterm: no pinned binary for $ARCH" >&2; exit 2 ;; esac
  B="$T_TMP/real"; mkdir -p "$B"
  # The digest is the proof, wherever the bytes came from.
  for _p in "upterm sha256-linux-$ARCH" "uptermd uptermd-linux-$ARCH"; do
    _n="${_p%% *}"; _k="${_p#* }"; _f="${_n}_linux_$ARCH.tar.gz"
    if [ -n "${SUPPORT_REAL_BIN:-}" ]; then cp "$SUPPORT_REAL_BIN/$_f" "$T_TMP/$_f"
    else curl -q --silent --show-error --fail --location --proto '=https' --output "$T_TMP/$_f" "https://github.com/owenthereal/upterm/releases/download/v$(pin version)/$_f" || exit 2; fi
    [ "$(sum "$T_TMP/$_f")" = "$(pin "$_k")" ] || { echo "real-upterm: $_f is not the pinned one" >&2; exit 2; }
    tar -xzf "$T_TMP/$_f" -C "$B" "$_n"
    cp "$T_TMP/$_f" "$B/"   # relay/install.sh proves the archive itself
  done
  if [ "$(uname -s)" = Linux ]; then
    SUPPORT_REAL_DIR="$B"; export SUPPORT_REAL_DIR
    exec sh "$0" --inner
  fi
  COPYFILE_DISABLE=1 tar -C "$T_ROOT" -cf - bin contracts relay standards tests/lib tests/hub/fixtures tests/member/support -C "$T_TMP" real \
    | docker run --rm -i --network none --entrypoint sh "$IMAGE" -c \
      'mkdir -p /tmp/t && tar -xf - -C /tmp/t 2>/dev/null; SUPPORT_REAL_DIR=/tmp/t/real; export SUPPORT_REAL_DIR; exec sh /tmp/t/tests/member/support/real-upterm.sh --inner'
  exit $?
fi

. "$T_ROOT/tests/hub/fixtures/board-env.sh"
. "$T_ROOT/tests/hub/fixtures/support-env.sh"
TERMINAL_RUN="$T_ROOT/tests/hub/fixtures/terminal_run.py"
PTY_RUN_TIMEOUT=70; export PTY_RUN_TIMEOUT
se_up
cp "$SUPPORT_REAL_DIR/upterm" "$BE_BIN/upterm"; ln -s "$SUPPORT_REAL_DIR/upterm" "$T_BIN/upterm"
for _n in admin stranger; do ssh-keygen -q -t ed25519 -N '' -C "$_n" -f "$T_TMP/$_n"; done
# The relay, laid out by the hub's own install under a temp root, named for loopback. Its host key is the one that install made.
VM="$T_TMP/vm"; VE="$VM/etc/harbor-relay"; UNIT="$VM/etc/systemd/system/harbor-relay.service"
sh "$T_ROOT/relay/install.sh" --root "$VM" --host 127.0.0.1 --from "$SUPPORT_REAL_DIR" > "$T_TMP/relay-install.out" 2>&1 \
  || { echo "real-upterm: relay/install.sh failed: $(cat "$T_TMP/relay-install.out")" >&2; exit 2; }
RELAY_KEY="$(sh "$T_ROOT/relay/install.sh" --root "$VM" --key | head -n 1)"
PORT="$(sed -n 's/^UPTERMD_SSH_ADDR=127\.0\.0\.1://p' "$VE/relay.env")"
WSADDR="$(sed -n 's/^UPTERMD_WS_ADDR=//p' "$VE/relay.env")"
# The unit's own ExecStart, with %d, the credentials folder, holding the key, and its settings file as the environment.
mkdir -p "$T_TMP/cred"; cp "$VE/host_key" "$T_TMP/cred/host_key"
EXEC="$(sed -n 's/^ExecStart=//p' "$UNIT" | sed -e "s|%d|$T_TMP/cred|g" -e "s|^/usr/local/bin/|$VM/usr/local/bin/|")"
( set -a; . "$VE/relay.env"; set +a
  # shellcheck disable=SC2086 # the unit's ExecStart is a word list by design
  exec $EXEC ) > "$T_TMP/uptermd.log" 2>&1 &
RELAYD=$!
{ printf '@cert-authority [127.0.0.1]:%s %s\n' "$PORT" "$RELAY_KEY"; printf '@cert-authority [%s]:%s %s\n' "${WSADDR%:*}" "${WSADDR##*:}" "$RELAY_KEY"; } > "$T_TMP/kh"
sleep 1
real_policy() { # [jq edit]: this run's relay and the admin's key, nothing else
  se_reset ".support = {keys: [\"$(cat "$T_TMP/admin.pub")\"], relay: \"ssh://127.0.0.1:$PORT\", relay_key: \"$RELAY_KEY\"} | ${1:-.}"
  se_settings 127.0.0.1
}
start() { # <name> <steps...>: a person at a terminal, in the background. Transcript $T_TMP/<name>.out
  _s="$1"; shift
  printf '%s\n' "$@" > "$T_TMP/$_s.steps"
  python3 "$TERMINAL_RUN" "$T_TMP/$_s.steps" "$T_TMP/$_s.out" -- sh "$SE_SUPPORT" &
  PERSON=$!
}
await() { # <file> <text> [tenths]: 0 once the file holds the text
  _i=0
  while [ "$_i" -lt "${3:-400}" ]; do
    grep -qF -- "$2" "$1" 2>/dev/null && return 0
    sleep 0.1; _i=$((_i + 1))
  done
  return 1
}
board_has() { # <prefix> [tenths]: 0 once a comment starts with it
  _i=0
  while [ "$_i" -lt "${2:-300}" ]; do
    se_comments | grep -q "^$1" && return 0
    sleep 0.1; _i=$((_i + 1))
  done
  return 1
}
join() { # <key> <target> <out> <steps...>: a guest at a terminal. JOIN_RC
  _k="$1"; _t="$2"; _o="$3"; shift 3
  printf '%s\n' "$@" > "$T_TMP/join.steps"
  JOIN_RC=0; python3 "$TERMINAL_RUN" "$T_TMP/join.steps" "$_o" -- upterm join -i "$_k" --known-hosts "$T_TMP/kh" "$_t" || JOIN_RC=$?
}
target() { sed -n 's/.*upterm join \(ssh:[^ ]*\).*/\1/p' "$1" | head -n 1; }
ASK1='expect Type update'; ASK2='send fix'; ASK3='expect the word allow'; ASK4='send allow'

t_section "0 - the binaries are the pinned ones, and the relay is the hub's own install"
t_has "upterm says its version" "$("$BE_BIN/upterm" version 2>/dev/null)" "$(pin version)"
t_has "uptermd landed by relay/install.sh says its version" "$("$VM/usr/local/bin/uptermd" version 2>/dev/null)" "$(pin version)"
t_eq "it listens where its settings file says, read from UPTERMD_* alone" 2223 "$PORT"
kill -0 "$RELAYD" 2>/dev/null && t_pass || t_fail "uptermd from the unit's ExecStart died: $(tail -3 "$T_TMP/uptermd.log")"
if command -v systemd-analyze >/dev/null 2>&1; then
  # verify reads the ExecStart binary from /, which a throwaway container lacks: the same unit, pointed at the temp root's copy.
  sed "s|^ExecStart=/usr/local/bin/|ExecStart=$VM/usr/local/bin/|" "$UNIT" > "$T_TMP/harbor-relay.service"
  _v="$(systemd-analyze verify "$T_TMP/harbor-relay.service" 2>&1)" && _rc=0 || _rc=$?
  # An unknown or misspelt key is only a warning with exit 0, and it would drop that hardening line: any output is a failure.
  t_eq "systemd-analyze verify passes the unit with nothing to say" '0:' "$_rc:$_v"
  _x="$(systemd-analyze security --offline=true "$T_TMP/harbor-relay.service" 2>/dev/null | sed -n 's/.*Overall exposure level for [^:]*: \([0-9.]*\).*/\1/p')"
  t_eq "and rates its exposure low (under 2.0 of 10): $_x" 1 "$(awk -v x="${_x:-99}" 'BEGIN { print (x < 2.0) ? 1 : 0 }')"
else
  t_fail "systemd-analyze is missing here, so the unit was not verified"
fi

t_section "1 - no one gets a shell before the person answers"
real_policy
se_accept_soon
start a "$ASK1" "$ASK2" "$ASK3" "$ASK4" 'expect Start the session? [y/n]' "wait-file $T_TMP/go-a" 'wait 1' 'key y' 'wait 0.5' 'send' "wait-file $T_TMP/end-a" 'hup'
await "$T_TMP/a.out" 'Start the session? [y/n]' 500 && t_pass || t_fail "the question never came: $(tail -5 "$T_TMP/a.out")"
TARGET="$(target "$T_TMP/a.out")"
t_has "upterm named a session" "$TARGET" "@127.0.0.1:$PORT"
t_eq "and it isn't on the board until the person says yes" '' "$(se_comments | grep '^session' || :)"
join "$T_TMP/admin" "$TARGET" "$T_TMP/early.out" 'wait 5' 'send echo early-$((6*7))' 'wait 3'
t_hasnt "a listed key runs nothing before the answer" "$(cat "$T_TMP/early.out"; printf ' .')" 'early-42'
t_hasnt "nothing reached the person's shell" "$(cat "$T_TMP/a.out")" 'early-42'
: > "$T_TMP/go-a"
board_has session && t_pass || t_fail "the session never reached the board: $(tail -5 "$T_TMP/a.out")"
SID="$(se_comments | sed -n 's/^session s-[0-9a-f]* //p')"
TARGET="ssh://$SID@127.0.0.1:$PORT"

t_section "2 - a key not in policy can't join, session id or not"
join "$T_TMP/stranger" "$TARGET" "$T_TMP/stranger.out" 'wait 4'
t_has "the relay's own words" "$(cat "$T_TMP/stranger.out")" 'refused your keys'
t_eq "and it left with no session" 255 "$JOIN_RC"

t_section "3 - a command, a file, a forward: nothing that doesn't appear on the person's screen"
_o="$(ssh -i "$T_TMP/admin" -p "$PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes "$SID@127.0.0.1" id 2>&1)" && _rc=0 || _rc=$?
t_eq "ssh with a command is refused" 1 "$_rc"
t_has "because exec is off" "$_o" "doesn't run commands a guest names"
_o="$(ssh -i "$T_TMP/admin" -p "$PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -s "$SID@127.0.0.1" sftp 2>&1 </dev/null)" && _rc=0 || _rc=$?
[ "$_rc" != 0 ] && t_pass || t_fail "the sftp subsystem opened: $_o"

t_section "4 - the listed key joins through harbor hub support, and the person sees it"
mkdir -p "$T_TMP/fix"
cat > "$T_BIN/gh" <<'EOF'
#!/bin/sh
url=''; while [ $# -gt 0 ]; do case "$1" in api|--paginate) ;; -H) shift ;; *) url="$1" ;; esac; shift; done
case "$url" in
  repos/*/issues/*/comments*) n="${url#*/issues/}"; cat "$BE_ST/comments/${n%%/*}.json" ;;
  repos/*/issues\?*) jq -s . "$BE_ST"/issues/*.json ;;
  repos/*/contents/*) cat "$T_FIX/${url##*/}" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$T_BIN/gh"
T_FIX="$T_TMP/fix"; export T_FIX BE_ST
cp "$T_TMP/state-policy.json" "$T_FIX/policy.json"; cp "$T_TMP/state-policy.json.sig" "$T_FIX/policy.json.sig"; cp "$BE_ROOT/hub-signers" "$T_FIX/hub-signers"
printf '%s\n' 'wait 3' 'send echo guest-$((6*7))-$(id -un)' "expect guest-42-$(id -un)" 'wait 1' > "$T_TMP/connect.steps"
_id="$(se_id)"
_rc=0
(
  unset HARBOR_MEMBER_ROLE HARBOR_MEMBER_LOGIN
  PTY_RUN_TIMEOUT=25 python3 "$TERMINAL_RUN" "$T_TMP/connect.steps" "$T_TMP/connect.out" -- sh "$T_ROOT/bin/hub-support.sh" connect "$_id" --key "$T_TMP/admin" --hub fixture-org/fixture-hub
) || _rc=$?
t_has "the admin's terminal runs the command, as the member's account" "$(cat "$T_TMP/connect.out")" "guest-42-$(id -un)"
await "$T_TMP/a.out" 'guest-42' 50 && t_pass || t_fail "the person didn't see it: $(tail -5 "$T_TMP/a.out")"

t_section "5 - closing the window ends it, and leaves nothing behind"
: > "$T_TMP/end-a"
wait "$PERSON" 2>/dev/null || :
board_has "closed $_id" && t_pass || t_fail "no closed comment: $(se_comments | tail -3)"
t_eq "the request is closed" closed "$(jq -r .state "$BE_ST/issues/1.json")"
t_eq "the record" "requested accepted started ended " "$(se_events)"
_i=0; while pgrep -f 'upterm host' >/dev/null 2>&1 && [ "$_i" -lt 50 ]; do sleep 0.2; _i=$((_i + 1)); done
t_eq "no upterm is left running" 0 "$(pgrep -f 'upterm host' | wc -l | tr -d ' ')"
t_eq "and no session folder" '' "$(find "$BE_HS" -maxdepth 1 -name 'sup.*')"
join "$T_TMP/admin" "$TARGET" "$T_TMP/after.out" 'wait 4'
t_eq "the session id is dead" 255 "$JOIN_RC"

t_section "6 - the time limit ends it, with a guest inside"
real_policy
HARBOR_MEMBER_SUPPORT_LIMIT_SECONDS=22; export HARBOR_MEMBER_SUPPORT_LIMIT_SECONDS
se_accept_soon
start b "$ASK1" "$ASK2" "$ASK3" "$ASK4" 'expect Start the session? [y/n]' 'wait 1' 'key y' 'wait 0.5' 'send' 'expect time limit was reached'
board_has session && t_pass || t_fail "no session: $(tail -5 "$T_TMP/b.out")"
SID="$(se_comments | sed -n 's/^session s-[0-9a-f]* //p')"
join "$T_TMP/admin" "ssh://$SID@127.0.0.1:$PORT" "$T_TMP/inside.out" 'wait 2' 'send echo inside-$((6*7))' 'expect inside-42' 'expect connection to the session ended'
t_has "the guest was in" "$(cat "$T_TMP/inside.out")" 'inside-42'
t_has "and the limit put them out" "$(cat "$T_TMP/inside.out")" 'connection to the session ended'
wait "$PERSON" 2>/dev/null || :
unset HARBOR_MEMBER_SUPPORT_LIMIT_SECONDS
t_has "the person was told" "$(cat "$T_TMP/b.out")" 'time limit was reached'
t_eq "the record says so" "requested accepted started timed-out " "$(se_events)"
board_has "closed " && t_pass || t_fail "no closed comment"
t_eq "the request is closed" closed "$(jq -r .state "$BE_ST/issues/1.json")"

t_section "7 - a planted UPTERM_ACCEPT and config file don't skip the question"
real_policy
mkdir -p "$HOME/.config/upterm"; printf 'accept: true\nskip-host-key-check: true\n' > "$HOME/.config/upterm/config.yaml"
UPTERM_ACCEPT=true; UPTERM_SKIP_HOST_KEY_CHECK=true; export UPTERM_ACCEPT UPTERM_SKIP_HOST_KEY_CHECK
se_accept_soon
start c "$ASK1" "$ASK2" "$ASK3" "$ASK4" 'expect Start the session? [y/n]' 'wait 1' 'key n' 'wait 0.5' 'send' 'expect not started'
wait "$PERSON" 2>/dev/null || :
unset UPTERM_ACCEPT UPTERM_SKIP_HOST_KEY_CHECK
t_has "the question still came" "$(cat "$T_TMP/c.out")" 'Start the session? [y/n]'
t_has "and no is no" "$(cat "$T_TMP/c.out")" 'not started'
t_eq "nothing went to the board" '' "$(se_comments | grep '^session' || :)"

t_section "8 - a relay with the wrong key is refused before anything is shared"
real_policy ".support.relay_key = \"$(cut -d' ' -f1,2 "$T_TMP/stranger.pub")\""
se_accept_soon
start d "$ASK1" "$ASK2" "$ASK3" "$ASK4" 'expect not started'
wait "$PERSON" 2>/dev/null || :
t_has "upterm refuses the relay" "$(cat "$T_TMP/d.out")" 'REMOTE HOST IDENTIFICATION'
t_hasnt "and asks nobody to start" "$(cat "$T_TMP/d.out")" '[y/n]'
t_eq "the request is closed" closed "$(jq -r .state "$BE_ST/issues/1.json")"

t_section "9 - the websocket listener, the path Caddy carries wss on 443 to"
cp "$T_TMP/admin.pub" "$T_TMP/ws-keys"
printf '%s\n' 'expect ws-ready' "wait-file $T_TMP/end-ws" 'hup' > "$T_TMP/ws-host.steps"
# A bare host, not member-support.sh: this proves the transport alone, so --accept stands in for the person's yes.
python3 "$TERMINAL_RUN" "$T_TMP/ws-host.steps" "$T_TMP/ws-host.out" -- upterm host --server "ws://$WSADDR" --known-hosts "$T_TMP/kh" \
  --authorized-keys "$T_TMP/ws-keys" --accept --no-forwarding --no-sftp --name wsprobe -- sh -c 'echo ws-ready; exec sh' &
WSHOST=$!
_i=0; _sid=''
while [ -z "$_sid" ] && [ "$_i" -lt 100 ]; do
  _sid="$(upterm session info wsprobe -o json 2>/dev/null | jq -r 'select(.status == "ready") | .joinCommand | capture("://(?<u>[^@ ]+)@").u' 2>/dev/null)" || _sid=''
  [ -n "$_sid" ] || sleep 0.2; _i=$((_i + 1))
done
t_has "a host registers over the websocket listener" "$_sid" ':'
join "$T_TMP/admin" "ws://$_sid@$WSADDR" "$T_TMP/ws-join.out" 'wait 2' 'send echo ws-$((6*7))' 'expect ws-42' 'wait 1'
t_has "and a listed key joins through it" "$(cat "$T_TMP/ws-join.out")" 'ws-42'
join "$T_TMP/stranger" "ws://$_sid@$WSADDR" "$T_TMP/ws-stranger.out" 'wait 3'
t_eq "a key not listed doesn't" 255 "$JOIN_RC"
: > "$T_TMP/end-ws"; wait "$WSHOST" 2>/dev/null || :

kill "$RELAYD" 2>/dev/null
be_down
t_done
