#!/usr/bin/env sh
# hub-release.sh (harbor#1278) — one hub release as one tool: preflight, merge, red-team refresh, publish, hub pin, suites at the pin, zips.
#   sh hub-release.sh --preflight <inputs>     report every problem in one list, change nothing, exit 1 if the list is not empty
#   sh hub-release.sh --run <inputs>           the preflight, then the chain below; the same list stops it before anything moves
# inputs (both modes): --core <harbor-core checkout> --hub <hub checkout> --hub-repo <owner/name> --roster <file> --kit <dir> --out <dir>
#   [--pr <owner/repo>#<n>]...  every PR the release lands, in merge order      [--harbor <checkout>]  default: this tool's own checkout
#   [--mirror-pr <n>]  the harbor PR whose mirror branch the publish closes (default: the last harbor PR given)   [--log-dir <dir>]
#   HARBOR_HUB_DIR and HARBOR_HUB_CORE_DIR stand in for --hub and --core.
# THE PREFLIGHT, every line a finding, none a change (only `git fetch` runs, which moves remote-tracking refs):
#   each PR: open (a merged one is skipped, a closed one is a finding), not a draft, based on main, mergeable, not BEHIND, checks green;
#   each checkout (harbor, harbor-core, hub): on main, clean, no index.lock, not ahead of or diverged from origin/main. A 0-byte lock
#   older than 10 minutes is named stale with its rm line; nothing here removes it. The hub may instead sit on the pin/<12 hex> branch a
#   killed run left, when its policy.json already holds core's tip;
#   the inputs exist (roster, kit files, hub-signers in the hub) and jq, zip and node are installed;
#   the red-team record (bin/eval-redteam-corpus.sh --print): red for any reason but staleness is a finding. Stale is a finding only
#   for --preflight with no PR left to merge; with a merge pending the guards will move, and --run refreshes the record before the publish.
# THE RUN, after a clean preflight:
#   1 merge each PR with --match-head-commit at the head the preflight saw, re-reading each one first (a PR that moved is a stop);
#     where CLAUDECODE is set it PRINTS the gh commands and exits 3: merges in an agent session go through the approval gate.
#     Run it again once they are merged: a merged PR is skipped
#   2 fast-forward the harbor and harbor-core checkouts      3 the red-team refresh: bin/eval-redteam-corpus.sh
#   4 re-check, immediately before the publish: origin/main did not move since step 2 began and the record is fresh for the guards
#   5 bin/ci-mirror.sh --publish, with HARBOR_CI_CORE_MIRROR_TOKEN from the environment (run this under `secret run`; never argv or a log)
#   6 bin/hub-pin-upgrade.sh at core's new tip       7 the member and hub suites in a clean clone of harbor-core at the pin
#   8 bin/member-setup-generate.sh into <out>/at-<7 hex>
# SIGNING IS NOT HERE. The run ends by telling the hub admin to sign by hand (hub-pin-upgrade printed the lines). No step reads or
# touches a key. Every step is re-runnable: a merged PR, a published tip and a hub already on its pin branch are skipped.
# The log: <log-dir>/backups/hub-release/<time>/log (default log-dir $HOME/.local/state/harbor/hub-release), named in the last line.
# Exit 0 done or preflight clean, 1 a finding or a failed step (nothing after it ran), 2 usage, 3 merges handed to the operator.
set -eu
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(dirname -- "$HERE")"
LOG_FD=1; export LOG_FD
. "$HERE/library-log.sh"
. "$HERE/library-fs.sh"
log_init hub-release

MODE=''; HARBOR="$ROOT"; CORE="${HARBOR_HUB_CORE_DIR:-}"; HUB="${HARBOR_HUB_DIR:-}"; HUBREPO=''; ROSTER=''; KIT=''; OUT=''
MIRPR=''; LOGDIR="$HOME/.local/state/harbor/hub-release"; PRS=''
usage() { log_fail "$1"; log_nofix "sh $0 --help"; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --preflight) MODE=preflight ;;
    --run) MODE=run ;;
    --pr|--harbor|--core|--hub|--hub-repo|--roster|--kit|--out|--mirror-pr|--log-dir)
      [ $# -ge 2 ] || usage "$1 needs a value"
      case "$1" in
        --pr) PRS="$PRS$2
" ;;
        --harbor) HARBOR="$2" ;; --core) CORE="$2" ;; --hub) HUB="$2" ;; --hub-repo) HUBREPO="$2" ;; --roster) ROSTER="$2" ;;
        --kit) KIT="$2" ;; --out) OUT="$2" ;; --mirror-pr) MIRPR="$2" ;; --log-dir) LOGDIR="$2" ;;
      esac
      shift ;;
    -h|--help) awk 'NR<2{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;;
    *) usage "unknown argument $1" ;;
  esac
  shift
done
[ -n "$MODE" ] || usage "say --preflight or --run"
[ -n "$CORE" ] && [ -n "$HUB" ] || usage "--core and --hub are required"
slug_valid "$HUBREPO" || usage "--hub-repo wants owner/name"
[ -n "$ROSTER" ] && [ -n "$KIT" ] && [ -n "$OUT" ] || usage "--roster, --kit and --out are required"
case "$MIRPR" in *[!0-9]*) usage "--mirror-pr wants a number" ;; esac
printf '%s' "$PRS" | while IFS= read -r _p; do
  [ -z "$_p" ] && continue
  case "$_p" in */*#[0-9]*) ;; *) echo "bad" ;; esac
done | grep -q bad && usage "--pr wants owner/repo#<number>"
for _d in "$HARBOR" "$CORE" "$HUB"; do
  [ -d "$_d" ] && git -C "$_d" rev-parse --git-dir >/dev/null 2>&1 || usage "$_d is not a git checkout"
done
HARBOR="$(CDPATH='' cd -- "$HARBOR" && pwd)"; CORE="$(CDPATH='' cd -- "$CORE" && pwd)"; HUB="$(CDPATH='' cd -- "$HUB" && pwd)"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/hub-release.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT INT TERM
: > "$WORK/pending"
log_file "$LOGDIR"
log_head "$MODE"

BAD=0
finding() { BAD=$((BAD + 1)); log_fail "$1"; if [ -n "${2:-}" ]; then log_fix "$2"; else log_nofix "docs/how-to/adopt.md"; fi; }
stop() { log_fail "$1"; if [ -n "${2:-}" ]; then log_fix "$2"; else log_nofix "docs/how-to/adopt.md"; fi; log_end || :; exit 1; }
# A command's output to the screen and the log together; its own status comes back.
run_logged() {
  _rcf="$WORK/rc"; rm -f "$_rcf"
  { "$@" 2>&1 && echo 0 > "$_rcf" || echo "$?" > "$_rcf"; } | { if [ -n "$LOG_PATH" ]; then tee -a "$LOG_PATH"; else cat; fi; }
  read -r _rc < "$_rcf" || _rc=1
  return "$_rc"
}

# ── a PR: one gh call, every finding it yields ──
check_pr() { # <owner/repo> <n>   sets PR_HEAD and PR_STATE; a pending one is appended to $WORK/pending
  _slug="$1"; _n="$2"; _w="$_slug#$_n"; PR_HEAD=''; PR_STATE=''
  if ! _j="$(gh pr view "$_n" -R "$_slug" --json state,isDraft,mergeable,mergeStateStatus,reviewDecision,headRefOid,baseRefName,statusCheckRollup </dev/null 2>&1)"; then
    finding "$_w: cannot read it ($(printf '%s' "$_j" | tr '\n' ' ' | cut -c1-120))" "gh pr view $_n -R $_slug"; return 0
  fi
  _t="$(printf '%s' "$_j" | jq -r '(.statusCheckRollup // []) as $c
      | ($c | map(select((.__typename == "StatusContext" and .state != "SUCCESS")
          or (.__typename != "StatusContext" and (.status != "COMPLETED" or ((.conclusion // "") | IN("SUCCESS", "SKIPPED", "NEUTRAL") | not))))) | length) as $bad
      | [.state, (.isDraft | tostring), .mergeable, .mergeStateStatus, (.reviewDecision // "-"), .headRefOid, .baseRefName, ($c | length), $bad] | @tsv')" ||
    { finding "$_w: gh answered with something unreadable" "gh pr view $_n -R $_slug --json state"; return 0; }
  IFS='	' read -r _st _dr _mg _ms _rv PR_HEAD _bs _nc _bad <<EOF
$_t
EOF
  PR_STATE="$_st"
  [ "$_st" != OPEN ] || OPEN_PRS=$((OPEN_PRS + 1))
  case "$_st" in
    MERGED) log_ok "$_w is already merged: skipped"; return 0 ;;
    OPEN) ;;
    *) finding "$_w is $_st, not open (landed through another PR?)" "drop --pr $_w from the release"; return 0 ;;
  esac
  _b0="$BAD"
  [ "$_dr" != true ] || finding "$_w is a draft" "gh pr ready $_n -R $_slug"
  [ "$_bs" = main ] || finding "$_w is based on $_bs, not main" "gh pr edit $_n -R $_slug --base main"
  if [ "$_mg" = CONFLICTING ] || [ "$_ms" = DIRTY ]; then finding "$_w conflicts with its base" "rebase or merge main into its branch, push, run again"
  elif [ "$_ms" = BEHIND ]; then finding "$_w is BEHIND its base" "gh pr update-branch $_n -R $_slug, wait for its checks, run again"
  elif [ "$_mg" = UNKNOWN ] || [ "$_ms" = UNKNOWN ]; then finding "$_w: GitHub has not worked out its mergeability yet" "run again in a minute"; fi
  if [ "$_nc" = 0 ]; then finding "$_w reports no checks" "gh pr checks $_n -R $_slug"
  elif [ "$_bad" != 0 ]; then finding "$_w: $_bad of $_nc checks are not green (failed or still running)" "gh pr checks $_n -R $_slug --watch"; fi
  if [ "$BAD" = "$_b0" ]; then
    log_ok "$_w open, mergeable, up to date, $_nc checks green, head $(printf %.12s "$PR_HEAD")"
    [ "$_rv" != REVIEW_REQUIRED ] || log_note "$_w needs an approval before it merges"
    [ "$_ms" != BLOCKED ] || log_note "$_w is BLOCKED by branch protection with nothing else wrong: a review or a required status"
    printf '%s\t%s\t%s\t%s\n' "$_slug" "$_n" "$PR_HEAD" "$_rv" >> "$WORK/pending"
  fi
}

# ── a checkout: on main, clean, no lock, level with origin/main ──
CORE_TIP=''
check_checkout() { # <label> <dir> <hub: 1 to allow a pin branch>
  _l="$1"; _d="$2"; _hub="${3:-0}"
  _lock="$(git -C "$_d" rev-parse --absolute-git-dir)/index.lock"
  if [ -e "$_lock" ]; then
    _mt="$(fs_mtime "$_lock")"; _sz="$(fs_size "$_lock")"; _sz="${_sz:-0}"; _age=$(( $(date +%s) - ${_mt:-0} ))
    if [ "$_sz" = 0 ] && [ "$_age" -gt 600 ]; then
      finding "$_l: $_lock is stale (0 bytes, $((_age / 60)) min old)" "rm -f $_lock"
    else
      finding "$_l: $_lock exists ($_sz bytes, $((_age / 60)) min old): a git process may hold it" "check no git runs in $_d, then rm -f $_lock"
    fi
  fi
  if ! git -C "$_d" fetch -q origin 2>/dev/null; then finding "$_l: cannot fetch origin in $_d" "git -C $_d fetch origin"; return 0; fi
  git -C "$_d" rev-parse -q --verify refs/remotes/origin/main >/dev/null 2>&1 || { finding "$_l: $_d has no origin/main" ""; return 0; }
  _br="$(git -C "$_d" symbolic-ref --short -q HEAD || echo '(detached)')"
  if [ "$_hub" = 1 ] && [ "${_br#pin/}" != "$_br" ]; then
    _held="$(jq -r .core.commit "$_d/policy.json" 2>/dev/null || :)"
    if [ -n "$CORE_TIP" ] && [ "$_held" = "$CORE_TIP" ] && [ "$_br" = "pin/$(printf %.12s "$CORE_TIP")" ]; then
      HUB_RAISED=1; log_ok "$_l is already on $_br, raised to core's tip: the pin step will be skipped"; return 0
    fi
    finding "$_l is on $_br, which does not hold core's tip: a killed release left it" "git -C $_d checkout -- policy.json && git -C $_d switch main && git -C $_d branch -D $_br"
    return 0
  fi
  [ "$_br" = main ] || finding "$_l: $_d is on $_br, not main (another session moved it?)" "git -C $_d switch main"
  [ -z "$(git -C "$_d" status --porcelain 2>/dev/null)" ] || finding "$_l: $_d has uncommitted or untracked changes" "commit or discard them in $_d"
  if [ "$_br" = main ]; then
    _ah="$(git -C "$_d" rev-list --count origin/main..HEAD)"; _bh="$(git -C "$_d" rev-list --count HEAD..origin/main)"
    if [ "$_ah" != 0 ]; then finding "$_l: main is $_ah commit(s) ahead of origin/main$([ "$_bh" = 0 ] || echo " and $_bh behind it"): the publish would stage them" "push or drop them in $_d"
    elif [ "$_bh" != 0 ]; then log_note "$_l: main is $_bh commit(s) behind origin/main; the run fast-forwards it"; fi
  fi
  return 0
}

# ── the red-team record ──
# RT_STALE says what a stale or never-run record is: note, or finding.
rt_check() { # note|finding
  if [ ! -f "$HARBOR/bin/eval-redteam-corpus.sh" ]; then finding "red-team: no bin/eval-redteam-corpus.sh in $HARBOR" ""; return 0; fi
  _rc=0
  _out="$(env -u HARBOR_EVAL_REDTEAM_BASELINE -u HARBOR_EVAL_REDTEAM_SOURCES -u HARBOR_SCOPE_CACHE_DIR sh "$HARBOR/bin/eval-redteam-corpus.sh" --print 2>&1)" || _rc=$?
  case "$_rc" in
    0) log_ok "red-team record is fresh for this checkout's guards and green"; return 0 ;;
    1|3) ;;
    *) finding "red-team: the record could not be read (exit $_rc)" "sh $HARBOR/bin/eval-redteam-corpus.sh --print"; return 0 ;;
  esac
  _stale=0
  if [ "$_rc" = 3 ] || printf '%s\n' "$_out" | grep -q 'stale:'; then _stale=1; fi
  _other="$(printf '%s\n' "$_out" | grep 'FAIL:' | grep -vc 'stale:' || :)"
  if [ "$_rc" = 1 ] && [ "${_other:-0}" -gt 0 ]; then
    finding "red-team: $_other corpus finding(s) are not accepted" "sh $HARBOR/bin/eval-redteam-corpus.sh --print; adjudicate each on harbor#1313"
  fi
  if [ "$_stale" = 1 ]; then
    if [ "$1" = finding ]; then finding "red-team: the record is stale for the current guards (the guards or the pins changed since the last run)" "sh $HARBOR/bin/eval-redteam-corpus.sh"
    else log_note "red-team: the record is stale for the current guards; the run refreshes it immediately before the publish"; fi
  fi
}

# ── the preflight ──
HUB_RAISED=0; OPEN_PRS=0
preflight() { # note|auto: auto makes a stale red-team record a finding when no PR is left to merge
  log_head "preflight: the PRs"
  [ -n "$PRS" ] || log_note "no --pr given: nothing to merge"
  printf '%s' "$PRS" > "$WORK/prs"
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    check_pr "${_p%#*}" "${_p##*#}"
  done < "$WORK/prs"
  log_head "preflight: the checkouts"
  check_checkout harbor "$HARBOR"
  check_checkout harbor-core "$CORE"
  CORE_TIP="$(git -C "$CORE" rev-parse -q --verify refs/remotes/origin/main 2>/dev/null || :)"
  check_checkout hub "$HUB" 1
  log_head "preflight: the inputs"
  command -v jq >/dev/null 2>&1 || finding "jq is not installed" "$(pkg_hint jq)"
  command -v zip >/dev/null 2>&1 || finding "zip is not installed" "$(pkg_hint zip)"
  command -v "${HARBOR_EVAL_NODE:-node}" >/dev/null 2>&1 || finding "node is not installed: the red-team corpus's ccg harness would be skipped, and a skipped corpus is red" "$(pkg_hint node)"
  if [ -z "${HARBOR_CI_CORE_MIRROR_TOKEN:-}" ]; then  # secret-seam: Actions secret (entry harbor-core-mirror-token), presence only
    if [ "$MODE" = run ]; then finding "HARBOR_CI_CORE_MIRROR_TOKEN is not set, so the publish could not reach harbor-core" "run this tool under secret run, with the harbor-core mirror token as HARBOR_CI_CORE_MIRROR_TOKEN"
    else log_note "HARBOR_CI_CORE_MIRROR_TOKEN is not set; --run needs it"; fi
  fi
  [ -f "$ROSTER" ] || finding "--roster: no file at $ROSTER" ""
  for _f in run-setup.ps1 INSTALL-FOR-CLAUDE.md CLAUDE.md; do [ -f "$KIT/$_f" ] || finding "--kit lacks $_f" ""; done
  [ -f "$HUB/hub-signers" ] || finding "the hub checkout has no hub-signers" "git -C $HUB pull"
  [ -f "$HUB/policy.json" ] || finding "the hub checkout has no policy.json" ""
  log_head "preflight: the red-team record"
  if [ "$1" = auto ] && [ "$OPEN_PRS" = 0 ]; then rt_check finding; else rt_check note; fi
}
if [ "$MODE" = preflight ]; then
  preflight auto   # a PR still to merge will move the guards, so a stale record is no finding yet; with none open it is
  if [ "$BAD" = 0 ]; then log_ok "nothing to fix: the release can run"
  else log_note "$BAD finding(s) above, each with its fix line: nothing was changed"; fi
  log_end || exit 1; exit 0
fi
preflight note
if [ "$BAD" -gt 0 ]; then log_note "$BAD finding(s) above, each with its fix line: nothing was changed"; log_end || :; exit 1; fi

# ── 1. the merges ──
HSLUG="$(slug_of_url "$(git -C "$HARBOR" config --get remote.origin.url 2>/dev/null || :)")"
log_head "1 merge"
if [ -s "$WORK/pending" ]; then
  if [ -n "${CLAUDECODE:-}" ]; then
    log_note "an agent session does not merge: these go through the operator's approval. Run them in this order, then run this tool again:"
    while IFS='	' read -r _s _n _h _rv; do
      [ "$_rv" != REVIEW_REQUIRED ] || printf '  gh pr review %s -R %s --approve -b "Approved by the operator."\n' "$_n" "$_s"
      printf '  gh pr merge %s -R %s --squash --delete-branch --match-head-commit %s\n' "$_n" "$_s" "$_h"
    done < "$WORK/pending"
    log_end || :; exit 3
  fi
  cp "$WORK/pending" "$WORK/todo"
  while IFS='	' read -r _s _n _h _rv; do
    _b0="$BAD"; check_pr "$_s" "$_n"   # the PR may have moved since the preflight, a merge before it included
    [ "$PR_STATE" = OPEN ] || continue   # merged in the meantime, by hand
    [ "$BAD" = "$_b0" ] || stop "$_s#$_n changed since the preflight; nothing further was merged" "fix it, then run this tool again: the merged ones are skipped"
    [ "$PR_HEAD" = "$_h" ] || stop "$_s#$_n moved from $(printf %.12s "$_h") to $(printf %.12s "$PR_HEAD") since the preflight; nothing further was merged" "run this tool again: the preflight reads the new head, and the merged ones are skipped"
    if [ "$_rv" = REVIEW_REQUIRED ]; then gh pr review "$_n" -R "$_s" --approve -b "Approved by the operator." </dev/null >/dev/null 2>&1 || :; fi
    gh pr merge "$_n" -R "$_s" --squash --delete-branch --match-head-commit "$_h" </dev/null ||
      stop "gh pr merge refused $_s#$_n" "read gh's reason above, then run this tool again: the merged ones are skipped"
    log_ok "merged $_s#$_n at $(printf %.12s "$_h")"
  done < "$WORK/todo"
else log_ok "no PR left to merge"; fi

# ── 2. the checkouts to main's tip ──
log_head "2 checkouts"
for _x in "harbor:$HARBOR" "harbor-core:$CORE"; do
  _d="${_x#*:}"
  git -C "$_d" fetch -q origin && git -C "$_d" merge -q --ff-only refs/remotes/origin/main || stop "${_x%%:*}: cannot fast-forward $_d to origin/main" "git -C $_d status"
  log_ok "${_x%%:*} at $(git -C "$_d" rev-parse --short HEAD)"
done

# ── 3. the red-team refresh, 4. the re-check right before the publish ──
log_head "3 red-team refresh"
TIP0="$(git -C "$HARBOR" rev-parse HEAD)"
run_logged sh "$HARBOR/bin/eval-redteam-corpus.sh" || stop "the red-team refresh is red: nothing was published" "sh $HARBOR/bin/eval-redteam-corpus.sh --print"
log_head "4 re-check before the publish"
git -C "$HARBOR" fetch -q origin || stop "cannot fetch origin in $HARBOR" ""
_now="$(git -C "$HARBOR" rev-parse refs/remotes/origin/main)"
[ "$_now" = "$TIP0" ] && [ "$(git -C "$HARBOR" rev-parse HEAD)" = "$TIP0" ] ||
  stop "main moved while the red-team ran ($(printf %.12s "$TIP0") to $(printf %.12s "$_now")): its guards may have moved, so the record may be stale; nothing was published" "run this tool again"
log_ok "origin/main is still $(printf %.12s "$TIP0")"
_b0="$BAD"; rt_check finding
[ "$BAD" = "$_b0" ] || stop "the red-team record is not fresh and green right before the publish: nothing was published" "sh $HARBOR/bin/eval-redteam-corpus.sh"

# ── 5. the publish ──
log_head "5 publish to harbor-core"
if [ -z "$MIRPR" ]; then
  MIRPR="$(printf '%s' "$PRS" | awk -v s="$HSLUG" 'NF { split($0, a, "#"); if (a[1] == s) n = a[2] } END { print n }')"
  [ -n "$MIRPR" ] || stop "no harbor PR to name for the publish" "pass --mirror-pr <n>, any harbor PR number"
fi
[ -n "${HARBOR_CI_CORE_MIRROR_TOKEN:-}" ] || stop "HARBOR_CI_CORE_MIRROR_TOKEN is not set, so nothing can reach harbor-core" "run this tool under secret run, with the harbor-core mirror token as HARBOR_CI_CORE_MIRROR_TOKEN"  # secret-seam: Actions secret (entry harbor-core-mirror-token), presence only
( HARBOR_CI_CORE_MIRROR_DIR="$CORE"; export HARBOR_CI_CORE_MIRROR_DIR
  run_logged sh "$HARBOR/bin/ci-mirror.sh" --publish "$MIRPR" ) || stop "ci-mirror --publish refused: nothing after it ran" "the gate rows above name the fix"
git -C "$CORE" fetch -q origin || stop "cannot fetch origin in $CORE" ""
PIN="$(git -C "$CORE" rev-parse refs/remotes/origin/main)"
log_ok "harbor-core main, the new pin: $PIN"

# ── 6. the hub pin, on a branch ──
log_head "6 hub pin"
if [ "$HUB_RAISED" = 1 ] && [ "$(git -C "$HUB" symbolic-ref --short -q HEAD)" = "pin/$(printf %.12s "$PIN")" ]; then log_ok "the hub is already on pin/$(printf %.12s "$PIN")"
else run_logged sh "$HARBOR/bin/hub-pin-upgrade.sh" --pin "$PIN" --hub "$HUB" --core "$CORE" || stop "hub-pin-upgrade refused" "read its refusal above"; fi

# ── 7. the member and hub suites, as the laptops run them: a clean clone at the pin ──
log_head "7 member and hub suites at the pin"
CLONE="$WORK/core"
git clone -q "$(git -C "$CORE" config --get remote.origin.url)" "$CLONE" && git -C "$CLONE" checkout -q --detach "$PIN" || stop "cannot clone harbor-core at $PIN" ""
grep -E '^tests/(member|hub)/' "$CLONE/contracts/suites.txt" > "$WORK/suites.txt" || :
[ -s "$WORK/suites.txt" ] || stop "the pin lists no member or hub suite, so nothing would run" "contracts/suites.txt at $PIN"
( cd "$CLONE" && run_logged sh bin/test-suite-run.sh --include "$WORK/suites.txt" ) || stop "the member/hub suites are RED at $PIN" "read the run above; the log has all of it"
log_ok "the member and hub suites are green at $(printf %.12s "$PIN")"

# ── 8. every colleague's zip ──
log_head "8 setup zips"
ZIPS="$OUT/at-$(printf %.7s "$PIN")"
run_logged sh "$HARBOR/bin/member-setup-generate.sh" --pin "$PIN" --core "$CORE" --hub "$HUBREPO" --signers "$HUB/hub-signers" \
  --roster "$ROSTER" --kit "$KIT" --out "$ZIPS" || stop "member-setup-generate failed" "read its refusal above"
log_ok "zips in $ZIPS"

log_head "done: signing is yours"
log_note "pin $PIN. The hub admin signs BY HAND, in their own terminal (the key asks for its passphrase): hub-pin-upgrade printed the lines above."
log_note "Then push the branch, open the hub PR, raise HARBOR_HUB_CORE_SHA to the pin, merge once the hub gate is green, and send the zips in $ZIPS/zips."
log_end
