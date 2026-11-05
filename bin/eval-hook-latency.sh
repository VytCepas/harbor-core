#!/usr/bin/env sh
# eval-hook-latency (harbor#1290) — what the snapshot step adds to a discarding git command in
# bin/admission-destroy.sh, measured the way the harness runs the hook: /bin/sh <guard> with the
# PreToolUse JSON on stdin. A PreToolUse hook past its timeout is skipped, so latency is a fail-open path.
#
#   sh bin/eval-hook-latency.sh run  [--runs N] [--tree DIR] [--budget-ms MS]   measure; exit 1 over budget
#   sh bin/eval-hook-latency.sh stats [--budget-ms MS] < "<arm> <ms>" lines     summarise saved samples
#
# `run` clones this checkout (or takes --tree), dirties it, then alternates two arms on the same tree: ON,
# and OFF, which is the shipped switch <git dir>/harbor-snapshot-off. Added latency = p50(ON) - p50(OFF).
# Snapshot refs are cleared between runs, so each run is a first discard. Exit 2: could not measure.
set -u
DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
GUARD="$DIR/admission-destroy.sh"
. "$DIR/library-log.sh"
log_init eval-hook-latency

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; }
die() { # <message> [fix]
  log_fail "$1"; log_fix "${2:-sh bin/eval-hook-latency.sh --help}"; log_end >/dev/null; exit 2
}

# stats: stdin "<arm> <ms>" -> a note per arm, then the added-latency verdict; returns 1 over budget.
stats() { # <budget-ms>
  _sd="$(mktemp -d "${TMPDIR:-/tmp}/eval-hook-latency.XXXXXX")" || die "no temp dir"
  sort -k1,1 -k2,2n | awk -v budget="$1" '
    function pick(arr, n, q,   i) { i = int(q * (n - 1) + 0.5) + 1; return arr[i] }
    { n[$1]++; v[$1, n[$1]] = $2 }
    END {
      for (a in n) {
        for (i = 1; i <= n[a]; i++) s[i] = v[a, i]
        p50[a] = pick(s, n[a], 0.5); p95[a] = pick(s, n[a], 0.95)
        printf "ARM\t%-4s n=%d  min=%.1f  p50=%.1f  p95=%.1f  max=%.1f ms\n", a, n[a], s[1], p50[a], p95[a], s[n[a]]
      }
      if (!("on" in n) || !("off" in n)) { print "NOARM"; exit }
      d = p50["on"] - p50["off"]
      printf "VERDICT\tadded p50 = %.1f ms (on - off), budget < %s ms: %s\n", d, budget, (d < budget + 0) ? "WITHIN" : "OVER"
    }' > "$_sd/out"
  grep -q '^NOARM' "$_sd/out" && { rm -rf "$_sd"; die "stats needs both an on and an off arm"; }
  log_head "stats"
  while IFS="$(printf '\t')" read -r _k _m; do
    case "$_k" in
      ARM) log_note "$_m" ;;
      VERDICT) case "$_m" in
        *WITHIN) log_ok "$_m" ;;
        *) log_fail "$_m"
           log_fix "see harbor#1290: the snapshot's cost is process spawns plus add -A; shave them in admission-destroy.sh (a human-gated change), or re-run on a quiet box" ;;
      esac ;;
    esac
  done < "$_sd/out"
  rm -rf "$_sd"
  log_end
}

run() { # <runs> <tree|-> <budget-ms>
  command -v perl >/dev/null 2>&1 || die "perl is the clock (Time::HiRes); none on PATH" "install perl"
  command -v jq >/dev/null 2>&1 || die "jq is needed to build the hook payload" "$(pkg_hint jq)"
  _w="$(mktemp -d "${TMPDIR:-/tmp}/eval-hook-latency.XXXXXX")" || die "no temp dir"
  trap 'chmod -R u+w "$_w" 2>/dev/null; rm -rf "$_w"' EXIT
  trap 'exit 130' INT TERM HUP
  # The hook writes its decision log under HOME/CLAUDE_CONFIG_DIR: keep the real ones out of the benchmark.
  mkdir -p "$_w/home" "$_w/cfg"
  if [ "$2" = - ]; then
    git clone -q --local "$DIR/.." "$_w/tree" 2>/dev/null || die "could not clone $DIR/.."
    T="$_w/tree"
  else
    T="$2"
  fi
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  _gd="$(git -C "$T" rev-parse --absolute-git-dir 2>/dev/null)" || die "$T is not a git worktree" "pass --tree <a git worktree>"
  _tracked="$(git -C "$T" ls-files | head -n 1)"
  [ -n "$_tracked" ] || die "$T has no tracked file to discard" "pass --tree <a git worktree with files>"
  # The tree a discard would find: tracked edits, a staged edit and untracked files.
  if [ "$2" = - ]; then
    git -C "$T" ls-files | head -n 3 | while IFS= read -r _f; do printf '\nbench edit\n' >> "$T/$_f"; done
    git -C "$T" add -- "$(git -C "$T" ls-files | sed -n 2p)"
    printf 'bench untracked\n' > "$T/bench-untracked-1.txt"; printf 'bench untracked\n' > "$T/bench-untracked-2.txt"
  fi
  _files="$(git -C "$T" ls-files | wc -l | tr -d ' ')"
  jq -n --arg c "git checkout -- $_tracked" --arg d "$T" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' > "$_w/payload"
  _off="$_gd/harbor-snapshot-off"; rm -f "$_off"

  # one timed hook run -> milliseconds on stdout. The clock starts after perl is up and stops at waitpid.
  _time1() {
    HOME="$_w/home" CLAUDE_CONFIG_DIR="$_w/cfg" perl -MTime::HiRes=time -e '
      my ($g, $in) = @ARGV; my $t0 = time; my $pid = fork();
      if (!$pid) { open(STDIN, "<", $in) or exit 126; open(STDOUT, ">", "/dev/null"); open(STDERR, ">", "/dev/null"); exec("/bin/sh", $g); exit 127 }
      waitpid($pid, 0); printf "%.1f\n", (time - $t0) * 1000' "$GUARD" "$_w/payload"
  }
  _snaps() { git -C "$T" for-each-ref refs/snapshots/ | wc -l | tr -d ' '; }
  _clear() { git -C "$T" for-each-ref --format='delete %(refname)' refs/snapshots/ | git -C "$T" update-ref --stdin; }

  # A benchmark of a step that did not run measures nothing: each arm must do what its name says.
  _clear; _time1 >/dev/null
  [ "$(_snaps)" = 1 ] || die "the ON arm took $(_snaps) snapshots, expected 1: the tree is clean or the hook did not reach the snapshot" \
    "pass --tree <a worktree with uncommitted changes>"
  _clear; : > "$_off"; _time1 >/dev/null
  [ "$(_snaps)" = 0 ] || die "the OFF arm still took a snapshot: the harbor-snapshot-off switch no longer works" \
    "check _snap_take in bin/admission-destroy.sh (harbor#1290)"
  rm -f "$_off"; _clear

  log_head "run"
  log_note "tree: $_files files, $(git -C "$T" status --porcelain | wc -l | tr -d ' ') uncommitted; load: $(uptime | sed 's/.*load averages*: //')"
  _i=0
  : > "$_w/samples"
  while [ "$_i" -lt "$1" ]; do
    _clear; printf 'on %s\n' "$(_time1)" >> "$_w/samples"
    _clear; : > "$_off"; printf 'off %s\n' "$(_time1)" >> "$_w/samples"; rm -f "$_off"
    _i=$((_i + 1))
  done
  _clear
  stats "$3" < "$_w/samples"
}

cmd="${1:-}"; [ "$#" -gt 0 ] && shift
RUNS=100; TREE=-; BUDGET=50
while [ "$#" -gt 0 ]; do
  case "$1" in
    --runs) RUNS="${2:-}"; shift 2 ;;
    --tree) TREE="${2:-}"; shift 2 ;;
    --budget-ms) BUDGET="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done
case "$cmd" in -h|--help) usage; exit 0 ;; esac
case "$RUNS" in ''|*[!0-9]*|0) die "--runs wants a positive integer" ;; esac
case "$BUDGET" in ''|*[!0-9]*) die "--budget-ms wants an integer" ;; esac
[ -n "$TREE" ] || die "--tree wants a directory"
case "$cmd" in
  run) [ -f "$GUARD" ] || die "no $GUARD"; run "$RUNS" "$TREE" "$BUDGET" ;;
  stats) stats "$BUDGET" ;;
  *) usage; exit 2 ;;
esac
