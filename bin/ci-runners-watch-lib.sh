#!/usr/bin/env sh
# ci-runners-watch-lib.sh (harbor#1060) — watching: the alarm, the drift cache, and `tick`.
# Sourced by ci-runners.sh, never run: it sets no shell option and reads the entry point's variables ($T, $CONF, $GH, $DOCKER, ...).
. "$(dirname -- "$0")/log-lib.sh"   # a second source keeps the run's counts (log-lib.sh)

# ── alarm: a runner that cannot take work, or work no runner can take (harbor#1060, check ci-runner-alarm) ──────────
# 2026-10-05 19:53 the Mac rebooted, Colima did not start, every Linux runner sat offline ~18 min and nothing said so.
# On this tick's reads, no loop of its own: every runner REGISTERED on GitHub to a watched repo (the fleet's, held ones
# too, an org runner and its org's repos, and the governance repo) that is offline, docker not answering, and a self-hosted job queued over ALARM_SEC that
# no online runner's labels cover. An offline runner or a dead docker must be seen on two ticks (ALARM_CONFIRM), so a
# runner updating itself is not an alarm; a runner the governor parked is not one either. `alarm off` in CONF disables it.
ALARM_SEC="${HARBOR_CI_NORUNNER_SEC:-600}"
ALARM_CONFIRM=240
alarmline() { printf '[check:ci-runner-alarm] %s %s\n' "$(iso "$NOW")" "$1" >> "$LOG" 2>/dev/null || :; }

# ── WEDGED: online and busy on a job that is dead in the water (harbor#1060, 2026-10-13) ──────────────────────────
# An org runner's mutmut forked 8 workers in its 1 GiB, the kernel OOM-killed one, and the job sat 3h at 0.4% CPU while
# the org's deploy queued behind it: online, busy, invisible above. Read docker-side (GitHub cannot list that org's
# runs): one exec per running runner container a tick, its cgroup's oom_kill and usage_usec and its Runner.Worker.
# The oom_kill counter is baselined per job (pid + start), so an earlier job's OOM never counts against the next: the idle
# sighting is the baseline only when exactly one job started since it (one Worker_*.log per job), else the job's own first.
nonneg() { case "$1" in ''|*[!0-9]*) echo "$2" ;; *) echo "$1" ;; esac; }
WEDGE_PCT="$(nonneg "${HARBOR_CI_WEDGE_CPU_PCT:-}" 2)"        # near zero: under this % of one core
WEDGE_OOM_SEC="$(nonneg "${HARBOR_CI_WEDGE_OOM_SEC:-}" 240)"  # an oom_kill in the job, then near zero since, for at least this long
WEDGE_BUSY_SEC="$(nonneg "${HARBOR_CI_WEDGE_BUSY_SEC:-}" 7200)"  # no oom_kill: a job busy this long ...
WEDGE_IDLE_SEC="$(nonneg "${HARBOR_CI_WEDGE_IDLE_SEC:-}" 3600)"  # ... and near zero over this window
WEDGE_READ='cat /sys/fs/cgroup/memory.events /sys/fs/cgroup/cpu.stat 2>/dev/null
echo "jobs $(ls "$HOME"/_diag/Worker_*.log 2>/dev/null | wc -l)"
ps -eo pid=,etimes=,comm= 2>/dev/null | while read -r p e c; do
  [ "$c" = Runner.Worker ] || continue; set -- $(cat "/proc/$p/stat" 2>/dev/null); echo "worker $p $e ${22:-0}"; done; :'
# an exec into a memory-starved container can hang: 20s, then it is unread (perl's alarm, as session-state.sh does)
dexec() { if command -v perl >/dev/null 2>&1; then perl -e 'alarm shift; exec @ARGV' 20 "$DOCKER" exec "$@"; else "$DOCKER" exec "$@"; fi; }
# wedge_one <container> — one JSON line: the cgroup's counters, jobs run so far and the job (Runner.Worker pid.start, age), or fails
wedge_one() {
  dexec "$1" sh -c "$WEDGE_READ" > "$T/wr" 2>/dev/null || return 1
  awk -v n="$1" '$1 == "oom_kill" { o = $2 } $1 == "usage_usec" { u = $2 } $1 == "jobs" { j = $2 } $1 == "worker" && w == "" { w = $2 "." $4; a = $3 }
    END { if (o !~ /^[0-9]+$/ || u !~ /^[0-9]+$/) exit 1
          printf "{\"name\":\"%s\",\"oom\":%s,\"usage\":%s,\"jobs\":%s,\"job\":%s,\"age\":%d,\"pid\":%d}\n", n, o, u, (j ~ /^[0-9]+$/ ? j : "null"), (w == "" ? "null" : "\"" w "\""), a, w }' "$T/wr"
}
# wedge.jsonl: every running runner container (fleet, org and its numbered twins, extra and governance alike), parked ones aside
wedge_read() {
  : > "$T/wedge.jsonl"
  [ "$DOCKER_OK" = 1 ] && [ "$(conf wedge)" != off ] || return 0
  while read -r n _i st; do
    case "$n" in *-linux|*-linux-[0-9]) ;; *) continue ;; esac   # an org's exampleorg-linux-2 as well as harbor-linux-2
    [ "$st" = running ] && ! grep -qxF "$n" "$T/parked" || continue
    # a read that fails (a hung exec, a starved container) is "unread", never "idle": its state is carried, not dropped
    wedge_one "$n" >> "$T/wedge.jsonl" || printf '{"name":"%s","unread":true}\n' "$n" >> "$T/wedge.jsonl"
  done < "$T/ps.txt"
}
do_alarm() {
  A="$CACHE_DIR/ci-runner-alarm.json"
  if [ "$(conf alarm)" = off ]; then rm -f "$A"; return 0; fi
  # watch.tsv: key, slug, and whose runner list serves it: its own (a repo, or an org runner), or its org's (an org repo)
  awk -F'\t' '$3 == 1 { print $1 "\t" $2 "\t" $1 } $3 != 1 && $11 == "org" { r = $4; sub(/-linux$/, "", r); print $1 "\t" $2 "\t" r }' \
    "$T/rows.tsv" > "$T/watch.tsv"
  _g="${GOV_REPO#*/}"
  if ! awk -F'\t' -v s="$GOV_REPO" '$2 == s { f = 1 } END { exit !f }' "$T/watch.tsv"; then
    printf '%s\t%s\t%s\n' "$_g" "$GOV_REPO" "$_g" >> "$T/watch.tsv"
    "$GH" api "repos/$GOV_REPO/actions/runners" > "$T/r.json" 2>/dev/null && jq -e '.runners | type == "array"' "$T/r.json" >/dev/null 2>&1 \
      && cp "$T/r.json" "$T/rn.$_g.json" || :
  fi
  jq -r '.parked[]? // empty' "$CACHE_DIR/ci-governor.json" > "$T/parked" 2>/dev/null || : > "$T/parked"
  : > "$T/down"; : > "$T/stuck.jsonl"; nread=0; nwatch=0
  while IFS="$TAB" read -r repo slug rk; do
    if [ "$rk" = "$repo" ]; then
      nwatch=$((nwatch + 1))
      [ -f "$T/rn.$rk.json" ] || continue
      nread=$((nread + 1))
      jq -r '.runners[] | select(.status != "online") | .name' "$T/rn.$rk.json" 2>/dev/null \
        | awk -v pf="$T/parked" 'BEGIN { while ((getline l < pf) > 0) p[l] = 1 } !($0 in p)' >> "$T/down" || :
    fi
    case "$slug" in */*) ;; *) continue ;; esac   # an org has no runs of its own; its repos are watched one by one
    [ -f "$T/rn.$rk.json" ] || continue
    jq -c '[.runners[] | select(.status == "online") | [.labels[]?.name | ascii_downcase]]' "$T/rn.$rk.json" > "$T/able.json" 2>/dev/null || echo '[]' > "$T/able.json"
    for _st in queued in_progress; do
      "$GH" api "repos/$slug/actions/runs?status=$_st&per_page=50" 2>/dev/null \
        | jq -r --argjson now "$NOW" --argjson s "$ALARM_SEC" '.workflow_runs[]?
            | ((.created_at // "1970-01-01T00:00:00Z") | fromdateiso8601) as $c
            | select($c <= $now - $s and $c > $now - 86400) | .id' 2>/dev/null || :
    done | sort -u > "$T/runids"
    while read -r id; do
      "$GH" api "repos/$slug/actions/runs/$id/jobs" 2>/dev/null \
        | jq -c --arg repo "$repo" --argjson now "$NOW" --argjson s "$ALARM_SEC" --slurpfile able "$T/able.json" '.jobs[]?
            | select(.status == "queued") | [(.labels // [])[] | ascii_downcase] as $l
            | select(($l | index("self-hosted")) != null)
            | ((.created_at // "1970-01-01T00:00:00Z") | fromdateiso8601) as $c
            | select($c <= $now - $s)
            | select(any($able[0][]; ($l - .) | length == 0) | not)
            | {repo: $repo, at: $c}' >> "$T/stuck.jsonl" 2>/dev/null || :
    done < "$T/runids"
  done < "$T/watch.tsv"
  [ "$DOCKER_OK" = 1 ] || printf 'docker\n' >> "$T/down"
  sort -u "$T/down" -o "$T/down"
  wedge_read
  # carry each item's first sighting across one refresh only (ci-queue.sh's rule): an old cache starts it again
  prev='{}'; [ -f "$A" ] && jq -e 'type == "object"' "$A" >/dev/null 2>&1 && prev="$(jq -c . "$A")"
  unread=false; [ "$nwatch" -gt 0 ] && [ "$nread" = 0 ] && unread=true
  jq -R -s -c --argjson prev "$prev" --argjson now "$NOW" --argjson confirm "$ALARM_CONFIRM" --argjson unread "$unread" \
      --argjson s "$ALARM_SEC" --slurpfile stuck "$T/stuck.jsonl" --slurpfile wr "$T/wedge.jsonl" --argjson dock "$DOCKER_OK" \
      --argjson pct "$WEDGE_PCT" --argjson oomw "$WEDGE_OOM_SEC" --argjson busy "$WEDGE_BUSY_SEC" --argjson idlew "$WEDGE_IDLE_SEC" '
    def hm: "\(. / 3600 | floor)h\((. % 3600) / 60 | floor | tostring | if length < 2 then "0" + . else . end)m";
    (($now - ($prev.at // 0)) <= 600) as $fresh
    | (if $fresh then ($prev.since // {}) else {} end) as $old
    | ($prev.wedge // {}) as $pw
    # per container: the job, its oom_kill baseline, CPU samples (only while the cache is fresh: a gap may be a sleep)
    | ($wr | map(select(.unread) | .name)) as $blind
    | ($wr | map(select(.unread | not) | . as $r | $pw[$r.name] as $p
        | if $r.job == null then {key: $r.name, value: {job: null, oom: $r.oom, jobs: $r.jobs}}
          else ($p != null and $p.job == $r.job) as $same
            | (if $same then $p.base elif $p != null and $p.job == null and $fresh and $p.jobs != null and $r.jobs == $p.jobs + 1 then $p.oom else $r.oom end) as $base
            | ((if $same and $fresh then ($p.samples // []) else [] end)
               | map(select(.[0] < $now and .[0] >= $now - $idlew - 900 and .[1] <= $r.usage))) as $hist
            | def cpu($w): ([$hist[] | select(.[0] <= $now - $w)] | last) as $x
                | if $x == null then null else {s: ((($r.usage - $x[1]) / 100000 | round) / 10), win: ($now - $x[0])} end;
            # the first sighting of the oom_kill count as it is now: CPU is measured from there, the "since"
            (if $same and $fresh and $p.oom == $r.oom and $p.oomseen != null then $p.oomseen else [$now, $r.usage] end) as $os
            | (if $now - $os[0] >= $oomw then {s: ((($r.usage - $os[1]) / 100000 | round) / 10), win: ($now - $os[0])} else null end) as $ca
            | cpu($idlew) as $cb
            | (if $r.oom > $base and $ca != null and $ca.s * 100 < $pct * $ca.win then "oom"
               elif $r.age >= $busy and $cb != null and $cb.s * 100 < $pct * $cb.win then "idle" else null end) as $why
            | {key: $r.name, value: {job: $r.job, pid: $r.pid, base: $base, oom: $r.oom, jobs: $r.jobs, oomseen: $os, age: $r.age, why: $why,
                 cpu: (if $why == "oom" then $ca elif $why == "idle" then $cb else null end), samples: ($hist + [[$now, $r.usage]])}}
          end) | from_entries) as $w0
    | (if $dock == 1 then $w0 + ([$blind[] | select($pw[.] != null) | {key: ., value: $pw[.]}] | from_entries) else $pw + $w0 end) as $wedge
    | ((split("\n") | map(select(. != ""))) + [$wedge | to_entries[] | select(.value.why != null) | "wedged:" + .key]) as $items
    | ($items | map({key: ., value: ($old[.] // $now)}) | from_entries) as $since
    | [$items[] | select($now - $since[.] >= $confirm)] as $up
    | {at: $now, unread: $unread, since: $since,
       docker_down: ($up | index("docker") != null), offline: [$up[] | select(. != "docker" and (startswith("wedged:") | not))],
       wedged: [$up[] | select(startswith("wedged:")) | ltrimstr("wedged:")], wedge: $wedge,
       stuck: {jobs: ($stuck | length), oldest: ([$stuck[].at] | min), repos: ([$stuck[].repo] | unique)}}
    # gsig is what GitHub is needed for: carried unchanged while it is unread, so a blind tick neither raises nor clears it
    | .gsig = (if $unread then ($prev | if has("gsig") then .gsig else (.sig // "") end)
               else [(if .docker_down then "docker down (colima status)" else empty end),
               (if (.offline | length) > 0 then "offline " + (.offline | join(" ")) else empty end),
               (if .stuck.jobs > 0 then "self-hosted jobs queued over \($s / 60 | floor)m with no runner able to take them on " + (.stuck.repos | join(" ")) else empty end)]
              | join("; ") end)
    | .sig = ([.gsig, (if (.wedged | length) > 0 then "wedged " + (.wedged | join(" ")) else "" end)] | map(select(. != "")) | join("; "))
    | .detail = ([.gsig,
                  (.wedged[] as $n | .wedge[$n] as $e
                   | "wedged \($n): job running \($e.age | hm), oom_kill +\($e.oom - $e.base) during it, \($e.cpu.s)s CPU in the \(if $e.why == "oom" then "\($e.cpu.win / 60 | floor)m since" else "last \($e.cpu.win / 60 | floor)m" end); clear: sh bin/ci-runners.sh unwedge \($n) --apply")]
                 | map(select(. != "")) | join("; "))' "$T/down" > "$A.tmp.$$" \
    && mv -f "$A.tmp.$$" "$A" || { rm -f "$A.tmp.$$"; return 0; }
  was="$(printf '%s' "$prev" | jq -r '.sig // ""')"; is="$(jq -r .sig "$A")"
  [ "$is" = "$was" ] && return 0
  # a standing item that changes (one of several clears) says what it was, so the line is a delta, never a bare re-raise
  if [ -n "$is" ]; then alarmline "ALARM: $(jq -r .detail "$A")${was:+ (was: $was)}. Detail: sh bin/ci-runners.sh list"
  else alarmline "cleared (was: $was)"; fi
}

# ── unwedge: end a confirmed-wedged job's step tree, so the runner fails the job and takes the next ───────────────
# Refuses unless the alarm cache (at most 900s old) confirms <container> wedged AND the job running now is that job.
# Ends every descendant of Runner.Worker, never Runner.Worker or Runner.Listener: TERM, then KILL after
# HARBOR_CI_UNWEDGE_GRACE seconds (default 10) to whichever of those same pids is left.
UNWEDGE_GRACE="$(nonneg "${HARBOR_CI_UNWEDGE_GRACE:-}" 10)"
steptree() { # <container> <worker-pid> — the worker's descendants, "pid<TAB>comm args", from one ps inside it
  dexec "$1" ps -eo pid=,ppid=,args= > "$T/ps.$1" 2>/dev/null || return 1
  awk -v w="$2" -v OFS='\t' '{ p[NR] = $1; pp[NR] = $2; a[NR] = $0; sub(/^[ \t]*[0-9]+[ \t]+[0-9]+[ \t]*/, "", a[NR]) }
    END { t[w] = 1; do { more = 0; for (i = 1; i <= NR; i++) if ((pp[i] in t) && !(p[i] in t)) { t[p[i]] = 1; more = 1 } } while (more)
          for (i = 1; i <= NR; i++) if ((p[i] in t) && p[i] != w) print p[i], substr(a[i], 1, 100) }' "$T/ps.$1"
}
do_unwedge() {
  A="$CACHE_DIR/ci-runner-alarm.json"; c="$TARGET"
  if ! [ -f "$A" ] || ! jq -e --arg c "$c" --argjson now "$NOW" '($now - (.at // 0)) <= 900 and ((.wedged // []) | index($c) != null)' "$A" >/dev/null 2>&1; then
    log_fail "$c is not confirmed wedged in $A (fresh within 900s): refusing to end anything"
    log_fix "wait for the alarm (two ticks), or look: sh $0 list; docker top $c"; return 1
  fi
  job="$(jq -r --arg c "$c" '.wedge[$c].job // ""' "$A")"
  cur="$(wedge_one "$c" | jq -r '.job // ""' 2>/dev/null || :)"
  if [ -z "$cur" ] || [ "$cur" != "$job" ]; then
    log_fail "$c: the wedged job ($job) is not the one running now (${cur:-none}): refusing"; log_fix "sh $0 tick re-reads it; docker top $c"; return 1
  fi
  steptree "$c" "${job%%.*}" > "$T/tree" || { log_fail "$c: could not list its processes"; log_fix "docker top $c"; return 1; }
  n="$(wc -l < "$T/tree" | tr -d ' ')"
  [ "$n" -gt 0 ] || { log_note "$c: Runner.Worker ${job%%.*} has no step processes left to end"; return 0; }
  printf 'PID\tSTEP PROCESS (descendants of Runner.Worker %s in %s)\n' "${job%%.*}" "$c"; cat "$T/tree"
  if [ "$APPLY" = 0 ]; then log_note "would send TERM to these $n, then KILL to any left after ${UNWEDGE_GRACE}s"; log_note "dry run: pass --apply to do it"; return 0; fi
  set -- $(cut -f1 "$T/tree")
  dexec "$c" sh -c 'kill -TERM "$@" 2>/dev/null; :' sh "$@" || { log_fail "$c: docker exec kill failed"; log_fix "docker top $c"; return 1; }
  sleep "$UNWEDGE_GRACE"
  # what is left of THOSE pids, orphaned or not (a pid TERM spared may be re-parented away from the worker); a zombie is ended
  dexec "$c" ps -eo pid=,stat= > "$T/alive" 2>/dev/null || : > "$T/alive"
  set -- $(awk 'NR == FNR { split($0, f, "\t"); w[f[1]] = 1; next } ($1 in w) && $2 !~ /^Z/ { print $1 }' "$T/tree" "$T/alive")
  k="$#"; [ "$k" = 0 ] || dexec "$c" sh -c 'kill -KILL "$@" 2>/dev/null; :' sh "$@" || :
  alarmline "unwedge $c: job $(jq -r --arg c "$c" '.wedge[$c].age as $a | "\($a / 3600 | floor)h\(($a % 3600) / 60 | floor | tostring | if length < 2 then "0" + . else . end)m"' "$A") in, sent TERM to $n step processes, KILL to $k left after ${UNWEDGE_GRACE}s; Runner.Worker and Runner.Listener untouched"
  log_ok "$c: TERM to $n step processes, KILL to $k; the runner fails the job and takes the next"
}

# ── tick: the report is the delta ────────────────────────────────────────────────────────────────
names() { awk -F'\t' -v v="$1" '$11 == v { printf "%s%s", s, $4; s = " " }' "$T/rows.tsv"; }
write_cache() {
  OUT="$CACHE_DIR/ci-runners.json"
  jq -cn --argjson at "$NOW" --argjson desired "$(awk -F'\t' '$3 == 1' "$T/rows.tsv" | wc -l | tr -d ' ')" \
    --arg missing "$(names missing)" --arg offline "$(names offline)" --arg stopped "$(names stopped)" --arg extra "$(names extra)" \
    --arg held "$(names hold)" --arg ok "$(names ok)" --arg stale "$(names stale)" --arg unread "$(names unknown)" \
    '{at: $at, desired: $desired, ok: ($ok | split(" ") | map(select(. != ""))), missing: ($missing | split(" ") | map(select(. != ""))),
      offline: ($offline | split(" ") | map(select(. != ""))), stopped: ($stopped | split(" ") | map(select(. != ""))),
      held: ($held | split(" ") | map(select(. != ""))), extra: ($extra | split(" ") | map(select(. != ""))),
      stale: ($stale | split(" ") | map(select(. != ""))), unread: ($unread | split(" ") | map(select(. != "")))}' > "$OUT.tmp.$$" \
    && mv -f "$OUT.tmp.$$" "$OUT" || { rm -f "$OUT.tmp.$$"; return 1; }
}
do_tick() {
  OUT="$CACHE_DIR/ci-runners.json"; prev=""
  [ -f "$OUT" ] && prev="$(jq -c '[.missing, .offline, .stopped, .extra]' "$OUT" 2>/dev/null || :)"
  # stale (an image older than the tag) and unread (GitHub did not list the runners) are not drift, but a cache that
  # dropped them read "9 desired, 0 ok, nothing wrong" while every container ran a 3-day-old image (2026-10-27).
  # One line when the stale set changes; `refresh --apply` stays the operator's.
  pstale=""; [ -f "$OUT" ] && pstale="$(jq -r '(.stale // []) | join(" ")' "$OUT" 2>/dev/null || :)"
  collect
  if [ "$DOCKER_OK" = 1 ]; then write_cache; now="$(jq -c '[.missing, .offline, .stopped, .extra]' "$OUT")"; else now="$prev"; fi
  if [ "$DOCKER_OK" = 1 ]; then
    nstale="$(names stale)"
    if [ "$nstale" != "$pstale" ]; then
      if [ -n "$nstale" ]; then logline "stale: $nstale on an image older than $IMAGE; sh bin/ci-runners.sh refresh --apply recreates the idle ones"
      elif [ -n "$pstale" ]; then logline "stale cleared"; fi
    fi
  fi
  if [ "$now" != "$prev" ]; then
    d=""
    for _k in missing offline stopped extra; do _l="$(names "$_k")"; [ -z "$_l" ] || d="$d${d:+; }$_k $_l"; done
    if [ -n "$d" ]; then logline "drift: $d"; elif [ -n "$prev" ]; then logline "drift cleared"; fi
  fi
  APPLY=1; sync_hook || :; do_switch
  [ "$CHANGED" = 0 ] || collect
  do_rerun
  do_alarm
  do_rerun_lost
}

