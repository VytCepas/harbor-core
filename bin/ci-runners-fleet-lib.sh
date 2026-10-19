#!/usr/bin/env sh
# ci-runners-fleet-lib.sh (harbor#1060) — the fleet view: the desired set (load_fleet), the actual set (collect, gov_row), `list`, and the mount lines.
# Sourced by ci-runners.sh, never run: it sets no shell option and reads the entry point's variables ($T, $CONF, $GH, $DOCKER, ...).
. "$(dirname -- "$0")/log-lib.sh"   # a second source keeps the run's counts (log-lib.sh)

# ── the desired set: fleet repos whose workflows read vars.CI_RUNS_ON ──────────────────────────
load_fleet() {
  if [ -s "$SNAP" ] && jq -e 'type == "array"' "$SNAP" >/dev/null 2>&1; then cp "$SNAP" "$T/snap.json"
  elif [ -x "$ORCH" ] && "$ORCH" snapshot --fleet "$FLEET" --json > "$T/snap.json" 2>/dev/null; then :
  else log_fail "no fleet snapshot: $SNAP is absent and $ORCH did not answer"; log_fix "$ORCH snapshot --fleet $FLEET --json"; exit 2; fi
  : > "$T/desired.tsv"
  jq -r '.[] | .descriptor | select(.path != null and .name != null) | [.name, .path] | @tsv' "$T/snap.json" > "$T/members.tsv" || exit 2
  while IFS="$TAB" read -r _n _p; do
    [ -d "$_p/.github/workflows" ] || continue
    cat "$_p"/.github/workflows/*.y*ml 2>/dev/null | grep -q 'vars\.CI_RUNS_ON' || continue
    cat "$_p/.agents/config.yaml" "$_p/.claude/config.yaml" 2>/dev/null | grep -Eq '^ci_runner:[[:space:]]*hosted' && continue
    _s="$(git -C "$_p" remote get-url origin 2>/dev/null | sed -E 's#(\.git)?/?$##; s#.*[:/]([^/:]+/[^/:]+)$#\1#' || :)"
    # no origin naming a GitHub repo: never pushed, so there is nothing to register a runner to (it was guessed as $OWNER/<name>)
    case "$_s" in */*) ;; *) continue ;; esac
    case "$_s" in *[!A-Za-z0-9._/-]*) continue ;; esac
    printf '%s\t%s\t%s\t%s-linux\n' "${_s#*/}" "$_s" "$_p" "${_s#*/}" >> "$T/desired.tsv"
  done < "$T/members.tsv"
  # `repo OWNER/NAME`: a repo the fleet does not list; `org ORG [cap] [runners N]`: the org's runners, its slug the bare
  # org name, row <org> on <org>-linux and row <org>-K on <org>-linux-K (the governance runners' naming)
  if [ -f "$CONF" ]; then
    awk '$1 == "repo" && $2 ~ /^[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+$/ { n = $2; sub(/^[^\/]*\//, "", n); printf "%s\t%s\t-\t%s-linux\n", n, $2, n }' "$CONF" >> "$T/desired.tsv"
  fi
  for _o in $ORGS; do
    _b="$(orgrow "$_o")"; printf '%s\t%s\t-\t%s-linux\n' "$_b" "$_o" "$_b" >> "$T/desired.tsv"
    _k=2; while [ "$_k" -le "$(org_n "$_o")" ]; do printf '%s-%s\t%s\t-\t%s-linux-%s\n' "$_b" "$_k" "$_o" "$_b" "$_k" >> "$T/desired.tsv"; _k=$((_k + 1)); done
  done
  awk -F'\t' '!seen[$2 "\t" $4]++' "$T/desired.tsv" > "$T/desired.u" && mv "$T/desired.u" "$T/desired.tsv"
}

# ── the actual set: docker, then GitHub, one row a repo ───────────────────────────────────────
# the image id the configured tag names now, and whether <container> was made from another one (harbor#1075)
tag_id() { [ -n "${TAGID+x}" ] || TAGID="$("$DOCKER" image inspect --format '{{.Id}}' "$IMAGE" 2>/dev/null || :)"; printf '%s' "$TAGID"; }
box_id() { "$DOCKER" inspect --format '{{.Image}}' "$1" 2>/dev/null || :; }
is_stale() { _t="$(tag_id)"; _h="$(box_id "$1")"; [ -n "$_t" ] && [ -n "$_h" ] && [ "$_t" != "$_h" ]; }
sid() { printf '%s' "${1#sha256:}" | cut -c1-12; }
# rows.tsv: repo slug want container state image runner busy runner-id CI_RUNS_ON verdict   ("-" for an empty field)
# GitHub's runner list and CI_RUNS_ON are read once a slug: an org's N rows share them (rs.*, vs.*)
collect() {
  load_fleet; rm -f "$T"/rs.* "$T"/vs.*
  DOCKER_OK=1
  if ! "$DOCKER" ps -a --format '{{.Names}} {{.Image}} {{.State}}' > "$T/ps.txt" 2> "$T/ps.err"; then
    # a tick still lets a repo fall back to hosted (its runner is on GitHub's list); it reports no drift from a dead docker
    [ "$CMD" = tick ] || { log_fail "docker did not answer: $(head -n 1 "$T/ps.err")"; log_fix "docker ps; colima status"; exit 2; }
    DOCKER_OK=0; : > "$T/ps.txt"
  fi
  : > "$T/rows.tsv"; mount_rows
  while IFS="$TAB" read -r repo slug _p c; do
    cstate=absent; image=-; runner=absent; busy=false; rid=-
    # another owner's repo is billed and served elsewhere: listed, never provisioned or switched from this account.
    # A repo of an org with an org runner is served by that one container, and switched with the org.
    case "$slug" in */*) _own="${slug%%/*}" ;; *) _own="$OWNER" ;; esac
    if [ "$_own" != "$OWNER" ]; then
      if is_org "$_own"; then _vd=org; is_hold "$repo" && _vd=hold
        printf '%s\t%s\t0\t%s\t-\t-\t-\tfalse\t-\t-\t%s\n' "$repo" "$slug" "$(orgrow "$_own")-linux" "$_vd" >> "$T/rows.tsv"
      else printf '%s\t%s\t0\t%s\t-\t-\t-\tfalse\t-\t-\tforeign\n' "$repo" "$slug" "$c" >> "$T/rows.tsv"; fi
      continue
    fi
    set -- $(awk -v n="$c" '$1 == n { print $3, $2; exit }' "$T/ps.txt")
    [ "$#" -ge 2 ] && { cstate="$1"; image="$2"; }
    _sk="$(printf '%s' "$slug" | tr '/' '_')"
    if [ -f "$T/rs.$_sk" ] || { "$GH" api "$(api_base "$slug")/actions/runners" > "$T/rs.$_sk" 2>/dev/null && jq -e '.runners | type == "array"' "$T/rs.$_sk" >/dev/null 2>&1; } \
       || { rm -f "$T/rs.$_sk"; false; }; then
      cp "$T/rs.$_sk" "$T/r.json"; cp "$T/r.json" "$T/rn.$repo.json"
      set -- $(jq -r --arg n "$c" '[.runners[] | select(.name == $n)][0] // empty | [.id, .status, (.busy | tostring)] | @tsv' "$T/r.json")
      [ "$#" -ge 3 ] && { rid="$1"; runner="$2"; busy="$3"; }
    else runner=unknown; fi
    if [ "$cstate" = running ] && "$DOCKER" top "$c" 2>/dev/null | grep -q 'Runner\.Worker'; then busy=true; fi
    if [ -f "$T/vs.$_sk" ]; then v="$(cat "$T/vs.$_sk")"
    else v="$(var_get "$slug" 2>"$T/v.err" || :)"; v="$(printf '%s' "$v" | tr -d ' \r\n')"
      if [ -z "$v" ]; then if grep -qi 'not found' "$T/v.err" 2>/dev/null; then v=unset; else v='?'; fi; fi
      printf '%s' "$v" > "$T/vs.$_sk"; fi
    # `hold <org lower-cased>` holds every runner of the org (rows <org>, <org>-2 ..), not only the first
    _held=0; is_hold "$repo" && _held=1
    case "$slug" in */*) ;; *) is_hold "$(orgrow "$slug")" && _held=1 ;; esac
    if [ "$_held" = 1 ]; then verdict=hold
    elif [ "$cstate" = absent ]; then verdict=missing
    elif [ "$cstate" != running ]; then verdict=stopped
    elif [ "$runner" = unknown ]; then verdict=unknown
    elif [ "$runner" != online ]; then verdict=offline
    else verdict=ok; fi
    [ "$verdict" != ok ] || ! is_stale "$c" || verdict=stale   # harbor#1075: running and online, but on an image the tag has moved from
    printf '%s\t%s\t1\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$repo" "$slug" "$c" "$cstate" "$image" "$runner" "$busy" "$rid" "$v" "$verdict" >> "$T/rows.tsv"
  done < "$T/desired.tsv"
  # a *-linux (or *-linux-K) container nothing in the fleet asks for (harbor-linux-* are the governance runners, not fleet
  # runners); an org's runner above its `runners N` is one, row <org>-K
  while read -r n image cstate; do
    case "$n" in harbor-linux|harbor-linux-[0-9]) continue ;; *-linux|*-linux-[0-9]) ;; *) continue ;; esac
    awk -F'\t' -v c="$n" '$4 == c { f = 1 } END { exit !f }' "$T/desired.tsv" && continue
    _x="${n%-linux}"; case "$n" in *-linux-[0-9]) _x="$(grp_of "$n")-${n##*-}" ;; esac
    printf '%s\t-\t0\t%s\t%s\t%s\t-\tfalse\t-\t-\textra\n' "$_x" "$n" "$cstate" "$image" >> "$T/rows.tsv"
  done < "$T/ps.txt"
  gov_row
}
# gov.tsv: the governance runners (harbor-linux, harbor-linux-2 .. up to `governance N`), one read-only row each apart from
# rows.tsv (so up, switch, the alarm and the cache never see them); the 12th field says whether it is on a stale image
# (harbor#1083). Row 1 is named harbor; row K, harbor-K.
gov_name() { if [ "$1" = 1 ]; then echo harbor-linux; else echo "harbor-linux-$1"; fi; }
# gate_name: the gate runners (harbor#1286), harbor-gate, harbor-gate-2 .. up to `gate N`. NOT *-linux, on purpose: the governor
# discovers *-linux containers, so it never moves a gate runner's --cpus; it keeps the fixed minimum it was made with.
gate_name() { if [ "$1" = 1 ]; then echo harbor-gate; else echo "harbor-gate-$1"; fi; }
# gov_one <container> <row name> <verdict: governance|gate> — append one read-only row to gov.tsv
gov_one() {
  _g="$1"; _gn="$2"; _gv="$3"; gs=absent; gi=-; gr=absent; gb=false; gid=-; gst=current
  set -- $(awk -v n="$_g" '$1 == n { print $3, $2; exit }' "$T/ps.txt"); [ "$#" -ge 2 ] && { gs="$1"; gi="$2"; }
  if [ -s "$T/gr.json" ]; then
    set -- $(jq -r --arg n "$_g" '[.runners[] | select(.name == $n)][0] // empty | [.id, .status, (.busy | tostring)] | @tsv' "$T/gr.json")
    [ "$#" -ge 3 ] && { gid="$1"; gr="$2"; gb="$3"; }
  else gr=unknown; fi
  if [ "$gs" = running ] && "$DOCKER" top "$_g" 2>/dev/null | grep -q 'Runner\.Worker'; then gb=true; fi
  [ "$gs" = absent ] || ! is_stale "$_g" || gst=stale
  printf '%s\t%s\t0\t%s\t%s\t%s\t%s\t%s\t%s\t-\t%s\t%s\n' "$_gn" "$GOV_REPO" "$_g" "$gs" "$gi" "$gr" "$gb" "$gid" "$_gv" "$gst" >> "$T/gov.tsv"
}
gov_row() {
  : > "$T/gov.tsv"; _k=1
  "$GH" api "repos/$GOV_REPO/actions/runners" > "$T/gr.json" 2>/dev/null && jq -e '.runners | type == "array"' "$T/gr.json" >/dev/null 2>&1 || : > "$T/gr.json"
  while [ "$_k" -le "$GOVN" ]; do
    _rn="${GOV_REPO#*/}"; [ "$_k" = 1 ] || _rn="$_rn-$_k"
    gov_one "$(gov_name "$_k")" "$_rn" governance; _k=$((_k + 1))
  done
  _k=1
  while [ "$_k" -le "$GATEN" ]; do gov_one "$(gate_name "$_k")" "$(gate_name "$_k")" gate; _k=$((_k + 1)); done
}
# field <repo> <n> — a column of one row
field() { awk -F'\t' -v r="$1" -v n="$2" '$1 == r { print $n; exit }' "$T/rows.tsv"; }

do_list() {
  if [ "$JSON" = 1 ]; then
    jq -R -s 'split("\n") | map(select(. != "") | split("\t") | {repo: .[0], slug: .[1], want: (.[2] == "1"), name: .[3], container: .[4],
      image: .[5], runner: .[6], busy: (.[7] == "true"), runner_id: .[8], ci_runs_on: .[9], verdict: .[10],
      stale: (.[10] == "stale" or .[11] == "stale"), governance: (.[10] == "governance"), gate: (.[10] == "gate")})' "$T/rows.tsv" "$T/gov.tsv"
    return 0
  fi
  cat "$T/rows.tsv" "$T/gov.tsv" > "$T/all.tsv"
  printf '%-22s %-5s %-9s %-30s %-8s %-10s %s\n' REPO WANT CONTAINER IMAGE RUNNER CI_RUNS_ON VERDICT
  while IFS="$TAB" read -r repo _s want _c cstate image runner busy _r v verdict gst; do
    [ "$busy" = true ] && runner="$runner/busy"
    [ "$verdict" != stale ] || verdict="stale: sh $0 refresh --apply"
    [ "$gst" != stale ] || verdict="governance, stale (read-only: sh $0 refresh --apply --include-governance)"
    printf '%-22s %-5s %-9s %-30s %-8s %-10s %s\n' "$repo" "$([ "$want" = 1 ] && echo yes || echo no)" "$cstate" "$image" "$runner" "$v" "$verdict"
  done < "$T/all.tsv"
}

# ── mounts: `mount REPO HOST-PATH CONTAINER-PATH`, read-only, into REPO's container (harbor#1060) ─────────
# a repo's gates may read other trees (~/.claude/skills, a sibling checkout) at the same paths; a recreate without them is red.
RUNNER_HOME="/home/${HARBOR_CI_RUNNER_USER:-runner}"   # the image's user (actions-runner); spelt apart, as CI's own HOME is this path
MOUNT_ROOT="${HARBOR_CI_MOUNT_ROOT:-/Users}"; MOUNT_ROOT="${MOUNT_ROOT%/}/"   # what Colima shares into its VM; the suites swap it
mount_check() { # <host> <container> — prints the container path (~ expanded), or why the line is refused, and fails
  case "$1$2" in *:*|*,*) echo "a path holds ':' or ','"; return 1 ;; esac
  case "/$1/$2/" in */../*|*/./*) echo "a path holds a . or .. segment"; return 1 ;; esac
  case "$1" in "$MOUNT_ROOT"?*) ;; *) echo "$1 is outside $MOUNT_ROOT: Colima shares only that into its VM, so it would mount empty"; return 1 ;; esac
  [ -e "$1" ] || { echo "$1 does not exist: it would mount empty"; return 1; }
  _d="$1"; [ -d "$_d" ] || _d="$(dirname -- "$1")"
  case "$(cd -P -- "$_d" 2>/dev/null && pwd -P)/" in "$MOUNT_ROOT"?*) ;; *) echo "$1 resolves outside $MOUNT_ROOT"; return 1 ;; esac
  [ -d "$1" ] || [ ! -L "$1" ] || { echo "$1 is a symlink"; return 1; }
  case "$2" in "~") echo "$RUNNER_HOME" ;; "~/"?*) echo "$RUNNER_HOME/${2#??}" ;; /?*) echo "$2" ;;
    *) echo "$2 is not an absolute path or ~/..."; return 1 ;; esac
}
# mounts.tsv: repo, host path, container path (as written if refused), why it is refused ('-' if not) — every mount line
mount_rows() {
  : > "$T/mounts.tsv"; [ -f "$CONF" ] || return 0
  awk -v OFS='\t' '$1 == "mount" { for (i = 2; i <= 4; i++) if ($i == "") $i = "-"; print NF, $2, $3, $4 }' "$CONF" > "$T/mlines"
  while IFS="$TAB" read -r nf r h p; do
    if [ "$nf" != 4 ]; then why="not 'mount REPO HOST-PATH CONTAINER-PATH' (always read-only: there is no mode field)"; cp="$p"
    elif cp="$(mount_check "$h" "$p")"; then why=-; else why="$cp"; cp="$p"; fi
    printf '%s\t%s\t%s\t%s\n' "$r" "$h" "$cp" "$why" >> "$T/mounts.tsv"
  done < "$T/mlines"
}
# have.tsv: the bind mounts <container> carries, the governor's events dir aside: host, container path, ro|rw
mounts_of() {
  "$DOCKER" inspect --format '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}} {{.Destination}} {{.RW}}{{"\n"}}{{end}}{{end}}' "$1" 2>/dev/null \
    | awk -v OFS='\t' 'NF == 3 && $2 != "/gov-events" { print $1, $2, ($3 == "true" ? "rw" : "ro") }' > "$T/have.tsv"
}
do_mounts() { # list's MOUNTS block: each line against each container of its repo (or org), and what a container carries the config does not name
  : > "$T/mc.tsv"
  awk -F'\t' '$5 != "-" && $5 != "absent" { print $4 }' "$T/rows.tsv" | while read -r c; do printf '%s\t%s\n' "$(grp_of "$c")" "$c" >> "$T/mc.tsv"; done
  : > "$T/mout"; : > "$T/mdrift"
  while IFS="$TAB" read -r r h p why; do
    _cs="$(awk -F'\t' -v r="$r" '$1 == r { print $2 }' "$T/mc.tsv")"; _nc="$(printf '%s\n' "$_cs" | grep -c . || :)"
    if [ "$why" != - ]; then printf '%-22s %s -> %s  %s\n' "$r" "$h" "$p" "refused: $why" >> "$T/mout"; continue; fi
    [ -n "$_cs" ] || { printf '%-22s %s -> %s  %s\n' "$r" "$h" "$p" "no container" >> "$T/mout"; continue; }
    for c in $_cs; do
      mounts_of "$c"
      if grep -qxF "$h$TAB$p${TAB}ro" "$T/have.tsv"; then st=ok; [ "$_nc" = 1 ] || st="ok on $c"
      elif grep -qxF "$h$TAB$p${TAB}rw" "$T/have.tsv"; then st="DRIFT: read-write on $c"; echo "$c" >> "$T/mdrift"
      else st="DRIFT: not on $c"; echo "$c" >> "$T/mdrift"; fi
      printf '%-22s %s -> %s  %s\n' "$r" "$h" "$p" "$st" >> "$T/mout"
    done
  done < "$T/mounts.tsv"
  while IFS="$TAB" read -r r c; do
    mounts_of "$c"
    while IFS="$TAB" read -r h p m; do
      awk -F'\t' -v r="$r" -v h="$h" -v p="$p" '$1 == r && $2 == h && $3 == p { f = 1 } END { exit !f }' "$T/mounts.tsv" && continue
      printf '%-22s %s -> %s  DRIFT: on %s (%s), not in the config\n' "$r" "$h" "$p" "$c" "$m" >> "$T/mout"; echo "$c" >> "$T/mdrift"
    done < "$T/have.tsv"
  done < "$T/mc.tsv"
  [ -s "$T/mout" ] || return 0
  printf '\nMOUNTS (read-only, from %s)\n' "$CONF"; cat "$T/mout"
  for c in $(sort -u "$T/mdrift"); do
    log_warn "$c: its mounts differ from the config; it is adopted, never recreated"
    log_fix "when it is idle: sh $0 down $(awk -F'\t' -v c="$c" '$4 == c { print $1; exit }' "$T/rows.tsv") --apply && sh $0 up --apply"
  done
}

mounts_ok() { # <container> — fails, saying why, when one of its mount lines is refused; NMOUNTS is how many it has
  _bad=0; NMOUNTS=0
  while IFS="$TAB" read -r r _h _p why; do
    [ "$r" = "$(grp_of "$1")" ] || continue
    if [ "$why" != - ]; then log_fail "$1: mount refused, so it is not created: $why"; log_fix "correct or delete that mount line in $CONF"; _bad=1
    else NMOUNTS=$((NMOUNTS + 1)); fi
  done < "$T/mounts.tsv"
  [ "$_bad" = 0 ]
}


# ── limits: memory and cpus per runner (harbor#1060, 2026-10-13: one 1 GiB org runner OOM'd and held the org 3h) ──────
# `limits NAME [memory SIZE] [cpus N]`: NAME is one container, or a group: <repo>, <org lower-cased> (every runner of
# it) or `harbor` (every governance runner). Own line, then group line, then the global `memory`/`cpus` line (not for
# a governance runner, which keeps what it was made with), then 1g / 1. A SIZE that is not N[bkmg] is ignored.
grp_of() { case "$1" in *-linux-[0-9]) printf '%s' "${1%-linux-[0-9]}" ;; *) printf '%s' "${1%-linux}" ;; esac; }   # exampleorg-linux-2 -> exampleorg
is_gov() { case "$1" in harbor-linux|harbor-linux-[0-9]|harbor-gate|harbor-gate-[0-9]) return 0 ;; esac; return 1; }   # pool and gate runners alike
is_gate() { case "$1" in harbor-gate|harbor-gate-[0-9]) return 0 ;; esac; return 1; }
bytes() { # <SIZE> — in bytes (k m g are 1024-based, as docker reads them), or fails
  printf '%s\n' "$1" | awk '{ s = tolower($0) } s ~ /^[0-9]+[bkmg]?$/ { u = substr(s, length(s)); m = (u == "k") ? 1024 : (u == "m") ? 1048576 : (u == "g") ? 1073741824 : 1
    printf "%.0f\n", (s + 0) * m; ok = 1 } END { exit !ok }'
}
gib() { awk -v b="$1" 'BEGIN { printf "%.1fg", b / 1073741824 }'; }
limit() { # <container> <memory|cpus> — what a limits line gives it, its own line before its group's; empty when none
  [ -f "$CONF" ] || return 0
  awk -v c="$1" -v g="$(grp_of "$1")" -v k="$2" '$1 == "limits" { n = tolower($2); for (i = 3; i < NF; i += 2) if ($i == k) { if (n == c) o = $(i + 1); else if (n == g) p = $(i + 1) } }
    END { print (o != "" ? o : p) }' "$CONF" 2>/dev/null || :
}
mem_want() { # <container> — its EXPLICITLY configured memory (a limits line, else for a fleet or org runner the global memory line), or empty
  _mv="$(limit "$1" memory)"; [ -n "$_mv" ] || is_gov "$1" || _mv="$(conf memory)"
  [ -z "$_mv" ] || bytes "$_mv" >/dev/null || _mv=""
  printf '%s' "$_mv"
}
mem_for() { _mf="$(mem_want "$1")"; printf '%s' "${_mf:-$MEMORY}"; }   # what create gives a fleet or org runner
cpus_for() { _cf="$(limit "$1" cpus)"; case "$_cf" in ''|.*|*.*.*|*[!0-9.]*) _cf="$CPUS" ;; esac; printf '%s' "$_cf"; }
mem_have() { "$DOCKER" inspect --format '{{.HostConfig.Memory}}' "$1" 2>/dev/null | tr -d ' \r\n' || :; }   # bytes; 0 is no cap
mem_used() { dexec "$1" cat /sys/fs/cgroup/memory.current 2>/dev/null | tr -d ' \r\n' || :; }                 # bytes in use now

# list's MEMORY block: each runner container's cap against its configured value, then every running one's caps summed
# against the VM's memory, so an overcommit is visible (2026-10-13: 18 GiB of caps in a 6 GiB VM)
do_memory() {
  printf '\nMEMORY (cap now, configured in %s)\n' "$CONF"; _tot=0; _nr=0; _nocap=0
  while read -r n _i st; do
    case "$n" in *-linux|*-linux-[0-9]) ;; *) continue ;; esac
    h="$(mem_have "$n")"; w="$(mem_want "$n")"; _l="$(limit "$n" memory)"
    case "$h" in ''|*[!0-9]*) hs="?" ;; 0) hs=none ;; *) hs="$(gib "$h")" ;; esac
    if [ "$st" = running ]; then _nr=$((_nr + 1)); case "$h" in ''|0|*[!0-9]*) _nocap=$((_nocap + 1)) ;; *) _tot=$((_tot + h)) ;; esac; fi
    if [ -n "$_l" ] && ! bytes "$_l" >/dev/null; then why="limits memory $_l is not a size (N[bkmg]): ignored"; log_warn "$n: $why"; log_fix "correct the limits line in $CONF"
    elif [ -z "$w" ]; then if is_gov "$n"; then why="no limits line names it: kept as made"; else why="no memory line: made at $MEMORY, never changed"; fi
    elif [ "$hs" = "?" ]; then why="config $w: unread"
    elif [ "$h" = "$(bytes "$w")" ]; then why="config $w: ok"
    else
      # up --apply sets only a wanted, un-held runner (limits_up): a held or an extra one is left as it is, so no fix is offered
      case "$(awk -F'\t' -v c="$n" '$4 == c && ($3 == 1 || $11 == "extra") { print $11; exit }' "$T/rows.tsv")" in
        hold) why="config $w: differs, on hold: left as it is" ;;
        extra) why="config $w: differs, extra runner: left as it is" ;;
        *) why="config $w: DRIFT"
           _g=""; ! is_gov "$n" || _g=" --include-governance"
           log_warn "$n: memory $hs, config $w"; log_fix "sh $0 up --apply$_g (docker update, live; no recreate)" ;;
      esac
    fi
    printf '%-22s %-6s %s\n' "$n" "$hs" "$why"
  done < "$T/ps.txt"
  vm="$("$DOCKER" info --format '{{.MemTotal}}' 2>/dev/null | tr -d ' \r\n' || :)"
  _nc=""; [ "$_nocap" = 0 ] || _nc=" (+$_nocap with no cap)"
  case "$vm" in ''|0|*[!0-9]*) printf 'budget: %s running runner containers cap %s%s; the VM memory is unread (docker info)\n' "$_nr" "$(gib "$_tot")" "$_nc"; return 0 ;; esac
  printf 'budget: %s running runner containers cap %s%s against the VM'"'"'s %s (docker info): %s\n' "$_nr" "$(gib "$_tot")" "$_nc" "$(gib "$vm")" \
    "$(awk -v t="$_tot" -v v="$vm" 'BEGIN { if (t > v) printf "OVERCOMMITTED %.1fx: concurrent jobs near their caps are OOM-killed", t / v; else printf "fits, %.1fg spare", (v - t) / 1073741824 }')"
}
