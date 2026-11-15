#!/usr/bin/env sh
# member-upgrade.sh (harbor#1278), check member.upgrade: the Stop hook that holds contracts/member-law.md §1 (Upgrade line) and §2 (second reader).
. "$(dirname "$0")/../../lib/core.sh"; t_init
H="$T_ROOT/bin/member-upgrade.sh"
LONG='I read the three files and changed the loader so the export runs nightly. The table now lands in the dataset with the closed schema, the old rows stay where they were, and the validator refuses any row that carries free text, a login or a path from the laptop.'

# tx <name> <tools…>: a transcript whose last turn calls the named tools.
tx() {
  _f="$T_TMP/$1.jsonl"; shift
  printf '%s\n' '{"type":"user","message":{"content":"earlier prompt"}}' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Task"}]}}' \
    '{"type":"user","message":{"content":"do the work"}}' > "$_f"
  for _n in "$@"; do printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"%s"}]}}\n' "$_n" >> "$_f"; done
  printf '%s' "$_f"
}
# run <transcript> <reply> [stop_hook_active]
run() { jq -nc --arg t "$1" --arg m "$2" --argjson a "${3:-false}" '{session_id:"s",transcript_path:$t,last_assistant_message:$m,stop_hook_active:$a}' | sh "$H"; }
reason() { printf '%s' "$1" | jq -r '.reason // ""'; }

t_section "the Upgrade line (§1)"
T1="$(tx work Read Edit)"
O="$(run "$T1" "$LONG")"
t_eq "a worked answer with no Upgrade line is sent back" block "$(printf '%s' "$O" | jq -r .decision)"
t_has "...naming the line it wants" "$(reason "$O")" 'starting "Upgrade:"'
t_has "...under its check id" "$(reason "$O")" 'member.upgrade:'
t_eq "an Upgrade line passes" "" "$(run "$T1" "$LONG
Upgrade: the company-start pack's harbor-help skill lists the loader commands, so next time ask it first.")"
t_eq "a bold one too" "" "$(run "$T1" "$LONG
**Upgrade:** none")"
t_eq "a short answer is exempt" "" "$(run "$T1" "It is in the loader.")"
t_eq "an answer with no tool call is exempt" "" "$(run "$(tx chat)" "$LONG")"
t_eq "stop_hook_active stands it down, so it never loops" "" "$(run "$T1" "$LONG" true)"

t_section "the second reader (§2)"
D="$LONG I recommend we keep the nightly run; it is done and the error rate fell to 2%.
Upgrade: ask for the schema check by name."
O="$(run "$T1" "$D")"
t_has "a deciding answer with no second agent is sent back" "$(reason "$O")" 'no second agent checked it'
t_hasnt "...and not for the Upgrade line it has" "$(reason "$O")" 'starting "Upgrade:"'
t_eq "an Agent call in the turn is the second reader" "" "$(run "$(tx verified Read Agent)" "$D")"
t_eq "so is a Task call" "" "$(run "$(tx verified2 Task Edit)" "$D")"
t_eq "an Agent call before the prompt does not count" block "$(run "$T1" "$D" | jq -r .decision)"
LT="$LONG Rekomenduoju palikti naktinį paleidimą, viskas sutvarkyta.
Upgrade: kitą kartą paprašyk schemos patikros."
t_has "Lithuanian counts too" "$(reason "$(run "$T1" "$LT")")" 'no second agent'
t_has "both gaps in one reason" "$(reason "$(run "$T1" "$LONG It is fixed.")")" 'starting "Upgrade:"'

t_section "what counts as work, and what owes nothing (harbor#1278)"
Q='I read the export and the date range stops at March 3. Do you have the full export, or should I pull the numbers from the connector instead? The connector is faster but only shows the last 90 days, so tell me which you prefer.'
t_eq "a question back after lookups owes nothing" "" "$(run "$(tx ask Read Grep)" "$Q")"
t_eq "a closing question does not excuse a turn that ran things" block "$(run "$(tx ran Bash Edit)" "$LONG Want me to publish it?" | jq -r .decision)"
t_eq "a refusal owes nothing" "" "$(run "$(tx no Read)" "I can't change the consent settings in that container, because company rules say I never weaken a control. I have only read the file and changed nothing, so please contact the admin and say which tag must fire before consent.")"
t_eq "a status note owes nothing" "" "$(run "$(tx wip Bash)" "Still running: the export has processed 3 of 5 accounts and I am waiting on the last two. Nothing has failed so far and no data has changed; I will report when all five are in.")"
t_eq "one Read and an explanation owe nothing" "" "$(run "$(tx look Read)" "This script reads the nightly file, groups the rows by campaign and writes one summary line per campaign. The grouping happens in the aggregate function, which keeps a running total per key.")"
t_has "a short answer after two runs is still work" "$(reason "$(run "$(tx two Bash Edit)" "Done: the job runs at 02:00.")")" 'starting "Upgrade:"'
t_has "...and 25 words after one query is work" "$(reason "$(run "$(tx one Bash)" "Yesterday there were 4,210 sessions and 96 purchases across the two sites; the second site is up on the week, the first is flat, and nothing else moved much.")")" 'starting "Upgrade:"'
t_eq "the label with its colon outside the bold passes" "" "$(run "$T1" "$LONG
**Upgrade**: none")"
t_eq "a lowercase label passes" "" "$(run "$T1" "$LONG
upgrade: none")"
t_eq "'upgrade' in prose is not the line" block "$(run "$T1" "$LONG We will upgrade: first the loader, then the export." | jq -r .decision)"
t_has "Lithuanian 'siūlau' decides" "$(reason "$(run "$T1" "$LONG Siūlau palikti naktinį paleidimą.
Upgrade: none")")" 'no second agent'
t_has "a figure in euros after the number" "$(reason "$(run "$T1" "$LONG The week cost 410 EUR.
Upgrade: none")")" 'no second agent'
t_eq "'how it works' decides nothing" "" "$(run "$T1" "$LONG Here is how the retry works.
Upgrade: none")"
t_eq "'you should see' decides nothing" "" "$(run "$T1" "$LONG You should see a green badge in the corner.
Upgrade: none")"
t_has "an imperative decides" "$(reason "$(run "$T1" "$LONG Pause the Display campaign.
Upgrade: none")")" 'no second agent'

t_section "precision and recall on the labelled corpus (harbor#1278)"
# Floors sit a few points under the measured numbers (corpus/report.md), so a worse hook goes red and noise does not.
# precision and recall, whole percents: clause 1, clause 2, the decides regex alone.
set -- $(sh "$T_ROOT/tests/member/upgrade/measure.sh" --pct)
floor() { t_eq "$1 stays at $3 percent or better" ok "$([ "${2:-0}" -ge "$3" ] && echo ok || echo "$2 percent")"; }
floor "clause 1 precision" "${1:-}" 85
floor "clause 1 recall" "${2:-}" 95
floor "clause 2 precision" "${3:-}" 80
floor "clause 2 recall" "${4:-}" 82
floor "the decides regex's precision" "${5:-}" 70
floor "the decides regex's recall" "${6:-}" 85
t_eq "the corpus holds 80 rows or more" ok "$([ "$(cat "$T_ROOT"/tests/member/upgrade/corpus/*.jsonl | wc -l | tr -d ' ')" -ge 80 ] && echo ok || echo few)"
t_eq "...in both languages" 2 "$(cat "$T_ROOT"/tests/member/upgrade/corpus/*.jsonl | jq -r .lang | sort -u | wc -l | tr -d ' ')"

t_section "it never breaks a session"
t_exit "empty input" 0 sh "$H" </dev/null
t_eq "garbage input prints nothing" "" "$(printf 'not json' | sh "$H")"
t_eq "a missing transcript means no tool calls, so no check" "" "$(run "$T_TMP/none.jsonl" "$LONG")"
t_done
