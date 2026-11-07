#!/usr/bin/env sh
# The status pane mod (harbor#1480): `claude plugin validate` is clean and `claude plugin test` passes on mods/status-pane.
# The mod's own tests hold the pane's guarantees, each shown red once: a button press appends the row, an id outside the
# source table is refused unrun, a failing source renders `unavailable: <reason>`, open and refresh run no scan (harbor#1485),
# scan-used follows only a scan that worked, the write table refuses any id the pane does not hold. Skips, loudly, where the claude CLI
# is absent (the Linux CI runners), since both checks are the CLI's own.
. "$(dirname "$0")/../../lib/core.sh"; t_init
MOD="$T_ROOT/mods/status-pane"
CLAUDE="$(command -v claude 2>/dev/null || true)"
if [ -z "$CLAUDE" ]; then
  echo "  SKIP the status pane: no claude CLI on PATH, so neither the validator nor the plugin test kit can run here"
  t_section "claude is absent: the mod is still where the suite looks for it"
  t_eq "mods/status-pane/.claude-plugin/plugin.json exists" present "$([ -f "$MOD/.claude-plugin/plugin.json" ] && echo present || echo absent)"
  t_done
fi

t_section "validate: the manifest and the hooks module as the engine reads them"
OUT="$("$CLAUDE" plugin validate "$MOD" 2>&1)"; RC=$?
t_eq "validate exits 0" 0 "$RC"
t_has "...and says it passed" "$OUT" 'Validation passed'
t_has "...seeing the three hooks" "$OUT" 'session.start, command.run{command=status-pane}, ui.render{component=Pane, requestId=status-pane}'
t_hasnt "...and no error" "$OUT" 'rror:'

t_section "test: the mod's own tests against the engine"
OUT="$("$CLAUDE" plugin test "$MOD" 2>&1)"; RC=$?
t_eq "plugin test exits 0" 0 "$RC"
WANT="$(grep -c '^test(' "$MOD/tests/pane.test.tsx")" # every test of the file, derived: a skipped or unreached one shows here
t_has "...all $WANT passed" "$OUT" " $WANT pass"
t_has "...none failed" "$OUT" ' 0 fail'
t_done
