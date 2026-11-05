#!/usr/bin/env sh
# harbor ui's headlines, lifecycle and table rows (harbor#738), split from panels.test.sh at its line budget: a tile reads
# the id its source prints, stopping the server stops every source it started, and the Fleet panel names the CLI
# the roots row names. Skips, loudly, where bun is absent.
REAL_HOME="$HOME"; UI_BUN="${HARBOR_STATUS_CONSOLE_BUN:-}"; REQ_BUN="${HARBOR_TEST_REQUIRE_BUN:-0}"  # before t_init clears them
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/lib/linux-sim.sh"; . "$T_ROOT/tests/cli/console-fixture.sh"
[ -n "$UI_BUN" ] || UI_BUN="$(command -v bun 2>/dev/null || true)"
[ -n "$UI_BUN" ] || { [ ! -x "$REAL_HOME/.bun/bin/bun" ] || UI_BUN="$REAL_HOME/.bun/bin/bun"; }
if [ -z "$UI_BUN" ]; then
  echo "  SKIP the panels: no bun on PATH (the runner image carries it once rebuilt)"
  t_section "bun is absent: only an image that does not promise it may skip"
  t_eq "HARBOR_TEST_REQUIRE_BUN is off where bun is absent" 0 "$REQ_BUN"
  t_done
fi
alive() { case "$(ps -o stat= -p "$1" 2>/dev/null)" in ''|Z*) echo no ;; *) echo yes ;; esac; }
hang_tree() { ui_tree 0; printf '#!/bin/sh\nsleep 12 &\necho $! > "%s/hang.pid"\nwait\n' "$T_TMP" > "$UI_ROOT/bin/admission-verify.sh"; chmod +x "$UI_ROOT/bin/admission-verify.sh"; rm -f "$T_TMP/hang.pid"; }
orphan_gone() { _g=0; while [ $_g -lt 30 ] && [ "$(alive "$(cat "$T_TMP/hang.pid")")" = yes ]; do sleep 0.1; _g=$((_g + 1)); done; alive "$(cat "$T_TMP/hang.pid")"; }

t_section "a headline reader reads the id its source prints (a renamed check id left Memory at 'ran ok')"
# The id comes from the script itself, so renaming it there makes this red; the reader is the one in sources.ts.
MEM_ID="$(sed -n 's/.*say "\[check:\([A-Za-z0-9.-]*\)\].*/\1/p' "$T_ROOT/bin/memory-route.sh" | head -1)"
t_has "memory-route.sh prints a [check:<id>] line" "$MEM_ID" "memory"
cat > "$T_TMP/headline.ts" <<HEADLINE_TS
import { makePanels } from "$T_ROOT/tools/ui/sources.ts";
const p = makePanels("$T_ROOT", "/cfg", "/home").find((x) => x.id === "memory")!;
console.log(p.headline!({ text: "[check:$MEM_ID] /cfg\n  ok     a/b - 5 notes\n[check:$MEM_ID] green - 3 of 3 governed repo(s) routed\nmemory-route: 0 ok, 0 failed, 0 warnings\n" }));
HEADLINE_TS
cat > "$T_TMP/headline2.ts" <<HEADLINE_TS
import { makePanels } from "$T_ROOT/tools/ui/sources.ts";
const p = makePanels("$T_ROOT", "/cfg", "/home").find((x) => x.id === "worktrees")!;
console.log(p.headline!({ text: "VERDICT  PATH  BRANCH  WHY\nSKIP     /a  main  the main worktree\nPRUNE    /b  x  directory is gone\nCOLLECT  /c  y  clean\n" }));
HEADLINE_TS
t_eq "the worktrees tile counts every verdict the script prints (PRUNE too)" "3 worktrees" "$("$UI_BUN" "$T_TMP/headline2.ts" 2>&1)"
t_eq "the memory tile reads the check line" "green - 3 of 3 governed repo(s) routed" "$("$UI_BUN" "$T_TMP/headline.ts" 2>&1)"


t_section "stopping the server (ctrl-c, SIGTERM, the idle stop) stops what a source is still running: nothing is orphaned"
srv_gone() { _g=0; while [ $_g -lt 100 ] && [ "$(alive "$1")" = yes ]; do sleep 0.1; _g=$((_g + 1)); done; alive "$1"; }
pid_up() { _g=0; while [ $_g -lt 100 ] && [ ! -s "$T_TMP/hang.pid" ]; do sleep 0.1; _g=$((_g + 1)); done; [ -s "$T_TMP/hang.pid" ]; }
hang_tree; ui_start stopsig --idle 120
ui_post '{"id":"floor"}' > /dev/null 2>&1 & Q1=$!
pid_up
t_eq "the source is running when the server is told to stop" yes "$(alive "$(cat "$T_TMP/hang.pid")")"
kill -TERM "$UI_PID"; t_eq "SIGTERM stops the server" no "$(srv_gone "$UI_PID")"
t_eq "and the sleep the source forked is gone with it" no "$(orphan_gone)"
wait "$Q1" 2>/dev/null; kill "$(cat "$T_TMP/hang.pid")" 2>/dev/null
hang_tree; ui_start stopidle --idle 2
ui_post '{"id":"floor"}' > /dev/null 2>&1 & Q1=$!
pid_up
t_eq "the idle stop ends the server with the source still running" no "$(srv_gone "$UI_PID")"
t_eq "and the sleep the source forked is gone with it" no "$(orphan_gone)"
wait "$Q1" 2>/dev/null; kill "$(cat "$T_TMP/hang.pid")" 2>/dev/null
ui_mutant shutdown 's/^export function killLive() {.*$/export function killLive() {} \/\/ guard:shutdown/' sources.ts
t_eq "the shutdown mutant differs" changed "$UI_MUT"
hang_tree; ui_start mshut --idle 120
ui_post '{"id":"floor"}' > /dev/null 2>&1 & Q1=$!
pid_up; kill -TERM "$UI_PID"; srv_gone "$UI_PID" > /dev/null
t_eq "without the kill the same probe finds the sleep still running" yes "$(alive "$(cat "$T_TMP/hang.pid")")"
wait "$Q1" 2>/dev/null; kill "$(cat "$T_TMP/hang.pid")" 2>/dev/null; UI_SCRIPT=""

t_section "the fleet CLI's name is the roots.tsv row, not a literal in the panel table (fleet's console script can be renamed in one place)"
ui_tree 0; rm -f "$T_BIN/projects-orchestrator"
printf '#!/bin/sh\n[ "$1" = --get ] && [ "$2" = HARBOR_SCOPE_FLEET_CONTROLLER_BIN ] && echo "$HOME/.local/bin/fleet-x"\n' > "$UI_ROOT/bin/scope-roots.sh"
ui_cmd fleet-x 0 '[{"descriptor":{"name":"xproj"},"status":{"branch":"main","dirty":false,"ahead":0,"behind":0,"last_commit":"t"}}]'
ui_start fleetrow --idle 120
FR="$(ui_get /)"
t_has "the Fleet panel names the command the row names" "$(ui_panel "$FR" fleet)" "fleet-x snapshot --json"
t_has "and shows what it printed" "$(ui_panel "$FR" fleet)" "<td>xproj</td>"
ui_stop
t_done
