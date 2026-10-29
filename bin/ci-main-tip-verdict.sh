#!/usr/bin/env sh
# ci-main-tip-verdict.sh (harbor#586) — does every recent commit on main carry a GREEN CI verdict, in every fleet repo?
#
#   sh ci-main-tip-verdict.sh            write $HARBOR_CACHE_DIR/main-tip-verdict.json (default ~/.claude/cache)
#   sh ci-main-tip-verdict.sh --print    print the DELTA and the AGES for a person; exit 1 when a tip is red, 3 when a repo was
#                                     unread and none was red (D-29 unchecked: before D-49 it was 2, now a bad option)
#
# WHY. CI-3 (merge-check) guards the PR before the merge and nothing asks the question after it.
# Measured 2026-10-01: 41 of the last 99 pushes to harbor's main were not green (30 cancelled, 11 failed,
# no run at all for some). Measured 2026-10-06: four workload repos sat red on main with
# nothing alerting, because the fleet view read `gh run list --limit 1` (any branch, any workflow).
#
# THE FLEET is where ci-runners.sh reads it: the fleet snapshot (cache/fleet-snapshot.json,
# HARBOR_FLEET_SNAPSHOT) members that carry .github/workflows and a github.com origin, plus the `repo
# OWNER/NAME` lines of $CLAUDE_CONFIG_DIR/.harbor-ci-runners, plus harbor itself (named by log-lib's repo_slug: this
# checkout's origin, or the bin/repo-slug.txt beside an install; harbor#1149). HARBOR_TIP_REPO=o/r
# judges that one repo only.
#
# A COMMIT'S VERDICT is read from ITS runs, never from `gh run list` (whose page silently drops old
# runs, and absence from a page reads as "no run" — #586's own first pass was 2.4x wrong that way). One
# list call per repo covers the window; a commit missing from it is asked about BY SHA before it is
# called no-run. Only push and schedule runs count: an issue-comment or issues run says nothing about main.
#   green           some run succeeded
#   pending         a run is queued or running (and, with no run yet, the commit is under 10 min old)
#   failed          no success, a run failed / timed out
#   cancelled-only  no success, no failure: every run was cancelled (or skipped, neutral)
#   no-run          the commit has no push or schedule run at all (red only in a STRICT repo, see below)
#   unjudged        no run, in a repo whose push workflows are path-filtered: normal, not a verdict
# PUSH GOVERNS. A green push run of a commit is green, whatever a scheduled run says (harbor#1368: a nightly with a
# missing secret kept a green main red for weeks). A scheduled failure beside a push run is the quieter `SCHED <repo>`
# (tip.sched), unless that workflow is declared main-health: a `main-health OWNER/NAME WORKFLOW NAME` line in
# .harbor-ci-runners (empty by default), whose latest scheduled run then fails the commit as before. A commit with no
# push run at all is still judged by its scheduled runs. A rerun is the list's latest attempt, so a pass clears a fail.
# A failed commit carries `runs` (attempts of its failing push runs): 1 is shown `·1 run`, a flake until a second says
# otherwise, and still red at once; no debounce, because a delay hides a real red. Red since is the first failing
# run's completion (tip.red_at), not the commit's age.
# STRICT is harbor only (HARBOR_TIP_STRICT): its governance runs on every push, so no run IS red. In every other
# repo a commit with no run is "unjudged" and the verdict is the NEWEST commit in the window that has one (a
# path-filtered deploy workflow skips a .github-only commit; a pipeline repo, seen 2026-09). Harbor-only is chosen over
# parsing each repo's `on:` filters: no extra calls, and it can only miss a real red when CI stops triggering at all.
# A repo with no run on any commit in the window is no-ci.
# RED is a tip that is failed, cancelled-only, no-run, or pending for over 2h (CI runs ~40 min).
#
# NOT RED, SAID ONCE. A repo whose push/schedule workflows are all disabled (`disabled_manually`) is state
# "disabled"; one with no push/schedule run on main at all is "no-ci". Neither alarms, each logs one line on
# the change into it, and both are re-read hourly.
#
# THE REPORT IS THE DELTA, NEVER THE CENSUS. The cache holds every commit of every repo; what a person is
# told is, per repo that is not plainly green, the tip and how long it has been red, which commits went
# non-green SINCE THE LAST RUN, and how many stand from before. Green repos are one line. A repo's first
# run is a baseline: nothing is "new", and only a red tip speaks.
#
# API CALLS PER TICK. One `commits` read per repo (it carries the tip and the chain), and nothing more
# while the tip is unchanged, green, and was fully read under an hour ago; a disabled or no-ci repo costs
# none for an hour. A repo that needs a full read adds one `actions/runs` list, up to 10 by-sha reads, and
# one `actions/workflows` read only when its tip is red.
#
# WHERE FINDINGS LAND (docs/reference/checks.md row `main-tip-verdict`): the statusline alarm `MAIN RED <repo> <age>` from
# the cache; one `[check:main-tip-verdict]` line in cache/checks.log per change per repo (new non-green, the
# tip's verdict changed, a repo gone disabled) — never one per tick; `--print` for the detail.
# It WRITES NOTHING ELSE and re-runs nothing: a cancelled run is re-run by a person
# (`gh run rerun <id>`), because re-running from an unreviewed signal would hide the thing it found.
#
# A FAILED READ KEEPS THAT REPO'S PREVIOUS ENTRY and marks it "unread": true; silence never means "all green".
# Run by status-fleet-snapshot-refresh.sh every 300s. POSIX sh, jq, gh (HARBOR_GH swaps in a fake).
set -eu
. "$(dirname -- "$0")/library-log.sh"
log_init main-tip-verdict

case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
PRINT=0
case "${1:-}" in
  --print) PRINT=1 ;;
  "") ;;
  *) LOG_FD=2; log_fail "unknown option $1"; log_fix "sh $0 --help"; exit 2 ;;   # not a run: stderr, no summary (logging.md)
esac
[ $# -le 1 ] || { LOG_FD=2; log_fail "unexpected argument $2 after $1"; log_fix "sh $0 --help"; exit 2; }

BRANCH="${HARBOR_TIP_BRANCH:-main}"
SELF="$(repo_slug)"                          # harbor's own OWNER/NAME (harbor#1149); empty when nothing names it
STRICT="${HARBOR_TIP_STRICT:-$SELF}"         # repos whose every push runs CI: a commit with no run there IS red
WINDOW="${HARBOR_TIP_WINDOW:-30}"            # first-parent commits judged per run
PEND_SEC="${HARBOR_TIP_PENDING_SEC:-7200}"   # a run pending longer than this is stuck
GRACE_SEC=600                                # a fresh commit has no run for a moment
RECHECK_SEC=3600                             # a final state is re-read this often (a nightly run can turn green red)
FALLBACK_MAX=10                              # by-sha reads per repo per run, a rate-limit bound
CACHE_DIR="${HARBOR_CACHE_DIR:-$HOME/.claude/cache}"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
OUT="$CACHE_DIR/main-tip-verdict.json"
LOG="$CACHE_DIR/checks.log"
# The check tier's receipt (harbor#896): red over the non-green commits' short shas, green when none,
# stood-down when GitHub did not answer. --print writes nothing, so it leaves no receipt either.
RECEIPTS="$(receipt_dir)"   # harbor#904: the dir the reconcile reads, not $CACHE_DIR/checks
NOW="${HARBOR_NOW:-$(date +%s)}"
GH="${HARBOR_GH:-gh}"
command -v jq >/dev/null 2>&1 || { log_fail "jq is required, so nothing was judged"; log_fix "$(pkg_hint jq)"; exit 3; }
# Harbor is in the fleet unless HARBOR_TIP_REPO names the one repo judged: with no name for it the verdict would leave harbor's own main out.
[ -n "$SELF" ] || [ -n "${HARBOR_TIP_REPO:-}" ] || { log_fail "harbor's own repository is not derivable (no origin in this checkout, no repo-slug.txt beside this install), so nothing was judged"
  log_fix "HARBOR_TIP_REPO=<owner/name> sh $0, or deploy again: the install carries bin/repo-slug.txt"; exit 3; }
case "$WINDOW" in ''|*[!0-9]*) WINDOW=30 ;; esac
[ "$WINDOW" -ge 1 ] || WINDOW=30

T="$(mktemp -d "${TMPDIR:-/tmp}/main-tip-verdict.XXXXXX")"
trap 'rm -rf "$T"' EXIT INT TERM
api() { "$GH" api "$1" 2>/dev/null; }

# The fleet, one OWNER/NAME a line: harbor, the snapshot's repos with workflows, the config's `repo` lines.
fleet() {
  if [ -n "${HARBOR_TIP_REPO:-}" ]; then printf '%s\n' "$HARBOR_TIP_REPO"; return 0; fi
  SNAP="${HARBOR_FLEET_SNAPSHOT:-$CACHE_DIR/fleet-snapshot.json}"
  {
    printf '%s\n' "$SELF"
    if [ -s "$SNAP" ]; then
      jq -r '.[] | .descriptor | select(.path != null) | .path' "$SNAP" 2>/dev/null | while IFS= read -r _p; do
        [ -d "$_p/.github/workflows" ] || continue
        git -C "$_p" remote get-url origin 2>/dev/null | grep -F 'github.com' \
          | sed -E 's#(\.git)?/?$##; s#.*[:/]([^/:]+/[^/:]+)$#\1#' || :
      done
    fi
    [ -f "$CFG/.harbor-ci-runners" ] && awk '$1 == "repo" && $2 ~ /^[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+$/ { print $2 }' "$CFG/.harbor-ci-runners"
  } | awk '!seen[$0]++'
}

# jq: the workflow runs that speak for main, one record each, from a runs page
RECS='def recs: [.workflow_runs[] | select(.event == "push" or .event == "schedule")
       | {sha: .head_sha, c: (.conclusion // .status // "unknown"), ev: .event, wf: (.workflow_id // 0), t: (.created_at // ""),
          nm: (.name // ""), u: (.updated_at // .created_at // ""), n: (.run_attempt // 1)}];'

# judge OWNER/NAME N — write $T/entry.N.json. Returns 1 when GitHub did not answer; the caller keeps the old entry.
judge() {
  _r="$1"; _d="$T/r$2"; mkdir -p "$_d"
  _strict=false; case " $STRICT " in *" $_r "*) _strict=true ;; esac
  if [ -f "$OUT" ]; then
    jq -c --arg r "$_r" '(if (.repos | type) == "array" then .repos else [.] end) | map(select(.repo == $r)) | .[0] // null' \
      "$OUT" > "$_d/prev.json" 2>/dev/null || printf 'null\n' > "$_d/prev.json"
  else printf 'null\n' > "$_d/prev.json"; fi
  # no readable previous entry means a baseline; the legacy single-repo cache has no state, so it is "ok"
  jq -c '. as $p | if $p == null then {have: false, state: null, bad: [], tip: null, head: null, checked: 0}
         else {have: (($p.commits | type) == "array"), state: ($p.state // "ok"), bad: [($p.commits // [])[] | select(.bad) | .sha],
               tip: ($p.tip.verdict // null), head: ($p.head // $p.tip.sha // null), checked: ($p.checked // $p.at // 0)} end' \
    "$_d/prev.json" > "$_d/p.json"
  _pstate="$(jq -r '.state // empty' "$_d/p.json")"
  _age="$(jq -r --argjson n "$NOW" '$n - .checked' "$_d/p.json")"
  # a disabled or no-ci repo is not asked again for an hour
  if [ "$PRINT" = 0 ] && { [ "$_pstate" = disabled ] || [ "$_pstate" = no-ci ]; } && [ "$_age" -lt "$RECHECK_SEC" ]; then
    jq -c '. + {changed: false}' "$_d/prev.json" > "$T/entry.$2.json"; return 0
  fi

  api "repos/$_r/commits?sha=$BRANCH&per_page=100" > "$_d/commits.json" || { _why=commits; return 1; }
  jq -e 'type == "array" and length > 0' "$_d/commits.json" >/dev/null 2>&1 || { _why=commits; return 1; }
  # the tip unchanged, green, and fully read recently: nothing new to ask (a nightly run can still turn it red, hence the hour)
  _tipsha="$(jq -r '.[0].sha' "$_d/commits.json")"
  if [ "$PRINT" = 0 ] && [ "$_pstate" = ok ] && [ "$(jq -r '.head // empty' "$_d/p.json")" = "$_tipsha" ] \
     && [ "$(jq -r '.tip // empty' "$_d/p.json")" = green ] && [ "$_age" -lt "$RECHECK_SEC" ]; then
    jq -c '. + {new: [], cleared: [], baseline: false, tip: (.tip + {changed: false})}' "$_d/prev.json" > "$T/entry.$2.json"; return 0
  fi

  api "repos/$_r/actions/runs?branch=$BRANCH&per_page=100" > "$_d/runs.json" || { _why=runs; return 1; }
  jq -e '.workflow_runs | type == "array"' "$_d/runs.json" >/dev/null 2>&1 || { _why=runs; return 1; }

  # The first-parent chain from the tip: a merge's branch commits carry no run of their own and
  # are not judged. Stops at the page edge or the window.
  jq -c --argjson w "$WINDOW" '
    (map({key: .sha, value: .}) | from_entries) as $m
    | [ .[0] | recurse(if (.parents[0].sha // null) != null and $m[.parents[0].sha] != null
                       then $m[.parents[0].sha] else empty end) ]
    | .[0:$w]
    | map({sha, at: (.commit.committer.date | fromdateiso8601),
           msg: (.commit.message | split("\n")[0] | .[0:90])})' "$_d/commits.json" > "$_d/chain.json"

  jq -c "$RECS recs" "$_d/runs.json" > "$_d/recs.json"
  # A page of under 100 runs is the whole of main's history; a full one stops at its oldest run, and only a
  # commit older than that can be missing from it. Those are asked BY SHA (absence from a page is not absence).
  # Past the bound the window is cut there, tip-first, so the tip is always judged or the repo is unread.
  jq -r 'if (.workflow_runs | length) >= 100 then ([.workflow_runs[].created_at] | min) else "" end' "$_d/runs.json" > "$_d/edge"
  _edge="$(cat "$_d/edge")"; _edge_at=0; [ -z "$_edge" ] || _edge_at="$(jq -rn --arg e "$_edge" '$e | fromdateiso8601')"
  _n=0; : > "$_d/extra.jsonl"; _cut=""
  for _sha in $(jq -r '.[].sha' "$_d/chain.json"); do
    jq -e --arg s "$_sha" 'any(.[]; .sha == $s)' "$_d/recs.json" >/dev/null 2>&1 && continue
    [ "$(jq -r --arg s "$_sha" '[.[] | select(.sha == $s) | .at][0] < '"$_edge_at"'' "$_d/chain.json")" = true ] || continue
    if [ "$_n" -ge "$FALLBACK_MAX" ]; then _cut="$_sha"; break; fi
    _n=$((_n + 1))
    api "repos/$_r/actions/runs?head_sha=$_sha&per_page=20" > "$_d/one.json" || { _why="runs for $_sha"; return 1; }
    jq -e '.workflow_runs | type == "array"' "$_d/one.json" >/dev/null 2>&1 || { _why="runs for $_sha"; return 1; }
    jq -c "$RECS recs" "$_d/one.json" >> "$_d/extra.jsonl"
  done
  if [ -n "$_cut" ]; then
    jq -c --arg s "$_cut" '(map(.sha) | index($s)) as $i | .[0:$i]' "$_d/chain.json" > "$_d/c2.json"
    jq -e 'length > 0' "$_d/c2.json" >/dev/null 2>&1 || { _why="the tip is outside the runs page"; return 1; }
    mv "$_d/c2.json" "$_d/chain.json"
  fi
  jq -s 'add' "$_d/recs.json" "$_d/extra.jsonl" > "$_d/all.json"

  # No push or schedule run on main at all: there is no main CI to judge. All of its workflows disabled: say so.
  _state=ok
  if [ "$(jq 'length' "$_d/all.json")" = 0 ]; then _state=no-ci; fi

  # conclusions per sha: push runs, and the latest scheduled run of each workflow (an old nightly is superseded)
  # s: latest scheduled run per workflow that is declared main-health; x: the others (judged only when no push run exists).
  # f: the first failing push or health run's completion time and n its attempts, for "red since" and the one-run mark.
  _mh="$(awk -v r="$_r" '$1 == "main-health" && $2 == r { sub(/^[^ \t]+[ \t]+[^ \t]+[ \t]+/, ""); print }' "$CFG/.harbor-ci-runners" 2>/dev/null | jq -R . | jq -sc . 2>/dev/null)" || _mh='[]'
  [ -n "$_mh" ] || _mh='[]'
  jq -c --argjson mh "$_mh" 'def bad: . == "failure" or . == "timed_out" or . == "startup_failure";
         def latest: group_by(.wf) | map(sort_by(.t) | last);
         group_by(.sha) | map(. as $g | {key: .[0].sha, value: {
           p: [.[] | select(.ev == "push") | .c],
           s: ([.[] | select(.ev == "schedule" and (.nm as $n | $mh | index($n)))] | latest | map(.c)),
           x: ([.[] | select(.ev == "schedule" and (.nm as $n | $mh | index($n) | not))] | latest | map(.c)),
           xn: ([.[] | select(.ev == "schedule" and (.nm as $n | $mh | index($n) | not))] | latest | map(select(.c | bad) | .nm)),
           f: ([.[] | select((.ev == "push" or (.nm as $n | $mh | index($n))) and (.c | bad)) | .u] | min),
           n: ([.[] | select((.ev == "push" or (.nm as $n | $mh | index($n))) and (.c | bad)) | .n] | add)}}) | from_entries' \
    "$_d/all.json" > "$_d/conc.json"

  jq -c --argjson now "$NOW" --argjson pend "$PEND_SEC" --argjson grace "$GRACE_SEC" --arg repo "$_r" --arg st0 "$_state" --argjson strict "$_strict" \
    --slurpfile conc "$_d/conc.json" --slurpfile prev "$_d/p.json" '
    def bad: . == "failure" or . == "timed_out" or . == "startup_failure";
    def verdict($p; $s; $x): (if ($p | length) == 0 then $x else [$x[] | select(bad | not)] end) as $xs | ($p + $s + $xs) as $a
      | if ($s | any(bad)) then "failed"
        elif ($a | length) == 0 then "no-run"
        elif any($a[]; . == "success") then "green"
        elif any($a[]; . == "in_progress" or . == "queued" or . == "pending" or . == "waiting" or . == "requested") then "pending"
        elif any($a[]; . == "failure" or . == "timed_out" or . == "startup_failure") then "failed"
        else "cancelled-only" end;
    ($conc[0]) as $c | ($prev[0]) as $p
    | [.[] | . as $k
        | ($c[$k.sha] // {p: [], s: [], x: [], xn: []}) as $e
        | verdict($e.p; $e.s; $e.x) as $v0
        | ($now - $k.at) as $age
        | (if ($v0 == "no-run" and ($strict | not)) then "unjudged"
           elif $v0 == "no-run" and $age < $grace then "pending" else $v0 end) as $v
        | {sha: $k.sha, at: $k.at, msg: $k.msg, verdict: $v,
           red_at: (if $v == "failed" then ($e.f // null | if . == null then null else fromdateiso8601 end) else null end),
           runs: (if $v == "failed" then $e.n else null end),
           sched: (if ($e.p | length) > 0 then $e.xn else [] end),
           bad: ($v == "failed" or $v == "cancelled-only" or $v == "no-run" or ($v == "pending" and $age > $pend))}] as $cm
    | ($cm | map(select(.bad))) as $bad
    | ([$cm[] | select(.verdict != "unjudged")] | .[0]) as $j
    | (if $j == null then "no-ci" else $st0 end) as $st
    | ($j // $cm[0]) as $tip
    | {repo: $repo, state: $st, head: $cm[0].sha, checked: $now, at: $now, window: ($cm | length), baseline: ($p.have | not),
       tip: {sha: $tip.sha, verdict: $tip.verdict, at: $tip.at, msg: $tip.msg, red: ($tip.bad and $st == "ok"),
             red_at: ($tip.red_at // $tip.at), runs: $tip.runs, single: ($tip.verdict == "failed" and $tip.runs == 1),
             sched: $tip.sched,
             red_for: (if $tip.bad and $st == "ok" then $now - ($tip.red_at // $tip.at) else null end),
             changed: ($p.tip != null and $p.tip != $tip.verdict)},
       counts: ($cm | group_by(.verdict) | map({key: .[0].verdict, value: length}) | from_entries),
       nongreen: (if $st == "ok" then ($bad | length) else 0 end),
       new: (if $p.have and $st == "ok" then [$bad[] | select(.sha as $s | $p.bad | index($s) | not)] else [] end),
       cleared: (if $p.have then [$p.bad[] | select(. as $s | [$cm[] | select(.bad | not) | .sha] | index($s))] else [] end),
       commits: (if $st == "ok" then $cm else [] end)}' "$_d/chain.json" > "$_d/entry.json"

  # A red tip whose every main workflow is disabled is not red: it is switched off. One read, only when red.
  if [ "$_state" = ok ] && jq -e '.tip.red' "$_d/entry.json" >/dev/null 2>&1; then
    api "repos/$_r/actions/workflows?per_page=100" > "$_d/wf.json" || { _why=workflows; return 1; }
    jq -e '.workflows | type == "array"' "$_d/wf.json" >/dev/null 2>&1 || { _why=workflows; return 1; }
    if jq -e --slurpfile a "$_d/all.json" '
         ($a[0] | map(.wf) | unique) as $ids
         | [.workflows[] | select(.id as $i | $ids | index($i))] as $w
         | ($w | length) > 0 and ($w | all(.state != "active"))' "$_d/wf.json" >/dev/null 2>&1; then
      jq -c '.state = "disabled" | .tip.red = false | .tip.red_for = null | .nongreen = 0 | .new = [] | .commits = []' \
        "$_d/entry.json" > "$_d/e2.json" && mv "$_d/e2.json" "$_d/entry.json"
    fi
  fi
  jq -c --slurpfile p "$_d/p.json" '. + {changed: (($p[0].state // "") != .state)}' "$_d/entry.json" > "$T/entry.$2.json"
}

# ── judge every repo; a repo that did not answer keeps its last entry, flagged ─────────────────
fleet > "$T/fleet.txt"
_i=0; _unread=0
while IFS= read -r _repo; do
  _i=$((_i + 1)); _why=""
  if ! judge "$_repo" "$_i"; then
    _unread=$((_unread + 1)); log_fail "$_repo: UNREAD, GitHub did not answer (${_why:-read})"; log_fix "gh auth status"
    _prev="$(jq -c --arg r "$_repo" '(if (.repos | type) == "array" then .repos else [.] end) | map(select(.repo == $r)) | .[0] // empty' "$OUT" 2>/dev/null || :)"
    if [ -n "$_prev" ]; then printf '%s\n' "$_prev" | jq -c '. + {unread: true}' > "$T/entry.$_i.json"
    else printf '{"repo":"%s","state":"unread","unread":true,"at":%s}\n' "$_repo" "$NOW" > "$T/entry.$_i.json"; fi
  fi
done < "$T/fleet.txt"
jq -s --argjson now "$NOW" '{at: $now, unread: (any(.[]; .unread == true)), repos: .}' "$T"/entry.*.json > "$T/result.json" 2>/dev/null \
  || { log_fail "no repo to judge, so nothing was judged"; log_fix "sh $0 --help"; exit 3; }

# ── --print: the delta and the ages, with the detail a person asked for ───────────────────────
if [ "$PRINT" = 1 ]; then
  log_head "main tip"
  _ago='def ago: (. as $s | if $s < 3600 then "\($s / 60 | floor)m" elif $s < 172800 then "\($s / 3600 | floor)h" else "\($s / 86400 | floor)d" end);'
  jq -r --argjson now "$NOW" "$_ago"'
    .repos[] | select(.state == "ok" and (.tip.red or (.new | length) > 0)) | .repo' "$T/result.json" > "$T/loud.txt"
  _k=0
  while IFS= read -r _repo; do
    _k=$((_k + 1))
    _tip="$(jq -r --arg r "$_repo" '.repos[] | select(.repo == $r) | "\(.repo) main tip \(.tip.sha[0:8]) \(.tip.verdict)  \(.tip.msg)"' "$T/result.json")"
    _red="$(jq -r --arg r "$_repo" "$_ago"'.repos[] | select(.repo == $r) | .tip.red_for // empty | ago' "$T/result.json")"
    if [ -n "$_red" ]; then
      jq -e --arg r "$_repo" '.repos[] | select(.repo == $r and .tip.single)' "$T/result.json" >/dev/null 2>&1 && _red="$_red (one run: rerun it before calling it a pattern)"
      log_fail "$_tip — RED for $_red"
      log_fix "gh run list -R $_repo -b $BRANCH -L 5   # then: gh run view <id> --log-failed -R $_repo; gh run rerun <id> -R $_repo"
    else log_ok "$_tip"; fi
    jq -r --arg r "$_repo" --argjson now "$NOW" "$_ago"'
      .repos[] | select(.repo == $r) |
      (if .baseline then "baseline run: no earlier cache, so nothing is reported as new"
       else "\(.new | length) new non-green since last run"
         + (if (.new | length) > 0 then ": " + ([.new[] | "\(.sha[0:8]) \(.verdict) \(($now - .at) | ago)"] | join(", ")) else "" end) end),
      "\(.nongreen - (.new | length)) non-green standing in the last \(.window) commits"
        + (if .nongreen > 0 then " (oldest \(([.commits[] | select(.bad) | .at] | min) as $o | ($now - $o) | ago))" else "" end),
      (if (.cleared | length) > 0 then "\(.cleared | length) cleared since last run" else empty end),
      (if .nongreen > 0 then "on file: " + ([.commits[] | select(.bad) | "\(.sha[0:8]) \(.verdict)"] | join(", ")) else empty end)' "$T/result.json" \
      | while IFS= read -r _l; do log_note "$_l"; done
  done < "$T/loud.txt"
  jq -r '.repos[] | select(.state == "ok" and (.tip.sched | length) > 0) | "\(.repo): scheduled workflow failing beside green push CI (SCHED, not red): \(.tip.sched | join(", "))"' "$T/result.json" | while IFS= read -r _x; do log_note "$_x"; done
  jq -r '.repos[] | select(.state == "disabled") | .repo' "$T/result.json" | while IFS= read -r _x; do log_note "$_x: main CI disabled, not judged"; done
  jq -r '.repos[] | select(.state == "no-ci") | .repo' "$T/result.json" | while IFS= read -r _x; do log_note "$_x: no push or schedule run on main, not judged"; done
  _g="$(jq -r '[.repos[] | select(.state == "ok" and (.tip.red | not) and ((.new | length) == 0)) | (.repo | sub("^[^/]*/"; ""))] | join(" ")' "$T/result.json")"
  [ -z "$_g" ] || log_ok "green: $_g"
  log_end >/dev/null || :
  if jq -e 'any(.repos[]; .tip.red == true)' "$T/result.json" >/dev/null 2>&1; then exit 1; fi
  [ "$_unread" = 0 ] || exit 3   # D-29 unchecked; a red tip already left above with 1
  exit 0
fi

# ── write: the cache, then one checks.log line per repo that CHANGED ──────────────────────────
mkdir -p "$CACHE_DIR"
_ts="$(jq -rn --argjson t "$NOW" '$t | todate')"
jq -c '.repos[]' "$T/result.json" 2>/dev/null > "$T/each.jsonl" || :
while IFS= read -r _e; do
  _repo="$(printf '%s' "$_e" | jq -r .repo)"
  [ "$(printf '%s' "$_e" | jq -r '.unread // false')" = false ] || continue
  _prevred=false
  [ -f "$OUT" ] && _prevred="$(jq -r --arg r "$_repo" '(if (.repos | type) == "array" then .repos else [.] end) | map(select(.repo == $r)) | .[0].tip.red // false' "$OUT" 2>/dev/null || echo false)"
  printf '%s' "$_e" | jq -r --arg ts "$_ts" --argjson now "$NOW" --arg pr "$_prevred" '
    if .state == "disabled" then (if .changed then "[check:main-tip-verdict] \($ts) \(.repo) main CI disabled (every push/schedule workflow); not judged" else empty end)
    elif .state != "ok" then empty
    elif ((.new | length) > 0) or .tip.changed or (.tip.red and $pr != "true") then
      "[check:main-tip-verdict] \($ts) \(.repo) tip \(.tip.sha[0:8]) \(.tip.verdict)"
      + (if .tip.red then " red \(($now - .tip.at) / 60 | floor)m" else "" end)
      + "; \(.new | length) new non-green: " + ([.new[] | "\(.sha[0:8]) \(.verdict)"] | join(" ")) + "; \(.nongreen - (.new | length)) standing"
    else empty end' >> "$LOG" 2>/dev/null || :
done < "$T/each.jsonl"
cp "$T/result.json" "$OUT.tmp.$$" && mv -f "$OUT.tmp.$$" "$OUT" || { rm -f "$OUT.tmp.$$"; exit 1; }
# subjects: harbor's non-green commits by short sha, as before; every other repo's as name:sha
_bad="$(jq -r --arg self "$SELF" '[.repos[] | select(.state == "ok" and (.unread | not)) | .repo as $r | (.repo | sub("^[^/]*/"; "")) as $n | .commits[] | select(.bad)
               | (if $r == $self then "" else $n + ":" end) + .sha[0:8]] | join(" ")' "$T/result.json")"
# shellcheck disable=SC2086 # short shas, one word each
if [ -n "$_bad" ]; then log_receipt "$RECEIPTS" main-tip-verdict red $_bad || log_warn "no receipt written to $RECEIPTS"
elif [ "$_unread" -gt 0 ]; then log_receipt "$RECEIPTS" main-tip-verdict stood-down || log_warn "no receipt written to $RECEIPTS"
else log_receipt "$RECEIPTS" main-tip-verdict green || log_warn "no receipt written to $RECEIPTS"; fi
# A repo GitHub did not answer for is unchecked (3, D-29) unless a red was judged beside it, which is the 1 it always was.
[ "$_unread" = 0 ] || { [ -z "$_bad" ] || exit 1; exit 3; }
