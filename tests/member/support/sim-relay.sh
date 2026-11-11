#!/usr/bin/env sh
# sim-relay.sh (harbor#1278) — the hub's relay deployed as docs/how-to/member-support.md "Run the relay" deploys it, and a member's session through it.
# A relay box with systemd as PID 1 runs `sudo sh ~/relay/install.sh --host <name>` as the operator does; a second box is the laptop and the admin.
#   sh tests/member/support/sim-relay.sh     SUPPORT_REAL_BIN=<dir> reads the release archives from there, and install.sh takes --from (said so)
# Not *.test.sh, as real-upterm.sh isn't: it needs docker and fetches Caddy and the release. With no docker it FAILS (exit 2), never skips.
# Everything it makes is named sim-relay-*: the image sim-relay-box:local (kept, as a build cache), the network and two boxes, removed at the end.
# Never real DNS or ACME: the relay's name ends in .local, so the shipped Caddyfile, unchanged, takes Caddy's internal CA, and the laptop trusts that CA.
if [ "${1:-}" = --member ]; then INNER=1; else INNER=0; fi
REAL_HOME="$HOME"
HARBOR_TEST_SUITE_TIMEOUT="${HARBOR_TEST_SUITE_TIMEOUT:-1800}"; export HARBOR_TEST_SUITE_TIMEOUT   # an apt install is quiet for a while
if [ "$INNER" = 1 ]; then _n=sim-relay-member; else _n=sim-relay; fi
. "$(dirname "$0")/../../lib/core.sh"; t_init "$_n"
PIN="$T_ROOT/contracts/support-upterm.tsv"
pin() { awk -F'\t' -v k="$1" '$1 == k { print $2; exit }' "$PIN"; }
sum() { { sha256sum "$1" 2>/dev/null || shasum -a 256 "$1"; } | cut -d' ' -f1; }

if [ "$INNER" = 0 ]; then
  IMAGE=sim-relay-box:local; NET=sim-relay-net; HUB=sim-relay-hub; MEM=sim-relay-member
  RELAY_HOST=relay.sim-relay.local
  export DOCKER_CONFIG="${DOCKER_CONFIG:-$REAL_HOME/.docker}"
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 || { echo "sim-relay: no docker daemon; refusing to substitute a weaker check" >&2; exit 2; }
  ARCH="$(docker info --format '{{.Architecture}}')"
  case "$ARCH" in x86_64|amd64) ARCH=amd64 ;; aarch64|arm64) ARCH=arm64 ;; *) echo "sim-relay: no pinned binary for $ARCH" >&2; exit 2 ;; esac
  sr_down() { docker rm -f "$HUB" "$MEM" >/dev/null 2>&1; docker network rm "$NET" >/dev/null 2>&1; :; }
  # core.sh's own EXIT trap, with the boxes removed first: a run killed by the watchdog leaves nothing either.
  trap 'sr_down; _t_unwatch; chmod -R u+w "$T_TMP" 2>/dev/null; rm -rf "$T_TMP"' EXIT
  hub() { docker exec "$HUB" "$@"; }
  ops() { docker exec -u ops -w /home/ops "$HUB" sh -c "$1"; }
  mem() { docker exec "$MEM" "$@"; }
  until_ok() { # <tenths> <cmd...>: 0 once the command succeeds
    _w="$1"; shift; _i=0
    while [ "$_i" -lt "$_w" ]; do "$@" >/dev/null 2>&1 && return 0; sleep 0.5; _i=$((_i + 5)); done
    return 1
  }
  booted() { case "$(hub systemctl is-system-running 2>/dev/null)" in running|degraded) return 0 ;; *) return 1 ;; esac; }
  active() { [ "$(hub systemctl is-active "$1" 2>/dev/null)" = active ]; }
  mainpid() { hub systemctl show -p MainPID --value harbor-relay.service 2>/dev/null; }

  sr_down
  B="$T_TMP/real"; mkdir -p "$B"
  if [ -n "${SUPPORT_REAL_BIN:-}" ]; then
    for _p in "upterm sha256-linux-$ARCH" "uptermd uptermd-linux-$ARCH"; do
      _f="${_p%% *}_linux_$ARCH.tar.gz"
      cp "$SUPPORT_REAL_BIN/$_f" "$B/$_f" || exit 2
      [ "$(sum "$B/$_f")" = "$(pin "${_p#* }")" ] || { echo "sim-relay: $_f is not the pinned one" >&2; exit 2; }
    done
  fi
  # Ubuntu 24.04, as the VM is. The archive's policy-rc.d is a container's, not a VM's: without it apt starts Caddy, as it does on the VM.
  docker build -q -t "$IMAGE" - > "$T_TMP/build.out" 2>&1 <<'EOF' || { echo "sim-relay: the image did not build: $(tail -5 "$T_TMP/build.out")" >&2; exit 2; }
FROM ubuntu:24.04
RUN apt-get update -q && DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends \
      systemd systemd-sysv dbus sudo curl ca-certificates openssh-client jq python3 git procps iproute2 openssl bsdutils \
    && rm -rf /var/lib/apt/lists/* /usr/sbin/policy-rc.d \
    && useradd -m -s /bin/bash ops && printf 'ops ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/ops
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
EOF
  docker network create "$NET" >/dev/null || exit 2
  # systemd as PID 1 without --privileged: what a VM's PID 1 has and docker takes away, given back one by one. SYS_ADMIN, a writable cgroup and
  # shared mounts: systemd's cgroups and LoadCredential's mount; SYS_PTRACE: ProtectProc=invisible with PrivateUsers; BPF, NET_ADMIN: IPAddressDeny's
  # cgroup firewall; systempaths=unconfined, seccomp, apparmor: docker's masked /proc and filters, which a VM's systemd doesn't run under.
  docker run -d --name "$HUB" --hostname relay --network "$NET" --network-alias "$RELAY_HOST" --cgroupns=private \
    --cap-add SYS_ADMIN --cap-add SYS_PTRACE --cap-add BPF --cap-add NET_ADMIN \
    --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
    -e container=docker --tmpfs /run --tmpfs /run/lock --entrypoint sh "$IMAGE" \
    -c 'mount -o remount,rw /sys/fs/cgroup && mount --make-rshared / && exec /lib/systemd/systemd' >/dev/null || exit 2
  docker run -d --name "$MEM" --hostname laptop --network "$NET" "$IMAGE" sleep infinity >/dev/null || exit 2
  until_ok 600 booted || { echo "sim-relay: systemd did not boot: $(hub systemctl is-system-running 2>&1)" >&2; exit 2; }

  t_section "1 - install.sh, as the operator runs it, under a running systemd"
  t_eq "PID 1 on the relay box is systemd" systemd "$(hub ps -o comm= -p 1)"
  # gcloud compute scp --recurse relay contracts/support-upterm.tsv: both land in the operator's home.
  COPYFILE_DISABLE=1 tar -C "$T_ROOT" -cf - relay contracts/support-upterm.tsv \
    | docker exec -i -u ops -w /home/ops "$HUB" sh -c 'tar -xf - 2>/dev/null && mv contracts/support-upterm.tsv . && rmdir contracts'
  INSTALL='cp ~/support-upterm.tsv ~/relay/ && sudo sh ~/relay/install.sh --host '"$RELAY_HOST"
  if [ -n "${SUPPORT_REAL_BIN:-}" ]; then
    docker cp "$B/uptermd_linux_$ARCH.tar.gz" "$HUB:/home/ops""/uptermd_linux_$ARCH.tar.gz" >/dev/null
    hub sh -c 'mkdir -p ~ops/dl && mv ~ops/uptermd_*.tar.gz ~ops/dl/ && chown -R ops ~ops/dl'
    INSTALL="$INSTALL --from ~/dl"
    echo "  note: SUPPORT_REAL_BIN is set, so install.sh took --from; the download itself was not run"
  fi
  _rc=0; ops "$INSTALL" > "$T_TMP/install.out" 2>&1 || _rc=$?
  t_eq "the documented install exits 0: $(tail -2 "$T_TMP/install.out" | tr '\n' ' ')" 0 "$_rc"
  t_has "and names the relay" "$(cat "$T_TMP/install.out")" "relay: wss://$RELAY_HOST"
  t_has "and made the host key once" "$(cat "$T_TMP/install.out")" 'made a new host key'
  RELAY_KEY="$(ops 'sudo sh ~/relay/install.sh --key' | head -n 1)"
  t_has "--key reads it back as an ed25519 key" "$RELAY_KEY" 'ssh-ed25519 '
  t_has "and it is the one the install printed" "$(cat "$T_TMP/install.out")" "relay_key: $RELAY_KEY"
  sleep 6   # past RestartSec, so a unit that exits at once is seen restarting, not active
  active harbor-relay.service && t_pass || t_fail "harbor-relay.service is $(hub systemctl is-active harbor-relay.service): $(hub journalctl -u harbor-relay.service --no-pager -n 5 2>&1)"
  t_eq "it has not restarted since" 0 "$(hub systemctl show -p NRestarts --value harbor-relay.service)"
  active caddy.service && t_pass || t_fail "caddy.service is $(hub systemctl is-active caddy.service)"
  P0="$(mainpid)"
  _u="$(hub stat -c %u "/proc/$P0")"   # systemd's dynamic range is 61184-65519; the box's nsswitch has no name for it
  t_eq "uptermd runs as a dynamic user (uid $_u)" 1 "$(awk -v u="${_u:-0}" 'BEGIN { print (u >= 61184 && u <= 65519) ? 1 : 0 }')"
  t_eq "and listens on loopback alone" "127.0.0.1:2223 127.0.0.1:8080 " \
    "$(hub ss -Hltnp | awk '/uptermd/ { print $4 }' | sort | tr '\n' ' ')"
  t_eq "the host key is root's alone" '600 root' "$(hub stat -c '%a %U' /etc/harbor-relay/host_key)"
  t_eq "the journal has no firewall error" '' "$(hub journalctl -u harbor-relay.service --no-pager | grep -i 'bpf' || :)"

  t_section "2 - the unit's own sandbox, as systemd applies it"
  # The installed unit's [Service] lines, each passed to a transient unit that tries one connection: IPAddressDeny is a cgroup
  # firewall, so only a process systemd starts under it shows whether it holds here.
  probe() { # <addr> <port> [no-ip]: the exit code of a connect run under the unit's own settings
    hub sh -c '
      a="$1"; p="$2"; noip="$3"; set --
      while IFS= read -r l; do
        case "$l" in ExecStart=*|Restart=*|RestartSec=*) continue ;; esac
        [ -z "$noip" ] || case "$l" in IPAddress*) continue ;; esac
        set -- "$@" -p "$l"
      done <<EOF
$(sed -n "/^\[Service\]/,/^\[/{/^[A-Z][A-Za-z]*=/p}" /etc/systemd/system/harbor-relay.service)
EOF
      systemd-run --wait -q -p RuntimeMaxSec=8 "$@" /bin/bash -c "exec 3<>/dev/tcp/$a/$p"' sh "$1" "$2" "${3:-}" >/dev/null 2>&1
  }
  HUBIP="$(docker inspect -f "{{(index .NetworkSettings.Networks \"$NET\").IPAddress}}" "$HUB")"
  _rc=0; probe 127.0.0.1 8080 || _rc=$?; t_eq "loopback is reachable from inside it" 0 "$_rc"
  _rc=0; probe "$HUBIP" 443 1 || _rc=$?; t_eq "the box's own address is reachable without the IP lines (the control)" 0 "$_rc"
  _rc=0; probe "$HUBIP" 443 || _rc=$?; [ "$_rc" != 0 ] && t_pass || t_fail "with the unit's IPAddressDeny, $HUBIP:443 was still reached"
  hub systemctl restart harbor-relay.service
  until_ok 100 active harbor-relay.service && [ "$(mainpid)" != "$P0" ] && t_pass || t_fail "systemctl restart did not bring it back"
  P1="$(mainpid)"; N1="$(hub systemctl show -p NRestarts --value harbor-relay.service)"
  hub kill -9 "$P1"
  _i=0; while [ "$_i" -lt 40 ]; do _p="$(mainpid)"; { [ "$_p" != 0 ] && [ "$_p" != "$P1" ] && active harbor-relay.service; } && break; sleep 0.5; _i=$((_i + 1)); done
  { [ "$(mainpid)" != 0 ] && [ "$(mainpid)" != "$P1" ] && active harbor-relay.service; } && t_pass || t_fail "a killed uptermd was not restarted"
  t_eq "systemd counted that restart" "$((N1 + 1))" "$(hub systemctl show -p NRestarts --value harbor-relay.service)"

  t_section "3 - systemd-analyze, read from the live unit"
  t_eq "verify has nothing to say" '' "$(hub systemd-analyze verify /etc/systemd/system/harbor-relay.service 2>&1)"
  SCORE="$(hub systemd-analyze security harbor-relay.service --no-pager 2>/dev/null | sed -n 's/.*Overall exposure level for [^:]*: \([0-9.]*\).*/\1/p')"
  CSCORE="$(hub systemd-analyze security caddy.service --no-pager 2>/dev/null | sed -n 's/.*Overall exposure level for [^:]*: \([0-9.]*\).*/\1/p')"
  echo "  harbor-relay.service exposure: ${SCORE:-none}; caddy.service (Ubuntu's own unit, the TLS end): ${CSCORE:-none}"
  t_eq "exposure under 2.0 of 10: $SCORE" 1 "$(awk -v x="${SCORE:-99}" 'BEGIN { print (x < 2.0) ? 1 : 0 }')"

  t_section "4 - TLS on 443 through Caddy, from the laptop"
  t_eq "the Caddyfile is proxy.txt with the name filled in, no overlay" '' \
    "$(sed "s/@RELAY_HOST@/$RELAY_HOST/g" "$T_ROOT/relay/proxy.txt" | docker exec -i "$HUB" sh -c 'diff - /etc/caddy/Caddyfile' 2>&1)"
  t_hasnt "Caddy never tried ACME for it" "$(hub journalctl -u caddy.service --no-pager; echo .)" 'acme-v02'
  _o="$(mem curl -sS -m 10 "https://$RELAY_HOST/health" 2>&1)" && _rc=0 || _rc=$?
  t_eq "a laptop that doesn't trust the certificate is refused" 60 "$_rc"
  hub cat /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt > "$T_TMP/root.crt"
  docker cp "$T_TMP/root.crt" "$MEM:/usr/local/share/ca-certificates/sim-relay-root.crt" >/dev/null
  mem update-ca-certificates >/dev/null 2>&1
  t_has "the certificate names the relay" "$(mem sh -c "openssl s_client -connect $RELAY_HOST:443 -servername $RELAY_HOST -verify_return_error </dev/null 2>/dev/null | openssl x509 -noout -ext subjectAltName")" "DNS:$RELAY_HOST"
  t_eq "and verifies once its CA is trusted, as a public CA would be" OK "$(mem curl -sS -m 10 "https://$RELAY_HOST/health" 2>&1)"
  t_eq "port 80 sends a browser to https" "308 https://$RELAY_HOST/health" "$(mem curl -sS -m 10 -o /dev/null -w '%{http_code} %{redirect_url}' "http://$RELAY_HOST/health")"
  _rc=0; mem bash -c "exec 3<>/dev/tcp/$RELAY_HOST/443" 2>/dev/null || _rc=$?; t_eq "443 is open from the laptop (the control)" 0 "$_rc"
  for _port in 2223 8080; do
    _rc=0; mem bash -c "exec 3<>/dev/tcp/$RELAY_HOST/$_port" 2>/dev/null || _rc=$?
    [ "$_rc" != 0 ] && t_pass || t_fail "uptermd's $_port is reachable from the laptop"
  done

  t_section "5 - a member's session, end to end through wss"
  COPYFILE_DISABLE=1 tar -C "$T_ROOT" -cf - bin contracts relay standards tests/lib tests/hub/fixtures tests/member/support \
    | docker exec -i "$MEM" sh -c 'mkdir -p /opt/t && tar -xf - -C /opt/t 2>/dev/null'
  if [ -n "${SUPPORT_REAL_BIN:-}" ]; then
    docker cp "$B/upterm_linux_$ARCH.tar.gz" "$MEM:/tmp/upterm_linux_$ARCH.tar.gz" >/dev/null
    _get=:
  else
    _get="curl -q --silent --show-error --fail --location --proto =https --output /tmp/upterm_linux_$ARCH.tar.gz https://github.com/owenthereal/upterm/releases/download/v$(pin version)/upterm_linux_$ARCH.tar.gz"
  fi
  mem sh -c "$_get && [ \"\$(sha256sum /tmp/upterm_linux_$ARCH.tar.gz | cut -d' ' -f1)\" = $(pin "sha256-linux-$ARCH") ] && mkdir -p /opt/real && tar -xzf /tmp/upterm_linux_$ARCH.tar.gz -C /opt/real upterm" \
    || { t_fail "the pinned upterm could not be put on the laptop"; t_done; }
  docker exec -e SIM_RELAY_HOST="$RELAY_HOST" -e SIM_RELAY_KEY="$RELAY_KEY" -e SUPPORT_REAL_DIR=/opt/real "$MEM" \
    sh /opt/t/tests/member/support/sim-relay.sh --member > "$T_TMP/member.out" 2>&1
  cat "$T_TMP/member.out"
  _c="$(sed -n 's/^sim-relay-member: \([0-9]*\) passed, \([0-9]*\) failed$/\1 \2/p' "$T_TMP/member.out")"
  if [ -n "$_c" ]; then T_PASS=$((T_PASS + ${_c% *})); T_FAIL=$((T_FAIL + ${_c#* })); t_pass
  else t_fail "the laptop's run printed no count"; fi

  t_section "6 - the host key outlives a re-install and a reboot"
  _rc=0; ops "$INSTALL" > "$T_TMP/install2.out" 2>&1 || _rc=$?
  t_eq "install.sh runs again" 0 "$_rc"
  t_hasnt "without a new key" "$(cat "$T_TMP/install2.out")" 'made a new host key'
  t_eq "the key is the same" "$RELAY_KEY" "$(ops 'sudo sh ~/relay/install.sh --key' | head -n 1)"
  docker restart -t 30 "$HUB" >/dev/null
  until_ok 600 booted && t_pass || t_fail "the relay box did not boot again: $(hub systemctl is-system-running 2>&1)"
  until_ok 200 active harbor-relay.service && t_pass || t_fail "harbor-relay.service did not come up at boot"
  until_ok 200 active caddy.service && t_pass || t_fail "caddy.service did not come up at boot"
  t_eq "the key is the same after the reboot" "$RELAY_KEY" "$(ops 'sudo sh ~/relay/install.sh --key' | head -n 1)"
  # The relay as a laptop meets it: a session registers only if the relay proves the key policy pins.
  mem sh -c "printf '@cert-authority [%s]:443 %s\n' $RELAY_HOST '$RELAY_KEY' > /tmp/kh && ssh-keygen -q -t ed25519 -N '' -f /tmp/k </dev/null && cp /tmp/k.pub /tmp/keys"
  mem sh -c "(timeout 40 script -qfc '/opt/real/upterm host --server wss://$RELAY_HOST --known-hosts /tmp/kh --authorized-keys /tmp/keys --accept --no-forwarding --no-sftp --no-exec --name reboot -- sh' /dev/null >/dev/null 2>&1 &)"
  _i=0; _st=''
  while [ "$_i" -lt 30 ] && [ "$_st" != ready ]; do
    _st="$(mem sh -c '/opt/real/upterm session info reboot -o json 2>/dev/null | jq -r .status' 2>/dev/null)"; sleep 1; _i=$((_i + 1))
  done
  t_eq "a session pinned to the first key registers after the reboot" ready "$_st"
  mem sh -c 'pkill -f "upterm host" || :'

  t_section "7 - an install whose relay can't start says so"
  # Something else on the VM holds uptermd's SSH port: uptermd exits at once, and systemd restarts it every RestartSec.
  hub systemctl stop harbor-relay.service
  hub systemd-run -q --unit sim-relay-squat python3 -c 'import socket,time; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1", 2223)); s.listen(); time.sleep(600)'
  until_ok 100 sh -c "docker exec $HUB ss -Hltn | grep -q '127.0.0.1:2223 '"
  _rc=0; ops "$INSTALL" > "$T_TMP/install3.out" 2>&1 || _rc=$?
  { ! active harbor-relay.service || [ "$(hub systemctl show -p NRestarts --value harbor-relay.service)" != 0 ]; } && t_pass \
    || t_fail "the planted port clash didn't stop uptermd, so this section proves nothing"
  t_eq "install.sh exits 1, not 0, when the service it started dies" 1 "$_rc"
  t_has "and points at the journal" "$(cat "$T_TMP/install3.out")" 'journalctl -u harbor-relay'
  t_hasnt "and doesn't announce the relay" "$(cat "$T_TMP/install3.out")" "relay: wss://"
  hub systemctl stop sim-relay-squat.service
  _rc=0; ops "$INSTALL" > "$T_TMP/install4.out" 2>&1 || _rc=$?
  t_eq "with the port free, the same install exits 0: $(tail -1 "$T_TMP/install4.out"; hub journalctl -u harbor-relay.service --no-pager -n 4 | cut -c1-160)" 0 "$_rc"
  active harbor-relay.service && t_pass || t_fail "harbor-relay.service is $(hub systemctl is-active harbor-relay.service) after the second install"

  t_section "8 - upterm's public relay is refused by the install"
  _o="$(ops 'sudo sh ~/relay/install.sh --host uptermd.upterm.dev' 2>&1)" && _rc=0 || _rc=$?
  t_eq "install.sh --host uptermd.upterm.dev exits 1" 1 "$_rc"
  t_has "and says why" "$_o" "upterm's public relay"
  _o="$(ops 'sudo sh ~/relay/install.sh --host eu.uptermd.upterm.dev' 2>&1)" && _rc=0 || _rc=$?
  t_eq "a name under it too" 1 "$_rc"
  t_eq "and the relay that runs is untouched" "$RELAY_KEY" "$(ops 'sudo sh ~/relay/install.sh --key' | head -n 1)"

  sr_down
  t_done
fi

# ---- inside the laptop box: member-support.sh and hub-support.sh, the board stubbed, the relay real ----
. "$T_ROOT/tests/hub/fixtures/board-env.sh"
. "$T_ROOT/tests/hub/fixtures/support-env.sh"
TERMINAL_RUN="$T_ROOT/tests/hub/fixtures/terminal_run.py"
PTY_RUN_TIMEOUT=70; export PTY_RUN_TIMEOUT
RELAY_HOST="$SIM_RELAY_HOST"; RELAY_KEY="$SIM_RELAY_KEY"; WSS="wss://$RELAY_HOST"
se_up
cp "$SUPPORT_REAL_DIR/upterm" "$BE_BIN/upterm"; ln -s "$SUPPORT_REAL_DIR/upterm" "$T_BIN/upterm"
for _n in admin stranger; do ssh-keygen -q -t ed25519 -N '' -C "$_n" -f "$T_TMP/$_n"; done
printf '@cert-authority [%s]:443 %s\n' "$RELAY_HOST" "$RELAY_KEY" > "$T_TMP/kh"
real_policy() { # [jq edit]: the deployed relay and the admin's key, nothing else
  se_reset ".support = {keys: [\"$(cat "$T_TMP/admin.pub")\"], relay: \"$WSS\", relay_key: \"$RELAY_KEY\"} | ${1:-.}"
  se_settings uptermd.upterm.dev "$RELAY_HOST"
}
start() { # <name> <steps...>: a person at a terminal, in the background. Transcript $T_TMP/<name>.out
  _s="$1"; shift
  printf '%s\n' "$@" > "$T_TMP/$_s.steps"
  python3 "$TERMINAL_RUN" "$T_TMP/$_s.steps" "$T_TMP/$_s.out" -- sh "$SE_SUPPORT" &
  PERSON=$!
}
await() { # <file> <text> [tenths]
  _i=0
  while [ "$_i" -lt "${3:-400}" ]; do grep -qF -- "$2" "$1" 2>/dev/null && return 0; sleep 0.1; _i=$((_i + 1)); done
  return 1
}
board_has() { # <prefix> [tenths]
  _i=0
  while [ "$_i" -lt "${2:-300}" ]; do se_comments | grep -q "^$1" && return 0; sleep 0.1; _i=$((_i + 1)); done
  return 1
}
join() { # <key> <target> <out> <steps...>: a guest at a terminal. JOIN_RC
  _k="$1"; _t="$2"; _o="$3"; shift 3
  printf '%s\n' "$@" > "$T_TMP/join.steps"
  JOIN_RC=0; python3 "$TERMINAL_RUN" "$T_TMP/join.steps" "$_o" -- upterm join -i "$_k" --known-hosts "$T_TMP/kh" "$_t" || JOIN_RC=$?
}
viassh() { # <sid> <ssh args...>: plain ssh through `upterm proxy`, the relay's host certificate checked against policy's key
  _sid="$1"; shift
  ssh -i "$T_TMP/admin" -p 443 -o BatchMode=yes -o UserKnownHostsFile="$T_TMP/kh" -o StrictHostKeyChecking=yes \
    -o "ProxyCommand=upterm proxy wss://$_sid@$RELAY_HOST" "$@"
}
ASK1='expect Type update'; ASK2='send fix'; ASK3='expect the word allow'; ASK4='send allow'

t_section "M1 - a member says yes, and the session registers through wss on 443"
real_policy
se_accept_soon
start a "$ASK1" "$ASK2" "$ASK3" "$ASK4" 'expect Start the session? [y/n]' 'wait 1' 'key y' 'wait 0.5' 'send' "wait-file $T_TMP/end-a" 'hup'
await "$T_TMP/a.out" 'Start the session? [y/n]' 500 && t_pass || t_fail "the question never came: $(tail -5 "$T_TMP/a.out")"
t_has "upterm named a session on the relay's 443" "$(sed -n 's/.*upterm join \(wss:[^ ]*\).*/\1/p' "$T_TMP/a.out" | head -n 1)" "@$RELAY_HOST"
board_has session && t_pass || t_fail "the session never reached the board: $(tail -5 "$T_TMP/a.out")"
SID="$(se_comments | sed -n 's/^session s-[0-9a-f]* //p')"
TARGET="wss://$SID@$RELAY_HOST"

t_section "M2 - the listed admin joins through harbor hub support, over TLS"
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
fix_policy() { cp "$T_TMP/state-policy.json" "$T_FIX/policy.json"; cp "$T_TMP/state-policy.json.sig" "$T_FIX/policy.json.sig"; cp "$BE_ROOT/hub-signers" "$T_FIX/hub-signers"; }
fix_policy
connect() { # <steps file> <out>: harbor hub support connect, as the admin at a terminal. CONNECT_RC
  CONNECT_RC=0
  (
    unset HARBOR_MEMBER_ROLE HARBOR_MEMBER_LOGIN
    PTY_RUN_TIMEOUT=25 python3 "$TERMINAL_RUN" "$1" "$2" -- sh "$T_ROOT/bin/hub-support.sh" connect "$(se_id)" --key "$T_TMP/admin" --hub fixture-org/fixture-hub
  ) || CONNECT_RC=$?
}
printf '%s\n' 'wait 3' 'send echo guest-$((6*7))-$(id -un)' "expect guest-42-$(id -un)" 'wait 1' > "$T_TMP/connect.steps"
connect "$T_TMP/connect.steps" "$T_TMP/connect.out"
t_has "the admin's terminal runs the command, as the member's account" "$(cat "$T_TMP/connect.out")" "guest-42-$(id -un)"
await "$T_TMP/a.out" 'guest-42' 50 && t_pass || t_fail "the person didn't see it: $(tail -5 "$T_TMP/a.out")"
# The same join with no CA trusted: the certificate is what lets it through, not the network.
printf '%s\n' 'wait 4' > "$T_TMP/notls.steps"
_rc=0; SSL_CERT_FILE=/dev/null SSL_CERT_DIR=/nonexistent python3 "$TERMINAL_RUN" "$T_TMP/notls.steps" "$T_TMP/notls.out" -- \
  upterm join -i "$T_TMP/admin" --known-hosts "$T_TMP/kh" "$TARGET" || _rc=$?
t_has "with no CA trusted, the join fails on the certificate" "$(cat "$T_TMP/notls.out")" 'certificate'
[ "$_rc" != 0 ] && t_pass || t_fail "a join with no CA trusted exited 0"

t_section "M3 - a key not on the list can't join"
join "$T_TMP/stranger" "$TARGET" "$T_TMP/stranger.out" 'wait 4'
t_has "the relay's own words" "$(cat "$T_TMP/stranger.out")" 'refused your keys'
t_eq "and it left with no session" 255 "$JOIN_RC"

t_section "M4 - exec, sftp and forwarding are refused, through the same wss"
_o="$(viassh "$SID" "$SID@$RELAY_HOST" id 2>&1 </dev/null)" && _rc=0 || _rc=$?
t_eq "ssh with a command is refused" 1 "$_rc"
t_has "by the member's upterm, so the route got there" "$_o" "doesn't run commands a guest names"
_o="$(viassh "$SID" -s "$SID@$RELAY_HOST" sftp 2>&1 </dev/null)" && _rc=0 || _rc=$?
t_eq "the sftp subsystem is refused" 255 "$_rc"
t_has "by name" "$_o" 'subsystem request failed'
_o="$(viassh "$SID" -W 127.0.0.1:22 "$SID@$RELAY_HOST" 2>&1 </dev/null)" && _rc=0 || _rc=$?
t_eq "a forward to the laptop's side (-W) is refused" 255 "$_rc"
t_has "because forwarding is off" "$_o" 'port forwarding is disabled'
_o="$(viassh "$SID" -N -o ExitOnForwardFailure=yes -R 127.0.0.1:0:127.0.0.1:1 "$SID@$RELAY_HOST" 2>&1 </dev/null)" && _rc=0 || _rc=$?
t_eq "a reverse forward (-R) is refused" 255 "$_rc"
t_has "by name" "$_o" 'remote port forwarding failed'

t_section "M5 - closing the window ends it"
: > "$T_TMP/end-a"
wait "$PERSON" 2>/dev/null || :
board_has "closed $(se_id)" && t_pass || t_fail "no closed comment: $(se_comments | tail -3)"
t_eq "the record" "requested accepted started ended " "$(se_events)"
_i=0; while pgrep -f 'upterm host' >/dev/null 2>&1 && [ "$_i" -lt 50 ]; do sleep 0.2; _i=$((_i + 1)); done
t_eq "no upterm is left running" 0 "$(pgrep -f 'upterm host' | wc -l | tr -d ' ')"
join "$T_TMP/admin" "$TARGET" "$T_TMP/after.out" 'wait 4'
t_eq "the session id is dead on the relay" 255 "$JOIN_RC"

cw_target() { printf 'wss://%s@%s' "$1" "$RELAY_HOST"; }
. "$T_ROOT/tests/member/support/colleague.sh"

t_section "M6 - upterm's public relay is refused by both scripts, before anything dials it"
se_stub_upterm   # records every call: none may come
real_policy ".support.relay = \"wss://uptermd.upterm.dev\""
se_run "$ASK1" "$ASK2" "$ASK3" "$ASK4" 'wait 2'
t_has "member-support.sh refuses it" "$SE_OUT" 'could not be read'
t_hasnt "and asks nobody to start" "$SE_OUT" '[y/n]'
t_eq "no request was filed" '' "$(find "$BE_ST/issues" -name '*.json')"
t_eq "and upterm never ran" no "$([ -e "$SE_UP" ] && echo yes || echo no)"
# The admin's side, with an open request and a posted session as the board would have them, and a policy naming the public relay.
_id=s-0123456789abcdef
_body="$(printf 'harbor-support: 1\nid: %s\nmember: alice\nreason: fix\ncore: 0123456789ab\ncc: @fixture-admin' "$_id")"
jq -n --arg t "support $_id" --arg b "$_body" '{number: 1, title: $t, body: $b, state: "open", user: {login: "alice", type: "User"}, created_at: "2026-11-07T09:00:00Z"}' > "$BE_ST/issues/1.json"
printf '[]' > "$BE_ST/comments/1.json"; be_comment 1 alice "session $_id abc:ZGVm"
fix_policy
printf '#!/bin/sh\necho "$@" >> %s/admin-upterm.calls\n' "$T_TMP" > "$T_BIN/upterm.rec"; chmod +x "$T_BIN/upterm.rec"; rm -f "$T_BIN/upterm"; mv "$T_BIN/upterm.rec" "$T_BIN/upterm"
printf '%s\n' 'wait 3' > "$T_TMP/pub.steps"
connect "$T_TMP/pub.steps" "$T_TMP/pub.out"
t_eq "hub-support.sh connect exits 1" 1 "$CONNECT_RC"
t_has "and says the policy fails" "$(cat "$T_TMP/pub.out")" 'fails its format'
t_eq "and upterm never ran" no "$([ -e "$T_TMP/admin-upterm.calls" ] && echo yes || echo no)"

be_down
t_done
