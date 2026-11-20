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
t_eq "--text on fill does not match a button" "exit 1" "$(mcp fill --text=Payments x)"
t_has "...naming the roles fill takes" "$(txt)" "no textbox, searchbox, combobox, spinbutton on the page has that name"
t_eq "--text on press is refused" "exit 1" "$(mcp press --text=Payments)"
t_has "...naming the verbs that take it" "$(txt)" "--text= is for click, dblclick, hover, text, fill, select, check, uncheck"
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
mkdir -p "$T_TMP/mut3/bin" "$T_TMP/mut3/contracts"; cp "$X/bin/access-chrome-mcp.seams.json" "$X/bin/access-browser-agent.sh" "$X/bin/scope-roots.sh" "$T_TMP/mut3/bin/"; cp "$X/contracts/browser-agent-hosts.txt" "$X/contracts/browser-script.tsv" "$X/contracts/live-change-words.txt" "$T_TMP/mut3/contracts/"
_old="$SRV"; SRV="$T_TMP/mut3/bin/access-chrome-mcp.ts"; cp "$_old" "$SRV"
# The control: the unchanged server in the mutant's directory clicks, so the red below is the mutation's (it once lacked
# live-change-words.txt, and every click there was refused whatever the mutant did).
t_eq "the unchanged server in the mutant's directory clicks the unique name" "exit 0" "$(mcp click --text=Payments)"
sed 's/^  if (pick.length === 1) return pick\[0\];/  if (false) return pick[0];/' "$_old" > "$SRV"
t_eq "the mutant differs from the server" yes "$(cmp -s "$_old" "$SRV" || echo yes)"
t_eq "and without the single-match line a unique name clicks nothing" "exit 1" "$(mcp click --text=Payments)"
SRV="$_old"

t_section "--text=<name> on the field verbs: only the roles each acts on, then every guard a ref call takes"
# A form whose labels repeat across roles: a heading and a textbox are both "Email", a checkbox and a button "Remember me".
cp "$SNAP" "$T_TMP/snap.keep"
cat > "$SNAP" <<'EOF'
- generic [active] [ref=e1] [box=8,16,1264,800]:
  - heading "Email" [level=2] [ref=e30] [box=8,16,200,20]
  - textbox "Email" [ref=e31] [box=8,40,200,20]
  - combobox "Country" [ref=e32] [box=8,70,200,20]
  - checkbox "Remember me" [ref=e33] [box=8,100,20,20]
  - button "Remember me" [ref=e34] [box=40,100,80,20]
  - radio "Monthly" [ref=e35] [box=8,130,20,20]
  - textbox "Name" [ref=e36] [box=8,160,200,20]
  - textbox "Name on card" [ref=e37] [box=8,190,200,20]
  - button "Continue" [ref=e38] [box=8,220,80,20]
EOF
clean; : > "$CALLS"
t_eq "fill --text fills the textbox, not the heading of the same name" "exit 0" "$(mcp fill --text=Email ann@example.com)"
t_eq "...on its ref, with the text" 1 "$(n '^fill e31 ann@example.com')"
t_has "...saying which field the name was" "$(txt)" '[--text=Email is textbox "Email" (e31)]'
: > "$CALLS"; mcp fill --text=Name Ann >/dev/null
t_eq "an exact field name outranks a longer one" 1 "$(n '^fill e36 Ann')"
t_eq "fill --text with no text is refused" "exit 1" "$(mcp fill --text=Email)"
t_has "...saying it takes the text to fill" "$(txt)" "exactly 1 other argument, the text to fill"
: > "$CALLS"
t_eq "fill --text beside a ref is refused" "exit 1" "$(mcp fill --text=Email e31 x)"
t_eq "...and fills nothing" 0 "$(n '^fill ')"
: > "$CALLS"
t_eq "check --text checks the checkbox, not the button of the same name" "exit 0" "$(mcp check '--text=Remember me')"
t_eq "...by the check script on e33" 1 "$(n '^script check e33')"
t_eq "uncheck --text takes no radio" "exit 1" "$(mcp uncheck --text=Monthly)"
: > "$CALLS"
t_eq "select --text picks the combobox" "exit 0" "$(mcp select --text=Country DE)"
t_eq "...by the select script on e32" 1 "$(n '^script select e32')"
: > "$CALLS"
t_eq "hover --text takes any named element" "exit 0" "$(mcp hover --text=Continue)"
t_eq "...by the hover script on e38" 1 "$(n '^script hover e38')"
t_eq "text --text with two exact matches is refused" "exit 1" "$(mcp text --text=Email)"
t_has "...listing both" "$(txt)" 'heading "Email" (e30); textbox "Email" (e31)'
: > "$CALLS"
echo 'Delete campaign' > "$CTL/submit_label"
t_eq "fill --text --submit that would commit a live change is refused" "exit 1" "$(mcp fill --text=Email x --submit)"
t_has "...by the submit guard, on the resolved ref" "$(txt)" "would commit 'Delete campaign'"
t_eq "...and fills nothing" 0 "$(n '^fill ')"
rm -f "$CTL/submit_label"
: > "$CALLS"
_steps="$(rpc "$(jq -cn '{jsonrpc:"2.0",id:1,method:"tools/call",params:{name:"steps",arguments:{steps:[{verb:"goto",args:["https://business.facebook.com/x"]},{verb:"fill",args:["--text=Email","ann@example.com"]},{verb:"check",args:["--text=Remember me"]},{verb:"click",args:["--text=Continue"]}]}}}')")"
t_eq "one steps call opens a page, fills it and submits it with no snapshot call" false "$(printf '%s' "$_steps" | jq -r '.result.isError')"
t_eq "...every step reached the page" "1 1 1 1" "$(n '^goto ') $(n '^fill e31') $(n '^script check e33') $(n '^script click e38')"
# The role filter removed, the heading named Email is a candidate again: the first arm above can fail.
mkdir -p "$T_TMP/mut4/bin" "$T_TMP/mut4/contracts"; cp "$X/bin/access-chrome-mcp.seams.json" "$X/bin/access-browser-agent.sh" "$X/bin/scope-roots.sh" "$T_TMP/mut4/bin/"; cp "$X/contracts/browser-agent-hosts.txt" "$X/contracts/browser-script.tsv" "$X/contracts/live-change-words.txt" "$T_TMP/mut4/contracts/"
_old="$SRV"; SRV="$T_TMP/mut4/bin/access-chrome-mcp.ts"; cp "$_old" "$SRV"
t_eq "the unchanged server in the mutant's directory fills the Email field" "exit 0" "$(mcp fill --text=Email x)"
sed 's/if (!m || (roles \&\& !roles.has(m\[1\]))) continue;/if (!m) continue;/' "$_old" > "$SRV"
t_eq "the role-filter mutant differs from the server" yes "$(cmp -s "$_old" "$SRV" || echo yes)"
t_eq "and without the role filter fill --text=Email is two matches" "exit 1" "$(mcp fill --text=Email x)"
SRV="$_old"
cp "$T_TMP/snap.keep" "$SNAP"

t_section "api first, enforced (2026-11-20): a vendor UI whose card ranks an api first is refused unless --ui= says why"
AD="$T_TMP/access"; mkdir -p "$AD" "$X/context-rules/user"; cp "$T_ROOT/context-rules/user/browser-last-tier.sh" "$X/context-rules/user/"
printf 'identity: a fixture card\nui-hosts: ads.reddit.com\nvia: api > browser\nuse: reddit-api campaigns list. Then the rest.\n' > "$AD/reddit.md"
reseam ".scopeEnv.ACCESS_DIR = \"$AD\""
clean; : > "$CALLS"
t_eq "goto a vendor UI whose card ranks an api first is refused" "exit 1" "$(mcp goto https://ads.reddit.com/x)"
t_has "...naming the tier and the card's first move" "$(txt)" "api first: reddit is reached at tier api"
t_has "...and the --ui= way" "$(txt)" '"--ui=<why the UI and not the api>"'
t_eq "...and the page is never opened" 0 "$(n '^goto ')"
t_eq "with --ui=<why> it opens" "exit 0" "$(mcp goto https://ads.reddit.com/x '--ui=the pixel screen has no api')"
t_eq "...the daemon getting the url alone" 1 "$(n '^goto https://ads.reddit.com/x$')"
t_has "...and the reason is kept" "$(cat "$WD/.ui-reasons.tsv")" "reddit	ads.reddit.com	the pixel screen has no api"
t_eq "--ui= on another verb is refused" "exit 1" "$(mcp click e3 '--ui=because i say so')"
t_eq "a host no card maps is not held" "exit 0" "$(mcp goto https://business.facebook.com/x)"
_st="$(rpc "$(jq -cn '{jsonrpc:"2.0",id:1,method:"tools/call",params:{name:"steps",arguments:{steps:[{verb:"goto",args:["https://ads.reddit.com/x"]},{verb:"snapshot"}]}}}')")"
t_eq "a goto step inside steps is held the same way" true "$(printf '%s' "$_st" | jq -r '.result.isError')"
t_has "...and stops there" "$(printf '%s' "$_st" | jq -r '.result.content[0].text')" "stopped at step 1 of 2"
t_eq "attach --operator is refused" "exit 1" "$(mcp attach --operator)"
t_has "...naming the agent Chrome instead" "$(txt)" "agents never drive the operator's own Chrome"
t_hasnt "...and never reaches the shell agent" "$(txt)" "arg=--operator"
mcp status >/dev/null
t_has "an agent verb tells the shell agent the call is an agent's" "$(txt)" "enforce=1"
# The match ignored, the vendor UI opens unasked: the first arm can fail.
mkdir -p "$T_TMP/mut5/bin" "$T_TMP/mut5/contracts" "$T_TMP/mut5/context-rules/user"
cp "$X/bin/access-chrome-mcp.seams.json" "$X/bin/access-browser-agent.sh" "$X/bin/scope-roots.sh" "$X/bin/library-log.sh" "$T_TMP/mut5/bin/"; cp "$X/contracts/"* "$T_TMP/mut5/contracts/"
cp "$X/context-rules/user/browser-last-tier.sh" "$T_TMP/mut5/context-rules/user/"
_old="$SRV"; SRV="$T_TMP/mut5/bin/access-chrome-mcp.ts"; cp "$_old" "$SRV"
t_eq "the unchanged server in the mutant's directory refuses the vendor UI" "exit 1" "$(mcp goto https://ads.reddit.com/x)"
sed 's/^  if (!card || !tier) return;$/  return;/' "$_old" > "$SRV"
t_eq "the api-first mutant differs from the server" yes "$(cmp -s "$_old" "$SRV" || echo yes)"
t_eq "and without the check the vendor UI opens" "exit 0" "$(mcp goto https://ads.reddit.com/x)"
SRV="$_old"
reseam 'del(.scopeEnv.ACCESS_DIR)'

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
