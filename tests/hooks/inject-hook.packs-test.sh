#!/usr/bin/env sh
# The packs harbor ships, through inject-hook.sh: they parse, route and stay silent where they
# must, only context-bearing events emit, every tracked pack is well-formed, and the merge gate
# denies end to end through .claude/inject.d (harbor#173, #181, #184, #254, #315).
. "$(dirname "$0")/../lib/core.sh"; t_init
. "$(dirname "$0")/inject-fixture.sh"
BOX="$T/boxcfg"; mkdir -p "$BOX/inject.d"; cp -R "$T_ROOT"/inject.d/box/. "$BOX/inject.d/"
# The registry is the private layer's file (harbor#1149): core ships none, so a fixture with example names stands in,
# beside the packs where the installer puts it. It resolves against $HOME, the sandbox: stand up the directories it names.
printf '# fixture registry\nharbor\t~/port/harbor\tthe fixture control plane\ndemo\t~/port/demo\ta fixture project\n' > "$BOX/inject.d/projects.tsv"
while IFS="$(printf '\t')" read -r _rn _rp _rest; do
  case "$_rn" in ''|'#'*) continue ;; esac
  case "$_rp" in '~/'*) mkdir -p "$HOME/${_rp#'~/'}" ;; esac
done < "$BOX/inject.d/projects.tsv"
firebox() { fire_cfg "$BOX" "$1"; }

t_section "8 · the shipped box packs route"
t_has "the subagent contract routes" "$(firebox '{"hook_event_name":"SubagentStart","session_id":"b1"}')" 'final text IS the return value'
# harbor#321: the note must not assert what the receiving agent carries. Empty output fails t_hasnt, so this cannot pass by silence.
_b1s="$(firebox '{"hook_event_name":"SubagentStart","session_id":"b1s"}')"
_claim_none='inherited none'
_claim_only='only place you will see'
t_hasnt "the subagent contract claims no constitution is carried (#321)" "$_b1s" "$_claim_none"
t_hasnt "the subagent contract claims this note is the only place its rules appear (#321)" "$_b1s" "$_claim_only"
t_has "the claim matcher finds the old wording where it is written (#321 control)" "you $_claim_none of the operator" "$_claim_none"
t_has "the claim matcher finds the old wording where it is written (#321 control)" "this note is the $_claim_only" "$_claim_only"
t_has "the subagent contract states its rules neutrally of the context (#321)" "$_b1s" 'whether or not the operator'
t_has "the compaction carry routes on source=compact" \
  "$(firebox '{"hook_event_name":"SessionStart","source":"compact","session_id":"b2"}')" 'rebuilt by compaction'
t_hasnt "the compaction carry is silent on source=startup" \
  "$(firebox '{"hook_event_name":"SessionStart","source":"startup","session_id":"b2b"}')" 'rebuilt by compaction'
t_eq "PreCompact, context-less, emits nothing rather than rejected JSON" "" "$(firebox '{"hook_event_name":"PreCompact","session_id":"b2c"}')"
t_eq "PostCompact is context-less too" "" "$(firebox '{"hook_event_name":"PostCompact","session_id":"b2d"}')"
CTXCFG="$T/ctxcfg"; mkdir -p "$CTXCFG/inject.d"
for _ev in UserPromptExpansion PostModelSwitch Notification PostCompact; do
  printf -- '---\nid: ctx-%s\nevent: %s\nwhen: always\nonce: never\n---\nCTXPROBE\n' "$_ev" "$_ev" > "$CTXCFG/inject.d/00-ctx-$_ev.md"
done
for _ev in UserPromptExpansion PostModelSwitch Notification; do
  t_has "$_ev carries a model-visible channel" "$(fire_cfg "$CTXCFG" "$(jq -cn --arg e "$_ev" '{hook_event_name:$e,session_id:"ctxprobe"}')")" 'additionalContext'
done
t_eq "PostCompact with a pack on it still emits nothing" "" "$(fire_cfg "$CTXCFG" '{"hook_event_name":"PostCompact","session_id":"ctxprobe"}')"
t_has "the detector routes" "$(firebox "$(resp_ev Read "$QUIET_FIXTURE" b3)")" 'addressed to whatever is'
_b4="$(firebox '{"hook_event_name":"SessionStart","session_id":"b4"}')"
t_has "the project pointer routes, counting REGISTERED projects (harbor#181)" "$_b4" 'REGISTERED project(s)'
t_hasnt "the pointer no longer claims a count of the box" "$_b4" 'project(s) on this box'

t_section "8 · the \$VAR pack, and the heredoc false positive it shipped with"
t_has "fires on a real flag-taking call" "$(firebox "$(bash_ev PreToolUse 'bq query $P sql' v1)")" 'does not word-split'
t_eq "silent on a single-value use" "" "$(firebox "$(bash_ev PreToolUse 'cd $HOME' v2)")"
t_eq "silent on a quoted variable" "" "$(firebox "$(bash_ev PreToolUse 'bq query "$SQL"' v3)")"
t_eq "silent on the trap quoted inside a heredoc" "" "$(firebox "$(bash_ev PreToolUse 'gh issue create --body "$(cat <<'"'"'EOF'"'"'
example: bq query $P sql
EOF
)"' v4)")"
t_has "a heredoc does not mask a real call after it" "$(firebox "$(bash_ev PreToolUse 'cat <<EOF
notes
EOF
bq query $P sql' v5)")" 'does not word-split'

t_section "8 · the unbounded-wait-loop pack (the 39-minute loop, 2026-08-24)"
t_has "fires on the original bug" "$(firebox "$(bash_ev PreToolUse 'until [ "$(grep -c x f)" -ge 5 ]; do sleep 15; done' w1)")" 'cannot report giving up'
t_has "fires on while true + sleep" "$(firebox "$(bash_ev PreToolUse 'while true; do sleep 5; done' w2)")" 'cannot report giving up'
t_eq "silent on a for loop" "" "$(firebox "$(bash_ev PreToolUse 'for i in 1 2 3; do sleep 1; done' w3)")"
t_eq "silent on while read" "" "$(firebox "$(bash_ev PreToolUse 'while read l; do sleep 1; done < f' w4)")"
t_eq "silent on while IFS= read" "" "$(firebox "$(bash_ev PreToolUse 'while IFS= read -r l; do sleep 1; done < f' w4b)")"
t_eq "silent when a deadline is computed" "" \
  "$(firebox "$(bash_ev PreToolUse 'E=$(( $(date +%s) + 60 )); while [ $(date +%s) -lt $E ]; do sleep 5; done' w5)")"
t_eq "silent when wait-for is used" "" "$(firebox "$(bash_ev PreToolUse 'wait-for -t 60 -i 5 -- test -f /tmp/x' w6)")"
t_eq "silent on a loop with no sleep" "" "$(firebox "$(bash_ev PreToolUse 'while read x; do echo $x; done < f' w7)")"
t_eq "silent on the trap inside a heredoc" "" "$(firebox "$(bash_ev PreToolUse 'gh issue create --body "$(cat <<'"'"'EOF'"'"'
bad: until [ 1 -eq 2 ]; do sleep 15; done
EOF
)"' w8)")"
t_has "a heredoc does not mask a real wait loop after it" "$(firebox "$(bash_ev PreToolUse 'cat <<EOF
notes
EOF
until nc -z localhost 99; do sleep 5; done' w9)")" 'cannot report giving up'

t_section "8 · the project and repo-skills pointers"
# The directory comes from the path column, never the name (harbor#619 moved repos under ~/port).
_first="$(awk -F'\t' '$1 !~ /^#/ && NF >= 2 { print $1; exit }' "$BOX/inject.d/projects.tsv")"
_firstrel="$(awk -F'\t' '$1 !~ /^#/ && NF >= 2 { print $2; exit }' "$BOX/inject.d/projects.tsv")"
_firstdir="$HOME/${_firstrel#'~/'}"; git -C "$_firstdir" init -q . >/dev/null 2>&1
_pp="$(printf '%s' '{"hook_event_name":"SessionStart","session_id":"b5"}' \
  | CLAUDE_CONFIG_DIR="$BOX" CLAUDE_PROJECT_DIR="$_firstdir" sh "$SUT" 2>/dev/null)"
# The legacy needle "$_first: " matched no format the pointer prints; the list entry is "- name (".
t_has "from outside every project the pointer lists $_first" "$(firebox '{"hook_event_name":"SessionStart","session_id":"b5o"}')" "- $_first ("
t_hasnt "the pointer omits the project the session stands in ($_first)" "$_pp" "- $_first ("
gone "the repo-skills pointer is silent with no hidden skills" \
  "$(firebox '{"hook_event_name":"SessionStart","session_id":"b6"}')" 'cannot see and cannot invoke'
mkdir -p "$REPO/.claude/skills/secret-thing"
printf -- '---\nname: secret-thing\ndescription: "Does the secret thing. USE WHEN never."\ndisable-model-invocation: true\n---\nbody\n' \
  > "$REPO/.claude/skills/secret-thing/SKILL.md"
_b7="$(firebox '{"hook_event_name":"SessionStart","session_id":"b7"}')"
t_has "the repo-skills pointer names a hidden repo skill" "$_b7" 'secret-thing'
t_has "and says the model cannot see it" "$_b7" 'cannot see and cannot invoke'
_r315="$(firebox '{"hook_event_name":"SessionStart","session_id":"b7r"}')"
t_has "the pointer declares the root its paths resolve against (harbor#315)" "$_r315" 'every path below is relative to'
_root315="$(printf '%s' "$_r315" | sed -n 's/.*every path below is relative to \([^,]*\),.*/\1/p')"
t_eq "the declared root is absolute ($_root315)" / "$(printf '%s' "$_root315" | cut -c1)"

t_section "8 · a result that will be re-read all session (harbor#184, 32 KB threshold)"
_res() { # <tool> <bytes> [session] → the engine's stdout
  firebox "$(jq -cn --arg t "$1" --arg r "$(awk -v n="$2" 'BEGIN{while (i++ < n) printf "x"}')" --arg s "${3:-r-$$}" \
    '{hook_event_name:"PostToolUse",tool_name:$t,session_id:$s,tool_response:$r}')"
}
t_has "a 40 KB result is named" "$(_res Read 40000 lv2a)" 'result threshold'
t_eq "a 500 B result says nothing" "" "$(_res Read 500 lv2b)"
t_eq "exactly at the threshold is silent" "" "$(_res Read 32768 lv2c)"
t_has "one byte over fires" "$(_res Read 32769 lv2d)" 'result threshold'
t_has "Read is told about offset/limit" "$(_res Read 40000 lv2e)" 'offset/limit'
t_has "browser_batch is told about get_page_text" "$(_res mcp__claude-in-chrome__browser_batch 90000 lv2f)" 'get_page_text'
t_has "an in-scope tool with no specific case gets the generic remedy" "$(_res mcp__meta-ads__ads_catalog_search_product 40000 lv2g)" 'subagent'
t_eq "an Agent result is exempt" "" "$(_res Agent 90000 lv2h)"
_res Read 40000 lv2i >/dev/null
t_eq "the second large result in a session is silent" "" "$(_res Read 40000 lv2i)"
t_has "a tool: pattern matches the family it names (a regex, like settings.json)" "$(_res mcp__claude-in-chrome__computer 90000 lv2j)" 'result threshold'
t_eq "a tool outside the declared set is still skipped" "" "$(_res NotDeclaredAnywhere 90000 lv2k)"

t_section "8b · PostToolUseFailure, on the measured payload shape (claude 2.1.258)"
FAILCFG="$T/failcfg"; mkdir -p "$FAILCFG/inject.d"
cp "$T_ROOT/inject.d/box/85-tool-failure-is-not-a-result.md" "$T_ROOT/inject.d/box/tool-failure.sh" "$FAILCFG/inject.d/"
fail_ev() { # <is_interrupt> <error> [session]
  jq -cn --argjson i "$1" --arg e "$2" --arg s "${3:-f-$$}" \
    '{hook_event_name:"PostToolUseFailure",tool_name:"Read",session_id:$s,tool_input:{file_path:"/nope.txt"},tool_use_id:"tu1",error:$e,is_interrupt:$i,duration_ms:4}'
}
t_has "a failed tool call gets the note" "$(fire_cfg "$FAILCFG" "$(fail_ev false 'File does not exist.' f1)")" 'not verified'
t_eq "an operator interrupt is silent" "" "$(fire_cfg "$FAILCFG" "$(fail_ev true 'The user doesn'"'"'t want to take this action' f2)")"
fire_cfg "$FAILCFG" "$(fail_ev false 'first' f3)" >/dev/null
t_eq "the second failure in a session is silent" "" "$(fire_cfg "$FAILCFG" "$(fail_ev false 'second' f3)")"
t_has "the note rides a model-visible channel on this event" "$(fire_cfg "$FAILCFG" "$(fail_ev false 'x' f4)")" 'additionalContext'
ERRCFG="$T/errcfg"
pack "$ERRCFG/inject.d" 10-err.md <<'PACK'
---
id: err
event: PostToolUseFailure
when: content-contains does not exist
once: never
---
ERRSEEN
PACK
t_has "content-contains reads .error on a failure payload" "$(fire_cfg "$ERRCFG" "$(fail_ev false 'File does not exist. Note: cwd is /tmp' e1)")" ERRSEEN
gone "a different error still does not match" "$(fire_cfg "$ERRCFG" "$(fail_ev false 'Edit anchor not found' e2)")" ERRSEEN

t_section "8c · an Agent call chooses its tier (harbor#818, #843)"
_ag() { # <tool> <tool_input json> [session]
  firebox "$(jq -cn --arg t "$1" --argjson i "$2" --arg s "${3:-ag-$$}" --arg c "$REPO" \
    '{hook_event_name:"PreToolUse",tool_name:$t,session_id:$s,cwd:$c,tool_input:$i}')"
}
_defn() { mkdir -p "${1%/*}"; printf -- '---\nname: %s\ndescription: fixture\nmodel: %s\n---\nbody\n' "$2" "$3" > "$1"; }
_defn "$BOX/plugins/cache/mkt/demo-kit/1.0/agents/pinned.md" pinned haiku
_defn "$BOX/plugins/cache/mkt/demo-kit/1.0/agents/loose.md" loose inherit
_defn "$BOX/agents/scout.md" scout haiku
_defn "$BOX/agents/file-name-differs.md" renamed sonnet
_defn "$REPO/.claude/agents/local.md" local '"opus"  # quoted, commented'
_a1="$(_ag Agent '{"description":"d","prompt":"p","subagent_type":"general-purpose"}' ag1)"
t_has "no model on a general-purpose call is denied" "$_a1" '"permissionDecision":"deny"'
t_has "the reason names the tiers" "$_a1" 'haiku + effort medium: search'
t_has "the reason names the effort for code changes" "$_a1" 'haiku + effort high: a scoped code change'
t_has "the reason points at the full rules" "$_a1" 'skills/agent-routing/SKILL.md'
t_has "a second no-model call in the same session is denied too (once: never)" \
  "$(_ag Agent '{"description":"d","prompt":"p","subagent_type":"general-purpose"}' ag1)" '"permissionDecision":"deny"'
t_has "no subagent_type and no model is denied" "$(_ag Agent '{"description":"d","prompt":"p"}' ag2)" '"permissionDecision":"deny"'
t_has "the legacy Task name is covered" "$(_ag Task '{"description":"d","prompt":"p"}' ag3)" '"permissionDecision":"deny"'
gone "a call that sets model passes" "$(_ag Agent '{"description":"d","prompt":"p","model":"sonnet"}' ag4)" 'permissionDecision'
gone "a fork passes: it ignores model by design" "$(_ag Agent '{"description":"d","prompt":"p","subagent_type":"fork"}' ag5)" 'permissionDecision'
gone "a plugin agent whose definition pins a model passes" "$(_ag Agent '{"description":"d","prompt":"p","subagent_type":"demo-kit:pinned"}' ag6)" 'permissionDecision'
t_has "a plugin agent that inherits is denied" "$(_ag Agent '{"description":"d","prompt":"p","subagent_type":"demo-kit:loose"}' ag7)" '"permissionDecision":"deny"'
t_has "an unknown plugin agent is denied" "$(_ag Agent '{"description":"d","prompt":"p","subagent_type":"demo-kit:absent"}' ag8)" '"permissionDecision":"deny"'
gone "a user agent pinned by filename passes" "$(_ag Agent '{"description":"d","prompt":"p","subagent_type":"scout"}' ag9)" 'permissionDecision'
gone "a user agent pinned by its name: field passes" "$(_ag Agent '{"description":"d","prompt":"p","subagent_type":"renamed"}' ag10)" 'permissionDecision'
gone "a project agent with a quoted, commented pin passes" "$(_ag Agent '{"description":"d","prompt":"p","subagent_type":"local"}' ag11)" 'permissionDecision'
t_has "a glob in subagent_type exempts nothing" "$(_ag Agent '{"description":"d","prompt":"p","subagent_type":"*:pinned"}' ag12)" '"permissionDecision":"deny"'
gone "a malformed tool_input fails open" "$(_ag Agent '"not an object"' ag13)" 'permissionDecision'
gone "a Bash call is not this pack's business" "$(firebox "$(bash_ev PreToolUse 'ls' ag14)")" 'permissionDecision'

t_section "9 · every tracked pack is well-formed"
fm() { awk 'NR==1 && $0 !~ /^---/ {exit} NR>1 && $0 ~ /^---/ {exit} NR>1' "$1"; }  # <pack> → its frontmatter
for _f in "$T_ROOT"/inject.d/*/*.md "$T_ROOT"/.claude/inject.d/*.md; do
  [ -f "$_f" ] || continue
  _e="$(fm "$_f" | awk -F': *' '$1=="event"{print $2;exit}')"
  _w="$(fm "$_f" | grep -c '^when:')"; _r="$(fm "$_f" | awk -F': *' '$1=="run"{print $2;exit}')"
  _b="$(awk 'BEGIN{n=0} /^---[[:space:]]*$/ {n++; next} n>=2' "$_f" | tr -d '[:space:]')"
  case "$_e" in PreToolUse|PostToolUse|PostToolUseFailure|SessionStart|PreCompact|SubagentStart) _v=ok ;; *) _v="no usable event" ;; esac
  [ "$_v" != ok ] || [ "${_w:-0}" -ge 1 ] || _v="no when: predicate"
  if [ "$_v" = ok ] && [ -n "$_r" ]; then [ -f "$(dirname "$_f")/$_r" ] || _v="run: script $_r is missing"
  elif [ "$_v" = ok ] && [ -z "$_b" ]; then _v="neither a body nor a run:"; fi
  t_eq "well-formed: ${_f#"$T_ROOT"/}" ok "$_v"
done

t_section "the merge gate end to end: shipped pack, real govern-hook.sh, stubbed backstop (harbor#254)"
E2E="$T/e2e"; mkdir -p "$E2E/repo/bin" "$E2E/repo/.claude/inject.d" "$E2E/cfg"
( cd "$E2E/repo" && git init -q . && git config user.email t@t && git config user.name t \
  && git config commit.gpgsign false && printf 'x\n' > README && git add -A && git commit -qm init ) >/dev/null 2>&1
cp "$T_ROOT/bin/govern-hook.sh" "$E2E/repo/bin/"; cp "$T_ROOT/.claude/inject.d/merge-note.sh" "$E2E/repo/.claude/inject.d/"
for _mp in "$T_ROOT"/.claude/inject.d/*merge*.md; do cp "$_mp" "$E2E/repo/.claude/inject.d/"; done
_e2e() { # <exit> <text> <command>
  printf '#!/usr/bin/env sh\nprintf "%%s\\n" "%s"\nexit %s\n' "$2" "$1" > "$E2E/repo/bin/merge-check.sh"
  jq -cn --arg c "$3" '{hook_event_name:"PreToolUse",tool_name:"Bash",session_id:"e-1",tool_input:{command:$c}}' \
    | CLAUDE_CONFIG_DIR="$E2E/cfg" CLAUDE_PROJECT_DIR="$E2E/repo" sh "$SUT" 2>/dev/null
}
t_has "a refusing backstop denies through the shipped pack" "$(_e2e 1 'REFUSED  a check is not passing on #253' 'gh pr merge 253 --squash')" '"permissionDecision":"deny"'
t_has "the harbor#254 incident command is denied" \
  "$(_e2e 1 'REFUSED  pending' 'sh bin/merge-check.sh 253 2>&1 | tail -2 && gh pr merge 253 --squash')" '"permissionDecision":"deny"'
t_hasnt "a green PR is not interrupted" "$(_e2e 0 'ok  #253 — 12 check(s) pass' 'gh pr merge 253 --squash')" 'permissionDecision'
t_hasnt "a tooling fault fails open" "$(_e2e 2 'merge-check: gh is not installed' 'gh pr merge 253')" 'permissionDecision'

t_section "the browser route: Claude in Chrome is refused on a host harbor chrome covers (2026-09-30)"
_HR="$HOME/$(awk -F'\t' '$1 == "harbor" { sub(/^~\//, "", $2); print $2; exit }' "$BOX/inject.d/projects.tsv")"
mkdir -p "$_HR/CONTRACTS"; cp "$T_ROOT/CONTRACTS/browser-agent-hosts.txt" "$_HR/CONTRACTS/"
nav_ev() { printf '{"hook_event_name":"PreToolUse","session_id":"%s","tool_name":"mcp__claude-in-chrome__navigate","tool_input":{"url":"%s","tabId":1}}' "$2" "$1"; }
batch_ev() { printf '{"hook_event_name":"PreToolUse","session_id":"%s","tool_name":"mcp__claude-in-chrome__browser_batch","tool_input":{"actions":[{"name":"computer","input":{"action":"wait"}},{"name":"navigate","input":{"tabId":1,"url":"%s"}}]}}' "$2" "$1"; }
t_has "a navigate to ads.reddit.com is denied" "$(firebox "$(nav_ev https://ads.reddit.com/ br1)")" '"permissionDecision":"deny"'
t_has "the refusal names the command to run" "$(firebox "$(nav_ev https://ads.reddit.com/ br2)")" 'harbor chrome goto'
t_has "...and the MCP tool first (harbor#1301)" "$(firebox "$(nav_ev https://ads.reddit.com/ br3)")" 'mcp__harbor_chrome__goto with args [\"https://ads.reddit.com/\"]'
t_has "a subdomain of a listed host is denied" "$(firebox "$(nav_ev https://x.ads.reddit.com/a br3)")" '"permissionDecision":"deny"'
t_has "a scheme-less, upper-case url is denied" "$(firebox "$(nav_ev WWW.LinkedIn.com/campaignmanager br4)")" '"permissionDecision":"deny"'
t_has "a navigate inside browser_batch is denied" "$(firebox "$(batch_ev https://ads.reddit.com/accounts br5)")" '"permissionDecision":"deny"'
t_has "a second navigate is denied too (once: never)" "$(firebox "$(nav_ev https://ads.reddit.com/ br1)")" '"permissionDecision":"deny"'
t_hasnt "an unlisted host is not refused" "$(firebox "$(nav_ev https://en.wikipedia.org/wiki/X br6)")" 'permissionDecision'
t_hasnt "a lookalike host is not refused" "$(firebox "$(nav_ev https://ads.reddit.com.evil.test/ br7)")" 'permissionDecision'
t_hasnt "a suffix that is not a subdomain is not refused" "$(firebox "$(nav_ev https://badads.reddit.com.test/ br8)")" 'permissionDecision'
t_hasnt "a Sheets/Docs editor is not refused (docs.google.com)" "$(firebox "$(nav_ev https://docs.google.com/spreadsheets/d/x/edit br11)")" 'permissionDecision'
t_hasnt "an editor inside browser_batch is not refused" "$(firebox "$(batch_ev https://docs.google.com/document/d/x br12)")" 'permissionDecision'
t_has "another google.com host is still denied" "$(firebox "$(nav_ev https://ads.google.com/aw/overview br13)")" '"permissionDecision":"deny"'
t_has "a lookalike editor host is still denied" "$(firebox "$(nav_ev https://docs.google.com.ads.google.com/ br14)")" '"permissionDecision":"deny"'
t_has "the first Claude-in-Chrome call gets the route reminder" "$(firebox "$(nav_ev https://en.wikipedia.org/ br9)")" 'ToolSearch will never show it'
mv "$_HR/CONTRACTS/browser-agent-hosts.txt" "$_HR/CONTRACTS/hosts.off"
t_hasnt "no hosts file fails open" "$(firebox "$(nav_ev https://ads.reddit.com/ br10)")" 'permissionDecision'
mv "$_HR/CONTRACTS/hosts.off" "$_HR/CONTRACTS/browser-agent-hosts.txt"
t_done
