#!/usr/bin/env sh
# harbor ui's panels (harbor#738): each names its source and run time, is derived at page load, says
# `unavailable: <reason>` and never 0, and shows no command output unescaped. Red proofs as in console-guards-test.sh.
# Skips, loudly, where bun is absent; HARBOR_REQUIRE_BUN=1 turns that into a failure.
REAL_HOME="$HOME"; UI_BUN="${HARBOR_STATUS_CONSOLE_BUN:-}"; REQ_BUN="${HARBOR_REQUIRE_BUN:-0}"  # before t_init clears them
. "$(dirname "$0")/../lib/core.sh"; t_init
. "$T_ROOT/tests/lib/linux-sim.sh"; . "$T_ROOT/tests/cli/console-fixture.sh"
[ -n "$UI_BUN" ] || UI_BUN="$(command -v bun 2>/dev/null || true)"
[ -n "$UI_BUN" ] || { [ ! -x "$REAL_HOME/.bun/bin/bun" ] || UI_BUN="$REAL_HOME/.bun/bin/bun"; }
if [ -z "$UI_BUN" ]; then
  echo "  SKIP the panels: no bun on PATH (the runner image carries it once rebuilt)"
  t_section "bun is absent: only an image that does not promise it may skip"
  t_eq "HARBOR_REQUIRE_BUN is off where bun is absent" 0 "$REQ_BUN"
  t_done
fi
cmd_of() { case "$1" in # the source command each panel must name
  floor) echo 'bin/floor-verify.sh --live' ;; findings) echo 'bin/findings.sh report' ;; register) echo 'CHECKS.md' ;;
  checks) echo 'cache/checks.log' ;; guards) echo 'bin/observe-report.sh --fp' ;; context) echo 'bin/context-budget.sh --check' ;;
  memory) echo 'bin/memory-route.sh --live' ;; backlog) echo 'bin/issue-connector.sh --audit' ;;
  fleet) echo 'projects-orchestrator snapshot --json' ;; sessions) echo 'bin/fleet-sessions.sh --json' ;;
  worktrees) echo 'bin/worktree.sh list' ;; prs) echo 'gh pr list --json' ;; obligations) echo 'bin/status-obligations.sh show --json' ;; esac; }
ob_panel() { ui_panel "$1" obligations; }
ob_view() { printf '%s' "$1" | sed 's/<div data-view=/\n<div data-view=/g' | grep "^<div data-view=\"$2\""; }
ob_titles() { printf '%s' "$1" | grep -o '<td>fixture [^<]*</td>' | sed 's/<[^>]*>//g' | tr '\n' ','; }
tiles_unavailable() { printf '%s\n' "$1" | grep -o 'class="value">unavailable<' | wc -l | tr -d ' '; }
want_n="$(printf '%s\n' $PANEL_IDS | wc -l | tr -d ' ')"

ui_tree 0; ui_start good --idle 300
PAGE="$(ui_get /)"
t_section "every panel is present, names its source command and when it ran"
for id in $PANEL_IDS; do
  S="$(ui_panel "$PAGE" "$id")"
  t_has "$id is on the page" "$S" "id=\"p-$id\""
  t_has "$id names its source command" "$S" "$(cmd_of "$id")"
  t_has "$id carries its run time" "$S" '<time datetime="20'
done
t_section "ui_panel returns that panel's section and no other (harbor#1113: it used to return all of them for every id)"
for id in $PANEL_IDS; do
  S="$(ui_panel "$PAGE" "$id")"
  t_eq "$id: exactly one section comes back" 1 "$(printf '%s' "$S" | grep -o '<section' | wc -l | tr -d ' ')"
  t_has "$id: and it is the one asked for" "$S" "id=\"p-$id\""
done
t_hasnt "the floor section does not carry the findings panel" "$(ui_panel "$PAGE" floor)" 'id="p-findings"'
t_has "the page says it is read-only" "$PAGE" "read-only"
t_has "the Work tab is there" "$PAGE" 'data-tab-btn="work"'

t_section "each panel shows what its source printed, with the healthy kept quiet"
t_has "floor: the summary line becomes the headline" "$PAGE" 'class="value">2 ok · 1 warn<'
t_has "floor: the two ok lines fold away" "$(ui_panel "$PAGE" floor)" "2 healthy lines"
t_has "floor: the warning stays in view" "$(ui_panel "$PAGE" floor)" '<span class="warn">  WARN: c</span>'
t_has "the register lists the check's id" "$(ui_panel "$PAGE" register)" "<td>alpha-check</td>"
t_has "the alerts panel shows the log line" "$(ui_panel "$PAGE" checks)" "fixture line"
t_has "fleet is a table of repos" "$(ui_panel "$PAGE" fleet)" "<td>proj</td>"
t_has "sessions are a table" "$(ui_panel "$PAGE" sessions)" "<td>s1</td>"
t_has "pull requests are a table" "$(ui_panel "$PAGE" prs)" "<td>fixture pr</td>"
t_has "text sources show their output" "$(ui_panel "$PAGE" backlog)" "fixture issue-connector output"

t_section "a page load shows stored results: it runs a source only when none is stored, or it is older than --min-age"
t_eq "the first load ran floor once" 1 "$(ui_calls floor-verify)"
t_eq "and gh once" 1 "$(ui_calls gh)"
ui_get / > /dev/null; ui_get / > /dev/null; ui_get / > /dev/null
t_eq "three more loads started no floor run" 1 "$(ui_calls floor-verify)"
t_eq "nor a gh run" 1 "$(ui_calls gh)"
ui_post '{"id":"floor"}' > /dev/null
t_eq "a POST /run re-runs that one panel" 2 "$(ui_calls floor-verify)"
t_eq "and only that one" 1 "$(ui_calls gh)"
t_eq "POST /refresh is refused without the session" 403 "$(ui_code -X POST "$UI_URL/refresh")"
ui_code -X POST -H "Cookie: $UI_COOKIE" "$UI_URL/refresh" > /dev/null
t_eq "POST /refresh re-runs everything" 2 "$(ui_calls gh)"

t_section "SSE: a re-run panel reaches an open stream"
curl -sN -m 6 -H "Cookie: $UI_COOKIE" "$UI_URL/events" > "$T_TMP/sse.out" 2>/dev/null &
SSE=$!; sleep 1
ui_post '{"id":"prs"}' > /dev/null
wait "$SSE" 2>/dev/null
t_has "the stream opens" "$(cat "$T_TMP/sse.out")" ": connected"
t_has "it carries a panel event" "$(cat "$T_TMP/sse.out")" "event: panel"
t_has "for the panel that was re-run" "$(cat "$T_TMP/sse.out")" '"id":"prs"'
ui_stop

t_section "--min-age: a stored result older than it is derived again on the next load"
ui_stop
ui_tree 0
ui_start aged --idle 120 --min-age 1
ui_get / > /dev/null; sleep 2; ui_get / > /dev/null
t_eq "the second load, 2s later, ran floor again" 2 "$(ui_calls floor-verify)"
ui_stop
ui_mutant minage 's/num("--min-age", 300)/num("--min-age", 0)/'
t_eq "the min-age mutant differs" changed "$UI_MUT"
rm -f "$T_TMP"/calls.*
ui_start mminage --idle 120
ui_get / > /dev/null; ui_get / > /dev/null; ui_get / > /dev/null
t_eq "with no minimum age every load starts a run, which is what a repeated GET must not do" 3 "$(ui_calls floor-verify)"
ui_stop; UI_SCRIPT=""

t_section "one run per panel: two overlapping requests start one process"
ui_tree 0; UI_STUB_SLEEP=2; ui_stub floor-verify 0 "slow"; UI_STUB_SLEEP=""
ui_start slow --idle 120
ui_post '{"id":"floor"}' > /dev/null & Q1=$!
ui_post '{"id":"floor"}' > /dev/null & Q2=$!
wait "$Q1" "$Q2"
t_eq "one floor-verify ran" 1 "$(ui_calls floor-verify)"
ui_stop
ui_mutant inflight '/guard:inflight/d'
t_eq "the in-flight mutant differs" changed "$UI_MUT"
rm -f "$T_TMP"/calls.*
ui_start minflight --idle 120
ui_post '{"id":"floor"}' > /dev/null & Q1=$!
ui_post '{"id":"floor"}' > /dev/null & Q2=$!
wait "$Q1" "$Q2"
t_eq "without the lock the same two requests start two" 2 "$(ui_calls floor-verify)"
ui_stop; UI_SCRIPT=""

t_section "a source that hangs is cut off at --timeout, and so is everything it forked"
hang_tree() { ui_tree 0; printf '#!/bin/sh\nsleep 12 &\necho $! > "%s/hang.pid"\nwait\n' "$T_TMP" > "$UI_ROOT/bin/floor-verify.sh"; chmod +x "$UI_ROOT/bin/floor-verify.sh"; rm -f "$T_TMP/hang.pid"; }
orphan_gone() { _g=0; while [ $_g -lt 30 ] && [ "$(alive "$(cat "$T_TMP/hang.pid")")" = yes ]; do sleep 0.1; _g=$((_g + 1)); done; alive "$(cat "$T_TMP/hang.pid")"; }
alive() { case "$(ps -o stat= -p "$1" 2>/dev/null)" in ''|Z*) echo no ;; *) echo yes ;; esac; }
hang_tree
ui_start hang --idle 120 --timeout 1
T0="$(date +%s)"; ui_post '{"id":"floor"}' > /dev/null; DT=$(( $(date +%s) - T0 ))
t_eq "the request returned in about the timeout, not the hang" yes "$([ "$DT" -lt 8 ] && echo yes)"
t_has "the panel says it timed out" "$(ui_panel "$(ui_get /)" floor)" "unavailable: timed out after 1s"
t_eq "the sleep the source forked is gone" no "$(orphan_gone)"
T0="$(date +%s)"; RC="$(ui_code -X POST -H "Cookie: $UI_COOKIE" "$UI_URL/refresh")"; DT=$(( $(date +%s) - T0 ))
t_eq "the panel is not locked: /refresh answers" 200 "$RC"
t_eq "and promptly" yes "$([ "$DT" -lt 8 ] && echo yes)"
ui_stop; kill "$(cat "$T_TMP/hang.pid")" 2>/dev/null
ui_mutant deadline 's/await Promise.race(\[done, deadline\])/await done/' sources.ts
t_eq "the deadline mutant differs" changed "$UI_MUT"
hang_tree; ui_start mdead --idle 120 --timeout 1
T0="$(date +%s)"; ui_post '{"id":"floor"}' > /dev/null; DT=$(( $(date +%s) - T0 ))
t_eq "without the deadline the request waits for the hung child" no "$([ "$DT" -lt 8 ] && echo yes || echo no)"
ui_stop; kill "$(cat "$T_TMP/hang.pid")" 2>/dev/null
ui_mutant groupkill '/guard:groupkill/s/.*/    proc.kill(); \/\/ guard:groupkill/' sources.ts
t_eq "the group-kill mutant differs" changed "$UI_MUT"
hang_tree; ui_start mgroup --idle 120 --timeout 1
ui_post '{"id":"floor"}' > /dev/null
t_eq "killing only the shell leaves the forked sleep running" yes "$(alive "$(cat "$T_TMP/hang.pid")")"
ui_stop; kill "$(cat "$T_TMP/hang.pid")" 2>/dev/null; UI_SCRIPT=""

t_section "output is escaped: a PR title or a command line cannot inject markup"
ui_tree 0
EVIL='<script>alert(1)</script> & "q"'
ui_stub findings 0 "$EVIL"; ui_cmd gh 0 '[{"number":1,"title":"<img src=x onerror=alert(1)>","headRefName":"b","isDraft":false,"updatedAt":"t"}]'
ui_start esc --idle 120; EP="$(ui_get /)"
t_has "the script tag arrives as text" "$EP" '&lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;q&quot;'
t_hasnt "and never as a tag" "$EP" '<script>alert(1)'
t_has "a PR title arrives as text" "$EP" '&lt;img src=x onerror=alert(1)&gt;'
t_hasnt "and never as a tag" "$EP" '<img src=x'
ui_stop
ui_mutant esc '/guard:escape/s/.*/export const esc = (s: unknown) => String(s);/' render.ts
t_eq "the escape mutant differs" changed "$UI_MUT"
ui_start mesc --idle 120
MESC="$(ui_get /)"
t_has "without esc() the same probe finds a live script tag" "$MESC" '<script>alert(1)</script> & "q"'
t_has "and a live img tag" "$MESC" '<img src=x onerror=alert(1)>'; ui_stop
UI_SCRIPT=""

t_section "every source failing renders unavailable, never 0"
ui_tree 3; ui_start fail --idle 120
FP="$(ui_get /)"
t_eq "the page still answers" 200 "$(ui_code -H "Cookie: $UI_COOKIE" "$UI_URL/")"
for id in $PANEL_IDS; do t_has "$id says unavailable" "$(ui_panel "$FP" "$id")" "unavailable:"; done
t_eq "every tile says unavailable" "$want_n" "$(tiles_unavailable "$FP")"
t_hasnt "no tile reads 0" "$FP" 'class="value">0<'
t_has "the reason is the source's own words" "$(ui_panel "$FP" floor)" "unavailable: exit 3: stub floor-verify: boom"
t_has "a panel still names its source when it failed" "$(ui_panel "$FP" floor)" "bin/floor-verify.sh --live"
ui_stop
ui_mutant exit 's/if (!p.okExits.includes(code))/if (false)/' sources.ts
t_eq "the exit-code mutant differs" changed "$UI_MUT"
ui_start mexit --idle 120
t_hasnt "treating any exit as an answer, the same probe finds no unavailable" "$(ui_panel "$(ui_get /)" floor)" "unavailable:"; ui_stop
UI_SCRIPT=""

ui_mutant ctxdown 's/r.status === "unavailable" ? `unavailable/(r.status === "unavailable" \&\& p.id !== "context") ? `unavailable/' render.ts
t_eq "the context-never-unavailable mutant differs" changed "$UI_MUT"
ui_tree 3; ui_start mctx --idle 120; MCX="$(ui_get /)"
t_hasnt "a context panel that never says unavailable is seen by the per-panel probe" "$(ui_panel "$MCX" context)" "unavailable:"
t_has "while the panel beside it still says so" "$(ui_panel "$MCX" floor)" "unavailable:"
t_has "and the whole page still contains the word, which is all the old helper looked at" "$MCX" "unavailable: exit 3"
ui_stop; UI_SCRIPT=""

t_section "a source that does not exist on this box is unavailable, not an error"
ui_tree 0; rm -rf "$UI_ROOT/bin" "$T_BIN/gh" "$T_BIN/projects-orchestrator"
linux_path "$T_TMP/nogh" gh projects-orchestrator harbor
OLDPATH="$PATH"; PATH="$T_TMP/nogh"; ui_start missing --idle 120; PATH="$OLDPATH"
MP="$(ui_get /)"
t_eq "the page is a 200" 200 "$(ui_code -H "Cookie: $UI_COOKIE" "$UI_URL/")"
t_has "a missing script is named" "$(ui_panel "$MP" floor)" "unavailable: bin/floor-verify.sh is not on this box"
t_has "a missing command is named" "$(ui_panel "$MP" fleet)" "unavailable: projects-orchestrator is not installed on this box"
t_has "gh too" "$(ui_panel "$MP" prs)" "unavailable: gh is not installed on this box"
t_has "and the obligations script, for the Obligations tab: unavailable, never 0" "$(ob_panel "$MP")" "unavailable: bin/status-obligations.sh is not on this box"
t_eq "the panels that could still run did" yes "$(ui_panel "$MP" register | grep -q '<td>alpha-check</td>' && echo yes)"
ui_stop
OB_NEW='{"id":"pr:acme/widgets#9","kind":"pr","subject":"acme/widgets#9","repo":"widgets","owner":"operator","title":"fixture brand new","link":"","opened_ts":"2026-10-06T01:29:00Z","deadline_ts":"","state":"open","closed_by":"","closed_ts":"","age_s":60}'
OB_ROWS_4="[$OB_NEW,${OB_ROWS_3#\[}"
OB_SRC_EV_DOWN='{"events":{"ok":false,"reason":"bus unreadable","ts":"2026-10-06T01:30:00Z"},"gh":{"ok":true,"reason":"","ts":"2026-10-06T01:30:00Z"}}'
OB_SRC_GH_DOWN='{"events":{"ok":true,"reason":"","ts":"2026-10-06T01:30:00Z"},"gh":{"ok":false,"reason":"gh not logged in","ts":"2026-10-06T01:30:00Z"}}'
OB_SRC_ALL_DOWN='{"events":{"ok":false,"reason":"bus unreadable","ts":"x"},"gh":{"ok":false,"reason":"gh not logged in","ts":"x"}}'
nbadge() { printf '%s' "$1" | grep -o 'data-kind="new"' | wc -l | tr -d ' '; }
ob_tree() { ui_tree 0; OB_ROWS="${1:-}"; OB_SOURCES="${2:-}"; OB_PROPOSALS="${3:-}"; ob_set; OB_ROWS=""; OB_SOURCES=""; OB_PROPOSALS=""; }  # a good tree with the Obligations output replaced
ob_seq() { # <name> — view, a row appears, view, the source goes down, comes back, view: sets SEQ_NEW2 and SEQ_NEW4 (new badges in the flat view)
  ui_tree 0; ui_start "$1" --idle 120
  ui_get / > /dev/null
  OB_ROWS="$OB_ROWS_4"; ob_set; ui_post '{"id":"obligations"}' > /dev/null
  SEQ_NEW2="$(nbadge "$(ob_view "$(ob_panel "$(ui_get /)")" none)")"
  ob_stub_raw 3 x; ui_post '{"id":"obligations"}' > /dev/null; ui_get / > /dev/null
  ob_set; ui_post '{"id":"obligations"}' > /dev/null; OB_ROWS=""
  SEQ_NEW4="$(nbadge "$(ob_view "$(ob_panel "$(ui_get /)")" none)")"
  ui_stop
}

t_section "Obligations tab: the frozen JSON, ordered new, then overdue, then oldest, each row linked (harbor#1053)"
ui_tree 0; ui_start ob --idle 300
OP1="$(ob_panel "$(ui_get /)")"; PG1="$(ui_get /)"
t_has "the tab is there" "$PG1" 'data-tab-btn="obligations"'
t_has "it carries its run time" "$OP1" '<time datetime="20'
t_has "and when the command generated the list" "$OP1" 'datetime="2026-10-06T01:30:00Z"'
t_has "each source it reported is listed as ok" "$OP1" '<code>events</code> ok'
t_has "the first view names its baseline honestly" "$OP1" "first view since this console started"
t_hasnt "so nothing is marked new yet" "$OP1" 'data-kind="new"'
t_eq "overdue first, then the oldest, then the rest" "fixture overdue agent,fixture oldest intent,fixture open pr," "$(ob_titles "$(ob_view "$OP1" none)")"
t_has "a row's age is shown" "$OP1" '>25h<'
t_has "and its overdue badge" "$OP1" 'data-kind="overdue"'
t_has "a row links to its PR" "$OP1" '<a href="https://github.com/acme/widgets/pull/7" target="_blank" rel="noopener noreferrer">acme/widgets#7</a>'
t_has "the tile says how many and how many overdue" "$PG1" 'class="value">3 listed · 1 overdue<'
t_has "the empty proposals list says when it arrives" "$OP1" "No proposals"
ui_stop

t_section "grouped by repo, kind or owner, the groups with something new or overdue first"
ui_start grp --idle 120; OPG="$(ob_panel "$(ui_get /)")"
RV="$(ob_view "$OPG" repo)"
t_has "the repo view has a group per repo with its count" "$RV" '<h3>repo: widgets <span class="muted">2</span>'
t_eq "and the group with the overdue row is first" "<h3>repo: gadgets " "$(printf '%s' "$RV" | grep -o '<h3>[^<]*' | head -1)"
t_has "the kind view groups by kind" "$(ob_view "$OPG" kind)" '<h3>kind: intent '
t_has "the owner view groups by owner" "$(ob_view "$OPG" owner)" '<h3>owner: operator '
t_hasnt "the flat view has no groups" "$(ob_view "$OPG" none)" "<h3>"
ui_stop
ui_mutant ogrp 's/if (by === "none") return/if (true) return/' obligations.ts
t_eq "the grouping mutant differs" changed "$UI_MUT"
ui_start mogrp --idle 120
t_hasnt "ungrouped, the same probe finds no repo group" "$(ob_view "$(ob_panel "$(ui_get /)")" repo)" "<h3>repo:"; ui_stop; UI_SCRIPT=""

t_section "the delta: a row not listed at the previous view is new; an outage does not reset the baseline"
ui_tree 0; ui_start delta --idle 120
ui_get / > /dev/null
OB_ROWS="$OB_ROWS_4"; ob_set; OB_ROWS=""; ui_post '{"id":"obligations"}' > /dev/null
PG2="$(ui_get /)"; OP2="$(ob_panel "$PG2")"
t_eq "the new row comes first, then the old order" "fixture brand new,fixture overdue agent,fixture oldest intent,fixture open pr," "$(ob_titles "$(ob_view "$OP2" none)")"
t_eq "exactly one row is new" 1 "$(nbadge "$(ob_view "$OP2" none)")"
t_has "the tab says what new is relative to" "$OP2" "new = not listed at the previous view"
t_has "the tile counts it" "$PG2" 'class="value">4 listed · 1 overdue · 1 new<'
t_eq "a third view, nothing changed, has nothing new" 0 "$(nbadge "$(ob_panel "$(ui_get /)")")"
ui_stop
ob_seq seq
t_eq "the same sequence: one new badge after the row appears" 1 "$SEQ_NEW2"
t_eq "and none once the source is back after an outage" 0 "$SEQ_NEW4"
ui_mutant onew 's/isNew: base !== null \&\& !base.has(idOf(r))/isNew: false/' obligations.ts
t_eq "the new-badge mutant differs" changed "$UI_MUT"
ob_seq mseq1
t_eq "with newness switched off the same sequence shows no new row" 0 "$SEQ_NEW2"
ui_mutant obase 's/if (shapeProblem(json)) return;/if (false) return;/' obligations.ts
t_eq "the baseline mutant differs" changed "$UI_MUT"
ob_seq mseq2
t_eq "an outage that resets the baseline makes every row new on recovery" 4 "$SEQ_NEW4"
ui_mutant ovw '/beginView(states/d' server.ts
t_eq "the view-tracking mutant differs" changed "$UI_MUT"
ob_seq mseq3
t_eq "with no view recorded nothing is ever new" 0 "$SEQ_NEW2"; UI_SCRIPT=""

t_section "each source that did not answer says unavailable: <reason>, and an empty list is not a clean bill"
ob_tree "" "$OB_SRC_EV_DOWN"; ui_start sev --idle 120; PS="$(ui_get /)"; OPS="$(ob_panel "$PS")"
t_has "a failed source is named with its reason" "$OPS" '<code>events</code> unavailable: bus unreadable'
t_has "the source that answered is still ok" "$OPS" '<code>gh</code> ok'
t_has "the rows are still listed" "$OPS" "fixture open pr"
t_has "the tile counts the dead source" "$PS" 'class="value">3 listed · 1 overdue · 1 source down<'
ui_stop
ob_tree "" "$OB_SRC_GH_DOWN"; ui_start sgh --idle 120
t_has "the other source failing is named too" "$(ob_panel "$(ui_get /)")" '<code>gh</code> unavailable: gh not logged in'; ui_stop
ob_tree "[]" "$OB_SRC_ALL_DOWN"; ui_start sall --idle 120; PA="$(ui_get /)"; OPA="$(ob_panel "$PA")"
t_has "both are named" "$OPA" '<code>events</code> unavailable: bus unreadable'
t_has "an empty list over dead sources says so" "$OPA" "not a clean bill"
t_hasnt "the tile does not say none open" "$PA" 'class="value">none open'
t_hasnt "and no tile reads 0" "$PA" 'class="value">0<'
ui_stop
ui_mutant osrc 's/const ok = isObj(s) \&\& s.ok === true;/const ok = true;/' obligations.ts
t_eq "the source mutant differs" changed "$UI_MUT"
ob_tree "" "$OB_SRC_EV_DOWN"; ui_start mosrc --idle 120
t_hasnt "treating every source as ok, the same probe finds no unavailable" "$(ob_panel "$(ui_get /)")" "unavailable: bus unreadable"; ui_stop
ui_mutant ohead 's/down === 0 ? "none open" : "none listed"/true ? "none open" : "none listed"/' obligations.ts
t_eq "the headline mutant differs" changed "$UI_MUT"
ob_tree "[]" "$OB_SRC_ALL_DOWN"; ui_start mhead --idle 120
t_has "with the down-count check gone, dead sources read as none open" "$(ui_get /)" 'class="value">none open'; ui_stop; UI_SCRIPT=""

t_section "the command itself unavailable, or not the frozen shape, is unavailable, never an empty list"
for case in 'not json|output is not JSON' '{"obligations":[]}|output has no sources map' '[]|output is not a JSON object' '{"sources":{}}|output has no obligations list'; do
  ob_tree; ob_stub_raw 0 "${case%%|*}"; ui_start shape --idle 120; PH="$(ui_get /)"
  t_has "${case%%|*} says why" "$(ob_panel "$PH")" "unavailable: ${case#*|}"
  t_has "and its tile is there" "$PH" 'id="t-obligations"'
  t_eq "the tab shows no table" 0 "$(ob_panel "$PH" | grep -c '<table')"
  ui_stop
done
ob_tree "[]" "{}"; ui_start nosrc --idle 120
t_has "no sources at all is not a pass" "$(ob_panel "$(ui_get /)")" "unavailable: the command reported no sources"; ui_stop
ui_mutant oshape 's/if (bad) return unavailable(bad, t0, code);/if (false) return unavailable(bad, t0, code);/' sources.ts
t_eq "the shape mutant differs" changed "$UI_MUT"
ob_tree; ob_stub_raw 0 '{"obligations":[]}'; ui_start mshape --idle 120
t_eq "without the shape check the same probe no longer finds the reason" no "$(ui_get / | grep -q 'unavailable: output has no sources map' && echo yes || echo no)"; ui_stop; UI_SCRIPT=""

t_section "a link is rendered only if it is https://, whatever the JSON says"
BADROWS="[$(ob_row a1 'fixture good' 'https://ok.example/p' s1),$(ob_row a2 'fixture js' 'javascript:alert(1)' s2),$(ob_row a3 'fixture http' 'http://plain.example/x' s3),$(ob_row a4 'fixture rel' '//evil.example/x' s4),$(ob_row a5 'fixture data' 'data:text/html,hi' s5),$(ob_row a6 'fixture caps' 'HTTPS://caps.example/x' s6),$(ob_row a7 'fixture quote' 'https://ok.example/a\"onmouseover=\"alert(1)' s7),$(ob_row a8 'fixture nospace' ' https://ok.example/x' s8)]"
ob_tree "$BADROWS"; ui_start lnk --idle 120; LP="$(ob_view "$(ob_panel "$(ui_get /)")" none)"
t_has "the https link is a link" "$LP" '<a href="https://ok.example/p"'
t_hasnt "javascript: appears nowhere" "$LP" "javascript:"
t_hasnt "http: is not linked" "$LP" 'href="http:'
t_hasnt "a scheme-relative link is not linked" "$LP" 'href="//'
t_hasnt "data: is not linked" "$LP" 'href="data:'
t_hasnt "a capitalised scheme is not linked" "$LP" 'href="HTTPS'
t_hasnt "a leading space is not linked" "$LP" 'href=" '
t_has "a quote in an https link is encoded, not an attribute break" "$LP" '%22onmouseover'
t_hasnt "so no event handler attribute appears" "$LP" 'onmouseover="'
t_eq "only the two https rows are anchors" 2 "$(printf '%s' "$LP" | grep -o '<a href=' | wc -l | tr -d ' ')"
t_has "a row without a link still shows its subject" "$LP" "<td>s2</td>"
ui_stop
ui_mutant olink 's/ || !link.startsWith("https:\/\/")//' obligations.ts
t_eq "the link mutant differs" changed "$UI_MUT"
ob_tree "$BADROWS"; ui_start molink --idle 120
t_has "without the https-only check the same probe finds a javascript: href" "$(ob_view "$(ob_panel "$(ui_get /)")" none)" 'href="javascript:alert(1)"'; ui_stop; UI_SCRIPT=""

t_section "every string from the JSON is escaped: title, subject, repo, kind, owner, source name and reason, proposal title"
EV='<img src=x onerror=alert(1)>'
EROW="[$(ob_row e1 "$EV" '' '<script>alert(2)</script>' '\"><b>repo' '<i>owner' '<u>kind')]"
ESRC='{"<s>name":{"ok":false,"reason":"<b>why</b>","ts":"t"}}'
EPROP='[{"id":"p1","obligation_id":"<i>oid","title":"<em>prop</em>","argv":["x"]}]'
ob_tree "$EROW" "$ESRC" "$EPROP"; ui_start oesc --idle 120; EOP="$(ob_panel "$(ui_get /)")"
t_has "a title arrives as text" "$EOP" '&lt;img src=x onerror=alert(1)&gt;'
t_has "a subject arrives as text" "$EOP" '&lt;script&gt;alert(2)&lt;/script&gt;'
t_has "a repo with a quote arrives as text" "$EOP" '&quot;&gt;&lt;b&gt;repo'
t_has "an owner arrives as text" "$EOP" '&lt;i&gt;owner'
t_has "a kind arrives as text" "$EOP" '&lt;u&gt;kind'
t_has "a source name arrives as text" "$EOP" '&lt;s&gt;name'
t_has "a reason arrives as text" "$EOP" '&lt;b&gt;why&lt;/b&gt;'
t_has "a proposal title arrives as text" "$EOP" '&lt;em&gt;prop&lt;/em&gt;'
t_eq "and none of them survives as a tag" "" "$(printf '%s' "$EOP" | grep -o '<\(img src=x\|script>alert(2)\|b>repo\|i>owner\|u>kind\|s>name\|b>why\|em>prop\|i>oid\)' | head -1)"
ui_stop
ui_mutant oesc '/guard:escape/s/.*/export const esc = (s: unknown) => String(s);/' render.ts
t_eq "the escape mutant differs" changed "$UI_MUT"
ob_tree "$EROW" "$ESRC" "$EPROP"; ui_start moesc --idle 120
t_has "without esc() the same probe finds a live img tag" "$(ob_panel "$(ui_get /)")" '<img src=x onerror=alert(1)>'; ui_stop; UI_SCRIPT=""

t_section "the empty states: nothing listed, no proposals, and closed rows folded away"
ob_tree "[]"; ui_start empty --idle 120; PE="$(ui_get /)"; OPE="$(ob_panel "$PE")"
t_has "an empty list over healthy sources says nothing is listed" "$OPE" "nothing listed"
t_has "the tile says none open" "$PE" 'class="value">none open<'
t_has "proposals have an empty state naming #1052" "$OPE" "No proposals. They arrive with harbor#1052"
t_hasnt "no source is called unavailable" "$OPE" "unavailable"
ui_stop
CLOSED="[$(ob_row c1 'fixture still open' '' s1),$(ob_row c2 'fixture done' '' s2 | sed 's/"state":"open"/"state":"closed"/')]"
ob_tree "$CLOSED"; ui_start closed --idle 120; CP="$(ob_panel "$(ui_get /)")"
t_has "a closed row is folded into a count" "$CP" "1 closed or abandoned"
t_eq "and is not in the open list" "fixture still open," "$(ob_titles "$(ob_view "$CP" none)")"
ui_stop
ui_mutant oempty 's/nothing listed/0/;s/No proposals\./0/' obligations.ts
t_eq "the empty-state mutant differs" changed "$UI_MUT"
ob_tree "[]"; ui_start moempty --idle 120
t_hasnt "without the empty-state text the same probe finds none" "$(ob_panel "$(ui_get /)")" "nothing listed"; ui_stop; UI_SCRIPT=""

t_section "proposals are shown, never applied: no button, no route (harbor#1052 is the seam)"
PROP='[{"id":"p1","obligation_id":"pr:acme/widgets#7","title":"fixture proposal","argv":["touch","'"$T_TMP"'/pwned"]}]'
ob_tree "" "" "$PROP"; ui_start prop --idle 120; PP="$(ui_get /)"; OPP="$(ob_panel "$PP")"
t_has "a proposal is listed as text" "$OPP" "fixture proposal"
t_has "against its obligation" "$OPP" "pr:acme/widgets#7"
t_hasnt "its command is not shown, so there is nothing to copy as if vetted" "$OPP" "pwned"
t_hasnt "no apply control exists" "$OPP" "data-apply"
t_eq "and no button in the proposals list" 0 "$(printf '%s' "$OPP" | sed 's/<h3>Proposals/\n&/' | tail -1 | grep -c '<button')"
R="$(ui_post '{"id":"p1"}')"; t_has "a proposal id is not in the allowlist" "$R" " 403"
R="$(ui_post '{"id":"obligations","argv":["touch","'"$T_TMP"'/pwned"],"apply":"p1"}')"; t_has "naming a proposal's argv beside a real id runs only the real panel" "$R" " 200"
t_eq "and nothing the request named was run" no "$([ -e "$T_TMP/pwned" ] && echo yes || echo no)"
t_eq "the server has no apply route" 404 "$(ui_code -X POST -H "Cookie: $UI_COOKIE" -H 'Content-Type: application/json' -d '{"id":"p1"}' "$UI_URL/apply")"
ui_stop
ui_mutant oprop 's/export const proposalActions = (_proposal: Record<string, any>): string => "";/export const proposalActions = (_proposal: Record<string, any>): string => `<button data-apply>apply<\/button>`;/' obligations.ts
t_eq "the seam mutant differs" changed "$UI_MUT"
ob_tree "" "" "$PROP"; ui_start moprop --idle 120
t_has "a button put through the seam is visible to the same probe" "$(ob_panel "$(ui_get /)")" "data-apply"; ui_stop; UI_SCRIPT=""
t_section "the tab runs the console's own script and never a PATH harbor, before and after the obligations PR (harbor#1113)"
# Before: bin/status-obligations.sh is absent. The PATH harbor below answers validly and counts its calls, so the old source would show a healthy tab.
ui_tree 0; rm -f "$UI_ROOT/bin/status-obligations.sh"; ui_start noscript --idle 120
NS="$(ui_get /)"; ui_post '{"id":"obligations"}' > /dev/null; NS2="$(ui_get /)"
t_has "with the script absent the panel says so" "$(ob_panel "$NS2")" "unavailable: bin/status-obligations.sh is not on this box"
t_eq "and the tile reads unavailable, never an empty list" 1 "$(printf '%s' "$NS2" | grep -o 'id="t-obligations"[^>]*><span class="label">Obligations</span><span class="value">unavailable<' | wc -l | tr -d ' ')"
t_hasnt "no table is drawn" "$(ob_panel "$NS2")" "<table"
t_eq "no process started: the PATH harbor was never called, on load or on a re-run" 0 "$(ui_calls harbor)"
ui_stop
ui_mutant pathharbor 's/argv: sh("status-obligations.sh", "show", "--json")/argv: ["harbor", "status", "obligations", "--json"]/' sources.ts
t_eq "the PATH-harbor mutant differs" changed "$UI_MUT"
ui_tree 0; rm -f "$UI_ROOT/bin/status-obligations.sh"; ui_start mpath --idle 120; ui_get / > /dev/null
t_eq "the old source starts the PATH harbor although the script is absent" 1 "$(ui_calls harbor)"
t_has "and shows a healthy tab for it" "$(ob_panel "$(ui_get /)")" "fixture open pr"; ui_stop; UI_SCRIPT=""
# After: the script is in the console's own tree. It runs from there, once per run, and the PATH harbor is still never called.
ui_tree 0; ui_start script --idle 120; ui_get / > /dev/null; ui_post '{"id":"obligations"}' > /dev/null
t_eq "with the script present it ran for the first load and the re-run" 2 "$(ui_calls status-obligations)"
t_eq "and the PATH harbor was never called" 0 "$(ui_calls harbor)"
t_has "the tab shows its rows" "$(ob_panel "$(ui_get /)")" "fixture open pr"
t_has "and names the script it ran" "$(ob_panel "$(ui_get /)")" "sh bin/status-obligations.sh show --json"
ui_stop

t_section "a hostile command cannot make the page huge: output, string, source, row and link caps (harbor#1113)"
big() { head -c "$1" /dev/zero | tr '\0' "$2"; }
size() { printf '%s' "$1" | wc -c | tr -d ' '; }
BIGROW='{"id":"b1","kind":"pr","subject":"s","repo":"r","owner":"o","title":"%s","link":"","opened_ts":"x","deadline_ts":"","state":"open","closed_by":"","closed_ts":"","age_s":1}'
OKSRC='{"a":{"ok":true,"reason":"","ts":"t"}}'
# one 1 MB title, rendered once per grouping
OB_ROWS="[$(printf "$BIGROW" "$(big 1000000 '<')")]"; ob_tree "$OB_ROWS"; OB_ROWS=""
ui_start bigstr --idle 120; BP="$(ui_get /)"
t_eq "a 1 MB title makes a small page, not 16 MB" yes "$([ "$(size "$BP")" -lt 300000 ] && echo yes || echo no)"
t_has "the title is cut, and says so" "$(ob_panel "$BP")" "&lt;&lt;&lt;…"
ui_stop
ui_mutant nostrcap 's/const MAX_STR = 200;/const MAX_STR = 100000000;/' obligations.ts
t_eq "the string-cap mutant differs" changed "$UI_MUT"
ob_tree "[$(printf "$BIGROW" "$(big 1000000 '<')")]"; ui_start mbigstr --idle 120
t_eq "without the cap the same title makes a page over 10 MB" yes "$([ "$(size "$(ui_get /)")" -gt 10000000 ] && echo yes || echo no)"; ui_stop; UI_SCRIPT=""
# a 9 MB answer is refused before it is parsed
printf '{"generated_ts":"t","sources":%s,"obligations":[{"id":"x","title":"%s","state":"open"}],"proposals":[]}' "$OKSRC" "$(big 9000000 x)" > "$T_TMP/huge.json"
ui_tree 0; ob_stub_file "$T_TMP/huge.json"; ui_start huge --idle 120; HP="$(ui_get /)"
t_has "an output over 8 MB is unavailable, with the reason" "$(ob_panel "$HP")" "unavailable: output is larger than 8 MB"
ui_stop
ui_mutant nobytecap 's/Buffer.byteLength(out) > OB_MAX_BYTES/false/' sources.ts
t_eq "the byte-cap mutant differs" changed "$UI_MUT"
ui_tree 0; ob_stub_file "$T_TMP/huge.json"; ui_start mhuge --idle 120
t_hasnt "without the byte cap the same output is parsed, not refused" "$(ob_panel "$(ui_get /)")" "output is larger than"; ui_stop; UI_SCRIPT=""
# 300 sources: the cap shows 50, and the one that is down is among them
SRC300="$(awk 'BEGIN { printf "{"; for (i = 1; i <= 300; i++) printf "%s\"s%d\":{\"ok\":%s,\"reason\":\"gone\",\"ts\":\"t\"}", (i > 1 ? "," : ""), i, (i == 300 ? "false" : "true"); printf "}" }')"
ob_tree "[]" "$SRC300"; ui_start src300 --idle 120; SP="$(ob_panel "$(ui_get /)")"
t_eq "300 sources render 50" 50 "$(printf '%s' "$SP" | grep -o '<li data-tone' | wc -l | tr -d ' ')"
t_has "the rest are counted, not dropped silently" "$SP" "250 more sources not shown"
t_has "a source that did not answer is shown even though it was the last" "$SP" "<code>s300</code> unavailable: gone"
ui_stop
ui_mutant nosrccap 's/const MAX_SOURCES = 50;/const MAX_SOURCES = 100000;/' obligations.ts
t_eq "the source-cap mutant differs" changed "$UI_MUT"
ob_tree "[]" "$SRC300"; ui_start msrc300 --idle 120
t_eq "without the cap every source is rendered" 300 "$(ob_panel "$(ui_get /)" | grep -o '<li data-tone' | wc -l | tr -d ' ')"; ui_stop; UI_SCRIPT=""
# 300 rows: 200 per grouping, and the page says it is a part
ROWS300="[$(awk 'BEGIN { for (i = 1; i <= 300; i++) printf "%s{\"id\":\"r%d\",\"kind\":\"pr\",\"subject\":\"s%d\",\"repo\":\"r\",\"owner\":\"o\",\"title\":\"fixture row %d\",\"link\":\"\",\"opened_ts\":\"x\",\"deadline_ts\":\"\",\"state\":\"open\",\"closed_by\":\"\",\"closed_ts\":\"\",\"age_s\":%d}", (i > 1 ? "," : ""), i, i, i, i }')]"
ob_tree "$ROWS300"; ui_start rows300 --idle 120; RPG="$(ui_get /)"; RP="$(ob_panel "$RPG")"
t_eq "300 rows render 200 in the flat view" 200 "$(ob_view "$RP" none | grep -o '<tr data-state' | wc -l | tr -d ' ')"
t_has "and the tab says it is the first 200 of 300" "$RP" "showing the first 200 of 300 listed"
ui_stop
ui_mutant norowcap 's/const MAX_ROWS = 200;/const MAX_ROWS = 100000;/' obligations.ts
t_eq "the row-cap mutant differs" changed "$UI_MUT"
ob_tree "$ROWS300"; ui_start mrows300 --idle 120
t_eq "without the cap every row is rendered" 300 "$(ob_view "$(ob_panel "$(ui_get /)")" none | grep -o '<tr data-state' | wc -l | tr -d ' ')"; ui_stop; UI_SCRIPT=""
# a 100 KB https link is not an href
ob_tree "[$(ob_row l1 'fixture longlink' "https://ok.example/$(big 100000 a)" s1)]"; ui_start lnklong --idle 120; LL="$(ob_panel "$(ui_get /)")"
t_eq "a link over 2 KB is not an anchor" 0 "$(printf '%s' "$LL" | grep -o '<a href=' | wc -l | tr -d ' ')"
t_has "the row still shows its subject" "$LL" "<td>s1</td>"
ui_stop
ui_mutant nolinkcap 's/link.length > MAX_LINK || //' obligations.ts
t_eq "the link-cap mutant differs" changed "$UI_MUT"
ob_tree "[$(ob_row l1 'fixture longlink' "https://ok.example/$(big 100000 a)" s1)]"; ui_start mlnklong --idle 120
t_eq "without the cap the same link is rendered, once per grouping" 4 "$(ob_panel "$(ui_get /)" | grep -o '<a href=' | wc -l | tr -d ' ')"; ui_stop; UI_SCRIPT=""

t_section "every other string the tab prints is escaped too: generated_ts, deadline, source ts, closed_by, closed_ts, state (harbor#1113)"
HR_LIVE='{"id":"e2","kind":"pr","subject":"s2","repo":"r","owner":"o","title":"t2","link":"","opened_ts":"x","deadline_ts":"<d>dl","state":"open","closed_by":"","closed_ts":"","age_s":1}'
HR_DONE='{"id":"e3","kind":"pr","subject":"s3","repo":"r","owner":"o","title":"t3","link":"","opened_ts":"x","deadline_ts":"","state":"closed","closed_by":"<cb>x","closed_ts":"<ct>y","age_s":1}'
HR_STATE='{"id":"e4","kind":"pr","subject":"s4","repo":"r","owner":"o","title":"t4","link":"","opened_ts":"x","deadline_ts":"","state":"open\" onmouseover=\"alert(1)","closed_by":"","closed_ts":"","age_s":1}'
HR_ROWS="[$HR_LIVE,$HR_DONE,$HR_STATE]"
HR_SRC='{"s1":{"ok":true,"reason":"","ts":"<t>src"}}'
hr_tree() { OB_GEN='<g>gen'; ob_tree "$HR_ROWS" "$HR_SRC"; OB_GEN=""; }
hr_tree; ui_start hostile --idle 120; HO="$(ob_panel "$(ui_get /)")"
t_has "generated_ts arrives as text" "$HO" 'datetime="&lt;g&gt;gen">&lt;g&gt;gen</time>'
t_has "deadline_ts arrives as text" "$HO" '&lt;d&gt;dl'
t_has "a source's ts arrives as text" "$HO" '&lt;t&gt;src'
t_has "closed_by arrives as text" "$HO" '&lt;cb&gt;x'
t_has "closed_ts arrives as text" "$HO" '&lt;ct&gt;y'
t_eq "and none of them survives as a tag" "" "$(printf '%s' "$HO" | grep -o '<\(g>gen\|d>dl\|t>src\|cb>x\|ct>y\)' | head -1)"
t_has "a row whose state is not a known one is not listed, and is counted" "$HO" "1 row with a state this tab does not know"
t_hasnt "so its attribute break appears nowhere" "$HO" "onmouseover"
ui_stop
for m in 'gen|s/[$]{esc(text(json.generated_ts))}/${text(json.generated_ts)}/g|<g>gen' \
         'deadline|s/esc(clip(typeof r.deadline_ts/(clip(typeof r.deadline_ts/|<d>dl' \
         'srcts|s/esc(clip(s.ts))/(clip(s.ts))/|<t>src' \
         'closedby|s/esc(text(r.closed_by))/(text(r.closed_by))/|<cb>x' \
         'closedts|s/esc(text(r.closed_ts))/(text(r.closed_ts))/|<ct>y'; do
  _n="${m%%|*}"; _r="${m#*|}"; _sed="${_r%|*}"; _probe="${_r##*|}"
  ui_mutant "esc-$_n" "$_sed" obligations.ts
  t_eq "the $_n mutant differs" changed "$UI_MUT"
  hr_tree; ui_start "mesc-$_n" --idle 120
  t_has "without esc() on $_n the same probe finds it live" "$(ob_panel "$(ui_get /)")" "$_probe"; ui_stop
done
# state is gated to open/overdue before it is printed, so the escape is the second line of defence: open the gate and it is the only one
ui_mutant gate 's/ACTIVE.has(r.state)/true/' obligations.ts
t_eq "the state-gate mutant differs" changed "$UI_MUT"
hr_tree; ui_start mgate --idle 120
t_has "with the gate open, data-state is still escaped" "$(ob_panel "$(ui_get /)")" 'data-state="open&quot; onmouseover=&quot;alert(1)"'; ui_stop
ui_mutant gatenoesc 's/ACTIVE.has(r.state)/true/;s/data-state="[$]{esc(text(r.state))}"/data-state="${text(r.state)}"/' obligations.ts
t_eq "the gate-and-escape mutant differs" changed "$UI_MUT"
hr_tree; ui_start mgate2 --idle 120
t_has "with both gone the same probe finds a live attribute break" "$(ob_panel "$(ui_get /)")" 'data-state="open" onmouseover="alert(1)"'; ui_stop; UI_SCRIPT=""
t_done
