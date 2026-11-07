#!/usr/bin/env sh
# scan.test.sh (harbor#1485) — bin/status-suggest-scan.sh: repeated work across sessions, from fixture transcripts under a throwaway config dir.
# A candidate is a closed-vocabulary shape in 3+ sessions. Input is every tool call, so a session with no Bash and a repeated
# connector task yields one. A seeded fake secret, path and client-like name ride in every fixture call and must never come out.
# Ids in stopped.tsv go before the cap of 3. Nothing is written: not the store, not the state folder, not a temp file.
. "$(dirname "$0")/../../lib/core.sh"; t_init
SCAN="$T_ROOT/bin/status-suggest-scan.sh"
CFG="$T_TMP/ucfg"; ST="$T_TMP/state"; mkdir -p "$CFG/projects/-fx" "$ST"
NOW="$(jq -n -r 'now | todate')"; OLD="$(jq -n -r '(now - 3456000) | todate')"
SEC='sk-FAKESECRET0123456789'; CLI='AcmeBigClient'; PTH='/Users/zed/clients/AcmeBigClient'
n=0
# call <name> <input-json>: one tool_use block
call() { printf '{"type":"tool_use","id":"@ID@","name":"%s","input":%s}' "$1" "$2"; }
# sess <file> <ts> <side> <block>...: one session file, one assistant record per block
sess() { _f="$CFG/projects/-fx/$1.jsonl"; _ts="$2"; _sd="$3"; shift 3
  for _b in "$@"; do n=$((n+1)); _b="$(printf '%s' "$_b" | sed "s/@ID@/i$n/")"; printf '{"type":"assistant","timestamp":"%s","isSidechain":%s,"message":{"content":[%s]}}\n' "$_ts" "$_sd" "$_b" >> "$_f"; done; }
# sess numbers the @ID@ of every block, so no two calls share an id and none is mistaken for a resumed copy.
mcp()  { call "mcp__${CLI}_Flow__$1" "{\"client\":\"$CLI\",\"token\":\"$SEC\"}"; }
wr()   { call Write "{\"file_path\":\"$PTH/$1\",\"content\":\"$SEC\"}"; }
ed()   { call Edit "{\"file_path\":\"$PTH/$1\",\"old_string\":\"$SEC\",\"new_string\":\"x\"}"; }
sh_()  { call Bash "{\"command\":$(jq -n --arg c "$1" '$c')}"; }
rd()   { call Read "{\"file_path\":\"$PTH/a.txt\"}"; }
web()  { call WebSearch "{\"query\":\"$CLI $SEC\"}"; }
scan() { (cd "$T_TMP" && HARBOR_STATUS_SUGGEST_DIR="$ST" sh "$SCAN" "$@"); }
tree() { find "$CFG" "$ST" "$T_TMP/tmp" "$T_TMP/home" -type f 2>/dev/null | sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(cksum < "$f")"; done; }
reset() { rm -rf "$CFG/projects/-fx"; mkdir -p "$CFG/projects/-fx"; rm -f "$ST/stopped.tsv"; }
cands() { scan --json --dir "$CFG" | jq -r -c ".candidates | ${1:-.}"; }
unset CLAUDE_CONFIG_DIR

t_section "1 - the shape of the output, and a session with no Bash and a repeated connector task"
for i in 1 2 3 4; do sess "c$i" "$NOW" false "$(mcp get_ad_performance)" "$(rd)" "$(mcp get_attribution)" "$(wr report.md)"; done
sess other "$NOW" false "$(rd)" "$(rd)"
BEFORE="$(tree)"
OUT="$(scan --json --dir "$CFG" 2>"$T_TMP/err")"
t_eq "the output is one JSON object" 1 "$(printf '%s' "$OUT" | jq -s 'length')"
t_eq "schema 1, days defaults to 14" '1 14' "$(printf '%s' "$OUT" | jq -r '"\(.schema) \(.days)"')"
t_eq "sessions counts every session that made a tool call" 5 "$(printf '%s' "$OUT" | jq '.sessions')"
t_eq "exactly one candidate: the connector task" 1 "$(printf '%s' "$OUT" | jq '.candidates | length')"
t_eq "a candidate carries exactly the contract's keys" '["count","id","kind","sessions","shape"]' "$(printf '%s' "$OUT" | jq -c '.candidates[0] | keys')"
t_eq "the shape is plain words from the vocabulary" "connector report, then write document" "$(printf '%s' "$OUT" | jq -r '.candidates[0].shape')"
t_eq "a connector and a document make a skill" skill "$(printf '%s' "$OUT" | jq -r '.candidates[0].kind')"
t_eq "in 4 sessions" 4 "$(printf '%s' "$OUT" | jq '.candidates[0].sessions')"
t_eq "the id is 8 hex digits" true "$(printf '%s' "$OUT" | jq '.candidates[0].id | test("^[0-9a-f]{8}$")')"
ID1="$(printf '%s' "$OUT" | jq -r '.candidates[0].id')"
t_eq "the same scan twice is byte-identical" "$OUT" "$(scan --json --dir "$CFG")"
t_eq "the id is stable across scans of other windows" "$ID1" "$(scan --json --days 3 --dir "$CFG" | jq -r '.candidates[0].id')"

t_section "2 - privacy: a secret, a path and a client name in every call never come out"
t_hasnt "no secret" "$OUT" "$SEC"
t_hasnt "no client name" "$OUT" "$CLI"
t_hasnt "no path" "$OUT" "/Users"
t_hasnt "no file name" "$OUT" "report.md"
reset
for i in 1 2 3; do sess "p$i" "$NOW" false "$(sh_ "cd $PTH && TOKEN=$SEC curl -H 'Authorization: Bearer $SEC' https://$CLI.example/x")" "$(sh_ "gh pr create --title $CLI --body $SEC")"; done
PO="$(scan --json --dir "$CFG")"
t_eq "Bash is reduced to a tool and a subcommand from lists" "run curl, then run gh pr" "$(printf '%s' "$PO" | jq -r '.candidates[0].shape')"
t_hasnt "no secret from a command" "$PO" "$SEC"
t_hasnt "no client name from a command" "$PO" "$CLI"
t_hasnt "no path from a command" "$PO" "/Users"
reset
for i in 1 2 3; do sess "u$i" "$NOW" false "$(web)" "$(sh_ "$CLI-secret-tool --x")" "$(sh_ "$PTH/run.sh $SEC")" "$(mcp get_ad_performance)"; done
UO="$(scan --json --dir "$CFG")"
t_eq "an unknown command word is one phrase, whatever it was" "search the web, then run a command, then connector report" "$(printf '%s' "$UO" | jq -r '.candidates[0].shape')"
t_hasnt "an unknown command word does not come out" "$UO" "$CLI"
t_eq "every shape is lowercase words and commas" true "$(printf '%s' "$UO$PO" | jq -s '[.[].candidates[].shape | test("^[a-z0-9 ,]+$")] | all')"

t_section "3 - the cap of 3, and stopped ids go before it"
reset
# shape A in 7 sessions, B in 6, C in 5, D in 4: four candidates, each session holding one pair
pair() { # <count> <prefix> <first-call> <second-call>
  _i=1; while [ "$_i" -le "$1" ]; do sess "$2$_i" "$NOW" false "$3" "$4"; _i=$((_i+1)); done; }
pair 7 A "$(mcp get_ad_performance)" "$(wr a.md)"
pair 6 B "$(web)" "$(wr b.xlsx)"
pair 5 C "$(mcp send_message)" "$(wr c.pptx)"
pair 4 D "$(sh_ 'gh pr list')" "$(sh_ 'harbor event ci')"
T3="$(cands)"
t_eq "the cap is 3, best first (more sessions)" '[7,6,5]' "$(printf '%s' "$T3" | jq -c '[.[].sessions]')"
TOP="$(printf '%s' "$T3" | jq -r '.[0].id')"; D4="$(scan --json --dir "$CFG" | jq -r '.candidates[] | select(.sessions == 5) | .id')"
printf '%s\t2026-11-06\tpanel\n' "$TOP" > "$ST/stopped.tsv"
S1="$(cands)"
t_eq "the top one stopped: the next 3 come back, not an empty slot" '[6,5,4]' "$(printf '%s' "$S1" | jq -c '[.[].sessions]')"
t_hasnt "the stopped id is gone" "$S1" "$TOP"
printf 'id\tsince\torigin\n%s\t2026-11-06\tagent\nnot-an-id\t-\t-\n' "$TOP" > "$ST/stopped.tsv"
t_eq "a header and a junk line in stopped.tsv change nothing" '[6,5,4]' "$(scan --json --dir "$CFG" | jq -c '[.candidates[].sessions]')"
printf '%s\t2026-11-06\tpanel\n' "$D4" >> "$ST/stopped.tsv"
t_eq "two stopped ids are both dropped" '[6,4]' "$(scan --json --dir "$CFG" | jq -c '[.candidates[].sessions]')"
rm -f "$ST/stopped.tsv"
t_eq "stopped.tsv removed: they all come back" '[7,6,5]' "$(scan --json --dir "$CFG" | jq -c '[.candidates[].sessions]')"
t_eq "a kind is one of skill, hook, job" true "$(scan --json --dir "$CFG" | jq '[.candidates[].kind | IN("skill","hook","job")] | all')"

t_section "4 - what is a repeat, and what is not"
reset
pair 2 E "$(mcp get_ad_performance)" "$(wr a.md)"
t_eq "2 sessions are not a pattern" '[]' "$(cands)"
pair 1 F "$(mcp get_ad_performance)" "$(wr a.md)"
t_eq "3 sessions are" 1 "$(cands 'length')"
reset
for i in 1 2 3 4; do sess "g$i" "$NOW" false "$(rd)" "$(rd)" "$(ed a.py)" "$(sh_ 'git status')" "$(sh_ 'git diff')" "$(rd)" "$(sh_ 'ls')"; done
t_eq "reads, a code edit and bare git are plumbing: no candidate" '[]' "$(cands)"
reset
for i in 1 2 3 4; do sess "v$i" "$NOW" false "$(wr a.md)" "$(ed a.py)" "$(sh_ 'git status')"; done
t_eq "one real step among plumbing is not a pattern" '[]' "$(cands)"
reset
for i in 1 2 3 4; do sess "h$i" "$NOW" false "$(ed a.py)" "$(sh_ 'npm test')"; done
t_eq "an edit of code, then a named tool, is a hook" '["hook"]' "$(cands '[.[].kind]' )"
reset
for i in 1 2 3 4; do sess "j$i" "$NOW" false "$(sh_ 'gh pr list')" "$(sh_ 'harbor event ci')"; done
t_eq "shell-only work is a job" '["job"]' "$(cands '[.[].kind]')"
reset
for i in 1 2 3 4; do sess "k$i" "$NOW" false "$(mcp get_ad_performance)" "$(rd)" "$(rd)" "$(web)" "$(mcp get_attribution)" "$(wr a.md)"; done
t_eq "reads between steps do not break a shape, consecutive repeats are one step" "connector report, then search the web, then connector report, then write document" "$(cands '.[0].shape')" 
reset
for i in 1 2 3 4; do sess "m$i" "$NOW" false "$(mcp get_ad_performance)" "$(web)" "$(wr a.md)"; done
t_eq "a shape inside a longer one with the same sessions is not a second candidate" 1 "$(cands 'length')"
t_eq "...the longest is kept" "connector report, then search the web, then write document" "$(cands '.[0].shape')"
reset
for i in 1 2 3 4; do sess "n$i" "$NOW" true "$(mcp get_ad_performance)" "$(wr a.md)"; done
t_eq "subagent calls are not read" '[]' "$(cands)"
reset
for i in 1 2 3 4; do sess "q$i" "$NOW" false "$(mcp get_rows)" "$(mcp create_doc)"; done
t_eq "a verb in the tool name tells a report from an update" "connector report, then connector update" "$(cands '.[0].shape')"
reset
for i in 1 2 3 4; do sess "w$i" "$NOW" false "$(wr a.md)" "$(wr b.csv)" "$(wr c.html)"; done
t_eq "the extension class names the file kind" "write document, then write spreadsheet, then write web page" "$(cands '.[0].shape')"

t_section "5 - the window, copies of a session, and noise in the store"
reset
for i in 1 2; do sess "r$i" "$NOW" false "$(mcp get_ad_performance)" "$(wr a.md)"; done
sess r3 "$OLD" false "$(mcp get_ad_performance)" "$(wr a.md)"
sess r4 "$NOW" false "$(mcp get_ad_performance)" "$(wr a.md)"
touch -t "$(jq -n -r '(now - 7800000) | strftime("%Y%m%d%H%M")')" "$CFG/projects/-fx/r4.jsonl"
t_eq "an old record in a fresh file, and an untouched file, are outside 14 days" '[]' "$(cands)"
t_eq "--days 60 reaches the old record but not the stale file" 3 "$(scan --json --days 60 --dir "$CFG" | jq '.candidates[0].sessions')"
t_eq "--days is echoed" 60 "$(scan --json --days 60 --dir "$CFG" | jq '.days')"
reset
for i in 1 2; do sess "s$i" "$NOW" false "$(mcp get_ad_performance)" "$(wr a.md)"; done
cp "$CFG/projects/-fx/s1.jsonl" "$CFG/projects/-fx/s1-resumed.jsonl"
t_eq "a resumed session that copies history counts its calls once: 2 sessions, no candidate" '[]' "$(cands)"
t_eq "...and it is not a session of its own" 2 "$(scan --json --dir "$CFG" | jq '.sessions')"
reset
for i in 1 2 3; do sess "x$i" "$NOW" false "$(mcp get_ad_performance)" "$(wr a.md)"; done
{ printf '{"type":"assistant","timestamp":"%s","message":{"content":[{"type":"tool_use","id":"t","name":"Skill","input":{"skill":'"'"'\n' "$NOW"
  printf '{"type":"user","uuid":"q","timestamp":"%s","message":{"content":"{\\"type\\":\\"tool_use\\",\\"name\\":\\"WebSearch\\"}"}}\n' "$NOW"
  printf '{"type":"api-request-blob","timestamp":"%s","message":{"content":[{"type":"tool_use","id":"z","name":"WebSearch","input":{}}]}}\n' "$NOW"
} >> "$CFG/projects/-fx/x1.jsonl"
t_eq "a truncated line, a user quote and a request echo are not calls" "connector report, then write document" "$(cands '.[0].shape')"

t_section "6 - read-only: nothing is written anywhere"
reset
for i in 1 2 3 4; do sess "y$i" "$NOW" false "$(mcp get_ad_performance)" "$(wr a.md)"; done
printf '%s\t2026-11-06\tpanel\n' deadbeef > "$ST/stopped.tsv"
BEFORE="$(tree)"
scan --json --dir "$CFG" >/dev/null 2>&1; scan --json --live >/dev/null 2>&1 || :
t_eq "the store, the state folder and the temp dirs are the same after a scan" "$BEFORE" "$(tree)"
NOSTATE="$T_TMP/never-made"
(cd "$T_TMP" && HARBOR_STATUS_SUGGEST_DIR="$NOSTATE" sh "$SCAN" --json --dir "$CFG" >/dev/null 2>&1)
t_eq "a state folder that does not exist is not created" no "$([ -e "$NOSTATE" ] && echo yes || echo no)"
t_eq "the default state folder under HOME is not created" no "$([ -e "$HOME/.local/state/harbor/suggest" ] && echo yes || echo no)"

t_section "7 - usage and unavailable"
t_exit "no target is a usage error" 2 sh "$SCAN" --json
t_exit "--live and --dir together are refused" 2 sh "$SCAN" --json --live --dir "$CFG"
t_exit "--json is required" 2 sh "$SCAN" --dir "$CFG"
t_exit "--days 0 is refused" 2 sh "$SCAN" --json --days 0 --dir "$CFG"
t_exit "--days abc is refused" 2 sh "$SCAN" --json --days abc --dir "$CFG"
t_exit "--apply is refused: the scan is read-only" 2 sh "$SCAN" --json --apply --dir "$CFG"
t_exit "an unknown flag is refused" 2 sh "$SCAN" --json --nope --dir "$CFG"
EMPTY="$T_TMP/empty"; mkdir -p "$EMPTY"
t_exit "a config dir with no transcript store is exit 1" 1 sh "$SCAN" --json --dir "$EMPTY"
t_eq "...and prints no JSON" "" "$(sh "$SCAN" --json --dir "$EMPTY" 2>/dev/null)"
mkdir -p "$EMPTY/projects"
t_eq "an empty store is an honest zero" '{"schema":1,"days":14,"sessions":0,"candidates":[]}' "$(scan --json --dir "$EMPTY")"
t_has "--help prints the header" "$(sh "$SCAN" --help)" "status-suggest-scan.sh"

t_section "8 - kind mod (decision 9): read-only lookups a person keeps going back to, and nothing else"
kind_of() { scan --json --dir "$CFG" | jq -r '[.candidates[].kind] | unique | join(" ")'; }
reset
for i in 1 2 3; do sess "m$i" "$NOW" false "$(mcp get_ad_performance)" "$(sh_ 'docker ps')" "$(mcp get_attribution)" "$(sh_ 'docker ps -a')"; done
t_eq "lookups only, four a session: a mod" mod "$(kind_of)"
t_eq "...and the mod is the longest shape" "connector report, then run docker ps, then connector report, then run docker ps" "$(cands '.[0].shape' | tr -d '"')"
reset
for i in 1 2 3; do sess "m$i" "$NOW" false "$(sh_ 'kubectl logs x')" "$(sh_ 'docker ps')" "$(sh_ 'kubectl logs y')" "$(sh_ 'docker ps')"; done
t_eq "Bash lookups count too, with no connector" mod "$(kind_of)"
reset
for i in 1 2 3; do sess "m$i" "$NOW" false "$(mcp get_ad_performance)" "$(sh_ 'docker ps')"; done
t_eq "the same lookups once a session: a task, not a thing to keep in view" skill "$(kind_of)"
reset
for i in 1 2 3; do sess "m$i" "$NOW" false "$(sh_ 'kubectl logs x')" "$(sh_ 'docker ps')"; done
t_eq "...and a Bash pair once a session is a job" job "$(kind_of)"
reset
for i in 1 2 3; do sess "m$i" "$NOW" false "$(mcp get_ad_performance)" "$(wr a.md)" "$(mcp get_attribution)" "$(wr b.md)"; done
t_eq "a write in the shape: never a mod, however often" skill "$(kind_of)"
reset
for i in 1 2 3; do sess "m$i" "$NOW" false "$(sh_ 'gh pr create')" "$(sh_ 'docker ps')" "$(sh_ 'gh pr create')" "$(sh_ 'docker ps')"; done
t_eq "a step that may write (gh pr) is no lookup" job "$(kind_of)"
reset
for i in 1 2 3; do sess "m$i" "$NOW" false "$(mcp create_report)" "$(sh_ 'docker ps')" "$(mcp create_report)" "$(sh_ 'docker ps')"; done
t_eq "a connector update is no lookup" skill "$(kind_of)"

t_section "8b - a connector is a report only by a known read verb: unknown is not read-only, so it is never a mod"
tok() { reset; for i in 1 2 3; do sess "v$i" "$NOW" false "$(mcp "$1")" "$(wr a.md)"; done; cands '.[0].shape' | tr -d '"' | sed 's/, then write document$//'; }
for _t in get_rows list_items read_doc search_all query_x find_y show_z describe_w fetch_v view_u lookup_t retrieve_s getRows listItems list-items search; do
  t_eq "$_t reads" 'connector report' "$(tok "$_t")"
done
for _t in create_report send_message update_row delete_x get_or_create_x list_and_delete getOrCreateThing; do
  t_eq "$_t writes" 'connector update' "$(tok "$_t")"
done
for _t in save_report sync_data generate_x rename_y clear_z close_w enable_v disable_u mark_t authenticate report_outcome ad_performance whoami target; do
  t_eq "$_t says neither: the neutral step, no false claim of a write" 'use a connector' "$(tok "$_t")"
done
reset
for i in 1 2 3; do sess "m$i" "$NOW" false "$(call WebFetch '{"url":"https://x.example/a"}')" "$(mcp save_report)" "$(call WebFetch '{"url":"https://x.example/a"}')" "$(mcp save_report)"; done
t_eq "the finding's case: a write verb no list named is not a mod" skill "$(kind_of)"
reset
for i in 1 2 3; do sess "m$i" "$NOW" false "$(mcp ad_performance)" "$(sh_ 'docker ps')" "$(mcp ad_performance)" "$(sh_ 'docker ps')"; done
t_eq "a noun-named connector is not read-only: lookups beside it are no mod" skill "$(kind_of)"
t_eq "...and the shape says use, not update" 'use a connector, then run docker ps, then use a connector, then run docker ps' "$(cands '.[0].shape' | tr -d '"')"

t_section "8c - a path with non-ASCII characters scans the same"
CFG0="$CFG"; CFG="$T_TMP/ucfg-Čekis-é"; mkdir -p "$CFG/projects/-fx"
for i in 1 2 3; do sess "u$i" "$NOW" false "$(mcp get_rows)" "$(wr a.md)"; done
_o="$(scan --json --dir "$CFG")"
t_eq "three sessions, not a silent zero" 3 "$(printf '%s' "$_o" | jq '.sessions')"
t_eq "...and the candidate" 'connector report, then write document' "$(printf '%s' "$_o" | jq -r '.candidates[0].shape')"
sess u4 "$NOW" false "$(call Write '{"file_path":"/x/.jsonl:{.md","content":"x"}')"
t_eq "the cut mark inside a record leaves the record whole: a session with only that record counts" 4 "$(scan --json --dir "$CFG" | jq '.sessions')"
CFG="$CFG0"

t_section "8d - a planted state folder: the scan believes nothing it finds there"
reset
for i in 1 2 3; do sess "z$i" "$NOW" false "$(mcp get_rows)" "$(wr a.md)"; done
ZID="$(cands '.[0].id')"
printf '%s\t2026-11-06\tpanel\n' "$ZID" > "$T_TMP/stop.out"
ln -s "$T_TMP/stop.out" "$ST/stopped.tsv"
t_eq "stopped.tsv a link is not read: the candidate stays" "$ZID" "$(cands '.[0].id')"
rm -f "$ST/stopped.tsv"; mkfifo "$ST/stopped.tsv"
t_eq "stopped.tsv a FIFO: no hang" "$ZID" "$(cands '.[0].id')"
rm -f "$ST/stopped.tsv"; mv "$ST" "$ST.real"; mkdir -p "$T_TMP/elsewhere"; cp "$T_TMP/stop.out" "$T_TMP/elsewhere/stopped.tsv"; ln -s "$T_TMP/elsewhere" "$ST"
t_eq "the folder a link is not read through" "$ZID" "$(cands '.[0].id')"
rm -f "$ST"; mv "$ST.real" "$ST"
cp "$T_TMP/stop.out" "$ST/stopped.tsv"
t_eq "...and a plain stop list still drops it (the arms above can fail)" '[]' "$(cands)"
rm -f "$ST/stopped.tsv"

t_section "9 - the closed vocabulary: printed from the lists the reduction reads, and the real reduction stays inside it"
VOC="$(sh "$SCAN" --vocabulary)"
t_eq "--vocabulary reads no store and needs no target" 0 "$?"
t_eq "...and no two entries are the same step" "$(printf '%s' "$VOC" | jq '.steps | length')" "$(printf '%s' "$VOC" | jq '.steps | unique | length')"
t_eq "...the four kinds" 'mod skill hook job' "$(printf '%s' "$VOC" | jq -r '.kinds | join(" ")')"
t_eq "...all three connector steps" 'connector report|connector update|use a connector' "$(printf '%s' "$VOC" | jq -r '[.steps[] | select(test("connector"))] | join("|")')"
t_exit "--vocabulary beside anything else is a usage error" 2 sh "$SCAN" --vocabulary --live
in_voc() { printf '%s' "$VOC" | jq -e --arg s "$1" '.steps | index($s) != null' >/dev/null; }
# one real call of each class, carried through the real reduction beside a connector step: each step it prints must be a listed one
probe() { # <want step> <block>
  reset
  for i in 1 2 3; do sess "v$i" "$NOW" false "$(mcp get_ad_performance)" "$2"; done
  _shape="$(scan --json --dir "$CFG" | jq -r '.candidates[0].shape // ""')"
  t_has "the reduction prints '$1'" "$_shape" "$1"
  _bad=''; _o="$(jq -rn --arg s "$_shape" '$s | split(", then ")[]')"
  while IFS= read -r _st; do in_voc "$_st" || _bad="$_bad[$_st]"; done <<STEPS
$_o
STEPS
  t_eq "...and every step of that shape is in the vocabulary" '' "$_bad"
}
probe 'run python3' "$(sh_ 'python3 x.py')"
probe 'run harbor merge-stack' "$(sh_ 'harbor merge-stack 12')"
probe 'run terraform' "$(sh_ 'terraform nosuchword')"
probe 'write spreadsheet' "$(wr a.csv)"
probe 'edit web page' "$(ed a.html)"
probe 'write slides' "$(wr a.pptx)"
probe 'edit document' "$(ed a.md)"
probe 'search the web' "$(web)"
probe 'read a web page' "$(call WebFetch '{"url":"https://x.example/a"}')"
probe 'use the browser' "$(call mcp__chrome__click '{}')"
probe 'connector update' "$(mcp create_report)"
probe 'use a connector' "$(mcp ad_performance)"
t_done
