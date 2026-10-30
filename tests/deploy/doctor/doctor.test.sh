#!/usr/bin/env sh
# deploy-doctor.sh's report: value lines carry values, the FLOOR_GREP pin agrees with guard-lib,
# and an unreadable guard-lib reads blank rather than as a value (harbor#371).
. "$(dirname "$0")/../../lib/core.sh"; t_init
OUT="$(sh "$T_ROOT/bin/deploy-doctor.sh" 2>&1)"; RC=$?
resolve() { sh -c '. "$1/bin/library-admission.sh" >/dev/null 2>&1 && printf %s "${FLOOR_GREP:-}"' _ "$1" 2>/dev/null; }

t_section "doctor exits 0 and produces a report"
t_eq "deploy-doctor.sh exit" 0 "$RC"
t_eq "report is longer than 200 bytes" yes "$([ "$(printf '%s' "$OUT" | wc -c)" -gt 200 ] && echo yes)"

t_section "no value line prints raw shell instead of its answer"
t_eq "lines with unexpanded \$( or \${" 0 "$(printf '%s' "$OUT" | grep -cE '\$\(|\$\{')"

t_section "the FLOOR_GREP pin is absolute and agrees with guard-lib"
PIN="$(printf '%s' "$OUT" | sed -n 's/^  note: FLOOR_GREP pin *: *//p' | head -1)"
t_eq "pin is an absolute path" / "$(printf '%.1s' "$PIN")"
REAL="$(resolve "$T_ROOT")"
t_eq "guard-lib resolves a FLOOR_GREP" yes "${REAL:+yes}"
t_eq "pin matches guard-lib's FLOOR_GREP" "$REAL" "$PIN"

t_section "an unreadable guard-lib resolves blank, not to a value"
mkdir -p "$T_TMP/nolib/bin"
t_eq "resolver on a tree with no library-admission.sh" "" "$(resolve "$T_TMP/nolib")"

t_section "every fatal dependency is named with a status"
for t in jq grep awk sed git; do
  t_eq "row for $t" yes "$(printf '%s\n' "$OUT" | grep -qE "^$t  *(ok|MISSING)" && echo yes)"
done

t_section "a missing fatal dependency fails both modes (harbor#905)"
# This PATH is the real one minus jq. Before this case, no test made a probed tool go missing, so
# doctor could exit 0 on a fatal miss in either mode and stay green.
NOJQ="$T_TMP/nojq"; mkdir -p "$NOJQ"
for _d in $(printf '%s' "$PATH" | tr ':' ' '); do
  [ -d "$_d" ] || continue
  for _b in "$_d"/*; do
    _n="${_b##*/}"; [ "$_n" != jq ] && [ -x "$_b" ] && [ ! -e "$NOJQ/$_n" ] && ln -s "$_b" "$NOJQ/$_n"
  done
done
t_eq "positive control: jq is gone from that PATH" no "$(env PATH="$NOJQ" sh -c 'command -v jq' >/dev/null 2>&1 && echo yes || echo no)"
OUT2="$(env PATH="$NOJQ" sh "$T_ROOT/bin/deploy-doctor.sh" 2>&1)"; RC2=$?
t_eq "text mode exits 1" 1 "$RC2"
t_has "and names the fatal miss" "$OUT2" "  FAIL: jq missing"
J="$(env PATH="$NOJQ" sh "$T_ROOT/bin/deploy-doctor.sh" --json 2>/dev/null)"; RCJ=$?
t_eq "--json exits 1" 1 "$RCJ"
t_has "--json counts it" "$J" '"missing_fatal":1'

t_section "the report says presence is not correctness"
t_has "closing sentence" "$OUT" "availability, not correctness"
t_done
