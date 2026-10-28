#!/usr/bin/env sh
# G2 (harbor#26) — Stop hook: append a host-partitioned session record, then
# allowlist-stage → gitleaks gate (fail-CLOSED on findings OR missing scanner)
# → commit → push (fail-open on NETWORK only: the commit stays local and the
# next Stop retries the push). Stands down only on the repo's `worklog: off`. NEVER
# blocks the session: every path exits 0. Staging is a tracked-glob allowlist
# — git add -A is deliberately absent (G1).

# CLAUDE_CONFIG_DIR-aware: in a sandbox session this resolves to the sandbox,
# whose MEMORY has no .git — the hook stands down instead of touching live.
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
WORKLOG_DIR="${HARBOR_LOG_DIR:-$CFG/MEMORY}"
TOKEN_FILE="${HARBOR_LOG_TOKEN_FILE:-$CFG/.helm-log-token}"

# ONE marker implementation, not three (H2, CONTRACTS/marker.md). This hook used
# to walk the tree itself with `[ -e "$d/.agents" ]` — the exact predicate
# floor_in_repo was hardened away from after the 2026-07-24 marker-forgery
# finding, because it accepts a zero-byte FILE or a symlink to anywhere. Verified
# still forgeable here before the change: a planted `.agents` file made this hook
# stand down, i.e. silently stopped work-log sync, while the guards refused the
# same forgery. It also walked from the hook process's own $PWD instead of the
# session cwd the payload carries.
#
# Stdin is read FIRST now, because the shared resolver reads .cwd from it.
# harbor#813: no dirname fork. A failed or unresolvable $(dirname) left DIR at the cwd, sourcing ./guard-lib.sh from it.
case "$0" in */*) DIR="${0%/*}" ;; *) DIR=. ;; esac
[ ! -f "$DIR/manifest.tsv" ] || DIR="$DIR/../../bin"  # D-88: in the repo an engine sits beside its manifest in hooks/<engine>/; deployed, flat beside its libraries
. "$DIR/guard-lib.sh"
# A Stop hook's stdout is the harness's, so its log goes to stderr (CONTRACTS/logging.md). Every
# path still exits 0: a blocked commit is a WARN with its fix, never a blocked session.
LOG_FD=2; . "$DIR/log-lib.sh"
floor_read_stdin
IN="${FLOOR_IN:-}"
# Stands down only where the repo's .agents/config.yaml says `worklog: off` (harbor#954).
floor_engine_stand_down && exit 0

[ -d "$WORKLOG_DIR/.git" ] || exit 0

# Session record — append-only, write-once path per host (memory-format contract).
SID="$(floor_field '.session_id')"
CWD="$(floor_field '.cwd')"
HOST="$(floor_host_token)"
DATE="$(date +%Y-%m-%d)"
[ -n "$SID" ] || SID="unknown-$(date +%H%M%S)"
# The format lives in floor_worklog_record (guard-lib.sh), not here. It used to
# be open-coded, and harbor#6 added a SECOND writer — memory-harvest.sh, which
# backfills a record for a session that never reached this hook. Two open-coded
# writers of one format drift silently: both keep producing files, they just stop
# being the same shape.
floor_worklog_record "$WORKLOG_DIR" "$HOST" "$SID" "$DATE" "$(date +%H:%M)" "${CWD:-unknown}" || true

cd "$WORKLOG_DIR" || exit 0

# One session at a time stages, commits and pushes: concurrent Stops raced on the
# remote ref (50 of 54 push failures, `cannot lock ref`). A skipped session loses
# nothing — its record is on disk and the next push carries every local commit.
# A lock left by a killed hook is reclaimed after 10 minutes.
_wl_lock="$WORKLOG_DIR/.git/harbor-worklog.lock"
[ -z "$(find "$WORKLOG_DIR/.git" -maxdepth 1 -name harbor-worklog.lock -mmin +10 2>/dev/null)" ] || rmdir "$_wl_lock" 2>/dev/null
mkdir "$_wl_lock" 2>/dev/null || exit 0
trap 'rmdir "$_wl_lock" 2>/dev/null' EXIT

# Tracked-glob allowlist (deny-by-default; never git add -A). One add per
# glob: git aborts a multi-pathspec add wholesale if ANY pathspec is empty.
for g in 'WORK/sessions/*/*.md' 'KNOWLEDGE/*.md' 'LEARNING/*.md' 'CHECKPOINTS/*/*' \
         'WISDOM/*.md' IDEAS.md README.md .gitignore; do
  git add -- "$g" >/dev/null 2>&1 || true
done

git diff --cached --quiet 2>/dev/null && exit 0   # nothing new

# Fail-CLOSED secret gate on the staged snapshot.
if ! command -v gitleaks >/dev/null 2>&1; then
  git reset -q
  log_warn "gitleaks is missing, so the work-log commit and push are BLOCKED (fail-closed): $WORKLOG_DIR"
  log_fix "$(pkg_hint gitleaks)"; log_end || :
  exit 0
fi
# floor_gitleaks_staged, not a literal subcommand: 8.18.4 has no `gitleaks git`
# and exits 1 on it, which `--exit-code 1` makes indistinguishable from a finding
# — so this gate refused every commit on a box carrying the version CI itself
# pins, while reporting a secret. See guard-lib.sh for the probe and the measured
# equivalence. The fail-closed posture below is unchanged: non-zero still blocks.
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

# Push — network failures are the ONLY fail-open leg (commit stays local).
# The token is the store's `worklog-token` (harbor#1205); the plaintext file is read only until it moves.
# Each state warns once (a stamp per state), so a token that is gone is said, never silently unpushed.
wl_warn_once() {
  _wl_st="$CFG/.worklog-token-warned.$1"
  [ -e "$_wl_st" ] && return 0
  : > "$_wl_st" 2>/dev/null || :
  log_warn "$2"; log_fix "$3"; log_end || :
}
_wl_secret="${HARBOR_SECRET_BIN:-$(command -v secret 2>/dev/null || true)}"; [ -n "$_wl_secret" ] || _wl_secret="$HOME/.local/bin/secret"
_wl_via=""
if [ -f "$_wl_secret" ] && sh "$_wl_secret" run worklog-token WORKLOG_TOKEN -- true >/dev/null 2>&1; then
  _wl_via=store; rm -f "$CFG/.worklog-token-warned.legacy" "$CFG/.worklog-token-warned.missing" 2>/dev/null || :
elif [ -f "$TOKEN_FILE" ]; then
  wl_warn_once legacy "the work-log token is still the plaintext $TOKEN_FILE, not the store (harbor#1205)" \
    "copy the token on GitHub, then: sh $DIR/save-log-token.sh   # stores it and removes the file"
  WORKLOG_TOKEN="$(cat "$TOKEN_FILE" 2>/dev/null)" || exit 0
  [ -n "$WORKLOG_TOKEN" ] || exit 0
  export WORKLOG_TOKEN
else
  wl_warn_once missing "no worklog-token in the store, so the work log is committed here and never pushed (harbor#1205)" \
    "copy the token on GitHub, then: sh $DIR/save-log-token.sh"
  exit 0
fi

# THE TOKEN GOES THROUGH THE ENVIRONMENT, NEVER THE URL. CONSTITUTION §4 states
# this as a bare imperative — "Never put auth tokens in URLs. Authorization:
# header only — URLs leak into logs, shell history, and referrers" — and this
# hook, which runs on every Stop, was the thing breaking it. A URL-embedded
# credential reaches the reflog, `ps`, and any proxy in front of the remote.
# The credential helper receives it from the environment instead: the helper
# STRING is visible in `ps`, the token is not. It also means a failure message
# from git can no longer contain the credential, which is why the error is now
# safe to print.
#
# PUSH TO `origin`, NOT TO A URL. Pushing to an explicit URL never advances
# origin/main, so `git status` in the work-log reported a monotonically growing
# [ahead N] while every push was succeeding — measured at 11 with local HEAD and
# the remote ref at the IDENTICAL sha. A status signal that is always wrong is
# one nobody reads, and this one hid the only question worth asking of a
# sync hook: is the log actually leaving this machine?
_wl_helper='!f(){ test "$1" = get && printf "username=x-access-token\npassword=%s\n" "$WORKLOG_TOKEN"; }; f'  # secret-seam: entry worklog-token, injected by secret run
if [ "$_wl_via" = store ]; then
  _wl_err="$(sh "$_wl_secret" run worklog-token WORKLOG_TOKEN -- git -c credential.helper="$_wl_helper" push --quiet origin main 2>&1)"
else
  _wl_err="$(git -c credential.helper="$_wl_helper" push --quiet origin main 2>&1)"
fi
_wl_rc=$?
unset WORKLOG_TOKEN

# FAIL OPEN ON NETWORK ONLY, which is what the header has always claimed. The
# old `>/dev/null 2>&1 || true` made a rejected credential, a non-fast-forward,
# a deleted remote and a clean success indistinguishable — so the stated
# contract and the implemented one were different documents. The commit is
# local either way and the next Stop retries; what changes is whether the
# operator ever learns the log stopped leaving the machine.
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
