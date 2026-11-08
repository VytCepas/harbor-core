#!/bin/sh
# install.sh (harbor#1278) — the hub's own upterm relay on a small Linux VM: uptermd at the pinned digest, run by systemd as a dynamic user
# that reaches nothing but loopback, behind Caddy for wss on 443. Why and the operator's steps: docs/how-to/member-support.md, "Run the relay".
#   sudo sh install.sh --host <relay host> [--from <dir>]   install, or install again over the same host key
#   sudo sh install.sh --key                                the relay's key for policy `support.relay_key`, then its fingerprint
#   sh install.sh --root <dir> --host <host> [--from <dir>] only the files, under <dir>: no root, no apt, no systemctl (tests)
# --from names a folder holding uptermd_linux_<arch>.tar.gz; without it the release is downloaded. Either way its digest must be the pin's.
# Exit 0 done, 1 refused, 2 usage. Run it from a copy of relay/ with support-upterm.tsv beside it, or from a harbor checkout.
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin; export PATH
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PIN="$HERE/support-upterm.tsv"; [ -f "$PIN" ] || PIN="$HERE/../contracts/support-upterm.tsv"

say() { printf '%s\n' "$*"; }
die() { printf 'install.sh: %s\n' "$1" >&2; exit "${2:-1}"; }
usage() { sed -n '4,6p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
pin() { awk -F'\t' -v k="$1" '/^#/ { next } $1 == k { print $2; found = 1; exit } END { exit !found }' "$PIN"; }
sum() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

MODE=install; ROOT=''; HOST=''; FROM=''
while [ $# -gt 0 ]; do
  case "$1" in
    --key) MODE=key ;;
    --root|--host|--from) [ $# -ge 2 ] || usage
      case "$1" in --root) ROOT="$2" ;; --host) HOST="$2" ;; --from) FROM="$2" ;; esac; shift ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) usage ;;
  esac
  shift
done
case "$ROOT" in ''|/*) ;; *) die "--root wants an absolute path, got '$ROOT'" 2 ;; esac
ETC="$ROOT/etc/harbor-relay"

if [ "$MODE" = key ]; then
  [ -s "$ETC/host_key.pub" ] || die "no host key at $ETC/host_key.pub: install first"
  cut -d' ' -f1,2 "$ETC/host_key.pub"
  ssh-keygen -l -f "$ETC/host_key.pub"
  exit 0
fi

[ -f "$PIN" ] || die "no support-upterm.tsv beside this script or in ../contracts: it holds the digest the download must match"
# The name laptops dial, and the principal on the relay's certificate. Never upterm's public relay, which this replaces.
case "$HOST" in ''|-*|.*|*.|*..*|*[!abcdefghijklmnopqrstuvwxyz0123456789.-]*) die "--host wants the relay's DNS name in lower case, got '$HOST'" 2 ;; esac
case "$HOST" in *.*) ;; *) die "--host wants a full DNS name with a dot, got '$HOST'" 2 ;; esac
_pub="$(pin public-relay)" || die "$PIN has no public-relay row"
case "$HOST" in "$_pub"|*".$_pub") die "--host $HOST is upterm's public relay, which is never used" ;; esac
if [ -z "$ROOT" ]; then
  [ "$(id -u)" -eq 0 ] || die 'run it as root (sudo), or with --root <dir> to write the files only'
  [ "$(uname -s)" = Linux ] || die 'the relay runs on Linux'
  command -v systemctl >/dev/null 2>&1 || die 'systemd is needed: the unit is what limits uptermd'
fi
for _t in ssh-keygen tar sed awk; do command -v "$_t" >/dev/null 2>&1 || die "$_t is missing"; done

case "$(uname -m)" in x86_64|amd64) ARCH=amd64 ;; aarch64|arm64) ARCH=arm64 ;; *) die "no pinned uptermd for $(uname -m)" ;; esac
VERSION="$(pin version)" || die "$PIN has no version"
WANT="$(pin "uptermd-linux-$ARCH")" || die "$PIN has no uptermd digest for linux-$ARCH"

W="$(mktemp -d "${TMPDIR:-/tmp}/harbor-relay.XXXXXX")"; trap 'rm -rf "$W"' EXIT; trap 'exit 130' INT TERM
TAR="uptermd_linux_$ARCH.tar.gz"
if [ -n "$FROM" ]; then cp "$FROM/$TAR" "$W/$TAR" || die "no $TAR in $FROM"
else
  command -v curl >/dev/null 2>&1 || die 'curl is missing'
  curl -q --silent --show-error --fail --location --proto '=https' --connect-timeout 20 --max-time 600 --output "$W/$TAR" \
    "https://github.com/owenthereal/upterm/releases/download/v$VERSION/$TAR" || die "uptermd $VERSION could not be downloaded"
fi
GOT="$(sum "$W/$TAR")"
[ "$GOT" = "$WANT" ] || die "refused: $TAR is not the pinned one (sha256 $GOT, pinned $WANT)"
mkdir "$W/x"; tar -xzf "$W/$TAR" -C "$W/x" uptermd || die "$TAR holds no uptermd"
say "uptermd $VERSION for linux-$ARCH matches its pin"

# Caddy first, so its package's own Caddyfile is the one replaced below. Ubuntu's archive signs it.
if [ -z "$ROOT" ] && ! command -v caddy >/dev/null 2>&1; then
  apt-get update -q && DEBIAN_FRONTEND=noninteractive apt-get install -y -q caddy || die 'caddy could not be installed from the Ubuntu archive'
fi

mkdir -p "$ROOT/usr/local/bin" "$ROOT/etc/systemd/system" "$ROOT/etc/caddy"
(umask 022; mkdir -p "$ETC")
cp "$W/x/uptermd" "$W/uptermd.new" && chmod 0755 "$W/uptermd.new" && mv -f "$W/uptermd.new" "$ROOT/usr/local/bin/uptermd"
# One key for the life of the relay: laptops pin it through signed policy, so a new one means a policy re-sign. Never replaced here.
if [ ! -s "$ETC/host_key" ]; then
  (umask 077; ssh-keygen -q -t ed25519 -N '' -C harbor-relay -f "$ETC/host_key" </dev/null) || die 'the host key could not be made'
  say "made a new host key: put it in policy (sudo sh $0 --key)"
fi
chmod 0600 "$ETC/host_key"; chmod 0644 "$ETC/host_key.pub"
sed "s/@RELAY_HOST@/$HOST/g" "$HERE/relay-settings.txt" > "$ETC/relay.env"
sed "s/@RELAY_HOST@/$HOST/g" "$HERE/proxy.txt" > "$ROOT/etc/caddy/Caddyfile"
cp "$HERE/relay.service" "$ROOT/etc/systemd/system/harbor-relay.service"
chmod 0644 "$ETC/relay.env" "$ROOT/etc/caddy/Caddyfile" "$ROOT/etc/systemd/system/harbor-relay.service"

if [ -z "$ROOT" ]; then
  systemctl daemon-reload
  systemctl enable harbor-relay.service >/dev/null 2>&1 || die 'harbor-relay.service could not be enabled'
  systemctl restart harbor-relay.service || die 'harbor-relay.service did not start: journalctl -u harbor-relay'
  systemctl reload-or-restart caddy.service || die 'caddy did not take the new Caddyfile: journalctl -u caddy'
  # restart returns once uptermd is started, so one that exits at once reads as started. Past the unit's RestartSec, the same process must still run.
  _pid="$(systemctl show -p MainPID --value harbor-relay.service)"
  sleep 7
  { systemctl is-active --quiet harbor-relay.service && [ "$_pid" != 0 ] && [ "$(systemctl show -p MainPID --value harbor-relay.service)" = "$_pid" ]; } \
    || die 'harbor-relay.service started and then stopped: journalctl -u harbor-relay'
fi
say "relay: wss://$HOST"
say "relay_key: $(cut -d' ' -f1,2 "$ETC/host_key.pub")"
