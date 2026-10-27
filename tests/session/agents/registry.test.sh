#!/usr/bin/env sh
# CONTRACTS/agents.tsv and the subagent pack's universal stop rules (harbor#445 item E): the table has the
# nine columns on every row and the seven seed roles, every row names a stop rule, and the pack carries
# the five universal rules inside its byte budget.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TSV="$T_ROOT/CONTRACTS/agents.tsv"; PACK="$T_ROOT/inject.d/box/10-subagent-contract.md"
t_section "agents.tsv shape"
t_eq "header is the nine columns" "role	model	effort	tools	input	output	done_when	must_not	stop_rule" "$(head -n 1 "$TSV")"
t_eq "every row has nine fields" "9" "$(awk -F'\t' '{print NF}' "$TSV" | sort -u)"
for r in build review audit cold-read consolidate docs explore; do
  t_eq "seed role $r present once" 1 "$(awk -F'\t' -v r="$r" 'NR>1 && $1==r' "$TSV" | wc -l | tr -d ' ')"
done
t_eq "no empty cell" 0 "$(awk -F'\t' 'NR>1{for(i=1;i<=NF;i++) if($i=="") n++} END{print n+0}' "$TSV")"
t_eq "build and consolidate may not push" 2 "$(awk -F'\t' '($1=="build"||$1=="consolidate") && $8 ~ /push/' "$TSV" | wc -l | tr -d ' ')"
t_section "the pack's universal stop rules"
P="$(cat "$PACK")"
t_has "report once" "$P" 'Report once'
t_has "a closed message ends the role" "$P" 'work is closed'
t_has "stop own background work" "$P" 'background'
t_has "no push, PR or merge" "$P" 'push, open a PR or merge'
t_has "deliverables go to the given path" "$P" 'path you were given'
t_eq "the pack stays under its byte budget (1400)" 1 "$([ "$(wc -c < "$PACK" | tr -d ' ')" -le 1400 ] && echo 1 || echo 0)"
t_done
