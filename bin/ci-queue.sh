#!/usr/bin/env sh
# ci-queue.sh (harbor#657) — how long until this box's CI runners are free: the
# jobs still to run, and when the last of them should finish, for the statusline.
#
#   sh ci-queue.sh            write $HARBOR_SCOPE_CACHE_DIR/ci-queue.json (default ~/.claude/cache)
#   sh ci-queue.sh --print    print one line per repo instead of writing the cache
#
# WHAT IT ANSWERS. "How long until CI is done" — asked 2026-09-23 while three
# runners worked through two overlapping runs, when the answer took five API
# reads and a schedule worked out by hand. status-fleet-glyph.sh renders it as ⏳N ·~Mm.
#
# THE REPOS ARE DERIVED, NEVER LISTED. Every running runner container's
# RUNNER_URL, and every <runner>/.runner under HARBOR_CI_RUNNERS_DIR (default
# ~/runners), names the repo it serves, and the number of runners per repo is the
# parallelism the estimate schedules against.
# Adding or removing a runner changes the estimate with no edit here.
#
# THE ESTIMATE. A job's typical length is the median of its last three successful
# runs in the same workflow. A running job has typical minus elapsed left, never
# below zero; a queued job waits for the earliest free runner. A run that has not
# listed its jobs yet is assumed to need its workflow's usual set. NOT MODELLED:
# `needs:` between jobs, so a job that waits on another reads as startable now and
# the estimate runs short — which is why the glyph prints it with a `~`. A job with
# no history takes the longest known typical, so an unknown job never shortens it.
#
# ABSOLUTE TIMES ONLY. The cache stores the epoch each repo should be free (`eta`),
# never a countdown: status-fleet-glyph.sh subtracts the clock at print time, as row 1
# does for the rate-limit reset (harbor#84), because the harness can skip or cancel
# any tick and a stored countdown is wrong by however long it was left standing.
#
# A REPO GITHUB WOULD NOT ANSWER FOR is written with "unread": true and renders as
# `?`: "could not look" must never read as "nothing running".
#
# A WEDGED RUNNER IS NOT A BUSY ONE (harbor#152). On 2026-08-06 six jobs sat
# `queued` for 25 minutes against a runner the API reported `online, busy=false`;
# the fault was only in the runner's own _diag log, and a service restart cleared
# it. Either fact alone is normal — a queue waits, an idle runner is idle — and
# only the conjunction is a stall: a SELF-HOSTED job queued over STALL_SEC (600)
# while at least one runner of this repo is online and not busy. It must hold on
# two refreshes in a row, because a runner idles about a minute between jobs
# (#279) and one sample would page on every handoff. A hosted job queued beside
# an idle self-hosted runner is not a stall: that runner could never take it.
#
# IT REPORTS AND NAMES THE REMEDY; IT NEVER RESTARTS ANYTHING. A restart is a
# self-healing act on live infrastructure from an unreviewed signal, and the
# 2026-08-06 outage was server-side, where a restart loop would only flap. The
# runners endpoint needs repo admin; when it cannot be read the stall is UNKNOWN
# (`idle: null`) and the estimate above is untouched.
#
# Run by status-fleet-snapshot-refresh.sh every 300s. Writes atomically; on any failure
# the previous cache is kept. POSIX sh, jq, gh (HARBOR_TEST_GH swaps in a fake).
set -eu

case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/library-log.sh"
log_init ci-queue
PRINT=0
case "${1:-}" in
  --print) PRINT=1 ;;
  "") ;;
  *) log_fail "unknown option $1"; log_fix "sh $0 --help"; log_end || :; exit 2 ;;
esac

RUNNERS_DIR="${HARBOR_CI_RUNNERS_DIR:-${HARBOR_RUNNERS_DIR:-$HOME/runners}}"
CACHE_DIR="${HARBOR_SCOPE_CACHE_DIR:-${HARBOR_CACHE_DIR:-$HOME/.claude/cache}}"
OUT="$CACHE_DIR/ci-queue.json"
NOW="${HARBOR_TEST_NOW:-${HARBOR_NOW:-$(date +%s)}}"
GH="${HARBOR_TEST_GH:-${HARBOR_GH:-gh}}"
DOCKER="${HARBOR_CI_DOCKER:-${HARBOR_DOCKER:-docker}}"
STALL_SEC="${HARBOR_CI_STALL_SEC:-600}"
STALL_CONFIRM=240   # a second refresh, less jitter: 300s apart, never one sample
command -v jq >/dev/null 2>&1 || { log_fail "jq is required and is not on PATH"; log_fix "$(pkg_hint jq)"; log_end || :; exit 2; }

T="$(mktemp -d "${TMPDIR:-/tmp}/ci-queue.XXXXXX")"
trap 'rm -rf "$T"' EXIT INT TERM

api() { "$GH" api "$1" 2>/dev/null; }   # <endpoint> -> JSON on stdout, nonzero on failure

# owner/repo, once per runner folder. The runner writes .runner with a UTF-8
# byte-order mark; it is stripped here rather than trusting every jq to skip it.
# UNPROVEN ON THIS BOX: jq 1.7 already skips the mark, so ci-queue-test.sh stays
# green with the `tr` removed (measured 2026-09-23). The strip is for an older jq,
# and no suite here can show it doing anything.
: > "$T/repos"
for _f in "$RUNNERS_DIR"/*/.runner; do
  [ -f "$_f" ] || continue
  tr -d '\357\273\277' < "$_f" | jq -r '.gitHubUrl // empty' 2>/dev/null \
    | sed -n 's#^https://github\.com/\([^/][^/]*/[^/][^/]*\)/*$#\1#p' >> "$T/repos" || :
done
# Runner CONTAINERS (the fleet since ci-runners.sh, harbor#1060) carry no .runner on the host: each names its repo in
# RUNNER_URL. Read only from .runner folders, the queue was empty while every runner was busy (2026-10-27). A gate
# container runs gate jobs only, so it is not parallelism here; an org URL names no repo; docker down adds nothing.
for _c in $("$DOCKER" ps --format '{{.Names}}' 2>/dev/null); do
  case "$_c" in *-gate|*-gate-[0-9]) continue ;; esac
  "$DOCKER" inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$_c" 2>/dev/null \
    | sed -n 's#^RUNNER_URL=https://github\.com/\([^/][^/]*/[^/][^/]*\)/*$#\1#p' >> "$T/repos" || :
done

: > "$T/out.jsonl"
sort "$T/repos" | uniq -c > "$T/counts"
while read -r _n _repo; do
  [ -n "$_repo" ] || continue
  _ok=1
  api "repos/$_repo/actions/runs?status=in_progress&per_page=50" > "$T/a.json" || _ok=0
  api "repos/$_repo/actions/runs?status=queued&per_page=50"      > "$T/b.json" || _ok=0
  # A RUN OLDER THAN A DAY IS A GHOST, NOT WORK. Measured 2026-09-23: a governance
  # run created 2026-08-06, the day of a GitHub Actions outage, still reads
  # `queued` with no jobs seven weeks later. Assumed to need its workflow's usual
  # set, it turned "1 job left" into "9 jobs, ~15m". Ghosts are counted, never
  # scheduled; `gh run cancel <id>` clears one.
  [ "$_ok" = 1 ] && jq -s --argjson now "$NOW" '[.[].workflow_runs[]?] | unique_by(.id)
      | map(. + {ghost: (((.created_at // "1970-01-01T00:00:00Z") | fromdateiso8601) < ($now - 86400))})' \
      "$T/a.json" "$T/b.json" > "$T/all.json" 2>/dev/null || _ok=0
  [ "$_ok" = 1 ] && jq 'map(select(.ghost | not))' "$T/all.json" > "$T/runs.json" || _ok=0
  _ghosts=0; [ "$_ok" = 1 ] && _ghosts="$(jq '[.[] | select(.ghost)] | length' "$T/all.json")"

  : > "$T/jobs.jsonl"; : > "$T/hist.jsonl"
  if [ "$_ok" = 1 ]; then
    for _id in $(jq -r '.[].id' "$T/runs.json"); do
      _wf="$(jq -r --argjson id "$_id" '.[] | select(.id == $id) | .workflow_id' "$T/runs.json")"
      api "repos/$_repo/actions/runs/$_id/jobs?per_page=100" > "$T/j.json" || { _ok=0; break; }
      jq -c --argjson run "$_id" --argjson wf "$_wf" \
        '.jobs[]? | {run: $run, wf: $wf, name, status, started_at, created_at, labels}' "$T/j.json" >> "$T/jobs.jsonl" || { _ok=0; break; }
    done
  fi
  if [ "$_ok" = 1 ]; then
    for _wf in $(jq -r '[.[].workflow_id] | unique | .[]' "$T/runs.json"); do
      api "repos/$_repo/actions/workflows/$_wf/runs?status=success&per_page=3" > "$T/h.json" || { _ok=0; break; }
      for _hid in $(jq -r '.workflow_runs[]?.id' "$T/h.json"); do
        api "repos/$_repo/actions/runs/$_hid/jobs?per_page=100" > "$T/hj.json" || { _ok=0; break; }
        jq -c --argjson wf "$_wf" '.jobs[]?
            | select(.conclusion == "success" and .started_at != null and .completed_at != null)
            | {wf: $wf, name, dur: ((.completed_at | fromdateiso8601) - (.started_at | fromdateiso8601))}' \
          "$T/hj.json" >> "$T/hist.jsonl" || { _ok=0; break; }
      done
      [ "$_ok" = 1 ] || break
    done
  fi

  if [ "$_ok" != 1 ]; then
    jq -cn --arg repo "$_repo" --argjson n "$_n" '{repo: $repo, runners: $n, unread: true}' >> "$T/out.jsonl"
    continue
  fi
  jq -s . "$T/jobs.jsonl" > "$T/jobs.json"
  jq -s . "$T/hist.jsonl" > "$T/hist.json"
  # The idle runners, by name, or null when the endpoint will not answer. Kept
  # apart from _ok on purpose: an unreadable runner list costs the stall verdict,
  # never the estimate.
  if api "repos/$_repo/actions/runners?per_page=100" > "$T/rn.json" \
     && jq -e '.runners' "$T/rn.json" >/dev/null 2>&1; then
    jq -c '[.runners[] | select(.status == "online" and .busy == false)
             | {name, labels: [.labels[]?.name | ascii_downcase]}]' "$T/rn.json" > "$T/idle.json"
  else
    printf 'null\n' > "$T/idle.json"
  fi
  # A SUSPICION IS CARRIED ONLY ACROSS ONE REFRESH (Codex on #699). If the box
  # slept, the last cache can be hours old, and reusing its suspect_since would
  # turn the first sample after waking into a "second" observation. So the
  # previous cache must be at most two refresh intervals (600s) old, or the
  # suspicion starts again from now.
  _since="$(jq -r --arg r "$_repo" --argjson now "$NOW" '
      if ($now - ((.at // 0) | tonumber)) > 600 then empty
      else (.repos[]? | select(.repo == $r) | .suspect_since // empty) end' "$OUT" 2>/dev/null || :)"
  case "$_since" in ''|*[!0-9]*) _since=null ;; esac
  jq -cn --arg repo "$_repo" --argjson n "$_n" --argjson now "$NOW" --argjson ghosts "$_ghosts" \
      --argjson stallsec "$STALL_SEC" --argjson confirm "$STALL_CONFIRM" --argjson since "$_since" \
      --slurpfile idle "$T/idle.json" \
      --slurpfile runs "$T/runs.json" --slurpfile jobs "$T/jobs.json" --slurpfile hist "$T/hist.json" '
    def median: sort | .[((length - 1) / 2) | floor];
    ($runs[0]) as $runs | ($jobs[0]) as $jobs | ($hist[0]) as $hist
    | ($hist | group_by([.wf, .name])
        | map({key: "\(.[0].wf)/\(.[0].name)", value: (map(.dur) | median)}) | from_entries) as $typ
    | ([$typ[]] | max // 600) as $longest
    # A run that has not listed its jobs yet needs its workflow usual set.
    | def typ($wf; $name): $typ["\($wf)/\($name)"] // $longest;
      [$runs[] | .id as $id | .workflow_id as $wf
        | select([$jobs[] | select(.run == $id)] | length == 0)
        | ($hist | map(select(.wf == $wf) | .name) | unique)[]
        | {run: $id, wf: $wf, name: ., status: "queued"}] as $implied
    | [($jobs + $implied)[] | select(.status != "completed")] as $left
    | [$left[] | select(.status == "in_progress")
        | if .started_at == null then typ(.wf; .name)
          else ([typ(.wf; .name) - ($now - (.started_at | fromdateiso8601)), 0] | max) end] as $busy
    | [$left[] | select(.status != "in_progress") | typ(.wf; .name)] as $wait
    # Runner free times, as seconds from now: the busy ones, then the idle ones.
    | (($busy + ([range(0; ([$n - ($busy | length), 0] | max))] | map(0))) | sort) as $free
    | (reduce $wait[] as $d ($free; (.[0] + $d) as $x | (.[1:] + [$x]) | sort)) as $end
    | ($idle[0]) as $idle
    | [$jobs[] | select(.status == "queued" and .created_at != null
          and ($now - (.created_at | fromdateiso8601)) >= $stallsec)] as $old
    # ONLY A RUNNER THAT COULD TAKE THE JOB (Codex on #699): its labels must
    # cover the job labels, compared case-blind as GitHub does. This is also what
    # keeps a HOSTED job out: no self-hosted runner carries ubuntu-latest. A
    # separate self-hosted filter was redundant beside it, and a mutant removing
    # it survived every case, so it went. An idle Linux runner
    # beside a queued macOS job is not a stall, and restarting it would help nothing.
    | [($idle // [])[] | .labels as $rl
        | select(any($old[]; ([(.labels // [])[] | ascii_downcase] - $rl) | length == 0))] as $able
    | ($idle != null and ($able | length) > 0) as $suspect
    | (if $suspect then ($since // $now) else null end) as $ssince
    | {repo: $repo, runners: $n, left: ($left | length), ghosts: $ghosts,
       eta: (if ($left | length) == 0 then null else $now + (($end | max) // 0) end),
       idle: (if $idle == null then null else [$idle[].name] end),
       able: [$able[].name], stale_queued: ($old | length), suspect_since: $ssince,
       stall: ($suspect and ($now - $ssince) >= $confirm)}' \
    >> "$T/out.jsonl"
done < "$T/counts"

# One line per repo, as "<tag><TAB><message>"; the shell turns each into the library's own line.
jq -r --argjson now "$NOW" --argjson stallsec "$STALL_SEC" '
  if .unread then "warn\t\(.repo)  runners=\(.runners)  UNREAD — GitHub did not answer", "fix\tgh auth status  # then rerun: sh bin/ci-queue.sh --print"
  elif .left == 0 then "ok\t\(.repo)  runners=\(.runners)  idle"
  else "ok\t\(.repo)  runners=\(.runners)  jobs left=\(.left)  done in ~\(((.eta - $now) / 60) | ceil)m" end,
  (if (.ghosts // 0) > 0 then "warn\t\(.repo)  \(.ghosts) ghost run(s) over a day old, not counted", "fix\tgh run list -R \(.repo) -s queued  # then gh run cancel <id>" else empty end),
  (if .stall == true then
     "warn\t\(.repo)  STALL: \(.stale_queued) self-hosted job(s) queued over \($stallsec / 60 | floor)m while \(.able | join(", ")) — able to take it — sat IDLE, on two refreshes — wedged, not busy (harbor#152); an idle runner is running nothing, so restarting it kills no job",
     "fix\tcd ~/runners/\(.able[0]) && ./svc.sh stop && ./svc.sh start",
     "note\tif the job was CANCELLED instead, sh bin/ci-lost-job.sh reads why (harbor#675)"
   elif .suspect_since != null then "note\t\(.repo)  a queued job and an idle runner since \(.suspect_since | todate): a stall if the next refresh agrees"
   else empty end)' \
  "$T/out.jsonl" > "$T/log.tsv"
log_head "$([ "$PRINT" = 1 ] && echo 'queue per repo' || echo 'queue per repo, written to the cache')"
TAB="$(printf '\t')"
while IFS="$TAB" read -r _tag _msg; do
  case "$_tag" in
    ok) log_ok "$_msg" ;;
    warn) log_warn "$_msg" ;;
    fix) log_fix "$_msg" ;;
    note) log_note "$_msg" ;;
  esac
done < "$T/log.tsv"
[ -s "$T/log.tsv" ] || log_note "no runner under $RUNNERS_DIR names a repo"

if [ "$PRINT" = 1 ]; then
  log_end; exit $?
fi

if mkdir -p "$CACHE_DIR" && jq -s --argjson at "$NOW" '{at: $at, repos: .}' "$T/out.jsonl" > "$OUT.tmp.$$" \
   && mv -f "$OUT.tmp.$$" "$OUT"; then
  log_ok "wrote $OUT"
else
  rm -f "$OUT.tmp.$$" 2>/dev/null || :
  log_fail "could not write $OUT"
  log_fix "mkdir -p $CACHE_DIR && sh $0"
  log_end || :; exit 1
fi
log_end; exit $?
