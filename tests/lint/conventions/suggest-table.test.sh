#!/usr/bin/env sh
# lint.suggest-table (harbor#1485): every refusal of bin/lint-suggest-table.sh goes red on its own row, the shipped table and the fixture
# are clean, and the rule in lint-conventions turns a bad table into a finding. Red first, then green.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
CHECK="$T_ROOT/bin/lint-suggest-table.sh"; RP="$T_TMP/table"
HDR='id	kind	tools	word	recogniser	quiet	line	switch_to	safe	install	requires	source'
L='A plain line for the test.'
chk() { { printf '%s\n' "$HDR"; printf '%s\n' "$1"; } > "$RP.tsv"; sh "$CHECK" "$RP.tsv" 2>&1; }
refused() { # <label> <row> <reason text>
  _o="$(chk "$2")"; t_has "refused: $1" "$_o" "$3"
}
clean() { t_eq "clean: $1" 0 "$(chk "$2" | /usr/bin/grep -c 'FAIL:')"; }

t_section "a row must have something distinctive (decision 24)"
refused "any WebSearch row" "w	tool	WebSearch	-	^WebSearch	-	$L	-	no	-	-	core" 'WebSearch'
refused "a generic tool" "w	tool	WebFetch	-	^WebFetch	-	$L	-	no	-	-	core" 'generic'
refused "a generic read" "w	tool	Read	-	^Read md project	-	$L	-	no	-	-	core" 'generic'
refused "a bare extension" "w	tool	Write	-	^Write md	-	$L	-	no	-	-	core" 'bare extension'
refused "a connector beside a bare write" "w	tool	mcp__a__b|Write	-	^.* md	-	$L	-	no	-	-	core" 'bare extension'
refused "a regex for a tool name" "w	tool	mcp__a__.*	-	^mcp__a	-	$L	-	no	-	-	core" 'not a plain tool name'
refused "a Bash row that matches anything" "w	verb	Bash	gh	^.*gh	-	$L	-	no	-	-	core" 'does not name a command'
clean "a specific connector" "w	tool	mcp__a__b	-	^mcp__a__b 	-	$L	-	no	-	-	core"
clean "a write plus a place word" "w	tool	Write|Edit	-	^(Write|Edit) md deliverables$	-	$L	-	no	-	-	core"
clean "a specific command" "w	verb	Bash	gh	^gh pr checks	-	$L	-	no	-	-	core"

t_section "a Bash recogniser is anchored on every branch"
refused "no anchor" "w	verb	Bash	gh	gh pr	-	$L	-	no	-	-	core" 'not anchored'
refused "a second branch with none" "w	verb	Bash	gh	^gh pr|checks	-	$L	-	no	-	-	core" 'not anchored'
clean "a group" "w	verb	Bash	gh	^gh (pr|run) view	-	$L	-	no	-	-	core"
clean "a bar in a bracket" "w	verb	Bash	gh	^gh [|]x	-	$L	-	no	-	-	core"
clean "two anchored branches" "w	verb	Bash	gh	^gh pr|^gh run	-	$L	-	no	-	-	core"
refused "Bash beside another tool" "w	verb	Bash|Write	gh	^gh	-	$L	-	no	-	-	core" 'names Bash alone'
refused "no word on a Bash row" "w	verb	Bash	-	^gh	-	$L	-	no	-	-	core" 'literal word'
refused "a word the recogniser never holds" "w	verb	Bash	glab	^gh pr	-	$L	-	no	-	-	core" 'word is not in the recogniser'
refused "a word on a connector row" "w	tool	mcp__a__b	gh	^mcp__a__b 	-	$L	-	no	-	-	core" 'only a Bash row has a word'
refused "an ERE that does not compile" "w	verb	Bash	gh	^gh (	-	$L	-	no	-	-	core" 'does not compile'
refused "a quiet ERE that does not compile" "w	verb	Bash	gh	^gh	x(	$L	-	no	-	-	core" 'does not compile'
refused "a class one grep has and another does not" "w	verb	Bash	gh	^gh\\spr	-	$L	-	no	-	-	core" 'backslash class'

t_section "safe, mods and trust"
refused "a safe mod" "w	mod	mcp__a__b	-	^mcp__a__b 	-	$L	panel	yes	route	-	core" 'a mod row cannot be safe'
refused "a mod with no route" "w	mod	mcp__a__b	-	^mcp__a__b 	-	$L	panel	no	-	-	core" 'needs install'
refused "install on another kind" "w	verb	Bash	gh	^gh	-	$L	-	no	route	-	core" 'only a mod row has install'
refused "safe with no tool" "w	verb	Bash	gh	^gh	-	$L	-	yes	-	-	core" 'needs a switch_to'
refused "safe outside core" "w	verb	Bash	gh	^gh	-	$L	x	yes	-	-	acme-pack" 'only a core row can be safe'
refused "a sentence in switch_to" "w	verb	Bash	gh	^gh	-	$L	please run this tool now ok	no	-	-	core" 'is a sentence'
refused "shell in switch_to" "w	verb	Bash	gh	^gh	-	$L	x; rm	no	-	-	core" 'cannot'
refused "a skill row with no skill" "w	skill	Bash	gh	^gh	-	$L	-	no	-	-	core" 'skill name'
refused "requires outside the tokens" "w	verb	Bash	gh	^gh	-	$L	-	no	-	/usr/bin/x	core" 'requires is not'
refused "requires with a parent step" "w	verb	Bash	gh	^gh	-	$L	-	no	-	@CFG@/../x	core" 'requires is not'
clean "requires under the config dir" "w	verb	Bash	gh	^gh	-	$L	-	no	-	@CFG@/skills/x/SKILL.md	core"
clean "requires under home" "w	verb	Bash	gh	^gh	-	$L	-	no	-	@HOME@/.local/bin/x	core"

t_section "the shape of a row"
refused "a short row" "w	verb	Bash" '3 cells'
refused "an empty cell" "w	verb	Bash	gh	^gh		$L	-	no	-	-	core" 'a cell is empty'
refused "a bad id" "Bad_Id	verb	Bash	gh	^gh	-	$L	-	no	-	-	core" 'the id is not'
refused "an id past 27" "aaaaaaaaaaaaaaaaaaaaaaaaaaaa	verb	Bash	gh	^gh	-	$L	-	no	-	-	core" 'the id is not'
refused "a source that is no pack id" "w	verb	Bash	gh	^gh	-	$L	-	no	-	-	Acme Pack" 'the source is not'
refused "no person line" "w	verb	Bash	gh	^gh	-	-	-	no	-	-	core" 'the person line is empty'
refused "a kind outside the list" "w	job	Bash	gh	^gh	-	$L	-	no	-	-	core" 'the kind is not'
refused "safe outside yes and no" "w	verb	Bash	gh	^gh	-	$L	-	maybe	-	-	core" 'safe is not'
_o="$(chk "w	verb	Bash	gh	^gh	-	$L	-	no	-	-	core
w	verb	Bash	gh	^gh	-	$L	-	no	-	-	core")"
t_has "refused: a repeated id" "$_o" 'repeated'
printf 'id\tkind\n' > "$RP.tsv"; t_has "refused: another header" "$(sh "$CHECK" "$RP.tsv" 2>&1)" 'not the contract header'
t_has "refused: a table that is not there" "$(sh "$CHECK" "$RP.absent" 2>&1)" 'no such table'

t_section "the person's line"
refused "a backtick" 'w	verb	Bash	gh	^gh	-	Use the `tool` here.	-	no	-	-	core' 'backtick'
refused "a path" "w	verb	Bash	gh	^gh	-	Look in docs/reports for this.	-	no	-	-	core" 'holds a path'
refused "a home path" "w	verb	Bash	gh	^gh	-	Look in ~/notes for this.	-	no	-	-	core" 'holds a path'
refused "a script name" "w	verb	Bash	gh	^gh	-	Try report.sh for this.	-	no	-	-	core" 'path or a flag'
refused "a flag" "w	verb	Bash	gh	^gh	-	Add --watch to this.	-	no	-	-	core" 'path or a flag'
refused "a command word" "w	verb	Bash	gh	^gh	-	The git way is slower.	-	no	-	-	core" 'command word: git'
refused "the row's own word" "w	verb	Bash	fixturectl	^fixturectl	-	The fixturectl way is slower.	-	no	-	-	core" 'command word: fixturectl'
refused "the tool it switches to" "w	verb	Bash	gh	^gh	-	Use tidy-report instead.	tidy-report	no	-	-	core" 'command word: tidy-report'
refused "too many words" "w	verb	Bash	gh	^gh	-	one two three four five six seven eight nine ten one two three four five six seven eight nine ten one two three four five six	-	no	-	-	core" 'the limit is 25'
refused "a sentinel" "w	verb	Bash	gh	^gh	-	HARBOR-DECISION deny: no.	-	no	-	-	core" 'like a sentinel'
refused "/status-pane outside an intro" "w	verb	Bash	gh	^gh	-	Open /status-pane for this.	-	no	-	-	core" 'holds a path'
refused "another slash token in an intro" "w	intro	-	-	-	-	Open /status-panel for this.	-	no	-	-	core" 'holds a path'
clean "/status-pane in an intro" "w	intro	-	-	-	-	Open /status-pane and press Scan.	-	no	-	-	core"
clean "English that looks like a tool" "w	verb	Bash	gh	^gh	-	Harbor can find, sort and watch this for you.	-	no	-	-	core"

t_section "an intro row"
refused "tools - on another kind" "w	verb	-	-	-	-	$L	-	no	-	-	core" 'only for kind=intro'
refused "an intro with a tool" "w	intro	mcp__a__b	-	-	-	$L	-	no	-	-	core" 'an intro row has -'
refused "a safe intro" "w	intro	-	-	-	-	$L	x	yes	-	-	core" 'an intro row is safe=no'

t_section "the shipped table and the fixture"
t_eq "the shipped table is clean" 'suggest-table: 0 ok, 0 failed, 0 warnings' "$(sh "$CHECK" "$T_ROOT/context-rules/user/suggest-tool.tsv" 2>&1)"
t_eq "the fixture is clean" 'suggest-table: 0 ok, 0 failed, 0 warnings' "$(sh "$CHECK" "$T_ROOT/fixtures/injection-rule/suggest-tool.tsv" 2>&1)"
t_eq "the shipped table has a header and no rows" 1 "$(awk 'NF' "$T_ROOT/context-rules/user/suggest-tool.tsv" | wc -l | tr -d ' ')"
t_exit "clean exits 0" 0 sh "$CHECK" "$T_ROOT/fixtures/injection-rule/suggest-tool.tsv"
chk "w	verb	Bash	gh	gh	-	$L	-	no	-	-	core" >/dev/null
t_exit "a finding exits 1" 1 sh "$CHECK" "$RP.tsv"
t_exit "no table named exits 2" 2 sh "$CHECK"

t_section "the rule: a bad table is a finding at the row's mode"
reg() { printf 'id\tmode\ttype\tengine\tsurfaces\tmoment\tfunction\tstability\tsuccessor\towner\tred_proof\temitted\ttitle\nlint.suggest-table\t%s\tlint\tbin/lint-conventions.sh\t-\tci\tdetective\texperimental\t-\tlint\t-\t-\tfixture\n' "$1" > "$RP.reg"; }
runr() { reg "$1"; HARBOR_LINT_CONTROLS="$RP.reg" HARBOR_SCOPE_ROOT="$2" sh "$LINT" --only lint.suggest-table 2>&1; printf 'exit=%s\n' "$?"; }
fx() { rm -rf "$1"; mkdir -p "$1/context-rules/user" "$1/fixtures/injection-rule"
  printf '%s\n' "$HDR" > "$1/fixtures/injection-rule/suggest-tool.tsv"
  { printf '%s\n' "$HDR"; [ -z "$2" ] || printf '%s\n' "$2"; } > "$1/context-rules/user/suggest-tool.tsv"; }
fx "$RP.a" "w	mod	mcp__a__b	-	^mcp__a__b 	-	$L	panel	yes	route	-	core"
_o="$(runr block "$RP.a")"
t_has "block: the finding fails the run" "$_o" 'VIOLATION [lint.suggest-table]'
t_has "block: it names the row and the reason" "$_o" 'w: a mod row cannot be safe'
t_has "block: exit 1" "$_o" 'exit=1'
_o="$(runr warn "$RP.a")"
t_has "warn: an advisory" "$_o" 'ADVISORY [lint.suggest-table]'
t_has "warn: exit 0" "$_o" 'exit=0'
fx "$RP.b" ''
_o="$(runr block "$RP.b")"
t_hasnt "a clean tree has no finding" "$_o" '[lint.suggest-table]'
t_has "a clean tree exits 0" "$_o" 'exit=0'
rm -f "$RP.b/fixtures/injection-rule/suggest-tool.tsv" "$RP.b/context-rules/user/suggest-tool.tsv"
_o="$(runr block "$RP.b")"
t_has "a tree with no table says it compared nothing" "$_o" 'ADVISORY [lint.suggest-table]'
t_has "and does not fail" "$_o" 'exit=0'
t_red lint.suggest-table
t_done
