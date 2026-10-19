#!/usr/bin/env sh
# install-stamp.sh — refuse a deploy that would REMOVE installed work (harbor#115)
#
#   sh install-stamp.sh --check <config-dir> <installer>   0 = safe, 1 = regression
#   sh install-stamp.sh --write <config-dir> <installer> [--live]
#   sh install-stamp.sh --show  <config-dir>
#
# WHAT HAPPENED. On 2026-08-04 a deploy was run from a `main` checkout before the
# PR had merged. `git pull` said "Already up to date" — correctly — and both
# installers then wrote OLDER guards over newer ones, silently removing four
# security fixes that were already live. `floor-verify` still reported FLOOR IS
# ON, because every check it makes was still true: the guards were present,
# wired, and blocking. They were simply the previous versions.
#
# Nothing compared the SOURCE against what was already installed. The dry run
# printed `~ guard-lib.sh (replace)` in both directions, so the one moment an
# operator could have caught it told them nothing.
#
# THE QUESTION IS NOT "IS THE SOURCE OLDER", IT IS "WOULD THIS REMOVE WORK".
# Those differ, and only the second one is safe to gate on. A strict
# ancestor check catches the 2026-08-04 shape (main strictly behind the branch)
# and MISSES the commoner one: installing from a feature branch that never
# received a fix `main` has. Both are the same loss. So the test is
#
#   git rev-list --count <current>..<stamped>
#
# — commits reachable from what is INSTALLED but not from what is about to be
# installed. Non-zero means this deploy removes them, whatever the topology, and
# the refusal names them.
#
# WHY A STAMP AND NOT A CONTENT COMPARE. #115 lists three candidate fixes and
# calls this one "the only one that answers reliably". A content compare cannot
# tell an intentional edit from a regression, and mtimes on a `cp -R` are whatever
# the copy left behind. What was deployed is a fact, so it is recorded as one.
set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO="$(CDPATH= cd -- "$SRC/.." && pwd)"
. "$SRC/log-lib.sh"
. "$SRC/install-lib.sh"
log_init install-stamp
usage() { sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; }
LIVE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STAMP_NAME=".helm-install-stamp"

MODE=""; DIR=""; WHO=""; LIVE_OK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check|--write|--show) MODE="$1" ;;
    --live) LIVE_OK=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) printf 'install-stamp: unknown flag: %s\n' "$1" >&2; exit 2 ;;
    *) if [ -z "$DIR" ]; then DIR="$1"; else WHO="$1"; fi ;;
  esac
  shift
done
[ -n "$MODE" ] || { usage; exit 0; }
[ -n "$DIR" ]  || { echo "install-stamp: needs a config dir" >&2; exit 2; }

_phys() { CDPATH= cd -P -- "$1" 2>/dev/null && pwd -P || printf '%s' "$1"; }
STAMP="$DIR/$STAMP_NAME"
_short() { printf '%s' "$1" | cut -c1-8; }
_q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }         # always quoted
_qn() { case "$1" in *[!A-Za-z0-9_./:=@%+,-]*|'') _q "$1" ;; *) printf '%s' "$1" ;; esac; }  # when needed
# How the installers spell this dir back (the install standard): --live for $HOME/.claude, else --dir.
LIVE="$HOME/.claude"
_target_spelling() {
  if [ "$(_phys "$DIR")" = "$(_phys "$LIVE")" ]; then printf '%s' --live; else printf '%s %s' --dir "$(_q "$(_phys "$DIR")")"; fi
}

# ── the recorded state ──────────────────────────────────────────────────────
_stamped() { # <installer> -> sha, or empty
  [ -f "$STAMP" ] || return 0
  awk -v k="$1" '$1 == k { print $2; exit }' "$STAMP" 2>/dev/null || :
}

_git() { git -C "$REPO" "$@" 2>/dev/null; }

case "$MODE" in

  --show)  # data, not a run: the stamp file itself
    if [ -f "$STAMP" ]; then cat "$STAMP"; else printf 'no stamp at %s\n' "$STAMP"; fi
    exit 0
    ;;

  --check)
    [ -n "$WHO" ] || { echo "install-stamp: --check needs an installer name" >&2; exit 2; }
    _cur="$(_git rev-parse HEAD || printf '')"
    # NOT A GIT CHECKOUT. Nothing to compare, and refusing here would break an
    # install from an exported tree — a gate that fires on a legitimate case is
    # one that gets removed (CONSTITUTION §2.11).
    [ -n "$_cur" ] || { log_skip "$WHO: $REPO is not a git checkout — cannot compare, proceeding"; log_end; exit $?; }
    _old="$(_stamped "$WHO")"
    # THE INSTALL MANIFEST'S COMMITS JOIN THE STAMP'S (install standard §3): every commit a row of this
    # installer records must pass too. The stamp is integrity-protected (CONTRACTS/helm-state.md) and the
    # manifest is not, so a manifest row can only ADD a refusal, never clear the stamp's.
    _mfc="$(il_mf_rows "$DIR" | awk -F'\t' -v w="$WHO" -v s="$_old" \
      '$3 == w && $4 ~ /^[0-9a-f]+$/ && length($4) >= 40 && $4 != s && !seen[$4]++ { print $4 }')"
    # FIRST INSTALL. A fresh box has no stamp and must not be blocked; this is
    # the deliberate asymmetry against the "unknown refuses" rule used elsewhere
    # in this repo. Unknown-means-refuse is right when the unknown state is
    # dangerous; here the unknown state is a new machine.
    if [ -z "$_old" ] && [ -z "$_mfc" ]; then log_ok "$WHO: no previous stamp in $DIR — first install"; log_end; exit $?; fi
    # One commit's verdict: 0 nothing lost, 1 a loss (a FAIL, with its fix). <where> is empty for the
    # stamp, whose lines are the contract deploy reads, and names the manifest for a row's commit.
    _judge() { # <installed-commit> <where>
      _jo="$1"; _jw="$2"
      if [ "$_jo" = "$_cur" ]; then [ -n "$_jw" ] || log_ok "$WHO: already at $(_short "$_cur") in $DIR"; return 0; fi
      # The stamped commit is not in THIS repository — a different clone, or a
      # branch since deleted. Disclose; do not guess.
      if ! _git cat-file -e "$_jo^{commit}"; then
        log_warn "$WHO: installed from $(_short "$_jo")$_jw, which $REPO does not contain — cannot tell whether this deploy moves forward or back"
        log_fix "git -C $(_q "$REPO") fetch --all && sh $(_qn "$SRC/install-stamp.sh") --check $(_q "$DIR") $WHO"
        return 0
      fi
      _lost="$(_git rev-list --count "$_cur..$_jo" || printf '')"
      # AN UNREADABLE COUNT IS NOT ZERO. Found reviewing this file: the first cut
      # folded an empty or non-numeric answer into 0 and proceeded, which is the
      # permissive direction on an unknown — the exact shape this repo keeps
      # finding. Both commits are known to exist by the cat-file check above, so
      # this should be unreachable; if it is ever reached, saying so beats
      # inventing a verdict. It discloses rather than refuses because a git hiccup
      # must not block a legitimate deploy (§2.11).
      case "$_lost" in
        ''|*[!0-9]*)
          log_warn "$WHO: could not count commits between $(_short "$_cur") and $(_short "$_jo")$_jw — proceeding, but this deploy was NOT checked for regression"
          log_nofix "harbor#115"
          return 0 ;;
      esac
      if [ "$_lost" -eq 0 ]; then
        _ahead="$(_git rev-list --count "$_jo..$_cur" || printf '0')"
        [ -n "$_jw" ] || log_ok "$WHO: moves forward $_ahead commit(s) — nothing installed is lost"
        return 0
      fi
      # A COUNT OF UNREACHABLE COMMITS IS NOT A COUNT OF LOST WORK (harbor#213).
      # `$_cur..$_old` counts commits reachable from the installed stamp and not from
      # the source, which for a squash-merging repo is every commit of whatever branch
      # the last install ran from — merged or not. Measured live 2026-08-13, this
      # refused `floor-install.sh --live --apply` with "would REMOVE 25 commit(s)"
      # while `git diff --stat origin/main <installed> -- bin/ hooks/` showed 24
      # insertions against 2653 deletions: main was the SUPERSET, and all 24 "unique"
      # lines were superseded earlier forms. The consequence was not cosmetic —
      # guard-cloud and guard-destroy gated nothing on the box for days, because the
      # only tool that installs them refused to run.
      #
      # And the remedy it printed was `--allow-regression`, a flag whose name asserts
      # a rollback that is not happening. That is the flag a reader learns to pass
      # reflexively, after which the check protects nothing (§2.11).
      #
      # So ask by CONTENT before refusing. merged-check.sh is the shared predicate
      # (four sufficient tests, cheapest first, failing toward "absent"); the same
      # question is asked by worktree.sh and govern-hook.sh, and three copies of it
      # is harbor#213 one level up.
      _mc="$SRC/merged-check.sh"
      if [ -f "$_mc" ] \
         && [ "$(sh "$_mc" --repo "$REPO" "$_cur" "$_jo" 2>/dev/null | awk '{print $1; exit}')" = "merged" ]; then
        [ -n "$_jw" ] || log_ok "$WHO: moves forward — the $_lost commit(s) unreachable from the source are patch-present in it (squash-merged), nothing is lost"
        return 0
      fi
      # The FAIL text is a contract: deploy and the installers read "<who> would remove N installed commit(s)".
      log_fail "$WHO would remove $_lost installed commit(s) from $DIR — a regression: installed $(_short "$_jo")$_jw, source $(_short "$_cur")"
      log_fix "sh $(_qn "$SRC/$WHO.sh") --apply $(_target_spelling) --accept-loss"
      log_note "or deploy from a checkout that contains them: git -C $(_q "$REPO") pull"
      _git log --oneline --no-decorate "$_cur..$_jo" | while IFS= read -r _l; do log_note "installed, not in the source: $_l"; done
      # THE CONTENT CHECK RAN AND DISAGREED, so say which question was answered. A
      # bare refusal here reads as "the content check is missing", and the operator's
      # next move — reaching for --allow-regression — is the same either way unless
      # the message distinguishes them.
      if [ -f "$_mc" ]; then
        log_note "content check: these commits are NOT patch-present in the source (harbor#213 predicate)"
      else
        log_note "content check: SKIPPED — $_mc is missing, so this is an ancestry verdict only"
      fi
      return 1
    }
    if [ -n "$_old" ]; then _judge "$_old" '' || :
    else log_note "$WHO: no stamp in $DIR, but its .harbor-manifest rows record what it installed"; fi
    _mfn=0
    while IFS= read -r _mcm; do
      [ -n "$_mcm" ] || continue
      _mfn=$((_mfn + 1)); _judge "$_mcm" " (recorded in $DIR/.harbor-manifest)" || :
    done <<EOF
$_mfc
EOF
    [ "$_mfn" -eq 0 ] || log_note "$WHO: .harbor-manifest records $_mfn more installed commit(s), each judged the same way"
    log_end; exit $?
    ;;

  --write)
    [ -n "$WHO" ] || { echo "install-stamp: --write needs an installer name" >&2; exit 2; }
    # D2's INTENT, applied by hand. That rule triggers on an `--apply` flag and
    # this script has none, so it will never fire here — but this writes into a
    # config dir, which is precisely what D2 exists to gate. Resolved paths, and
    # a flag set by the arg loop rather than $1 (harbor#52).
    if [ "$(_phys "$DIR")" = "$(_phys "$LIVE_DIR")" ] && [ "$LIVE_OK" -eq 0 ]; then
      log_fail "refusing to write the live config dir $DIR without an explicit --live"
      log_fix "sh $(_qn "$SRC/install-stamp.sh") --write $(_q "$DIR") $WHO --live"
      log_end; exit 1
    fi
    if [ ! -d "$DIR" ]; then
      log_fail "no such config dir: $DIR"
      log_nofix "install into it first; install-stamp records an install, it does not make one"
      log_end; exit 1
    fi
    _cur="$(_git rev-parse HEAD || printf '')"
    [ -n "$_cur" ] || { log_skip "$WHO: $REPO is not a git checkout — nothing to record"; log_end; exit $?; }
    _when="$(_git log -1 --format=%cI "$_cur" || printf 'unknown')"
    _desc="$(_git describe --tags --always --dirty 2>/dev/null || printf '%s' "$_cur")"
    # Rewrite in place: one line per installer, newest wins. A stamp file that
    # only ever appends turns into a log nobody reads, and the FIRST match would
    # then be the oldest — the reader of `_stamped` takes the first line.
    _tmp="$STAMP.$$"
    if [ -f "$STAMP" ]; then awk -v k="$WHO" '$1 != k' "$STAMP" > "$_tmp" 2>/dev/null || : ; fi
    printf '%s %s %s %s\n' "$WHO" "$_cur" "$_when" "$_desc" >> "$_tmp"
    mv "$_tmp" "$STAMP"
    log_ok "$WHO: recorded at $(_short "$_cur") in $STAMP"
    log_end; exit $?
    ;;
esac
