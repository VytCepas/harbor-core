#!/usr/bin/env sh
# eval-pass-score.sh — MAD confidence gating over docs/explanation/admission-baseline.md's adversarial pass table.
# harbor#3 (workstream B), method taken from upstream `Loop` @ a4e8e74 (docs/reference/provenance.md).
#
# WHY: the install criterion ("a pass must find fewer defects than it introduces") was called failed by eye; with four data points a 17 -> 9 move may be
# indistinguishable from the series' own scatter. Upstream's Loop gates this with |delta| / MAD(series) and refuses to bank a delta below the noise floor.
# MAD, not stddev: n=4, and one pass-10-shaped outlier would swallow a stddev whole.
# Removed notes: docs/explanation/code-cases/bin-eval-pass-score.md
set -eu

# --help BEFORE ANY WORK (S4, harbor#140): the text is the header read out of THIS file, so help cannot drift; a script that ignored --help ran a
# sweep of `bin/*.sh --help` past five minutes.
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
# The report is the run's log (contracts/logging.md, harbor#771). Its exit code is its verdict (0 / 2 do not
# install / 3 the gate did not run), which admission-install.sh reads, so a verdict FAIL ends the run with that code.
. "$ROOT/bin/library-log.sh"
log_init pass-score
die() { log_fail "$1"; log_fix "$2"; log_end || :; exit "$3"; }
FLOOR="$ROOT/docs/explanation/admission-baseline.md"
NOISE_FLOOR=1.0   # |delta|/MAD below this is not evidence. Upstream's threshold.

[ -f "$FLOOR" ] || die "no $FLOOR" "git checkout -- docs/explanation/admission-baseline.md" 1

# ── Extract the pass table ────────────────────────────────────────────────
# The header row names the passes, each metric row carries one integer per pass; a leading ~ is tolerated (pass 10 was an estimate). The doc carries one
# table per pass-review, each a superset of the last, so the LAST match is current (grep -m1 read the pass-11 table).
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
      # MAD == 0: the series has no scale, so any movement is unmeasurable, not automatically real.
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
# Reported ALONGSIDE the table, not in the gate: the table counts DEFECTS FOUND PER ADVERSARIAL PASS, the replay counts RULE HITS ON REAL TRAFFIC, and
# substituting one for the other would change what the MAD gate gates (harbor#44's "read real block counts" taken literally would make this lie).
# The replay adds the denominator CONSTITUTION rule 2 (a false positive is a defect) never had.
_rp="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.helm-replay/baseline.tsv"
if [ -f "$_rp" ]; then
  _tot="$(wc -l < "$_rp" | tr -d ' ')"
  _blk="$(grep -c '	BLOCK	' "$_rp" 2>/dev/null | head -1 | tr -d ' \n')"
  case "$_blk" in ''|*[!0-9]*) _blk=0 ;; esac
  log_head "real-traffic evidence (M2)"
  log_note "$_blk of $_tot replayed real commands are blocked ($(awk -v b="$_blk" -v t="$_tot" 'BEGIN{printf "%.1f", (t>0?100*b/t:0)}')%)."
  log_note "This is a DIFFERENT quantity from the table above — rule hits on traffic, not defects found per pass. It does not enter the MAD gate."
  log_note "Adjudicate it with: sh bin/eval-replay.sh --labels"
else
  log_head "real-traffic evidence (M2)"
  log_skip "No replay baseline yet. The install criterion above is still being read from adversarial-pass ESTIMATES against synthetic assertions."
  log_note "Build the evidence with: sh bin/eval-replay.sh --baseline"
fi

# THE GATE WAS ONE-SIDED (#47 finding 20): it fired only when criticals was above the noise floor AND rising on the last step, so a run of clean passes
# then a jump, or a series ending flat above zero, exited 0. Hence the LEVEL test (criticals above zero at the end is not clean) and the TREND test across
# the whole series. `|| true` because grep is last in the pipeline and `set -eu` killed the script on a criticals row with no numeric cell (rc=1, no verdict).
# An empty series is UNMEASURED: a gate that did not run must not print a verdict that reads like it did (pass-3 review).
crit_all="$(row criticals | tr ' ' '\n' | grep -E '^[0-9]+$' || true)"
if [ -z "${crit_all:-}" ]; then
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
       log_nofix "docs/explanation/admission-baseline.md — fix and pin each one, or accept it in writing as a published residual (decision 23, harbor#1149)"
       log_end || :; exit 2 ;;
  esac
fi
if [ -n "${crit_last:-}" ] && [ "$crit_last" -gt 0 ]; then
  # A series that ENDS above zero does not meet "fewer defects than it introduces", whichever direction it moved.
  [ "${crit_last:-0}" -lt "${crit_max:-0}" ] || log_note "the latest criticals value is the worst in the series, not a recovery from it"
  log_fail "VERDICT: the latest pass still reports $crit_last critical(s). Do not install."
  log_nofix "docs/explanation/admission-baseline.md — an adjudicated pass that leaves zero criticals open, its row \`| open criticals |\` (decision 23, harbor#1149)"
  log_end || :; exit 2
fi
if [ -n "${crit_first:-}" ] && [ -n "${crit_last:-}" ] && [ "$crit_last" -gt "$crit_first" ]; then
  log_fail "VERDICT: criticals are higher than when the series began ($crit_first -> $crit_last). Do not install."
  log_nofix "docs/explanation/admission-baseline.md — the next adversarial pass must bring the criticals series down"
  log_end || :; exit 2
fi

printf '%s' "$verdict_lines" | grep -q 'criticals=SIGNAL' && {
  crit="$(row criticals)"
  last="$(printf '%s' "$crit" | tr ' ' '\n' | grep -E '^[0-9]+$' | tail -1)"
  prev="$(printf '%s' "$crit" | tr ' ' '\n' | grep -E '^[0-9]+$' | tail -2 | head -1)"
  if [ "$last" -gt "$prev" ]; then
    log_fail "VERDICT: criticals are rising and the rise is above the noise floor. That is the one series where SIGNAL is bad news. Do not install."
    log_nofix "docs/explanation/admission-baseline.md — the next adversarial pass must bring the criticals series down"
    log_end || :; exit 2
  fi
}
log_ok "VERDICT: no series shows a significant worsening. Read the table, then decide."
log_end; exit $?
