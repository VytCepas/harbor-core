#!/usr/bin/env sh
# access-chrome-mcp.ts (harbor#1507): the script-first verbs (click, dblclick, hover, check, uncheck, select, scroll) run a fixed
# script from contracts/browser-script.tsv after the guard snapshot; --real is the daemon's own verb. Against the fake daemon.
REQ_BUN="${HARBOR_TEST_REQUIRE_BUN:-0}"  # before t_init clears it
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/server-env.sh"
t_section "script-first: the scripted verbs run a fixed script; --real is the daemon's own verb (harbor#1507)"
clean; : > "$CALLS"
t_eq "a click runs by script" "exit 0" "$(mcp click e3)"
t_has "saying so, with the page URL" "$(txt)" "click done by script"
t_eq "as the click script on the ref, raw" 1 "$(n '^script click e3 \[raw\]')"
t_eq "never the daemon's click" 0 "$(n '^click e3')"
: > "$CALLS"
t_eq "click --real is the daemon's click" "exit 0" "$(mcp click e3 --real)"
t_eq "...once" 1 "$(n '^click e3')"
t_eq "...with no script" 0 "$(n '^script ')"
t_eq "...and no --real reaching the daemon" 0 "$(n ' --real')"
: > "$CALLS"; mcp click e3 right >/dev/null
t_eq "a right click is the daemon's (a script press is the left button)" 1 "$(n '^click e3 right')"
: > "$CALLS"; mcp click e3 --modifiers=Shift >/dev/null
t_eq "a click with modifiers is the daemon's" 1 "$(n '^click e3')"
: > "$CALLS"
t_eq "check runs the check script with true" "exit 0" "$(mcp check e3)"
t_eq "...on the ref" 1 "$(n '^script check e3 arg=true')"
t_eq "uncheck runs the same script with false" 1 "$(mcp uncheck e3 >/dev/null; n '^script check e3 arg=false')"
t_eq "hover runs by script" 1 "$(mcp hover e3 >/dev/null; n '^script hover e3')"
t_eq "dblclick runs by script" 1 "$(mcp dblclick e3 >/dev/null; n '^script dblclick e3')"
mcp select e3 'Lietuva' 'a"b' >/dev/null
t_eq "select passes its values as one JSON literal, quotes escaped" 1 "$(n '^script select e3 arg=\["Lietuva","a\\"b"\]')"
t_eq "select with no value is refused" "exit 1" "$(mcp select e3)"
t_eq "check with a second argument is refused" "exit 1" "$(mcp check e3 e4)"
: > "$CALLS"
t_eq "scroll by pixels runs on the page" "exit 0" "$(mcp scroll 800)"
t_eq "...with the pixels as its literal, and no ref" 1 "$(n '^script scroll arg=800 \[raw\]')"
t_eq "...and no guard snapshot (no ref, no label)" 0 "$(n 'harbor-guard.yml')"
t_eq "scroll up is a negative number" 1 "$(mcp scroll -400 >/dev/null; n '^script scroll arg=-400')"
t_eq "scroll a ref into view passes null" 1 "$(mcp scroll e3 >/dev/null; n '^script scroll e3 arg=null')"
t_eq "scroll an element by pixels" 1 "$(mcp scroll 300 e3 >/dev/null; n '^script scroll e3 arg=300')"
t_eq "scroll with two numbers is refused" "exit 1" "$(mcp scroll 1 2)"
t_eq "scroll with a selector is refused" "exit 1" "$(mcp scroll 'text=Delete')"
t_eq "scroll with nothing is refused" "exit 1" "$(mcp scroll)"
t_eq "--real on scroll is refused" "exit 1" "$(mcp scroll 800 --real)"
t_eq "--real on fill is refused" "exit 1" "$(mcp fill e9 x --real)"
: > "$CALLS"
t_eq "a destructive label is refused on hover too" "exit 1" "$(mcp hover e4)"
t_eq "and on check" "exit 1" "$(mcp check e4)"
t_eq "neither ran a script" 0 "$(n '^script ')"
printf 'refused: the element is disabled' > "$CTL/script_result"
t_eq "a script that refuses is refused" "exit 1" "$(mcp click e3)"
t_has "in the script's words" "$(txt)" "click e3 by script: refused: the element is disabled"
t_has "naming --real as the way on" "$(txt)" "harbor chrome click e3 --real"
printf 'unchanged: the page left it at false' > "$CTL/script_result"
t_eq "a check the page did not take is refused" "exit 1" "$(mcp check e3)"
t_has "saying the page left it" "$(txt)" "unchanged: the page left it at false"
clean; : > "$CTL/fail_script"
t_eq "a script the daemon could not run is an error" "exit 1" "$(mcp click e3)"
clean; printf 'https://accounts.google.com/signin' > "$CTL/page_url"
t_eq "a script click that lands on sign-in is refused as signed out" "exit 1" "$(mcp click e3)"
t_has "naming the sign-in" "$(txt)" "signed out"
clean
# The scripted dispatch removed, a click must reach the daemon's own verb: the arms above can fail.
mkdir -p "$T_TMP/mut2/bin" "$T_TMP/mut2/contracts"; cp "$X/bin/access-chrome-mcp.seams.json" "$X/bin/access-browser-agent.sh" "$X/bin/scope-roots.sh" "$T_TMP/mut2/bin/"; cp "$X/contracts/browser-agent-hosts.txt" "$X/contracts/browser-script.tsv" "$T_TMP/mut2/contracts/"
sed 's/^  if (SCRIPTED.has(verb) \&\& !real .*/  if (false) return null as never;/' "$SRV" > "$T_TMP/mut2/bin/access-chrome-mcp.ts"
t_eq "the mutant differs from the server" yes "$(cmp -s "$SRV" "$T_TMP/mut2/bin/access-chrome-mcp.ts" || echo yes)"
_old="$SRV"; SRV="$T_TMP/mut2/bin/access-chrome-mcp.ts"; : > "$CALLS"; mcp click e3 >/dev/null
t_eq "and without the scripted dispatch the click is the daemon's" 1 "$(n '^click e3')"
SRV="$_old"

t_done
