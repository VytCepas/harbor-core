#!/usr/bin/env sh
# harbor#1421: the session server answers a click on a local page in under 1 s at the median (20 clicks, headless Chromium
# this suite starts itself), refuses each guard's case against the real daemon, and reports a closed daemon as a hand-off.
# The measurement and its table are benchmark.sh's; this suite is its verdict. A box with no headless browser skips.
. "$(dirname "$0")/../../lib/core.sh"; t_init
t_section "benchmark.sh: the median click, and the guards against a real daemon"
_rc=0; sh "$T_ROOT/tests/access/chrome/benchmark.sh" 20 > "$T_TMP/bench.out" 2>&1 || _rc=$?
if [ "$_rc" -eq 3 ]; then
  sed 's/^/  /' "$T_TMP/bench.out"; t_pass "skipped: a prerequisite is missing, so nothing was measured"
else
  t_eq "benchmark.sh passes (the table is below when it does not)" 0 "$_rc"
  [ "$_rc" -eq 0 ] || sed 's/^/  | /' "$T_TMP/bench.out"
  t_has "the median is under 1000 ms" "$(cat "$T_TMP/bench.out")" "< 1000 ms"
  t_has "a destructive label is refused by the real daemon's server" "$(cat "$T_TMP/bench.out")" "refused: a destructive label"
  t_has "a closed daemon is a hand-off" "$(cat "$T_TMP/bench.out")" "a closed daemon: hand-off"
fi
t_done
