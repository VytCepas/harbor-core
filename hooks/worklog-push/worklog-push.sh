#!/usr/bin/env sh
# G2 (harbor#26) — Stop hook: append a host-partitioned session record, then
# allowlist-stage → gitleaks gate (fail-CLOSED on findings OR missing scanner)
# → commit → push (fail-open on NETWORK only: the commit stays local and the
# next Stop retries the push). Stands down only on the repo's `worklog: off`. NEVER
# blocks the session: every path exits 0. Staging is a tracked-glob allowlist
# — git add -A is deliberately absent (G1).

# CLAUDE_CONFIG_DIR-aware: a sandbox session resolves to a MEMORY with no .git, so the hook stands down instead of touching live.
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
WORKLOG_DIR="${HARBOR_MEMORY_LOG_DIR:-$CFG/MEMORY}"
TOKEN_FILE="${HARBOR_MEMORY_LOG_TOKEN_FILE:-$CFG/.helm-log-token}"

# One marker implementation (H2, contracts/marker.md): the hook's own `.agents` walk accepted a zero-byte file or symlink and started from the process $PWD, so a planted file silently stopped work-log sync. Stdin is read FIRST because the shared resolver reads .cwd from it.
# Removed notes: docs/explanation/code-cases/hooks-worklog-push-worklog-push.md
# harbor#813: no dirname fork. A failed or unresolvable $(dirname) left DIR at the cwd, sourcing ./library-admission.sh from it.
case "$0" in */*) DIR="${0%/*}" ;; *) DIR=. ;; esac
[ ! -f "$DIR/manifest.tsv" ] || DIR="$DIR/../../bin"  # D-88: in the repo an engine sits beside its manifest in hooks/<engine>/; deployed, flat beside its libraries
. "$DIR/library-admission.sh"
# A Stop hook's stdout is the harness's, so its log goes to stderr (contracts/logging.md). Every
# path still exits 0: a blocked commit is a WARN with its fix, never a blocked session.
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2; . "$DIR/library-log.sh"
floor_read_stdin
floor_engine_stand_down && exit 0

[ -d "$WORKLOG_DIR/.git" ] || exit 0

SID="$(floor_field '.session_id')"
CWD="$(floor_field '.cwd')"
HOST="$(floor_host_token)"
DATE="$(date +%Y-%m-%d)"
[ -n "$SID" ] || SID="unknown-$(date +%H%M%S)"
# The format lives in floor_worklog_record (library-admission.sh), shared with memory-harvest.sh: two open-coded writers of one format drift silently.
floor_worklog_record "$WORKLOG_DIR" "$HOST" "$SID" "$DATE" "$(date +%H:%M)" "${CWD:-unknown}" || true

cd "$WORKLOG_DIR" || exit 0

# One session at a time stages, commits and pushes: concurrent Stops raced on the remote ref (harbor#559: 50 of 54
# push failures were `cannot lock ref`). A skipped session loses nothing: its record is on disk and the next push
# carries every local commit. A lock left by a killed hook is reclaimed after 10 minutes.
_wl_lock="$WORKLOG_DIR/.git/harbor-worklog.lock"
[ -z "$(find "$WORKLOG_DIR/.git" -maxdepth 1 -name harbor-worklog.lock -mmin +10 2>/dev/null)" ] || rmdir "$_wl_lock" 2>/dev/null
mkdir "$_wl_lock" 2>/dev/null || exit 0
trap 'rmdir "$_wl_lock" 2>/dev/null' EXIT

# Tracked-glob allowlist, deny-by-default; one add per glob because git aborts a multi-pathspec add if ANY pathspec is empty.
for g in 'WORK/sessions/*/*.md' 'KNOWLEDGE/*.md' 'LEARNING/*.md' 'CHECKPOINTS/*/*' \
         'WISDOM/*.md' IDEAS.md README.md .gitignore; do
  git add -- "$g" >/dev/null 2>&1 || true
done

git diff --cached --quiet 2>/dev/null && exit 0   # nothing new

if ! command -v gitleaks >/dev/null 2>&1; then
  git reset -q
  log_warn "gitleaks is missing, so the work-log commit and push are BLOCKED (fail-closed): $WORKLOG_DIR"
  log_fix "$(pkg_hint gitleaks)"; log_end || :
  exit 0
fi
# floor_gitleaks_staged, not a literal subcommand: 8.18.4 (CI's pin) has no `gitleaks git`, and its exit 1 read as a finding. Non-zero still blocks (fail-closed).
if ! floor_gitleaks_staged "$WORKLOG_DIR" >/dev/null 2>&1; then
  git reset -q
  log_warn "gitleaks found a secret in the staged work-log, so its commit and push are BLOCKED (fail-closed): inspect $WORKLOG_DIR"
  log_nofix "harbor#26 — remove it from $WORKLOG_DIR; the next Stop retries"; log_end || :
  exit 0
fi

# harbor#1191: with no identity at all, retry once as a per-command fallback (never written to git config);
# any other failure is a FAIL with git's reason. The exit stays 0, so the session is never blocked.
_wl_rc=0
_wl_cerr="$(git commit -q -m "log: $HOST $DATE" 2>&1)" || _wl_rc=$?
_wl_fb=""
if [ "$_wl_rc" -ne 0 ] && { ! git var GIT_AUTHOR_IDENT >/dev/null 2>&1 || ! git var GIT_COMMITTER_IDENT >/dev/null 2>&1; }; then
  _wl_hn="$(floor_host_token)"; [ -n "$_wl_hn" ] || _wl_hn=box
  _wl_fb="harbor@$_wl_hn.local"; _wl_rc=0
  _wl_cerr="$(git -c user.name=harbor -c user.email="$_wl_fb" commit -q -m "log: $HOST $DATE" 2>&1)" || _wl_rc=$?
fi
if [ "$_wl_rc" -ne 0 ]; then
  git reset -q
  _wl_why="$(printf '%s\n' "$_wl_cerr" | awk 'NF' | tail -1)"
  log_fail "commit FAILED — the work log is not committed or pushed; the next Stop retries. git: $_wl_why"
  log_nofix "harbor#1191 — the git error above says why"; log_end || :
  exit 0
fi
if [ -n "$_wl_fb" ]; then
  log_warn "no git identity: committed as $_wl_fb (fallback, per command; git config untouched)"
  log_fix "git -C \"$WORKLOG_DIR\" config user.name '<name>' && git -C \"$WORKLOG_DIR\" config user.email '<email>'"; log_end || :
fi

# Push - network failures are the ONLY fail-open leg. The token is the store's `worklog-token` only (harbor#1205); a leftover plaintext file is named, never read. Each state warns once.
wl_warn_once() {
  _wl_st="$CFG/.worklog-token-warned.$1"
  [ -e "$_wl_st" ] && return 0
  : > "$_wl_st" 2>/dev/null || :
  log_warn "$2"; log_fix "$3"; log_end || :
}
_wl_secret="${HARBOR_ACCESS_SECRET_BIN:-${HARBOR_SECRET_BIN:-$(command -v secret 2>/dev/null || true)}}"; [ -n "$_wl_secret" ] || _wl_secret="$HOME/.local/bin/secret"
if [ -f "$_wl_secret" ] && sh "$_wl_secret" run worklog-token WORKLOG_TOKEN -- true >/dev/null 2>&1; then
  rm -f "$CFG/.worklog-token-warned.legacy" "$CFG/.worklog-token-warned.missing" 2>/dev/null || :
elif [ -f "$TOKEN_FILE" ]; then
  wl_warn_once legacy "the work-log token is still the plaintext $TOKEN_FILE, which is no longer read, so the work log is committed here and never pushed (harbor#1205)" \
    "sh $_wl_secret adopt $TOKEN_FILE worklog-token   # stores it, proves the copy by sha256, removes the file"
  exit 0
else
  wl_warn_once missing "no worklog-token in the store, so the work log is committed here and never pushed (harbor#1205)" \
    "copy the token on GitHub, then: sh $DIR/memory-log-token-save.sh"
  exit 0
fi

# The token goes through the environment, never the URL (CONSTITUTION 4): the helper string shows in `ps`, the token does not, and git's error can no longer contain it.
# Push to `origin`, not a URL: an explicit URL never advances origin/main, so `git status` showed a growing [ahead N] while every push succeeded.
_wl_helper='!f(){ test "$1" = get && printf "username=x-access-token\npassword=%s\n" "$WORKLOG_TOKEN"; }; f'  # secret-seam: entry worklog-token, injected by secret run
_wl_err="$(sh "$_wl_secret" run worklog-token WORKLOG_TOKEN -- git -c credential.helper="$_wl_helper" push --quiet origin main 2>&1)"
_wl_rc=$?

# Fail open on NETWORK only: the old `>/dev/null 2>&1 || true` hid rejected credentials and non-fast-forwards. The commit stays local either way; the operator must learn the log stopped leaving the machine.
if [ "$_wl_rc" -ne 0 ]; then
  case "$_wl_err" in
    *'Could not resolve host'*|*'unable to access'*|*'Connection refused'* \
    |*'Operation timed out'*|*'etwork is unreachable'*|*'Connection reset'*)
      : ;;   # offline — silent by design, retried next Stop
    *)
      # The pre-push gitleaks scan prints its INF lines first; git's reason is last (harbor#324).
      _wl_why="$(printf '%s\n' "$_wl_err" | awk '$2 != "INF"' | tail -3 | tr '\n' ' ')"
      [ -n "$_wl_why" ] || _wl_why="$(printf '%s\n' "$_wl_err" | tail -1)"
      log_warn "push FAILED — the commit is local and NOT lost; next Stop retries. git: $_wl_why"
      log_nofix "harbor#324 — the git error above says why"; log_end || : ;;
  esac
fi
exit 0
