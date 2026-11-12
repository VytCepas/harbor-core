# tests/member/fixture.sh — the throwaway checkout and stubs the member suites share (harbor#1278). Sourced after core.sh's t_init.
# The REAL install, composer, confinement, access.sh, scope-roots.sh and guards run in it. Stubbed: what other lanes build (their contracts are
# in lanes.md), what needs root (sudo, chown, chflags, chattr), and what writes outside the temp dir (bin/secret, deploy, the package manager).
# shellcheck disable=SC2016 # the stub bodies are written out verbatim
SYS="$T_TMP/Program Files/ClaudeCode"   # a space, as on macOS and Windows: a hook path that splits is a floor that never runs
MFILE="$SYS/managed-settings.json"; MROOT="$SYS/harbor"
MHOME="$T_TMP/alice-home"; CORE="$T_TMP/core"; STORE="$T_TMP/store"; CALLS="$T_TMP/calls"
SINK="$MROOT/MEMORY/OBSERVABILITY/member/guard-decisions.jsonl"
mkdir -p "$SYS" "$MHOME" "$STORE"; : > "$CALLS"

stub() { # <path> <body...> — one line per argument
  _s="$1"; shift
  { printf '#!/bin/sh\n'; printf '%s\n' "$@"; } > "$_s"; chmod +x "$_s"
}
# Every other lane's script, at its contract's exit codes. The hash is over content only, as the staged and landed trees must agree.
member_stubs() { # <bin dir>
  for _n in member-dispatch.sh member-post.sh member-session.sh hub-tier.sh hub-approval.sh hub-board.sh hub-events.sh member-update.sh; do
    stub "$1/$_n" 'exit 0'
  done
  stub "$1/member-integrity.sh" \
    'r="${HARBOR_MEMBER_ROOT:-${0%/*}/..}"; s="${HARBOR_SCOPE_MANAGED_SETTINGS:-$r/../managed-settings.json}"' \
    'h() { { cat "$r"/bin/*; cat "$s"; } | cksum | tr " " 0 | cut -c1-16 | sed "s/^/0000000000000000/; s/.*\(................\)$/\1/" | tr -c "0-9\n" 0; }' \
    'case "$1" in hash) h ;; check) [ "$(h)" = "$(cat "$r/floor.pin")" ] ;; esac'
  stub "$1/hub-sync.sh" 'printf "hub-sync %s repo=%s\n" "$*" "$HARBOR_HUB_REPO" >> "$CALLS"; [ "$1" != check ] || exit "${CHECK_RC:-0}"' \
    '[ "$1" != path ] || { [ -z "${P_JSON:-}" ] || printf "%s\n" "$P_JSON"; exit 0; }; exit "${SYNC_RC:-0}"'
  stub "$1/secret" \
    'case "$1" in put) [ -z "${NO_STORE:-}" ] || { echo "no credential store" >&2; exit 1; }; cat > "$STORE/$2" ;; rm) rm -f "$STORE/$2" ;; list) ls "$STORE" | sed "s/^/secret./" ;; esac' \
    "case \"\$1\" in check) [ ! -e '$T_TMP/no-store' ] || { echo 'no credential store' >&2; exit 1; }; printf 'secret check PATH=%s STORE=%s\\n' \"\$PATH\" \"\${STORE:-unset}\" >> '$CALLS' ;; esac"   # check runs under env -i: paths fixed here
  # bwrap's probe has its own suite and answers per box (a runner may block user namespaces): --preflight reads its answer here, the rest is real.
  awk 'NR == 2 { print "case \"${1-}\" in --preflight) [ -z \"${PREFLIGHT:-}\" ] || [ -s \"$PREFLIGHT\" ]; exit $? ;; esac" } { print }' \
    "$1/deploy-confinement.sh" > "$1/deploy-confinement.sh.new" && mv "$1/deploy-confinement.sh.new" "$1/deploy-confinement.sh"
  stub "$1/deploy.sh" \
    'printf "deploy %s unattended=%s snapshot-empty=%s\n" "$*" "${HARBOR_DEPLOY_UNATTENDED:-}" "$([ -f "$HARBOR_DEPLOY_SNAPSHOT" ] && [ ! -s "$HARBOR_DEPLOY_SNAPSHOT" ] && echo yes)" >> "$CALLS"' \
    'exit "${DEPLOY_RC:-0}"'
}
# core_checkout: this tree's real files with the stubs over them, committed, so the pin check has a commit to read.
core_checkout() {
  mkdir -p "$CORE"
  cp -R "$T_ROOT/bin" "$T_ROOT/contracts" "$CORE/"
  mkdir -p "$CORE/standards/naming"; cp "$T_ROOT/standards/naming/controls.tsv" "$CORE/standards/naming/"
  member_stubs "$CORE/bin"
  # What the release would serve: a fake archive, and a pin that names it, so no install suite reaches the network.
  mkdir -p "$T_TMP/release"; printf '#!/bin/sh\nexit 0\n' > "$T_TMP/release/upterm"; chmod +x "$T_TMP/release/upterm"
  tar -czf "$T_TMP/upterm.tar.gz" -C "$T_TMP/release" upterm
  _ud="$(shasum -a 256 "$T_TMP/upterm.tar.gz" 2>/dev/null || sha256sum "$T_TMP/upterm.tar.gz")"; _ud="${_ud%% *}"
  sed -e "s/^sha256-linux-amd64\t.*/sha256-linux-amd64\t$_ud/" -e "s/^sha256-linux-arm64\t.*/sha256-linux-arm64\t$_ud/" "$T_ROOT/contracts/support-upterm.tsv" > "$CORE/contracts/support-upterm.tsv"
  git -C "$CORE" init -q -b main
  git -C "$CORE" add -A
  git -C "$CORE" -c user.name=t -c user.email=t@t commit -q -m core
  PIN="$(git -C "$CORE" rev-parse HEAD)"
}
# Root's tools. Each records its argv; `sudo` drops to the member's HOME, as `sudo -u alice -H` would.
root_stubs() {
  stub "$T_BIN/sudo" 'if [ "$1 $2 $3" = "-n -l -U" ]; then [ -z "${SUDO_GRANT:-}" ] || printf "User %s may run the following commands on box:\n    %b\n" "$4" "$SUDO_GRANT"; exit 0; fi' \
    'printf "sudo %s %s %s\n" "$1" "$2" "$3" >> "$CALLS"' '[ "$1" = -u ] && [ "$3" = -H ] || exit 9' 'shift 3' 'unset CLAUDE_CONFIG_DIR' 'HOME="$MHOME" exec "$@"'
  stub "$T_BIN/visudo" 'printf "visudo %s\n" "$*" >> "$CALLS"; exit "${VISUDO_RC:-0}"'
  stub "$T_BIN/id" 'case "$*" in -u) exec /usr/bin/id -u ;; "-u alice") echo 1001 ;; "-gn alice") echo alice ;; "-Gn alice") echo "${ID_GROUPS:-alice staff}" ;; *) exec /usr/bin/id "$@" ;; esac'
  # The tree is whole when it is chowned, so a settings file already there at that moment landed too early.
  stub "$T_BIN/chown" 'printf "chown %s\n" "$*" >> "$CALLS"' '[ "$1" != -R ] || [ ! -e "$HARBOR_SCOPE_MANAGED_SETTINGS" ] || echo settings-before-files >> "$CALLS"'
  stub "$T_BIN/chflags" 'printf "chflags %s\n" "$*" >> "$CALLS"; exit "${FLAG_RC:-0}"'
  stub "$T_BIN/chattr" 'printf "chattr %s\n" "$*" >> "$CALLS"; exit "${FLAG_RC:-0}"'
  stub "$T_BIN/apt-get" 'printf "apt-get %s\n" "$*" >> "$CALLS"; exit "${APT_RC:-0}"'
  stub "$T_BIN/curl" 'printf "curl %s\n" "$*" >> "$CALLS"' 'while [ $# -gt 0 ]; do [ "$1" != --output ] || { cp "$RELEASE_TAR" "$2"; exit "${CURL_RC:-0}"; }; shift; done' 'exit 1'
  stub "$T_BIN/bwrap" 'exit 0'
  stub "$T_BIN/socat" 'exit 0'
}
SIGNERS="$T_TMP/hub-signers"
printf 'hub namespaces="harbor-hub" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFixtureFixtureFixtureFixtureFixtureFixtureFix\n' > "$SIGNERS"
RELEASE_TAR="$T_TMP/upterm.tar.gz"
export CALLS STORE MHOME RELEASE_TAR
HARBOR_SCOPE_MANAGED_SETTINGS="$MFILE"; export HARBOR_SCOPE_MANAGED_SETTINGS

# fake_ps <ps1> <base>: does what the PowerShell's Put and Keep rows say, and nothing else. It proves the payload, never PowerShell.
fake_ps() {
  grep "^Put '\|^Keep '" "$1" | while IFS= read -r _l; do
    _k="${_l%% *}"; _r="${_l#* \'}"; _r="${_r%%\'*}"; _p="$2/$(printf '%s' "$_r" | tr '\\' '/')"
    mkdir -p "${_p%/*}"
    case "$_k" in
      Keep) [ -e "$_p" ] || : > "$_p" ;;
      Put) _b="${_l#*\' \'}"; _b="${_b%\'}"; printf '%s' "$_b" | base64 --decode > "$_p" ;;
    esac
  done
}
# install [args]: the real install, stdout and stderr to $OUT, exit in $RC. Stdin is empty unless the case pipes one.
OUT="$T_TMP/out"
install() {
  RC=0; sh "$CORE/bin/member-install.sh" "$@" >"$OUT" 2>&1 </dev/null || RC=$?
}
FULL() { printf '%s\n' --user alice --hub fixture-org/fixture-hub --login alice-gh --signers "$SIGNERS" --pin "$PIN"; }
