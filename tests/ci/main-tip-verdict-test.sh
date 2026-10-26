#!/usr/bin/env sh
# main-tip-verdict.sh read against a fake gh (harbor#586, the whole fleet: harbor#1088). The stub serves one fixture file per
# endpoint and fails for any it has none for: that is "GitHub did not answer". The real API is never
# called. Each verdict has a planted commit that must read red and a control that must not.
. "$(dirname "$0")/../lib/core.sh"; t_init
FX="$T_TMP/fx"; CACHE="$T_TMP/cache"; GH="$T_TMP/gh"
mkdir -p "$FX" "$CACHE"
NOW=1790000000
R=o/r
fxname() { printf '%s/%s' "$FX" "$(printf '%s' "$1" | tr '/?&=' '____')"; }
cat > "$GH" <<'STUB'
#!/bin/sh
f="$FX/$(printf '%s' "$2" | tr '/?&=' '____')"
[ -z "${GH_LOG:-}" ] || printf '%s\n' "$2" >> "$GH_LOG"
[ "$1" = api ] && [ -f "$f" ] && cat "$f"
STUB
chmod +x "$GH"

# commits <sha...> — newest first, one hour apart, the tip landing $TIP_AGE seconds ago; each one's
# first parent is the next in the list, so a sha left OUT is a branch commit the walk must skip.
commits() {
  _i=0; _out=""
  for _s in "$@"; do
    _next="$(printf '%s\n' "$@" | sed -n "$((_i + 2))p")"
    _e=$((NOW - TIP_AGE - _i * 3600))
    _d="$(jq -rn --argjson t "$_e" '$t | todate')"
    _out="$_out$(jq -cn --arg s "$_s" --arg n "$_next" --arg d "$_d" \
      '{sha: $s, parents: (if $n == "" then [] else [{sha: $n}] end), commit: {committer: {date: $d}, message: ("commit " + $s + "\n\nbody")}}'),"
    _i=$((_i + 1))
  done
  printf '[%s]\n' "${_out%,}" > "$(fxname "repos/$R/commits?sha=main&per_page=100")"
}
# runs <sha:conclusion|sha:-status|sha:conclusion@s ...> — main's runs; `sha:-queued` has no conclusion yet,
# `@s` makes it a scheduled run (a later one in the list is a later one in time). PAD=1 fills the page to 100
# runs, the oldest newer than the tip, so a commit missing from it is genuinely outside the page.
runs() {
  _j="[]"; _k=0
  for _p in "$@"; do
    _s="${_p%%:*}"; _c="${_p#*:}"; _ev=push; _k=$((_k + 1)); _t="$(jq -rn --argjson t "$((NOW - 1800 + _k))" '$t | todate')"
    case "$_c" in *@s) _ev=schedule; _c="${_c%@s}" ;; esac
    case "$_c" in
      -*) _j="$(printf '%s' "$_j" | jq -c --arg s "$_s" --arg st "${_c#-}" --arg e "$_ev" --arg t "$_t" '. + [{head_sha: $s, conclusion: null, status: $st, event: $e, workflow_id: 7, created_at: $t}]')" ;;
      *)  _j="$(printf '%s' "$_j" | jq -c --arg s "$_s" --arg c "$_c" --arg e "$_ev" --arg t "$_t" '. + [{head_sha: $s, conclusion: $c, status: "completed", event: $e, workflow_id: 7, created_at: $t}]')" ;;
    esac
  done
  [ -z "${PAD:-}" ] || _j="$(printf '%s' "$_j" | jq -c --arg t "$(jq -rn --argjson t "$((NOW - 3600))" '$t | todate')" '. + [range(100) | {head_sha: "zz", conclusion: "success", status: "completed", event: "push", workflow_id: 7, created_at: $t}]')"
  printf '{"workflow_runs":%s}\n' "$_j" > "$(fxname "repos/$R/actions/runs?branch=main&per_page=100")"
}
# byrun <sha> <conclusion|none> — the by-sha answer for a commit the list page did not carry.
byrun() {
  if [ "$2" = none ]; then _w='[]'; else _w='[{"head_sha":"'"$1"'","conclusion":"'"$2"'","status":"completed","event":"push","workflow_id":7}]'; fi
  printf '{"workflow_runs":%s}\n' "$_w" > "$(fxname "repos/$R/actions/runs?head_sha=$1&per_page=20")"
}
# wfstate <state> — the repo's workflows list: one workflow, id 7, in that state (an unrelated active one beside it).
wfstate() { printf '{"workflows":[{"id":7,"state":"%s"},{"id":9,"state":"active"}]}\n' "$1" > "$(fxname "repos/$R/actions/workflows?per_page=100")"; }
run() { FX="$FX" HARBOR_GH="$GH" HARBOR_TIP_REPO="$R" HARBOR_TIP_STRICT="$R" HARBOR_CACHE_DIR="$CACHE" HARBOR_RECEIPTS="$CACHE/checks" HARBOR_NOW="${AT:-$NOW}" \
          sh "$T_ROOT/bin/main-tip-verdict.sh" "$@"; }
get() { jq -r ".repos[0] | $1" "$CACHE/main-tip-verdict.json"; }
getr() { jq -r ".repos[] | select(.repo == \"$1\") | $2" "$CACHE/main-tip-verdict.json"; }   # one repo's field in the fleet cache
reset() { rm -f "$CACHE/main-tip-verdict.json" "$CACHE/checks.log"; AT=$NOW; wfstate active; unset PAD; }
# the fleet run: the fixture repos come from `repo` lines in the config, the way ci-runners reads them
CFGD="$T_TMP/cfg"; mkdir -p "$CFGD"; printf '[]\n' > "$T_TMP/snap.json"
# Harbor's own slug is named by log-lib's repo_slug (harbor#1149): the fleet cases run a copy laid out as runtime-install lays it, with
# the pin beside it, so the slug is o/harbor whatever remote this checkout has.
MTI="$T_TMP/inst/bin"; mkdir -p "$MTI"; cp "$T_ROOT/bin/main-tip-verdict.sh" "$T_ROOT/bin/log-lib.sh" "$MTI/"; printf '# pin\no/harbor\n' > "$MTI/repo-slug.txt"
fleet() { FX="$FX" HARBOR_GH="$GH" HARBOR_CACHE_DIR="$CACHE" HARBOR_RECEIPTS="$CACHE/checks" HARBOR_NOW="${AT:-$NOW}" CLAUDE_CONFIG_DIR="$CFGD" HARBOR_FLEET_SNAPSHOT="$T_TMP/snap.json" \
          sh "$MTI/main-tip-verdict.sh" "$@"; }
TIP_AGE=$((3 * 3600))

t_section "control: an all-green history does not alarm"
reset; commits a1 a2 a3 a4; runs a1:success a2:success a3:success a4:success
t_exit "a green history writes the cache and exits 0" 0 run
t_eq "the tip reads green" green "$(get .tip.verdict)"
t_eq "a green tip is not red" false "$(get .tip.red)"
t_eq "no commit is non-green" 0 "$(get .nongreen)"
t_eq "every commit in the window is judged" 4 "$(get .window)"
t_eq "a green history stamps nothing in checks.log" no "$([ -s "$CACHE/checks.log" ] && echo yes || echo no)"
t_exit "--print exits 0 on a green tip" 0 run --print
t_eq "its receipt is green, with no subjects (harbor#896)" "green 0" "$(jq -r '"\(.status) \(.subjects | length)"' "$CACHE/checks/main-tip-verdict.json")"

t_section "planted: a failed tip is RED, with its age"
reset; runs a1:failure a2:success a3:success a4:success
run
t_eq "the tip reads failed" failed "$(get .tip.verdict)"
t_eq "a failed tip is red" true "$(get .tip.red)"
t_eq "it has been red for the three hours since it landed" 10800 "$(get .tip.red_for)"
t_eq "its receipt is red over the non-green commit's short sha" 'red ["r:a1"]' "$(jq -c -r '"\(.status) \(.subjects | tojson)"' "$CACHE/checks/main-tip-verdict.json")"
rm -f "$CACHE/checks/main-tip-verdict.json"; run --print >/dev/null 2>&1 || :
t_eq "--print leaves no receipt" no "$([ -f "$CACHE/checks/main-tip-verdict.json" ] && echo yes || echo no)"
run
t_exit "--print exits 1 on a red tip" 1 run --print
P="$(run --print || true)"
t_has "--print says RED and for how long" "$P" 'RED for 3h'
t_has "--print names the tip" "$P" 'main tip a1'
t_has "a red tip stamps one line in checks.log under its registry id" "$(cat "$CACHE/checks.log")" '[check:main-tip-verdict]'

t_section "planted: cancelled-only and no-run tips are RED; a green one next to them is not"
reset; runs a1:cancelled a2:success a3:success a4:success; run
t_eq "a cancelled-only tip is red" cancelled-only "$(get .tip.verdict)"
t_eq "…and red" true "$(get .tip.red)"
reset; runs a1:cancelled a1:failure a2:success a3:success a4:success; run
t_eq "a failure beside a cancellation is failed, not cancelled" failed "$(get .tip.verdict)"
reset; runs a1:cancelled a1:success a2:success a3:success a4:success; run
t_eq "a later green run supersedes a cancelled one" green "$(get .tip.verdict)"
reset; PAD=1 runs a2:success a3:success a4:success; byrun a1 none; run
t_eq "a tip with no run at all is no-run" no-run "$(get .tip.verdict)"
t_eq "…and red" true "$(get .tip.red)"
reset; PAD=1 runs a2:success a3:success a4:success; byrun a1 success; run
t_eq "a tip missing from the list page but green by sha is GREEN (the page-edge false negative)" green "$(get .tip.verdict)"

t_section "a fresh commit is given time; a stuck run is not"
TIP_AGE=120; commits a1 a2 a3 a4; reset; runs a2:success a3:success a4:success; byrun a1 none; run
t_eq "a two-minute-old commit with no run yet is pending" pending "$(get .tip.verdict)"
t_eq "…and not red" false "$(get .tip.red)"
TIP_AGE=1800; commits a1 a2 a3 a4; reset; runs a1:-in_progress a2:success a3:success a4:success; run
t_eq "a run in progress for half an hour is pending, not red" false "$(get .tip.red)"
TIP_AGE=$((3 * 3600)); commits a1 a2 a3 a4; reset; runs a1:-in_progress a2:success a3:success a4:success; run
t_eq "a run still in progress after three hours is stuck, and red" true "$(get .tip.red)"

t_section "only the tip is red; older non-green commits are counted, not alarmed"
reset; runs a1:success a2:failure a3:cancelled a4:success; run
t_eq "a green tip over a red commit is not red" false "$(get .tip.red)"
t_eq "the two non-green commits are counted" 2 "$(get .nongreen)"
t_eq "a first run is a baseline and reports nothing new" 0 "$(get '.new | length')"
t_eq "…and says so" true "$(get .baseline)"
P="$(run --print)"
t_has "--print names a green-tipped repo on one line, not as a census" "$P" 'green: r'
t_eq "…and does not list its older non-green commits" 0 "$(printf '%s\n' "$P" | grep -c 'on file')"

t_section "the delta: new since last run, and standing ones are not repeated"
reset; runs a1:success a2:success a3:success a4:success; run
commits n1 a1 a2 a3 a4; AT=$((NOW + 300)); runs n1:failure a1:success a2:success a3:success a4:success; run
t_eq "a commit that went non-green since last run is new" 1 "$(get '.new | length')"
t_eq "…and is the tip" n1 "$(get '.new[0].sha')"
t_eq "…so one line is stamped" 1 "$(wc -l < "$CACHE/checks.log" | tr -d ' ')"
t_has "…and it names the new commit and its verdict" "$(cat "$CACHE/checks.log")" 'n1 failed'
AT=$((NOW + 600)); run
t_eq "the same state one tick later has nothing new" 0 "$(get '.new | length')"
t_eq "…the failure is standing, not repeated" 1 "$(get .nongreen)"
t_eq "…and the log did not grow" 1 "$(wc -l < "$CACHE/checks.log" | tr -d ' ')"
t_has "--print reports the delta first" "$(run --print || true)" '0 new non-green since last run'
t_eq "--print writes nothing" 1 "$(wc -l < "$CACHE/checks.log" | tr -d ' ')"
commits n2 n1 a1 a2 a3 a4; AT=$((NOW + 900)); runs n2:cancelled n1:failure a1:success a2:success a3:success a4:success; run
t_eq "a second non-green is one new, beside the standing one" 1 "$(get '.new | length')"
t_eq "…the standing one is still counted" 2 "$(get .nongreen)"
t_eq "…a second line is stamped" 2 "$(wc -l < "$CACHE/checks.log" | tr -d ' ')"
AT=$((NOW + 1200)); runs n2:cancelled n1:success a1:success a2:success a3:success a4:success; run
t_eq "a failed commit re-run to green is cleared" 1 "$(get '.cleared | length')"

t_section "a branch commit beside a merge has no run of its own and is not judged"
TIP_AGE=$((3 * 3600)); commits m1 m2 m3; reset
jq -c '.[0].parents = [{sha:"m2"},{sha:"br"}] | . + [{sha:"br",parents:[{sha:"m3"}],commit:{committer:{date:"2026-09-01T00:00:00Z"},message:"branch"}}]' \
  "$(fxname "repos/$R/commits?sha=main&per_page=100")" > "$T_TMP/c.json" && mv "$T_TMP/c.json" "$(fxname "repos/$R/commits?sha=main&per_page=100")"
runs m1:success m2:success m3:success; run
t_eq "the walk follows the first parent only" 3 "$(get .window)"
t_eq "a branch commit with no run is not a no-run" 0 "$(get .nongreen)"

t_section "a failed read is never read as green"
commits a1 a2 a3 a4; reset; runs a1:failure a2:success a3:success a4:success; run
rm -f "$(fxname "repos/$R/actions/runs?branch=main&per_page=100")"
AT=$((NOW + 300))
t_exit "an unanswered read, no red judged, exits 3 (D-29 unchecked), not the 1 of a red tip" 3 run
t_eq "the previous cache is kept" failed "$(get .tip.verdict)"
t_eq "…and flagged unread" true "$(get .unread)"
t_eq "its receipt says stood-down: GitHub did not answer, nothing was judged" stood-down "$(jq -r .status "$CACHE/checks/main-tip-verdict.json")"
t_has "--print says UNREAD" "$(run --print || true)" 'UNREAD'
rm -f "$CACHE/main-tip-verdict.json"; run || true
t_eq "no cache to keep still writes an unread marker" true "$(get .unread)"
t_exit "--print with nothing read and nothing red exits 3 (D-29 unchecked)" 3 run --print
t_exit "an unknown option is a usage error, 2" 2 run --bogus
t_exit "a second option is no different" 2 run --print --bogus
# CONTRACTS/logging.md: a usage error is not a run. Its words go to stderr, so a --print caller's stdout stays data.
run --print --bogus > "$T_TMP/u.out" 2> "$T_TMP/u.err" || :
t_eq "usage leaves stdout empty" "" "$(cat "$T_TMP/u.out")"
t_has "...and is said on stderr" "$(cat "$T_TMP/u.err")" 'unexpected argument --bogus'
t_eq "...with no summary line on either stream, because it is not a run" "" "$(cat "$T_TMP/u.out" "$T_TMP/u.err" | grep -E '^main-tip-verdict: [0-9]+ ok' || :)"
run --bogus > "$T_TMP/u.out" 2> "$T_TMP/u.err" || :
t_eq "an unknown first option is the same" "" "$(cat "$T_TMP/u.out")"
t_has "...named on stderr" "$(cat "$T_TMP/u.err")" 'unknown option --bogus'
t_eq "valid: --print on a read tip still puts its verdict on stdout" yes "$(run --print 2>/dev/null | grep -q . && echo yes || echo no)"
mkdir -p "$T_TMP/nojq"; for _c in dirname cat date mktemp rm mkdir sed awk tr head wc id uname; do _p="$(command -v $_c)"; [ -z "$_p" ] || ln -sf "$_p" "$T_TMP/nojq/$_c"; done
_nj="$(PATH="$T_TMP/nojq" /bin/sh "$T_ROOT/bin/main-tip-verdict.sh" 2>&1; echo "rc=$?")"
t_has "no jq on PATH: the run is blind, so it exits 3 (D-29 unchecked)" "$_nj" 'rc=3'
t_has "...and says nothing was judged" "$_nj" 'nothing was judged'

# ═══ the fleet (harbor#1088): every repo the fleet lists, one verdict each ═══════════════════════
t_section "fleet: the repos come from the snapshot (workflows + github origin) and the config's repo lines"
printf 'repo o/green\nrepo o/sched\nrepo o/off\nrepo o/gone\n' > "$CFGD/.harbor-ci-runners"
mkdir -p "$T_TMP/p/snap/.github/workflows" "$T_TMP/p/nowf"
git -C "$T_TMP/p/snap" init -q && git -C "$T_TMP/p/snap" remote add origin https://github.com/o/snap.git
git -C "$T_TMP/p/nowf" init -q && git -C "$T_TMP/p/nowf" remote add origin https://github.com/o/nowf.git
printf '[{"descriptor":{"name":"snap","path":"%s"}},{"descriptor":{"name":"nowf","path":"%s"}}]\n' "$T_TMP/p/snap" "$T_TMP/p/nowf" > "$T_TMP/snap.json"
TIP_AGE=$((3 * 3600))
fixrepo() { R="o/$1"; shift; commits "$@"; }
reset
R=o/harbor; commits h1 h2; wfstate active; runs h1:success h2:success   # harbor is always in the fleet
fixrepo green g1 g2; wfstate active; runs g1:success g2:success
fixrepo snap n1 n2; wfstate active; runs n1:success n2:success
fixrepo sched s1 s2; wfstate active; runs s1:success s1:failure@s s2:success
fixrepo off d1 d2; wfstate disabled_manually; runs d1:cancelled d2:cancelled
GH_LOG="$T_TMP/calls.log"; export GH_LOG; : > "$GH_LOG"; AT=$NOW
t_exit "a fleet run with a red repo and an unread one exits 1" 1 fleet
t_eq "the fleet is harbor, the snapshot's repo with workflows, and the config's lines, no more" "o/gone o/green o/harbor o/off o/sched o/snap" "$(jq -r '[.repos[].repo] | sort | join(" ")' "$CACHE/main-tip-verdict.json")"
t_eq "a snapshot repo with no .github/workflows is never asked" 0 "$(grep -c 'o/nowf' "$GH_LOG" | tr -d ' ')"

t_section "fleet: green, failed-scheduled, disabled, unread — one verdict each"
t_eq "a green repo is green and not red" "green false" "$(getr o/green '"\(.tip.verdict) \(.tip.red)"')"
t_eq "a snapshot-derived repo is judged too" green "$(getr o/snap .tip.verdict)"
t_eq "a scheduled failure beside a green push run makes the commit failed" "failed true" "$(getr o/sched '"\(.tip.verdict) \(.tip.red)"')"
t_eq "…and its age counts from the tip's commit" 10800 "$(getr o/sched .tip.red_for)"
t_eq "a repo whose main workflows are all disabled is disabled, not red" "disabled false" "$(getr o/off '"\(.state) \(.tip.red)"')"
t_eq "a repo GitHub did not answer for is unread, never green" "unread true" "$(getr o/gone '"\(.state) \(.unread)"')"
t_eq "the cache says it has an unread repo" true "$(jq -r .unread "$CACHE/main-tip-verdict.json")"
t_eq "one line for the failed repo, one for the disabled repo, none for the rest" 2 "$(wc -l < "$CACHE/checks.log" | tr -d ' ')"
t_has "the failed repo's line names it" "$(cat "$CACHE/checks.log")" '[check:main-tip-verdict]'
t_has "…and says tip s1 failed" "$(cat "$CACHE/checks.log")" 'o/sched tip s1 failed'
t_has "the disabled repo is reported as such, once" "$(cat "$CACHE/checks.log")" 'o/off main CI disabled'
t_eq "its receipt is red over the failed repo's commit, name-prefixed" 'red ["sched:s1"]' "$(jq -c -r '"\(.status) \(.subjects | tojson)"' "$CACHE/checks/main-tip-verdict.json")"

t_section "fleet: --print is the delta; a green repo is a word, not a block"
P="$(AT=$NOW fleet --print || true)"
t_has "the failed repo is named with its age" "$P" 'o/sched main tip s1'
t_has "…RED for 3h" "$P" 'RED for 3h'
t_has "the disabled repo is said once" "$P" 'o/off: main CI disabled'
t_has "the unread repo says UNREAD" "$P" 'o/gone: UNREAD'
t_has "green repos are one line" "$P" 'green: harbor snap green'
t_eq "a green repo gets no block of its own" 0 "$(printf '%s\n' "$P" | grep -c 'o/green')"
t_exit "--print exits 1 while a tip is red" 1 fleet --print

t_section "fleet: delta across two runs, and the call budget while nothing changed"
: > "$GH_LOG"; AT=$((NOW + 300)); fleet >/dev/null 2>&1 || :
t_eq "the same state five minutes on stamps nothing new" 2 "$(wc -l < "$CACHE/checks.log" | tr -d ' ')"
t_eq "…and the failed repo has nothing new" 0 "$(getr o/sched '.new | length')"
t_eq "the disabled repo costs no call inside the hour" 0 "$(grep -c 'o/off' "$GH_LOG" | tr -d ' ')"
t_eq "a green repo with an unchanged tip costs one call (the commits read)" 1 "$(grep -c 'o/green' "$GH_LOG" | tr -d ' ')"
t_eq "a red repo is read in full each tick: commits, runs, workflows" 3 "$(grep -c 'o/sched' "$GH_LOG" | tr -d ' ')"
t_eq "a repo that did not answer keeps its entry and is still unread" "unread" "$(getr o/gone .state)"
t_eq "an hour on, a green repo is read in full again (a nightly run can turn it red)" 2 "$(AT=$((NOW + 4000)); : > "$GH_LOG"; fleet >/dev/null 2>&1 || :; grep -c 'o/green' "$GH_LOG" | tr -d ' ')"

t_section "fleet: a new failure is one new line; a later scheduled success clears the old one"
fixrepo green n0 g1 g2; wfstate active; runs n0:failure g1:success g2:success
AT=$((NOW + 4300)); fleet >/dev/null 2>&1 || :
t_eq "the repo that just went red is new, the others are not" "1 0" "$(getr o/green '.new | length') $(getr o/sched '.new | length')"
t_has "…and one line is stamped for it" "$(tail -1 "$CACHE/checks.log")" 'o/green tip n0 failed'
fixrepo sched s1 s2; runs s1:success s1:failure@s s1:success@s s2:success
AT=$((NOW + 4600)); fleet >/dev/null 2>&1 || :
t_eq "a later scheduled success on the same tip clears the scheduled failure" "green false" "$(getr o/sched '"\(.tip.verdict) \(.tip.red)"')"
t_eq "…and the repo's red commit is cleared, not standing" 1 "$(getr o/sched '.cleared | length')"
unset GH_LOG

t_section "fleet: a repo with no push or schedule run on main has no CI to judge"
reset; printf 'repo o/noci\n' > "$CFGD/.harbor-ci-runners"; printf '[]\n' > "$T_TMP/snap.json"
R=o/harbor; commits h1 h2; runs h1:success h2:success
fixrepo noci c1 c2; wfstate active; runs; fleet >/dev/null 2>&1 || :
t_eq "it is no-ci, not red forever" "no-ci false" "$(getr o/noci '"\(.state) \(.tip.red)"')"

t_section "fleet: a path-filtered repo's run-less commit is not judged; the newest commit that ran is (harbor#1088)"
reset; printf 'repo o/paths\nrepo o/pathsred\nrepo o/nowhere\n' > "$CFGD/.harbor-ci-runners"
R=o/harbor; commits h1 h2; runs h1:success h2:success
fixrepo paths p1 p2 p3; wfstate active; runs p2:success p3:success
fixrepo pathsred q1 q2 q3; wfstate active; runs q2:failure q3:success
fixrepo nowhere w1 w2; wfstate active; runs h1:success
fleet >/dev/null 2>&1 || :
t_eq "a tip with no run, over a green run commit, is green and not red" "green false p2" "$(getr o/paths '"\(.tip.verdict) \(.tip.red) \(.tip.sha)"')"
t_eq "…the run-less commit is unjudged, not a no-run" 1 "$(getr o/paths '.counts.unjudged')"
t_eq "…and stamps nothing for it" 0 "$(grep -c 'o/paths tip' "$CACHE/checks.log" | tr -d ' ')"
t_eq "a run-less tip over a FAILED run commit is red, named after that commit" "failed true q2" "$(getr o/pathsred '"\(.tip.verdict) \(.tip.red) \(.tip.sha)"')"
t_has "…and its line names that commit" "$(cat "$CACHE/checks.log")" 'o/pathsred tip q2 failed'
t_eq "a repo with no run on any commit in the window is no-ci" "no-ci false" "$(getr o/nowhere '"\(.state) \(.tip.red)"')"
t_eq "harbor stays strict: a run-less harbor tip IS red" "no-run true" "$(R=o/harbor; commits h0 h1 h2; runs h1:success h2:success; fleet >/dev/null 2>&1 || :; getr o/harbor '"\(.tip.verdict) \(.tip.red)"')"

t_section "fleet: harbor's own repository is named by repo_slug, never spelled in the script (harbor#1149)"
reset; printf '[]\n' > "$T_TMP/snap.json"; : > "$CFGD/.harbor-ci-runners"
R=other/fork; commits f1 f2; wfstate active; runs f1:success f2:success
TREE="$T_TMP/tree"; mkdir -p "$TREE/bin" "$TREE/CONTRACTS"; cp "$T_ROOT/bin/main-tip-verdict.sh" "$T_ROOT/bin/log-lib.sh" "$TREE/bin/"
printf 'o/pinned\n' > "$TREE/CONTRACTS/repo-slug.txt"; git -C "$TREE" init -q; git -C "$TREE" remote add origin https://github.com/other/fork.git
GH_LOG="$T_TMP/calls2.log"; export GH_LOG; : > "$GH_LOG"
FX="$FX" HARBOR_GH="$GH" HARBOR_CACHE_DIR="$CACHE" HARBOR_RECEIPTS="$CACHE/checks" HARBOR_NOW="$NOW" CLAUDE_CONFIG_DIR="$CFGD" HARBOR_FLEET_SNAPSHOT="$T_TMP/snap.json" \
  sh "$TREE/bin/main-tip-verdict.sh" >/dev/null 2>&1 || :
t_eq "a copy in a checkout judges that checkout's origin as harbor, not the pin" "other/fork" "$(jq -r '[.repos[].repo] | join(" ")' "$CACHE/main-tip-verdict.json")"
t_eq "...and asks GitHub about nothing else" 0 "$(grep -c 'o/pinned\|o/harbor' "$GH_LOG" | tr -d ' ')"
unset GH_LOG
NOPIN="$T_TMP/nopin/bin"; mkdir -p "$NOPIN"; cp "$T_ROOT/bin/main-tip-verdict.sh" "$T_ROOT/bin/log-lib.sh" "$NOPIN/"; rm -f "$CACHE/main-tip-verdict.json"
_np="$(FX="$FX" HARBOR_GH="$GH" HARBOR_CACHE_DIR="$CACHE" CLAUDE_CONFIG_DIR="$CFGD" HARBOR_FLEET_SNAPSHOT="$T_TMP/snap.json" sh "$NOPIN/main-tip-verdict.sh" 2>&1; echo "rc=$?")"
t_has "an install with no pin cannot name harbor: it judges nothing and exits 3 (unchecked)" "$_np" 'rc=3'
t_has "...and says why" "$_np" 'harbor'"'"'s own repository is not derivable'
t_eq "...and writes no verdict that would leave harbor out" no "$([ -f "$CACHE/main-tip-verdict.json" ] && echo yes || echo no)"
_np1="$(FX="$FX" HARBOR_GH="$GH" HARBOR_TIP_REPO=other/fork HARBOR_CACHE_DIR="$CACHE" HARBOR_RECEIPTS="$CACHE/checks" HARBOR_NOW="$NOW" sh "$NOPIN/main-tip-verdict.sh" 2>&1; echo "rc=$?")"
t_has "...unless HARBOR_TIP_REPO names the one repo to judge" "$_np1" 'rc=0'

t_done
