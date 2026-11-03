#!/usr/bin/env sh
# deploy-launchd-sync.sh (harbor#1437) — deploy brings the box's scheduled jobs up and keeps them on current code.
#
#   sh deploy-launchd-sync.sh snapshot <file>    before the install: each installed job's program/script bytes, to <file>
#   sh deploy-launchd-sync.sh plan <file>        a dry run of `apply`: what would be installed and restarted
#   sh deploy-launchd-sync.sh apply <file>       after the install: install the marked plists that are missing or differ,
#                                                restart every RUNNING job whose bytes changed since the snapshot (and only those)
#   sh deploy-launchd-sync.sh verify             read-only: a job still running a script older than its installed copy is red
#
# WHY. A deploy replaced event-dispatch.sh and never restarted the follower, which ran a week-old copy and then refused
# every reaction (2026-10-25..11-02, check id event.dispatch). A job is "installed" when ~/Library/LaunchAgents holds a
# com.harbor.*.plist; its program is the ProgramArguments entries that are files. A plist in launchd/ carrying
# `harbor:deploy-installs` is installed by this tool when missing or different from its rendering (bin/deploy-launchd-render.sh),
# so a deploy is the one act that turns scheduled machinery on. An interval job is not restarted: its next tick runs the new
# bytes. verify reads the process start time against the file's mtime; a job whose bytes are unchanged since the last
# sync (the ledger below) is current even when a re-copy touched the mtime.
# This runs from the operator's terminal under deploy; a Claude session never runs it (deploy and launchctl are refused).
#
# State: ~/.local/state/harbor/launchd-run.tsv  label <TAB> pid <TAB> start-epoch <TAB> bytes-checksum, written by apply.
# Exit 0 ok, 1 a job is stale or a step failed, 2 usage. macOS only (launchd): elsewhere it is a note and exit 0.
# platform: macOS-only — launchd; with no launchctl on PATH every mode logs a skip.
set -u
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH='' cd -- "$HERE" && pwd)"
. "$HERE/library-log.sh"
. "$HERE/library-fs.sh"
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2; log_init launchd-sync
ID='[check:deploy.launchd]'
LA="$HOME/Library/LaunchAgents"
STATE="$HOME/.local/state/harbor"; LEDGER="$STATE/launchd-run.tsv"
UID_="$(id -u)"
MARK='harbor:deploy-installs'

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
[ $# -ge 1 ] || usage
case "$1" in -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
MODE="$1"; ARG="${2-}"
case "$MODE" in snapshot|plan|apply) [ -n "$ARG" ] || usage ;; verify) ;; *) usage ;; esac

if ! command -v launchctl >/dev/null 2>&1; then log_skip "$ID no launchctl here: launchd jobs are macOS's"; log_end; exit 0; fi

# A sandbox HOME (a suite, a throwaway box) must never reach the real launchd domain: with the system launchctl and a HOME that
# is not this account's own, nothing is read or loaded.
_real="$(CDPATH='' cd -- "$(eval echo "~$(id -un)")" 2>/dev/null && pwd -P)" || _real=""
_me="$(CDPATH='' cd -- "$HOME" 2>/dev/null && pwd -P)" || _me=""
if [ "$(command -v launchctl)" = /bin/launchctl ] && [ "$_real" != "$_me" ]; then
  log_skip "$ID HOME ($HOME) is not this account's home: the real launchd is not touched from a sandbox"; log_end; exit 0
fi

# plist_label <plist> / plist_args <plist>: our plists are written one key per line; this reads exactly that form.
plist_label() { sed -n 's|.*<key>Label</key><string>\([^<]*\)</string>.*|\1|p' "$1" | head -1; }
plist_args() { awk '/<key>ProgramArguments<\/key>/ { f = 1; next } f && /<\/array>/ { exit } f && /<string>/ { s = $0; sub(/.*<string>/, "", s); sub(/<\/string>.*/, "", s); print s }' "$1"; }
# bytes_of <plist>: one checksum over every ProgramArguments entry that is an absolute regular file.
bytes_of() {
  plist_args "$1" | while IFS= read -r _a; do
    case "$_a" in /*) [ -f "$_a" ] && printf '%s ' "$(cksum < "$_a" | awk '{print $1 "." $2}')" ;; esac
  done
}
mtime_of() { fs_mtime "$1"; }
# bootout is asynchronous: bootstrapping a KeepAlive job launchd is still unloading is refused (the 2026-11-03 deploy).
# unloaded <label>: wait up to 10 s for launchd to drop it. A suite stubs launchctl `print` to report it alive for N polls.
unloaded() {
  _w=0
  while launchctl print "gui/$UID_/$1" >/dev/null 2>&1; do
    [ "$_w" -lt 10 ] || return 1
    sleep 1; _w=$((_w + 1))
  done
}
# load_job <label> <plist>: bootstrap; a refused bootstrap is retried once after the same wait.
load_job() {
  launchctl bootstrap "gui/$UID_" "$2" >/dev/null 2>&1 && return 0
  unloaded "$1" || :
  launchctl bootstrap "gui/$UID_" "$2" >/dev/null 2>&1
}
# reload_job <label> <plist>: bootout, wait until it is gone, bootstrap.
reload_job() {
  launchctl bootout "gui/$UID_/$1" >/dev/null 2>&1 || :
  unloaded "$1" || log_note "$ID $1 is still loaded 10 s after bootout"
  load_job "$1" "$2"
}
# is_loaded <label>: launchd has the job (running or not). wants_loaded <plist>: it asks to be started, by KeepAlive or RunAtLoad.
is_loaded() { launchctl print "gui/$UID_/$1" >/dev/null 2>&1; }
wants_loaded() { grep -Eq '<key>KeepAlive</key>|<key>RunAtLoad</key>[[:space:]]*<true/>' "$1"; }
# pid_of <label>: the job's pid, or nothing when it is not running.
pid_of() { launchctl print "gui/$UID_/$1" 2>/dev/null | sed -n 's/^[[:space:]]*pid = \([0-9][0-9]*\)$/\1/p' | head -1; }
# start_of <pid>: the process start as an epoch, from ps elapsed time ([[dd-]hh:]mm:ss).
start_of() {
  _el="$(ps -o etime= -p "$1" 2>/dev/null | tr -d ' ')"; [ -n "$_el" ] || return 1
  printf '%s\n' "$_el" | awk -v now="$(date +%s)" '{ d = 0; t = $0
    if (index(t, "-")) { split(t, a, "-"); d = a[1]; t = a[2] }
    n = split(t, p, ":"); s = 0; for (i = 1; i <= n; i++) s = s * 60 + p[i]
    print now - (d * 86400 + s) }'
}
installed_plists() { for _p in "$LA"/com.harbor.*.plist; do [ -f "$_p" ] && printf '%s\n' "$_p"; done; }

case "$MODE" in
snapshot)
  : > "$ARG" || { log_fail "$ID cannot write $ARG"; log_fix "check the path"; log_end; exit 1; }
  for _p in $(installed_plists); do printf '%s\t%s\n' "$(plist_label "$_p")" "$(bytes_of "$_p")" >> "$ARG"; done
  log_ok "$ID snapshot: $(grep -c . "$ARG") installed job(s) recorded"
  log_end; exit 0 ;;

plan|apply)
  [ -f "$ARG" ] || { log_fail "$ID no snapshot at $ARG: run snapshot before the install"; log_fix "sh $0 snapshot $ARG"; log_end; exit 1; }
  # 1. the marked plists: installed when missing, rewritten and reloaded when they differ from their rendering.
  for _t in "$HERE"/../launchd/*.plist; do
    [ -f "$_t" ] && grep -q "$MARK" "$_t" || continue
    _b="${_t##*/}"; _l="${_b%.plist}"
    _out="${TMPDIR:-/tmp}/launchd-sync.$$.$_b"
    if ! sh "$HERE/deploy-launchd-render.sh" "$_t" > "$_out" 2> "$_out.err"; then
      log_fail "$ID $_b does not render: $(tr '\n' ' ' < "$_out.err")"; log_fix "sh $HERE/deploy-launchd-render.sh --check $_t"; rm -f "$_out" "$_out.err"; continue
    fi
    rm -f "$_out.err"
    if [ -f "$LA/$_b" ] && cmp -s "$_out" "$LA/$_b"; then
      rm -f "$_out"
      # Unchanged bytes are not a loaded job: an earlier bootstrap that was refused left it on disk and down (2026-11-03).
      is_loaded "$_l" && continue
      if [ "$MODE" = plan ]; then log_note "$ID would load $_l: $_b is installed but launchd does not have it"; continue; fi
      if load_job "$_l" "$LA/$_b"; then log_ok "$ID loaded $_b: it was installed and not loaded"
      else log_fail "$ID $_b is installed but launchctl bootstrap refused it"; log_fix "launchctl bootstrap gui/$UID_ $LA/$_b"; fi
      continue
    fi
    if [ "$MODE" = plan ]; then log_note "$ID would install $_b into $LA and (re)load $_l"; rm -f "$_out"; continue; fi
    mkdir -p "$LA" && cp "$_out" "$LA/$_b" && rm -f "$_out" || { log_fail "$ID could not write $LA/$_b"; log_fix "ls -ld $LA"; continue; }
    if reload_job "$_l" "$LA/$_b"; then log_ok "$ID installed and loaded $_b"
    else log_fail "$ID installed $_b but launchctl bootstrap refused it"; log_fix "launchctl bootstrap gui/$UID_ $LA/$_b"; fi
  done
  # 2. a running job whose program or script bytes changed since the snapshot is restarted, and no other.
  for _p in $(installed_plists); do
    _l="$(plist_label "$_p")"; [ -n "$_l" ] || continue
    _was="$(awk -F'\t' -v l="$_l" '$1 == l { print $2; f = 1; exit } END { if (!f) print "-" }' "$ARG")"
    _now="$(bytes_of "$_p")"
    [ "$_was" != "-" ] || continue                  # not installed before this deploy: the install above started it
    [ "$_was" != "$_now" ] || continue              # bytes unchanged: leave it running
    _pid="$(pid_of "$_l")"
    if [ -z "$_pid" ]; then log_note "$ID $_l changed and is not running: its next run uses the new bytes"; continue; fi
    if [ "$MODE" = plan ]; then log_note "$ID would restart $_l (pid $_pid): its program changed"; continue; fi
    if launchctl kickstart -k "gui/$UID_/$_l" >/dev/null 2>&1; then log_ok "$ID restarted $_l: its program changed"
    else log_fail "$ID could not restart $_l"; log_fix "launchctl kickstart -k gui/$UID_/$_l"; fi
  done
  # 3. the ledger verify reads: every running job, the process it has now and the bytes it was started on.
  if [ "$MODE" = apply ]; then
    mkdir -p "$STATE"; : > "$LEDGER.new"
    for _p in $(installed_plists); do
      _l="$(plist_label "$_p")"; _pid="$(pid_of "$_l")"; [ -n "$_pid" ] || continue
      _st="$(start_of "$_pid")" || continue
      printf '%s\t%s\t%s\t%s\n' "$_l" "$_pid" "$_st" "$(bytes_of "$_p")" >> "$LEDGER.new"
    done
    mv -f "$LEDGER.new" "$LEDGER"
  fi
  log_end; exit $? ;;

verify)
  _n=0
  for _p in $(installed_plists); do
    _l="$(plist_label "$_p")"; [ -n "$_l" ] || continue
    if wants_loaded "$_p" && ! is_loaded "$_l"; then
      log_fail "$ID $_l is installed but not loaded: launchd is not running it"
      log_fix "launchctl bootstrap gui/$UID_ $_p   (or: sh bin/deploy.sh --apply --live)"; continue
    fi
    _pid="$(pid_of "$_l")"; [ -n "$_pid" ] || continue
    _st="$(start_of "$_pid")" || { log_skip "$ID $_l: pid $_pid has no readable start time"; continue; }
    _n=$((_n + 1)); _stale=""
    for _a in $(plist_args "$_p"); do
      case "$_a" in /*) ;; *) continue ;; esac
      [ -f "$_a" ] || continue
      _mt="$(mtime_of "$_a")"; [ -n "$_mt" ] || continue
      [ $((_st + 2)) -lt "$_mt" ] || continue   # ps reports whole seconds: a job started in the same second as its file is current
      # newer than the process: stale unless the ledger saw this very process on these very bytes
      _led="$(awk -F'\t' -v l="$_l" -v s="$_st" '$1 == l { d = s - $3; if (d < 0) d = -d; if (d <= 2) print $4 }' "$LEDGER" 2>/dev/null | head -1)"
      [ "$_led" = "$(bytes_of "$_p")" ] || _stale="$_a"
    done
    if [ -n "$_stale" ]; then
      log_fail "$ID $_l (pid $_pid) is running code older than $_stale: it was started before that file was installed"
      log_fix "launchctl kickstart -k gui/$UID_/$_l   (or: sh bin/deploy.sh --apply --live, which restarts changed jobs)"
    else log_ok "$ID $_l (pid $_pid) runs the bytes installed"; fi
  done
  [ "$_n" -gt 0 ] || log_note "$ID no installed com.harbor job is running"
  log_end; exit $? ;;
esac
