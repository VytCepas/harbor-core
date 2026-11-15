#!/usr/bin/env sh
# access-chrome-mcp.ts (harbor#1507): click --text=<name> reads the ref from the guard snapshot and clicks it with every guard a
# ref click takes; and every call leaves one line in the per-call timings file. Against the fake daemon.
REQ_BUN="${HARBOR_TEST_REQUIRE_BUN:-0}"  # before t_init clears it
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/server-env.sh"
TF="$T_TMP/timings.tsv"
reseam() { jq "$1" "$X/bin/access-chrome-mcp.seams.json" > "$T_TMP/sj" && mv "$T_TMP/sj" "$X/bin/access-chrome-mcp.seams.json"; }

t_section "click --text=<name>: one match is clicked, by its ref, after the same guards"
clean; : > "$CALLS"
t_eq "an exact name is clicked" "exit 0" "$(mcp click --text=Payments)"
t_eq "...as the click script on its ref" 1 "$(n '^script click e13')"
t_has "...saying which element the name was" "$(txt)" '[--text=Payments is button "Payments" (e13)]'
t_eq "...after the guard snapshot (once to find it, once to check it)" 2 "$(n 'snapshot --boxes --filename=harbor-guard.yml')"
: > "$CALLS"
t_eq "a part of one name is enough when it is the only one" "exit 0" "$(mcp click '--text=data SOURCE')"
t_eq "...case and spacing aside" 1 "$(n '^script click e9')"
: > "$CALLS"
t_eq "two exact matches are refused" "exit 1" "$(mcp click --text=Create)"
t_has "...listing both with their refs" "$(txt)" 'button "Create" (e3); button "Create" (f2e3)'
t_has "...and not the partial match an exact one outranks" "$(txt)" "2 elements match"
t_has "...naming a ref click as the way on" "$(txt)" 'mcp__harbor_chrome__click with args ["<one of those refs>"]'
t_eq "...and clicking nothing" 0 "$(n '^script click\|^click ')"
t_eq "a destructive name is refused as a ref click is" "exit 1" "$(mcp click '--text=Delete campaign')"
t_has "...by the destructive-label guard, on the resolved ref" "$(txt)" "destructive click refused: 'button \"Delete campaign\"' (e4)"
t_eq "...and never clicked" 0 "$(n '^script click e4')"
t_eq "a name carrying a ref inside its quotes is the element's own ref" "exit 0" "$(mcp click --text=Spoof)"
t_eq "...e17, not the e4 written in its name" 1 "$(n '^script click e17')"
t_eq "a zero-size element is not a match" "exit 1" "$(mcp click --text=Hidden)"
t_has "...so the name matches nothing" "$(txt)" "no element on the page has that name"
t_has "...and find is the way on" "$(txt)" 'mcp__harbor_chrome__find with args ["Hidden"]'
t_eq "no match is refused" "exit 1" "$(mcp click --text=Nonexistent)"
t_eq "a ref and --text together are refused" "exit 1" "$(mcp click e3 --text=Payments)"
t_eq "two --text are refused" "exit 1" "$(mcp click --text=Payments --text=Save)"
t_eq "an empty --text is refused" "exit 1" "$(mcp click '--text=  ')"
t_eq "--text on fill is refused" "exit 1" "$(mcp fill --text=Payments x)"
: > "$CALLS"
t_eq "dblclick takes --text too" "exit 0" "$(mcp dblclick --text=Payments)"
t_eq "...by script" 1 "$(n '^script dblclick e13')"
: > "$CALLS"; mcp click --text=Payments --real >/dev/null
t_eq "--text with --real is the daemon's click on the ref" 1 "$(n '^click e13')"
: > "$CALLS"; mcp click --text=Payments right >/dev/null
t_eq "...and a button after --text goes with the ref" 1 "$(n '^click e13 right')"
# A page of eleven partial matches: the refusal lists ten and says there are more (review of harbor#1536).
cp "$SNAP" "$T_TMP/snap.keep"
{ echo '- generic [active] [ref=e1] [box=8,16,1264,800]:'
  for _r in 1 2 3 4 5 6 7 8 9 10 11; do echo "  - button \"Row $_r\" [ref=r$_r] [box=8,$((_r * 30)),80,20]"; done; } > "$SNAP"
: > "$CALLS"
t_eq "eleven matches are refused" "exit 1" "$(mcp click --text=Row)"
t_has "...counting all eleven" "$(txt)" "11 elements match"
t_has "...listing the tenth" "$(txt)" '(r10)'
t_hasnt "...but not the eleventh" "$(txt)" '(r11)'
t_has "...and saying the list is cut" "$(txt)" '; …'
cp "$T_TMP/snap.keep" "$SNAP"
_n200="$(printf '%200s' '' | tr ' ' 'x')"
t_eq "a 200-character name is taken (and matches nothing here)" "exit 1" "$(mcp click "--text=$_n200")"
t_has "...refused for no match, not for its length" "$(txt)" "no element on the page has that name"
t_eq "a 201-character name is refused" "exit 1" "$(mcp click "--text=x$_n200")"
t_has "...for its length" "$(txt)" "1..200 characters"
# The single-match line removed, a unique name must stop clicking: the arms above can fail.
mkdir -p "$T_TMP/mut3/bin" "$T_TMP/mut3/contracts"; cp "$X/bin/access-chrome-mcp.seams.json" "$X/bin/access-browser-agent.sh" "$X/bin/scope-roots.sh" "$T_TMP/mut3/bin/"; cp "$X/contracts/browser-agent-hosts.txt" "$X/contracts/browser-script.tsv" "$T_TMP/mut3/contracts/"
sed 's/^  if (pick.length === 1) return pick\[0\];/  if (false) return pick[0];/' "$SRV" > "$T_TMP/mut3/bin/access-chrome-mcp.ts"
t_eq "the mutant differs from the server" yes "$(cmp -s "$SRV" "$T_TMP/mut3/bin/access-chrome-mcp.ts" || echo yes)"
_old="$SRV"; SRV="$T_TMP/mut3/bin/access-chrome-mcp.ts"
t_eq "and without the single-match line a unique name clicks nothing" "exit 1" "$(mcp click --text=Payments)"
SRV="$_old"

t_section "per-call timings: one line per call, kept across sessions, no URL or argument"
clean; rm -f "$TF"
mcp click e3 >/dev/null; mcp goto https://business.facebook.com/secret-path-x >/dev/null; mcp click e4 >/dev/null
t_eq "three calls, three lines" 3 "$(wc -l < "$TF" | tr -d ' ')"
t_eq "every line has eight columns" 3 "$(awk -F'\t' 'NF == 8' "$TF" | wc -l | tr -d ' ')"
t_eq "...the session, the verb and ok" "claude-abc123def456 click ok" "$(head -1 "$TF" | cut -f2,3,8 | tr '\t' ' ')"
t_eq "a refused call is timed too, as an error" "click error" "$(tail -1 "$TF" | cut -f3,8 | tr '\t' ' ')"
t_eq "no URL reaches the file" 0 "$(grep -c 'secret-path-x\|business.facebook' "$TF" || :)"
t_eq "the times are whole milliseconds" 3 "$(awk -F'\t' '$4 ~ /^[0-9]+$/ && $5 ~ /^[0-9]+$/ && $6 ~ /^[0-9]+$/ && $7 ~ /^[0-9]+$/' "$TF" | wc -l | tr -d ' ')"
rm -f "$TF"
rpc "$(jq -cn '{jsonrpc:"2.0",id:1,method:"tools/call",params:{name:"steps",arguments:{steps:[{verb:"tab_list"},{verb:"snapshot"}]}}}')" >/dev/null
t_eq "steps leaves a line per step and none for the whole, so no step is counted twice" "steps/tab-list steps/snapshot" "$(cut -f3 "$TF" | tr '\n' ' ' | sed 's/ $//')"
mcp tabs >/dev/null
t_eq "a verb run by the shell agent is timed as well" tabs "$(tail -1 "$TF" | cut -f3)"
reseam '.timingsMax = 100 | .timingsKeep = 2'
for _i in 1 2 3 4 5 6; do mcp tab_list >/dev/null; done
t_eq "past its size the file is cut to its newest lines" yes "$([ "$(wc -l < "$TF")" -le 3 ] && echo yes)"
reseam '.timingsFile = "/dev/null/no/such/dir/t.tsv"'
t_eq "a timings file that cannot be written never fails a call" "exit 0" "$(mcp click e3)"
seams 0

t_done
