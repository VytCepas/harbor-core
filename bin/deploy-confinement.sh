#!/usr/bin/env sh
# CONFINEMENT INSTALL (harbor#1298, #555 P1) — the `sandbox` block of the root-owned managed-settings.json.
#   sudo sh deploy-confinement.sh              compose core then private rows, merge, write, read back
#   sh deploy-confinement.sh --dry-run         print the target path and the merged JSON, write nothing
#   sh deploy-confinement.sh --compose         print only the composed sandbox block
#   sh deploy-confinement.sh --marker          print only the marker body the install writes beside it
#   sudo sh deploy-confinement.sh --uninstall  remove the sandbox block, keep every other key
#
# Holds only `sandbox`, composed from contracts/confinement-hosts.txt and confinement-paths.txt, then the private
# layer's files of the same names (contracts/private-layer.md); no layer is core alone. Managed tier: no session
# can change it, and allowManagedDomainsOnly makes it admin-required, so no repo can loosen it (#1297 round 2).
# The retry stays open for P1's measured week. harbor.toml `confinement_strict = "true"` closes it (P4) and
# `confinement_credentials = "true"` adds the `secret` rows as sandbox.credentials deny (P5): both are the operator's
# edit after the week passes #555 decision 10, and both compose deterministically, so drift.confinement compares alike.
# A marker beside the managed file (harbor-confinement) tells the guard ledger the confinement is on, with no fork.
# `confinement_skip = "true"` (P3, harbor#1300) adds the line `skip=covered` to it: the guards then skip the rules
# contracts/confinement-coverage.tsv marks covered on a confined call. It lives in the root-owned marker, never read
# from harbor.toml at runtime, because harbor.toml sits inside the write zone a confined session can change.
# On Linux the install refuses unless bubblewrap can start as the operator: with failIfUnavailable a box that
# cannot run it would refuse every session (#1297 round 5: stock Ubuntu 24.04 needs an AppArmor profile).
# platform: enableWeakerNetworkIsolation is written on Darwin only; gh's Go TLS fails without it (#1297 round 3).
# allowLocalBinding is written false on purpose: on, it opens the operator's logged-in Chrome to every confined command;
# sessions reach Chrome through the harbor_chrome MCP server instead (harbor#1301, contracts/browser-routing.md row 4).
# Target: macOS /Library/Application Support/ClaudeCode/, Linux and WSL /etc/claude-code/. HARBOR_MANAGED_SETTINGS
# moves it (tests, no root). Composition runs as the operator, never root: HOME, PORT_ROOT and the layer are theirs.
set -eu
# Under sudo a user-writable dir on PATH would run its jq/mkdir/chown as root: pin it first.
PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
CORE="$HERE/../contracts"
# stdout is data (--compose, --dry-run, and the block root captures): the log goes to stderr, or a FAIL is swallowed
LOG_FD=2; export LOG_FD
. "$HERE/library-log.sh"
log_init deploy-confinement
# As root nothing that steers the write or its content is caller-chosen (sudo -E or env_keep would pass it).
confine_refuse_override() { # <uid> -> 1 and a FAIL when root is handed a path or content override
  [ "$1" -eq 0 ] || return 0
  for _v in HARBOR_MANAGED_SETTINGS HARBOR_CONFINEMENT_PRIVATE HARBOR_CONFINEMENT_OS; do
    eval "_s=\${$_v:-}"
    [ -z "$_s" ] && continue
    log_fail "$_v is set under root: refusing a caller-chosen target or content"
    log_fix "sudo env -u $_v sh $0"; return 1
  done
}
# rows <file> -> its rows, comments and blank lines dropped; nothing for an absent file
rows() { [ -f "$1" ] || return 0; sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^[[:space:]]*$/d' "$1"; }
# check_rows <file> <hosts|paths> -> 1 and a FAIL per row that does not compose; an unreadable file refuses too
check_rows() {
  [ -e "$1" ] || return 0
  [ -f "$1" ] && [ -r "$1" ] || { log_fail "$1 exists but cannot be read"; log_fix "ls -l $1"; return 1; }
  _bad="$(rows "$1" | if [ "$2" = hosts ]; then grep -vE '^(\*\.)?[a-z0-9-]+(\.[a-z0-9-]+)+$'
    else grep -vE '^(write|deny-write|read|secret) (/|~/|@PORT_ROOT@|@DELIVERABLES@)[^[:space:]]*$'; fi || :)"
  [ -z "$_bad" ] && return 0
  printf '%s\n' "$_bad" | while IFS= read -r _r; do log_fail "$1: a row that does not compose: $_r"; done
  log_fix "edit $1 (format: its own header)"; return 1
}
# compose -> the sandbox block as JSON on stdout; 1 when a row does not compose
compose() {
  _port="$(sh "$HERE/scope-roots.sh" --port-root)" && [ -n "$_port" ] \
    || { log_fail "scope-roots.sh resolved no workspace root (above; contracts/port-root.md)"; log_fix "sh $HERE/scope-roots.sh --port-root"; return 1; }
  [ -d "$_port" ] && _port="$(CDPATH= cd -P -- "$_port" && pwd)"
  _del="$(sh "$HERE/scope-roots.sh" --conf deliverables_dir 2>/dev/null || :)"; _del="${_del:-~/Deliverables}"
  _priv="${HARBOR_CONFINEMENT_PRIVATE-$(sh "$HERE/scope-roots.sh" --private 2>/dev/null || :)}"
  _hf="$CORE/confinement-hosts.txt"; _pf="$CORE/confinement-paths.txt"
  _xh=''; _xp=''; [ -z "$_priv" ] || { _xh="$_priv/confinement-hosts.txt"; _xp="$_priv/confinement-paths.txt"; }
  _ok=0
  check_rows "$_hf" hosts || _ok=1; check_rows "$_pf" paths || _ok=1
  [ -z "$_priv" ] || { check_rows "$_xh" hosts || _ok=1; check_rows "$_xp" paths || _ok=1; }
  [ "$_ok" = 0 ] || return 1
  _os="${HARBOR_CONFINEMENT_OS:-$(uname -s)}"
  _strict="$(conf_on confinement_strict)" && _cred="$(conf_on confinement_credentials)" || return 1
  { rows "$_hf"; [ -z "$_xh" ] || rows "$_xh"; } | sed 's/^/host /' > "$_T/rows"
  { rows "$_pf"; [ -z "$_xp" ] || rows "$_xp"; } | sed -e "s|@PORT_ROOT@|$_port|g" -e "s|@DELIVERABLES@|$_del|g" >> "$_T/rows"
  jq -R -s --arg os "$_os" --argjson strict "$_strict" --argjson cred "$_cred" '
    [split("\n")[] | select(length > 0) | capture("^(?<k>[a-z-]+) (?<v>.*)$")] as $r
    | def of($k): [$r[] | select(.k == $k) | .v] | reduce .[] as $x ([]; if index([$x]) then . else . + [$x] end);
    {enabled: true, failIfUnavailable: true, allowUnsandboxedCommands: ($strict | not),
     network: {allowManagedDomainsOnly: true, allowLocalBinding: false, allowedDomains: of("host")},
     filesystem: {allowWrite: of("write"), denyWrite: of("deny-write"), allowRead: of("read")}}
    + (if $cred then {credentials: {files: [of("secret")[] | {path: ., mode: "deny"}]}} else {} end)
    + (if $os == "Darwin" then {enableWeakerNetworkIsolation: true} else {} end)' "$_T/rows"
}
# marker_body -> the marker's lines on stdout; 1 when harbor.toml cannot be read
marker_body() {
  _skip="$(conf_on confinement_skip)" || return 1
  printf 'confinement installed by deploy-confinement.sh (harbor#1298)\n'
  [ "$_skip" != true ] || printf 'skip=covered\n'
}
# conf_on <key> -> true when harbor.toml sets the key to "true", false when unset or anything else; a harbor.toml
# scope-roots.sh refuses (exit 2) refuses the compose: read as false, a typo would silently keep the retry open.
conf_on() {
  _cv="$(sh "$HERE/scope-roots.sh" --conf "$1" 2>&1)" && _crc=0 || _crc=$?
  [ "$_crc" -ne 2 ] || { log_fail "harbor.toml cannot be read for $1: $_cv"; log_fix "sh $HERE/scope-roots.sh --conf $1"; return 1; }
  [ "$_crc" -eq 0 ] && [ "$_cv" = true ] && echo true || echo false
}
# confine_preflight <os> -> 1 and a FAIL when this box cannot start the confinement for the operator. Darwin ships
# Seatbelt. Linux needs bubblewrap and socat, and on Ubuntu 24.04+ an AppArmor profile; the probe runs bwrap the way
# the sandbox does, as the operator (CONFINE_AS, "sudo -u <user>" under root), so a root-only success cannot pass.
confine_preflight() {
  [ "$1" = Darwin ] && return 0
  _miss=''; for _t in bwrap socat; do command -v "$_t" >/dev/null 2>&1 || _miss="$_miss $_t"; done
  [ -z "$_miss" ] || { log_fail "missing:$_miss (the confinement's Linux runtime)"; log_fix "$(pkg_hint bubblewrap) && $(pkg_hint socat)"; return 1; }
  # shellcheck disable=SC2086 # CONFINE_AS is a word list by design: empty, or "sudo -u <user>"
  if ! ${CONFINE_AS:-} bwrap --ro-bind / / --dev /dev --proc /proc --unshare-net --unshare-pid true >/dev/null 2>&1; then
    log_fail "bubblewrap cannot start an isolated network namespace here (stock Ubuntu 24.04+ restricts user namespaces)"
    log_fix "sudo tee /etc/apparmor.d/bwrap <<'EOF' (abi <abi/4.0>, include <tunables/global>, profile bwrap /usr/bin/bwrap flags=(unconfined) { userns, }) then sudo systemctl reload apparmor  # code.claude.com/docs/en/sandboxing"
    return 1
  fi
}
# The write is read back (harbor#457): a write that landed nowhere must not exit 0.
confine_verify() { # <file> <expected json> -> 0, or 1 and a FAIL
  _got="$(jq -S . "$1" 2>/dev/null)" || { log_fail "read-back: $1 is missing or not JSON after the write"; log_fix "sh $0 --dry-run"; return 1; }
  [ "$_got" = "$(printf '%s' "$2" | jq -S .)" ] && return 0
  log_fail "read-back: $1 is not the JSON this run meant to write"; log_fix "sh $0 --dry-run"; return 1
}
[ "${CONFINEMENT_LIB:-0}" = 1 ] && return 0
confine_refuse_override "$(id -u)" || exit 1
MODE=install
for a in "$@"; do case "$a" in
  --dry-run) MODE=dry ;; --compose) MODE=compose ;; --marker) MODE=marker ;; --uninstall) MODE=uninstall ;;
  -h|--help) awk 'NR<2{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;;
  *) log_fail "unknown argument $a"; log_nofix "sh bin/deploy-confinement.sh --help"; exit 2 ;;
esac; done
command -v jq >/dev/null 2>&1 || { log_fail "jq not found on the pinned PATH ($PATH): /usr/bin/jq is expected"; log_nofix "install jq at /usr/bin (harbor#902)"; exit 1; }
_T="$(mktemp -d "${TMPDIR:-/tmp}/harbor.XXXXXX")"; trap 'rm -rf "$_T"' EXIT INT TERM
if [ "$MODE" = compose ]; then compose || { log_end || :; exit 1; }; exit 0; fi
if [ "$MODE" = marker ]; then marker_body || { log_end || :; exit 1; }; exit 0; fi

if [ -n "${HARBOR_MANAGED_SETTINGS:-}" ]; then FILE="$HARBOR_MANAGED_SETTINGS"
else case "$(uname -s)" in
  Darwin) FILE='/Library/Application Support/ClaudeCode/managed-settings.json' ;;
  *) FILE='/etc/claude-code/managed-settings.json' ;;
esac; fi
BASE="$(dirname -- "$FILE")"
CUR='{}'
if [ -f "$FILE" ]; then
  CUR="$(cat "$FILE")"
  printf '%s' "$CUR" | jq -e 'type == "object"' >/dev/null 2>&1 \
    || { log_fail "$FILE is not a JSON object; not touching it"; log_nofix "fix or remove $FILE by hand"; exit 1; }
fi
if [ "$MODE" = uninstall ]; then
  NEW="$(printf '%s' "$CUR" | jq 'del(.sandbox)')"
else
  # Root composes as the operator who ran sudo: their HOME, PORT_ROOT and private layer, never root's.
  if [ "$(id -u)" -eq 0 ]; then
    [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ] \
      || { log_fail "run as root without sudo: there is no operator to compose for"; log_fix "sudo sh $0"; exit 1; }
    BLOCK="$(sudo -u "$SUDO_USER" -H env PORT_ROOT="${PORT_ROOT:-}" sh "$0" --compose)" \
      || { log_fail "composing as $SUDO_USER failed (above)"; log_fix "sh $0 --compose"; exit 1; }
    MARK="$(sudo -u "$SUDO_USER" -H env PORT_ROOT="${PORT_ROOT:-}" sh "$0" --marker)" \
      || { log_fail "reading harbor.toml as $SUDO_USER failed (above)"; log_fix "sh $0 --marker"; exit 1; }
  else
    BLOCK="$(compose)" || { log_end || :; exit 1; }
    MARK="$(marker_body)" || { log_end || :; exit 1; }
  fi
  NEW="$(printf '%s' "$CUR" | jq --argjson b "$BLOCK" '.sandbox = $b')"
fi
log_note "target: $FILE"
if [ "$MODE" != uninstall ]; then
  CONFINE_AS=''; [ "$(id -u)" -ne 0 ] || CONFINE_AS="sudo -u $SUDO_USER"
  confine_preflight "${HARBOR_CONFINEMENT_OS:-$(uname -s)}" || { log_end || :; exit 1; }
fi
if [ "$MODE" = dry ]; then printf '%s\n' "$NEW"; log_note "dry run: nothing written"; exit 0; fi

if [ -z "${HARBOR_MANAGED_SETTINGS:-}" ] && [ "$(id -u)" -ne 0 ]; then
  log_fail "not root: this file is root-owned by design"; log_fix "sudo sh $0$([ "$MODE" = uninstall ] && echo ' --uninstall')"; exit 1
fi
mkdir -p "$BASE"
TMPF="$(mktemp "$BASE/.managed-settings.XXXXXX")"; trap 'rm -f "$TMPF"; rm -rf "$_T"' EXIT INT TERM
printf '%s\n' "$NEW" > "$TMPF"
if [ "$(id -u)" -eq 0 ]; then grp=wheel; [ "$(uname -s)" = Darwin ] || grp=root; chown root:"$grp" "$TMPF"; fi
chmod 0644 "$TMPF"; mv "$TMPF" "$FILE"
confine_verify "$FILE" "$NEW" || { log_end || :; exit 1; }
# The marker the guard ledger reads (its `c` field) without forking on the hot path; its one policy line is the P3
# skip, and the guards honour it only while the file is root-owned.
if [ "$MODE" = install ]; then
  printf '%s\n' "$MARK" > "$BASE/harbor-confinement"
  [ "$(id -u)" -ne 0 ] || chown root:"$grp" "$BASE/harbor-confinement"
  chmod 0644 "$BASE/harbor-confinement"
else rm -f "$BASE/harbor-confinement"; fi
# The P3 skip is said at every install: the harbor.toml it comes from sits inside the write zone (review, #1300).
if [ "$MODE" = install ]; then
  case "$MARK" in *skip=covered*) log_note "P3 skip: ON (confinement_skip in harbor.toml): confined calls skip the covered rules" ;;
    *) log_note "P3 skip: off" ;; esac
fi
log_ok "$MODE: wrote $FILE, and read it back"; log_end
