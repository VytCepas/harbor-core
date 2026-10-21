#!/usr/bin/env sh
# ci-mirror.sh (harbor#1149) - mirror a harbor PR's core files to the public harbor-core repo, where hosted CI is free.
#
#   ci-mirror.sh [--dry-run] <pr>   stage the PR head's core set on branch ci/harbor-<pr>, push it, open or update PR "harbor#<pr>";
#                                   a core set equal to harbor-core main has no hosted run, so it sets public-ci success itself
#   ci-mirror.sh --status <pr>      set the `public-ci` commit status on the harbor PR head from the mirror branch's run
#   ci-mirror.sh --close <pr>       close the mirror PR and delete its branch
#
# Staging and every gate are bin/deploy-push.sh's, run from THIS checkout against the PR head (HARBOR_ROOT), so a PR cannot
# weaken the gate that judges it. Any red gate and nothing is pushed. The mirror checkout (HARBOR_CORE_MIRROR_DIR, required;
# its origin is harbor-core) must be clean and on a branch; the branch starts from origin/main
# and each mirror is one more snapshot commit on it, so a push is a fast-forward and never forced.
# The push credential is HARBOR_CORE_MIRROR_TOKEN, sent as a request header from the environment: never in a URL or argv.
# --dry-run runs the gates against the checkout as it is and touches no network.
# Env: HARBOR_CORE_SLUG (default VytCepas/harbor-core), HARBOR_SLUG (the harbor repo, else derived from origin).
# Exit 0 done, 1 refused or red, 2 usage.
set -eu

case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
ROOT="${HARBOR_ROOT:-$(CDPATH= cd -- "$SRC/.." && pwd)}"
. "$SRC/log-lib.sh"
log_init ci-mirror
LOG_FD=2

DRY=0; MODE=mirror; PR=''
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --status) MODE=status ;;
    --close) MODE=close ;;
    -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "ci-mirror: unknown option '$a'" >&2; exit 2 ;;
    *) [ -z "$PR" ] || { echo "ci-mirror: one pull request only" >&2; exit 2; }; PR="$a" ;;
  esac
done
case "$PR" in ''|*[!0-9]*) echo "usage: ci-mirror.sh [--dry-run] <pr> | --status <pr> | --close <pr>" >&2; exit 2 ;; esac
[ "$DRY" = 0 ] || [ "$MODE" = mirror ] || { echo "ci-mirror: --dry-run applies to a mirror only" >&2; exit 2; }

refuse() { log_fail "$1"; [ -z "${2:-}" ] || log_fix "$2"; log_end || :; exit 1; }

BRANCH="ci/harbor-$PR"
CORE="${HARBOR_CORE_SLUG:-VytCepas/harbor-core}"
slug_valid "$CORE" || refuse "HARBOR_CORE_SLUG '$CORE' is not owner/name" "export HARBOR_CORE_SLUG=<owner>/<harbor-core repo>"
NODIFF="no core file differs from $CORE main"
HSLUG="${HARBOR_SLUG:-$(slug_of_url "$(git -C "$ROOT" config --get remote.origin.url 2>/dev/null || :)")}"
slug_valid "$HSLUG" || refuse "the harbor repo slug is unknown" "export HARBOR_SLUG=<owner>/harbor"

need_token() {
  [ -n "${HARBOR_CORE_MIRROR_TOKEN:-}" ] || refuse "HARBOR_CORE_MIRROR_TOKEN is not set, so nothing can reach $CORE" "store the fine-grained harbor-core token as that harbor secret"
}
# gh calls against harbor-core carry the mirror token (gh sends GH_TOKEN as a header); harbor's own calls do not.
core_gh() { GH_TOKEN="$HARBOR_CORE_MIRROR_TOKEN" gh "$@"; }

# public-ci on the harbor PR head: STATE, DESC and URL as the caller set them.
set_status() {
  gh api -X POST "repos/$HSLUG/statuses/$HEAD_SHA" -f state="$STATE" -f context=public-ci -f description="$DESC" -f target_url="$URL" >/dev/null ||
    refuse "could not set public-ci on $HEAD_SHA" "the caller needs statuses: write on $HSLUG"
  log_ok "public-ci $STATE on $HSLUG#$PR ($(printf '%s' "$HEAD_SHA" | cut -c1-12)): $URL"
}
close_mirror() {
  if core_gh pr close "$BRANCH" --repo "$CORE" >/dev/null 2>&1; then log_ok "closed the mirror PR of $HSLUG#$PR"; else log_note "no open mirror PR for $BRANCH"; fi
  core_gh api -X DELETE "repos/$CORE/git/refs/heads/$BRANCH" >/dev/null 2>&1 || :
  # The delete's exit is not trusted: the branch must be gone.
  if core_gh api "repos/$CORE/git/ref/heads/$BRANCH" >/dev/null 2>&1; then refuse "$BRANCH still exists on $CORE" "gh api -X DELETE repos/$CORE/git/refs/heads/$BRANCH"; fi
  log_ok "$BRANCH is gone from $CORE"
}

case "$MODE" in
status)
  need_token
  HEAD_SHA="$(gh pr view "$PR" --repo "$HSLUG" --json headRefOid --jq .headRefOid)" || refuse "no head sha for $HSLUG#$PR" "gh pr view $PR --repo $HSLUG"
  MIR="$(core_gh pr list --repo "$CORE" --head "$BRANCH" --state open --json headRefOid --jq '.[0].headRefOid // empty')" || refuse "cannot read $CORE" "gh auth status"
  STATE=pending; DESC="no mirror PR yet"; URL="https://github.com/$CORE/tree/$BRANCH"
  if [ -n "$MIR" ]; then
    # One line per run of the mirror head: status, conclusion, url. A run of an older commit says nothing about this one.
    RUNS="$(core_gh run list --repo "$CORE" --branch "$BRANCH" --limit 30 --json headSha,status,conclusion,url \
      --jq ".[] | select(.headSha == \"$MIR\") | [.status, .conclusion, .url] | @tsv")" || refuse "cannot list runs on $CORE" "gh run list --repo $CORE --branch $BRANCH"
    if [ -z "$RUNS" ]; then DESC="hosted CI has not started on this mirror"
    else
      URL="$(printf '%s\n' "$RUNS" | awk -F'\t' '{ u = $3 } $1 == "completed" && $2 != "success" && $2 != "skipped" && $2 != "neutral" && !f { f = 1; fu = $3 } END { print (fu != "" ? fu : u) }')"
      STATE="$(printf '%s\n' "$RUNS" | awk -F'\t' '
        $1 != "completed" { pend = 1; next }
        $2 != "success" && $2 != "skipped" && $2 != "neutral" { bad = 1 }
        END { print (bad ? "failure" : (pend ? "pending" : "success")) }')"
      DESC="hosted CI on the public mirror: $STATE"
    fi
  else
    # No mirror because no core file differs: the mirror run set success itself, and pending here would undo it.
    CUR="$(gh api "repos/$HSLUG/commits/$HEAD_SHA/statuses" --jq '[.[] | select(.context == "public-ci")][0] | [.state, .description] | @tsv' 2>/dev/null || :)"
    if [ "$CUR" = "success	$NODIFF" ]; then log_ok "public-ci success on $HSLUG#$PR: $NODIFF"; log_end || :; exit 0; fi
  fi
  set_status
  log_end || :; exit 0 ;;
close)
  need_token; close_mirror
  log_end || :; exit 0 ;;
esac

# ── mirror ──
MIRDIR="${HARBOR_CORE_MIRROR_DIR:-}"
[ -n "$MIRDIR" ] || refuse "HARBOR_CORE_MIRROR_DIR is not set" "git clone https://github.com/$CORE.git <dir>, then export HARBOR_CORE_MIRROR_DIR=<dir>"
[ -d "$MIRDIR" ] || refuse "no mirror checkout at $MIRDIR" "git clone https://github.com/$CORE.git $MIRDIR"
TDIR="$(CDPATH= cd -- "$MIRDIR" && pwd -P)"
[ "$(git -C "$TDIR" rev-parse --show-toplevel 2>/dev/null || :)" = "$TDIR" ] || refuse "$MIRDIR is not the top level of a git checkout" ""
[ "$(slug_of_url "$(git -C "$TDIR" config --get remote.origin.url 2>/dev/null || :)")" = "$CORE" ] ||
  refuse "the mirror checkout's origin is not $CORE, so a push would go elsewhere" "git -C $TDIR remote set-url origin https://github.com/$CORE.git"
[ -z "$(git -C "$TDIR" status --porcelain 2>/dev/null)" ] || refuse "the mirror checkout has uncommitted or untracked changes" "commit or clean $TDIR"
[ "$DRY" = 1 ] || need_token

TMP="$(mktemp -d "${TMPDIR:-/tmp}/ci-mirror.XXXXXX")" || exit 2
WT="$TMP/src"
cleanup() { git -C "$ROOT" worktree remove --force "$WT" >/dev/null 2>&1 || :; git -C "$ROOT" worktree prune >/dev/null 2>&1 || :; rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

# The PR head as a detached checkout: deploy-push stages exactly its HEAD.
HEAD_SHA="$(gh pr view "$PR" --repo "$HSLUG" --json headRefOid --jq .headRefOid)" || refuse "no head sha for $HSLUG#$PR" "gh pr view $PR --repo $HSLUG"
case "$HEAD_SHA" in *[!0123456789abcdef]*|'') refuse "gh returned '$HEAD_SHA' for the head of #$PR, not a sha" "" ;; esac
if ! git -C "$ROOT" cat-file -e "$HEAD_SHA^{commit}" 2>/dev/null; then
  git -C "$ROOT" fetch -q origin "refs/pull/$PR/head" || refuse "cannot fetch the head of #$PR" "git -C $ROOT fetch origin refs/pull/$PR/head"
  [ "$(git -C "$ROOT" rev-parse FETCH_HEAD)" = "$HEAD_SHA" ] || refuse "the fetched head of #$PR is not $HEAD_SHA (it moved)" "run again"
fi
git -C "$ROOT" worktree add -q --detach "$WT" "$HEAD_SHA" || refuse "cannot check out $HEAD_SHA" ""

gate() { HARBOR_ROOT="$WT" sh "$SRC/deploy-push.sh" "$@"; }

if [ "$DRY" = 1 ]; then
  gate --dry-run "$TDIR" || refuse "a gate is red; a mirror would push nothing" "each release gate row above names its fix"
  log_ok "dry run: $BRANCH would carry $(printf '%s' "$HEAD_SHA" | cut -c1-12) and open PR harbor#$PR on $CORE; nothing was written or pushed"
  log_end || :; exit 0
fi

# The auth rides in git's environment as a header: not in the remote's URL, not in argv, not in .git/config.
AUTH="$(printf 'x-access-token:%s' "$HARBOR_CORE_MIRROR_TOKEN" | base64 | tr -d '\n')"
core_git() { GIT_TERMINAL_PROMPT=0 GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.extraHeader GIT_CONFIG_VALUE_0="Authorization: Basic $AUTH" git -C "$TDIR" "$@"; }

core_git fetch -q origin || refuse "cannot fetch $CORE" "check HARBOR_CORE_MIRROR_TOKEN (Contents: write)"
git -C "$TDIR" rev-parse -q --verify refs/remotes/origin/main >/dev/null || refuse "$CORE has no main to start from" ""
START=refs/remotes/origin/main
if git -C "$TDIR" rev-parse -q --verify "refs/remotes/origin/$BRANCH" >/dev/null; then START="refs/remotes/origin/$BRANCH"; fi
git -C "$TDIR" checkout -q -B "$BRANCH" "$START" || refuse "cannot check out $BRANCH in the mirror checkout" ""
# main moved since the last mirror: take it into the branch's history, keeping our tree (deploy-push replaces it anyway).
if ! git -C "$TDIR" merge-base --is-ancestor refs/remotes/origin/main HEAD; then
  git -C "$TDIR" merge -q -s ours --no-edit -m "Merge $CORE main into $BRANCH" refs/remotes/origin/main || refuse "cannot merge $CORE main into $BRANCH" ""
fi

# Staging, history scan and every gate: deploy-push's, unchanged. Refused or red, it wrote nothing and nothing is pushed.
gate "$TDIR" || refuse "deploy-push refused or a gate is red; nothing was pushed" "the release gate rows above name the fix"

if git -C "$TDIR" diff --quiet refs/remotes/origin/main HEAD; then
  # No core file differs, so no hosted run will ever report: public-ci is set here, or a required check waits forever.
  # A mirror left by an earlier push of this PR tested other core files, so it goes.
  log_ok "the core set of #$PR equals $CORE main; nothing to mirror"
  close_mirror
  STATE=success; DESC="$NODIFF"; URL="https://github.com/$CORE/tree/main"; set_status
  log_end || :; exit 0
fi

# A plain refspec: never a force, never main.
core_git push -q origin "$BRANCH:refs/heads/$BRANCH" || refuse "the push of $BRANCH was refused" "a non-fast-forward means the branch moved elsewhere; --close $PR and mirror again"
log_ok "pushed $BRANCH ($(git -C "$TDIR" rev-parse --short HEAD)) to $CORE"

TITLE="harbor#$PR"
BODY="Core-layer mirror of harbor PR $PR at $(printf '%s' "$HEAD_SHA" | cut -c1-12), staged by bin/ci-mirror.sh after the export gates. For hosted CI only; never merged."
EXIST="$(core_gh pr list --repo "$CORE" --head "$BRANCH" --state open --json number --jq '.[0].number // empty')" || refuse "cannot list PRs on $CORE" "the token needs Pull requests: write"
if [ -n "$EXIST" ]; then
  core_gh pr edit "$EXIST" --repo "$CORE" --title "$TITLE" --body "$BODY" >/dev/null || refuse "could not update $CORE#$EXIST" ""
  log_ok "updated $CORE#$EXIST (harbor#$PR)"
else
  core_gh pr create --repo "$CORE" --base main --head "$BRANCH" --title "$TITLE" --body "$BODY" >/dev/null || refuse "could not open the PR on $CORE" "the token needs Pull requests: write"
  log_ok "opened the mirror PR harbor#$PR on $CORE"
fi
log_end || :; exit 0
