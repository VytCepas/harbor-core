#!/usr/bin/env sh
# ci-runners-provision-lib.sh (harbor#1060) — container lifecycle: sync_hook, `up`, `refresh`, the governance runners, `down`.
# Sourced by ci-runners.sh, never run: it sets no shell option and reads the entry point's variables ($T, $CONF, $GH, $DOCKER, ...).
. "$(dirname -- "$0")/library-log.sh"   # a second source keeps the run's counts (library-log.sh)

# Every container runs the job hook from the shared events mount, so this copy is the one they run: kept equal to
# the hook beside this script on each up --apply and tick. It was hand-copied, so a fix to it reached no runner.
sync_hook() {
  _src="$(dirname -- "$0")/ci-governor-hook.sh"; _dst="$EVENTS/ci-governor-hook.sh"
  [ -f "$_src" ] && [ -d "$EVENTS" ] || return 0
  ! cmp -s "$_src" "$_dst" || return 0
  if cp "$_src" "$_dst.new" && chmod 0644 "$_dst.new" && mv "$_dst.new" "$_dst"; then
    logline "job hook installed in $EVENTS"; log_ok "job hook installed in the events mount"
  else rm -f "$_dst.new"; log_fail "could not install the job hook into $EVENTS"; log_fix "cp $_src $_dst"; return 1; fi
}

# ── up: the missing containers, as provision.sh made them ─────────────────────────────────────
create_ok() { # <name> — what create needs before it may touch anything
  mounts_ok "$1" || return 1
  "$DOCKER" image inspect "$IMAGE" >/dev/null 2>&1 \
    || { log_fail "$1: image $IMAGE is not on this box"; log_fix "set image <name> in $CONF (or HARBOR_CI_IMAGE), or build runners/linux"; return 1; }
  [ -d "$EVENTS" ] || { log_fail "$1: the governor's events dir $EVENTS does not exist"; log_fix "mkdir -p $EVENTS"; return 1; }
}
# labels_for <name> — what a container registers with: a governance runner is also `harbor-pool`, a gate runner `harbor-gate` (harbor#1286)
labels_for() { case "$1" in harbor-linux|harbor-linux-[0-9]) printf '%s,harbor-pool' "$LABELS" ;; harbor-gate|harbor-gate-[0-9]) printf '%s,harbor-gate' "$LABELS" ;; *) printf '%s' "$LABELS" ;; esac; }
create() { # <slug> <name>
  create_ok "$2" || return 1
  "$GH" api -X POST "$(api_base "$1")/actions/runners/registration-token" > "$T/tok.json" 2>/dev/null \
    && jq -r '.token // empty' "$T/tok.json" > "$T/tok" 2>/dev/null && [ -s "$T/tok" ] \
    || { rm -f "$T/tok.json" "$T/tok"; log_fail "$2: GitHub gave no registration token for $1"; log_fix "gh auth status"; return 1; }
  { printf 'RUNNER_URL=https://github.com/%s\nRUNNER_NAME=%s\nRUNNER_LABELS=%s\nRUNNER_TOKEN=' "$1" "$2" "$(labels_for "$2")"; cat "$T/tok"; } > "$T/env"
  rm -f "$T/tok.json" "$T/tok"
  _slug="$1"; _c="$2"; set --    # the read-only mounts become this function's arguments: sh has no arrays
  [ -n "${GOV_MEM:-}" ] || while IFS="$TAB" read -r r h p _w; do [ "$r" != "$(grp_of "$_c")" ] || set -- "$@" -v "$h:$p:ro"; done < "$T/mounts.tsv"
  # GOV_MEM/GOV_CPUS/GOV_EVENTS: harbor-linux's own values (harbor#1083); a fleet container takes the config's (LIMITS)
  _cpu="${GOV_CPUS:-$(cpus_for "$_c")}"; _mem="${GOV_MEM:-$(mem_for "$_c")}"
  if "$DOCKER" run -d --name "$_c" --restart unless-stopped --cpus "$_cpu" --memory "$_mem" --env-file "$T/env" \
       -v "${GOV_EVENTS:-$EVENTS}:/gov-events" "$@" \
       -e ACTIONS_RUNNER_HOOK_JOB_STARTED=/gov-events/ci-governor-hook.sh \
       -e ACTIONS_RUNNER_HOOK_JOB_COMPLETED=/gov-events/ci-governor-hook.sh \
       "$IMAGE" >/dev/null 2>&1; then rm -f "$T/env"
  else rm -f "$T/env"; log_fail "$_c: docker run failed"; log_fix "docker logs $_c; docker ps -a"; return 1; fi
  logline "$_c created for $_slug (image $IMAGE$([ "$#" = 0 ] || echo ", $(($# / 2)) read-only mounts")) at cpus $_cpu, memory $_mem"; log_ok "$_c created for $_slug"
}
do_up() {
  FAILED=0
  [ "$APPLY" = 0 ] || sync_hook || FAILED=1
  while IFS="$TAB" read -r repo slug _w c cstate _i _r busy _id _v verdict; do
    case "$verdict" in
      missing) if [ "$APPLY" = 1 ]; then create "$slug" "$c" || FAILED=1
               elif mounts_ok "$c"; then log_note "would create $c for $slug (image $IMAGE, $NMOUNTS read-only mounts) at cpus $(cpus_for "$c"), memory $(mem_for "$c")"; else FAILED=1; fi ;;
      stopped) [ "$busy" = true ] && continue
               if [ "$APPLY" = 1 ]; then
                 if "$DOCKER" start "$c" >/dev/null 2>&1; then logline "$c started"; log_ok "$c started"; else log_fail "$c would not start"; log_fix "docker logs $c"; FAILED=1; fi
               else log_note "would start $c"; fi ;;
      hold) log_skip "$repo is on hold ($(awk -v r="$repo" '$1 == "hold" && $2 == r { $1 = ""; $2 = ""; sub(/^ +/, ""); print; exit }' "$CONF"))" ;;
    esac
  done < "$T/rows.tsv"
  limits_up || FAILED=1
  if [ "$INCGOV" = 1 ]; then gov_up || FAILED=1; fi
  [ "$APPLY" = 1 ] || log_note "dry run: pass --apply to do it"
  [ "$FAILED" = 0 ]
}

live_state() { "$DOCKER" inspect --format '{{.State.Status}}' "$1" 2>/dev/null | tr -d ' \r\n' || :; }   # running, exited, ... now

# limits_up — an ADOPTED runner whose memory cap differs from its explicitly configured value (mem_want) is set to it LIVE,
# docker update with swap 2x (as docker run makes it), never a recreate. A raise goes in even under a job (a cgroup limit
# raised kills nothing); a lowering (or capping an uncapped one) never under a job, nor below what it uses now, both read again just before: refused,
# said, the rest carried on. Governance runners only with --include-governance (and only a limits line names them).
limits_up() {
  _lf=0
  { awk -F'\t' '$3 == 1 && $5 != "absent" && $11 != "hold" { print $4 "\t" $5 "\t" $8 }' "$T/rows.tsv"
    [ "$INCGOV" = 0 ] || awk -F'\t' '$5 != "absent" { print $4 "\t" $5 "\t" $8 }' "$T/gov.tsv"; } > "$T/lim.tsv"
  while IFS="$TAB" read -r c st busy; do
    w="$(mem_want "$c")"; [ -n "$w" ] || continue
    wb="$(bytes "$w")"; h="$(mem_have "$c")"
    case "$h" in ''|*[!0-9]*) log_warn "$c: its memory cap could not be read; left as it is"; continue ;; esac
    [ "$h" != "$wb" ] || continue
    _hs="$(gib "$h")"; [ "$h" != 0 ] || _hs="no cap"
    if [ "$h" = 0 ] || [ "$wb" -lt "$h" ]; then
      # the rows are from the start of the run: up may have started this container since, and a job may have come; look again
      st="$(live_state "$c")"
      case "$st" in '') log_fail "$c: memory $_hs -> $w is a lowering and the container's state could not be read: refused"; log_fix "docker inspect $c"; _lf=1; continue ;; esac
      [ "$st" != running ] || ! "$DOCKER" top "$c" 2>/dev/null | grep -q 'Runner\.Worker' || busy=true
      if [ "$busy" = true ]; then log_fail "$c: memory $_hs -> $w is a lowering and it is running a job: refused"; log_fix "sh $0 up --apply when it is idle"; _lf=1; continue; fi
      if [ "$st" = running ]; then
        u="$(mem_used "$c")"
        case "$u" in ''|*[!0-9]*) log_fail "$c: memory $_hs -> $w is a lowering and what it uses now could not be read: refused"; log_fix "docker stats --no-stream $c"; _lf=1; continue ;; esac
        [ "$wb" -ge "$u" ] || { log_fail "$c: memory $_hs -> $w is below what it uses now ($(gib "$u")): refused"; log_fix "a limits value of at least $(gib "$u") in $CONF, or sh $0 up --apply when it uses less"; _lf=1; continue; }
      fi
    fi
    if [ "$APPLY" != 1 ]; then log_note "would set $c memory $_hs -> $w live (docker update, no recreate)"; continue; fi
    if "$DOCKER" update --memory "$wb" --memory-swap "$((wb * 2))" "$c" >/dev/null 2>&1; then
      logline "$c memory $_hs -> $w (docker update, live$([ "$busy" != true ] || echo ', under a job'))"; log_ok "$c memory $_hs -> $w, live"
    else log_fail "$c: docker update refused memory $w"; log_fix "docker update --memory $wb --memory-swap $((wb * 2)) $c"; _lf=1; fi
  done < "$T/lim.tsv"
  return "$_lf"
}

# still_idle <container> <slug> <rid> — read again right before a `docker rm -f`: the rows were read once at the start, and a
# runner idle then can have taken a job since. Busy on docker, busy on GitHub, or GitHub not answering all say no.
still_idle() {
  if "$DOCKER" top "$1" 2>/dev/null | grep -q 'Runner\.Worker'; then return 1; fi
  [ "$3" != - ] || return 0
  "$GH" api "$(api_base "$2")/actions/runners" > "$T/si.json" 2>/dev/null && jq -e '.runners | type == "array"' "$T/si.json" >/dev/null 2>&1 || return 1
  [ "$(jq -r --argjson i "$3" '[.runners[] | select(.id == $i)][0].busy // false | tostring' "$T/si.json")" = false ]
}

# ── refresh: a container on a stale image is recreated as up makes it, never under a job (harbor#1075) ──
do_refresh() {
  FAILED=0; N=0; _new="$(tag_id)"
  while IFS="$TAB" read -r repo slug w c cstate _i runner busy rid _v verdict; do
    [ "$w" = 1 ] && [ "$cstate" != absent ] && [ "$verdict" != hold ] && is_stale "$c" || continue
    N=$((N + 1)); _old="$(box_id "$c")"
    if [ "$runner" = unknown ]; then log_fail "$c: GitHub did not answer, so it cannot be told whether the runner is busy"; log_fix "gh auth status"; FAILED=1; break; fi
    [ "$busy" != true ] || { log_skip "$c is running a job; left on image $(sid "$_old"), try again when it is idle"; continue; }
    create_ok "$c" || { FAILED=1; break; }
    if [ "$APPLY" != 1 ]; then log_note "would recreate $c for $slug: image $(sid "$_old") -> $(sid "$_new") ($IMAGE, $NMOUNTS read-only mounts)"; continue; fi
    still_idle "$c" "$slug" "$rid" || { log_skip "$c took a job since the list was read; left as it is, try again when it is idle"; continue; }
    "$DOCKER" rm -f "$c" >/dev/null 2>&1 || { log_fail "$c would not be removed"; log_fix "docker rm -f $c"; FAILED=1; break; }
    [ "$rid" = - ] || "$GH" api -X DELETE "$(api_base "$slug")/actions/runners/$rid" >/dev/null 2>&1 \
      || log_warn "$c removed, but its registration $rid on $slug is still there; the new one replaces it"
    create "$slug" "$c" || { log_fail "$c was removed and not recreated; the rest are untouched"; log_fix "sh $0 up --apply"; FAILED=1; break; }
    logline "$c refreshed: image $(sid "$_old") -> $(sid "$_new")"
  done < "$T/rows.tsv"
  [ "$N" != 0 ] || log_note "no container is on a stale image"
  if [ "$INCGOV" = 1 ] && [ "$FAILED" = 0 ]; then gov_refresh || FAILED=1
  elif [ "$INCGOV" = 0 ] && [ -n "$(awk -F'\t' '$12 == "stale" { print $4; exit }' "$T/gov.tsv")" ]; then
    log_note "$(awk -F'\t' '$12 == "stale" { print $4; exit }' "$T/gov.tsv") (governance) is on an older image too; refresh leaves it unless --include-governance is given"
  fi
  [ "$APPLY" = 1 ] || [ "$N" = 0 ] || log_note "dry run: pass --apply to do it"
  [ "$FAILED" = 0 ]
}
# gov_ref <name> <state> — the values a governance runner is made with, in GOV_MEM/GOV_EVENTS/GOV_CPUS: what the container has
# now, or when it is absent what harbor-linux has (harbor-linux-2 is made as harbor-linux is), else the defaults (harbor#1083)
cpus_for_gate() { _cg="$(limit "$1" cpus)"; case "$_cg" in ''|.*|*.*.*|*[!0-9.]*) _cg=1 ;; esac; printf '%s' "$_cg"; }
gov_ref() {
  _rf="$1"; [ "$2" != absent ] || _rf=harbor-linux
  if is_gate "$1"; then   # harbor#1286: a gate runner is small and fixed: cpus 1, memory 2g unless a limits line says otherwise; events as harbor-linux's
    GOV_MEM="$(mem_want "$1")"; GOV_MEM="${GOV_MEM:-2g}"; GOV_CPUS="$(cpus_for_gate "$1")"
    GOV_EVENTS="$("$DOCKER" inspect --format '{{range .Mounts}}{{if eq .Destination "/gov-events"}}{{.Source}}{{end}}{{end}}' harbor-linux 2>/dev/null || :)"
    [ -n "$GOV_EVENTS" ] || GOV_EVENTS="$EVENTS"; return 0
  fi
  GOV_MEM="$("$DOCKER" inspect --format '{{.HostConfig.Memory}}' "$_rf" 2>/dev/null || :)"
  case "$GOV_MEM" in ''|0|*[!0-9]*) GOV_MEM=4g ;; *) GOV_MEM="${GOV_MEM}b" ;; esac
  _gl="$(mem_want "$1")"; [ -z "$_gl" ] || GOV_MEM="$_gl"   # a limits line naming it (or `harbor`) wins
  GOV_EVENTS="$("$DOCKER" inspect --format '{{range .Mounts}}{{if eq .Destination "/gov-events"}}{{.Source}}{{end}}{{end}}' "$_rf" 2>/dev/null || :)"
  [ -n "$GOV_EVENTS" ] || GOV_EVENTS="$EVENTS"
  GOV_CPUS="$(awk -F= '{ gsub(/[ \t]/, "") } $1 == "linux_min" { v = $2 } END { print v }' "$CFG/.harbor-ci-governor" 2>/dev/null || :)"
  case "$GOV_CPUS" in ''|.*|*.*.*|*[!0-9.]*) GOV_CPUS=1 ;; esac
}
# up --include-governance: a governance runner that is absent is created, a stopped idle one started; nothing running is touched,
# so no queue check is needed. Each is registered on the governance repo by its own name (harbor-linux-2 is not harbor-linux).
gov_up() {
  _f=0
  while IFS="$TAB" read -r _r _s _w _c gs _i runner busy _id _v _vd gst; do
    case "$gs" in
      absent) create_ok "$_c" || { _f=1; continue; }
              gov_ref "$_c" "$gs"
              if [ "$APPLY" != 1 ]; then log_note "would create $_c for $GOV_REPO: labels $(labels_for "$_c"), image $IMAGE, cpus $GOV_CPUS, memory $GOV_MEM, events $GOV_EVENTS:/gov-events"; continue; fi
              create "$GOV_REPO" "$_c" || _f=1 ;;
      running) ;;
      *) [ "$busy" = true ] && continue
         if [ "$APPLY" = 1 ]; then
           if "$DOCKER" start "$_c" >/dev/null 2>&1; then logline "$_c started"; log_ok "$_c started"; else log_fail "$_c would not start"; log_fix "docker logs $_c"; _f=1; fi
         else log_note "would start $_c"; fi ;;
    esac
  done < "$T/gov.tsv"
  return "$_f"
}
# A governance runner runs harbor's own required checks, so it is recreated only when stale AND idle AND GitHub shows no queued
# or in-progress run of the governance repo (an idle runner can still be the one a queued check is waiting for).
# It keeps what it has: the events mount's source, its memory; --cpus is the governor's idle floor (linux_min), which
# the governor moves live from the next tick; the hooks and the restart policy are what create sets (harbor#1083).
# One row at a time; the first failure stops the rest.
gov_refresh() {
  while IFS="$TAB" read -r _r _s _w _c gs _i runner busy rid _v _vd gst; do gov_refresh_one || return 1; done < "$T/gov.tsv"
}
gov_refresh_one() {
  # an absent runner (say, after a create that failed) is made again the same way, with the defaults for what it cannot read
  [ "$gst" = stale ] || [ "$gs" = absent ] || { log_note "$_c is on the current image"; return 0; }
  if [ "$runner" = unknown ]; then log_fail "$_c: GitHub did not answer, so it cannot be told whether the runner is busy"; log_fix "gh auth status"; return 1; fi
  [ "$busy" != true ] || { log_skip "$_c is running a job; left as it is"; return 0; }
  _q=0
  for _st in queued in_progress; do
    "$GH" api "repos/$GOV_REPO/actions/runs?status=$_st&per_page=1" > "$T/q.json" 2>/dev/null && jq -e '.workflow_runs | type == "array"' "$T/q.json" >/dev/null 2>&1 \
      || { log_fail "$_c: GitHub did not answer for the $_st runs of $GOV_REPO, so it cannot be told its checks are idle"; log_fix "gh auth status"; return 1; }
    _q=$((_q + $(jq '.workflow_runs | length' "$T/q.json")))
  done
  [ "$_q" = 0 ] || { log_skip "$_c: $GOV_REPO has queued or in-progress runs; left as it is, try again when they are done"; return 0; }
  create_ok "$_c" || return 1
  _old="$(box_id "$_c")"; _new="$(tag_id)"
  gov_ref "$_c" "$gs"
  if [ "$APPLY" != 1 ]; then
    log_note "would recreate $_c for $GOV_REPO: image $(sid "$_old") -> $(sid "$_new"), cpus $GOV_CPUS, memory $GOV_MEM, events $GOV_EVENTS:/gov-events"; return 0
  fi
  [ "$gs" = absent ] || still_idle "$_c" "$GOV_REPO" "$rid" || { log_skip "$_c took a job since the list was read; left as it is"; return 0; }
  [ "$gs" = absent ] || "$DOCKER" rm -f "$_c" >/dev/null 2>&1 || { log_fail "$_c would not be removed"; log_fix "docker rm -f $_c"; return 1; }
  [ "$rid" = - ] || "$GH" api -X DELETE "$(api_base "$GOV_REPO")/actions/runners/$rid" >/dev/null 2>&1 \
    || log_warn "$_c removed, but its registration $rid on $GOV_REPO is still there; the new one replaces it"
  create "$GOV_REPO" "$_c" || { log_fail "$_c was removed and not recreated: harbor's own checks have no runner"; log_fix "sh $0 refresh --apply --include-governance (it is made again when absent)"; return 1; }
  logline "$_c refreshed (governance): image $(sid "$_old") -> $(sid "$_new")"
}

# ── down: the container and its registration, never under a running job ───────────────────────
do_down() {
  c="$TARGET-linux"; slug="$OWNER/$TARGET"
  load_fleet; _m="$(awk -F'\t' -v r="$TARGET" '$1 == r { print $2 "\t" $4; exit }' "$T/desired.tsv")"
  if [ -n "$_m" ]; then slug="${_m%%"$TAB"*}"; c="${_m#*"$TAB"}"
  else   # an org runner above `runners N` (N was lowered): <org>-K is <org>-linux-K, registered at the org
    for _o in $ORGS; do case "$TARGET" in "$(orgrow "$_o")"-[2-9]) c="$(orgrow "$_o")-linux-${TARGET##*-}"; slug="$_o" ;; esac; done
  fi
  "$DOCKER" ps -a --format '{{.Names}} {{.Image}} {{.State}}' > "$T/ps.txt" 2>/dev/null || { log_fail "docker did not answer"; log_fix "colima status"; exit 2; }
  have=0; awk -v n="$c" '$1 == n { f = 1 } END { exit !f }' "$T/ps.txt" && have=1
  "$GH" api "$(api_base "$slug")/actions/runners" > "$T/r.json" 2>/dev/null && jq -e '.runners | type == "array"' "$T/r.json" >/dev/null 2>&1 \
    || { log_fail "$c: GitHub did not answer, so it cannot be told whether the runner is busy"; log_fix "gh auth status"; return 1; }
  set -- $(jq -r --arg n "$c" '[.runners[] | select(.name == $n)][0] // empty | [.id, (.busy | tostring)] | @tsv' "$T/r.json")
  rid=""; busy=false; [ "$#" -ge 2 ] && { rid="$1"; busy="$2"; }
  [ "$have" = 1 ] && "$DOCKER" top "$c" 2>/dev/null | grep -q 'Runner\.Worker' && busy=true
  [ "$have" = 1 ] || [ -n "$rid" ] || { log_skip "$c: no container and no registration, nothing to remove"; return 0; }
  [ "$busy" = false ] || { log_fail "$c is running a job; nothing was removed"; log_fix "wait for it to finish: sh $0 list"; return 1; }
  if [ "$APPLY" != 1 ]; then
    log_note "would remove $c$([ -n "$rid" ] && echo " and its registration $rid on $slug")"; log_note "dry run: pass --apply to do it"; return 0
  fi
  [ "$have" = 0 ] || "$DOCKER" rm -f "$c" >/dev/null 2>&1 || { log_fail "$c would not be removed"; log_fix "docker rm -f $c"; return 1; }
  [ -z "$rid" ] || "$GH" api -X DELETE "$(api_base "$slug")/actions/runners/$rid" >/dev/null 2>&1 \
    || { log_warn "$c removed, but its registration $rid on $slug is still there"; log_fix "gh api -X DELETE $(api_base "$slug")/actions/runners/$rid"; }
  logline "$c removed ($slug)"; log_ok "$c removed"
}

