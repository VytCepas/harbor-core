#!/usr/bin/env sh
# The capped spawner in bin/event-dispatch.sh (harbor#1044), against a stub `claude`: inert until spawn.on
# exists; then `claude -p` with haiku, narrow tools, no permission prompts, 5 turns and $0.25, as the operator
# (no API key); the result goes back as agent.result with its cause; spend is read from total_cost_usd and
# held under $5 a UTC day. A real claude is never run: the suite stops if the one on PATH is not the stub.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/event/dispatch/fixture.sh"
[ "$(command -v claude)" = "$T_BIN/claude" ] || { echo "spawn.test: the claude on PATH is not the stub — refusing to run" >&2; exit 2; }
export ANTHROPIC_API_KEY=sk-test-never-used ANTHROPIC_AUTH_TOKEN=tok-never ANTHROPIC_BASE_URL=https://proxy.invalid \
  CLAUDE_CODE_OAUTH_TOKEN=oat-never GH_TOKEN=ghp-never AWS_SECRET_ACCESS_KEY=aws-never HARBOR_TEST_SECRET=stray
dispatch_once
register event.test-agent test.spawn
sh "$ED" on '"kind":"test\.spawn"' --id event.test-agent --debounce 0 --rate 60 --spawn 'Summarise the event.' 2>/dev/null
# The day's spend as the dispatcher counts it: its append-only record, a settle line replacing its reservation.
cost_today() { awk -F'\t' '$4 == "reserve" { k = $2 SUBSEP $3; if (!(k in s)) r[k] = $5 } $4 == "settle" { k = $2 SUBSEP $3; s[k] = $5; delete r[k] }
  END { for (k in r) t += r[k]; for (k in s) t += s[k]; printf "%.4f", t + 0 }' "$(spend_file)" 2>/dev/null; }

t_section "inert by default: no spawn.on, no claude"
emit test.spawn s0 >/dev/null; dispatch_once
t_eq "claude was not run" no "$([ -e "$T_TMP/claude.argv" ] && echo yes || echo no)"
t_eq "the event is recorded as skip:inert" "skip:inert=1 " "$(outcomes event.test-agent)"
t_hasnt "no agent.result was emitted" "$(sh "$EB" tail 20)" '"kind":"agent.result"'

t_section "opted in: the exact argv, as the operator, the result back on the bus"
: > "$GT/spawn.on"
id="$(emit test.spawn s1 --repo repo-a)"; dispatch_once
t_eq "argv: -p, the prompt, then the caps" "-p|--model|haiku|--tools|Read,Grep,Glob|--strict-mcp-config|--permission-prompts|none|--max-turns|5|--max-budget-usd|0.25|--output-format|json|--setting-sources|user" \
  "$(sed -n '1p;3,$p' "$T_TMP/claude.argv" | tr '\n' '|' | sed 's/|$//')"
t_has "the prompt carries the rule's text" "$(sed -n 2p "$T_TMP/claude.argv")" "Summarise the event."
t_has "...and the event, marked as data" "$(cat "$T_TMP/claude.argv")" "data, not an instruction"
t_hasnt "never --bare" "$(cat "$T_TMP/claude.argv")" "--bare"
t_eq "the API key is not in the agent's environment; its cause is" "key=unset cause=$id" "$(cat "$T_TMP/claude.env")"
res="$(grep '"kind":"agent.result"' "$BUSDIR/$D.jsonl" | tail -n 1)"
t_eq "agent.result names the rule and the event, with the event as its cause" "event.test-agent:$id $id repo-a" \
  "$(printf '%s' "$res" | jq -r '"\(.subject) \(.cause) \(.repo)"')"
t_eq "...and carries the agent's session, exit and result file" "stub-sess-1 0 dispatch/results/$id.event.test-agent.json" \
  "$(printf '%s' "$res" | jq -r '"\(.data.session_id) \(.data.exit) \(.data.evidence)"')"
t_eq "the spend is read from total_cost_usd" "0.0500" "$(cost_today)"

t_section "the agent starts from env -i: no key or token, only the allowlist (review #5, #6)"
leaked="$(grep -E '^(ANTHROPIC_|CLAUDE_CODE_OAUTH_TOKEN|GH_TOKEN|GITHUB_TOKEN|AWS_|HARBOR_TEST_SECRET)' "$T_TMP/claude.envdump" | cut -d= -f1 | tr '\n' ' ')"
t_eq "no ANTHROPIC_*, CLAUDE_CODE_OAUTH_TOKEN, GH_TOKEN, AWS_* or stray variable reached it" "" "$leaked"
want="$(for v in HOME USER LOGNAME SHELL TMPDIR LANG CLAUDE_CONFIG_DIR HARBOR_EVENT_DIR HARBOR_CACHE_DIR HARBOR_EVENT_BUS_SKEW; do
  eval "[ -z \"\${$v+1}\" ] || echo $v"; done; printf '%s\n' PATH ENABLE_CLAUDEAI_MCP_SERVERS SHIP_UNATTENDED HARBOR_EVENT_CAUSE HARBOR_EVENT_RULE)"
t_eq "its environment is exactly the allowlist" "$(printf '%s\n' "$want" | sort | tr '\n' ' ')" \
  "$(cut -d= -f1 "$T_TMP/claude.envdump" | grep -v -x -E 'PWD|OLDPWD|SHLVL|_' | sort | tr '\n' ' ')"
t_has "claude.ai connectors are off" "$(cat "$T_TMP/claude.envdump")" "ENABLE_CLAUDEAI_MCP_SERVERS=false"
t_has "...and MCP servers: --strict-mcp-config with no --mcp-config" "$(cat "$T_TMP/claude.argv")" "--strict-mcp-config"
t_hasnt "...never --mcp-config" "$(cat "$T_TMP/claude.argv")" "--mcp-config"

t_section "the daily cap: \$5 a UTC day, counting the next agent at its \$0.25 cap"
printf '%s\tseed\tevent.test-agent\treserve\t4.7000\n' "$((NOON + $(date -u +%s)))" >> "$(spend_file)"
rm -f "$T_TMP/claude.argv"; emit test.spawn s2 >/dev/null; dispatch_once
t_eq "4.75 spent: one more fits exactly" yes "$([ -e "$T_TMP/claude.argv" ] && echo yes || echo no)"
t_eq "...spend is now 4.80" "4.8000" "$(cost_today)"
rm -f "$T_TMP/claude.argv"; emit test.spawn s3 >/dev/null; dispatch_once 2>/dev/null
t_eq "4.80 spent: the next is refused" no "$([ -e "$T_TMP/claude.argv" ] && echo yes || echo no)"
t_has "...and recorded" "$(outcomes event.test-agent)" "skip:cap=1"
t_has "...with one checks.log line naming the check" "$(cat "$CACHE/checks.log")" "[check:event.dispatch]"
t_has "...that says when it lifts" "$(cat "$CACHE/checks.log")" "no spawn until 00:00 UTC"
emit test.spawn s4 >/dev/null; dispatch_once 2>/dev/null
t_eq "a second refusal the same day writes no second line" 1 "$(grep -c 'daily cap' "$CACHE/checks.log")"
HARBOR_EVENT_BUS_SKEW=$((NOON + 86400)); export HARBOR_EVENT_BUS_SKEW
emit test.spawn s5 >/dev/null; dispatch_once
t_eq "the next UTC day starts at zero" yes "$([ -e "$T_TMP/claude.argv" ] && echo yes || echo no)"

t_section "a cost the agent did not report counts as the cap; an overrun is an alarm"
stub_cost none; emit test.spawn s6 >/dev/null; dispatch_once 2>/dev/null
t_eq "no total_cost_usd: 0.25 recorded" "0.2500" "$(awk -F'\t' '$6 == "s6" { print $7 }' "$LEDGER")"
stub_cost 0.31; emit test.spawn s7 >/dev/null; dispatch_once 2>/dev/null
t_has "over \$0.25: a checks.log line" "$(cat "$CACHE/checks.log")" "cost \$0.3100, over the \$0.25 per-agent cap"
stub_cost

t_section "no claude on the PATH"
mkdir -p "$T_TMP/nobin"; ln -s "$(command -v jq)" "$T_TMP/nobin/jq"
P2="$T_TMP/nobin:/usr/bin:/bin:/usr/sbin:/sbin"
if PATH="$P2" command -v claude >/dev/null 2>&1; then echo "  skip: a claude lives in a system dir here — not run"; t_pass
else
  rm -f "$T_TMP/claude.argv"; emit test.spawn s8 >/dev/null; PATH="$P2" sh "$ED" dispatch --once 2>/dev/null
  t_eq "nothing spawned, recorded as such" "fail:no-claude" "$(awk -F'\t' '$6 == "s8" { print $5 }' "$LEDGER")"
fi

t_section "a -- handler is only an installed, allowlisted Harbor script with its recorded bytes (review #1, r2 #1)"
rm -f "$GT/spawn.on" "$T_TMP/claude.argv" "$T_TMP/claude.starts"
register event.test-cmd test.cmd
ln -s "$T_BIN/claude" "$T_TMP/ai"
mkdir -p "$HOME/.local/bin" "$T_TMP/tools"; ln -s "$T_BIN/claude" "$HOME/.local/bin/claude"; cp "$T_BIN/claude" "$T_TMP/tools/cc"
printf '"%s" -p "from a script" --dangerously-skip-permissions\n' "$T_BIN/claude" > "$T_TMP/abs.sh"
printf 'claude -p "from a script"\n' > "$T_TMP/wrap.sh"
refused() { # <label> <handler argv...>: on exits 4
  _l="$1"; shift
  t_exit "$_l is refused (4)" 4 sh "$ED" on '"kind":"test\.cmd"' --id event.test-cmd --debounce 0 --rate 60 -- "$@"
}
refused "-- claude -p …" claude -p 'do things' --tools Bash
refused "-- env claude …" env claude -p x
refused "-- nice -n 5 claude …" nice -n 5 claude -p x
refused "-- sh -c 'claude -p x'" sh -c 'cd /; claude -p x'
refused "-- <absolute path to claude>" "$T_BIN/claude" -p x
refused "-- <a symlink to claude under another name>" "$T_TMP/ai" -p x
refused "-- sh -c with the path split in two (r2 probe abs1)" sh -c 'exec "$HOME/.local/bin/cl""aude" -p uncapped --tools Bash'
refused "-- sh <a script that runs claude by absolute path> (abs2)" sh "$T_TMP/abs.sh"
refused "-- sh -c that drops the shim from PATH (abs3)" sh -c 'PATH="${PATH#*:}"; exec cl""aude -p "past the shim"'
refused "-- a copied claude binary (copy)" "$T_TMP/tools/cc" -p x
refused "-- npx @anthropic-ai/claude-code (npx)" npx -y @anthropic-ai/claude-code@latest -p q
refused "-- node cli.js (node)" node "$HOME/.local/share/claude/cli.js" -p q
mkdir -p "$T_TMP/.claude/bin"; printf 'exit 0\n' > "$T_TMP/.claude/bin/ok.sh"
refused "-- sh <a script outside {cfg}/bin>" sh "$T_TMP/.claude/bin/ok.sh"
printf 'exit 0\n' > "$T_TMP/clean.sh"; install_bin harbor-clean.sh "$T_TMP/clean.sh"
refused "-- sh {cfg}/bin/<installed but not allowlisted>" sh "$CFG/bin/harbor-clean.sh"
refused "-- /bin/sh <allowlisted> (only the exact form)" /bin/sh "$HND"
refused "-- sh {cfg}/bin/../bin/<allowlisted>" sh "$CFG/bin/../bin/pulse-notify.sh"
refused "-- sh <allowlisted> with an extra word" sh "$HND" extra
cp "$HND" "$T_TMP/hnd.keep"; printf '# edited\n' >> "$HND"
refused "-- sh <allowlisted, its bytes not the manifest's>" sh "$HND"
cp "$T_TMP/hnd.keep" "$HND"
t_eq "none of them left a rule" no "$([ -e "$GT/rules/event.test-cmd.rule" ] && echo yes || echo no)"
t_exit "-- sh {cfg}/bin/<allowlisted, as installed> is accepted" 0 sh "$ED" on '"kind":"test\.cmd"' --id event.test-cmd --debounce 0 --rate 60 -- sh "$HND"
printf 'id=event.test-cmd\npattern="kind":"test\\.cmd"\ndebounce=0\nrate=60\nbackstop=0\ncreated=0\nkind=cmd\nargv=claude\nargv=-p\nargv=do things\n' > "$GT/rules/event.test-cmd.rule"
emit test.cmd hand-edited >/dev/null; dispatch_once 2>/dev/null
t_eq "a rule file edited to run claude: claude did not run, no spawn.on needed to stop it" no "$([ -e "$T_TMP/claude.argv" ] && echo yes || echo no)"
t_eq "...recorded as refused" "refused" "$(awk -F'\t' '$6 == "hand-edited" { print $5 }' "$LEDGER")"
printf 'id=event.test-cmd\npattern="kind":"test\\.cmd"\ndebounce=0\nrate=60\nbackstop=0\ncreated=0\nkind=cmd\nargv=sh\nargv=%s\n' "$T_TMP/abs.sh" > "$GT/rules/event.test-cmd.rule"
emit test.cmd hand-abs >/dev/null; dispatch_once 2>/dev/null
t_eq "a rule file edited to a script that runs claude by absolute path: claude did not run" no "$([ -e "$T_TMP/claude.starts" ] && echo yes || echo no)"
t_eq "...recorded as refused" "refused" "$(awk -F'\t' '$6 == "hand-abs" { print $5 }' "$LEDGER")"
sh "$ED" on '"kind":"test\.cmd"' --id event.test-cmd --debounce 0 --rate 60 -- sh "$HND" 2>/dev/null
handler event.test-cmd "$T_TMP/wrap.sh"
emit test.cmd wrapped >/dev/null; dispatch_once 2>/dev/null
t_eq "and behind it, the refusing shim: an installed script that calls claude by name runs no agent" no "$([ -e "$T_TMP/claude.argv" ] && echo yes || echo no)"
t_eq "...the handler failed with the shim's 126" "done:126" "$(awk -F'\t' '$6 == "wrapped" { print $5 }' "$LEDGER")"

t_section "a spawned agent starts in its own empty directory, never HOME (review r2 #5)"
: > "$GT/spawn.on"; rm -f "$T_TMP/claude.ctx"
emit test.spawn cwd1 >/dev/null; dispatch_once 2>/dev/null
wd="$(sed -n 's/^pwd=//p' "$T_TMP/claude.ctx")"
t_has "its working directory is under the dispatcher's state dir" "$wd" "$ST/work/agent."
t_eq "...it was empty when the agent started" "entries=0" "$(grep '^entries=' "$T_TMP/claude.ctx")"
t_eq "...and it is gone after" no "$([ -e "$wd" ] && echo yes || echo no)"

t_section "SHIP_UNATTENDED=1 reaches every handler and agent (review r2 #2)"
t_eq "the agent has SHIP_UNATTENDED=1" "ship=1" "$(grep '^ship=' "$T_TMP/claude.ctx")"
printf 'printf "ship=%%s\\n" "${SHIP_UNATTENDED-unset}" > "%s"\n' "$T_TMP/handler.ship" > "$T_TMP/ship.sh"
handler event.test-cmd "$T_TMP/ship.sh"
unset SHIP_UNATTENDED
emit test.cmd ship1 >/dev/null; dispatch_once 2>/dev/null
t_eq "a cmd handler has SHIP_UNATTENDED=1, though the dispatcher was started without it" "ship=1" "$(cat "$T_TMP/handler.ship" 2>/dev/null)"

t_section "while the kill switch {cfg}/.harbor-autoship.off exists, nothing runs (review r2 #2)"
rm -f "$T_TMP/handler.ship" "$T_TMP/claude.starts"; : > "$CFG/.harbor-autoship.off"
emit test.cmd killed1 >/dev/null; emit test.spawn killed2 >/dev/null
SHIP_UNATTENDED=1 sh "$ED" dispatch --once 2>/dev/null
t_eq "the cmd handler did not run" no "$([ -e "$T_TMP/handler.ship" ] && echo yes || echo no)"
t_eq "the agent did not run, spawn.on or not" no "$([ -e "$T_TMP/claude.starts" ] && echo yes || echo no)"
t_eq "...both recorded" "skip:autoship-off skip:autoship-off" "$(awk -F'\t' '$6 == "killed1" || $6 == "killed2" { print $5 }' "$LEDGER" | tr '\n' ' ' | sed 's/ $//')"
t_has "...with a checks.log line naming the switch" "$(cat "$CACHE/checks.log")" ".harbor-autoship.off exists"
rm -f "$CFG/.harbor-autoship.off"; emit test.cmd after >/dev/null; dispatch_once 2>/dev/null
t_eq "lifted: the next event runs, and nothing held back is replayed" "done:0" "$(awk -F'\t' '$6 == "after" { print $5 }' "$LEDGER")"
t_eq "...killed1 still has its one line" 1 "$(awk -F'\t' '$6 == "killed1"' "$LEDGER" | grep -c .)"

t_section "no rule ever invokes gate-approve.sh, whatever its trigger (review r2 #2)"
register event.autoapprove approval.open
t_exit "-- sh -c 'gate-approve.sh merge …; gh pr merge …' on approval.open (r2 probe P3) is refused" 4 \
  sh "$ED" on '"kind":"approval\.open"' --id event.autoapprove --debounce 0 --rate 60 -- sh -c 'gate-approve.sh merge VytCepas/harbor 1 deadbeef; gh pr merge 1 -R VytCepas/harbor --squash'
printf 'exit 0\n' > "$T_TMP/ga.sh"; install_bin gate-approve.sh "$T_TMP/ga.sh"
sh "$ED" on '"kind":"approval\.open"' --id event.autoapprove -- sh "$CFG/bin/gate-approve.sh" 2>"$T_TMP/ga.err"; rc=$?
t_eq "-- sh {cfg}/bin/gate-approve.sh, installed and recorded, is refused (4)" 4 "$rc"
t_has "...naming why" "$(cat "$T_TMP/ga.err")" "no rule ever approves"
printf 'sh gate-approve.sh merge x 1 abc\n' > "$T_TMP/pn-ga.sh"; install_bin pulse-notify.sh "$T_TMP/pn-ga.sh"
t_exit "an allowlisted script whose bytes name gate-approve.sh is refused" 4 sh "$ED" on '"kind":"approval\.open"' --id event.autoapprove -- sh "$HND"
install_bin pulse-notify.sh "$T_TMP/router.sh"
t_exit "a --spawn prompt that names gate-approve.sh is refused" 4 sh "$ED" on '"kind":"approval\.open"' --id event.autoapprove --spawn 'run gate-approve.sh merge for it'
t_eq "none of them left a rule" no "$([ -e "$GT/rules/event.autoapprove.rule" ] && echo yes || echo no)"
printf 'id=event.autoapprove\npattern="kind":"approval\\.open"\ndebounce=0\nrate=60\nbackstop=0\ncreated=0\nkind=cmd\nargv=sh\nargv=%s\n' "$CFG/bin/gate-approve.sh" > "$GT/rules/event.autoapprove.rule"
emit approval.open merge-VytCepas_harbor-1-deadbeef0000 >/dev/null; dispatch_once 2>/dev/null
t_eq "a rule file written by hand to run it is refused on load" "refused" "$(awk -F'\t' '$4 == "event.autoapprove" { print $5 }' "$LEDGER")"
rm -f "$GT/rules/event.autoapprove.rule"

t_section "a spawn killed mid-run keeps its \$0.25 reservation and is never spawned again (review #4)"
: > "$GT/spawn.on"; rm -f "$T_TMP/claude.starts"; : > "$T_TMP/stub.block"
emit test.spawn killed >/dev/null
i=0
while [ "$i" -lt 4 ]; do
  i=$((i + 1))
  sh "$ED" dispatch --once 2>/dev/null & DP=$!
  n=0; while [ "$(lines "$T_TMP/claude.starts")" -lt "$i" ] && kill -0 "$DP" 2>/dev/null && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
  kill -s TERM "$DP" 2>/dev/null; wait "$DP" 2>/dev/null
done
rm -f "$T_TMP/stub.block"; dispatch_once 2>/dev/null
t_eq "four TERMs and a clean run: the agent was started once" 1 "$(lines "$T_TMP/claude.starts")"
t_eq "...its ledger line is the reservation" "reserved" "$(awk -F'\t' '$6 == "killed" { print $5 }' "$LEDGER" | tr '\n' ' ' | sed 's/ $//')"
t_eq "...counted at the \$0.25 cap" "0.25" "$(awk -F'\t' '$6 == "killed" { print $7 }' "$LEDGER")"

t_section "the kill switch stops a handler already running: its whole process group, within seconds (review r3 #2)"
rm -f "$GT/spawn.on" "$CFG/.harbor-autoship.off"
cat > "$T_TMP/inflight.sh" <<EOF
sleep 300 & printf '%s\n' "\$!" > "$T_TMP/inflight.child"
printf '%s\n' "\$\$" > "$T_TMP/inflight.pid"
while :; do sleep 0.2; done
EOF
handler event.test-cmd "$T_TMP/inflight.sh"
emit test.cmd inflight >/dev/null
sh "$ED" dispatch --once 2>/dev/null & DP=$!
until_file "$T_TMP/inflight.child" 15
hp="$(cat "$T_TMP/inflight.pid" 2>/dev/null)"; cp_="$(cat "$T_TMP/inflight.child" 2>/dev/null)"
t_eq "the handler and its child are running" yes "$(kill -0 "$hp" 2>/dev/null && kill -0 "$cp_" 2>/dev/null && echo yes || echo no)"
: > "$CFG/.harbor-autoship.off"; t0="$(date +%s)"
n=0; while kill -0 "$DP" 2>/dev/null && [ "$n" -lt 150 ]; do sleep 0.1; n=$((n + 1)); done
t_eq "the dispatcher finished within 6 s of the switch" yes "$([ $(( $(date +%s) - t0 )) -le 6 ] && ! kill -0 "$DP" 2>/dev/null && echo yes || echo no)"
kill "$DP" 2>/dev/null; wait "$DP" 2>/dev/null
t_eq "the handler is gone" no "$(kill -0 "$hp" 2>/dev/null && echo yes || echo no)"
t_eq "...and its child in the same group" no "$(kill -0 "$cp_" 2>/dev/null && echo yes || echo no)"
t_eq "...recorded as killed" "killed:autoship-off" "$(awk -F'\t' '$6 == "inflight" { print $5 }' "$LEDGER")"
t_has "...with a checks.log line" "$(cat "$CACHE/checks.log")" "its process group was killed"
kill -9 "$hp" "$cp_" 2>/dev/null; rm -f "$CFG/.harbor-autoship.off"

t_section "the kill switch stops an agent already running, and keeps its spend counted (review r3 #2)"
: > "$GT/spawn.on"; : > "$T_TMP/stub.block"; : > "$T_TMP/claude.starts"
emit test.spawn agent-inflight >/dev/null
sh "$ED" dispatch --once 2>/dev/null & DP=$!
until_file "$T_TMP/claude.starts" 15
sp="$(tail -n 1 "$T_TMP/claude.starts")"
t_eq "the agent is running" yes "$(kill -0 "$sp" 2>/dev/null && echo yes || echo no)"
: > "$CFG/.harbor-autoship.off"; t0="$(date +%s)"
n=0; while kill -0 "$DP" 2>/dev/null && [ "$n" -lt 150 ]; do sleep 0.1; n=$((n + 1)); done
t_eq "the dispatcher finished within 6 s of the switch" yes "$([ $(( $(date +%s) - t0 )) -le 6 ] && ! kill -0 "$DP" 2>/dev/null && echo yes || echo no)"
kill "$DP" 2>/dev/null; wait "$DP" 2>/dev/null
t_eq "the agent is gone" no "$(kill -0 "$sp" 2>/dev/null && echo yes || echo no)"
t_eq "...recorded as killed, its \$0.25 kept" "killed:autoship-off 0.2500" "$(awk -F'\t' '$6 == "agent-inflight" { print $5, $7 }' "$LEDGER")"
rm -f "$T_TMP/stub.block" "$CFG/.harbor-autoship.off"; kill -9 "$sp" 2>/dev/null

t_section "the kill switch in the live ~/.claude holds whatever config dir the dispatcher has (review r3 #1)"
mkdir -p "$HOME/.claude"; : > "$HOME/.claude/.harbor-autoship.off"; rm -f "$T_TMP/handler.ship"
handler event.test-cmd "$T_TMP/ship.sh"
emit test.cmd live-switch >/dev/null; dispatch_once 2>/dev/null
t_eq "the handler did not run" no "$([ -e "$T_TMP/handler.ship" ] && echo yes || echo no)"
t_eq "...recorded" "skip:autoship-off" "$(awk -F'\t' '$6 == "live-switch" { print $5 }' "$LEDGER")"
rm -f "$HOME/.claude/.harbor-autoship.off"

t_section "the follower and a rule write are the operator's: never a Claude session, never another config dir (review r3 #1)"
rm -f "$T_TMP/handler.ship"; emit test.cmd from-session >/dev/null
t_exit "dispatch --once inside a Claude session (CLAUDECODE set) is refused (4)" 4 env CLAUDECODE=1 sh "$ED" dispatch --once
# Bounded: a follower that is not refused would run forever, so it gets 10 s and then reads as 124.
env CLAUDECODE=1 sh "$ED" dispatch >/dev/null 2>&1 </dev/null & FP=$!
n=0; while kill -0 "$FP" 2>/dev/null && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
if kill -0 "$FP" 2>/dev/null; then kill "$FP"; wait "$FP" 2>/dev/null; rc=124; else rc=0; wait "$FP" || rc=$?; fi
t_eq "...so is the follower" 4 "$rc"
t_eq "...and nothing ran" no "$([ -e "$T_TMP/handler.ship" ] && echo yes || echo no)"
t_exit "on <pattern> inside a session is refused (4)" 4 env CLAUDECODE=1 sh "$ED" on '"kind":"test\.cmd"' --id event.test-cmd -- sh "$HND"
t_exit "on --preset inside a session is refused (4)" 4 env CLAUDECODE=1 sh "$ED" on --preset event.pulse
t_exit "on --off inside a session is refused (4)" 4 env CLAUDECODE=1 sh "$ED" on --off event.test-cmd
t_exit "on --list inside a session is a read, and runs" 0 env CLAUDECODE=1 sh "$ED" on --list
t_exit "a checkout's copy (not installed) does not follow (4)" 4 sh "$T_ROOT/bin/event-dispatch.sh" dispatch --once
# The r3 probe cfgenv.sh: a config dir with its own allowlisted script, manifest row and no kill switch.
EL="$T_TMP/elsewhere"; mkdir -p "$EL/bin"; printf ': > "%s"\n' "$T_TMP/elsewhere.ran" > "$EL/bin/pulse-notify.sh"
printf '%s 100755 bin/pulse-notify.sh runtime-install test\n' "$(git hash-object --no-filters "$EL/bin/pulse-notify.sh")" > "$EL/.harbor-manifest"
: > "$CFG/.harbor-autoship.off"
rc=0; CLAUDE_CONFIG_DIR="$EL" sh "$ED" dispatch --once 2>"$T_TMP/el.err" || rc=$?
t_eq "the installed copy with CLAUDE_CONFIG_DIR pointing elsewhere: refused (4)" 4 "$rc"
t_has "...naming the config dir it was installed into" "$(cat "$T_TMP/el.err")" "the config dir this copy was installed into"
t_eq "...and the other dir's script never ran" no "$([ -e "$T_TMP/elsewhere.ran" ] && echo yes || echo no)"
rm -f "$CFG/.harbor-autoship.off"; dispatch_once 2>/dev/null

t_section "the day's spend survives a truncated ledger: the cap holds (review r3 #1)"
: > "$GT/spawn.on"; stub_cost 0.05; : > "$T_TMP/claude.starts"
printf '%s\tseed-r3\tevent.test-agent\treserve\t4.8000\n' "$((NOON + 86400 + $(date -u +%s)))" >> "$(spend_file)"
i=0
while [ "$i" -lt 6 ]; do
  i=$((i + 1)); : > "$LEDGER"; emit test.spawn "trunc$i" >/dev/null; dispatch_once 2>/dev/null
done
t_eq "six ': > ledger' and six events: no agent ran (r3 selfopt: 6 ran, \$6.50 in a \$5 day)" 0 "$(lines "$T_TMP/claude.starts")"
t_eq "...each one recorded as the cap" "skip:cap" "$(awk -F'\t' '$6 == "trunc6" { print $5 }' "$LEDGER")"

t_section "a spend record that shrank fails closed: the day counts as spent (review r3 #1)"
HARBOR_EVENT_BUS_SKEW=$((NOON + 2 * 86400)); export HARBOR_EVENT_BUS_SKEW
emit test.spawn day3-a >/dev/null; dispatch_once 2>/dev/null
t_eq "a fresh day: one agent ran" 1 "$(lines "$T_TMP/claude.starts")"
: > "$(spend_file)"
emit test.spawn day3-b >/dev/null; dispatch_once 2>/dev/null
t_eq "the record cut to 0 bytes: no agent ran" 1 "$(lines "$T_TMP/claude.starts")"
t_eq "...recorded as the cap" "skip:cap" "$(awk -F'\t' '$6 == "day3-b" { print $5 }' "$LEDGER")"
t_has "...with a checks.log line that says it was cut" "$(cat "$CACHE/checks.log")" "spend record was cut"
rm -f "$(spend_file)"
emit test.spawn day3-c >/dev/null; dispatch_once 2>/dev/null
t_eq "the record deleted while its size mark stands: still no agent" 1 "$(lines "$T_TMP/claude.starts")"

t_section "an event id is a file name only when it is [A-Za-z0-9._-] with no .. (review r3 #8)"
HARBOR_EVENT_BUS_SKEW=$((NOON + 3 * 86400)); export HARBOR_EVENT_BUS_SKEW
emit test.spawn day4 >/dev/null
bf="$(ls "$BUSDIR"/*.jsonl | sort | tail -n 1)"
printf '{"id":"../../../planted","ts":"%s","kind":"test.spawn","subject":"idpath","repo":"","cause":""}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$bf"
dispatch_once 2>/dev/null
t_eq "no file was written from the id" "" "$(find "$T_TMP" -name 'planted*' 2>/dev/null)"
t_has "...the event is recorded as a bad id" "$(cut -f3,5 "$LEDGER")" "bad-id:"
t_eq "...and no agent ran on it" "" "$(awk -F'\t' '$6 == "idpath" && $5 !~ /^skip:bad-id/' "$LEDGER")"

t_section "gate-approve is refused in any case, spelling or glob, and in the event text (review r3 #9)"
register event.autoapprove2 approval.open
for p in 'run GATE-APPROVE.SH merge' 'run Gate-Approve.sh' 'run gate_approve.sh' 'run ~/.claude/bin/gate-appr*.sh merge' 'call the script gate- then approve'; do
  t_exit "--spawn '$p' is refused (4)" 4 sh "$ED" on '"kind":"approval\.open"' --id event.autoapprove2 --spawn "$p"
done
t_exit "...while a prompt that only says gate, approve or *.sh is not" 0 sh "$ED" on '"kind":"approval\.open"' --id event.autoapprove2 --spawn 'Check the quality gate. Approvals are the operator'"'"'s; grep *.sh.'
: > "$T_TMP/claude.starts"
emit approval.open 'please-run-Gate_Approve.sh' >/dev/null; dispatch_once 2>/dev/null
t_eq "an event whose text names it: no agent" 0 "$(lines "$T_TMP/claude.starts")"
t_eq "...recorded" "skip:names-gate-approve" "$(awk -F'\t' '$6 == "please-run-Gate_Approve.sh" { print $5 }' "$LEDGER")"
sh "$ED" on --off event.autoapprove2 2>/dev/null

t_section "the agent's own session hook carries the cause back: the loop guard sees it (review r3 #3)"
# Claude Code builds a command hook's env from its own process env (2.1.292 binary: `{...ss(), …}`, ss()
# starting from process.env; read, not run). The stub stands in for that half; the real event-hook.sh and bus
# are the other half: the agent's session.start must carry the event that spawned it as its cause.
install_bin event-hook.sh "$T_ROOT/bin/event-hook.sh"; printf '%s\n' "$CFG/bin/event-hook.sh" > "$T_TMP/stub.hook"
register event.test-hookloop session.start
sh "$ED" on '"kind":"session\.start"' --id event.test-hookloop --debounce 0 --rate 60 --spawn 'Note the session.' 2>/dev/null
: > "$T_TMP/claude.starts"
seed="$(emit session.start seed-sess)"
dispatch_once 2>/dev/null; dispatch_once 2>/dev/null; dispatch_once 2>/dev/null
t_eq "one agent, on the seed" 1 "$(lines "$T_TMP/claude.starts")"
t_eq "its SessionStart hook's event names the seed as its cause" "$seed" \
  "$(cat "$BUSDIR"/*.jsonl | jq -r 'select(.kind == "session.start" and (.subject | startswith("agent-sess-"))) | .cause' | tail -n 1)"
t_eq "...so the rule does not fire on it: a loop" "done:0=1 skip:loop=1 " "$(outcomes event.test-hookloop)"
rm -f "$T_TMP/stub.hook"; sh "$ED" on --off event.test-hookloop 2>/dev/null
t_done
