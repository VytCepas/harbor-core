#!/usr/bin/env sh
# bin/ci-runners.sh rerun-lost (harbor#675 and #1060, check ci-lost-rerun) against stubbed gh: a job whose ONLY annotation
# says no runner acquired it is re-run once, and so is a job the runner lost mid-run (a step with no conclusion, or the runner's
# own lost-connection text); a job that ran and failed, or carries any other annotation, never is. Operator decision 2026-10-06.
. "$(dirname "$0")/../lib/core.sh"; t_init
. "$T_ROOT/tests/ci/ci-runners-fixture.sh"
LOST='[{"message":"The job was not acquired by Runner of type self-hosted even after multiple attempts"}]'
MIXED='[{"message":"The job was not acquired by Runner of type self-hosted even after multiple attempts"},{"message":"Process completed with exit code 1."}]'
REAL='[{"message":"Process completed with exit code 1."}]'
REFUSED='[{"message":"The job was not started because recent account payments have failed or your spending limit needs to be increased"}]'
ago() { date -u -r "$((NOW - $1))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$((NOW - $1))" +%Y-%m-%dT%H:%M:%SZ; }
fleet() { reset; container alpha-linux port-linux-runner:local running; runner alpha online false; echo self-hosted > "$FX/var/alpha"; runner harbor online false 9; }
# plant <repo> <run> <conclusion> <attempt> <age-s> <steps> <annotation-json> — a run with ONE job, id run*10
plant() {
  mkdir -p "$FX/runs" "$FX/jobs" "$FX/ann"; _f="$FX/runs/$1.json"; [ -f "$_f" ] || echo '[]' > "$_f"
  jq -c --argjson id "$2" --arg c "$3" --argjson a "$4" --arg at "$(ago "$5")" \
    '. + [{databaseId:$id, conclusion:$c, createdAt:$at, attempt:$a}]' "$_f" > "$_f.n" && mv "$_f.n" "$_f"
  printf '{"jobs":[{"id":%s,"conclusion":"%s","steps":%s}]}\n' "$(($2 * 10))" "$3" "$6" > "$FX/jobs/$2.json"
  printf '%s\n' "$7" > "$FX/ann/$(($2 * 10)).json"
}
NOSTEPS='[]'; STEPS='[{"name":"Run tests","conclusion":"failure"}]'
reruns() { cat "$FX/reruns.log" 2>/dev/null || :; }
jobreruns() { reruns | grep ' job ' || :; }
llog() { _n="$(grep -c 'check:ci-lost-rerun' "$CACHE/checks.log" 2>/dev/null)" || _n=0; echo "${_n:-0}"; }
plantall() {
  plant alpha 301 cancelled 1 3600 "$NOSTEPS" "$LOST"
  plant alpha 302 failure 1 3600 "$STEPS" "$REAL"
  plant alpha 303 cancelled 1 3600 "$NOSTEPS" "$MIXED"
  plant alpha 304 failure 1 3600 "$NOSTEPS" "$REFUSED"
  plant alpha 305 cancelled 1 216000 "$NOSTEPS" "$LOST"
  plant alpha 306 cancelled 2 3600 "$NOSTEPS" "$LOST"
  plant alpha 307 failure 1 3600 "$STEPS" "$LOST"
}

t_section "a lost-only job is re-run once, and only it"
fleet; plantall
OUT="$(run rerun-lost)"
t_has "the dry run names the lost job" "$OUT" "301"
t_eq "...and re-runs nothing" 0 "$(nlines "$FX/reruns.log")"
t_eq "...and remembers nothing" 0 "$(nlines "$CACHE/ci-lost-reruns.tsv")"
run rerun-lost --apply >/dev/null
t_eq "apply re-runs job 3010 of run 301, by job, and nothing else" "rerun 301 VytCepas/alpha job 3010" "$(reruns)"
t_eq "one [check:ci-lost-rerun] line" 1 "$(llog)"
t_has "...naming repo, run and job" "$(cat "$CACHE/checks.log")" "VytCepas/alpha run 301 job 3010"
run rerun-lost --apply >/dev/null; run rerun-lost --apply >/dev/null
t_eq "second and third tick re-run nothing" 1 "$(nlines "$FX/reruns.log")"
t_eq "...and log nothing" 1 "$(llog)"
t_has "the job is remembered, keyed by id" "$(cat "$CACHE/ci-lost-reruns.tsv")" "VytCepas/alpha 3010 301"
t_eq "never a job that executed steps (302, 307)" 0 "$(reruns | grep -c -e ' 302 ' -e ' 307 ' || true)"
t_eq "never a mixed-annotation job (303)" 0 "$(reruns | grep -c ' 303 ' || true)"
t_eq "never a billing refusal (304: that is rerun-refused's)" 0 "$(reruns | grep -c ' 304 ' || true)"
t_eq "never a run older than 48h (305)" 0 "$(reruns | grep -c ' 305 ' || true)"
t_eq "never a run already past attempt 1 (306)" 0 "$(reruns | grep -c ' 306 ' || true)"

t_section "the once survives a lost state of the seen cache, and a failed re-run is retried"
rm -f "$CACHE/ci-lost-seen.tsv"; run rerun-lost --apply >/dev/null
t_eq "control: with the seen cache gone the state file alone still stops it" 1 "$(nlines "$FX/reruns.log")"

fleet; plant alpha 301 cancelled 1 3600 "$NOSTEPS" "$LOST"; : > "$FX/rerun.fail"; run rerun-lost --apply >/dev/null
t_eq "a re-run GitHub refused is not remembered" 0 "$(nlines "$CACHE/ci-lost-reruns.tsv")"
t_eq "...and is not logged as done" 0 "$(llog)"
rm "$FX/rerun.fail"; run rerun-lost --apply >/dev/null
t_eq "...so the next tick tries again, once" "rerun 301 VytCepas/alpha job 3010" "$(reruns)"

t_section "off switch, and where it does not run"
fleet; plantall; printf 'lost-rerun off\n' > "$CLAUDE_CONFIG_DIR/.harbor-ci-runners"; run rerun-lost --apply >/dev/null; run tick >/dev/null
t_eq "lost-rerun off: no job is re-run, by the verb or by tick" "" "$(jobreruns)"
t_eq "...nothing is logged" 0 "$(llog)"
fleet; plantall; runner alpha offline false; run rerun-lost --apply >/dev/null
t_eq "control: a repo whose runner is offline is not sent a re-run" 0 "$(nlines "$FX/reruns.log")"
fleet; plantall; rm "$FX/var/alpha"; run rerun-lost --apply >/dev/null
t_eq "control: a repo not on self-hosted is not re-run (it would go to hosted minutes)" 0 "$(nlines "$FX/reruns.log")"

t_section "tick runs it, and the governance repo is covered"
fleet; plantall; run tick >/dev/null
t_eq "tick re-runs the lost job (the billing refusal beside it is rerun-refused's)" "rerun 301 VytCepas/alpha job 3010" "$(jobreruns)"
fleet; plant harbor 401 cancelled 1 3600 "$NOSTEPS" "$LOST"; run tick >/dev/null
t_eq "harbor's own lost job, served by harbor-linux" "rerun 401 VytCepas/harbor job 4010" "$(reruns)"
fleet; plant harbor 401 cancelled 1 3600 "$NOSTEPS" "$LOST"; runner harbor offline false 9; run tick >/dev/null
t_eq "control: harbor's runner offline, nothing" 0 "$(nlines "$FX/reruns.log")"

t_section "infrastructure failure mid-run (harbor#1060, 2026-10-06 run 37511778240): a step with no conclusion, or the runner's own text"
OPEN='[{"name":"Set up job","conclusion":"success"},{"name":"Every selected suite","conclusion":null},{"name":"Post","conclusion":null}]'
DONE='[{"name":"Set up job","conclusion":"success"},{"name":"Run tests","conclusion":"success"}]'
OPENFAIL='[{"name":"Run tests","conclusion":"failure"},{"name":"Post","conclusion":null}]'
COMM='[{"message":"The self-hosted runner: harbor-linux lost communication with the server. Verify the machine is running and has a healthy network connection."}]'
SHUT='[{"message":"The runner has received a shutdown signal. This can happen when the runner service is stopped."}]'
COMMMIX='[{"message":"The self-hosted runner: harbor-linux lost communication with the server."},{"message":"Process completed with exit code 1."}]'
CANCELED='[{"message":"The operation was canceled."}]'
plantinfra() {
  plant alpha 311 failure 1 3600 "$OPEN" "[]"            # the 2026-10-06 shape: failed, a step left open, no annotation
  plant alpha 312 cancelled 1 3600 "$DONE" "$COMM"       # runner lost communication, every step concluded
  plant alpha 313 failure 1 3600 "$DONE" "$SHUT"         # runner shutdown signal
  plant alpha 314 failure 1 3600 "$DONE" "$REAL"         # a real test failure: exit code 1, nothing open
  plant alpha 315 failure 1 3600 "$OPENFAIL" "$COMM"     # a failed step AND an open one: the failure is real
  plant alpha 316 failure 1 3600 "$DONE" "$COMMMIX"      # lost-communication text beside any other annotation
  plant alpha 317 cancelled 1 3600 "$DONE" "$CANCELED"   # a person's cancel or a timeout
  plant alpha 318 failure 1 3600 "$DONE" "[]"            # failed, no annotation, nothing open
  plant alpha 319 failure 1 3600 "$NOSTEPS" "$COMM"      # lost communication before any step
}
fleet; plantinfra
t_has "the dry run names the open-step job" "$(run rerun-lost)" "311"
t_eq "...and re-runs nothing" 0 "$(nlines "$FX/reruns.log")"
run rerun-lost --apply >/dev/null
t_eq "each infrastructure shape is re-run once by job id (one job a run)" "rerun 311 VytCepas/alpha job 3110
rerun 312 VytCepas/alpha job 3120
rerun 313 VytCepas/alpha job 3130
rerun 319 VytCepas/alpha job 3190" "$(reruns | sort)"
t_eq "never a real test failure (314: exit code 1, nothing open)" 0 "$(reruns | grep -c ' 314 ' || true)"
t_eq "never a failed step beside an open one (315)" 0 "$(reruns | grep -c ' 315 ' || true)"
t_eq "never lost-communication text beside another annotation (316)" 0 "$(reruns | grep -c ' 316 ' || true)"
t_eq "never a cancel or a timeout (317)" 0 "$(reruns | grep -c ' 317 ' || true)"
t_eq "never a failure with no annotation and nothing open (318)" 0 "$(reruns | grep -c ' 318 ' || true)"
t_eq "one [check:ci-lost-rerun] line per re-run" 4 "$(llog)"
t_has "...saying why: a step with no conclusion" "$(grep ' 311 ' "$CACHE/checks.log" || grep 'run 311' "$CACHE/checks.log")" "a step left with no conclusion"
t_has "...saying why: the runner lost its connection" "$(grep 'run 312' "$CACHE/checks.log")" "runner lost its connection"
: > "$FX/reruns.log"; run rerun-lost --apply >/dev/null; run tick >/dev/null
t_eq "the second and third pass re-run nothing" 0 "$(nlines "$FX/reruns.log")"

t_section "an open step alone is not infrastructure: a cancel, a timeout and a fail-fast sibling carry one too"
HCANCEL='[{"message":"The run was canceled by @someone."}]'
TIMEOUT='[{"message":"The job running on runner harbor-linux has exceeded the maximum execution time of 30 minutes."}]'
FFAST='[{"message":"The operation was canceled."}]'
fleet
plant alpha 501 cancelled 1 3600 "$OPEN" "$HCANCEL"     # a person cancelled the run mid-step
plant alpha 502 cancelled 1 3600 "$OPEN" "$TIMEOUT"     # GitHub scores a timeout as cancelled
plant alpha 503 failure 1 3600 "$OPEN" "$TIMEOUT"       # ...and sometimes as failure
plant alpha 504 cancelled 1 3600 "$OPEN" "[]"           # cancelled, nothing said
plant alpha 506 cancelled 1 3600 "$OPEN" "$FFAST"       # a matrix fail-fast sibling
plant alpha 507 failure 1 3600 "$OPEN" "$FFAST"         # ...read as failed
plant alpha 508 failure 1 3600 "$OPEN" "$REAL"          # an open step beside a real failure's annotation
plant alpha 505 failure 1 3600 "$OPEN" "$COMM"          # the 2026-10-06 shape: failed, open step, the runner's own text
plant alpha 311 failure 1 3600 "$OPEN" "[]"             # failed, open step, no annotation
run rerun-lost --apply >/dev/null
t_eq "only the failed open-step jobs the runner dropped are re-run (311, 505)" "rerun 311 VytCepas/alpha job 3110
rerun 505 VytCepas/alpha job 5050" "$(reruns | sort)"
for _k in 501 502 503 504 506 507 508; do
  t_eq "never an open-step job that is a cancel, a timeout or a sibling ($_k)" 0 "$(reruns | grep -c " $_k " || true)"
done

t_section "a second infrastructure failure of the same job is never re-run twice"
fleet; plant alpha 311 failure 1 3600 "$OPEN" "[]"; run rerun-lost --apply >/dev/null
t_eq "(setup) the first failure is re-run" "rerun 311 VytCepas/alpha job 3110" "$(reruns)"
: > "$FX/reruns.log"; rm -f "$CACHE/ci-lost-seen.tsv"
plant alpha 351 failure 2 1800 "$OPEN" "[]"
run rerun-lost --apply >/dev/null
t_eq "the re-run (attempt 2) fails the same way: left to a person" 0 "$(nlines "$FX/reruns.log")"
fleet; plant alpha 311 failure 1 3600 "$OPEN" "[]"; run rerun-lost --apply >/dev/null; : > "$FX/reruns.log"
rm -f "$CACHE/ci-lost-seen.tsv"; run rerun-lost --apply >/dev/null
t_eq "...and the same job on attempt 1 again, with the seen cache gone, is stopped by the job's own record" 0 "$(nlines "$FX/reruns.log")"
t_eq "...one line in the log, ever" 1 "$(llog)"

t_section "a refused re-run is not remembered, and the off switch covers the new shapes"
fleet; plant alpha 311 failure 1 3600 "$OPEN" "[]"; : > "$FX/rerun.fail"; run rerun-lost --apply >/dev/null
t_eq "refused: nothing remembered" 0 "$(nlines "$CACHE/ci-lost-reruns.tsv")"
rm "$FX/rerun.fail"; run rerun-lost --apply >/dev/null
t_eq "...and the next tick tries again" "rerun 311 VytCepas/alpha job 3110" "$(reruns)"
fleet; plantinfra; printf 'lost-rerun off\n' > "$CLAUDE_CONFIG_DIR/.harbor-ci-runners"; run rerun-lost --apply >/dev/null
t_eq "lost-rerun off: no infrastructure shape is re-run either" 0 "$(nlines "$FX/reruns.log")"
fleet; plant alpha 314 failure 1 3600 "$DONE" "$REAL"; run rerun-lost --apply >/dev/null; : > "$FX/gh.log"; run rerun-lost --apply >/dev/null
t_eq "a real failure is read once and then remembered: the second pass reads no annotations" 0 "$(grep -c -e '/jobs' -e '/annotations' "$FX/gh.log" || true)"
fleet; plant alpha 302 failure 1 3600 "$STEPS" "$REAL"; run rerun-lost --apply >/dev/null
t_eq "a job with a failed step has its annotations never read" 0 "$(grep -c '/annotations' "$FX/gh.log" || true)"

t_section "API budget"
fleet; plantall; run rerun-lost --apply >/dev/null; : > "$FX/gh.log"; run rerun-lost --apply >/dev/null
t_eq "the second pass over the same runs reads no jobs and no annotations" 0 "$(grep -c -e '/jobs' -e '/annotations' "$FX/gh.log" || true)"
t_eq "...and asks GitHub only for each repo's run list (alpha, harbor)" "2" "$(grep -c '^run list' "$FX/gh.log")"
t_eq "...and the stubs saw nothing off script" 0 "$(nlines "$FX/unexpected.log")"
t_done
