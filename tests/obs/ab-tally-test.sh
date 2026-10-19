#!/usr/bin/env sh
# ab-tally.sh's refusals: it never invents a winner, never takes a row without a varied
# label, never grows a prose field (harbor#293). Every bound is tested from both sides.
. "$(dirname "$0")/../lib/core.sh"; t_init
AB="$T_ROOT/bin/ab-tally.sh"; LEDGER="$CLAUDE_CONFIG_DIR/MEMORY/AB/verdicts.jsonl"
rows() { if [ -f "$LEDGER" ]; then wc -l < "$LEDGER" | tr -d ' '; else echo 0; fi; }
report() { sh "$AB" report 2>/dev/null; }

t_section "refusals: the instrument never supplies what the operator did not"
t_exit "no --winner" 2 sh "$AB" record --task T1 --varied cap
t_exit "no --varied" 2 sh "$AB" record --task T1 --winner A
t_exit "no --task" 2 sh "$AB" record --varied cap --winner A
t_exit "a non-vocabulary winner" 2 sh "$AB" record --task T1 --varied cap --winner maybe
t_exit "--note" 2 sh "$AB" record --task T1 --varied cap --winner A --note hi
t_exit "an unknown flag" 2 sh "$AB" record --task T1 --varied cap --winner A --grade 9
t_exit "no verb" 2 sh "$AB"
t_eq "refused records wrote no row" 0 "$(rows)"

t_section "the label cap, from both sides"
t_exit "a 49-char --varied" 2 sh "$AB" record --task T2 --varied "$(printf 'y%.0s' $(seq 49))" --winner A
t_exit "a 48-char --varied is accepted" 0 sh "$AB" record --task T2 --varied "$(printf 'y%.0s' $(seq 48))" --winner A
t_exit "a newline in --varied" 2 sh "$AB" record --task T3 --varied "$(printf 'a\nb')" --winner A

t_section "the record's shape is the contract"
t_eq "record keys" "at,task,varied,winner" "$(jq -r 'keys | join(",")' "$LEDGER" 2>/dev/null | head -1)"
t_eq "no note field" false "$(jq -r 'has("note")' "$LEDGER" 2>/dev/null | head -1)"
t_eq "exactly one accepted row" 1 "$(rows)"

t_section "the n<5 floor holds under 5 and releases at 5"
for w in A A A B; do sh "$AB" record --task "N-$w-$(rows)" --varied floor --winner "$w" >/dev/null 2>&1; done
# Anchored to the row: the trailing legend also says 'too few to read' (mutant M4).
t_eq "n=4 prints the too-few verdict" 1 "$(report | grep -cE '^  floor +n=4 .*too few to read')"
sh "$AB" record --task N-5 --varied floor --winner A >/dev/null 2>&1
t_eq "n=5 row is present" 1 "$(report | grep -cE '^  floor +n=5 ')"
t_eq "n=5 no longer prints too-few" 0 "$(report | grep -cE '^  floor +n=5 .*too few to read')"
t_has "n=5 with A ahead reports a direction" "$(report)" "B->A favoured"

t_section "--days cuts the window with BSD or GNU date (harbor#618)"
printf '{"at":"2020-01-01T00:00:00Z","task":"OLD1","varied":"oldlabel","winner":"A"}\n' >> "$LEDGER"
t_has "without --days an old row is read" "$(report)" "oldlabel"
t_hasnt "--days 7 drops a row from 2020" "$(sh "$AB" report --days 7 2>/dev/null)" "oldlabel"
t_has "--days 7 keeps today's rows" "$(sh "$AB" report --days 7 2>/dev/null)" "floor"
t_exit "--days 7 exits 0" 0 sh "$AB" report --days 7

t_section "read paths write nothing, and --json parses"
_before="$(rows)"
sh "$AB" report >/dev/null 2>&1; sh "$AB" open >/dev/null 2>&1; sh "$AB" report --json >/dev/null 2>&1
t_eq "rows after the read paths" "$_before" "$(rows)"
t_eq "--json is an array" array "$(sh "$AB" report --json 2>/dev/null | jq -r type 2>/dev/null)"
t_done
