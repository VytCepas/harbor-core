#!/usr/bin/env sh
# pulse-notify (harbor#9 — workstream E, E1) — the edge trigger and the sink.
#
#   sh pulse-notify.sh             # evaluate, notify on CHANGES, write state
#   sh pulse-notify.sh --dry-run   # print what it would say; write nothing, send nothing
#
# This is the only thing in workstream E that writes, and the only thing that
# speaks. pulse.sh evaluates and stays silent; keeping the two apart is what
# lets every verdict be tested without a state file or a notification sink.
#
# EDGES, NOT LEVELS. A monitor that announces a standing condition on every tick
# is a monitor the operator mutes, and a muted channel monitors nothing — the
# same economics as a guard with false positives (CONSTITUTION №2.11), which
# FLOOR.md already paid for once when B7 blocked `git grep` over Harbor's own
# docs. So: a verdict is announced when it CHANGES, a persisting CRIT is
# repeated at most once a day, a recovery is announced once, and everything
# else is silent. The tile and `sh pulse.sh` carry the level at all times; the
# lock screen carries only the news.
#
# UNKNOWN NEVER SPEAKS. A source that stopped being readable is a real fact and
# it is on the tile, but it is the one class most likely to be transient — a
# fleet cache mid-write, a MEMORY checkout mid-rebase — and a channel that fires
# on those is a channel that cried wolf first.
#
# THE NOTIFICATION BODY IS THE LEAST PRIVATE SURFACE IN HARBOR. It renders on a
# lock screen, in a screen share, and into the system's own notification store.
# §3's boundary applies with no judgment call available at the moment it fires,
# so the body is built only from pulse.sh's own vocabulary — a check id, a
# verdict, and a detail string this repo wrote — and then scrubbed of anything
# path-shaped anyway. Two independent controls, because the first one is a
# convention and the second one is a mechanism.
#
# THE SINK IS BEST-EFFORT AND SAYS SO. `osascript -e 'display notification'`
# returns 0 whether the banner renders or is suppressed — the attributed bundle
# may never have been granted permission, and Focus silences it with no signal
# to the caller. Delivery therefore cannot be proven from inside this script;
# it closes only on a human saying they saw one.
#
# MEASURED 2026-08-03, BOTH CONTEXTS, and they were measured separately because
# they are separate claims. A banner sent by this file from a SESSION was seen
# by the operator; that settles the sink and the AppleScript path. A banner sent
# by the LAUNCHD job was then seen too — the unit bootstrapped into gui/<uid>,
# the state file cleared so a standing verdict became a fresh edge again, and
# `launchctl kickstart -k` fired it. The log carries the pair that proves the
# edge logic at the same time:
#
#   pulse: worst=warn spoke=0 sink=osascript answered=4/4   <- state already held it
#   pulse: worst=warn spoke=1 sink=osascript answered=4/4   <- same verdict, fresh state
#
# Nothing here rests on that measurement staying true. The durable record is the
# state file and the dashboard tile; the banner is an accelerator, and `sink`
# records which of the three cases each run was in, so "no banner appeared" is
# diagnosable rather than mysterious. A grant can be revoked in System Settings
# without telling anyone, which is why the sink is still best-effort by design.
#
# `--selftest` EXISTS BECAUSE THE VERIFICATION STEP DID NOT WORK. The plist
# header told the operator to kickstart the job and look for a banner — but a
# scheduled run is edge-triggered, so a box whose verdicts have not moved sends
# nothing, and a silent sink and a healthy box are indistinguishable at exactly
# the moment you are trying to tell them apart. `--selftest` sends one banner
# unconditionally, writes no state, and touches no verdict.
#
# THE SCRIPT IS PASSED ON STDIN AND THE TEXT AS ARGV, deliberately. Interpolating
# a message into an `-e` string is the shell-injection shape CONSTITUTION §4
# forbids; `on run argv` means no part of the body is ever parsed as AppleScript.
set -eu

# --help BEFORE ANY WORK (S4, harbor#140). Placed immediately after strict mode
# so it is the first executable line: a --help that reaches an argument parser is
# a --help that a script with no parser ignores, and this file had none. Measured
# 2026-08-20: a sweep of `bin/*.sh --help` ran past five minutes because at least
# one script treated the flag as a request to do work, and five of the scripts
# with no --help at all are mutators. The text is the header, read out of THIS
# file at runtime, so a help message cannot drift from what the script says it is.
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
SRC="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# Its status lines are log-lib's, on stderr (CONTRACTS/logging.md): stdout keeps the one receipt line.
. "$SRC/log-lib.sh"
LOG_FD=2; log_init pulse-notify
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CACHE_DIR="${HARBOR_CACHE_DIR:-$CFG/cache}"
STATE="${HARBOR_PULSE_STATE:-$CACHE_DIR/pulse-state.json}"
# A CRIT that nobody has fixed is still worth one reminder a day. Anything more
# frequent is the standing-condition spam this file exists to avoid.
REMIND="${HARBOR_PULSE_REMIND:-86400}"
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

# The sink is bin/alert-lib.sh's chain (harbor#618): macOS, notify-send, a WSL2 toast, else a logged line.
# Only a desktop channel counts as said: a logged line leaves the edge unrecorded, to be said on a later run.
ALERT_LIB_DIR="$SRC"; . "$SRC/alert-lib.sh"
SINK="$(notify_sink)"

send() { # <subtitle> <body> -> 0 ONLY if a desktop channel took it
  harbor_notify "$1" "$2"
  [ "$NOTIFY_SINK" != log ]
}

if [ "${1:-}" = "--selftest" ]; then
  if [ "$SINK" = log ]; then
    log_fail "no desktop channel on this machine (macOS notifications, notify-send, a WSL2 toast) — banners go to the event log only"
    log_fix "install libnotify's notify-send (Linux), then: sh $0 --selftest"
    log_end || :; exit 1
  fi
  _first="$SINK"
  if ! send "pulse — selftest" "the sink works — this run changed nothing"; then
    log_fail "$_first refused the banner and no later channel took it — it went to the event log only"
    log_nofix "CHECKS.md, row pulse (WSL2 often runs no notification daemon)"
    log_end || :; exit 1
  fi
  log_ok "one banner sent through $SINK — if none appeared, the sink is suppressed, not broken: check the notification permission"
  log_end; exit 0
fi

command -v jq >/dev/null 2>&1 || { log_fail "jq is required"; log_fix "$(pkg_hint jq)"; log_end || :; exit 1; }

PREV_RAN=0
if [ -f "$STATE" ]; then
  PREV_RAN="$(jq -r '.ran_at // 0' "$STATE" 2>/dev/null || printf '0')"
  case "$PREV_RAN" in ''|*[!0-9]*) PREV_RAN=0 ;; esac
fi
# The probe cannot read state — it is the pure evaluator — but it needs one fact
# only the writer has: when this pair last ran. Without it a stale fleet cache
# and a laptop that was closed are the same observation.
NEW="$(HARBOR_PULSE_LAST_RUN="$PREV_RAN" sh "$SRC/pulse.sh" --json 2>/dev/null)" || {
  log_fail "the probe failed — writing no state rather than a healthy one"
  log_fix "sh $SRC/pulse.sh   # the probe by hand, which says why"
  log_end || :; exit 1
}
[ -n "$NEW" ] || { log_fail "the probe returned nothing"; log_fix "sh $SRC/pulse.sh --json"; log_end || :; exit 1; }

PREV='{}'
# `-f` and not `-e`: a FIFO planted at the state path would hang a reader
# forever and there is no `timeout` on macOS (DE-11). A named pipe is not a
# regular file, so this refuses to read it and the run continues on defaults.
if [ -f "$STATE" ]; then PREV="$(cat "$STATE" 2>/dev/null || printf '{}')"; fi
case "$PREV" in "") PREV='{}' ;; esac
printf '%s' "$PREV" | jq -e . >/dev/null 2>&1 || PREV='{}'

RAN_AT="$(printf '%s' "$NEW" | jq -r '.ran_at')"
WORST="$(printf '%s' "$NEW" | jq -r '.worst')"


# REFUSE TO SPEAK IF I CANNOT REMEMBER THAT I SPOKE. Notifications go out first
# and state is written last, so a state write that fails AFTER the banners turns
# an edge-triggered notifier into a level-triggered one: the same verdict is
# announced on every tick, forever, which is the failure mode this whole design
# is built to avoid. Proving the write is possible before any banner leaves is
# cheaper than making the send transactional.
if [ "$DRY" -eq 0 ]; then
  mkdir -p "$CACHE_DIR" 2>/dev/null || true
  if [ -e "$STATE" ] && [ ! -f "$STATE" ]; then
    log_fail "$STATE exists and is not a regular file — refusing to write"
    log_fix "ls -l '$STATE'   # then move it aside"
    log_end || :; exit 1
  fi
  _probe="$STATE.wtest.$$"
  # The redirection is inside a SUBSHELL because a failed redirect is reported
  # by the shell itself, before the command runs, so the command's own 2>/dev/null
  # never suppresses it — the operator would get the shell's raw diagnostic and
  # then this file's explanation of the same thing.
  if ! ( : > "$_probe" ) 2>/dev/null; then
    log_fail "cannot write beside $STATE — saying nothing, because an unrecordable notification repeats forever"
    log_fix "chmod u+w '$CACHE_DIR'"
    log_end || :; exit 1
  fi
  rm -f "$_probe"
fi

# Path-shaped anything becomes [path] before it can reach a lock screen. The
# vocabulary upstream of this has none today; this is the mechanism that keeps
# that true when someone adds a check next month and quotes a filename in it.
scrub() { printf '%s' "$1" | sed -e 's#[~/][^ ]*#[path]#g'; }

say() { # <subtitle> <body> -> 0 ONLY if the sink accepted it
  # THE RETURN VALUE IS LOAD-BEARING. This used to swallow every failure and
  # return 0, so a box with no sink at all recorded the edge as announced and
  # then suppressed it forever: the operator would never hear about a WARN that
  # was "sent" into nothing. A send that did not happen must leave the edge
  # unrecorded, so the next run says it again.
  send "$1" "$2"
}

KEEP="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"
SAID="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"
HELD="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"
trap 'rm -f "$KEEP" "$SAID" "$HELD"' EXIT INT TERM HUP

printf '%s' "$NEW" | jq -r '.checks | to_entries[] | [.key, .value.verdict, .value.detail] | @tsv' \
| while IFS='	' read -r id verdict detail; do
  [ -n "$id" ] || continue
  # THE COMPARISON IS AGAINST WHAT WAS LAST ANNOUNCED, not against the previous
  # verdict. Those differ the moment an `unknown` lands between two real ones,
  # and reading the previous verdict got both directions wrong: warn → unknown →
  # ok announced no recovery at all (the operator's last message stayed an
  # unresolved warning), while warn → unknown → warn announced the same standing
  # condition twice. The last thing SAID is the only thing the operator's
  # attention is actually holding, so it is the thing to diff against.
  nv="$(printf '%s' "$PREV"  | jq -r --arg k "$id" '.notified[$k].verdict // ""')"
  nat="$(printf '%s' "$PREV" | jq -r --arg k "$id" '.notified[$k].at // 0')"

  fire=""
  case "$verdict" in
    crit|warn)
      if [ "$verdict" != "$nv" ]; then
        fire="$(printf '%s' "$verdict" | tr '[:lower:]' '[:upper:]')"
      elif [ "$verdict" = crit ] && [ "$((RAN_AT - nat))" -ge "$REMIND" ]; then
        fire="STILL CRIT"
      fi ;;
    ok)
      case "$nv" in warn|crit) fire="RECOVERED" ;; esac ;;
  esac

  # _rv/_rat is what the notified map should hold for this check after this run.
  # Default: whatever it held before — an unannounced run must not disturb it.
  _rv="$nv"; _rat="$nat"
  if [ -n "$fire" ]; then
    body="$fire — $(scrub "$detail")"
    _ok=1
    if [ "$DRY" -eq 1 ]; then
      printf 'would notify: [%s] %s\n' "$id" "$body"
      _ok=0
    elif say "pulse — $id" "$body"; then
      _ok=0
    else
      printf '%s\n' "$id" >> "$HELD"
    fi
    if [ "$_ok" -eq 0 ]; then
      printf '%s\n' "$id" >> "$SAID"
      if [ "$fire" = RECOVERED ]; then
        # Clear it. The condition is over, and the next occurrence must be news.
        _rv=""; _rat=0
      else
        _rv="$verdict"; _rat="$RAN_AT"
      fi
    fi
    # _ok=1 means the sink refused it: leave the map untouched so the next run
    # tries the same edge again rather than pretending it was delivered.
  fi
  # AN `if`, NOT `[ … ] && printf`. The AND-list form makes the loop body's exit
  # status 1 whenever the test is false, which makes the whole `while` exit 1 —
  # and the loop is the tail of a pipeline, so `set -e` kills the script right
  # here, BEFORE the state write below. Measured: a recovery notification was
  # sent, the script died silently on the way out, the stale state survived, and
  # the next run announced the same recovery again. A run that did half its job
  # and exited 0 is the exact shape DE-14 is about.
  if [ -n "$_rv" ]; then
    printf '%s\t%s\t%s\n' "$id" "$_rv" "$_rat" >> "$KEEP"
  fi
done

# TWO FILES, BECAUSE ONE COUNTED THE WRONG THING. The loop runs in a subshell
# (right-hand side of a pipe), so a counter variable cannot survive it — but the
# first version counted $KEEP, which also carries FORWARD the entries that were
# not announced. A silent second run therefore reported `notifications: 1`, a
# field claiming this run spoke when it had not. $SAID holds only what was
# actually said.
SPOKEN="$(wc -l < "$SAID" 2>/dev/null | tr -d ' ')"
[ -n "$SPOKEN" ] || SPOKEN=0
# A notifier that cannot speak is a no-op by decision, not a failure (harbor#618): WSL2 and servers often have no
# sink or no daemon behind notify-send. One note per run; every held edge stays unrecorded, so the first run
# that has a working sink announces it. The tile and `sh pulse.sh` carry the level meanwhile.
_HELD="$(wc -l < "$HELD" 2>/dev/null | tr -d ' ')"
if [ "${_HELD:-0}" -gt 0 ] && [ "$DRY" -eq 0 ]; then
  log_note "$_HELD banner(s) held: sink=$SINK did not take them (no notification daemon?) — each edge is said again on a run that has one"
fi

if [ "$DRY" -eq 1 ]; then
  printf 'worst=%s  sink=%s  state=%s (unwritten: --dry-run)\n' "$WORST" "$SINK" "$STATE"
  exit 0
fi

# The directory was created and proven writable above, before anything was said.
# The precedent for creating it at all is fleet-snapshot-refresh.sh, which does
# the same: DE-11 and DE-13 forbid this in the GUARD hot path, where a hang is a
# total bypass of every rule, not in a scheduled writer whose worst failure is a
# missing tile.
TMP="$STATE.tmp.$$"
trap 'rm -f "$KEEP" "$SAID" "$TMP"' EXIT INT TERM HUP
# Temp-then-rename, never append: a rename cannot be intercepted by whatever is
# at the destination, and a half-written state file is the one thing that would
# make the next run's edge detection wrong in both directions.
printf '%s' "$NEW" | jq --arg sink "$SINK" --argjson spoke "${SPOKEN:-0}" \
  --rawfile keep "$KEEP" '
  . + { sink: $sink, notifications: $spoke,
        notified: ($keep | split("\n") | map(select(length > 0) | split("\t"))
                   | map({ key: .[0], value: { verdict: .[1], at: (.[2] | tonumber) } })
                   | from_entries) }' > "$TMP"
[ -s "$TMP" ] || { log_fail "refusing to write an empty state file"; log_nofix "harbor#9"; log_end || :; exit 1; }
mv "$TMP" "$STATE"
# ONE LINE PER RUN, ON STDOUT. The plist declares StandardOutPath so that a run
# that happened is distinguishable from one that did not — and the first version
# of this file printed nothing on success, which made that log exactly as
# uninformative as the always-empty stderr of the fleet job this design
# criticised for exactly that. A healthy silent run and a job that has not fired
# since July must not produce the same artefact.
printf 'pulse: worst=%s spoke=%s sink=%s answered=%s/%s\n' \
  "$WORST" "$SPOKEN" "$SINK" \
  "$(printf '%s' "$NEW" | jq -r '.inputs_seen // 0')" \
  "$(printf '%s' "$NEW" | jq -r '.checks_run // 0')"
log_end || :
exit 0
