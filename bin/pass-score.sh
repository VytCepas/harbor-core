#!/usr/bin/env sh
# pass-score.sh — MAD confidence gating over FLOOR.md's adversarial pass table.
# harbor#3 (workstream B), method taken from upstream `Loop` @ a4e8e74 (PROVENANCE.md).
#
# Why this exists. The stated criterion for installing the floor live is "a pass
# must find fewer defects than it introduces", and it has been called failed
# three times by eye. By eye is not good enough: with four data points, a metric
# that moves 17 -> 9 looks like progress and may be indistinguishable from the
# scatter of the series itself. Upstream's Loop skill gates exactly this — it
# computes |delta| / MAD(series) per iteration and refuses to bank a delta below
# the noise floor, logging it `marginal` instead. Same problem, same gate.
#
# MAD (median absolute deviation) rather than stddev: n=4, and one pass-10-shaped
# outlier would swallow a stddev whole.
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
ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
# The report is the run's log (CONTRACTS/logging.md, harbor#771). Its exit code is its verdict (0 / 2 do not
# install / 3 the gate did not run), which floor-install.sh reads, so a verdict FAIL ends the run with that code.
. "$ROOT/bin/log-lib.sh"
log_init pass-score
# die <what failed> <fix> <exit> — FAIL, its fix, the summary, the exit code the tool always had.
die() { log_fail "$1"; log_fix "$2"; log_end || :; exit "$3"; }
FLOOR="$ROOT/FLOOR.md"
NOISE_FLOOR=1.0   # |delta|/MAD below this is not evidence. Upstream's threshold.

[ -f "$FLOOR" ] || die "no $FLOOR" "git checkout -- FLOOR.md" 1

# ── Extract the pass table ────────────────────────────────────────────────
# The header row names the passes; each metric row carries one integer per pass.
# Numbers are read with a leading ~ tolerated ("~24" — pass 10 was an estimate,
# and recording it as exact would be a worse lie than recording it as fuzzy).
# FLOOR.md carries one table per pass-review, each a superset of the last, so
# the LAST match is the current one. `grep -m1` here read the pass-11 table and
# silently reported a three-point series as if it were the whole record.
row() { # <label> -> space-separated integers
  grep "^| $1 |" "$FLOOR" 2>/dev/null | tail -1 \
    | sed 's/^|[^|]*|//; s/|$//; s/|/ /g' \
    | tr -d '*~' \
    | tr -s ' '
}

passes="$(grep '^| | pass' "$FLOOR" | tail -1 | sed 's/^| |//; s/|$//; s/|/ /g' | tr -d '*' | tr -s ' ' \
          | sed 's/pass //g')"
[ -n "$passes" ] || die "no pass table in $FLOOR" "grep -n '^| | pass' $FLOOR" 1

# ── Statistics, in awk (no bc dependency — the floor's rule is POSIX-only) ──
stats() { # stdin: one integer per line
  awk '
    { v[n++] = $1 + 0 }
    function med(a, c,   i, j, t, b) {
      for (i = 0; i < c; i++) b[i] = a[i]
      for (i = 0; i < c; i++) for (j = i+1; j < c; j++)
        if (b[j] < b[i]) { t = b[i]; b[i] = b[j]; b[j] = t }
      return (c % 2) ? b[int(c/2)] : (b[c/2 - 1] + b[c/2]) / 2
    }
    END {
      if (n < 3) { print "n/a"; exit }
      m = med(v, n)
      for (i = 0; i < n; i++) { d = v[i] - m; dev[i] = (d < 0) ? -d : d }
      mad = med(dev, n)
      delta = v[n-1] - v[n-2]
      ad = (delta < 0) ? -delta : delta
      # MAD == 0 means the series has not moved off its median often enough to
      # have a scale. Any movement is then unmeasurable, not automatically real.
      if (mad == 0) { printf "%d %.1f %.1f %s inf\n", delta, m, mad, "—"; exit }
      printf "%d %.1f %.1f %.2f %.2f\n", delta, m, mad, ad/mad, ad/mad
    }'
}

log_head "adversarial passes: $passes"
log_note "noise floor: |delta| must exceed ${NOISE_FLOOR}× MAD to count as evidence"
log_note "$(printf '%-38s %9s %8s %7s %8s  %s' METRIC SERIES DELTA MAD 'x MAD' VERDICT)"

verdict_lines=''
for metric in confirmed refuted "caused by the previous round's fixes" criticals; do
  series="$(row "$metric")"
  [ -n "$series" ] || continue
  s="$(printf '%s' "$series" | tr ' ' '\n' | grep -E '^[0-9]+$' | stats)"
  case "$s" in n/a) continue ;; esac

  delta="$(printf '%s' "$s" | cut -d' ' -f1)"
  mad="$(printf '%s' "$s" | cut -d' ' -f3)"
  ratio="$(printf '%s' "$s" | cut -d' ' -f4)"

  if [ "$ratio" = "—" ]; then
    v="UNMEASURABLE (MAD=0)"
  else
    # POSIX sh has no float compare; awk decides.
    if awk "BEGIN{exit !($ratio >= $NOISE_FLOOR)}"; then v="SIGNAL"; else v="NOISE — do not bank"; fi
  fi

  log_note "$(printf '%-38s %9s %8s %7s %8s  %s' \
    "$(printf '%s' "$metric" | cut -c1-38)" \
    "$(printf '%s' "$series" | sed 's/^ *//; s/ *$//; s/ /,/g')" \
    "$delta" "$mad" "$ratio" "$v")"
  verdict_lines="$verdict_lines$metric=$v
"
done

# ── OBSERVE/REPLAY evidence (M2, harbor#44) ─────────────────────────────────
# harbor#44's Done-when says "pass-score.sh reads real block counts instead of
# pass-report estimates". Taken literally that is a CATEGORY ERROR and
# implementing it literally would make this script lie: the table above counts
# DEFECTS FOUND PER ADVERSARIAL PASS, while the replay counts RULE HITS ON REAL
# TRAFFIC. Substituting one for the other would silently change what the MAD
# gate is gating. So the replay is reported ALONGSIDE, with the relationship
# stated, and the pass series is left alone.
#
# What the replay genuinely adds is the denominator the table never had:
# CONSTITUTION rule 2 says "a false positive is a defect, not safety", and until
# harbor#44 there was no data source that could ever falsify it.
_rp="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.helm-replay/baseline.tsv"
if [ -f "$_rp" ]; then
  _tot="$(wc -l < "$_rp" | tr -d ' ')"
  _blk="$(grep -c '	BLOCK	' "$_rp" 2>/dev/null | head -1 | tr -d ' \n')"
  case "$_blk" in ''|*[!0-9]*) _blk=0 ;; esac
  log_head "real-traffic evidence (M2)"
  log_note "$_blk of $_tot replayed real commands are blocked ($(awk -v b="$_blk" -v t="$_tot" 'BEGIN{printf "%.1f", (t>0?100*b/t:0)}')%)."
  log_note "This is a DIFFERENT quantity from the table above — rule hits on traffic, not defects found per pass. It does not enter the MAD gate."
  log_note "Adjudicate it with: sh bin/replay.sh --labels"
else
  log_head "real-traffic evidence (M2)"
  log_skip "No replay baseline yet. The install criterion above is still being read from adversarial-pass ESTIMATES against synthetic assertions."
  log_note "Build the evidence with: sh bin/replay.sh --baseline"
fi

# THE GATE WAS ONE-SIDED (#47 finding 20). It fired only when `criticals` was
# BOTH above the noise floor AND rising on the last step — so the worst possible
# series, a run of clean passes followed by a jump, exited 0: with a low MAD the
# ratio is huge, but a single quiet pass before the jump made `last > prev` the
# only test that mattered, and any series ending flat sailed through. Two extra
# tests, both cheap:
#   • the LEVEL, not just the delta — criticals above zero at the end is not a
#     clean floor however the series got there;
#   • the TREND across the whole series, so one quiet pass cannot launder a rise.
# `|| true` because `grep` is LAST in this pipeline, so the assignment inherits
# its status — and under `set -eu` a FLOOR.md whose newest criticals row carries
# no numeric cell killed the script right here: the table printed, then nothing,
# rc=1, no verdict, no message.
#
# TWO CORRECTIONS TO WHAT THIS COMMENT USED TO CLAIM (pass-3 review), both of
# which were wrong in the direction that flatters the fix:
#   • "or one whose cells are `n/a`, which stats() itself emits" — stats() writes
#     n/a to its OWN stdout at line 52; it never writes FLOOR.md, and nothing in
#     this repo does. A table with fewer than 3 passes leaves crit_all populated
#     and the gate firing. That path does not exist.
#   • "the guards below were unreachable on exactly the path they were written
#     for" — they are reachable now and still cannot fire, because every one is
#     gated on `[ -n "${crit_last:-}" ]`, which is empty precisely when this path
#     is taken. Completing the run is not the same as running the gate.
# So the honest state is the third branch below: an empty series is UNMEASURED,
# and a gate that did not run must not print a verdict that reads like it did.
crit_all="$(row criticals | tr ' ' '\n' | grep -E '^[0-9]+$' || true)"
if [ -z "${crit_all:-}" ]; then
  # This is not "no worsening".
  die "VERDICT: no readable criticals series in $FLOOR — THE GATE DID NOT RUN" "grep -n '^| criticals |' $FLOOR # fix the criticals row, then sh $0" 3
fi
crit_last="$(printf '%s\n' "$crit_all" | tail -1)"
crit_first="$(printf '%s\n' "$crit_all" | head -1)"
crit_max="$(printf '%s\n' "$crit_all" | sort -n | tail -1)"
# Decision 23 on harbor#1149 (amends 19): a pass whose findings are all adjudicated records `| open criticals |`, its
# criticals neither fixed and pinned nor accepted as a published residual; a lens that never reported is published as
# untested instead of blocking. When the LATEST pass has that cell, it is the gate; `-` marks a pass without one.
open_row="$(row 'open criticals')"
if [ -n "$open_row" ]; then
  [ "$(printf '%s\n' $open_row | wc -l | tr -d ' ')" = "$(printf '%s\n' $passes | wc -l | tr -d ' ')" ] ||
    die "VERDICT: the open criticals row has not one cell per pass — THE GATE DID NOT RUN" "grep -n '^| open criticals |' $FLOOR # one cell per pass, - where a pass has none" 3
  open_last="$(printf '%s\n' $open_row | tail -1)"
  case "$open_last" in
    ''|*[!0-9]*) ;;
    0) log_note "the latest adjudicated pass found ${crit_last:-?} critical(s), and every one is fixed and pinned or an accepted residual"
       log_ok "VERDICT: no critical is open after the latest adjudicated pass (decision 23). Read its published limitations, then decide."
       log_end; exit $? ;;
    *) log_fail "VERDICT: the latest adjudicated pass leaves $open_last critical(s) open. Do not install."
       log_nofix "FLOOR.md — fix and pin each one, or accept it in writing as a published residual (decision 23, harbor#1149)"
       log_end || :; exit 2 ;;
  esac
fi
if [ -n "${crit_last:-}" ] && [ "$crit_last" -gt 0 ]; then
  # A criterion of "fewer defects than it introduces" is not met by a series that ENDS above zero, whichever
  # direction it moved.
  [ "${crit_last:-0}" -lt "${crit_max:-0}" ] || log_note "the latest criticals value is the worst in the series, not a recovery from it"
  log_fail "VERDICT: the latest pass still reports $crit_last critical(s). Do not install."
  log_nofix "FLOOR.md — an adjudicated pass that leaves zero criticals open, its row \`| open criticals |\` (decision 23, harbor#1149)"
  log_end || :; exit 2
fi
if [ -n "${crit_first:-}" ] && [ -n "${crit_last:-}" ] && [ "$crit_last" -gt "$crit_first" ]; then
  log_fail "VERDICT: criticals are higher than when the series began ($crit_first -> $crit_last). Do not install."
  log_nofix "FLOOR.md — the next adversarial pass must bring the criticals series down"
  log_end || :; exit 2
fi

printf '%s' "$verdict_lines" | grep -q 'criticals=SIGNAL' && {
  crit="$(row criticals)"
  last="$(printf '%s' "$crit" | tr ' ' '\n' | grep -E '^[0-9]+$' | tail -1)"
  prev="$(printf '%s' "$crit" | tr ' ' '\n' | grep -E '^[0-9]+$' | tail -2 | head -1)"
  if [ "$last" -gt "$prev" ]; then
    log_fail "VERDICT: criticals are rising and the rise is above the noise floor. That is the one series where SIGNAL is bad news. Do not install."
    log_nofix "FLOOR.md — the next adversarial pass must bring the criticals series down"
    log_end || :; exit 2
  fi
}
log_ok "VERDICT: no series shows a significant worsening. Read the table, then decide."
log_end; exit $?
