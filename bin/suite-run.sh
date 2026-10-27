#!/usr/bin/env sh
# suite-run.sh — run many suites at once, longest first, and say which failed (harbor#679)
#
#   sh suite-run.sh [options] [suite...]   run the suites (default: every line of --list)
#   sh suite-run.sh --plan [options]       print the queue order and run nothing
#   sh suite-run.sh --tally <results> <key> <suite>...   one group's verdict from a run's results
#   sh suite-run.sh --combine <out> [--list F] [--include F] <results>...   N shards' results as one run's
#
#   -j, --jobs N       suites at once (HARBOR_SUITE_JOBS; default 3 x CPUs, 3 on macOS)
#   --list FILE        the candidate suites (default CONTRACTS/suites.txt)
#   --include FILE     keep only the suites FILE names
#   --select           ask bin/suite-select.sh which suites this changeset needs; the rest stand down
#   --shard K/N        run shard K of N of the selected suites, split by recorded time (stand-downs: shard 1)
#   --results FILE     keep the per-suite results here (TSV: verdict secs rc count suite reason)
#   --record           rewrite tests/suite-durations.tsv from this run's timings
#   --record-from FILE the same from a results file another run kept (a CI shard's), running nothing
#   --lint SECS        with --record/--record-from: the seconds shard 1 spends in bin/lint-conventions.sh (kept if omitted)
#   HARBOR_SUITE_TIMEOUT  seconds a suite may print nothing before it is cut off (default 900, 0 = none)
#   HARBOR_SUITE_HARD_TIMEOUT  seconds in all, however much it prints (default 4 x the above, 0 = none)
#   HARBOR_SUITE_CACHE=1  a queued suite whose inputs already passed is a `cached` row, not a run (bin/suite-cache.sh)
#
# WHY LONGEST FIRST. The wall time of a parallel run is set by its tail: a 40 s suite started last
# finishes 40 s after everything else. Measured 2026-10-04 on the Linux runner image (30 suites,
# 2 CPUs): manifest order P=6 121 s, longest first P=6 74 s. So the queue is ordered by the committed
# durations table, and a suite the table does not know runs FIRST — it may be the long one.
#
# SHARDS (harbor#1172). --shard K/N splits the selected suites over N jobs so no one job carries the
# whole run: longest first by the table, each to the shard with the least recorded time so far (the
# lowest K on a tie); a suite the table does not know weighs the table's mean. Shard 1 STARTS with the
# table's `bin/lint-conventions.sh` row, because CI runs the linter there before its suites (median 1.8 min,
# max 6.8, measured 2026-10-17): a split of suite time alone left shard 1 with 213 suites to shard 2's 113.
# Every shard derives the same split from the same inputs, so the jobs never talk. Their inputs can still differ — each job reads
# the base over the network and the repo's variables at its own start, and a job can die before it
# reports — so --combine refuses a suite in no shard's results or in two, rather than pass a run that
# dropped or doubled one.
#
# EVERY QUEUED SUITE MUST COME BACK. A suite with no result line (a worker killed outright, or damaged
# results) is a failure named LOST, never a quiet omission: a runner that drops suites reads as a faster
# green run. A worker that is signalled or exits early writes its own fail row, naming why (harbor#1378).
set -eu

DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT="${HARBOR_ROOT:-$(CDPATH= cd -- "$DIR/.." && pwd)}"
DUR="$ROOT/tests/suite-durations.tsv"
TAB="$(printf '\t')"

usage() { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

_path() { case "$1" in */*) printf '%s/%s' "$ROOT" "$1" ;; *) printf '%s/bin/%s' "$ROOT" "$1" ;; esac; }
_names() { grep -vE '^[[:space:]]*(#|$)' "$1" | awk '{ print $1 }'; }  # a list file's suite column

# ── one suite, inside a worker (xargs calls this file back) ───────────────────
if [ "${1:-}" = "--_one" ]; then
  _s="$2"; _b="${_s##*/}"
  # THE POOL'S WIDTH IS RE-READ BEFORE EVERY SUITE (harbor#1032). xargs starts --jobs workers once, but
  # ci-governor.sh can cut harbor-linux to 0.5 CPU mid-run (`docker update --cpus`, which cpu.max shows
  # live): six suites on half a core is how a run hit its 900s timeouts on 2026-10-04. So a worker waits
  # here, outside the timeout, until fewer than 3 x the current quota are running. No quota (the Mac):
  # the pool as started, and the governor's own slots do the throttling.
  _allow() {
    _q="$(cat "${HARBOR_CPU_MAX:-/sys/fs/cgroup/cpu.max}" 2>/dev/null || :)"
    case "$_q" in
      [0-9]*' '[0-9]*) printf '%s\n' "$_q" | awk -v j="$_SR_JOBS" '{ a = int(3 * $1 / $2); if (a < 1) a = 1; if (a > j) a = j; print a }' ;;
      *) printf '%s\n' "$_SR_JOBS" ;;
    esac
  }
  # Every descendant of a pid, stopped first so none forks a replacement, then killed (the way reap.sh does).
  # The confinement refuses ps (harbor#555), so the suite's own process group is stopped and killed as well.
  _killtree() {
    _kf="$_SR_LOGS/../kt.$$"; _ka=" $1 "; _kk=""
    kill -STOP "-$1" 2>/dev/null || :
    while :; do
      ps -A -o pid= -o ppid= > "$_kf" 2>/dev/null || :
      _kn="$(awk -v all="$_ka" 'index(all, " " $2 " ") && !index(all, " " $1 " ") { printf "%s ", $1 }' "$_kf")" || _kn=""
      [ -n "$_kn" ] || break
      kill -STOP $_kn 2>/dev/null || :
      _ka="$_ka$_kn"; _kk="$_kk $_kn"
    done
    rm -f "$_kf"; kill -9 "-$1" 2>/dev/null || :; kill -9 $1 $_kk 2>/dev/null || :
  }
  # A WORKER NEVER VANISHES (harbor#1378): a signal or an early exit still writes a fail row that names it,
  # so LOST is left meaning a damaged results file. On exit it drops its slot marker, and the lock if it holds it.
  _t0="$(date +%s)"; _sp=""; _held=""; _done=""
  _row() { printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$(( $(date +%s) - _t0 ))" "$2" "$3" "$_s" "$4" >> "$_SR_RES"; _done=1; }
  _sig() { [ -z "$_sp" ] || _killtree "$_sp"; _row fail "$2" - "the worker was killed by SIG$1"; exit "$2"; }
  _run="$_SR_LOGS/../running"; mkdir -p "$_run"
  trap '_e=$?; rm -f "$_run/$$"; [ -z "$_held" ] || rm -f "$_run.lock"; [ -n "$_done" ] || _row fail "$_e" - "the worker exited $_e before its result"' EXIT
  trap '_sig TERM 143' TERM; trap '_sig INT 130' INT; trap '_sig HUP 129' HUP
  # The slot lock is a file the shell creates with O_EXCL (set -C), never mkdir: uutils mkdir 0.10 (Ubuntu
  # 26.04, ubuntu-latest) exits 0 when it loses the race, so two workers held it and one died (harbor#1378).
  while :; do
    if ( set -C; printf '%s\n' "$$" > "$_run.lock" ) 2>/dev/null; then
      _held=1
      for _m in "$_run"/*; do [ -f "$_m" ] && ! kill -0 "${_m##*/}" 2>/dev/null && rm -f "$_m"; done
      if [ "$(find "$_run" -type f | wc -l | tr -d ' ')" -lt "$(_allow)" ]; then : > "$_run/$$"; _held=""; rm -f "$_run.lock"; break; fi
      _held=""; rm -f "$_run.lock"; sleep 0.5    # full: wait for a suite to finish
    else
      # Broken only when its holder is dead (read twice, as event-bus.sh does) or it is over a minute old.
      _lp=""; { read -r _lp < "$_run.lock"; } 2>/dev/null || :
      if { [ -n "$_lp" ] && ! kill -0 "$_lp" 2>/dev/null; } || [ -n "$(find "$_run.lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
        _lq=""; { read -r _lq < "$_run.lock"; } 2>/dev/null || :; [ "$_lq" != "$_lp" ] || rm -f "$_run.lock"
      fi
      sleep 0.1                         # another worker is counting
    fi
  done
  _log="$_SR_LOGS/$(printf '%s' "$_s" | tr '/' '_').log"
  _t0="$(date +%s)"
  cd "$ROOT"
  # One local CPU slot per suite through bin/ci-governor.sh (harbor#1032): the suite's output still goes to
  # its log, the governor's "waiting for a slot" to the terminal. Under Actions it is a plain run.
  # The terminal is fd 2 by dup, never /dev/stderr by name: the confinement refuses that open (harbor#555).
  if [ -f "$DIR/ci-governor.sh" ]; then set -- sh "$DIR/ci-governor.sh" run --out "$_log" -- sh "$(_path "$_s")"; _sink=""
  else set -- sh "$(_path "$_s")"; _sink="$_log"; fi
  # THE LIMIT IS FOR A HANG, NOT FOR A SLOW RUN (harbor#1149): the suite is cut off when its log has not
  # grown for _SR_TMO seconds, or after _SR_HARD in all. A wall-clock limit failed four suites that were
  # still printing, on a loaded runner (27-182 s recorded, 900 s+ measured). No timeout(1) needed, so the
  # Mac enforces it too. Each tick is a log-size read and a kill -0: no fork a signal could be lost in.
  # Monitor mode gives the suite its own process group for _killtree; a shell with no tty (dash) declines it, and
  # there ps still walks the tree. Stdin stays /dev/null, as it is for any background job without monitor mode.
  set -m 2>/dev/null || :
  if [ -n "$_sink" ]; then "$@" > "$_sink" 2>&1 < /dev/null & else "$@" >&2 2>&1 < /dev/null & fi
  _sp=$!; set +m 2>/dev/null || :
  # Its own group is out of reach of a signal to the run's group, so a stopped worker takes its suite with it (_sig).
  _sz=-1; _lc="$(date +%s)"; _rc=""
  while kill -0 "$_sp" 2>/dev/null; do
    sleep 0.5
    _nw="$(date +%s)"
    # No log yet is the governor waiting for a CPU slot, bounded by its own deadline: not a hang, so the idle clock waits too.
    if [ -f "$_log" ]; then _nz="$(wc -c < "$_log" | tr -d ' ')"; else _nz=-1; _lc="$_nw"; fi
    if [ "$_nz" != "$_sz" ]; then _sz="$_nz"; _lc="$_nw"; fi
    if { [ "$_SR_TMO" != 0 ] && [ $(( _nw - _lc )) -ge "$_SR_TMO" ]; } || { [ "$_SR_HARD" != 0 ] && [ $(( _nw - _t0 )) -ge "$_SR_HARD" ]; }; then
      _killtree "$_sp"; _rc=124; break
    fi
  done
  if [ -n "$_rc" ]; then wait "$_sp" 2>/dev/null || :; else _rc=0; wait "$_sp" || _rc=$?; fi
  _n="$(awk -v k="${_b%.sh}:" '$1 == k { print $2; exit }' "$_log")"
  _v=pass; _why=""
  [ "$_rc" -eq 0 ] || { _v=fail; _why="exited $_rc"; }
  [ "$_rc" -ne 124 ] || _why="timed out: no output for ${_SR_TMO}s, or ${_SR_HARD}s in all"
  _row "$_v" "$_rc" "${_n:--}" "$_why"
  exit 0
fi

. "$DIR/log-lib.sh"
log_init suite-run

# ── --tally: one group's verdict, published for the CI jobs that relay it ────
# pass = every named suite has a result and none failed, and they agree on whether they ran (a split
# group is the defect --sum refuses too). A suite that ran publishes its count; a ran one with none is
# refused rather than summed as 0. Outputs: <key>=pass|fail, <key>_ran, <key>_count.
if [ "${1:-}" = "--tally" ]; then
  [ $# -ge 4 ] || usage
  _res="$2"; _key="$3"; shift 3
  log_head "tally $_key"
  _v=pass; _ran=""; _tot=0; _cnt=yes
  for _s in "$@"; do
    _row="$(awk -F '\t' -v s="$_s" '$5 == s { print $1 "\t" $4; exit }' "$_res" 2>/dev/null || :)"
    case "$_row" in
      '') _v=fail; log_fail "$_key: $_s has no result in $_res — it never ran"
          log_nofix "bin/suite-run.sh: run $_s in the same suite-run as the rest of $_key"; continue ;;
      fail*) _v=fail; log_fail "$_key: $_s failed"; log_nofix "$_s"; continue ;;
    esac
    _r=true; case "$_row" in skip*) _r=false ;; esac
    if [ -n "$_ran" ] && [ "$_ran" != "$_r" ]; then
      _v=fail; log_fail "$_key: $_s ran=$_r but an earlier suite ran=$_ran — the group must run or stand down together"
      log_nofix "CONTRACTS/suite-paths.txt: give every suite of $_key the same declaration"
    fi
    _ran="$_r"
    [ "$_r" = true ] || continue
    _c="${_row#*"$TAB"}"
    case "$_c" in ''|-|*[!0-9]*) _cnt=no ;; *) _tot=$((_tot + _c)) ;; esac
  done
  [ -n "$_ran" ] || _ran=false
  if [ "$_ran" = true ] && [ "$_cnt" = no ]; then
    _v=fail; log_fail "$_key: a suite that ran printed no '<name>: N passed' count; refusing to publish one"
    log_nofix "CONTRACTS/logging.md — a suite ends with its '<name>: N passed, M failed' line"
  fi
  [ "$_v" = pass ] && log_ok "$_key: $# suite(s), ran=$_ran, count=$_tot"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf '%s=%s\n%s_ran=%s\n%s_count=%s\n' "$_key" "$_v" "$_key" "$_ran" "$_key" "$_tot" >> "$GITHUB_OUTPUT"
  fi
  log_end; exit $?
fi

# ── options ───────────────────────────────────────────────────────────────────
JOBS="${HARBOR_SUITE_JOBS:-}"; LIST="$ROOT/CONTRACTS/suites.txt"; INC=""; SEL=0; RES=""; REC=0; PLAN=0
SHARD=""; COMB=""; RECFROM=""; LINT=""; LINTKEY="bin/lint-conventions.sh"
while [ $# -gt 0 ]; do
  case "$1" in
    -j|--jobs) [ $# -ge 2 ] || usage; JOBS="$2"; shift 2 ;;
    --list) [ $# -ge 2 ] || usage; LIST="$2"; shift 2 ;;
    --include) [ $# -ge 2 ] || usage; INC="$2"; shift 2 ;;
    --results) [ $# -ge 2 ] || usage; RES="$2"; shift 2 ;;
    --shard) [ $# -ge 2 ] || usage; SHARD="$2"; shift 2 ;;
    --combine) [ $# -ge 2 ] || usage; COMB="$2"; shift 2 ;;
    --record-from) [ $# -ge 2 ] || usage; RECFROM="$2"; shift 2 ;;
    --lint) [ $# -ge 2 ] || usage; LINT="$2"; shift 2 ;;
    --select) SEL=1; shift ;;
    --record) REC=1; shift ;;
    --plan) PLAN=1; shift ;;
    -h|--help) usage ;;
    -*) printf 'suite-run: unknown option: %s\n' "$1" >&2; usage ;;
    *) break ;;
  esac
done
case "$LINT" in *[!0-9]*) printf 'suite-run: --lint wants whole seconds, got %s\n' "$LINT" >&2; exit 2 ;; esac
for _f in "$LIST" $INC; do [ -f "$_f" ] || { printf 'suite-run: no such list: %s\n' "$_f" >&2; exit 2; }; done
SK=""; SN=""
if [ -n "$SHARD" ]; then # K/N, 1 <= K <= N, no leading zeros
  case "$SHARD" in [1-9]*/[1-9]*) SK="${SHARD%/*}"; SN="${SHARD#*/}" ;; esac
  case "$SK$SN" in ''|*[!0-9]*) printf 'suite-run: --shard wants K/N with 1 <= K <= N, got %s\n' "$SHARD" >&2; exit 2 ;; esac
  [ "$SK" -le "$SN" ] || { printf 'suite-run: --shard wants K/N with 1 <= K <= N, got %s\n' "$SHARD" >&2; exit 2; }
fi

_cpus() { # a container's CPU quota (cgroup v2) when it has one, else the online CPUs
  _q="$(cat /sys/fs/cgroup/cpu.max 2>/dev/null || :)"
  case "$_q" in [0-9]*' '[0-9]*) printf '%s\n' "$_q" | awk '{ c = int(($1 + $2 - 1) / $2); print (c < 1 ? 1 : c) }'; return ;; esac
  getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2
}
# 3 x CPUs: the measured knee on the Linux image (P=6 and P=10 both 74 s on 2 CPUs, P=3 130 s). The
# Mac measured the other way under the operator's own load (P=3 354 s, P=6 438 s), so it gets 3.
# A GitHub-hosted runner gets 1 x: at P=12 on its 4 shared vCPUs floor-test's Q-R4 latency budget ran
# 61 s of 60 (harbor-core's first CI run, 2026-10-19), a red that is the load's and not the guard's.
if [ -z "$JOBS" ]; then
  if [ "$(uname -s)" = Darwin ]; then JOBS=3
  elif [ "${RUNNER_ENVIRONMENT:-}" = github-hosted ]; then JOBS=$(_cpus)
  else JOBS=$(( $(_cpus) * 3 )); fi
fi
case "$JOBS" in ''|*[!0-9]*|0) printf 'suite-run: --jobs wants a positive number, got %s\n' "$JOBS" >&2; exit 2 ;; esac

_td="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"  # a TMPDIR ending in / would print a // path
WORK="$(mktemp -d "${_td%/}/suite-run.XXXXXX")"
# The work dir goes when the run is green and stays when it is not: a FAIL line names a log inside it.
KEEP=0; trap '[ "$KEEP" = 1 ] || rm -rf "$WORK"' EXIT
[ -n "$RES" ] || RES="$WORK/results.tsv"
mkdir -p "$WORK/logs"

_dur() { if [ -f "$DUR" ]; then printf '%s' "$DUR"; else printf /dev/null; fi; }
_record() { # <results> — merge: its timings win, suites it did not run keep theirs, suites gone from the manifest go
  { _names "$ROOT/CONTRACTS/suites.txt"; printf '%s\n' "$LINTKEY"; } > "$WORK/man"   # the linter is no suite: its row rides along
  {
    printf '# generated by bin/suite-run.sh --record — do not hand-edit (seconds <TAB> suite, longest first)\n'
    awk -F '\t' -v OFS='\t' -v lk="$LINTKEY" -v lint="$LINT" 'FILENAME == ARGV[1] { if ($0 !~ /^#/ && NF >= 2) d[$2] = $1; next }
      FILENAME == ARGV[2] { if ($1 != "skip" && $1 != "cached") d[$5] = $2; next }
      $1 == lk && lint != "" { d[lk] = lint }
      ($1 in d) { print d[$1], $1 }' "$(_dur)" "$1" "$WORK/man" \
      | sort -t "$TAB" -k1,1nr -k2,2
  } > "$WORK/dur.new"
  mv "$WORK/dur.new" "$DUR"
  log_ok "recorded $(grep -vc '^#' "$DUR" || :) durations in ${DUR#"$ROOT"/}"
}
if [ -n "$RECFROM" ]; then
  [ -f "$RECFROM" ] || { printf 'suite-run: no such results file: %s\n' "$RECFROM" >&2; exit 2; }
  log_head record; _record "$RECFROM"; log_end; exit $?
fi

# ── the candidates: positional suites, else the list; then include ───
# Under --combine the positional arguments are results files and the candidates are the list's.
if [ $# -gt 0 ] && [ -z "$COMB" ]; then printf '%s\n' "$@" > "$WORK/cand"; else _names "$LIST" > "$WORK/cand"; fi
for _s in $(cat "$WORK/cand"); do
  [ -f "$(_path "$_s")" ] || { printf 'suite-run: no such suite: %s\n' "$_s" >&2; exit 2; }
done
# A name in an include file that is not a candidate is a stale list, refused rather than ignored: a
# quick level that silently shrinks is a suite leaving CI unseen. (--exclude went with macOS CI, harbor#1060.)
if [ -n "$INC" ]; then
  _names "$INC" | while IFS= read -r _n; do grep -Fxq -- "$_n" "$WORK/cand" || printf '%s\n' "$_n"; done > "$WORK/stale"
  if [ -s "$WORK/stale" ]; then
    printf 'suite-run: %s names suite(s) that are not candidates: %s\n' "${INC#"$ROOT"/}" "$(tr '\n' ' ' < "$WORK/stale")" >&2
    exit 2
  fi
  _names "$INC" > "$WORK/names"
  awk -v nf="$WORK/names" 'FILENAME == nf { n[$0] = 1; next } $0 in n' "$WORK/names" "$WORK/cand" > "$WORK/next"
  mv "$WORK/next" "$WORK/cand"
fi

# ── --combine: the shards' results as one run's, every candidate exactly once ──
# One row per candidate goes to <out>, so --tally reads it as it reads an unsharded run's: a LOST suite has
# no row (its group fails as "never ran") and a DUPLICATE one gets a single fail row, never its first row.
if [ -n "$COMB" ]; then
  [ $# -gt 0 ] || usage
  log_head combine
  : > "$WORK/all"
  for _f in "$@"; do
    if [ -f "$_f" ]; then cat "$_f" >> "$WORK/all"
    else log_fail "no results at $_f — that shard never reported"; log_nofix "the shard's job: it ended before writing its results"; fi
  done
  awk -F '\t' -v OFS='\t' -v cf="$WORK/cand" -v rf="$WORK/rep" '
    FILENAME == cf { c[++nc] = $1; isc[$1] = 1; next }
    NF == 0 { next }
    { n[$5]++; if (!($5 in row)) row[$5] = $0; if (!($5 in isc) && !($5 in st)) { st[$5] = 1; so[++ns] = $5 } }
    END {
      for (i = 1; i <= nc; i++) {
        s = c[i]
        if (!(s in n)) print "LOST", s > rf
        else if (n[s] > 1) { print "DUPLICATE", s, n[s] > rf; print "fail", 0, "-", "-", s, "in " n[s] " shards\047 results" }
        else print row[s]
      }
      for (i = 1; i <= ns; i++) print "STRAY", so[i] > rf
    }' "$WORK/cand" "$WORK/all" > "$COMB"
  [ -f "$WORK/rep" ] || : > "$WORK/rep"
  _why="bin/suite-run.sh --shard: every shard must split the same selection (same commit, same base, same lists)"
  while IFS="$TAB" read -r _k _s _n; do
    case "$_k" in
      LOST) log_fail "LOST: $_s is a candidate and no shard has a result for it"; log_nofix "$_why" ;;
      DUPLICATE) log_fail "DUPLICATE: $_s has $_n results across the shards"; log_nofix "$_why" ;;
      STRAY) log_fail "STRAY: $_s has a result and is not a candidate of ${LIST#"$ROOT"/}"; log_nofix "$_why" ;;
    esac
  done < "$WORK/rep"
  [ -s "$WORK/rep" ] || log_ok "every candidate has exactly one result across the $# file(s)"
  _nc="$(awk -F '\t' '$1 == "cached"' "$COMB" | grep -c . || :)"; [ "$_nc" = 0 ] && _nc="" || _nc=", $_nc cached"
  log_note "$# shard result file(s), $(grep -c . "$WORK/cand" || :) candidate(s): $(awk -F '\t' '$1 == "pass"' "$COMB" | grep -c . || :) passed$_nc, $(awk -F '\t' '$1 == "fail"' "$COMB" | grep -c . || :) failed, $(awk -F '\t' '$1 == "skip"' "$COMB" | grep -c . || :) stood down — combined: $COMB"
  log_end; exit $?
fi

# ── selection: one suite-select --list for the lot, not one call per suite ────
: > "$RES"   # here, not earlier: --record-from and --combine read results files and must not empty one
if [ "$SEL" = 1 ]; then
  if ! HARBOR_ROOT="$ROOT" sh "$DIR/suite-select.sh" --list > "$WORK/verdicts" 2> "$WORK/verdicts.err"; then
    log_head select; log_fail "bin/suite-select.sh --list failed: $(head -3 "$WORK/verdicts.err" | tr '\n' ' ')"
    log_nofix "bin/suite-select.sh"; log_end; exit 1
  fi
  awk -v cf="$WORK/cand" 'FILENAME == cf { c[$1] = 1; next } $1 == "SKIP" && ($2 in c) { s = $2; $1 = ""; $2 = ""; sub(/^ +/, ""); print "skip\t0\t-\t-\t" s "\t" $0 }' \
    "$WORK/cand" "$WORK/verdicts" >> "$RES"
  awk -F '\t' -v rf="$RES" 'FILENAME == rf { d[$5] = 1; next } !($1 in d)' "$RES" "$WORK/cand" > "$WORK/next"; mv "$WORK/next" "$WORK/cand"
fi

# ── the shard: this job's share of the selection (SHARDS above) ──
# split: shard <TAB> manifest index <TAB> suite <TAB> weight, for every selected suite.
SHNOTE=""
if [ -n "$SK" ]; then
  # Shard 1's head start: the linter's recorded seconds (the table's LINTKEY row), never counted as a suite.
  PRE="$(awk -F '\t' -v lk="$LINTKEY" '$2 == lk && $1 ~ /^[0-9]+$/ { print $1; exit }' "$(_dur)")"; PRE="${PRE:-0}"
  awk -F '\t' -v OFS='\t' -v df="$(_dur)" -v lk="$LINTKEY" '
    FILENAME == df { if ($0 !~ /^#/ && NF >= 2 && $1 ~ /^[0-9]+$/ && $2 != lk) { d[$2] = $1; t += $1; k++ } next }
    { s[++n] = $1 }
    END { u = k ? int((t + k - 1) / k) : 1; if (u < 1) u = 1
          for (i = 1; i <= n; i++) print ((s[i] in d) ? d[s[i]] : u), i, s[i] }' "$(_dur)" "$WORK/cand" \
    | sort -t "$TAB" -k1,1nr -k2,2n \
    | awk -F '\t' -v OFS='\t' -v n="$SN" -v pre="$PRE" 'BEGIN { l[1] = pre } { b = 1; for (i = 2; i <= n; i++) if (l[i] < l[b]) b = i; l[b] += $1; print b, $2, $3, $1 }' > "$WORK/split"
  awk -F '\t' -v k="$SK" '$1 == k' "$WORK/split" | sort -t "$TAB" -k2,2n | cut -f3 > "$WORK/cand"
  SHNOTE="$(awk -F '\t' -v k="$SK" -v n="$SN" -v pre="$PRE" '{ t += $4; a++; w[$1] += $4 } $1 == k { c++ }
    END { w[1] += pre; for (i = 1; i <= n; i++) all = all (i > 1 ? " " : "") w[i] "s"
          printf "shard %d/%d: %d of %d selected suite(s), %ds of %ds recorded (linter %ds on shard 1; every shard: %s)", k, n, c, a, w[k], t + pre, pre, all }' "$WORK/split")"
  # The stand-downs are reported once, by shard 1, so the shards' results combine to each suite once.
  if [ "$SK" != 1 ]; then
    _ns="$(awk -F '\t' '$1 == "skip"' "$RES" | grep -c . || :)"
    [ "$_ns" = 0 ] || SHNOTE="$SHNOTE; $_ns stood down, reported by shard 1"
    awk -F '\t' '$1 != "skip"' "$RES" > "$WORK/next"; cat "$WORK/next" > "$RES"
  fi
fi

# ── the queue: unknown first, then longest first; manifest order breaks ties ──
awk -F '\t' -v OFS='\t' -v df="$(_dur)" 'FILENAME == df { if ($0 !~ /^#/ && NF >= 2) d[$2] = $1; next }
  { print (($1 in d) ? d[$1] : 999999), FNR, $1 }' "$(_dur)" "$WORK/cand" \
  | sort -t "$TAB" -k1,1nr -k2,2n | cut -f3 > "$WORK/queue"
if [ "$PLAN" = 1 ]; then [ -z "$SHNOTE" ] || printf "%s\n" "$SHNOTE" >&2; cat "$WORK/queue"; rm -rf "$WORK"; exit 0; fi

# ── the cache (harbor#1288, CONTRACTS/suite-cache.md): opt-in, never on main nor when everything runs ──
# A queued suite whose key holds a recorded pass leaves the queue as a `cached` row carrying that pass's
# time and count, so --tally, --combine and the counts read it as they read a run. Unset: nothing here runs.
CNOTE=""
if [ "${HARBOR_SUITE_CACHE:-}" = 1 ]; then
  if CNOTE="$(HARBOR_ROOT="$ROOT" sh "$DIR/suite-cache.sh" lookup "$WORK/queue" "$WORK/keys" "$WORK/hits" 2>&1)"; then
    cat "$WORK/hits" >> "$RES"
    awk -F '\t' -v hf="$WORK/hits" 'FILENAME == hf { h[$5] = 1; next } !($1 in h)' "$WORK/hits" "$WORK/queue" > "$WORK/next"
    mv "$WORK/next" "$WORK/queue"
  else
    rm -f "$WORK/keys"
  fi
fi

NQ="$(grep -c . "$WORK/queue" || :)"
log_head "run"
[ -z "$SHNOTE" ] || log_note "$SHNOTE"
[ -z "$CNOTE" ] || log_note "cache $(printf '%s' "$CNOTE" | head -1)"
[ ! -s "$WORK/hits" ] || while IFS="$TAB" read -r _v _secs _x _y _s _why; do log_ok "cached $_s — $_why"; done < "$WORK/hits"
log_note "$NQ suite(s), $JOBS at a time, longest first by ${DUR#"$ROOT"/}$([ -f "$DUR" ] || printf ' (absent: manifest order)')"
_skips="$(awk -F '\t' '$1 == "skip"' "$RES")"
[ -z "$_skips" ] || printf '%s\n' "$_skips" | while IFS="$TAB" read -r _v _x _y _z _s _why; do log_skip "$_s stood down — $_why"; done

# ── run: xargs keeps JOBS workers busy in queue order; this loop reports as they finish ──
_SR_LOGS="$WORK/logs"; _SR_RES="$RES"; _SR_TMO="${HARBOR_SUITE_TIMEOUT:-900}"; _SR_JOBS="$JOBS"
export _SR_LOGS _SR_RES _SR_TMO _SR_JOBS
case "$_SR_TMO" in *[!0-9]*) printf 'suite-run: HARBOR_SUITE_TIMEOUT wants seconds, got %s\n' "$_SR_TMO" >&2; exit 2 ;; esac
_SR_HARD="${HARBOR_SUITE_HARD_TIMEOUT:-$(( _SR_TMO * 4 ))}"; export _SR_HARD
case "$_SR_HARD" in *[!0-9]*) printf 'suite-run: HARBOR_SUITE_HARD_TIMEOUT wants seconds, got %s\n' "$_SR_HARD" >&2; exit 2 ;; esac
T0="$(date +%s)"
# A queue the cache emptied starts no pool: GNU xargs would run one worker with no suite.
if [ -s "$WORK/queue" ] || [ ! -f "$WORK/keys" ]; then
  xargs -P "$JOBS" -n 1 sh "$DIR/suite-run.sh" --_one < "$WORK/queue" &
  XP=$!
else XP=""; fi
SEEN="$(grep -c . "$RES" || :)"
_report() { # every result line past SEEN, once each
  _now="$(grep -c . "$RES" || :)"
  [ "$_now" -gt "$SEEN" ] || return 0
  sed -n "$((SEEN + 1)),${_now}p" "$RES" > "$WORK/new"; SEEN="$_now"
  while IFS="$TAB" read -r _v _secs _rc _n _s _why; do
    case "$_v" in
      pass) log_ok "${_secs}s $_s" ;;
      fail) log_fail "${_secs}s $_s $_why — log: $WORK/logs/$(printf '%s' "$_s" | tr '/' '_').log"; log_nofix "$_s" ;;
    esac
  done < "$WORK/new"
}
while [ -n "$XP" ] && kill -0 "$XP" 2>/dev/null; do _report; sleep 1; done
[ -z "$XP" ] || wait "$XP" || :
_report
WALL=$(( $(date +%s) - T0 ))

# ── accounting: every queued suite has exactly one result ─────────────────────
awk -F '\t' -v rf="$RES" 'FILENAME == rf { n[$5]++; next } n[$1] != 1 { print $1 }' "$RES" "$WORK/queue" > "$WORK/lost"
while IFS= read -r _s; do
  [ -n "$_s" ] || continue
  log_fail "LOST: $_s was queued and has no single result line — a worker died or the results were damaged"
  log_nofix "bin/suite-run.sh (results: $RES)"
done < "$WORK/lost"

_np="$(awk -F '\t' '$1 == "pass"' "$RES" | grep -c . || :)"
_nf="$(awk -F '\t' '$1 == "fail"' "$RES" | grep -c . || :)"
_ns="$(awk -F '\t' '$1 == "skip"' "$RES" | grep -c . || :)"
if [ "$_nf" != 0 ] || [ -s "$WORK/lost" ]; then KEEP=1; fi
case "$RES" in "$WORK"/*) [ "$KEEP" = 1 ] || _rk=" (removed with the work dir: all green)" ;; esac
# A pass is kept for its key only from a run whose results account for every suite: a damaged results
# file could carry a row no suite wrote. A fail is never kept.
_nc=""
if [ -f "$WORK/keys" ]; then
  _nc=", $(awk -F '\t' '$1 == "cached"' "$RES" | grep -c . || :) cached"
  if [ -s "$WORK/lost" ]; then log_note "cache: nothing recorded — the results are damaged"
  else log_note "cache: $(HARBOR_ROOT="$ROOT" sh "$DIR/suite-cache.sh" record "$WORK/keys" "$RES" 2>&1 | head -1)"; fi
fi
log_note "$_np passed$_nc, $_nf failed, $_ns stood down, wall ${WALL}s at P=$JOBS — results: $RES${_rk:-}"

# The tail of each failed suite's log, after the list, so the cause is on the page.
awk -F '\t' '$1 == "fail" { print $5 }' "$RES" | while IFS= read -r _s; do
  log_head "tail of $_s"
  tail -n "${HARBOR_SUITE_TAIL:-40}" "$WORK/logs/$(printf '%s' "$_s" | tr '/' '_').log" | sed 's/^/    /'
done

[ "$REC" != 1 ] || _record "$RES"
log_end; exit $?
