#!/usr/bin/env sh
# worktree.sh — session worktrees: create, retire, collect (CI-4, harbor#150)
#
#   sh worktree.sh list             every worktree, its branch, and its verdict
#   sh worktree.sh new <branch>     a worktree under $PORT_ROOT/.worktrees/<repo>/ on a fresh branch off origin/main
#   sh worktree.sh retire <name>    remove one — refuses dirty, held or unmerged
#   sh worktree.sh gc               remove every clean, unheld, merged worktree
#                                   DRY RUN unless --apply is passed
#
#   --force   on `retire` only: accept an UNMERGED branch. It never accepts a
#             dirty worktree or one a live session is working in.
#
# WHY THIS EXISTS. Several terminals already run against this repo at once, and
# `~/harbor-ci` is a WORKTREE of `~/harbor` rather than a second clone — one
# branch namespace, so a branch checked out in one is unavailable in the other,
# and `git checkout main` in the wrong terminal simply fails. On 2026-08-06 six
# orphaned worktrees from a dead session's scratchpad were pinning six merged
# branches undeletable. `git worktree prune` does NOT clear those while the
# directories still exist; each needed `git worktree remove`.
#
# THE REFUSALS ARE THE FEATURE. A garbage collector that deletes working
# directories is the most dangerous shape in this repo, so the discipline is
# taken wholesale from bin/test-sandbox-make.sh (harbor#143), which deleted a live
# config dir and exited 0 because its gate ran three lines AFTER the delete and
# compared STRINGS: `~/x`, `~/x/`, `~/x/.` and `~/x/../x` are one directory and
# no two are one string. So here every decision is made and printed BEFORE
# anything is removed, and every path comparison is between RESOLVED paths.
#
# Three refusals are unconditional — there is no flag that turns them off:
#
#   dirty     uncommitted or untracked content. The orphans this tool collects
#             come from sessions that DIED, and a session that died mid-edit is
#             exactly the one whose worktree still holds the only copy.
#   held      a live session is working in it. Sourced from context-peers.sh,
#             which already answers "which sessions are alive and which tree
#             does each WRITE to" — reimplementing that here would be a second
#             copy of a fact that lives somewhere else.
#   the main worktree  the repo itself is never a candidate.
#   the base branch    a worktree checked out on $BASE holds no session work, and
#             is_merged cannot say so: a branch is always an ancestor of itself,
#             so "merged into $BASE" is TRUE for $BASE by construction. That is a
#             destructive verdict resting on a test that cannot fail
#             (CONSTITUTION §2.10), and it is harbor#163.
set -eu

ROOT="${HARBOR_SCOPE_ROOT:-${HARBOR_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}}"
DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# THE REPO'S NAME COMES FROM ITS MAIN WORKTREE (harbor#1149), never from $ROOT: run from inside a worktree,
# $ROOT is that worktree and its basename would nest the new tree under .worktrees/<repo>-wt-<x>/.
# `worktree list` prints the main checkout first.
MAIN="$(git -C "$ROOT" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
[ -n "$MAIN" ] || MAIN="$ROOT"
REPO_NAME="$(basename -- "$MAIN")"
BASE="${HARBOR_CI_BASE:-${HARBOR_BASE:-origin/main}}"
APPLY=0; FORCE=0
LOG_FD=2   # stdout is the verdict table and the gc plan; the log goes to stderr
. "$DIR/library-log.sh"
US="$(printf '\037')"

# RESOLVED, NEVER COMPARED AS STRINGS (harbor#143). A path that does not exist
# yet resolves to itself, which is what `new` needs.
_phys() { CDPATH= cd -P -- "$1" 2>/dev/null && pwd -P || printf '%s' "$1"; }

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; }

CMD="${1:-}"
[ $# -gt 0 ] && shift || :
ARG=""
for a in ${@+"$@"}; do
  case "$a" in
    --apply) APPLY=1 ;;
    --force) FORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) printf 'worktree: unknown flag: %s\n' "$a" >&2; exit 2 ;;
    *)  ARG="$a" ;;
  esac
done
case "$CMD" in
  ''|-h|--help) usage; exit 0 ;;
  list|new|retire|gc) ;;
  *) printf 'worktree: unknown command: %s (see --help)\n' "$CMD" >&2; exit 2 ;;
esac

# ── which trees are LIVE SESSIONS working in ────────────────────────────────
# Delegated, not reimplemented: context-peers.sh already filters to live
# sessions (`is_live` compares a pid AND its start time, because a pid alone is
# a recycled-pid false positive) and already reports the tree each session
# WRITES to rather than the directory it was launched from. Both of those were
# measured findings; a second implementation here would drift from them.
#
# IF THAT LIST CANNOT BE OBTAINED, EVERY WORKTREE COUNTS AS HELD. An empty
# answer and "no sessions are running" are indistinguishable from here, and only
# one of them is safe to act on.
HELD_TREES=""
HELD_KNOWN=0
if [ -x "$DIR/context-peers.sh" ] || [ -f "$DIR/context-peers.sh" ]; then
  if _fs="$(sh "$DIR/context-peers.sh" --json 2>/dev/null)" && [ -n "$_fs" ]; then
    # HELD_KNOWN is set ONLY when the extraction itself succeeded. The first cut
    # set it unconditionally with a `|| printf ''` fallback, so a jq that failed
    # — missing, stubbed, or fed malformed JSON — produced an empty tree list
    # that read as "no session holds anything" and made every worktree
    # collectable. An unanswerable question must not resolve to the permissive
    # answer, which is the same rule the empty-changeset case follows in
    # bin/test-suite-select.sh.
    if HELD_TREES="$(printf '%s' "$_fs" \
        | jq -r '(if type=="array" then . else (.sessions // []) end)[]? | .tree // empty' 2>/dev/null)"; then
      HELD_KNOWN=1
    fi
  fi
fi

is_held() { # <resolved worktree path>
  [ "$HELD_KNOWN" -eq 1 ] || return 0        # unknown means held
  [ -n "$HELD_TREES" ] || return 1
  while IFS= read -r _t; do
    [ -n "$_t" ] || continue
    [ "$(_phys "$_t")" = "$1" ] && return 0
  done <<HELD
$HELD_TREES
HELD
  return 1
}

is_dirty() { # <worktree path>
  [ -d "$1" ] || return 1
  [ -n "$(git -C "$1" status --porcelain 2>/dev/null)" ]
}

is_merged() { # <sha>
  # BY CONTENT, NOT ANCESTRY (harbor#213). `merge-base --is-ancestor` is
  # false-negative by construction here: every PR in this repo lands as a squash
  # merge, so a fully merged branch is never an ancestor of $BASE. Measured
  # 2026-08-13: `retire selfheal-route-and-judge` was refused as unmerged while
  # `git diff origin/main 59c44ea` was EMPTY — the tree was identical to main.
  # Clearing it needed `--force`, the flag documented as "accept an UNMERGED
  # branch", for a branch that was merged. A gate whose documented bypass is the
  # normal path is a gate that has stopped meaning anything (§2.11).
  #
  # gate-merged-check.sh is a sibling script rather than an inlined predicate because
  # govern-hook.sh and deploy-install-stamp.sh ask the same question, and three copies of
  # it is the defect harbor#213 describes one level up. It fails toward `absent`,
  # which keeps the conservative direction: refusing to retire costs a `--force`,
  # retiring wrongly destroys uncommitted work.
  git -C "$ROOT" rev-parse --verify -q "$BASE" >/dev/null 2>&1 || return 1
  [ -f "$DIR/gate-merged-check.sh" ] || return 1
  [ "$(sh "$DIR/gate-merged-check.sh" --repo "$ROOT" "$BASE" "$1" 2>/dev/null | awk '{print $1; exit}')" = "merged" ]
}

# ── the worktree table ──────────────────────────────────────────────────────
# `--porcelain` rather than the human table: the human one aligns columns and
# has no stable field boundary, and a path with a space in it would be parsed
# into two fields by anything that splits on whitespace.
_rows() {
  git -C "$ROOT" worktree list --porcelain 2>/dev/null | awk -v US="$US" '
    /^worktree /  { if (p != "") print p US s US b; p = substr($0, 10); s = ""; b = "" }
    /^HEAD /      { s = substr($0, 6) }
    /^branch /    { b = substr($0, 8); sub(/^refs\/heads\//, "", b) }
    /^detached$/  { b = "(detached)" }
    END           { if (p != "") print p US s US b }'
}

# The MAIN worktree carries a .git DIRECTORY; a linked one carries a .git file
# pointing at the common dir. That is a property of the thing itself rather than
# of its position in a list, so it cannot be wrong for a repo laid out unusually.
# A removed tree under .worktrees/<repo>/ leaves that directory behind; rmdir takes it only when empty.
drop_empty_parent() { # <removed worktree path>
  case "$1" in */.worktrees/*/*) rmdir -- "$(dirname -- "$1")" 2>/dev/null || : ;; esac
}
is_main() { [ -d "$1/.git" ]; }

verdict() { # <path> <sha> <branch> -> sets V and WHY
  V=SKIP
  if is_main "$1";        then WHY="the main worktree";                 return; fi
  if [ ! -d "$1" ];       then V=PRUNE; WHY="directory is gone — prunable"; return; fi
  # THE BASE BRANCH, AND is_merged CANNOT REFUSE IT. A branch is an ancestor of
  # itself, so the merged test below is TRUE for $BASE by construction and every
  # worktree checked out on it reads as collected work. harbor#163: `gc` marked
  # the repo's second working copy COLLECT for exactly that reason and `--apply`
  # removed the directory.
  #
  # ORDERED DELIBERATELY. After the missing-directory test, because an orphaned
  # RECORD is still prunable whatever branch it named — the record is not anyone's
  # work. Before the liveness and dirty tests, because this needs no git call and
  # no fleet-sessions round trip, and because "it is the base branch" is the more
  # fundamental reason to keep it than "someone is using it right now".
  #
  # ${BASE#*/} strips ONLY the remote segment: origin/main -> main, and
  # origin/release/2 -> release/2. When HARBOR_CI_BASE names a local branch carrying
  # no slash the expansion is a no-op, which is what the second pattern is for.
  case "$3" in "${BASE#*/}"|"$BASE")
    WHY="$3 is the base branch — never session work"; return ;;
  esac
  if is_held "$1";        then WHY="a live session is working here";    return; fi
  if is_dirty "$1";       then WHY="uncommitted or untracked changes";  return; fi
  case "$3" in '(detached)'|'') WHY="detached HEAD — no branch to judge"; return ;; esac
  if ! is_merged "$2";    then WHY="$3 is not merged into $BASE";       return; fi
  V=COLLECT; WHY="clean, unheld, and merged into $BASE"
}

case "$CMD" in

  list)
    printf '%-8s %-34s %-26s %s\n' VERDICT PATH BRANCH WHY
    while IFS="$US" read -r _p _s _b; do
      [ -n "$_p" ] || continue
      _r="$(_phys "$_p")"
      verdict "$_r" "$_s" "$_b"
      printf '%-8s %-34s %-26s %s\n' "$V" "$_p" "${_b:--}" "$WHY"
    done <<ROWS
$(_rows)
ROWS
    [ "$HELD_KNOWN" -eq 1 ] \
      || log_note "the live-session list was unavailable, so every worktree reads as held"
    ;;

  new)
    [ -n "$ARG" ] || { echo "worktree: new needs a branch name" >&2; exit 2; }
    # A branch name reaches the filesystem as a directory name, so it is
    # validated rather than trusted: no leading dash, no `..`, no absolute path.
    case "$ARG" in
      -*|*..*|/*|*' '*) echo "worktree: refusing branch name: $ARG" >&2; exit 2 ;;
      *[!a-zA-Z0-9._/-]*) echo "worktree: branch name has characters outside [A-Za-z0-9._/-]: $ARG" >&2; exit 2 ;;
    esac
    git -C "$ROOT" rev-parse --verify -q "$BASE" >/dev/null 2>&1 \
      || { printf 'worktree: %s does not exist here — fetch first\n' "$BASE" >&2; exit 1; }
    git -C "$ROOT" rev-parse --verify -q "refs/heads/$ARG" >/dev/null 2>&1 \
      && { printf 'worktree: branch already exists: %s\n' "$ARG" >&2; exit 1; }
    _slug="$(printf '%s' "$ARG" | tr '/' '-')"
    # harbor#1149: worktrees live under $PORT_ROOT/.worktrees/<repo>/; the sibling `<repo>-wt-*` layout is legacy.
    _pw="$(HARBOR_SCOPE_ROOT= HARBOR_ROOT= sh "$DIR/scope-roots.sh" --port-root)" || { echo "worktree: cannot resolve PORT_ROOT" >&2; exit 1; }
    _dest="${_pw%/}/.worktrees/$REPO_NAME/$_slug"
    mkdir -p -- "$(dirname -- "$_dest")"
    [ -e "$_dest" ] && { printf 'worktree: already exists: %s\n' "$_dest" >&2; exit 1; }
    git -C "$ROOT" worktree add -b "$ARG" "$_dest" "$BASE"
    # BORN WITH THE MEMORY STORE (harbor#589). The store is keyed by the session's cwd, so a fresh
    # worktree starts blind. The repo's own routing, memory-route.sh --apply, discovers the new tree
    # through `git worktree list`: one mechanism, not a second linker here. --live only when the
    # config dir IS the live one, because that write gate demands it spelled out.
    LIVE_DIR="$HOME/.claude"
    _cfg="${CLAUDE_CONFIG_DIR:-$LIVE_DIR}"
    if [ "$(_phys "$_cfg")" = "$(_phys "$LIVE_DIR")" ]; then _tgt="--live"; else _tgt="--dir"; fi
    _rc=0
    if [ "$_tgt" = "--live" ]; then sh "$DIR/memory-route.sh" --live --apply --quiet >/dev/null 2>&1 || _rc=$?
    else sh "$DIR/memory-route.sh" --dir "$_cfg" --apply --quiet >/dev/null 2>&1 || _rc=$?; fi
    if [ "$_rc" -eq 0 ]; then log_ok "memory store linked for the new worktree"
    else
      log_warn "memory route not complete (memory-route exit $_rc) — a session there may start with no memory"
      log_fix "sh $DIR/memory-route.sh $_tgt $([ "$_tgt" = "--dir" ] && printf '%s ' "$_cfg")--apply"
    fi
    printf '\nworktree ready: %s\n  branch: %s (off %s)\n  retire: sh bin/worktree.sh retire %s\n' \
      "$_dest" "$ARG" "$BASE" "$_slug"
    log_end
    ;;

  retire)
    [ -n "$ARG" ] || { echo "worktree: retire needs a worktree name or path" >&2; exit 2; }
    # Accept either the directory name or a full path, and resolve BOTH sides
    # before comparing — the whole point of harbor#143.
    _want="$ARG"
    # A bare name is tried in both layouts (harbor#1149): the new one first, then the legacy sibling.
    case "$_want" in
      */*) ;;
      *) _pw="$(HARBOR_SCOPE_ROOT= HARBOR_ROOT= sh "$DIR/scope-roots.sh" --port-root 2>/dev/null || :)"
         _want="${_pw%/}/.worktrees/$REPO_NAME/$ARG"
         [ -d "$_want" ] || _want="$(dirname -- "$MAIN")/$REPO_NAME-wt-$ARG" ;;
    esac
    _want="$(_phys "$_want")"
    _hit=""
    while IFS="$US" read -r _p _s _b; do
      [ -n "$_p" ] || continue
      [ "$(_phys "$_p")" = "$_want" ] && _hit="$_p$US$_s$US$_b"
    done <<ROWS
$(_rows)
ROWS
    [ -n "$_hit" ] || { printf 'worktree: not a worktree of this repo: %s\n' "$_want" >&2; exit 1; }
    _p="${_hit%%"$US"*}"; _rest="${_hit#*"$US"}"; _s="${_rest%%"$US"*}"; _b="${_rest#*"$US"}"
    verdict "$_want" "$_s" "$_b"
    case "$V" in
      COLLECT|PRUNE) ;;
      *)
        # --force covers exactly one of these, and the message says which.
        case "$WHY" in
          *"not merged"*)
            [ "$FORCE" -eq 1 ] || { printf 'worktree: refusing — %s (pass --force to accept)\n' "$WHY" >&2; exit 1; } ;;
          *)
            printf 'worktree: refusing — %s\n' "$WHY" >&2
            echo "  no flag overrides this; use git directly if you mean it" >&2
            exit 1 ;;
        esac ;;
    esac
    printf 'removing %s (%s)\n' "$_p" "$WHY"
    git -C "$ROOT" worktree remove "$_p" 2>/dev/null || git -C "$ROOT" worktree prune
    drop_empty_parent "$_p"
    ;;

  gc)
    # DRY RUN BY DEFAULT. The decision is printed in full before anything is
    # removed, which is the ordering harbor#143 got wrong.
    _n=0
    while IFS="$US" read -r _p _s _b; do
      [ -n "$_p" ] || continue
      _r="$(_phys "$_p")"
      verdict "$_r" "$_s" "$_b"
      case "$V" in
        COLLECT|PRUNE)
          _n=$((_n + 1))
          if [ "$APPLY" -eq 1 ]; then
            printf 'removing  %s (%s)\n' "$_p" "$WHY"
            git -C "$ROOT" worktree remove "$_p" 2>/dev/null || :
            drop_empty_parent "$_p"
          else
            printf 'would remove  %s (%s)\n' "$_p" "$WHY"
          fi ;;
        *) printf 'keeping       %s (%s)\n' "$_p" "$WHY" ;;
      esac
    done <<ROWS
$(_rows)
ROWS
    if [ "$APPLY" -eq 1 ]; then
      # Only after the removals, and only ever for entries whose directory is
      # already gone: prune deletes ADMIN records, never working directories.
      git -C "$ROOT" worktree prune
      printf '\ncollected: %d\n' "$_n"
    else
      printf '\ncollectable: %d (dry run — pass --apply)\n' "$_n"
    fi
    [ "$HELD_KNOWN" -eq 1 ] \
      || log_note "the live-session list was unavailable, so nothing was collectable"
    ;;
esac
