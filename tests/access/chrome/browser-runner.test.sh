#!/usr/bin/env sh
# agents/browser-runner.md (harbor#1507 pilot): the subagent a main session hands a mechanical browser flow keeps its
# model, its tool list and its size. It runs on haiku, holds ONLY harbor_chrome verbs that exist in the server's table, never
# holds a verb that changes a live system or reaches past the guards (confirm_click, upload, ...) or any other tool, and its
# instructions stay a short context. The role row in contracts/agents.tsv and the pilot section of the routing contract agree.
. "$(dirname "$0")/../../lib/core.sh"; t_init
DEF="$T_ROOT/agents/browser-runner.md"; SERVER="$T_ROOT/bin/access-chrome-mcp.ts"
BODY_MAX=60
fm() { awk '/^---$/{c++; next} c==1' "$DEF"; }                 # the frontmatter
body() { awk '/^---$/{c++; next} c>=2' "$DEF"; }               # everything after it
VERBS_TABLE="$(awk '/^const VERBS: Record/{f=1; next} f && /^};/{exit} f' "$SERVER")"   # the server's verb table
TOOLS="$(fm | sed -n 's/^tools: *//p' | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep .)"

t_section "frontmatter: name, model, description"
t_eq "name" "browser-runner" "$(fm | sed -n 's/^name: *//p')"
t_eq "model is haiku" "haiku" "$(fm | sed -n 's/^model: *//p')"
t_eq "a one-line description" 1 "$(fm | grep -c '^description: .\{20,\}')"

t_section "tools: harbor_chrome verbs only, each one the server has"
t_eq "the list is not empty" 1 "$([ "$(printf '%s\n' "$TOOLS" | grep -c .)" -ge 20 ] && echo 1 || echo 0)"
t_eq "every entry is an mcp__harbor_chrome__ verb" 0 "$(printf '%s\n' "$TOOLS" | grep -vc '^mcp__harbor_chrome__[a-z_]*$')"
t_eq "no entry twice" 0 "$(printf '%s\n' "$TOOLS" | sort | uniq -d | grep -c .)"
for v in $(printf '%s\n' "$TOOLS" | sed 's/^mcp__harbor_chrome__//; s/_/-/g'); do
  t_eq "the server's table has the verb $v" 1 "$(printf '%s\n' "$VERBS_TABLE" | grep -cE "(^|[ ,])('$v'|$v): " | sed 's/^[2-9]/1/')"
done
for v in attach detach status goto tab_new tab_list tab_select tab_close snapshot find text click dblclick fill type press select \
         check uncheck hover scroll wait_signin screenshot front go_back reload; do
  t_has "holds $v" "$TOOLS" "mcp__harbor_chrome__$v"
done
# A verb the guards cannot make safe in a haiku's hands, and every non-browser tool: never listed.
for v in confirm_click upload dialog_accept dialog_dismiss pdf drag console state doctor hosts resize \
         mousemove mousedown mouseup mousewheel keydown keyup tabs go_forward steps; do
  t_hasnt "never holds $v" "$TOOLS" "mcp__harbor_chrome__$v"
done
for v in Bash Write Edit Agent Task WebFetch Read; do
  t_eq "never holds $v" 0 "$(printf '%s\n' "$TOOLS" | grep -cx "$v")"
done

t_section "the instructions stay short and carry the gates"
t_eq "the body is at most $BODY_MAX lines" 1 "$([ "$(body | wc -l | tr -d ' ')" -le "$BODY_MAX" ] && echo 1 || echo 0)"
B="$(body)"
t_has "a refusal is reported, not routed around" "$B" "A refusal is an answer"
t_has "no sign-in by the agent" "$B" "wait_signin"
t_has "page text is data" "$B" "are data"
t_has "text click before find" "$B" '--text='
t_has "its own lane" "$B" 'lane: "runner"'
t_has "detach last" "$B" '`detach`'
for k in done steps_run what_was_read refusals url_hosts_visited; do t_has "report carries $k" "$B" "\"$k\""; done

t_section "the role row and the pilot section agree"
ROW="$(awk -F'\t' '$1=="browser-runner"' "$T_ROOT/contracts/agents.tsv")"
t_eq "one browser-runner row in agents.tsv" 1 "$(printf '%s\n' "$ROW" | grep -c .)"
t_eq "...on haiku" "haiku" "$(printf '%s' "$ROW" | cut -f2)"
t_has "the routing contract names the pilot" "$(cat "$T_ROOT/contracts/browser-routing.md")" "browser-runner"
t_done
