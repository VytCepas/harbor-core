#!/usr/bin/env sh
# hub-sync.sh (harbor#1278) — a member laptop holds the newest policy it can prove came from the admin. Format: contracts/hub.md.
#   sh hub-sync.sh path          the last good policy file, or nothing. Exit 0 either way. Verified on every call (F3)
#   sh hub-sync.sh fetch         fetch, verify, validate, accept. Exit 0 updated or unchanged, 1 refused, 3 hub unreachable
#   sh hub-sync.sh state         joined, revoked or none. revoked only from a verified policy naming this login
#   sh hub-sync.sh check         exit 0 a policy verifies, 1 policy files exist and none verifies (tampered), 2 none
#   sh hub-sync.sh hook <pack> <rel>   the path of a delivered hub hook whose sha256 matches the signed policy, else nothing and exit 1
#   sh hub-sync.sh root          the managed root this copy answers to
#   sh hub-sync.sh token         exit 0 when a hub token can be read from the secret store, 1 when not; prints nothing
# A bad or missing hub never lowers a limit: any failure keeps the files on disk, and a 401, 403 or network failure is "unreachable".
set -eu
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH= cd -- "$HERE" && pwd -P)"
. "$HERE/library-log.sh"
. "$HERE/library-hub.sh"
. "$HERE/library-git-safe.sh"
log_init hub-sync
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2

STATE="$(hub_state_dir)"
TIMEOUT="${HARBOR_HUB_TIMEOUT:-8}"
case "$TIMEOUT" in ''|*[!0-9]*) TIMEOUT=8 ;; esac

# The managed root: a copy that sits in <managed root>/bin proves it by the marker beside it, and no env value can move it
# (a settings env block reaches every hook). Otherwise the one managed setting, then the platform default.
managed_root() {
  if [ -f "$HERE/harbor-member-mode" ]; then (cd "$HERE/.." && pwd -P); return 0; fi
  if [ -n "${HARBOR_MEMBER_ROOT:-}" ]; then printf '%s\n' "$HARBOR_MEMBER_ROOT"; return 0; fi
  # W4: the Windows answer may move this; WSL reads the Windows chain through /mnt/c.
  if [ "$(uname -s)" = Darwin ]; then printf '%s\n' '/Library/Application Support/ClaudeCode/harbor'
  elif grep -qi microsoft /proc/version 2>/dev/null; then printf '%s\n' '/mnt/c/Program Files/ClaudeCode/harbor'
  else printf '%s\n' /etc/claude-code/harbor; fi
}

is_member() { hub_is_member; }

# W7: the token store, bin/secret's file store on Linux and WSL (no keyring). The ref is hub-token, read
# through the sibling secret in the managed root, as hub-board.sh reads it; a copy outside a managed root may be pointed elsewhere.
secret_bin() {
  _sb="$HERE/secret"
  if [ ! -e "$HERE/harbor-member-mode" ] && [ -n "${HARBOR_ACCESS_SECRET_BIN:-}" ]; then _sb="$HARBOR_ACCESS_SECRET_BIN"; fi
  [ -f "$_sb" ] && printf '%s' "$_sb"   # W4: run with sh, so a drvfs mode without an execute bit still works
}
has_token() {
  _sb="$(secret_bin)" || return 1
  sh "$_sb" run hub-token HUB_SYNC_CREDENTIAL -- sh -c '[ -n "$HUB_SYNC_CREDENTIAL" ]' 2>/dev/null
}

# verify_pair <policy> <sig>: a real ssh-keygen -Y verify against the root-installed key. Anything missing is a failure.
verify_pair() {
  _sg="$(managed_root)/hub-signers"
  [ -s "$1" ] && [ -s "$2" ] && [ -s "$_sg" ] || return 1
  command -v ssh-keygen >/dev/null 2>&1 || return 1
  ssh-keygen -Y verify -f "$_sg" -I hub -n harbor-hub -s "$2" < "$1" > /dev/null 2>&1
}

serial_of() { # <file>: the serial, 0 when it is not a whole number
  _sv="$(jq -r 'if (.serial|type) == "number" then (.serial|floor|tostring) else "0" end' "$1" 2>/dev/null)" || _sv=0
  case "$_sv" in ''|*[!0-9]*) _sv=0 ;; esac
  printf '%s' "$_sv"
}

# best_policy: of the live copy and the last-good copy, the verified one with the higher serial, so replaying an older signed
# file into the live place cannot roll the policy back. Sets BEST (a path, empty when none verifies) and PRESENT (a file exists).
best_policy() {
  BEST=''; PRESENT=0; _bs=-1
  for _d in "$STATE" "$STATE/last-good"; do
    [ -e "$_d/policy.json" ] && PRESENT=1
    verify_pair "$_d/policy.json" "$_d/policy.json.sig" || continue
    _n="$(serial_of "$_d/policy.json")"
    if [ "$_n" -gt "$_bs" ]; then _bs="$_n"; BEST="$_d/policy.json"; fi
  done
  [ -n "$BEST" ]
}

record() { # <note>: the last attempt, for `status`; advisory only, nothing decides on it
  { mkdir -p "$STATE" && printf '%s\t%s\n' "$(date +%s)" "$1" > "$STATE/last-sync.$$" && mv -f "$STATE/last-sync.$$" "$STATE/last-sync"; } 2>/dev/null || :
}

# bounded <seconds> <command...>: no timeout(1) on BSD. A hung network must not hold a session start.
bounded() {
  _bsec="$1"; shift
  "$@" & _bp=$!
  ( sleep "$_bsec"; pkill -P "$_bp" 2>/dev/null; kill "$_bp" 2>/dev/null ) > /dev/null 2>&1 < /dev/null & _bw=$!
  _brc=0; wait "$_bp" 2>/dev/null || _brc=$?
  kill "$_bw" 2>/dev/null || :
  wait "$_bw" 2>/dev/null || :
  return "$_brc"
}

valid_repo() { case "$1" in */*/*|*/|/*|*[!A-Za-z0-9._/-]*|'') return 1 ;; */*) return 0 ;; *) return 1 ;; esac; }

remote_url() {
  # Honoured only with no member marker beside this file, as hub-board.sh treats its seam: this URL gets the token.
  if [ ! -e "$HERE/harbor-member-mode" ] && [ -n "${HARBOR_HUB_REMOTE:-}" ]; then
    # An override must be https or a local path; ext:: and friends are refused. Content is signed, so it can only cause "unreachable".
    case "$HARBOR_HUB_REMOTE" in https://?*|/?*) ;; *) return 1 ;; esac
    case "$HARBOR_HUB_REMOTE" in *[[:space:]]*|*[[:cntrl:]]*) return 1 ;; esac
    printf '%s' "$HARBOR_HUB_REMOTE"; return 0
  fi
  valid_repo "${HARBOR_HUB_REPO:-}" || return 1
  printf 'https://github.com/%s.git' "$HARBOR_HUB_REPO"
}

# The token rides in an Authorization header set through the git child's environment, never argv or the URL.
# It runs as the child of `secret run`: bin/secret has no verb that prints a value, and printing one here would rebuild it.
git_fetch() { # <clone> <url>
  if has_token; then sh "$(secret_bin)" run hub-token HUB_SYNC_CREDENTIAL -- sh "$0" --git-child "$1" "$2"
  else git_child "$1" "$2"; fi
}
git_child() { # <clone> <url>
  (
    export GIT_TERMINAL_PROMPT=0 GIT_ALLOW_PROTOCOL=https:file
    # A user-writable ~/.gitconfig could send this fetch, header and all, elsewhere with url.insteadOf: beside the marker no config but this one (harbor#1278).
    if [ -e "$HERE/harbor-member-mode" ]; then export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null; fi
    unset GIT_TRACE GIT_CURL_VERBOSE GIT_TRACE_CURL
    # Appended after any GIT_CONFIG entries already in the environment, never replacing them.
    _gn="${GIT_CONFIG_COUNT:-0}"; case "$_gn" in ''|*[!0-9]*) _gn=0 ;; esac
    export "GIT_CONFIG_KEY_$_gn=credential.helper" "GIT_CONFIG_VALUE_$_gn="; _gn=$((_gn + 1))
    if [ -n "${HUB_SYNC_CREDENTIAL:-}" ]; then
      export "GIT_CONFIG_KEY_$_gn=http.extraHeader" "GIT_CONFIG_VALUE_$_gn=Authorization: Basic $(printf 'x-access-token:%s' "$HUB_SYNC_CREDENTIAL" | tr -d ' \r\n' | base64 | tr -d '\n')"
      _gn=$((_gn + 1))
      unset HUB_SYNC_CREDENTIAL
    fi
    export GIT_CONFIG_COUNT="$_gn"
    bounded "$TIMEOUT" gs_env -C "$1" fetch -q --no-tags "$2" '+HEAD:refs/hub/head'
  )
}

cmd_path() {
  is_member || return 0
  if best_policy; then printf '%s\n' "$BEST"; fi
  return 0
}

cmd_state() {
  is_member || { echo none; return 0; }
  best_policy || { echo none; return 0; }
  _me="${HARBOR_MEMBER_LOGIN:-}"
  if [ -n "$_me" ] && [ "$(jq -r --arg m "$_me" '(.revoked // []) | index($m) != null' "$BEST" 2>/dev/null)" = true ]; then echo revoked; else echo joined; fi
}

cmd_check() {
  is_member || return 2
  if best_policy; then return 0; fi
  [ "$PRESENT" -eq 1 ] && return 1
  return 2
}

cmd_hook() { # <pack> <rel>
  [ $# -eq 2 ] || { log_fail "hook needs a pack id and a path"; log_fix "sh $0 hook <pack> <rel>"; return 2; }
  is_member && best_policy || return 1
  case "$1" in ''|*[!abcdefghijklmnopqrstuvwxyz0123456789.-]*) return 1 ;; esac
  case "$2" in ''|/*|*..*|*[!A-Za-z0-9._/-]*) return 1 ;; esac
  _want="$(jq -r --arg p "$1" --arg r "$2" '[.hooks[]? | select(.pack == $p and .path == $r) | .sha256][0] // empty' "$BEST")"
  [ -n "$_want" ] || return 1
  _hf="$STATE/hooks/$1/$2"
  [ -f "$_hf" ] && [ ! -L "$_hf" ] || return 1
  [ "$(hub_sha256 < "$_hf")" = "$_want" ] || return 1
  printf '%s\n' "$_hf"
}

cmd_fetch() {
  is_member || { log_note "not a member box: nothing to fetch"; return 0; }
  _sg="$(managed_root)/hub-signers"
  if [ ! -s "$_sg" ]; then
    log_fail "no hub-signers at $_sg, so nothing the hub sends can be proved"; log_fix "IT installs the admin's public key there (contracts/hub.md)"
    record "refused: no signer key"; return 1
  fi
  _url="$(remote_url)" || { log_fail "HARBOR_HUB_REPO is not owner/name"; log_fix "IT sets HARBOR_HUB_REPO in the managed settings"; record "refused: no hub repo"; return 1; }
  (umask 077; mkdir -p "$STATE") || { log_fail "cannot make $STATE"; log_fix "check the permissions of ${STATE%/*}"; return 1; }
  _clone="$STATE/repo"
  [ -d "$_clone/.git" ] || gs_env init -q "$_clone" 2>/dev/null || { log_fail "cannot make the hub clone at $_clone"; log_fix "check the permissions of $STATE"; return 1; }
  if ! git_fetch "$_clone" "$_url" > /dev/null 2>&1; then
    # A 401, a 403 and a dead network look alike from here, and none of them is a revocation (F27, R22): change nothing.
    log_warn "hub unreachable: the last good policy stays"; record "unreachable"; return 3
  fi
  _cand="$STATE/cand.$$"; rm -rf "$_cand"; (umask 077; mkdir -p "$_cand")
  trap 'rm -rf "$_cand"' EXIT INT TERM
  gs_env -C "$_clone" show --no-textconv refs/hub/head:policy.json > "$_cand/policy.json" 2>/dev/null &&
    gs_env -C "$_clone" show --no-textconv refs/hub/head:policy.json.sig > "$_cand/policy.json.sig" 2>/dev/null || {
    log_fail "the hub has no signed policy at its head"; log_fix "the admin runs harbor hub sign and commits policy.json and policy.json.sig"
    record "refused: no policy"; return 1; }
  if [ "$(wc -c < "$_cand/policy.json" | tr -d ' ')" -gt 524288 ]; then
    log_fail "policy.json is over 512 KB"; log_fix "the admin trims the policy"; record "refused: too large"; return 1
  fi
  # The signature first: nothing unsigned is parsed.
  if ! verify_pair "$_cand/policy.json" "$_cand/policy.json.sig"; then
    log_fail "the policy's signature does not verify against hub-signers: refused, the last good policy stays"
    log_fix "the admin signs with the key whose public half IT installed, or IT replaces hub-signers"
    record "refused: bad signature"; return 1
  fi
  if ! sh "$HERE/hub-format.sh" policy "$_cand/policy.json" > "$_cand/format.out" 2>&1; then
    log_fail "the signed policy breaks the format: $(head -n 1 "$_cand/format.out")"; log_fix "the admin fixes policy.json, then harbor hub sign"
    record "refused: format"; return 1
  fi
  _new="$(serial_of "$_cand/policy.json")"
  if best_policy; then
    _cur="$(serial_of "$BEST")"
    if [ "$_new" -lt "$_cur" ] || { [ "$_new" -eq "$_cur" ] && ! cmp -s "$_cand/policy.json" "$BEST"; }; then
      log_fail "serial $_new is not above the held serial $_cur: refused, so an old signed file cannot be replayed"
      log_fix "the admin raises serial in policy.json and signs again"
      record "refused: serial"; return 1
    fi
    if [ "$_new" -eq "$_cur" ]; then
      # Heal a copy that was damaged while the other verified, then report unchanged.
      for _d in "$STATE" "$STATE/last-good"; do
        verify_pair "$_d/policy.json" "$_d/policy.json.sig" || install_pair "$_cand" "$_d"
      done
      record "unchanged serial $_cur"; log_ok "policy unchanged at serial $_cur"; return 0
    fi
  fi
  install_pair "$_cand" "$STATE/last-good"
  install_pair "$_cand" "$STATE"
  record "updated serial $_new"
  log_ok "policy serial $_new accepted"
  if [ "$(jq -r --arg m "${HARBOR_MEMBER_LOGIN:-}" '(.revoked // []) | index($m) != null' "$_cand/policy.json")" = true ]; then
    log_note "the verified policy lists this login as revoked"
  fi
  return 0
}

install_pair() { # <from dir> <to dir>: signature first, so a reader between the two moves sees a mismatch and uses the other copy
  (umask 077; mkdir -p "$2") || return 1
  cp "$1/policy.json.sig" "$2/policy.json.sig.new.$$" && mv -f "$2/policy.json.sig.new.$$" "$2/policy.json.sig"
  cp "$1/policy.json" "$2/policy.json.new.$$" && mv -f "$2/policy.json.new.$$" "$2/policy.json"
}

_rc=0
case "${1:-}" in
  -h|--help) awk 'NR < 2 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;;
  --git-child) git_child "$2" "$3" ;;  # re-entered by `secret run`, which holds the credential for this one process
  path) cmd_path ;;
  state) cmd_state ;;
  check) cmd_check ;;
  hook) shift; cmd_hook "$@" ;;
  root) managed_root ;;
  token) has_token ;;
  fetch) cmd_fetch || _rc=$?; log_end || : ;;
  *) log_fail "usage: hub-sync.sh path | fetch | state | check | hook <pack> <rel> | root | token"; log_fix "sh $0 --help"; log_end || :; exit 2 ;;
esac
exit "$_rc"
