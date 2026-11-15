#!/usr/bin/env sh
# member-tools.sh (harbor#1278; control member.tools-sync) — a member's own skills, agents and commands, kept in sync with their private repo.
#   sh member-tools.sh pull                 session start: bring the personal repo's tools into <config>/skills, agents, commands
#   sh member-tools.sh push                 Stop: when something changed, commit the personal tools to the repo and push; then send what `propose` queued
#   sh member-tools.sh propose <tool>       queue a proposal to move one tool to the company hub (a skills/<name> tool); the next push opens the hub issue
#   sh member-tools.sh status               the repo, the last result, what was skipped and why
#   sh member-tools.sh workdir              the folder this makes its temp clones in (a folder the managed settings deny to the agent)
# The repo is <org>/tools-<login>: the org is the hub repo's own owner (HARBOR_HUB_REPO), never a constant here. Layout: skills/<name>/SKILL.md,
# agents/<name>.md, commands/<name>.md. Nothing else in it is read.
# The personal place is <config>/skills, agents, commands. This never writes the managed root, a project, a hook or a setting; a tool whose front
# matter has a hooks: key, a symlink or an oversized file is skipped and said. A name that a managed install, a hub pack or a core skill holds is
# skipped and said: managed wins. Where a tool differs on both sides, the laptop's copy wins and is pushed.
# Bounded like the hub calls (HARBOR_HUB_TIMEOUT, default 8 seconds), fail-open: every exit from a hook verb is 0, and an unreachable or missing repo
# changes nothing on disk. The token is the member's hub token (its repo list includes the personal repo, docs/how-to/hub-admin.md), read only through
# bin/secret as a child, so this verb works from a hook and not from the agent's sandbox: that is why propose queues instead of sending.
# Nothing the agent can write decides what git runs or where the token goes: every run clones into a fresh mode-700 temp dir the hook makes and removes
# (state under ~/.local/state/harbor/tools is data only, never a git dir), git ignores every user and system config and runs no hook or fsmonitor, and the
# auth header is scoped to the exact remote URL and sits in the environment of the one git process that needs it. State files are validated when read.
# Test seam, honoured only with no member marker beside this file: HARBOR_HUB_TOOLS_REMOTE (a local path or https URL).
# Exit 0 done or nothing to do, 1 a refusal of propose or an unusable argument, 2 usage.
set -eu
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH='' cd -- "$HERE" && pwd -P)"
. "$HERE/library-log.sh"
. "$HERE/library-hub.sh"
CTL=member.tools-sync
FAULT=0
if hub_marker; then hub_env_clean || FAULT=1; fi
log_init member-tools
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh; stdout of a hook verb is the hook's reply
LOG_FD=2
TAB="$(printf '\t')"
TIMEOUT="${HARBOR_HUB_TIMEOUT:-8}"
case "$TIMEOUT" in ''|*[!0-9]*) TIMEOUT=8 ;; esac
MAX_BYTES=1048576
# No user or system git config, ever: ~/.gitconfig is the agent's to write (core.fsmonitor, core.hooksPath, url.<x>.insteadOf all run or redirect from it).
GIT_TERMINAL_PROMPT=0; GIT_ALLOW_PROTOCOL=https:file; GIT_CONFIG_NOSYSTEM=1; GIT_CONFIG_GLOBAL=/dev/null
export GIT_TERMINAL_PROMPT GIT_ALLOW_PROTOCOL GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL
unset GIT_CONFIG_COUNT GIT_EXEC_PATH GIT_TEMPLATE_DIR GIT_SSH GIT_SSH_COMMAND GIT_PROXY_COMMAND GIT_ASKPASS SSH_ASKPASS 2>/dev/null || :
# git_safe <args>: git with the settings that run code or move a request switched off on the command line too (belt to the env's braces).
git_safe() { git -c core.hooksPath=/dev/null -c core.fsmonitor=false -c core.sshCommand=false -c http.followRedirects=false -c credential.helper= "$@"; }

# A hook never fails a session: say it on stdout as one line and leave.
quiet_exit() { [ "${HOOK:-0}" = 1 ] && exit 0; exit "${1:-0}"; }
# pull's stdout is the session note member-session.sh carries; push runs at Stop, where stdout is the hook's reply and so stays empty.
say() { if [ "$VERB" = pull ]; then printf '%s: %s\n' "$CTL" "$1"; else printf '%s: %s\n' "$CTL" "$1" >&2; fi; }
warn() { printf '%s: %s\n' "$CTL" "$1" >&2; }

# --child <url> <git args> is this script re-entered by `secret run`, which holds the credential in the environment for one process: git gets it as a header
# scoped to that url (a redirect to another host never carries it), never argv, and the variable is gone before git starts.
if [ "${1:-}" = --child ]; then
  [ $# -ge 3 ] || exit 2
  _curl="$2"; shift 2
  case "$_curl" in https://?*|/?*) ;; *) exit 2 ;; esac
  if [ -n "${TOOLS_CREDENTIAL:-}" ]; then
    GIT_CONFIG_COUNT=1; GIT_CONFIG_KEY_0="http.$_curl.extraHeader"
    GIT_CONFIG_VALUE_0="Authorization: Basic $(printf 'x-access-token:%s' "$TOOLS_CREDENTIAL" | tr -d ' \r\n' | base64 | tr -d '\n')"
    export GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0
  fi
  unset TOOLS_CREDENTIAL GIT_TRACE GIT_CURL_VERBOSE GIT_TRACE_CURL
  git_safe "$@"
  exit $?
fi

case "${1:-}" in
  -h|--help|help) awk 'NR < 2 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;;
  pull|push) VERB="$1"; HOOK=1; shift ;;
  propose|status|workdir) VERB="$1"; HOOK=0; shift ;;
  *) awk 'NR < 2 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0" >&2; exit 2 ;;
esac

[ "$FAULT" -eq 0 ] || { warn "this laptop's member facts could not be read: nothing synced"; quiet_exit 1; }
hub_is_member || [ -n "${HARBOR_HUB_TOOLS_REMOTE:-}" ] || { [ "$HOOK" = 1 ] && exit 0; warn "this is not a member laptop: there is no personal repo to sync"; exit 1; }

LOGIN="${HARBOR_MEMBER_LOGIN:-}"
HUBREPO="${HARBOR_HUB_REPO:-}"
case "$LOGIN" in ''|-*|*[!A-Za-z0-9-]*) warn "no GitHub login known: nothing synced"; quiet_exit 1 ;; esac
slug_valid "$HUBREPO" || { warn "no hub repo known: nothing synced"; quiet_exit 1; }
ORG="${HUBREPO%%/*}"
PERSONAL="$ORG/tools-$LOGIN"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
ST="$(dirname "$(hub_state_dir)")/tools"
HUBST="$(hub_state_dir)"
DB="$ST/installed.tsv"            # rel TAB hash: what the laptop and the repo last agreed on
PROP="$CFG/.harbor-tools/propose"  # a request the agent can write: the hook validates it and sends

# Never into the managed root: the config dir must not sit under it.
MROOT="$(CDPATH='' cd -- "$HERE/.." && pwd -P)"
# the nearest existing ancestor, resolved, plus the rest: a config dir not made yet still has to be judged by where it would land
_cr="$CFG"; _tail=''
while [ ! -d "$_cr" ] && [ "$_cr" != / ] && [ "$_cr" != . ]; do _tail="/${_cr##*/}$_tail"; _cr="$(dirname "$_cr")"; done
_cr="$(CDPATH='' cd -- "$_cr" 2>/dev/null && pwd -P)${_tail}" || _cr="$CFG"
case "$_cr/" in "$MROOT"/*) warn "the config dir $CFG is inside the managed root: nothing synced"; quiet_exit 1 ;; esac

# Temp clones live under the hub state folder, which the managed settings deny to the agent for sandbox writes and for Edit (bin/member-managed.sh,
# member_protected): a same-user process of the agent cannot race into one while it runs. Never $TMPDIR, which the agent may write. If the folder can't be
# made the hook does nothing.
WORKBASE="$HUBST"
if [ "$VERB" = workdir ]; then printf '%s\n' "$WORKBASE"; exit 0; fi
_top="$WORKBASE"; while [ ! -d "$_top" ] && [ "$_top" != / ]; do _top="$(dirname "$_top")"; done   # the nearest folder that was already there
mkdir -p "$WORKBASE" 2>/dev/null || quiet_exit 0
chmod 700 "$WORKBASE" 2>/dev/null || :
W="$(umask 077; mktemp -d "$WORKBASE/tools-work.XXXXXX" 2>/dev/null)" || quiet_exit 0
chmod 700 "$W" 2>/dev/null || :
REPO="$W/repo"   # a fresh clone per run, in a directory the agent could not have planted anything in
# a state folder this run made is taken away again with its parents, so a run that changed nothing leaves nothing
_cleanup() {
  rm -rf "$W"
  _cd="$WORKBASE"; while [ "$_cd" != "$_top" ] && [ "$_cd" != / ]; do rmdir "$_cd" 2>/dev/null || break; _cd="$(dirname "$_cd")"; done
}
trap _cleanup EXIT
trap 'exit 0' HUP INT TERM

remote_url() {
  if [ ! -e "$HERE/harbor-member-mode" ] && [ -n "${HARBOR_HUB_TOOLS_REMOTE:-}" ]; then
    case "$HARBOR_HUB_TOOLS_REMOTE" in https://?*|/?*) ;; *) return 1 ;; esac
    case "$HARBOR_HUB_TOOLS_REMOTE" in *[[:space:]]*|*[[:cntrl:]]*) return 1 ;; esac
    printf '%s' "$HARBOR_HUB_TOOLS_REMOTE"; return 0
  fi
  printf 'https://github.com/%s.git' "$PERSONAL"
}
secret_bin() {
  _sb="$HERE/secret"
  if [ ! -e "$HERE/harbor-member-mode" ] && [ -n "${HARBOR_ACCESS_SECRET_BIN:-}" ]; then _sb="$HARBOR_ACCESS_SECRET_BIN"; fi
  [ -f "$_sb" ] && printf '%s' "$_sb"
}
has_token() { _s="$(secret_bin)" || return 1; sh "$_s" run hub-token TOOLS_CREDENTIAL -- sh -c '[ -n "$TOOLS_CREDENTIAL" ]' 2>/dev/null; }
# net <url> <git args>: one git process, bounded. With a stored token (secret_bin names where it is looked for) that process gets the url-scoped header through `secret run`.
net() {
  _nurl="$1"; shift; _nrc=0
  if has_token; then
    hub_bounded "$TIMEOUT" sh "$(secret_bin)" run hub-token TOOLS_CREDENTIAL -- sh "$0" --child "$_nurl" "$@" || _nrc=$?
  else
    hub_bounded "$TIMEOUT" git_safe "$@" || _nrc=$?
  fi
  return "$_nrc"
}
git_id() { git_safe -c user.name=harbor-tools -c user.email=harbor-tools@users.noreply.invalid -c commit.gpgsign=false "$@"; }

# ── names, items, hashes ─────────────────────────────────────────────────────────────────────────────────
name_ok() { case "$1" in ''|[!A-Za-z0-9]*|*[!A-Za-z0-9._-]*|*..*) return 1 ;; esac; [ "${#1}" -le 64 ]; }
# rel_ok <rel>: skills/<n>, agents/<n>.md or commands/<n>.md with a good name
rel_ok() {
  case "$1" in
    skills/*) name_ok "${1#skills/}" ;;
    agents/*.md) name_ok "${1#agents/}" && name_ok "$(basename "$1" .md)" ;;
    commands/*.md) name_ok "${1#commands/}" && name_ok "$(basename "$1" .md)" ;;
    *) return 1 ;;
  esac
}
lower() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }
# list_items <root>: every candidate rel under a skills/, agents/, commands/ folder, one per line, sorted
list_items() {
  for _k in skills agents commands; do
    [ -d "$1/$_k" ] || continue
    ( cd "$1/$_k" && find . -mindepth 1 -maxdepth 1 ! -name '.*' | sed 's|^\./||' | LC_ALL=C sort ) | while IFS= read -r _n; do
      case "$_k:$_n" in skills:*|agents:*.md|commands:*.md) printf '%s/%s\n' "$_k" "$_n" ;; esac
    done
  done
}
item_hash() { # <root> <rel>
  if [ -d "$1/$2" ]; then
    ( cd "$1/$2" && find . -type f | LC_ALL=C sort | while IFS= read -r _f; do printf '%s %s\n' "$(hub_sha256 < "$_f")" "$_f"; done ) | hub_sha256
  else hub_sha256 < "$1/$2"; fi
}
# item_bad <root> <rel>: prints why this item is not carried, nothing when it is
item_bad() {
  _p="$1/$2"
  rel_ok "$2" || { printf 'its name is not a plain name'; return 0; }
  if [ -L "$_p" ] || [ -n "$(find "$_p" -type l 2>/dev/null | head -n 1)" ]; then printf 'it holds a symlink'; return 0; fi
  case "$2" in skills/*) [ -f "$_p/SKILL.md" ] || { printf 'it has no SKILL.md'; return 0; } ;; *) [ -f "$_p" ] || { printf 'it is not a file'; return 0; } ;; esac
  [ -n "$(find "$_p" ! -type f ! -type d 2>/dev/null | head -n 1)" ] && { printf 'it holds a file that is not a regular file'; return 0; }
  _sz="$(find "$_p" -type f -exec cat {} + 2>/dev/null | wc -c | tr -d ' ')"
  [ "${_sz:-0}" -le "$MAX_BYTES" ] || { printf 'it is over %s bytes' "$MAX_BYTES"; return 0; }
  # a hook in front matter (skills and agents can carry one): personal hooks stay forbidden
  _mds="$(find "$_p" -type f -name '*.md' 2>/dev/null)"
  for _m in $_mds; do
    tr -d '\r' < "$_m" | awk 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit } NR > 1 && /^[ \t]*hooks[ \t]*:/ { f = 1 } END { exit !f }' && { printf 'its front matter has a hooks: key'; return 0; }
  done
  return 0
}
# managed_set: rels a managed install, a hub pack or a core skill holds, lower-cased, into $W/managed
managed_set() {
  : > "$W/managed"
  _norm() { awk '{ n = split($0, a, "/"); if (a[1] == "skills" && n >= 2) print "skills/" a[2]; else if ((a[1] == "agents" || a[1] == "commands") && n == 2) print $0 }'; }
  if [ -f "$CFG/.harbor-manifest" ]; then awk '/^#/ || NF < 5 { next } { print $3 }' "$CFG/.harbor-manifest" | _norm >> "$W/managed"; fi
  for _m in "$CFG"/.harbor-packs/*.tsv; do
    [ -f "$_m" ] || continue
    awk -F'\t' '($1 == "F" || $1 == "D") && NF >= 2 { print $2 }' "$_m" | _norm >> "$W/managed"
  done
  # what the hub offers, installed or not
  for _pk in "$HUBST"/repo/packs/*/harbor-pack; do
    [ -d "$_pk" ] || continue
    list_items "$_pk" >> "$W/managed"
  done
  # core's own skills, where this copy sits beside them (a checkout; a managed root carries none)
  [ -d "$MROOT/skills" ] && list_items "$MROOT" | grep '^skills/' >> "$W/managed" || :
  tr 'A-Z' 'a-z' < "$W/managed" | LC_ALL=C sort -u > "$W/managed.l"
}
is_managed() { grep -qxF "$(lower "$1")" "$W/managed.l"; }

# ── the baseline: rel TAB hash ───────────────────────────────────────────────────────────────────────────
# The state file is the agent's to write, so it is read only through db_clean: a line counts when its rel passes rel_ok and its hash is 64 hex.
# A planted skills/../../x never reaches an rm -rf, a cp or a git path.
db_clean() {
  : > "$W/db.clean"
  [ -f "$DB" ] || return 0
  while IFS="$TAB" read -r _dr _dh _dx; do
    [ -z "${_dx:-}" ] || continue
    rel_ok "$_dr" || continue
    case "$_dh" in ''|*[!0123456789abcdef]*) continue ;; esac
    [ "${#_dh}" -eq 64 ] || continue
    printf '%s\t%s\n' "$_dr" "$_dh"
  done < "$DB" >> "$W/db.clean"
}
base_get() { awk -F'\t' -v r="$1" '$1 == r { print $2; exit }' "$W/db.clean" 2>/dev/null || :; }
base_put() { # <rel> <hash> into $W/db.new
  printf '%s\t%s\n' "$1" "$2" >> "$W/db.new"
}
db_commit() {
  mkdir -p "$ST" 2>/dev/null || return 1
  LC_ALL=C sort -u "$W/db.new" > "$ST/installed.tsv.new.$$" && mv -f "$ST/installed.tsv.new.$$" "$DB"
}
# local_set: the personal place's carried items into $W/local (rel TAB hash); skipped ones into $W/skip (rel TAB why)
local_set() {
  : > "$W/local"; : > "$W/skip"
  list_items "$CFG" | while IFS= read -r _r; do
    if is_managed "$_r"; then continue; fi
    _why="$(item_bad "$CFG" "$_r")"
    if [ -n "$_why" ]; then printf '%s\t%s\n' "$_r" "$_why" >> "$W/skip"; continue; fi
    printf '%s\t%s\n' "$_r" "$(item_hash "$CFG" "$_r")" >> "$W/local"
  done
}

# sync_clone: a fresh clone of the remote in $REPO. 0 reached, 1 not reached (nothing changed anywhere). Sets REMOTE_HEAD (empty for an empty repo).
REMOTE_HEAD=''
sync_clone() {
  _url="$(remote_url)" || return 1
  rm -rf "$REPO"
  net "$_url" clone -q --no-tags --no-local "$_url" "$REPO" >/dev/null 2>&1 || return 1
  [ -d "$REPO/.git" ] || return 1
  REMOTE_HEAD="$(git_safe -C "$REPO" rev-parse HEAD 2>/dev/null)" || REMOTE_HEAD=''
  return 0
}
record_status() { mkdir -p "$ST" 2>/dev/null && printf '%s\t%s\n' "$(date +%s)" "$1" > "$ST/last" 2>/dev/null || :; }
add_skipped_note() { # reads $W/skip, $W/collide into a short note
  _n=''
  if [ -s "$W/collide" ]; then _n="$_n skipped, a managed or hub tool has the name: $(awk '{ printf "%s%s", (c++ ? ", " : ""), $1 }' "$W/collide")."; fi
  if [ -s "$W/skip" ]; then _n="$_n not carried: $(awk -F'\t' '{ printf "%s%s (%s)", (c++ ? ", " : ""), $1, $2 }' "$W/skip")."; fi
  printf '%s' "$_n"
}

install_item() { # <rel>: copy from the repo into the config dir, atomically
  _rel="$1"; _kind="${_rel%%/*}"; _dst="$CFG/$_rel"
  mkdir -p "$CFG/$_kind" || return 1
  rm -rf "$CFG/$_kind/.tools-new.$$"
  cp -R "$REPO/$_rel" "$CFG/$_kind/.tools-new.$$" || { rm -rf "$CFG/$_kind/.tools-new.$$"; return 1; }
  rm -rf "$_dst"
  mv "$CFG/$_kind/.tools-new.$$" "$_dst"
}

cmd_pull() {
  managed_set
  sync_clone || { warn "the personal repo $PERSONAL could not be reached: nothing changed"; return 0; }
  db_clean
  : > "$W/db.new"; : > "$W/collide"; : > "$W/skip"; : > "$W/installed"; : > "$W/removed"
  [ -z "$REMOTE_HEAD" ] || [ ! -d "$REPO" ] || list_items "$REPO" > "$W/remote"
  [ -f "$W/remote" ] || : > "$W/remote"
  while IFS= read -r _r; do
    if is_managed "$_r"; then printf '%s\n' "$_r" >> "$W/collide"; continue; fi
    _why="$(item_bad "$REPO" "$_r")"
    if [ -n "$_why" ]; then printf '%s\t%s\n' "$_r" "$_why" >> "$W/skip"; continue; fi
    _rh="$(item_hash "$REPO" "$_r")"
    if [ ! -e "$CFG/$_r" ]; then
      if install_item "$_r"; then base_put "$_r" "$_rh"; printf '%s\n' "$_r" >> "$W/installed"; else warn "$_r could not be written: left alone"; fi
      continue
    fi
    _lh="$(item_hash "$CFG" "$_r")"; _bh="$(base_get "$_r")"
    if [ "$_lh" = "$_rh" ]; then base_put "$_r" "$_rh"
    elif [ -n "$_bh" ] && [ "$_lh" = "$_bh" ]; then
      if install_item "$_r"; then base_put "$_r" "$_rh"; printf '%s\n' "$_r" >> "$W/installed"; else base_put "$_r" "$_bh"; fi
    else
      [ -z "$_bh" ] || base_put "$_r" "$_bh"   # the laptop's copy differs: it stays, and the next push sends it
    fi
  done < "$W/remote"
  # a tool the repo dropped goes from this laptop only when this laptop had not changed it
  if [ -n "$REMOTE_HEAD" ] && [ -s "$W/db.clean" ]; then
    while IFS="$TAB" read -r _r _bh; do
      grep -qxF "$_r" "$W/remote" && continue
      is_managed "$_r" && continue
      if [ -e "$CFG/$_r" ] && [ "$(item_hash "$CFG" "$_r")" = "$_bh" ]; then rm -rf "$CFG/$_r"; printf '%s\n' "$_r" >> "$W/removed"
      elif [ -e "$CFG/$_r" ]; then base_put "$_r" "$_bh"; fi
    done < "$W/db.clean"
  elif [ -s "$W/db.clean" ]; then
    cat "$W/db.clean" >> "$W/db.new"
  fi
  db_commit || warn "the sync record could not be written"
  head_put "$REMOTE_HEAD"
  record_status "pulled $(wc -l < "$W/installed" | tr -d ' ') new or updated, $(wc -l < "$W/removed" | tr -d ' ') removed, $(wc -l < "$W/collide" | tr -d ' ') skipped by name"
  _msg=''
  [ ! -s "$W/installed" ] || _msg="$_msg updated from your personal repo: $(tr '\n' ' ' < "$W/installed" | sed 's/ $//')."
  [ ! -s "$W/removed" ] || _msg="$_msg removed (dropped from your personal repo): $(tr '\n' ' ' < "$W/removed" | sed 's/ $//')."
  _msg="$_msg$(add_skipped_note)"
  [ -z "$_msg" ] || say "${_msg# }"
  return 0
}

# ── propose ──────────────────────────────────────────────────────────────────────────────────────────────
slug() { printf '%s' "$1" | tr '/' '_'; }
cmd_propose() {
  CTL=member.tools-propose
  _tool="${1:-}"; [ $# -gt 0 ] && shift || :
  _note=''
  while [ $# -gt 0 ]; do
    case "$1" in --note) [ $# -ge 2 ] || { warn "--note needs text"; return 2; }; _note="$2"; shift ;; *) warn "unknown argument $1"; return 2 ;; esac
    shift
  done
  [ -n "$_tool" ] || { warn "say which tool: propose skills/<name>"; return 2; }
  case "$_tool" in */*) ;; *) _tool="skills/$_tool" ;; esac
  case "$_tool" in skills/*) ;; *) warn "only a skill can move to the hub (a hub pack carries skills): $_tool"; return 1 ;; esac
  rel_ok "$_tool" || { warn "$_tool is not a plain skill name"; return 1; }
  [ -f "$CFG/$_tool/SKILL.md" ] || { warn "$_tool is not in your personal place ($CFG/skills)"; return 1; }
  managed_set
  ! is_managed "$_tool" || { warn "$_tool has the name of a managed or hub tool, and managed wins: rename it first"; return 1; }
  _why="$(item_bad "$CFG" "$_tool")"; [ -z "$_why" ] || { warn "$_tool is not carried ($_why): fix that first"; return 1; }
  case "$_note" in *[[:cntrl:]]*) warn "--note has a control character"; return 1 ;; esac
  [ "${#_note}" -le 300 ] || { warn "--note is over 300 characters"; return 1; }
  mkdir -p "$PROP" || { warn "$PROP is not writable"; return 1; }
  printf '%s\n%s\n' "$_tool" "$_note" > "$PROP/$(slug "$_tool")" || return 1
  log_ok "$CTL: queued $_tool; the end of your turn pushes it to $PERSONAL and opens the hub issue"
  log_end || :
  return 0
}
# send_proposals: for each queued request, once its commit is on the remote, open one issue on the hub repo. Nothing is written to the hub.
# Under a managed root the hook's PATH is pinned to the system directories, where gh is not, and the member's token is hub-board.sh's to read: that is the path
# that runs there. gh is for a box with no managed root (an admin's, a test's), found on the caller's own PATH.
issue_create() { # <title> <body file>
  if ! { hub_marker 2>/dev/null || [ -e "$HERE/harbor-member-mode" ]; } && command -v gh >/dev/null 2>&1; then
    if has_token; then
      hub_bounded "$TIMEOUT" sh "$(secret_bin)" run hub-token GH_TOKEN -- gh issue create --repo "$HUBREPO" --title "$1" --body-file "$2" >/dev/null 2>&1
    else
      hub_bounded "$TIMEOUT" gh issue create --repo "$HUBREPO" --title "$1" --body-file "$2" >/dev/null 2>&1
    fi
  else
    [ -f "$HERE/hub-board.sh" ] || return 1
    jq -n --arg t "$1" --rawfile b "$2" '{title: $t, body: $b}' > "$W/issue.json" || return 1
    mkdir -p "$W/board" && hub_bounded "$TIMEOUT" sh "$HERE/hub-board.sh" call "$W/board" POST "/repos/$HUBREPO/issues" "$W/issue.json" >/dev/null 2>&1 || return 1
    case "$(cat "$W/board/status" 2>/dev/null)" in 201) return 0 ;; *) return 1 ;; esac
  fi
}
# The commit a proposal names is the repo head last pulled or pushed, kept in $ST/head (data, read only when it is 40 hex), and the tool must still be
# the bytes that were synced then: so no clone is needed to send, and a tool edited since waits for the next push.
head_put() { case "$1" in ''|*[!0123456789abcdef]*) return 0 ;; esac; [ "${#1}" -eq 40 ] || return 0; mkdir -p "$ST" 2>/dev/null && printf '%s\n' "$1" > "$ST/head" 2>/dev/null || :; }
send_proposals() {
  CTL=member.tools-sync
  [ -d "$PROP" ] || return 0
  _head="$(cat "$ST/head" 2>/dev/null)" || _head=''
  case "$_head" in ''|*[!0123456789abcdef]*) return 0 ;; esac
  [ "${#_head}" -eq 40 ] || return 0
  db_clean
  for _q in "$PROP"/*; do
    [ -f "$_q" ] || continue
    _tool="$(sed -n 1p "$_q")"; _note="$(sed -n 2p "$_q" | tr -d '[:cntrl:]' | cut -c1-300)"
    rel_ok "$_tool" || { rm -f "$_q"; continue; }
    _bh="$(base_get "$_tool")"
    [ -n "$_bh" ] && [ -e "$CFG/$_tool" ] && [ "$(item_hash "$CFG" "$_tool")" = "$_bh" ] || continue   # not synced yet: the next push retries
    _c="$_head"
    _done="$ST/proposed/$(slug "$_tool")-$_c"
    if [ -e "$_done" ]; then rm -f "$_q"; continue; fi
    printf 'Personal repo: %s\nTool: %s\nCommit: %s\nProposed by: %s\n' "$PERSONAL" "$_tool" "$_c" "$LOGIN" > "$W/body"
    [ -z "$_note" ] || printf 'Note: %s\n' "$_note" >> "$W/body"
    if issue_create "tool proposal $_tool from $LOGIN" "$W/body"; then
      mkdir -p "$ST/proposed" && : > "$_done" || :
      rm -f "$_q"
      say "opened a hub issue proposing $_tool at ${_c%"${_c#????????????}"}."
    else
      warn "the hub issue for $_tool could not be opened now: it stays queued"
    fi
  done
  return 0
}

# ── push ─────────────────────────────────────────────────────────────────────────────────────────────────
cmd_push() {
  managed_set
  local_set
  # the cheap test first, no network: the carried items against what was last agreed
  : > "$W/base.cur"
  db_clean
  while IFS="$TAB" read -r _r _h; do is_managed "$_r" || printf '%s\t%s\n' "$_r" "$_h"; done < "$W/db.clean" | LC_ALL=C sort > "$W/base.cur"
  LC_ALL=C sort "$W/local" > "$W/local.s"
  _changed=1; cmp -s "$W/local.s" "$W/base.cur" && _changed=0
  if [ "$_changed" -eq 1 ] || [ -d "$PROP" ]; then
    if [ "$_changed" -eq 0 ] && [ -z "$(find "$PROP" -type f 2>/dev/null | head -n 1)" ]; then return 0; fi
    if [ "$_changed" -eq 1 ]; then
      sync_clone || { warn "the personal repo $PERSONAL could not be reached: your tools stay on this laptop, the next turn tries again"; send_proposals; return 0; }
      # local wins: lay the carried items over the remote's, and drop what this laptop removed
      while IFS="$TAB" read -r _r _h; do
        _kind="${_r%%/*}"; mkdir -p "$REPO/$_kind"
        rm -rf "$REPO/$_r"; cp -R "$CFG/$_r" "$REPO/$_r"
      done < "$W/local.s"
      while IFS="$TAB" read -r _r _h; do
        grep -qF "$_r$TAB" "$W/local.s" || rm -rf "$REPO/$_r"
      done < "$W/base.cur"
      git_safe -C "$REPO" add -A >/dev/null 2>&1 || { warn "git could not stage your tools"; return 0; }
      if git_safe -C "$REPO" diff --cached --quiet 2>/dev/null; then
        cp "$W/local.s" "$W/db.new"; db_commit || :; head_put "$REMOTE_HEAD"
      else
        git_id -C "$REPO" commit -q -m "tools: sync from $LOGIN's laptop" >/dev/null 2>&1 || { warn "git could not commit your tools"; return 0; }
        _url="$(remote_url)" || return 0
        if net "$_url" -C "$REPO" push -q "$_url" 'HEAD:refs/heads/main' >/dev/null 2>&1; then
          cp "$W/local.s" "$W/db.new"; db_commit || warn "the sync record could not be written"
          head_put "$(git_safe -C "$REPO" rev-parse HEAD 2>/dev/null)"
          record_status "pushed $(wc -l < "$W/local.s" | tr -d ' ') tool(s)"
          say "saved your tools to $PERSONAL."
        else
          record_status "push failed"
          warn "your tools could not be pushed to $PERSONAL now: they stay on this laptop, the next turn tries again"
          send_proposals; return 0
        fi
      fi
    fi
    send_proposals
  fi
  [ ! -s "$W/skip" ] || say "not carried:$(awk -F'\t' '{ printf "%s%s (%s)", (c++ ? ", " : " "), $1, $2 }' "$W/skip")."
  return 0
}

cmd_status() {
  printf 'personal repo: %s\nconfig dir: %s\nstate: %s\n' "$PERSONAL" "$CFG" "$ST"
  [ -f "$ST/last" ] && printf 'last: %s\n' "$(cut -f2 "$ST/last")" || printf 'last: never\n'
  managed_set; local_set
  printf 'carried: %s\n' "$(wc -l < "$W/local" | tr -d ' ')"
  [ ! -s "$W/skip" ] || awk -F'\t' '{ print "not carried: " $1 " (" $2 ")" }' "$W/skip"
  [ ! -d "$PROP" ] || for _q in "$PROP"/*; do [ -f "$_q" ] && printf 'queued proposal: %s\n' "$(sed -n 1p "$_q")"; done
  return 0
}

case "$VERB" in
  pull) cmd_pull || :; exit 0 ;;
  push) cmd_push || :; exit 0 ;;
  propose) _rc=0; cmd_propose "$@" || _rc=$?; exit "$_rc" ;;
  status) cmd_status; exit 0 ;;
esac
