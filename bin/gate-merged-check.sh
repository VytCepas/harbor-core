#!/usr/bin/env sh
# merged-check (harbor#213) - is this branch's work already in BASE? Judged by CONTENT, not reachability:
# the repo's merge method (squash, merge, rebase) is a setting. Five tests, cheapest first; any one answering
# "merged" suffices (order is cost, not precedence): 1 ancestor, 2 empty diff vs BASE, 3 git cherry all `-`
# (the only test that answers a rebase-merge), 4 total-diff patch-id (N>1 squash), 5 no-op merge (harbor#634).
# FAIL TOWARD "ABSENT": every unknown reports absent, since consumers delete worktrees on `merged`. Tests 3
# and 4 check git's exit status because failure output equals "merged" (harbor#226); the suite forces it.
# Removed notes: docs/explanation/code-cases/bin-gate-merged-check.md
set -eu

usage() {
  cat <<'USAGE'
usage: gate-merged-check.sh <base-ref> <ref>...
       gate-merged-check.sh --repo <dir> <base-ref> <ref>...

Prints one line per ref, in the order given:
  merged <ref>     the ref's content is already in <base-ref>
  absent <ref>     it is not, or the question could not be answered

Exit 0 when every ref was classified, 2 on a usage error or an unusable base.
The verdict is on stdout; exit status is NOT the verdict (a single ref would be
ambiguous with a git failure). The run log (contracts/logging.md) is on stderr.
USAGE
}

# Verdict lines are DATA parsed by worktree.sh, govern-hook.sh and deploy-install-stamp.sh; the run log stays on stderr.
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2
# ${0%/*}, not $(dirname): a hook runs this, and it must not fall back to the session's cwd (harbor#810).
case "$0" in */*) _mc_here="${0%/*}" ;; *) _mc_here=. ;; esac
. "$_mc_here/library-log.sh"
log_init merged-check

REPO="."
case "${1:-}" in
  --repo) [ $# -ge 2 ] || { usage >&2; exit 2; }; REPO="$2"; shift 2 ;;
  -h|--help|'') usage; exit 0 ;;
esac
[ $# -ge 2 ] || { usage >&2; exit 2; }

BASE="$1"; shift

_git() { git -C "$REPO" "$@" 2>/dev/null; }

_git rev-parse --git-dir >/dev/null || {
  log_fail "not a git repository: $REPO"; log_fix "sh $0 --repo <a git checkout> $BASE $*"; log_end || :; exit 2; }
_git rev-parse --verify -q "$BASE^{commit}" >/dev/null || {
  log_fail "base ref not found: $BASE (in $REPO)"; log_fix "git -C $REPO fetch origin  # then name a base that resolves"; log_end || :; exit 2; }
log_head "$BASE against $# ref(s)"

# One verdict: the data line on stdout, then its log line.
_say() { # <merged|absent> <ref>
  printf '%s %s\n' "$1" "$2"
  if [ "$1" = merged ]; then log_ok "merged $2: its content is already in $BASE"
  else log_note "absent $2: its content is not in $BASE, or the question could not be answered"; fi
}

# Patch-id index: built once, lazily (govern-hook.sh runs this over every local branch at SessionStart).
IDX=""
IDX_BUILT=0
IDX_FROM=""

_patch_id() { # reads a diff on stdin
  git patch-id --stable 2>/dev/null | awk '{print $1; exit}'
}

_build_index() { # <since>  — patch-ids of commits BASE gained after <since>
  [ "$IDX_BUILT" = "1" ] && [ "$IDX_FROM" = "$1" ] && return 0
  IDX=""
  for _c in $(_git rev-list "$1..$BASE" || true); do
    _p="$(_git show "$_c" --format= | _patch_id || true)"
    [ -n "$_p" ] && IDX="$IDX $_p"
  done
  IDX_BUILT=1
  IDX_FROM="$1"
}

# TEST 5 (harbor#634): a patch-id hashes context lines, so test 4 cannot see a squash made on a base a sibling
# had already moved. A clean `git merge-tree --write-tree BASE REF` equal to BASE^{tree} asks the content question
# directly; conflict or git older than 2.38 is `absent`. Merged blobs go to a scratch object store (removed on
# exit) so SessionStart leaves no loose objects. Called as `git`, not `_git`: an assignment before a function persists.
SCRATCH=""
ODIR=""
trap 'if [ -n "$SCRATCH" ]; then rm -rf "$SCRATCH"; fi' EXIT

_noop_merge() { # <ref> — true only for a clean merge whose tree is BASE's own
  _bt="$(_git rev-parse --verify -q "$BASE^{tree}")" || return 1
  if [ -z "$SCRATCH" ]; then
    ODIR="$(_git rev-parse --path-format=absolute --git-path objects)" || return 1
    [ -d "$ODIR" ] || return 1
    SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/merged-check.XXXXXX")" || return 1
  fi
  _mt="$(GIT_OBJECT_DIRECTORY="$SCRATCH" GIT_ALTERNATE_OBJECT_DIRECTORIES="$ODIR" \
           git -C "$REPO" merge-tree --write-tree "$BASE" "$1" 2>/dev/null)" || return 1
  [ -n "$_bt" ] && [ "$(printf '%s\n' "$_mt" | sed -n 1p)" = "$_bt" ]
}

for REF in "$@"; do
  # A ref that does not resolve is `absent`: govern-hook lists refs a concurrent session may delete.
  if ! _git rev-parse --verify -q "$REF^{commit}" >/dev/null; then
    _say absent "$REF"; continue
  fi

  # 1 · ancestor — a real merge, or the ref IS base
  if _git merge-base --is-ancestor "$REF" "$BASE"; then
    _say merged "$REF"; continue
  fi

  # 2 · the tree is identical to base
  if _git diff --quiet "$BASE" "$REF" --; then
    _say merged "$REF"; continue
  fi

  MB="$(_git merge-base "$BASE" "$REF" || true)"
  if [ -z "$MB" ]; then
    # Unrelated histories. Nothing to compare, and `absent` is the safe answer.
    _say absent "$REF"; continue
  fi

  # 3 - git cherry: `+` absent, `-` present, empty = merged. Check git's STATUS first (harbor#226): `_git` drops
  # stderr, so a failed cherry looks like a ref adding nothing and would yield the destructive `merged`.
  if _cherry="$(_git cherry "$BASE" "$REF")"; then
    _absent="$(printf '%s\n' "$_cherry" | grep -c '^+' || true)"
    case "$_absent" in
      ''|*[!0-9]*) ;;                                  # unreadable → fall through
      0) _say merged "$REF"; continue ;;
    esac
  fi

  # 4 - SQUASH CASE: total diff as one patch-id against patch-ids base gained since the merge-base. Both statuses
  # are checked (harbor#226): a successful empty diff is `merged`; a failed diff or hash is `absent`.
  if _bd="$(_git diff "$MB..$REF")"; then
    if [ -z "$_bd" ]; then
      _say merged "$REF"; continue
    fi
    _bp="$(printf '%s\n' "$_bd" | _patch_id)"
  else
    _bp=""
  fi
  if [ -z "$_bp" ]; then
    _say absent "$REF"; continue
  fi
  _build_index "$MB"
  case " $IDX " in
    *" $_bp "*) _say merged "$REF"; continue ;;
  esac

  # 5 · THE MERGE IS A NO-OP (harbor#634). Reached only when test 4 said no.
  if _noop_merge "$REF"; then
    _say merged "$REF"
  else
    _say absent "$REF"
  fi
done
log_end; exit $?
