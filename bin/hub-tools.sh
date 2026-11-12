#!/usr/bin/env sh
# hub-tools.sh (harbor#1278; `harbor hub tools`, control hub.tools-admin) — the admin's side of members' personal tools. Format: docs/how-to/hub-admin.md, section 10.
#   harbor hub tools create <login> [--hub OWNER/NAME] [--admin LOGIN]... [--policy FILE]
#        one private repo <owner>/tools-<login>: the person gets write, every admin read. Owner is the hub's. Admins are the --admin logins and the
#        approvers of --policy (a policy.json). Refuses where the organisation's default repository permission is not none, which would show it to every member.
#   harbor hub tools admit <tool> --hub-dir DIR --pack ID --from DIR
#        copy skills/<name> from a checkout of the personal repo (at the proposed commit) into packs/<ID> of a hub checkout, list it in extension.json,
#        and run hub-gate.sh over the result. A gate that is red puts the hub checkout back as it was and exits 1. It signs and merges nothing.
# Runs on the admin's box with the admin's own gh. Exit 0 done, 1 refused or the gate is red, 2 usage.
set -eu
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH='' cd -- "$HERE" && pwd)"
. "$HERE/library-hub.sh"
. "$HERE/library-log.sh"
LOG_FD=2
log_init hub-tools
CTL=hub.tools-admin
usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; }
die() { log_fail "$CTL: $1"; log_fix "${2:-sh $HERE/hub-tools.sh --help}"; log_end || :; exit "${3:-1}"; }
login_ok() { case "$1" in ''|-*|*[!A-Za-z0-9-]*) return 1 ;; esac; [ "${#1}" -le 39 ]; }

verb="${1:-}"; [ $# -eq 0 ] || shift
case "$verb" in create|admit) ;; -h|--help|help) usage; exit 0 ;; *) usage >&2; exit 2 ;; esac
! hub_is_member || die 'this is the admin side: a member'"'"'s tools sync by themselves' '' 1

HUB="${HARBOR_HUB_REPO:-}"; ADMINS=''; POLICY=''; ARG=''; HUBDIR=''; PACK=''; FROM=''
while [ $# -gt 0 ]; do
  case "$1" in
    --hub) [ $# -ge 2 ] || die '--hub needs owner/name' '' 2; HUB="$2"; shift ;;
    --admin) [ $# -ge 2 ] || die '--admin needs a login' '' 2; login_ok "$2" || die "'$2' is not a GitHub login" '' 2; ADMINS="$ADMINS $2"; shift ;;
    --policy) [ $# -ge 2 ] || die '--policy needs a file' '' 2; POLICY="$2"; shift ;;
    --hub-dir) [ $# -ge 2 ] || die '--hub-dir needs a folder' '' 2; HUBDIR="$2"; shift ;;
    --pack) [ $# -ge 2 ] || die '--pack needs an id' '' 2; PACK="$2"; shift ;;
    --from) [ $# -ge 2 ] || die '--from needs a folder' '' 2; FROM="$2"; shift ;;
    -*) die "unknown flag: $1" '' 2 ;;
    *) [ -z "$ARG" ] || die "one argument, not two: $1" '' 2; ARG="$1" ;;
  esac
  shift
done
command -v jq >/dev/null 2>&1 || die 'jq is missing' "$(pkg_hint jq)"

cmd_create() {
  login_ok "$ARG" || die "say the colleague's GitHub login: create <login>" '' 2
  slug_valid "$HUB" || die 'no hub named: pass --hub owner/name' 'harbor hub tools create <login> --hub owner/name' 2
  command -v gh >/dev/null 2>&1 || die 'gh is missing, and this uses your own GitHub login' "$(pkg_hint gh)"
  ORG="${HUB%%/*}"; REPO="$ORG/tools-$ARG"
  if [ -n "$POLICY" ]; then
    [ -r "$POLICY" ] || die "no policy at $POLICY" '' 2
    ADMINS="$ADMINS $(jq -r '(.approval.approvers // [])[]' "$POLICY" 2>/dev/null | tr '\n' ' ')"
  fi
  for _a in $ADMINS; do login_ok "$_a" || die "'$_a' is not a GitHub login" '' 2; done
  [ -n "$(printf '%s' "$ADMINS" | tr -d ' ')" ] || die 'no admin to read the repo: pass --admin LOGIN or --policy policy.json' '' 2
  # An org whose default repository permission is read or more shows every private repo to every member: this one would too.
  _dp="$(gh api "orgs/$ORG" --jq .default_repository_permission 2>/dev/null)" || die "could not read organisation $ORG (is gh signed in as an owner?)" 'gh auth status'
  [ "$_dp" = none ] || die "the organisation's default repository permission is '$_dp', so every member could read $REPO" "gh api -X PATCH orgs/$ORG -f default_repository_permission=none"
  if gh repo view "$REPO" >/dev/null 2>&1; then log_note "$CTL: $REPO exists already: only its access is set"
  else gh repo create "$REPO" --private --description "personal tools of $ARG (harbor hub tools)" >/dev/null || die "gh repo create $REPO failed"; log_ok "$CTL: created $REPO (private)"; fi
  gh api -X PUT "repos/$REPO/collaborators/$ARG" -f permission=push >/dev/null || die "could not give $ARG write on $REPO"
  log_ok "$CTL: $ARG has write on $REPO"
  for _a in $ADMINS; do
    [ "$_a" != "$ARG" ] || continue
    gh api -X PUT "repos/$REPO/collaborators/$_a" -f permission=pull >/dev/null || die "could not give $_a read on $REPO"
    log_ok "$CTL: $_a has read on $REPO"
  done
  log_note "$CTL: the member's hub token must list $REPO with Contents read and write, or their laptop cannot reach it: docs/how-to/hub-admin.md, section 10"
  log_end || :
}

cmd_admit() {
  case "$ARG" in skills/*) _n="${ARG#skills/}" ;; '') die 'say the tool: admit skills/<name>' '' 2 ;; *) _n="$ARG" ;; esac
  case "$_n" in ''|[!A-Za-z0-9]*|*[!A-Za-z0-9._-]*|*..*) die "'$_n' is not a plain skill name" '' 2 ;; esac
  case "$PACK" in ''|[!abcdefghijklmnopqrstuvwxyz0123456789]*|*[!abcdefghijklmnopqrstuvwxyz0123456789-]*) die '--pack wants a kebab-case pack id' '' 2 ;; esac
  [ -d "$HUBDIR/packs" ] || die "--hub-dir $HUBDIR is not a hub checkout (no packs/)" '' 2
  [ -f "$FROM/skills/$_n/SKILL.md" ] || die "no skills/$_n/SKILL.md under --from $FROM" '' 2
  [ -z "$(find "$FROM/skills/$_n" -type l | head -n 1)" ] || die "skills/$_n holds a symlink: a hub pack carries none" ''
  HUBDIR="$(CDPATH='' cd -- "$HUBDIR" && pwd)"
  _pk="$HUBDIR/packs/$PACK"; _w="$(mktemp -d "${TMPDIR:-/tmp}/hub-tools.XXXXXX")"; trap 'rm -rf "$_w"' EXIT
  _had=0; if [ -d "$_pk" ]; then _had=1; cp -R "$_pk" "$_w/backup"; fi
  _undo() { rm -rf "$_pk"; [ "$_had" -eq 0 ] || cp -R "$_w/backup" "$_pk"; }
  [ ! -e "$_pk/harbor-pack/skills/$_n" ] || die "packs/$PACK already holds skills/$_n: the admin edits it by hand" ''
  mkdir -p "$_pk/harbor-pack/skills"
  [ -f "$_pk/harbor-pack/pack.toml" ] || printf 'name = "%s"\nversion = "1.0.0"\nharbor_version = ">=1"\ndescription = "tools admitted from members"\n' "$PACK" > "$_pk/harbor-pack/pack.toml"
  cp -R "$FROM/skills/$_n" "$_pk/harbor-pack/skills/$_n"
  # extension.json: every file but pack.toml, with its sha256, as the hub's gate and every laptop read it
  _ver="$(jq -r '.version // "1.0.0"' "$_pk/extension.json" 2>/dev/null)" || _ver=1.0.0
  ( cd "$_pk/harbor-pack" && find . -type f ! -name pack.toml | sed 's|^\./||' | LC_ALL=C sort | while IFS= read -r _f; do
      jq -n --arg p "$_f" --arg s "$(hub_sha256 < "$_f")" '{path:$p,sha256:$s}'; done ) |
    jq -s --arg i "$PACK" --arg v "${_ver:-1.0.0}" '{schema:1,id:$i,version:$v,harbor_version:">=1",provides:["skill"],files:.}' > "$_pk/extension.json"
  _rc=0; sh "$HERE/hub-gate.sh" "$HUBDIR" > "$_w/gate" 2>&1 || _rc=$?
  if [ "$_rc" -ne 0 ]; then
    _undo
    sed 's/^/  gate: /' "$_w/gate" >&2
    die "the hub gate refused skills/$_n (exit $_rc): the hub checkout is as it was" 'fix the skill in the personal repo, or tell the colleague what the gate said'
  fi
  log_ok "$CTL: skills/$_n is in packs/$PACK and the gate is clean"
  log_note "$CTL: next, by hand: list the pack's commit in policy.json packs, raise serial, 'harbor hub sign', open the pull request (docs/how-to/hub-admin.md, section 10)"
  log_end || :
}

case "$verb" in create) cmd_create ;; admit) cmd_admit ;; esac
