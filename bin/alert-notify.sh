#!/usr/bin/env sh
# pulse-notify (harbor#9 — workstream E, E1) — the edge trigger and the sink.
#
#   sh alert-notify.sh             # evaluate, notify on CHANGES, write state
#   sh alert-notify.sh --dry-run   # print what it would say; write nothing, send nothing
# The only writer and speaker in workstream E; alert-probe.sh evaluates silently, so verdicts test without a state file or sink.
# EDGES, NOT LEVELS: a monitor that announces a standing condition every tick gets muted (CONSTITUTION §2.11). A verdict is
# announced when it CHANGES, a persisting CRIT at most once a day, a recovery once; the tile and `sh alert-probe.sh` carry the level.
# UNKNOWN NEVER SPEAKS: it is on the tile, but it is the class most likely to be transient.
# The body is the least private surface (lock screen, screen share): built only from alert-probe.sh's vocabulary (check id,
# verdict, repo-written detail) AND scrubbed of path-shaped text, a convention plus a mechanism (§3).
# The sink (bin/library-alert.sh) is best-effort: the macOS notification call returns 0 even when the banner is suppressed (Focus,
# revoked permission), so delivery cannot be proven from inside. The durable record is the state file and tile; `sink=` in the
# run line says which case each run was in.
# `--selftest` sends one banner unconditionally and writes no state: a scheduled run is edge-triggered, so a silent sink
# and a healthy box would otherwise look alike.
# Removed notes: docs/explanation/code-cases/bin-alert-notify.md
set -eu

# --help before any work (S4, harbor#140): a script with no parser would treat --help as a request to do work. The text
# is the header read at runtime, so it cannot drift.
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
SRC="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# Its status lines are log-lib's, on stderr (contracts/logging.md): stdout keeps the one receipt line.
. "$SRC/library-log.sh"
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2; log_init pulse-notify
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CACHE_DIR="${HARBOR_SCOPE_CACHE_DIR:-$CFG/cache}"
STATE="${HARBOR_ALERT_PROBE_STATE:-$CACHE_DIR/pulse-state.json}"
REMIND="${HARBOR_ALERT_PROBE_REMIND:-86400}"
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

# The sink is bin/library-alert.sh's chain (harbor#618): macOS, notify-send, a WSL2 toast, else a logged line.
# Only a desktop channel counts as said: a logged line leaves the edge unrecorded, to be said on a later run.
# shellcheck disable=SC2034 # ALERT_LIB_DIR: read by library-alert.sh
ALERT_LIB_DIR="$SRC"; . "$SRC/library-alert.sh"
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
    log_nofix "docs/reference/checks.md, row pulse (WSL2 often runs no notification daemon)"
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
# The probe is the pure evaluator and cannot read state; it needs the one fact only the writer has: when this pair last ran.
NEW="$(HARBOR_ALERT_PROBE_LAST_RUN="$PREV_RAN" sh "$SRC/alert-probe.sh" --json 2>/dev/null)" || {
  log_fail "the probe failed — writing no state rather than a healthy one"
  log_fix "sh $SRC/alert-probe.sh   # the probe by hand, which says why"
  log_end || :; exit 1
}
[ -n "$NEW" ] || { log_fail "the probe returned nothing"; log_fix "sh $SRC/alert-probe.sh --json"; log_end || :; exit 1; }

PREV='{}'
# `-f`, not `-e`: a FIFO at the state path would hang a reader forever and macOS has no `timeout` (DE-11).
if [ -f "$STATE" ]; then PREV="$(cat "$STATE" 2>/dev/null || printf '{}')"; fi
case "$PREV" in "") PREV='{}' ;; esac
printf '%s' "$PREV" | jq -e . >/dev/null 2>&1 || PREV='{}'

RAN_AT="$(printf '%s' "$NEW" | jq -r '.ran_at')"
WORST="$(printf '%s' "$NEW" | jq -r '.worst')"


# Refuse to speak if I cannot remember that I spoke: a state write failing after the banners turns an edge-trigger
# into a level-trigger. Prove the write is possible before any banner leaves.
if [ "$DRY" -eq 0 ]; then
  mkdir -p "$CACHE_DIR" 2>/dev/null || true
  if [ -e "$STATE" ] && [ ! -f "$STATE" ]; then
    log_fail "$STATE exists and is not a regular file — refusing to write"
    log_fix "ls -l '$STATE'   # then move it aside"
    log_end || :; exit 1
  fi
  _probe="$STATE.wtest.$$"
  if ! ( : > "$_probe" ) 2>/dev/null; then
    log_fail "cannot write beside $STATE — saying nothing, because an unrecordable notification repeats forever"
    log_fix "chmod u+w '$CACHE_DIR'"
    log_end || :; exit 1
  fi
  rm -f "$_probe"
fi

# Path-shaped anything becomes [path] before it can reach a lock screen, whatever a future check quotes.
scrub() { printf '%s' "$1" | sed -e 's#[~/][^ ]*#[path]#g'; }

say() { # <subtitle> <body> -> 0 ONLY if the sink accepted it
  # The return value is load-bearing: a send that did not happen must leave the edge unrecorded, so the next run says it again.
  send "$1" "$2"
}

KEEP="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"
SAID="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"
HELD="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"
trap 'rm -f "$KEEP" "$SAID" "$HELD"' EXIT INT TERM HUP

printf '%s' "$NEW" | jq -r '.checks | to_entries[] | [.key, .value.verdict, .value.detail] | @tsv' \
| while IFS='	' read -r id verdict detail; do
  [ -n "$id" ] || continue
  # Compare against what was last ANNOUNCED, not the previous verdict: warn -> unknown -> ok would announce no recovery,
  # and warn -> unknown -> warn would announce the same condition twice.
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
        _rv=""; _rat=0
      else
        _rv="$verdict"; _rat="$RAN_AT"
      fi
    fi
  fi
  # An `if`, not `[ ... ] && printf`: the AND-list leaves this loop (the tail of a pipeline) exiting 1 and `set -e` kills
  # the script before the state write, so a recovery would be announced again next run (DE-14).
  if [ -n "$_rv" ]; then
    printf '%s\t%s\t%s\n' "$id" "$_rv" "$_rat" >> "$KEEP"
  fi
done

# Two files: the loop runs in a pipe's subshell, and $KEEP also carries unannounced entries forward, so counting it
# made a silent run report notifications: 1. $SAID holds only what was actually said.
SPOKEN="$(wc -l < "$SAID" 2>/dev/null | tr -d ' ')"
[ -n "$SPOKEN" ] || SPOKEN=0
# A notifier that cannot speak is a no-op by decision (harbor#618): every held edge stays unrecorded and is said by the
# first run that has a working sink.
_HELD="$(wc -l < "$HELD" 2>/dev/null | tr -d ' ')"
if [ "${_HELD:-0}" -gt 0 ] && [ "$DRY" -eq 0 ]; then
  log_note "$_HELD banner(s) held: sink=$SINK did not take them (no notification daemon?) — each edge is said again on a run that has one"
fi

if [ "$DRY" -eq 1 ]; then
  printf 'worst=%s  sink=%s  state=%s (unwritten: --dry-run)\n' "$WORST" "$SINK" "$STATE"
  exit 0
fi

# The directory was proven writable above. Creating it is fine here; DE-11 and DE-13 forbid it only in the GUARD hot path.
TMP="$STATE.tmp.$$"
trap 'rm -f "$KEEP" "$SAID" "$TMP"' EXIT INT TERM HUP
# Temp-then-rename: a half-written state file would make the next run's edge detection wrong both ways.
printf '%s' "$NEW" | jq --arg sink "$SINK" --argjson spoke "${SPOKEN:-0}" \
  --rawfile keep "$KEEP" '
  . + { sink: $sink, notifications: $spoke,
        notified: ($keep | split("\n") | map(select(length > 0) | split("\t"))
                   | map({ key: .[0], value: { verdict: .[1], at: (.[2] | tonumber) } })
                   | from_entries) }' > "$TMP"
[ -s "$TMP" ] || { log_fail "refusing to write an empty state file"; log_nofix "harbor#9"; log_end || :; exit 1; }
mv "$TMP" "$STATE"
# THE FINDING PATH (harbor#1437, contracts/finding.md). A dead or refusing event dispatcher used to leave a WARN in /tmp and a
# banner that scrolled away. The dispatch row also becomes the receipt of check event.dispatch, which `lint-findings.sh
# reconcile` files as finding check/event.dispatch and closes when the row is ok again. unknown (could not look) files nothing.
_dv="$(printf '%s' "$NEW" | jq -r '.checks.dispatch.verdict // empty')"
_dd="$(printf '%s' "$NEW" | jq -r '.checks.dispatch.detail // empty')"
case "$_dv" in
  warn|crit) log_receipt "$(receipt_dir)" event.dispatch red "$(scrub "$_dd")" || log_warn "[check:event.dispatch] could not write the finding receipt" ;;
  ok) log_receipt "$(receipt_dir)" event.dispatch green || log_warn "[check:event.dispatch] could not write the finding receipt" ;;
esac
# ONE LINE PER RUN, ON STDOUT. The plist declares StandardOutPath so that a run
# One line per run on STDOUT, so the plist's StandardOutPath log shows a run that happened versus a job that has not fired.
printf 'pulse: worst=%s spoke=%s sink=%s answered=%s/%s\n' \
  "$WORST" "$SPOKEN" "$SINK" \
  "$(printf '%s' "$NEW" | jq -r '.inputs_seen // 0')" \
  "$(printf '%s' "$NEW" | jq -r '.checks_run // 0')"
log_end || :
exit 0
