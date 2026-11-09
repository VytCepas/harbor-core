#!/usr/bin/env sh
# member-install.sh (harbor#1278) — IT's one setup for a named member who isn't an admin. Run as root; asks nothing. docs/how-to/member-install.md.
#   sudo sh member-install.sh --user <member> --hub <owner/name> --login <github login> --signers <file> --pin <commit>
#                             [--mcp-allow <file>] [--token-stdin] [--windows-out <file>]
#   sudo sh member-install.sh --user <member> --store-check    before the token: the store writes and reads back as the member, as a hook does
#   sudo sh member-install.sh --user <member> --token-stdin    the token step alone, with IT beside the member; the value comes on stdin
#   sudo sh member-install.sh --user <member> --uninstall      leaving: only IT can run it, because the floor is root's
# Exit: 0 done, 1 refused, 2 usage, 3 on WSL, waiting for the PowerShell (run it, then run this again), 4 installed but no token stored,
# 5 installed and the token stored, but no verified first policy: the laptop refuses every call until one verifies.
#
# Order is the point. Nothing is written until a higher policy source is ruled out; the tree is built whole in a stage, then landed files first
# and managed-settings.json last, so settings never name a script that isn't there. User steps run as the member, because a root write into a
# folder the member owns can be aimed anywhere by a link. On WSL root can't write C:\Program Files, so the same stage goes out as PowerShell.
# HARBOR_SCOPE_MANAGED_SETTINGS moves the target for tests, and only then may this run without root; under root it is refused.
set -eu
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(CDPATH='' cd -- "$HERE/.." && pwd)"
# Under root a user-writable dir on PATH would run its tools as root. A test needs its stubs, and has no privilege to protect.
[ "$(id -u)" -ne 0 ] || { PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH; }
. "$HERE/library-log.sh"
. "$HERE/library-hub.sh"
log_init member-install
MEMBER_MANAGED_LIB=1; . "$HERE/member-managed.sh"; MEMBER_MANAGED_LIB=0
log_init member-install

TOKEN_REF=hub-token
OBS_HOST=member
SINK_REL="MEMORY/OBSERVABILITY/$OBS_HOST/guard-decisions.jsonl"
PS1_DEFAULT=/opt/harbor-member.ps1

die() { log_fail "$1"; if [ -n "${2:-}" ]; then log_fix "$2"; else log_nofix 'docs/how-to/member-install.md'; fi; log_end || :; exit "${3:-1}"; }
_as_member() { sudo -u "$MEMBER" -H "$@"; }
# Every user step is run this way. The argument array goes straight to sudo: no value reaches a shell string.
member_group() { id -gn "$MEMBER"; }
root_group() { if [ "$OS" = Darwin ]; then printf wheel; else printf root; fi; }

# A member who is an admin can edit the managed source, so "the agent can't change it" would be false on that laptop (plan, Known limits).
# MEMBER_ROOT_GROUPS are root by another name: docker, lxd, incus, libvirt and microk8s start a privileged container or VM that mounts the
# managed root, and disk writes the raw block device it sits on.
MEMBER_ROOT_GROUPS='sudo admin wheel root docker lxd incus incus-admin libvirt libvirtd microk8s disk'
member_refuse_admin() {
  for _g in $(id -Gn "$MEMBER"); do
    case " $MEMBER_ROOT_GROUPS " in *" $_g "*) die "$MEMBER is in the group $_g: an admin can remove all of this, so this laptop can't be a member box" "remove $MEMBER from $_g, then run this again" ;; esac
  done
  # A sudoers grant needs no group, so sudo itself is asked. The one line that may stand is this install's own helper rule, from an earlier run.
  command -v sudo >/dev/null 2>&1 || return 0
  _own="(root) NOPASSWD: /bin/sh $MROOT/bin/member-prereqs.sh"
  sudo -n -l -U "$MEMBER" 2>/dev/null | sed -n '/may run the following commands/,$p' | sed 1d | sed -e 's/^[[:space:]]*//' -e 's/\\//g' -e '/^$/d' > "$_SUDOL"
  while IFS= read -r _l; do
    [ "$_l" = "$_own" ] || die "$MEMBER has a sudoers grant ($_l): an admin can remove all of this, so this laptop can't be a member box" "remove the grant, then run this again: sudo -l -U $MEMBER"
  done < "$_SUDOL"
}
# member_pkg_list <manager> -> the packages, from the one list the install and the session helper share.
member_pkg_list() {
  awk -v c="$([ "$1" = apt-get ] && echo 2 || echo 3)" '/^[[:space:]]*#/ || !NF { next } $c != "-" { print $c }' "$ROOT/contracts/member-prereqs.txt"
}
member_prereqs() {
  log_head 'prerequisites'
  if [ "$OS" = Darwin ]; then
    # No package manager is assumed here. /usr/bin is what the pinned PATH reads, and macOS ships these with the command line tools.
    for _t in git jq curl ssh-keygen; do
      [ -x "/usr/bin/$_t" ] || command -v "$_t" >/dev/null 2>&1 || die "$_t is missing, and on macOS it must be at /usr/bin" 'xcode-select --install'
    done
    log_ok 'git, jq, curl and ssh-keygen are present'; return 0
  fi
  if command -v apt-get >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive; export DEBIAN_FRONTEND
    apt-get update -q || die 'apt-get update failed' 'apt-get update'
    # shellcheck disable=SC2046 # one package per word, from the fixed list above
    apt-get install -y -q --no-install-recommends $(member_pkg_list apt-get) || die 'apt-get install failed' "apt-get install -y $(member_pkg_list apt-get | tr '\n' ' ')"
  elif command -v dnf >/dev/null 2>&1; then
    # shellcheck disable=SC2046 # as above
    dnf install -y -q $(member_pkg_list dnf) || die 'dnf install failed' "dnf install -y $(member_pkg_list dnf | tr '\n' ' ')"
  else
    die 'no apt-get or dnf here, so the prerequisites can not be installed' 'install git jq curl openssh bubblewrap socat by hand, then run this again'
  fi
  for _t in git jq curl ssh-keygen bwrap socat; do
    command -v "$_t" >/dev/null 2>&1 || die "$_t is still missing after the install" "$(pkg_hint "$_t")"
  done
  log_ok 'git, jq, curl, ssh-keygen, bwrap and socat are present'
  member_apparmor /etc/apparmor.d
}
# Ubuntu 24.04+ stops bubblewrap without a profile, and failIfUnavailable would then refuse every session (bin/deploy-confinement.sh).
member_apparmor() { # <profile dir>
  sh "$HERE/deploy-confinement.sh" --preflight --user "$MEMBER" >/dev/null 2>&1 && return 0
  [ -d "$1" ] || die 'bubblewrap can not start for this member, and this box has no AppArmor to fix that' "sh '$HERE/deploy-confinement.sh' --preflight --user $MEMBER"
  printf '%s\n' 'abi <abi/4.0>,' 'include <tunables/global>' 'profile bwrap /usr/bin/bwrap flags=(unconfined) {' '  userns,' '}' > "$1/bwrap"
  apparmor_parser -r "$1/bwrap" || die 'apparmor_parser refused the bwrap profile' "apparmor_parser -r $1/bwrap"
  sh "$HERE/deploy-confinement.sh" --preflight --user "$MEMBER" || die 'bubblewrap still can not start for this member' "sh '$HERE/deploy-confinement.sh' --preflight --user $MEMBER"
  log_ok "wrote the bwrap AppArmor profile in $1"
}
# The pin is checked against this very checkout: a floor copied from anything else would carry a pin that lies (R10).
member_pin_check() {
  _head="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)" || die "$ROOT is not a git checkout" 'sh bin/member-bootstrap.sh'
  [ "$_head" = "$PIN" ] || die "this checkout is at $_head, not the pin $PIN" "git -C '$ROOT' checkout --detach $PIN"
  [ -z "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ] || die "$ROOT has uncommitted changes, and they would become the floor" "git -C '$ROOT' status"
  log_ok "the checkout is at the pin $PIN, clean"
}
# hub-signers must verify a policy: OpenSSH allowed_signers, principal `hub`, namespace `harbor-hub` (contracts/hub.md).
member_signers_check() {
  [ -f "$SIGNERS" ] || die "--signers: no file at $SIGNERS" 'give the allowed_signers file the hub admin supplied'
  grep -Eq '^hub[[:space:]]+namespaces="harbor-hub"[[:space:]]+(ssh-|ecdsa-|sk-)' "$SIGNERS" \
    || die "$SIGNERS holds no row for principal hub, namespace harbor-hub" 'contracts/hub.md, the signing key'
}

# member_upterm: the remote support binary, by digest, into the stage, so floor.pin covers it. Linux and WSL only: that is what a member runs it on.
member_upterm() {
  _up="$ROOT/contracts/support-upterm.tsv"
  if [ "$OS" = Darwin ]; then log_note 'remote support runs on Linux and WSL, so upterm is not installed here'; return 0; fi
  case "$(uname -m)" in x86_64|amd64) _ua=amd64 ;; aarch64|arm64) _ua=arm64 ;; *) die "no pinned upterm for $(uname -m)" "$_up" ;; esac
  _uv="$(awk -F'\t' '$1 == "version" { print $2; exit }' "$_up")"
  _uw="$(awk -F'\t' -v k="sha256-linux-$_ua" '$1 == k { print $2; exit }' "$_up")"
  [ -n "$_uv" ] && [ -n "$_uw" ] || die "$_up has no version or digest for linux-$_ua" 'contracts/support-upterm.tsv'
  _ut="$WORK/upterm.tar.gz"
  curl -q --silent --show-error --fail --location --proto '=https' --max-time 180 --output "$_ut" \
    "https://github.com/owenthereal/upterm/releases/download/v$_uv/upterm_linux_$_ua.tar.gz" || die "upterm $_uv could not be downloaded" 'check this box can reach github.com, then run this again'
  _ug="$(hub_sha256 < "$_ut")"
  [ "$_ug" = "$_uw" ] || die "refused: the upterm download is not the pinned one (sha256 $_ug, pinned $_uw)" 'contracts/support-upterm.tsv'
  mkdir -p "$WORK/upterm"
  tar -xzf "$_ut" -C "$WORK/upterm" upterm || die 'the upterm archive holds no upterm' "$_up"
  cp "$WORK/upterm/upterm" "$STAGE/harbor/bin/upterm"
  log_ok "upterm $_uv for linux-$_ua matches its pin"
}
# member_policy_copy <signers> -> 0 with $WORK/policy.json, a copy root verified itself, 1 with none to read. Hosts and the relay widen or move
# the network, and the member chose which file hub-sync.sh names, so root reads only its own verified copy, as member-update.sh does (N6).
# The bytes are read as the member, so a path they name can't make root read what they can't. A serial below pin.serial, the last one
# applied, is an old signed file: refused, as the updater refuses it.
member_policy_copy() {
  POLICY_SERIAL=''
  [ -f "$MROOT/bin/hub-sync.sh" ] && [ -s "$1" ] || return 1
  _pp="$(_as_member env HARBOR_MEMBER_ROLE=member HARBOR_HUB_REPO="$HUB" HARBOR_MEMBER_LOGIN="$LOGIN" HARBOR_MEMBER_ROOT="$MROOT" sh "$MROOT/bin/hub-sync.sh" path </dev/null 2>/dev/null)" || return 1
  [ -n "$_pp" ] || return 1
  rm -f "$WORK/policy.json" "$WORK/policy.json.sig"
  _as_member cat -- "$_pp" > "$WORK/policy.json" 2>/dev/null && _as_member cat -- "$_pp.sig" > "$WORK/policy.json.sig" 2>/dev/null || return 1
  if ! ssh-keygen -Y verify -f "$1" -I hub -n harbor-hub -s "$WORK/policy.json.sig" < "$WORK/policy.json" >/dev/null 2>&1; then
    log_warn "the policy does not verify against $1, so none of its hosts or its relay are applied"; return 1
  fi
  _ps="$(jq -r '.serial // ""' "$WORK/policy.json" 2>/dev/null)" || _ps=''
  case "$_ps" in ''|*[!0-9]*) log_warn 'the verified policy has no whole-number serial, so none of its hosts or its relay are applied'; return 1 ;; esac
  if [ -f "$MROOT/pin.serial" ]; then
    _last="$(cat "$MROOT/pin.serial")"
    case "$_last" in ''|*[!0-9]*) die "$MROOT/pin.serial is not a number" "cat '$MROOT/pin.serial'" ;; esac
    [ "$_ps" -ge "$_last" ] || die "refused: $MEMBER's policy is serial $_ps, below the $_last already applied: an old signed file" \
      "sudo -u $MEMBER -H sh '$MROOT/bin/hub-sync.sh' fetch, then run this again"
  fi
  POLICY_SERIAL="$_ps"
}
# member_policy_relay -> the relay host the verified copy names, or nothing. Managed settings are fixed until they are composed again,
# so a relay that moved reaches sandbox.network.deniedDomains only then; member-support.sh refuses until it has.
member_policy_relay() {
  _pr="$(jq -r '.support.relay // empty' "$WORK/policy.json" 2>/dev/null)" || return 0
  _pr="${_pr#*://}"; printf '%s' "${_pr%%:*}"
}
# member_policy_hosts -> the hosts the verified copy adds to the sandbox, one per line. member-managed.sh checks each one's shape.
member_policy_hosts() { jq -r '(.hosts // [])[] | strings' "$WORK/policy.json" 2>/dev/null || :; }
# member_settings_compose <out> <mcp file or ''> <hub> <login>: the managed settings, with what a verified policy adds when there is one.
member_settings_compose() {
  set -- "$1" --hub "$3" --login "$4" --user "$MEMBER" ${2:+--mcp-allow} ${2:+"$2"}
  _mc_out="$1"; shift
  if [ -n "$POLICY_SERIAL" ]; then
    _relay="$(member_policy_relay)"
    [ -z "$_relay" ] || set -- "$@" --deny-host "$_relay"
    _hosts="$(member_policy_hosts)"
    set -f   # a `*.` row must stay a word, not a glob
    for _h in $_hosts; do set -- "$@" --allow-host "$_h"; done
    set +f
  fi
  sh "$HERE/member-managed.sh" "$@" > "$_mc_out" || die 'composing the managed settings failed (above)' "sh '$HERE/member-managed.sh' $*"
  jq -e 'type == "object"' "$_mc_out" >/dev/null 2>&1 || die 'the composed settings are not a JSON object, and Claude Code would refuse to start' "sh '$HERE/member-managed.sh' $*"
}
# stage_tree -> $STAGE holds everything that lands, relative to the folder of the managed settings file.
stage_tree() {
  log_head 'stage · the whole tree, before anything is written'
  mkdir -p "$STAGE/harbor/bin" "$STAGE/harbor/MEMORY/OBSERVABILITY/$OBS_HOST"
  sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^[[:space:]]*$/d' "$ROOT/contracts/member-files.txt" > "$WORK/rows"
  while read -r _src _dest; do
    [ -f "$ROOT/$_src" ] || die "contracts/member-files.txt names $_src, which this checkout lacks: a half floor stops every call" "git -C '$ROOT' log -1"
    cp "$ROOT/$_src" "$STAGE/harbor/bin/${_dest:-${_src##*/}}"
  done < "$WORK/rows"
  : > "$STAGE/harbor/bin/harbor-member-mode"
  cp "$SIGNERS" "$STAGE/harbor/hub-signers"
  printf '%s\n' "$OBS_HOST" > "$STAGE/harbor/.helm-obs-host"
  : > "$STAGE/harbor/$SINK_REL"
  # Who this laptop is, for what runs outside a session (member-update.sh, by a schedule). Before the hash, so it is pinned with the rest.
  _home="$(_as_member sh -c 'printf "%s" "$HOME"')" || die "the home of $MEMBER can not be read" "sudo -u $MEMBER -H sh -c 'echo \$HOME'"
  case "$_home" in /*) ;; *) die "the home of $MEMBER is '$_home', not an absolute path" 'contracts/hub.md, member.conf' ;; esac
  case "$_home" in *[!A-Za-z0-9._/@+\ -]*) die "the home of $MEMBER holds a character member.conf and the shell line can't carry: $_home" 'contracts/hub.md, member.conf' ;; esac
  printf 'hub=%s\nlogin=%s\nhome=%s\n' "$HUB" "$LOGIN" "$_home" > "$STAGE/harbor/member.conf"
  # The commit this floor is, for member-update.sh; and the serial whose hosts and relay it carries. Neither is in the hash.
  printf '%s\n' "$PIN" > "$STAGE/harbor/core.commit"
  member_policy_copy "$SIGNERS" || :
  [ -z "$POLICY_SERIAL" ] || printf '%s\n' "$POLICY_SERIAL" > "$STAGE/harbor/pin.serial"
  member_settings_compose "$STAGE/managed-settings.json" "$MCP_FILE" "$HUB" "$LOGIN"
  sh "$HERE/deploy-confinement.sh" --marker --member --user "$MEMBER" > "$STAGE/harbor-confinement" || die 'writing the confinement marker failed (above)' "sh '$HERE/deploy-confinement.sh' --marker --member"
  member_upterm
  # What lands in bin beside the list, derived from the stage: member-update.sh carries these, and integrity checks they stay (N3).
  ( cd "$STAGE/harbor/bin" && ls ) | awk 'NR == FNR { n[$2 != "" ? $2 : substr($1, match($1, /[^\/]*$/))] = 1; next } !($0 in n)' "$WORK/rows" - > "$STAGE/harbor/floor.extra"
  # As the member, not root: overrides are refused under root, and the hash must come from the same code the session runs.
  chmod -R a+rX "$WORK"
  _pin="$(_as_member env HARBOR_MEMBER_ROOT="$STAGE/harbor" HARBOR_SCOPE_MANAGED_SETTINGS="$STAGE/managed-settings.json" sh "$STAGE/harbor/bin/member-integrity.sh" hash)" \
    || die 'member-integrity.sh hash failed (above)' "sh '$STAGE/harbor/bin/member-integrity.sh' hash"
  case "$_pin" in *[!0123456789abcdef]*|'') die "member-integrity.sh printed '$_pin', not a hash" 'contracts/hub.md, what runs where' ;; esac
  [ "${#_pin}" -eq 16 ] || die "member-integrity.sh printed '$_pin', not 16 hex" 'contracts/hub.md, what runs where'
  printf '%s\n' "$_pin" > "$STAGE/harbor/floor.pin"
  log_ok "staged $(wc -l < "$WORK/rows" | tr -d ' ') floor files, the pin is $_pin"
}
# put_file <from> <to>: a temp file beside the target, then a rename, so no reader ever meets half a file.
put_file() {
  mkdir -p "${2%/*}"
  cp "$1" "$2.new.$$"
  chmod "${3:-0644}" "$2.new.$$"
  mv "$2.new.$$" "$2"
}
# land_unix: root owns all of it. Only the ledger is the member's to append to.
land_unix() {
  log_head "land · $MROOT"
  _grp="$(root_group)"
  sink_clear   # an append-only file refuses chmod and chown, so a re-run lifts the flag and seals it again below
  for _f in "$STAGE/harbor/bin/"*; do put_file "$_f" "$MROOT/bin/${_f##*/}" 0755; done
  for _f in "$MROOT/bin/"*; do [ -e "$STAGE/harbor/bin/${_f##*/}" ] || rm -f "$_f"; done   # a file the pin dropped goes too
  for _n in hub-signers floor.pin floor.extra .helm-obs-host member.conf core.commit pin.serial; do [ ! -f "$STAGE/harbor/$_n" ] || put_file "$STAGE/harbor/$_n" "$MROOT/$_n"; done
  put_file "$STAGE/harbor-confinement" "${MROOT%/*}/harbor-confinement"
  member_sink
  chown -R "root:$_grp" "$MROOT" "${MROOT%/*}/harbor-confinement"
  chown "root:$(member_group)" "$MROOT/$SINK_REL"
  sink_seal
  put_file "$STAGE/managed-settings.json" "$MFILE"
  chown "root:$_grp" "$MFILE"
  [ "$(jq -S . "$MFILE" 2>/dev/null)" = "$(jq -S . "$STAGE/managed-settings.json")" ] || die "read-back: $MFILE is not what this run wrote" "jq . '$MFILE'"
  log_ok "landed, and read $MFILE back"
}
# THE LEDGER (F11). library-admission.sh creates nothing and writes only into a folder it can't write, so the install makes both.
# What stops the agent rewriting it: the Edit deny and denyWrite rows, no unsandboxed path for its commands, and the append-only flag below.
member_sink() {
  _sink="$MROOT/$SINK_REL"
  mkdir -p "${_sink%/*}"
  [ -f "$_sink" ] || : > "$_sink"
  chmod 0660 "$_sink"
  chmod 0555 "${_sink%/*}"
}
sink_seal() {
  _sink="$MROOT/$SINK_REL"; _flag=0
  if [ "$OS" = Darwin ]; then chflags sappnd "$_sink" 2>/dev/null && _flag=1
  else chattr +a "$_sink" 2>/dev/null && _flag=1; fi
  if [ "$_flag" = 1 ]; then log_ok "the ledger takes appends only: $_sink"
  else log_warn "the ledger could not be made append-only; only the deny rows stop a rewrite: $_sink"; fi
}
sink_clear() {
  _sink="$MROOT/$SINK_REL"
  [ -e "$_sink" ] || return 0
  if [ "$OS" = Darwin ]; then chflags nosappnd "$_sink" 2>/dev/null || :
  else chattr -a "$_sink" 2>/dev/null || :; fi
}
# tree_landed: every staged byte is under the base, the ledger only present. This is how WSL reads the PowerShell's work back.
tree_landed() {
  _base="${MFILE%/*}"
  ( cd "$STAGE" && find . -type f | sed 's|^\./||' ) > "$WORK/staged"
  while IFS= read -r _f; do
    [ -f "$_base/$_f" ] || return 1
    [ "$_f" = "harbor/$SINK_REL" ] || cmp -s "$STAGE/$_f" "$_base/$_f" || return 1
  done < "$WORK/staged"
}
land_windows() {
  log_head 'land · the Windows half'
  if tree_landed; then log_ok "the floor is in place under ${MFILE%/*}, byte for byte"; return 0; fi
  _ps="${WINDOWS_OUT:-$PS1_DEFAULT}"
  sh "$HERE/member-windows.sh" --stage "$STAGE" --member "$MEMBER" > "$_ps.new.$$" || { rm -f "$_ps.new.$$"; die 'member-windows.sh refused (above)'; }
  mv "$_ps.new.$$" "$_ps"
  log_note "root in this distro can't write C:\\Program Files. In PowerShell as administrator, run the script at $_ps:"
  log_note "  powershell -NoProfile -ExecutionPolicy Bypass -File \\\\wsl.localhost\\$(printf '%s' "${WSL_DISTRO_NAME:-Ubuntu}")$(printf '%s' "$_ps" | tr '/' '\\')"
  log_note 'then run this same command again, which reads the result back and goes on'
  log_end || :; exit 3
}
# /etc here, or beside the moved settings under a test: root-only homes for what the distro itself must hold, on WSL too.
member_etc() { if [ -n "${HARBOR_SCOPE_MANAGED_SETTINGS:-${HARBOR_MANAGED_SETTINGS:-}}" ]; then printf '%s/etc' "${MFILE%/*}"; else printf /etc; fi; }
# W5: the member's one root path, and exactly this command with exactly no argument. visudo first: a broken file here would break every sudo on the box.
# macOS has no package manager to call, so its tools stay IT's and a missing one is said in the session.
member_sudoers() {
  [ "$OS" != Darwin ] || return 0
  _f="$(member_etc)/sudoers.d/harbor-member-prereqs"
  printf '# Written by member-install.sh (harbor#1278).\n%s ALL=(root) NOPASSWD: /bin/sh %s\n' "$MEMBER" "$(printf '%s' "$MROOT/bin/member-prereqs.sh" | sed 's/[\\ ,:=]/\\&/g')" > "$WORK/sudoers"
  visudo -c -q -f "$WORK/sudoers" >/dev/null 2>&1 || die 'visudo refused the prerequisites rule, so it was not written' "visudo -c -f '$WORK/sudoers'"
  put_file "$WORK/sudoers" "$_f" 0440   # the temp name holds a dot, and sudo skips those, so no reader meets half a rule
  chown "root:$(root_group)" "$_f"
  log_ok "$MEMBER may run the prerequisites helper as root, and nothing else: $_f"
}
# W10: a terminal starts in ~/port. Only from the home folder, so `wsl.exe --cd` and a shell opened anywhere else keep their folder. In /etc, so it is root's and needs no user file.
member_profile() {
  [ "$OS" != Darwin ] || return 0
  printf '# Written by member-install.sh (harbor#1278). W10.\ncase "$-" in *i*) if [ "$HOME" = %s ] && [ "$PWD" = "$HOME" ] && [ -d "$HOME/port" ]; then cd "$HOME/port" || :; fi ;; esac\n' "'$_home'" > "$WORK/profile"
  put_file "$WORK/profile" "$(member_etc)/profile.d/harbor-member.sh"
  chown "root:$(root_group)" "$(member_etc)/profile.d/harbor-member.sh"
  log_ok "$MEMBER's interactive shells start in ~/port"
}

# member_user_tier: a copy of the pinned checkout the member owns, then deploy as the member. No user-tier floor (R9).
member_user_tier() {
  log_head "user tier · as $MEMBER"
  _port="$(_as_member sh "$HERE/scope-roots.sh" --port-root)" || die "the workspace of $MEMBER can not be resolved" "sh '$HERE/scope-roots.sh' --port-root"
  _dest="$_port/harbor"
  _as_member mkdir -p "$_port"
  _as_member rm -rf "$_dest.new"
  _as_member mkdir "$_dest.new"
  ( cd "$ROOT" && tar -cf - . ) | _as_member tar -xf - -C "$_dest.new" || die "copying the checkout for $MEMBER failed" "sh '$0' --help"
  _as_member rm -rf "$_dest"
  _as_member mv "$_dest.new" "$_dest"
  _as_member sh "$_dest/bin/harbor" scope install || die 'harbor scope install failed (above)' "sudo -u $MEMBER -H sh '$_dest/bin/harbor' scope install"
  _snap="$(_as_member mktemp "${_port}/.harbor-deploy-snapshot.XXXXXX")"
  _rc=0
  _as_member env HARBOR_DEPLOY_UNATTENDED=1 HARBOR_DEPLOY_SNAPSHOT="$_snap" sh "$_dest/bin/deploy.sh" --apply --live --member --pin "$PIN" --unattended || _rc=$?
  _as_member rm -f "$_snap"
  [ "$_rc" -eq 0 ] || die "deploy for $MEMBER failed (rc=$_rc, above): the managed floor stays on" "sudo -u $MEMBER -H sh '$_dest/bin/deploy.sh' --live --member --pin $PIN"
}
# The pin was computed in the stage; this is the same code asked the same question at the real path, so a path-dependent hash goes red here.
member_integrity_check() {
  _as_member env HARBOR_MEMBER_ROOT="$MROOT" sh "$MROOT/bin/member-integrity.sh" check \
    || die 'member-integrity.sh check does not match floor.pin on the installed tree' "sh '$MROOT/bin/member-integrity.sh' hash"
  log_ok 'the installed floor matches floor.pin'
}

# W7: the ONE place the member's token is stored. bin/secret is the only sanctioned store. With no store this fails and nothing is written
# anywhere else: a plaintext file is what bin/secret refuses, and it would sit where the agent can read it (harbor#618, R7). The value arrives
# on stdin and leaves on stdin, so it is never in argv, a variable or a file here.
member_token_store() {
  # stdin is closed for the question: sudo can read ahead of a child that never reads, which would eat the token. A pasted newline would end the header.
  if _as_member sh "$MROOT/bin/access.sh" has "$TOKEN_REF" </dev/null >/dev/null 2>&1; then
    tr -d '\r\n' | _as_member sh "$MROOT/bin/secret" put "$TOKEN_REF"
  else
    tr -d '\r\n' | _as_member sh "$MROOT/bin/access.sh" add "$TOKEN_REF" --kind token --what 'this member on the hub board' --use-when 'managed hooks reach the hub' \
      --reaches 'hub repo: issues and contents' --cannot 'approve a request, or reach any other repo' --grant 'the member, with IT beside them' --revoke 'delete the token on GitHub, and remove the member from the hub repo' --secret "$TOKEN_REF" --value-stdin
  fi
}
member_token_step() {
  log_head 'token · IT beside the member'
  if [ "$TOKEN" -eq 1 ]; then
    member_token_store || die "the token was not stored: no working secret store, or the register refused it (above). Nothing was written in its place. The floor is on, but every Claude Code step is refused until it is stored and the first policy fetched (harbor#618)" \
      "as root, check the store: sh '$0' --user $MEMBER --store-check; then enter the token again with --token-stdin" 4
    log_ok "stored $TOKEN_REF for $MEMBER through bin/secret"
  elif ! _as_member sh "$MROOT/bin/access.sh" has "$TOKEN_REF" </dev/null >/dev/null 2>&1; then
    die "not finished: $MEMBER has no hub token yet, so this laptop can't fetch the company safety settings, and every Claude Code step is refused until it does" \
      "with $MEMBER here, as root (on WSL: wsl -d Ubuntu -u root), read it with no echo or history:  read -rs T && printf '%s' \"\$T\" | sh '$0' --user $MEMBER --token-stdin; unset T" 4
  fi
  member_first_policy
}
# W7: the first-laptop check, before the token. bin/secret's own round trip on a throwaway value, as the member, from the same `env -i` and
# pinned PATH a hook starts from (MEMBER_HOOK_ENV), so a pass here is the path the token will take both ways. Prints no value.
member_store_check() {
  log_head "store check · $MEMBER"
  _mh="$(_as_member sh -c 'printf "%s" "$HOME"' </dev/null)"
  _as_member /usr/bin/env -i HOME="$_mh" USER="$MEMBER" LOGNAME="$MEMBER" PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/sh "$MROOT/bin/secret" check </dev/null \
    || die "the token store does not work for $MEMBER (above), so a token entered now would not be stored" \
      "as root: /bin/sh '$MROOT/bin/member-prereqs.sh'   (installs openssl and the rest of the list), then this check again" 1
  log_ok "the token store works for $MEMBER as a hook reads it: enter the token next (--token-stdin)"
}
# A joined laptop with no verified policy refuses every call (contracts/hub.md, Tiers and sets), so an install isn't finished until one verifies.
member_first_policy() {
  _hub="$(jq -r '.env.HARBOR_HUB_REPO // empty' "$MFILE")"; _login="$(jq -r '.env.HARBOR_MEMBER_LOGIN // empty' "$MFILE")"
  _retry="sudo -u $MEMBER -H sh '$MROOT/bin/hub-sync.sh' fetch && sudo -u $MEMBER -H sh '$MROOT/bin/hub-sync.sh' check, both exit 0"
  _rc=0
  _as_member env HARBOR_MEMBER_ROLE=member HARBOR_HUB_REPO="$_hub" HARBOR_MEMBER_LOGIN="$_login" HARBOR_MEMBER_ROOT="$MROOT" sh "$MROOT/bin/hub-sync.sh" fetch </dev/null || _rc=$?
  case "$_rc" in
    0) ;;
    3) die "not finished: the hub $_hub could not be reached from this laptop, so it has no company safety settings, and every Claude Code step is refused until it does. Check that this laptop reaches github.com (a proxy or firewall), and that $MEMBER's token can read $_hub: Contents read, not expired, approved by the organisation" "$_retry" 5 ;;
    *) die "the hub policy was refused (hub-sync.sh fetch exit $_rc): check --signers against the key the admin signs with" "$_retry" ;;
  esac
  _rc=0
  _as_member env HARBOR_MEMBER_ROLE=member HARBOR_HUB_REPO="$_hub" HARBOR_MEMBER_LOGIN="$_login" HARBOR_MEMBER_ROOT="$MROOT" sh "$MROOT/bin/hub-sync.sh" check </dev/null || _rc=$?
  [ "$_rc" -eq 0 ] || die "not finished: the fetch ended, but no policy on this laptop verifies against --signers (hub-sync.sh check exit $_rc), so every Claude Code step is refused" "$_retry" 5
  log_ok 'the first policy is fetched and verifies'
  HUB="$_hub" LOGIN="$_login" member_policy_copy "$MROOT/hub-signers" || return 0
  member_settings_refresh "$_hub" "$_login"
  _relay="$(member_policy_relay)"
  [ -z "$_relay" ] || jq -e --arg h "$_relay" '.sandbox.network.deniedDomains | index($h) != null' "$MFILE" >/dev/null 2>&1 \
    || log_warn "the policy names the relay $_relay, and these managed settings don't deny it yet: run this install again, or remote support stays refused"
  _hosts="$(member_policy_hosts)"; set -f
  for _h in $_hosts; do
    jq -e --arg h "$_h" '.sandbox.network.allowedDomains | index($h) != null' "$MFILE" >/dev/null 2>&1 \
      || log_warn "the policy adds the host $_h, and these managed settings don't allow it yet: run this install again to apply it"
  done; set +f
}
# member_settings_refresh <hub> <login>: the settings composed again from the verified copy and landed, then the floor pinned again, so a first
# install applies the policy's hosts and relay in the same run (N5). The MCP list is the landed file's own: a token-only run has no --mcp-allow.
member_settings_refresh() {
  _cc="$(cat "$MROOT/core.commit" 2>/dev/null || :)"
  if [ -n "$_cc" ] && [ "$_cc" != "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)" ]; then
    log_note "the floor is at $_cc, not this checkout: the updater composes its settings, so they are left to it"; return 0
  fi
  jq -c '.allowedMcpServers // []' "$MFILE" > "$WORK/mcp.json" || die "$MFILE can't be read back" "jq . '$MFILE'"
  member_settings_compose "$WORK/settings.new" "$WORK/mcp.json" "$1" "$2"
  if [ "$(jq -S . "$MFILE")" = "$(jq -S . "$WORK/settings.new")" ]; then
    printf '%s\n' "$POLICY_SERIAL" > "$WORK/pin.serial"; [ "$OS" = WSL ] || put_file "$WORK/pin.serial" "$MROOT/pin.serial"
    return 0
  fi
  # W4: root in the distro can't write C:\Program Files, so on WSL the PowerShell lands them: the warnings below say to run it again.
  [ "$OS" != WSL ] || return 0
  put_file "$WORK/settings.new" "$MFILE"
  chown "root:$(root_group)" "$MFILE"
  _pin="$(_as_member env HARBOR_MEMBER_ROOT="$MROOT" HARBOR_SCOPE_MANAGED_SETTINGS="$MFILE" sh "$MROOT/bin/member-integrity.sh" hash)" \
    || die 'member-integrity.sh hash failed (above)' "sh '$MROOT/bin/member-integrity.sh' hash"
  case "$_pin" in *[!0123456789abcdef]*|'') die "member-integrity.sh printed '$_pin', not a hash" 'contracts/hub.md, what runs where' ;; esac
  printf '%s\n' "$_pin" > "$WORK/floor.pin"; put_file "$WORK/floor.pin" "$MROOT/floor.pin"
  printf '%s\n' "$POLICY_SERIAL" > "$WORK/pin.serial"; put_file "$WORK/pin.serial" "$MROOT/pin.serial"
  chown "root:$(root_group)" "$MROOT/floor.pin" "$MROOT/pin.serial"
  member_integrity_check
  log_ok "the managed settings now carry the policy's hosts and relay (serial $POLICY_SERIAL)"
}

# Leaving (M2): a member can't do this alone, on purpose. The hub state and the token go; the user tier stays as a plain install with no floor.
member_uninstall() {
  log_head "uninstall · $MEMBER"
  if _as_member sh "$MROOT/bin/access.sh" has "$TOKEN_REF" </dev/null >/dev/null 2>&1; then
    _as_member sh "$MROOT/bin/access.sh" revoke "$TOKEN_REF" </dev/null || log_warn "could not revoke $TOKEN_REF: revoke it on GitHub too"
  fi
  _state="$(_as_member sh -c 'printf "%s/harbor/hub" "${XDG_STATE_HOME:-$HOME/.local/state}"')"
  _as_member rm -rf "$_state"
  rm -f "$(member_etc)/sudoers.d/harbor-member-prereqs" "$(member_etc)/profile.d/harbor-member.sh"
  if [ "$OS" = WSL ]; then
    _ps="${WINDOWS_OUT:-$PS1_DEFAULT}"
    sh "$HERE/member-windows.sh" --uninstall > "$_ps" || die 'member-windows.sh --uninstall failed (above)'
    log_note "root in this distro can't write C:\\Program Files. In PowerShell as administrator, run the script at $_ps"
    log_end; exit $?
  fi
  sink_clear
  chmod -R u+w "$MROOT" 2>/dev/null || :
  rm -rf "$MROOT"; rm -f "${MROOT%/*}/harbor-confinement"
  if jq -e '.env.HARBOR_MEMBER_ROLE == "member"' "$MFILE" >/dev/null 2>&1; then rm -f "$MFILE"
  elif [ -f "$MFILE" ]; then log_warn "$MFILE is not this install's, so it stays"; fi
  log_ok "the managed floor is gone. Restart Claude Code. Remove the member from the hub repo on GitHub."
  log_end; exit $?
}

[ "${MEMBER_INSTALL_LIB:-0}" = 1 ] && return 0
member_refuse_override "$(id -u)" || exit 1
umask 022   # IT's own umask must not leave a floor the member can't read: a blocked read under onFailure block stops every call
MEMBER=''; HUB=''; LOGIN=''; SIGNERS=''; PIN=''; MCP_FILE=''; TOKEN=0; UNINSTALL=0; STORE_CHECK=0; WINDOWS_OUT=''
while [ $# -gt 0 ]; do
  case "$1" in
    --token-stdin) TOKEN=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --store-check) STORE_CHECK=1 ;;
    --user|--hub|--login|--signers|--pin|--mcp-allow|--windows-out)
      [ $# -ge 2 ] || die "$1 needs a value" "sh $0 --help" 2
      case "$1" in --user) MEMBER="$2" ;; --hub) HUB="$2" ;; --login) LOGIN="$2" ;; --signers) SIGNERS="$2" ;; --pin) PIN="$2" ;; --mcp-allow) MCP_FILE="$2" ;; --windows-out) WINDOWS_OUT="$2" ;; esac
      shift ;;
    -h|--help) awk 'NR<2{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;;
    *) die "unknown argument $1" "sh $0 --help" 2 ;;
  esac
  shift
done
# Only root, or a test that moved the target. This is what makes leaving IT's: a member has neither (M2).
if [ "$(id -u)" -ne 0 ] && [ -z "${HARBOR_SCOPE_MANAGED_SETTINGS:-${HARBOR_MANAGED_SETTINGS:-}}" ]; then
  die 'not root: the floor is root-owned by design, so IT runs this' "sudo sh $0" 1
fi
# What useradd takes, as member-windows.sh's name_ok: a leading dot lets `..` through to /home/.., and all digits reads as a uid.
case "$MEMBER" in ''|-*|.*|*[!A-Za-z0-9._-]*) die "--user wants the member's account name, got '$MEMBER'" "sh $0 --help" 2 ;; esac
case "$MEMBER" in *[!0-9]*) ;; *) die "--user wants the member's account name, not a number: '$MEMBER'" "sh $0 --help" 2 ;; esac
[ "${#MEMBER}" -le 32 ] || die "--user wants an account name of 32 characters or fewer, got '$MEMBER'" "sh $0 --help" 2
[ "$MEMBER" != root ] || die '--user root: a member is never root' "sh $0 --help" 2
id -u "$MEMBER" >/dev/null 2>&1 || die "no account named $MEMBER on this machine" "create it, then run this again"
OS="$(member_os)"
case "$OS" in Darwin|Linux|WSL) ;; *) die "HARBOR_MEMBER_OS is $OS, not Darwin, Linux or WSL" "sh $0 --help" 2 ;; esac
MFILE="$(member_settings "$OS")"; MROOT="$(member_root "$OS")"
if [ "$UNINSTALL" -eq 1 ]; then member_uninstall; fi
if [ "$STORE_CHECK" -eq 1 ]; then
  [ -z "$HUB$LOGIN$SIGNERS$PIN" ] && [ "$TOKEN" -eq 0 ] || die '--store-check goes with --user alone' "sh $0 --help" 2
  [ -f "$MROOT/bin/harbor-member-mode" ] || die "no member floor at $MROOT: install it first" "sh $0 --help"
  member_store_check; log_end; exit $?
fi
if [ "$TOKEN" -eq 1 ] && [ -z "$HUB$LOGIN$SIGNERS$PIN" ]; then
  [ -f "$MROOT/bin/harbor-member-mode" ] || die "no member floor at $MROOT: install it first" "sh $0 --help"
  # member_policy_hosts copies the policy into WORK, and this path skips the full run that makes it (harbor#1278).
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/harbor-member.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT INT TERM
  member_token_step; log_end; exit $?
fi
[ -n "$HUB" ] && [ -n "$LOGIN" ] && [ -n "$SIGNERS" ] && [ -n "$PIN" ] || die '--user --hub --login --signers --pin all go together' "sh $0 --help" 2
slug_valid "$HUB" || die "--hub wants owner/name, got '$HUB'" "sh $0 --help" 2
case "$LOGIN" in -*|*[!A-Za-z0-9-]*) die "--login wants a GitHub login, got '$LOGIN'" "sh $0 --help" 2 ;; esac
case "$PIN" in *[!0123456789abcdef]*) die "--pin wants a 40-hex commit, got '$PIN'" "sh $0 --help" 2 ;; esac
[ "${#PIN}" -eq 40 ] || die "--pin wants a 40-hex commit, got '$PIN'" "sh $0 --help" 2

log_head "member install · $MEMBER on $OS"
_tmp="${TMPDIR:-/tmp}"; [ "$(id -u)" -ne 0 ] || _tmp=/tmp   # under root an inherited TMPDIR may be IT's own 0700 folder, and the member has to read the stage
WORK="$(mktemp -d "$_tmp/harbor-member.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT INT TERM
_SUDOL="$WORK/sudo.list"
member_refuse_admin
member_signers_check
member_prereqs
member_pin_check
# F10: first, so nothing is written that would be silently ignored.
_rc=0; _found="$(sh "$HERE/member-managed.sh" --higher-source)" || _rc=$?
if [ "$_rc" -ne 0 ]; then
  printf '%s\n' "$_found" | while IFS= read -r _l; do [ -z "$_l" ] || log_note "a higher policy source: $_l"; done
  die 'refused: writing the file would leave the floor silently absent' 'remove that source, or carry this policy in it; docs/how-to/member-install.md'
fi
STAGE="$WORK/stage"; mkdir -p "$STAGE"
stage_tree
if [ "$OS" = WSL ]; then land_windows; else land_unix; fi
member_sudoers
member_profile
member_user_tier
member_integrity_check
member_token_step
log_head 'next'
log_note "have $MEMBER open a session, run /status and read Setting sources: it must say Enterprise managed settings (file), with no Skipped sources line"
log_end; exit $?
