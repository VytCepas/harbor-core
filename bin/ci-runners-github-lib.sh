#!/usr/bin/env sh
# ci-runners-github-lib.sh (harbor#1060) — what the runners do on GitHub: `switch` (CI_RUNS_ON), `rerun-refused`, `rerun-lost`.
# Sourced by ci-runners.sh, never run: it sets no shell option and reads the entry point's variables ($T, $CONF, $GH, $DOCKER, ...).
. "$(dirname -- "$0")/library-log.sh"   # a second source keeps the run's counts (library-log.sh)

# ── switch: CI_RUNS_ON follows the minutes rule ci-runner-switch.sh decided ───────────────────────
CHANGED=0
# owner_verdict <slug> — each owner's own minutes verdict: sets want and why, or fails when there is none fresh to trust
owner_verdict() {
  case "$1" in */*) _v="$CACHE_DIR/runner-switch.json" ;; *) _v="$CACHE_DIR/runner-switch.$1.json" ;; esac
  [ -f "$_v" ] && jq -e '.unread == false and (.runner == "self-hosted" or .runner == "github-hosted") and (.at | type == "number")' "$_v" >/dev/null 2>&1 \
    && [ "$((NOW - $(jq -r .at "$_v")))" -le 900 ] || return 1
  want="$(jq -r .runner "$_v")"; why="$(jq -r '"\(.used)/\(.allowance) minutes"' "$_v")"
}
# An org with N runners has N rows and one variable: a slug is decided once (_sd), on the first row that acts or skips,
# and self-hosted needs only one of its runners running and online.
do_switch() {
  CHANGED=0; _sd=" "
  while IFS="$TAB" read -r repo slug w c cstate _i runner _b _id cur verdict; do
    [ "$w" = 1 ] && [ "$verdict" != hold ] || continue
    case "$_sd" in *" $slug "*) continue ;; esac
    [ "$cstate" != absent ] || [ "$runner" = online ] || [ "$runner" = offline ] || continue
    _src="ci-runner-switch.sh"; case "$slug" in */*) ;; *) _src="ci-runner-switch.sh --org $slug" ;; esac
    owner_verdict "$slug" || { _sd="$_sd$slug "; log_skip "$slug: no fresh verdict from $_src; CI_RUNS_ON left as it is"; continue; }
    if [ "$want" = self-hosted ]; then
      [ "$cstate" = running ] && [ "$runner" = online ] && [ "$cur" != self-hosted ] && [ "$cur" != '?' ] || continue
      _sd="$_sd$slug "
      if [ "$APPLY" != 1 ]; then log_note "would set CI_RUNS_ON self-hosted on $slug"; continue; fi
      if var_set "$slug" >/dev/null 2>&1; then
        logline "$slug CI_RUNS_ON $cur -> self-hosted ($why)"; CHANGED=$((CHANGED + 1))
      else log_warn "$slug: the CI_RUNS_ON write failed"; log_fix "gh auth status"; fi
    else
      [ "$cur" = self-hosted ] || continue
      _sd="$_sd$slug "
      if [ "$APPLY" != 1 ]; then log_note "would unset CI_RUNS_ON on $slug"; continue; fi
      if var_del "$slug" >/dev/null 2>&1; then
        logline "$slug CI_RUNS_ON self-hosted -> unset ($why)"; CHANGED=$((CHANGED + 1))
      else log_warn "$slug: the CI_RUNS_ON delete failed"; log_fix "gh auth status"; fi
    fi
  done < "$T/rows.tsv"
  return 0
}

# the repos a self-hosted, online runner serves: its own repo, or every listed repo of its org
serve_targets() {
  : > "$T/targets"
  while IFS="$TAB" read -r repo slug w _c cstate _i runner _b _id cur verdict; do
    [ "$w" = 1 ] && [ "$cur" = self-hosted ] && [ "$cstate" = running ] && [ "$runner" = online ] || continue
    case "$slug" in */*) printf '%s\n' "$slug" >> "$T/targets" ;;
      *) awk -F'\t' -v o="$slug/" '$11 == "org" && index($2, o) == 1 { print $2 }' "$T/rows.tsv" >> "$T/targets" ;; esac
  done < "$T/rows.tsv"
  awk '!seen[$0]++' "$T/targets" > "$T/targets.u" && mv "$T/targets.u" "$T/targets"   # an org's N runners serve its repos once
}

# ── rerun-refused: runs GitHub refused for billing, once each, only where a local runner can now take them ──
do_rerun() {
  RERUNS="$CACHE_DIR/ci-reruns.tsv"; touch "$RERUNS"
  cut_at=$((NOW - 172800))
  # the phrase lives in ci-lost-job.sh, which merge-check and pr-wait read too (harbor#1060); an empty one would match every run
  BILLING="$(sh "$(dirname -- "$0")/ci-lost-job.sh" --billing-pattern 2>/dev/null)" || BILLING=""
  [ -n "$BILLING" ] || { log_warn "rerun-refused: no billing phrase from ci-lost-job.sh"; return 0; }
  serve_targets
  while read -r slug; do
    "$GH" run list -R "$slug" --limit 30 --json databaseId,conclusion,createdAt,headBranch,name > "$T/runs.json" 2>/dev/null || continue
    jq -r --argjson cut "$cut_at" '.[] | select(.conclusion == "failure" and ((.createdAt | fromdateiso8601) > $cut)) | .databaseId' "$T/runs.json" > "$T/ids" 2>/dev/null || continue
    while read -r id; do
      awk -v s="$slug" -v i="$id" '$1 == s && $2 == i { f = 1 } END { exit !f }' "$RERUNS" && continue
      "$GH" api "repos/$slug/actions/runs/$id/jobs" > "$T/jobs.json" 2>/dev/null || continue
      job="$(jq -r '[.jobs[] | select(.conclusion == "failure")][0].id // empty' "$T/jobs.json" 2>/dev/null)"; [ -n "$job" ] || continue
      "$GH" api "repos/$slug/check-runs/$job/annotations" 2>/dev/null | jq -r '.[].message' 2>/dev/null \
        | grep -Eqi "$BILLING" || continue
      if [ "$APPLY" != 1 ]; then log_note "would re-run $slug run $id (refused for billing)"; continue; fi
      if "$GH" run rerun "$id" -R "$slug" >/dev/null 2>&1; then
        printf '%s %s %s\n' "$slug" "$id" "$NOW" >> "$RERUNS"; logline "$slug run $id re-run (refused for billing)"; log_ok "$slug run $id re-run"
      else log_warn "$slug run $id: the re-run failed; it is tried again next time"; fi
    done < "$T/ids"
  done < "$T/targets"
  awk -v cut="$((NOW - 1209600))" '$3 > cut' "$RERUNS" > "$T/reruns.n" 2>/dev/null && cat "$T/reruns.n" > "$RERUNS" || :
}

# ── rerun-lost: a job the infrastructure lost, re-run once (operator decision 2026-10-06, harbor#675 and #1060, check ci-lost-rerun) ──
# Three shapes, all of a job that FAILED or was CANCELLED with no step concluded `failure` (a real test failure is
# never one, and its annotations are never read):
#   1. not acquired: no steps, and every annotation says no runner took it (harbor#675; GitHub cancels what it cannot dispatch);
#   2. no conclusion: a FAILED job (never a cancelled one) with a step that started and never concluded (conclusion null) and
#      no annotation (2026-10-06, run 37511778240: BrokerServer TaskCanceledException, "Every selected suite" left open); a cancel,
#      a timeout ("exceeded the maximum execution time") and a fail-fast sibling carry an open step too and are not this;
#   3. runner lost: every annotation is the runner's own lost-connection or shutdown text (ci-lost-job.sh --runner-pattern).
# ci-lost-job.sh is the ONE reader of the phrases (shape 1 by its exit 0, 3 by its pattern); a job that ran and failed,
# or carries any other annotation, is never touched. `--job`, not `--failed`: --failed would re-run a real failure beside it.
# Once: ci-lost-reruns.tsv (slug job run attempt ts) is written BEFORE the call, and only a run still on attempt 1 is
# looked at, so a re-run (ours or a person's) is never followed by another, whatever the second failure looks like.
# Two lost jobs in one run: the first is re-run, the rest are left to a person (pr-wait prints the command).
# API per tick: 1 run list a repo, then for each NEW failed/cancelled run of the last 48h (at most LOST_READS, default 20)
# 1 jobs read, plus 1 annotation read per failed/cancelled job that has no failed step; a run that held
# no such job is remembered in ci-lost-seen.tsv and never read again. An idle fleet costs one call a repo (plus one for
# the governance runner).
lostline() { printf '[check:ci-lost-rerun] %s %s\n' "$(iso "$NOW")" "$1" >> "$LOG" 2>/dev/null || :; }
do_rerun_lost() {
  [ "$(conf lost-rerun)" != off ] || return 0
  LOSTS="$CACHE_DIR/ci-lost-reruns.tsv"; SEEN="$CACHE_DIR/ci-lost-seen.tsv"; touch "$LOSTS" "$SEEN"
  LJ="$(dirname -- "$0")/ci-lost-job.sh"; cut_at=$((NOW - 172800)); reads="${HARBOR_CI_LOST_READS:-20}"
  # an empty phrase would match every job: no phrase from ci-lost-job.sh means no shape-3 re-run, and a warning
  RUNNER_RE="$(sh "$LJ" --runner-pattern 2>/dev/null)" || RUNNER_RE=""
  [ -n "$RUNNER_RE" ] || { log_warn "rerun-lost: no runner phrase from ci-lost-job.sh"; return 0; }
  serve_targets
  # the governance repo's own runner, which no fleet row covers: only when it is online
  _g="${GOV_REPO#*/}"
  if ! grep -qx "$GOV_REPO" "$T/targets"; then
    if [ ! -f "$T/rn.$_g.json" ]; then "$GH" api "repos/$GOV_REPO/actions/runners" > "$T/rn.$_g.json" 2>/dev/null || rm -f "$T/rn.$_g.json"; fi
    jq -e '[.runners[]? | select(.status == "online")] | length > 0' "$T/rn.$_g.json" >/dev/null 2>&1 && printf '%s\n' "$GOV_REPO" >> "$T/targets"
  fi
  while read -r slug; do
    "$GH" run list -R "$slug" --limit 30 --json databaseId,conclusion,createdAt,attempt > "$T/lruns.json" 2>/dev/null || continue
    jq -r --argjson cut "$cut_at" '.[] | select((.conclusion == "failure" or .conclusion == "cancelled") and (.attempt // 1) == 1
         and ((.createdAt | fromdateiso8601) > $cut)) | .databaseId' "$T/lruns.json" > "$T/lids" 2>/dev/null || continue
    while read -r id; do
      awk -v s="$slug" -v i="$id" '$1 == s && $2 == i { f = 1 } END { exit !f }' "$SEEN" && continue
      awk -v s="$slug" -v i="$id" '$1 == s && $3 == i { f = 1 } END { exit !f }' "$LOSTS" && continue
      [ "$reads" -gt 0 ] || break; reads=$((reads - 1))
      "$GH" api "repos/$slug/actions/runs/$id/jobs" > "$T/ljobs.json" 2>/dev/null || continue
      # a job with a failed step is a real failure: out. Each row: job id, step count, steps with no conclusion
      jq -r '.jobs[] | select((.conclusion == "failure" or .conclusion == "cancelled") and ([(.steps // [])[] | select(.conclusion == "failure")] | length) == 0)
             | [.id, ((.steps // []) | length), ([(.steps // [])[] | select(.conclusion == null)] | length), .conclusion] | @tsv' "$T/ljobs.json" > "$T/lcand" 2>/dev/null || continue
      lost=""; why=""; readfail=0
      while IFS="$TAB" read -r job nsteps nopen jconc; do
        [ -n "$job" ] || continue
        if [ "$nsteps" = 0 ]; then
          sh "$LJ" "$slug" "https://github.com/$slug/actions/runs/$id/job/$job" >/dev/null 2>&1 && rc=0 || rc=$?
          case "$rc" in 0) lost="$job"; why="not acquired by a runner"; break ;; 1) ;; 3) continue ;; *) readfail=1; continue ;; esac
        fi
        "$GH" api "repos/$slug/check-runs/$job/annotations" > "$T/lann.json" 2>/dev/null && jq -e 'type == "array"' "$T/lann.json" >/dev/null 2>&1 || { readfail=1; continue; }
        nann="$(jq 'length' "$T/lann.json")"
        if [ "$nann" -gt 0 ] && ! jq -r '.[].message' "$T/lann.json" | grep -Evqi "$RUNNER_RE"; then
          lost="$job"; why="runner lost its connection"; break
        # an open step is not enough: GitHub scores a human cancel, a timeout and a fail-fast sibling as `cancelled`, and a
        # timeout can read `failure`, each with an open step and its own annotation. Only a FAILED job that carries no
        # annotation at all (or only the runner's, above) was dropped by the infrastructure
        elif [ "$nopen" -gt 0 ] && [ "$jconc" = failure ] && [ "$nann" = 0 ]; then
          lost="$job"; why="a step left with no conclusion"; break
        fi
      done < "$T/lcand"
      if [ -z "$lost" ]; then
        [ "$readfail" = 1 ] || [ "$APPLY" != 1 ] || printf '%s %s %s\n' "$slug" "$id" "$NOW" >> "$SEEN"
        continue
      fi
      if awk -v s="$slug" -v j="$lost" '$1 == s && $2 == j { f = 1 } END { exit !f }' "$LOSTS"; then
        [ "$APPLY" != 1 ] || printf '%s %s %s\n' "$slug" "$id" "$NOW" >> "$SEEN"; continue
      fi
      if [ "$APPLY" != 1 ]; then log_note "would re-run job $lost of $slug run $id ($why)"; continue; fi
      printf '%s %s %s 1 %s\n' "$slug" "$lost" "$id" "$NOW" >> "$LOSTS"
      if "$GH" run rerun "$id" -R "$slug" --job "$lost" >/dev/null 2>&1; then
        printf '%s %s %s\n' "$slug" "$id" "$NOW" >> "$SEEN"
        lostline "$slug run $id job $lost re-run once ($why; off: lost-rerun off)"; log_ok "$slug job $lost re-run"
      else
        grep -v "^$slug $lost " "$LOSTS" > "$T/lost.n" 2>/dev/null; cat "$T/lost.n" > "$LOSTS"
        log_warn "$slug job $lost: the re-run failed; it is tried again next time"
      fi
    done < "$T/lids"
  done < "$T/targets"
  awk -v cut="$((NOW - 1209600))" '$NF > cut' "$LOSTS" > "$T/lost.n" 2>/dev/null && cat "$T/lost.n" > "$LOSTS" || :
  awk -v cut="$((NOW - 259200))" '$NF > cut' "$SEEN" > "$T/seen.n" 2>/dev/null && cat "$T/seen.n" > "$SEEN" || :
}

