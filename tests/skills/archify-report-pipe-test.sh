#!/usr/bin/env sh
# vendor/archify check-render-output.mjs printed its JSON report, then process.exit(): on a pipe
# that cut the report at 64 KB, and `archify validate` crashed on a wide drawing (PROVENANCE.md).
. "$(dirname "$0")/../lib/core.sh"; t_init
A="$T_ROOT/vendor/archify"; F="$T_ROOT/fixtures/archify/fanout.architecture.json"
t_section "the fixture still produces a report over 64 KB"
(cd "$T_TMP" && node "$A/bin/archify.mjs" render architecture "$F" "$T_TMP/fanout.html" --quality standard >/dev/null 2>&1)
BYTES="$(node "$A/scripts/check-render-output.mjs" "$T_TMP/fanout.html" | wc -c | tr -d ' ')"
t_eq "report is larger than one pipe buffer" yes "$([ "${BYTES:-0}" -gt 65536 ] && echo yes || echo "no ($BYTES)")"
t_section "validate reads the whole report"
OUT="$(cd "$T_TMP" && node "$A/bin/archify.mjs" validate architecture "$F" --quality standard 2>&1)"; RC=$?
t_eq "validate exits 0" 0 "$RC"
t_has "validate reports ok" "$OUT" "ok architecture"
t_hasnt "no truncated JSON" "$OUT" "SyntaxError"
t_done
