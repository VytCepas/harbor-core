#!/usr/bin/env sh
# ci-mirror.sh (harbor#1149) - mirror a harbor PR's core files to the public harbor-core repo, where hosted CI is free.
#
#   ci-mirror.sh [--dry-run] <pr>   stage the PR's base, then its head, on branch ci/harbor-<pr>; push it and ci/base-<pr>, and
#                                   open or update PR "harbor#<pr>" into ci/base-<pr>. A head whose core set equals its base has
#                                   no hosted run, so it sets public-ci success itself
#   ci-mirror.sh --status <pr>      set the `public-ci` commit status on the harbor PR head from the mirror branch's run
#   ci-mirror.sh --close <pr>       close the mirror PR and delete its branch
#
# Staging and every gate are bin/deploy-push.sh's, run from THIS checkout against the PR head (HARBOR_ROOT), so a PR cannot
# weaken the gate that judges it. Any red gate and nothing is pushed. The mirror checkout (HARBOR_CORE_MIRROR_DIR, required;
# its origin is harbor-core) must be clean and on a branch; the branch starts from origin/main
# and each mirror is two more snapshot commits on it, the base then the head, so a push is a fast-forward and never forced.
# THE BASE. The mirror PR targets ci/base-<pr>, the core set of the PR's merge-base with this checkout's HEAD (the PR's
# base, as public-ci checks it out), so hosted CI diffs only what the PR changes. Against harbor-core main, the last
# publish, every PR carried everything merged since and selected every suite. The base passes the leak, secrets, history
# and domain gates too (deploy-push --ci-base), because it is pushed to the public repo.
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
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "ci-mirror: unknown option '$a'" >&2; exit 2 ;;
    *) [ -z "$PR" ] || { echo "ci-mirror: one pull request only" >&2; exit 2; }; PR="$a" ;;
  esac
done
case "$PR" in ''|*[!0-9]*) echo "usage: ci-mirror.sh [--dry-run] <pr> | --status <pr> | --close <pr>" >&2; exit 2 ;; esac
[ "$DRY" = 0 ] || [ "$MODE" = mirror ] || { echo "ci-mirror: --dry-run applies to a mirror only" >&2; exit 2; }

refuse() { log_fail "$1"; [ -z "${2:-}" ] || log_fix "$2"; log_end || :; exit 1; }

BRANCH="ci/harbor-$PR"; BASEBR="ci/base-$PR"
CORE="${HARBOR_CORE_SLUG:-VytCepas/harbor-core}"
slug_valid "$CORE" || refuse "HARBOR_CORE_SLUG '$CORE' is not owner/name" "export HARBOR_CORE_SLUG=<owner>/<harbor-core repo>"
NODIFF="no core file differs from the PR's base"
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
  for __b in "$BRANCH" "$BASEBR"; do
    core_gh api -X DELETE "repos/$CORE/git/refs/heads/$__b" >/dev/null 2>&1 || :
    # The delete's exit is not trusted: the branch must be gone.
    if core_gh api "repos/$CORE/git/ref/heads/$__b" >/dev/null 2>&1; then refuse "$__b still exists on $CORE" "gh api -X DELETE repos/$CORE/git/refs/heads/$__b"; fi
    log_ok "$__b is gone from $CORE"
  done
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
WT="$TMP/src"; WTB="$TMP/base"
cleanup() { for __w in "$WT" "$WTB"; do git -C "$ROOT" worktree remove --force "$__w" >/dev/null 2>&1 || :; done; git -C "$ROOT" worktree prune >/dev/null 2>&1 || :; rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

# The PR head as a detached checkout: deploy-push stages exactly its HEAD.
HEAD_SHA="$(gh pr view "$PR" --repo "$HSLUG" --json headRefOid --jq .headRefOid)" || refuse "no head sha for $HSLUG#$PR" "gh pr view $PR --repo $HSLUG"
case "$HEAD_SHA" in *[!0123456789abcdef]*|'') refuse "gh returned '$HEAD_SHA' for the head of #$PR, not a sha" "" ;; esac
if ! git -C "$ROOT" cat-file -e "$HEAD_SHA^{commit}" 2>/dev/null; then
  git -C "$ROOT" fetch -q origin "refs/pull/$PR/head" || refuse "cannot fetch the head of #$PR" "git -C $ROOT fetch origin refs/pull/$PR/head"
  [ "$(git -C "$ROOT" rev-parse FETCH_HEAD)" = "$HEAD_SHA" ] || refuse "the fetched head of #$PR is not $HEAD_SHA (it moved)" "run again"
fi
git -C "$ROOT" worktree add -q --detach "$WT" "$HEAD_SHA" || refuse "cannot check out $HEAD_SHA" ""
BASE_SHA="$(git -C "$ROOT" merge-base "$HEAD_SHA" HEAD 2>/dev/null)" || refuse "no merge-base of $HEAD_SHA and this checkout's HEAD" "check out the PR's base with its history (fetch-depth: 0)"

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

# The base first, so the head's commit diffs against it. Its gates are deploy-push's leak, secrets, history and domain rows.
git -C "$ROOT" worktree add -q --detach "$WTB" "$BASE_SHA" || refuse "cannot check out the base $BASE_SHA" ""
HARBOR_ROOT="$WTB" sh "$SRC/deploy-push.sh" --ci-base "$TDIR" || refuse "the PR's base $(printf '%s' "$BASE_SHA" | cut -c1-12) failed a gate; nothing was pushed" "the release gate rows above name the fix"
BASE_COMMIT="$(git -C "$TDIR" rev-parse HEAD)"

# Staging, history scan and every gate: deploy-push's, unchanged. Refused or red, it wrote nothing and nothing is pushed.
gate "$TDIR" || refuse "deploy-push refused or a gate is red; nothing was pushed" "the release gate rows above name the fix"

if git -C "$TDIR" diff --quiet "$BASE_COMMIT" HEAD; then
  # No core file differs, so no hosted run will ever report: public-ci is set here, or a required check waits forever.
  # A mirror left by an earlier push of this PR tested other core files, so it goes.
  log_ok "the core set of #$PR equals its base's; nothing to mirror"
  close_mirror
  STATE=success; DESC="$NODIFF"; URL="https://github.com/$CORE/tree/main"; set_status
  log_end || :; exit 0
fi

# A plain refspec: never a force, never main.
core_git push -q --atomic origin "$BRANCH:refs/heads/$BRANCH" "$BASE_COMMIT:refs/heads/$BASEBR" ||
  refuse "the push of $BRANCH and $BASEBR was refused" "a non-fast-forward means a branch moved elsewhere; --close $PR and mirror again"
log_ok "pushed $BRANCH ($(git -C "$TDIR" rev-parse --short HEAD)) and $BASEBR ($(git -C "$TDIR" rev-parse --short "$BASE_COMMIT")) to $CORE"

TITLE="harbor#$PR"
BODY="Core-layer mirror of harbor PR $PR at $(printf '%s' "$HEAD_SHA" | cut -c1-12), staged by bin/ci-mirror.sh after the export gates. For hosted CI only; never merged."
EXIST="$(core_gh pr list --repo "$CORE" --head "$BRANCH" --state open --json number --jq '.[0].number // empty')" || refuse "cannot list PRs on $CORE" "the token needs Pull requests: write"
if [ -n "$EXIST" ]; then
  core_gh pr edit "$EXIST" --repo "$CORE" --base "$BASEBR" --title "$TITLE" --body "$BODY" >/dev/null || refuse "could not update $CORE#$EXIST" ""
  log_ok "updated $CORE#$EXIST (harbor#$PR)"
else
  core_gh pr create --repo "$CORE" --base "$BASEBR" --head "$BRANCH" --title "$TITLE" --body "$BODY" >/dev/null || refuse "could not open the PR on $CORE" "the token needs Pull requests: write"
  log_ok "opened the mirror PR harbor#$PR on $CORE"
fi
log_end || :; exit 0
