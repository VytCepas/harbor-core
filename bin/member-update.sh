#!/usr/bin/env sh
# member-update.sh (harbor#1278) — moves a member laptop's floor, every row of contracts/member-files.txt, to the core commit the hub pins. One run, then it exits.
#   sh member-update.sh [--dry-run] [--policy FILE]     --policy names the policy file (default: hub-sync.sh path)
# Exit 0 updated or unchanged, 1 refused (and rolled back), 2 usage, 3 core unreachable. The steps and the checks: docs/how-to/hub-admin.md.
# Runs as root from a schedule the operator said yes to (templates/member/); nothing schedules it here.
set -eu
# N8: system directories only. /usr/local and /opt/homebrew are a user's own on most boxes, and this runs as root (library-hub.sh, hub_env_clean).
PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
# root_owned <path> -> 0 when the file, after its links, and every folder above it are root's and writable by no group or other.
# PATH order is no proof: the floor's hooks pin the same directories, so a tool that isn't here doesn't run the floor either.
root_owned() {
  _ro="$1"; _ron=0
  while [ -L "$_ro" ] && [ "$_ron" -lt 16 ]; do
    _rl="$(readlink "$_ro")"; case "$_rl" in /*) _ro="$_rl" ;; *) _ro="${_ro%/*}/$_rl" ;; esac; _ron=$((_ron + 1))
  done
  [ -f "$_ro" ] && [ ! -L "$_ro" ] || return 1
  _ro="$(CDPATH='' cd -P -- "${_ro%/*}/" && pwd -P)/${_ro##*/}" || return 1   # a folder that is a link (/bin on usr-merged Linux) is judged where it leads
  while :; do
    _rm="$(ls -ldn "$_ro" 2>/dev/null)" || return 1
    [ "$(printf '%s' "$_rm" | awk '{ print $3 }')" = 0 ] || return 1
    case "$(printf '%s' "$_rm" | cut -c6,9)" in *w*) return 1 ;; esac
    [ "$_ro" != / ] || return 0
    _ro="${_ro%/*}"; [ -n "$_ro" ] || _ro=/
  done
}
[ "${MEMBER_UPDATE_LIB:-0}" = 1 ] && return 0
usage() { sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
LOG_FD=2; export LOG_FD
. "$HERE/library-log.sh"
log_init member-update
say() { log_note "$*"; }
refuse() { log_fail "refused: $*"; log_nofix "docs/how-to/hub-admin.md, raising the pin"; exit 1; }

DRY=0; POLICY_ARG=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --dry-run) DRY=1 ;;
    --policy) [ "$#" -ge 2 ] || usage; POLICY_ARG="$2"; shift ;;
    *) usage ;;
  esac
  shift
done

# W4: the managed root per OS; one function, so a Windows answer changes one place.
# Under root the path and the source are never caller-chosen (sudo -E would pass them), as in deploy-confinement.sh.
default_root() {
  case "$(uname -s)" in
    Darwin) printf '%s' '/Library/Application Support/ClaudeCode/harbor' ;;
    *) if grep -qi microsoft /proc/version 2>/dev/null; then printf '%s' '/mnt/c/Program Files/ClaudeCode/harbor'
       else printf '%s' '/etc/claude-code/harbor'; fi ;;
  esac
}
# HARBOR_MEMBER_ROOT moves the root and HARBOR_MEMBER_CORE_SOURCE names the core repo (tests only); under root
# <managed root>/core-source, a root-owned file, names it instead.
UID_NOW="$(id -u)"
if [ "$UID_NOW" -eq 0 ]; then
  for _v in HARBOR_MEMBER_ROOT HARBOR_MEMBER_CORE_SOURCE; do
    eval "_s=\${$_v:-}"
    [ -z "$_s" ] || refuse "$_v is set under root: a caller-chosen path or source (run with: sudo env -u $_v sh $0)"
  done
  ROOT="$(default_root)"
else
  ROOT="${HARBOR_MEMBER_ROOT:-$(default_root)}"
fi
ROOT="${ROOT%/}"
for _t in jq git ssh-keygen tar; do
  _tp="$(command -v "$_t" 2>/dev/null)" || refuse "$_t is missing from $PATH (a Homebrew copy is not used: the floor's hooks don't see it either)"
  root_owned "$_tp" || refuse "$_tp is not root's alone (it or a folder above it is someone else's, or writable by a group or others), and root would run it"
done
[ -d "$ROOT/bin" ] && [ -f "$ROOT/bin/harbor-member-mode" ] || refuse "$ROOT/bin/harbor-member-mode is absent: this is not a member box, and a standalone box is never touched"
[ -s "$ROOT/hub-signers" ] || refuse "no $ROOT/hub-signers: nothing to verify the policy against"

W="$(mktemp -d "$ROOT.update.XXXXXX")" || refuse "cannot make a work folder beside $ROOT (the swap needs the same filesystem)"
LOCK="$ROOT.update.lock"
cleanup() { rm -rf "$W"; [ "${HAVE_LOCK:-0}" = 1 ] && rm -rf "$LOCK" || :; }
trap cleanup EXIT
trap 'exit 130' INT HUP TERM
HAVE_LOCK=0
if ! mkdir "$LOCK" 2>/dev/null; then
  _p="$(cat "$LOCK/pid" 2>/dev/null || :)"
  if [ -n "$_p" ] && kill -0 "$_p" 2>/dev/null; then log_fail "another update is running (pid $_p)"; log_nofix "wait for it; one run at a time"; exit 3; fi
  rm -rf "$LOCK"; mkdir "$LOCK" 2>/dev/null || refuse "cannot take the update lock $LOCK"
fi
HAVE_LOCK=1; printf '%s\n' "$$" > "$LOCK/pid"

# 1 · the policy: root must not trust a file the agent could have swapped after hub-sync checked it, so it
# verifies a private copy against the root-owned hub-signers itself and reads only the copy.
# A schedule hands this PATH alone, and root's own env holds no role, so who this laptop is comes from the root-owned member.conf (contracts/hub.md).
conf() { sed -n "s/^$1=//p" "$ROOT/member.conf" 2>/dev/null | head -n 1; }
POLICY_SRC="$POLICY_ARG"
if [ -z "$POLICY_SRC" ]; then
  [ -f "$ROOT/bin/hub-sync.sh" ] || refuse "no --policy and no $ROOT/bin/hub-sync.sh to name the last good policy"
  _home="$(conf home)"
  case "$_home" in /*) ;; *) refuse "$ROOT/member.conf names no absolute home, so the member's policy can't be found" ;; esac
  POLICY_SRC="$(env HARBOR_MEMBER_ROLE=member HARBOR_HUB_REPO="$(conf hub)" HARBOR_MEMBER_LOGIN="$(conf login)" HOME="$_home" XDG_STATE_HOME="$_home/.local/state" \
    sh "$ROOT/bin/hub-sync.sh" path 2>/dev/null || :)"
fi
[ -n "$POLICY_SRC" ] && [ -f "$POLICY_SRC" ] || refuse "no verified policy yet (hub-sync.sh path printed nothing)"
[ -f "$POLICY_SRC.sig" ] || refuse "$POLICY_SRC.sig is missing"
cp "$POLICY_SRC" "$W/policy.json" && cp "$POLICY_SRC.sig" "$W/policy.json.sig" || refuse "cannot copy the policy"
ssh-keygen -Y verify -f "$ROOT/hub-signers" -I hub -n harbor-hub -s "$W/policy.json.sig" < "$W/policy.json" >/dev/null 2>&1 \
  || refuse "the policy signature does not verify against $ROOT/hub-signers"
if [ -f "$ROOT/bin/hub-format.sh" ]; then
  sh "$ROOT/bin/hub-format.sh" policy "$W/policy.json" >/dev/null 2>&1 || refuse "the policy fails hub-format.sh policy"
fi
COMMIT="$(jq -r '.core.commit // ""' "$W/policy.json")"; CONTRACT="$(jq -r '.core.contract // ""' "$W/policy.json")"; SERIAL="$(jq -r '.serial // ""' "$W/policy.json")"
case "$COMMIT" in ????????????????????????????????????????) ;; *) refuse "core.commit is not 40 characters" ;; esac
case "$COMMIT" in *[!0123456789abcdef]*) refuse "core.commit is not lowercase hex" ;; esac
case "$CONTRACT$SERIAL" in *[!0-9]*|'') refuse "core.contract or serial is not a whole number" ;; esac

# 2 · a serial below the last applied is an old signed file; a floor that already fails its check is not re-pinned
# over (re-pinning would launder tampering).
if [ -f "$ROOT/pin.serial" ]; then
  _last="$(cat "$ROOT/pin.serial")"
  case "$_last" in ''|*[!0-9]*) refuse "$ROOT/pin.serial is not a number" ;; esac
  [ "$SERIAL" -ge "$_last" ] || refuse "policy serial $SERIAL is below the $_last already applied: an old signed file"
fi
HERE_COMMIT="$(cat "$ROOT/core.commit" 2>/dev/null || :)"
if [ "$HERE_COMMIT" = "$COMMIT" ]; then log_ok "unchanged: the floor is already at ${COMMIT%????????????????????????????}"; log_end || :; exit 0; fi
if [ "$DRY" -eq 1 ]; then log_ok "dry run: would move the floor from ${HERE_COMMIT:-none} to $COMMIT (contract $CONTRACT, serial $SERIAL)"; log_end || :; exit 0; fi
[ -f "$ROOT/bin/member-integrity.sh" ] || refuse "no $ROOT/bin/member-integrity.sh to check the floor with"
sh "$ROOT/bin/member-integrity.sh" check >/dev/null 2>&1 || refuse "the floor already fails member-integrity.sh check; re-pinning would hide that. Fix or reinstall it first"

# 3 · the commit: fetched by id, proved to be that commit, every file checked against its blob id, contract matched.
if [ -s "$ROOT/core-source" ]; then SOURCE="$(head -n 1 "$ROOT/core-source")"
else SOURCE="${HARBOR_MEMBER_CORE_SOURCE:-https://github.com/VytCepas/harbor-core.git}"; fi
case "$SOURCE" in -*|'') refuse "the core source '$SOURCE' is not a path or URL" ;; esac
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG GIT_CONFIG_GLOBAL GIT_ALTERNATE_OBJECT_DIRECTORIES
G="git -c core.hooksPath=/dev/null -c protocol.ext.allow=never"
mkdir "$W/src" && $G -C "$W/src" init -q . || refuse "git could not make a scratch repository"
if ! $G -C "$W/src" fetch -q --depth 1 --no-tags -- "$SOURCE" "$COMMIT" 2> "$W/fetch.err"; then
  log_fail "core unreachable or the commit is not there: $(tail -n 1 "$W/fetch.err")"; log_nofix "the next run tries again; the floor is unchanged"; exit 3
fi
[ "$($G -C "$W/src" rev-parse --verify -q "FETCH_HEAD^{commit}" 2>/dev/null || :)" = "$COMMIT" ] || refuse "what was fetched is not commit $COMMIT"
# The commit's own list decides what lands, so a pin moves the tiers, the guard table and the vocabulary with the code that reads them.
$G -C "$W/src" cat-file blob "$COMMIT:contracts/member-files.txt" > "$W/list" 2>/dev/null || refuse "the commit has no contracts/member-files.txt"
sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^[[:space:]]*$/d' "$W/list" > "$W/rows"
[ -s "$W/rows" ] || refuse "contracts/member-files.txt at $COMMIT lists nothing"
: > "$W/tree"; set --
while read -r _src _dest _extra; do
  _dest="${_dest:-${_src##*/}}"
  [ -z "${_extra:-}" ] || refuse "contracts/member-files.txt at $COMMIT has a row of three words: $_src"
  case "$_src" in /*|-*|*..*) refuse "contracts/member-files.txt at $COMMIT names $_src, which is not a path in the repo" ;; esac
  case "$_dest" in */*|.*) refuse "contracts/member-files.txt at $COMMIT lands $_src at $_dest, which is not a plain name" ;; esac
  _ent="$($G -C "$W/src" ls-tree "$COMMIT" -- "$_src")" || refuse "git can't read the tree at $COMMIT"
  [ -n "$_ent" ] || refuse "contracts/member-files.txt names $_src, which $COMMIT lacks: a half floor stops every call"
  case "$_ent" in 100644\ *|100755\ *) ;; *) refuse "$_src at $COMMIT is a link or submodule, not a plain file" ;; esac
  _meta="${_ent%%	*}"
  printf '%s\t%s\t%s\n' "${_meta##* }" "$_src" "$_dest" >> "$W/tree"
  set -- "$@" "$_src"
done < "$W/rows"
mkdir "$W/unpacked" "$W/new" && $G -C "$W/src" archive --format=tar "$COMMIT" -- "$@" | tar -x -C "$W/unpacked" || refuse "cannot unpack the floor at $COMMIT"
while IFS="$(printf '\t')" read -r _sha _src _dest; do
  mv "$W/unpacked/$_src" "$W/new/$_dest" || refuse "cannot lay out $_src"
done < "$W/tree"
_cv="$(sed -n 's/^CONTRACT_VERSION=\([0-9][0-9]*\)$/\1/p' "$W/new/harbor" 2>/dev/null | head -n 1)"
[ "$_cv" = "$CONTRACT" ] || refuse "bin/harbor at $COMMIT is contract ${_cv:-unknown}, the policy pins contract $CONTRACT: a pin this floor cannot meet"
# every file, by the commit's own blob id (a plain file, as the tree check above)
verify_tree() { # <flat folder> -> 1 on the first file whose blob id is not the commit's
  _dir="$1"
  while IFS="$(printf '\t')" read -r _want _src _dest; do
    _f="$_dir/$_dest"
    [ -f "$_f" ] && [ ! -L "$_f" ] || return 1
    [ "$($G hash-object --no-filters -- "$_f")" = "$_want" ] || return 1
  done < "$W/tree"
}
verify_tree "$W/new" || refuse "an unpacked file differs from the blob the commit names"

# N7: the managed settings, composed again by the commit's own member-managed.sh from the verified policy, so a new host, a moved relay and a new
# hook or deny row reach the laptop without IT. Composed before the swap, so a commit that can't compose them moves nothing.
SETTINGS="${ROOT%/*}/managed-settings.json"   # W4: one above the root on every platform today, as member-integrity.sh reads it
[ -f "$SETTINGS" ] || refuse "no $SETTINGS: this floor was never landed whole"
mkdir "$W/core" && $G -C "$W/src" archive --format=tar "$COMMIT" | tar -x -C "$W/core" || refuse "cannot unpack $COMMIT to compose the settings"
[ -f "$W/core/bin/member-managed.sh" ] || refuse "$COMMIT has no bin/member-managed.sh to compose the managed settings with"
_home="$(conf home)"
case "$_home" in /*) ;; *) refuse "$ROOT/member.conf names no absolute home, so the member the settings are for is unknown" ;; esac
_who="$(ls -ld "$_home" 2>/dev/null | awk '{ print $3 }')"
case "$_who" in ''|-*|.*|root|*[!A-Za-z0-9._-]*) refuse "the home $_home is owned by '${_who:-nobody}', not a member" ;; esac
jq -c '.allowedMcpServers // []' "$SETTINGS" > "$W/mcp.json" || refuse "$SETTINGS is not JSON"
set -- --hub "$(conf hub)" --login "$(conf login)" --user "$_who" --root "$ROOT" --mcp-allow "$W/mcp.json"
_relay="$(jq -r '.support.relay // empty' "$W/policy.json")"; _relay="${_relay#*://}"; _relay="${_relay%%:*}"
[ -z "$_relay" ] || set -- "$@" --deny-host "$_relay"
[ "$(jq -c ".connectors // []" "$W/policy.json" 2>/dev/null)" = "[]" ] || set -- "$@" --allow-claudeai-mcps   # beside managed-mcp.json, so claude.ai connectors keep loading
_hosts="$(jq -r '(.hosts // [])[] | strings' "$W/policy.json")"
set -f   # a `*.` row must stay a word, not a glob
for _h in $_hosts; do set -- "$@" --allow-host "$_h"; done
set +f
# Under root the composer drops to the member to read their workspace (deploy-confinement.sh), so the member must be able to read the commit.
chmod 0711 "$W"; chmod -R a+rX "$W/core"
sh "$W/core/bin/member-managed.sh" "$@" > "$W/settings.json" 2> "$W/compose.err" || refuse "the managed settings at $COMMIT do not compose: $(tail -n 1 "$W/compose.err")"
# A proxy or CA IT set in managed env is the hub's one network source (contracts/hub.md, Network env), so it carries over.
jq -n --slurpfile old "$SETTINGS" --slurpfile new "$W/settings.json" \
  '["HTTPS_PROXY","HTTP_PROXY","ALL_PROXY","NO_PROXY","https_proxy","http_proxy","all_proxy","no_proxy","SSL_CERT_FILE","SSL_CERT_DIR","CURL_CA_BUNDLE","GIT_SSL_CAINFO"] as $k
   | $new[0] | .env = ((.env // {}) + (($old[0].env // {}) | with_entries(select(.key as $x | $k | index($x)))))' > "$W/settings.carried" \
  && jq -e 'type == "object"' "$W/settings.carried" >/dev/null 2>&1 || refuse "the composed settings are not a JSON object"

# 4 · the swap, and the way back: any failure after it restores bin, pin and records, and says whether the box checks.
# The new bin is the list and the marker, as an install lands it, so a file the pin dropped goes with no record of the last one.
mkdir "$W/stage" || refuse "cannot make the new bin"
cp -p "$ROOT/bin/harbor-member-mode" "$W/stage/" || refuse "cannot keep harbor-member-mode"
# N3: what the install placed in bin beside the list (upterm, by digest) is in floor.extra, inside the pin. It moves with the floor, and
# member-integrity.sh check fails a floor that lost one.
if [ -f "$ROOT/floor.extra" ]; then
  while IFS= read -r _x; do
    case "$_x" in ''|*/*|.*) refuse "$ROOT/floor.extra names '$_x', not a plain name" ;; esac
    [ -f "$ROOT/bin/$_x" ] && [ ! -L "$ROOT/bin/$_x" ] || refuse "$ROOT/floor.extra names $_x, and bin holds no such file"
    awk -F'\t' -v x="$_x" '$3 == x { f = 1 } END { exit !f }' "$W/tree" && refuse "$_x is in floor.extra and in the list at $COMMIT: one owner only"
    [ "$_x" = harbor-member-mode ] || cp -p "$ROOT/bin/$_x" "$W/stage/" || refuse "cannot keep $_x"
  done < "$ROOT/floor.extra"
  if grep -qx upterm "$ROOT/floor.extra" && ! cmp -s "$ROOT/bin/support-upterm.tsv" "$W/new/support-upterm.tsv"; then
    log_warn "$COMMIT pins another upterm than the one on this laptop, which stays until IT runs the install again"
  fi
fi
( cd "$W/new" && tar -cf - . ) | ( cd "$W/stage" && tar -xf - ) || refuse "cannot lay the new files out"
chmod -R 0755 "$W/stage"
chmod 0644 "$W/stage/harbor-member-mode"
[ "$UID_NOW" -ne 0 ] || chown -R 0:0 "$W/stage" || refuse "cannot give the new bin to root"

mkdir "$W/prev"; for _f in core.commit pin.serial floor.pin; do [ ! -f "$ROOT/$_f" ] || cp -p "$ROOT/$_f" "$W/prev/$_f"; done
cp "$SETTINGS" "$W/prev/managed-settings.json" || refuse "cannot keep a copy of $SETTINGS"   # not -p: a file flag would come too
rollback() { # <reason>
  log_fail "failed: $1"; log_nofix "the old floor is being put back (below)"
  [ -d "$W/old-bin" ] && { rm -rf "${ROOT:?}/bin"; mv "$W/old-bin" "$ROOT/bin"; }
  for _f in core.commit pin.serial floor.pin; do
    if [ -f "$W/prev/$_f" ]; then cp -p "$W/prev/$_f" "$ROOT/$_f"; else rm -f "$ROOT/$_f"; fi
  done
  cmp -s "$W/prev/managed-settings.json" "$SETTINGS" || { cp "$W/prev/managed-settings.json" "$SETTINGS.new.$$" && chmod 0644 "$SETTINGS.new.$$" \
    && { [ "$UID_NOW" -ne 0 ] || chown 0:0 "$SETTINGS.new.$$"; } && mv "$SETTINGS.new.$$" "$SETTINGS"; } || :
  if sh "$ROOT/bin/member-integrity.sh" check >/dev/null 2>&1; then log_ok "the old floor checks again"
  else log_fail "the old floor does NOT check"; log_nofix "reinstall it (docs/how-to/member-install.md)"; fi
  exit 1
}
mv "$ROOT/bin" "$W/old-bin" || refuse "cannot move $ROOT/bin aside"
mv "$W/stage" "$ROOT/bin" || rollback "cannot move the new bin into place"
verify_tree "$ROOT/bin" || rollback "an installed file differs from the commit"
printf '%s\n' "$COMMIT" > "$ROOT/core.commit" && printf '%s\n' "$SERIAL" > "$ROOT/pin.serial" || rollback "cannot record the commit"
# The settings land after the code they name, as an install lands them: a temp file beside the target, then a rename.
if [ "$(jq -S . "$SETTINGS")" != "$(jq -S . "$W/settings.carried")" ]; then
  if cp "$W/settings.carried" "$SETTINGS.new.$$" 2>/dev/null && chmod 0644 "$SETTINGS.new.$$" && { [ "$UID_NOW" -ne 0 ] || chown 0:0 "$SETTINGS.new.$$"; } \
     && mv "$SETTINGS.new.$$" "$SETTINGS" 2>/dev/null; then
    [ "$(jq -S . "$SETTINGS" 2>/dev/null)" = "$(jq -S . "$W/settings.carried")" ] || rollback "read-back: $SETTINGS is not what this run wrote"
    log_ok "the managed settings are composed again at $COMMIT, with policy serial $SERIAL's hosts and relay"
  else
    rm -f "$SETTINGS.new.$$" 2>/dev/null || :
    # W4: on WSL the file is under /mnt/c, and whether the distro's root can write there is the open question; the old file stays, whole.
    log_warn "cannot write $SETTINGS from here, so the old settings stay: new hosts, a moved relay or new rows wait until IT runs the install again"
  fi
fi
# member.connectors: the policy's connectors, composed by the commit's own member-managed.sh and landed as <root>/connectors.json and managed-mcp.json beside the
# settings (in /etc/claude-code on WSL). Before the pin below, which covers connectors.json. A list that does not compose keeps the old files and says so.
_mcpf="${ROOT%/*}/managed-mcp.json"; case "$ROOT" in /mnt/*) _mcpf=/etc/claude-code/managed-mcp.json ;; esac
_cj="$(jq -c '.connectors // []' "$W/policy.json" 2>/dev/null)" || _cj='[]'
if [ "$_cj" != '[]' ]; then
  printf '%s\n' "$_cj" > "$W/connectors.json"
  if sh "$W/core/bin/member-managed.sh" --mcp-servers "$W/connectors.json" --root "$ROOT" > "$W/managed-mcp.json" 2> "$W/mcp.err"; then
    _own() { [ "$UID_NOW" -ne 0 ] || chown 0:0 "$1"; }
    if cp "$W/connectors.json" "$ROOT/connectors.json.new.$$" && chmod 0644 "$ROOT/connectors.json.new.$$" && _own "$ROOT/connectors.json.new.$$" && mv "$ROOT/connectors.json.new.$$" "$ROOT/connectors.json" \
       && cp "$W/managed-mcp.json" "$_mcpf.new.$$" && chmod 0644 "$_mcpf.new.$$" && _own "$_mcpf.new.$$" && mv "$_mcpf.new.$$" "$_mcpf"; then
      log_ok "the policy's connectors are landed again (serial $SERIAL)"
    else
      rm -f "$ROOT/connectors.json.new.$$" "$_mcpf.new.$$" 2>/dev/null || :
      log_warn "cannot write the connectors from here, so the old ones stay until IT runs the install again"
    fi
  else
    log_warn "the policy's connectors do not compose at $COMMIT ($(tail -n 1 "$W/mcp.err")): the old ones stay"
  fi
elif [ -f "$ROOT/connectors.json" ]; then
  rm -f "$ROOT/connectors.json" "$_mcpf" 2>/dev/null || log_warn "the policy declares no connector now, and the old files could not be removed from here"
fi
_h="$(sh "$ROOT/bin/member-integrity.sh" hash 2>/dev/null || :)"
case "$_h" in ????????????????) ;; *) rollback "member-integrity.sh hash did not print 16 hex" ;; esac
case "$_h" in *[!0123456789abcdef]*) rollback "member-integrity.sh hash did not print 16 hex" ;; esac
printf '%s\n' "$_h" > "$ROOT/floor.pin" || rollback "cannot write floor.pin"
sh "$ROOT/bin/member-integrity.sh" check >/dev/null 2>&1 || rollback "member-integrity.sh check fails on the new floor"
log_ok "updated: ${HERE_COMMIT:-none} -> $COMMIT (contract $CONTRACT, serial $SERIAL)"
log_end || :
