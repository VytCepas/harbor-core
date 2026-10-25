#!/usr/bin/env sh
# reconcile.test.sh (harbor#1050) — bin/status-obligations.sh reconcile: one fixture per source, a silent
# source flips nothing, the two places it runs. Every source is a stub behind its HARBOR_STATUS_OBLIGATION_*
# knob; gh, claude and launchctl on PATH are poison that records a touch, and the suite fails if one is hit.
#
# THE RED-PROOFS ARE IN THE SUITE. Each source's case is a function that prints ok or what was wrong, and
# runs twice: against the real script (must print ok) and against a copy with one line broken (must not).
# A mutation that did not apply fails too, so a proof cannot pass for want of a change.
. "$(dirname "$0")/../../lib/core.sh"; t_init

BIN="$T_ROOT/bin/status-obligations.sh"; KINDS="$T_ROOT/CONTRACTS/obligation-kinds.tsv"
W="$T_TMP/w"; EV="$W/ev"; OB="$W/ob"; FIX="$W/fix"; STUBS="$T_TMP/stubs"; MUTD="$T_TMP/mut"
NOW=2026-10-06T02:00:00Z; NOWE="$(jq -n -r --arg t "$NOW" '$t | fromdateiso8601')"; N=0; D=2026-10-06.jsonl
STUB_FIX="$FIX"; export STUB_FIX
READ_TO=""; BUDGET=""; FAULT=""; ONOVER=""; EMPTY='{}'

# Poison: the real tools must never run. A stub is reached only through its knob.
for _c in gh claude launchctl; do
  printf '#!/bin/sh\necho %s >> "%s/touched"\nexit 1\n' "$_c" "$T_TMP" > "$T_BIN/$_c"; chmod +x "$T_BIN/$_c"
done
mkdir -p "$STUBS" "$MUTD"
cat > "$STUBS/gh" <<'EOF'
#!/bin/sh
echo "$*" >> "$STUB_FIX/gh.calls"
[ ! -f "$STUB_FIX/gh.hang" ] || exec sleep 30
[ ! -f "$STUB_FIX/gh.hang2" ] || { sleep 30; exit 1; }   # a grandchild keeps stdout open past the kill (harbor#1115)
case "$1 $2" in
  "pr view") f="$STUB_FIX/pr-$3" ;;
  "run view") f="$STUB_FIX/run-$3.json" ;;
  *) exit 2 ;;
esac
[ -f "$f" ] || exit 1
cat "$f"
EOF
cat > "$STUBS/claude" <<'EOF'
#!/bin/sh
echo "$*" >> "$STUB_FIX/claude.calls"
[ "$1 $2 $3" = "agents --json --all" ] || exit 2
[ ! -f "$STUB_FIX/claude.hang" ] || exec sleep 30
[ ! -f "$STUB_FIX/claude.hang2" ] || { sleep 30; exit 1; }
[ -f "$STUB_FIX/agents.json" ] || exit 1
cat "$STUB_FIX/agents.json"
EOF
cat > "$STUBS/sessions" <<'EOF'
#!/bin/sh
echo "$*" >> "$STUB_FIX/sessions.calls"
[ ! -f "$STUB_FIX/sessions.hang" ] || exec sleep 30
[ ! -f "$STUB_FIX/sessions.hang2" ] || { sleep 30; exit 1; }
[ -f "$STUB_FIX/sessions.json" ] || exit 1
cat "$STUB_FIX/sessions.json"
EOF
chmod +x "$STUBS"/*
ln -sf "$T_ROOT/bin/log-lib.sh" "$MUTD/log-lib.sh"; ln -sf "$T_ROOT/bin/fs-lib.sh" "$MUTD/fs-lib.sh"; ln -sf "$T_ROOT/bin/event-bus.sh" "$MUTD/event-bus.sh"

fresh() { rm -rf "$W"; mkdir -p "$EV" "$OB" "$FIX/sweep"; N=0; NOW=2026-10-06T02:00:00Z; READ_TO=""; BUDGET=""; FAULT=""; ONOVER=""; }
ev() { # <ts> <kind> <subject> [data-json]
  N=$((N + 1))
  printf '{"id":"e%s","ts":"%s","src":"cli","kind":"%s","subject":"%s","repo":"harbor","cause":"","data":%s}\n' "$N" "$1" "$2" "$3" "${4:-$EMPTY}" >> "$EV/$D"
}
run() { # <script> <mode> — combined output
  env HARBOR_EVENT_DIR="$EV" HARBOR_OBLIGATION_DIR="$OB" HARBOR_STATUS_OBLIGATION_NOW="$NOW" HARBOR_STATUS_OBLIGATION_KINDS="$KINDS" \
    HARBOR_STATUS_OBLIGATION_GH="$STUBS/gh" HARBOR_STATUS_OBLIGATION_CLAUDE="$STUBS/claude" HARBOR_STATUS_OBLIGATION_SESSIONS="$STUBS/sessions" \
    HARBOR_STATUS_OBLIGATION_HOUSEKEEPING="$FIX/sweep/.helm-sweep.jsonl" HARBOR_STATUS_OBLIGATION_TRANSCRIPTS="$FIX/tr" \
    ${READ_TO:+HARBOR_STATUS_OBLIGATION_READ_TIMEOUT="$READ_TO"} ${BUDGET:+HARBOR_STATUS_OBLIGATION_BUDGET="$BUDGET"} \
    ${FAULT:+HARBOR_STATUS_OBLIGATION_FAULT="$FAULT"} ${ONOVER:+HARBOR_STATUS_OBLIGATION_ON_OVERDUE="$ONOVER"} sh "$1" "$2" 2>&1
}
rec() { run "$X" reconcile; }
cur() { jq -r --arg id "$1" ".obligations[] | select(.id == \$id) | .$2" "$OB/current.json"; }
src() { jq -r ".[\"$1\"].$2" "$OB/sources.json"; }
calls() { cat "$FIX/$1.calls" 2>/dev/null | wc -l | tr -d ' '; }
lines() { wc -l < "$OB/ledger.jsonl" | tr -d ' '; }
BAD=""
chk() { [ "$3" = "$2" ] || BAD="$BAD [$1: want '$2', got '$3']"; }
verdict() { printf '%s' "${BAD:-ok}"; BAD=""; }
sweep_rows() { # <at> then rows on stdin
  cat > "$FIX/sweep/.helm-sweep.jsonl"
  printf 'sweep items=3 risk=1 decide=1 reclaim=1 bytes=0 keep=0 unread=0 due=1 at=%s\n' "$1" > "$FIX/sweep/.helm-sweep"
}

# Break one line of the real script into a copy under $MUTD; fail if the line is not there.
mutate() { # <from> <to>
  awk -v from="$1" -v to="$2" 'BEGIN { RS = "\001" } { i = index($0, from); if (i == 0) exit 3; printf "%s%s%s", substr($0, 1, i - 1), to, substr($0, i + length(from)) }' \
    "$BIN" > "$MUTD/status-obligations.sh" || { t_fail "mutation target not found: $1"; return 1; }
  cmp -s "$BIN" "$MUTD/status-obligations.sh" && { t_fail "mutation changed nothing: $1"; return 1; }
  return 0
}
redproof() { # <label> <case function> <from> <to>
  mutate "$3" "$4" || return 0
  _v="$("$2" "$MUTD/status-obligations.sh")"
  [ "$_v" != ok ] && t_pass || t_fail "$1: the broken script still passed"
}

# ── the five fixtures ───────────────────────────────────────────────────────────────────────────────
case_sessions() { X="$1"; fresh
  ev 2026-10-06T01:00:00Z session.start S1; ev 2026-10-06T01:00:00Z session.start S2; ev 2026-10-06T01:58:00Z session.start S3
  ev 2026-10-06T01:01:00Z tool.background.start S1:T1 '{"tool":"Monitor"}'; ev 2026-10-06T01:01:00Z tool.background.start S1:T3 '{"tool":"Workflow"}'
  ev 2026-10-06T01:01:00Z tool.background.start S2:T2 '{"tool":"Monitor"}'
  printf '[{"sessionId":"S2","pid":1}]' > "$FIX/sessions.json"; printf '[]' > "$FIX/agents.json"; rec >/dev/null
  chk "a session the registry no longer lists is closed" closed "$(cur session:S1 state)"
  chk "closed_by says reconcile" reconcile "$(cur session:S1 closed_by)"
  chk "a live session stays open" open "$(cur session:S2 state)"
  chk "a session younger than the grace is not judged" open "$(cur session:S3 state)"
  chk "its Monitor is abandoned with it" abandoned "$(cur tool.background:S1:T1 state)"
  chk "abandoned by reconcile too" reconcile "$(cur tool.background:S1:T1 closed_by)"
  chk "a Workflow outlives its dead session" open "$(cur tool.background:S1:T3 state)"
  chk "a live session's Monitor stays open" open "$(cur tool.background:S2:T2 state)"
  chk "the ledger names the source" sessions "$(jq -r 'select(.obligation == "session:S1" and .to == "closed") | .source' "$OB/ledger.jsonl")"
  chk "and carries no event id" "" "$(jq -r 'select(.obligation == "session:S1" and .to == "closed") | .event' "$OB/ledger.jsonl")"
  chk "the source says it answered" true "$(src sessions ok)"
  verdict; }
case_agents() { X="$1"; fresh
  ev 2026-10-06T01:00:00Z agent.spawn a953054c '{"session_id":"S2"}'; ev 2026-10-06T01:00:00Z agent.spawn 7e28b750 '{"session_id":"S2"}'
  ev 2026-10-06T01:00:00Z agent.spawn S9:tu1 '{"session_id":"S9"}'; ev 2026-10-06T01:00:00Z agent.spawn S2:tu2 '{"session_id":"S2"}'
  ev 2026-10-06T01:00:00Z session.start BG1
  printf '[{"sessionId":"S2","pid":1}]' > "$FIX/sessions.json"
  printf '%s' '[{"id":"a953054c","sessionId":"a953054c-1","state":"done"},{"id":"7e28b750","sessionId":"7e28b750-1","state":"blocked"},{"id":"bg","sessionId":"BG1","state":"working"},{"pid":3,"sessionId":"S2","status":"idle"}]' > "$FIX/agents.json"
  rec >/dev/null
  chk "a dispatched agent the list says is done is closed" closed "$(cur agent:a953054c state)"
  chk "by reconcile" reconcile "$(cur agent:a953054c closed_by)"
  chk "a blocked agent is still running" open "$(cur agent:7e28b750 state)"
  chk "a subagent unknown to the list whose owner is gone is abandoned" abandoned "$(cur agent:S9:tu1 state)"
  chk "one whose owner lives stays open" open "$(cur agent:S2:tu2 state)"
  chk "a background session only the agents list knows is not dead" open "$(cur session:BG1 state)"
  chk "the read is one argv" "agents --json --all" "$(head -n 1 "$FIX/claude.calls")"
  verdict; }
case_pr() { X="$1"; fresh
  ev 2026-10-06T01:00:00Z pr.opened VytCepas/harbor#9; ev 2026-10-06T01:00:00Z pr.opened VytCepas/harbor#10; ev 2026-10-06T01:00:00Z pr.opened VytCepas/harbor#11
  printf MERGED > "$FIX/pr-9"; printf OPEN > "$FIX/pr-10"; printf CLOSED > "$FIX/pr-11"; rec >/dev/null
  chk "a merged PR is closed" closed "$(cur pr:VytCepas/harbor#9 state)"
  chk "by reconcile" reconcile "$(cur pr:VytCepas/harbor#9 closed_by)"
  chk "an open PR stays open" open "$(cur pr:VytCepas/harbor#10 state)"
  chk "a closed PR is closed" closed "$(cur pr:VytCepas/harbor#11 state)"
  chk "gh got the repo and number as separate arguments" "pr view 9 -R VytCepas/harbor --json state --jq .state" "$(grep '^pr view 9 ' "$FIX/gh.calls")"
  chk "one read per row" 3 "$(calls gh)"
  busk() { cat "$EV"/*.jsonl | jq -r --arg s "$1" 'select(.src == "status-obligations" and .subject == $s) | .kind' | tr '\n' ' '; }
  chk "the merge it saw is published as pr.merged (harbor#1367)" "pr.merged " "$(busk VytCepas/harbor#9)"
  chk "...a close as pr.closed" "pr.closed " "$(busk VytCepas/harbor#11)"
  chk "...and an open PR as nothing" "" "$(busk VytCepas/harbor#10)"
  ev 2026-10-06T02:30:00Z pr.merged VytCepas/harbor#9; NOW=2026-10-06T03:00:00Z; rec >/dev/null
  chk "a late merge event does not reopen it" closed "$(cur pr:VytCepas/harbor#9 state)"
  chk "...and a row already closed is not published again" "pr.merged " "$(busk VytCepas/harbor#9)"
  verdict; }
case_run() { X="$1"; fresh
  ev 2026-10-06T01:00:00Z ci.job.start VytCepas/harbor:7:suites; ev 2026-10-06T01:00:00Z ci.job.start VytCepas/harbor:8:suites; ev 2026-10-06T01:00:00Z ci.job.start VytCepas/harbor:9:lint
  printf '%s' '{"status":"completed","jobs":[]}' > "$FIX/run-7.json"
  printf '%s' '{"status":"in_progress","jobs":[{"name":"suites","status":"in_progress"}]}' > "$FIX/run-8.json"
  printf '%s' '{"status":"in_progress","jobs":[{"name":"lint","status":"completed"},{"name":"suites","status":"queued"}]}' > "$FIX/run-9.json"; rec >/dev/null
  chk "a completed run closes its job" closed "$(cur ci:VytCepas/harbor:7:suites state)"
  chk "by reconcile" reconcile "$(cur ci:VytCepas/harbor:7:suites closed_by)"
  chk "a running job stays open" open "$(cur ci:VytCepas/harbor:8:suites state)"
  chk "a job done inside a running run is closed" closed "$(cur ci:VytCepas/harbor:9:lint state)"
  chk "gh got the run id and repo separately" "run view 7 -R VytCepas/harbor --json status,jobs" "$(grep '^run view 7 ' "$FIX/gh.calls")"
  verdict; }
case_sweep() { X="$1"; fresh
  AT=$((NOWE - 3600))
  { printf '%s\n' '{"verdict":"RISK","class":"worktree","subject":"harbor-wt-old (merged)","reason":"x","action":""}'
    printf '{"verdict":"DECIDE","class":"stash","subject":"%s/port/harbor: 1 stash","reason":"x","action":""}\n' "$HOME"
    printf '%s\n' '{"verdict":"KEEP","class":"sacred","subject":"backups","reason":"x","action":""}' '{"verdict":"RECLAIM","class":"ds-store","subject":"5 files","reason":"x","action":""}'; } | sweep_rows "$AT"
  rec >/dev/null
  chk "a RISK row becomes a leftover" open "$(cur 'leftover:worktree:harbor-wt-old (merged)' state)"
  chk "a DECIDE row becomes one, with \$HOME as ~" open "$(cur 'leftover:stash:~/port/harbor: 1 stash' state)"
  chk "KEEP and RECLAIM rows do not" 2 "$(jq '.obligations | length' "$OB/current.json")"
  chk "the operator owns it" operator "$(cur 'leftover:worktree:harbor-wt-old (merged)' owner)"
  chk "the register's 7d deadline from the run clock" 2026-10-13T02:00:00Z "$(cur 'leftover:worktree:harbor-wt-old (merged)' deadline_ts)"
  chk "no row carries the home path" 0 "$(grep -c "$HOME" "$OB/current.json" "$OB/ledger.jsonl" | awk -F: '{s += $2} END {print s + 0}')"
  _n="$(lines)"; rec >/dev/null; chk "the same record again adds nothing" "$_n" "$(lines)"
  { printf '{"verdict":"DECIDE","class":"stash","subject":"%s/port/harbor: 1 stash","reason":"x","action":""}\n' "$HOME"; } | sweep_rows "$AT"; rec >/dev/null
  chk "a row gone from the next record is closed" closed "$(cur 'leftover:worktree:harbor-wt-old (merged)' state)"
  chk "by reconcile" reconcile "$(cur 'leftover:worktree:harbor-wt-old (merged)' closed_by)"
  chk "the ledger names the sweep" sweep "$(jq -r 'select(.to == "closed") | .source' "$OB/ledger.jsonl")"
  chk "a row still in the record stays open" open "$(cur 'leftover:stash:~/port/harbor: 1 stash' state)"
  verdict; }

t_section "sessions: a dead session closes, its background work is abandoned"
t_eq "the real script" ok "$(case_sessions "$BIN")"
redproof "sessions" case_sessions 'if age($r) >= $grace and dead($r.subject) then' 'if false then'
redproof "owner-session" case_sessions 'if $k.on_stop == "abandon" and' 'if $k.on_stop == "never" and'

t_section "claude-agents: the list's state closes an agent, and a background session is not dead"
t_eq "the real script" ok "$(case_agents "$BIN")"
redproof "claude-agents terminal state" case_agents '["done", "stopped", "failed"' '["nope", "stopped", "failed"'
redproof "claude-agents keeps a listed session alive" case_agents '.sessionId == $sid and ((.state' '.sessionId == $sid and false and ((.state'

t_section "gh-pr: gh's PR state closes the row"
t_eq "the real script" ok "$(case_pr "$BIN")"
redproof "gh-pr" case_pr 'IN("MERGED", "CLOSED") then' 'IN("NEVER") then'

t_section "gh-run: gh run view closes the job"
t_eq "the real script" ok "$(case_run "$BIN")"
redproof "gh-run" case_run '== "completed" then {to: "closed", source: "gh-run"}' '== "never" then {to: "closed", source: "gh-run"}'

t_section "sweep: a record's RISK and DECIDE rows open leftovers, and the next record closes them"
t_eq "the real script" ok "$(case_sweep "$BIN")"
redproof "sweep opens" case_sweep '.verdict | IN("RISK", "DECIDE")' '.verdict | IN("RISK")'
redproof "sweep closes" case_sweep '(.value.subject as $s | ($names | any(.[]; . == $s)) | not)' '(.value.subject as $s | ($names | any(.[]; . == $s)) | not | not)'

# ── a row whose truth can be asked is not left overdue (the statusline's OVERDUE) ───────────────────
# A Workflow outlives its session's STOP, so a dead owner alone never closed it: two such rows sat overdue for days on the live box
# while reconcile said "nothing to flip". They go once the deadline has passed and the dead owner wrote nothing after it.
touch_at() { # <epoch> <file> — GNU date takes -d @N, BSD date -r N; touch -t reads the stamp in TZ, pinned to UTC
  _st="$(date -u -d "@$1" +%Y%m%d%H%M.%S 2>/dev/null || date -u -r "$1" +%Y%m%d%H%M.%S)"; TZ=UTC touch -t "$_st" "$2"; }
case_lapsed() { X="$1"; fresh
  DL="$(jq -n -r '"2026-10-05T04:00:00Z" | fromdateiso8601')"; mkdir -p "$FIX/tr/p"
  for _s in S1 S4 S6; do ev 2026-10-05T00:00:00Z tool.background.start "$_s:T" '{"tool":"Workflow"}'; done
  ev 2026-10-05T00:00:00Z tool.background.start S5:T '{"tool":"CronCreate"}'; ev 2026-10-06T01:30:00Z tool.background.start S7:T '{"tool":"Workflow"}'
  : > "$FIX/tr/p/S1.jsonl"; touch_at "$((DL - 3600))" "$FIX/tr/p/S1.jsonl"
  : > "$FIX/tr/p/S4.jsonl"; touch_at "$((DL + 3600))" "$FIX/tr/p/S4.jsonl"
  : > "$FIX/tr/p/S7.jsonl"; touch_at "$((DL - 3600))" "$FIX/tr/p/S7.jsonl"
  ev 2026-10-04T00:00:00Z tool.background.start S8:T '{"tool":"CronCreate"}'; : > "$FIX/tr/p/S8.jsonl"; touch_at "$((DL - 86400 + 3600))" "$FIX/tr/p/S8.jsonl"
  printf '[{"sessionId":"S6","pid":1}]' > "$FIX/sessions.json"; printf '[]' > "$FIX/agents.json"; rec >/dev/null
  chk "a dead owner that wrote after the deadline but has been quiet 24h+: abandoned" abandoned "$(cur tool.background:S8:T state)"
  chk "a Workflow past its deadline, owner dead, transcript quiet since: abandoned" abandoned "$(cur tool.background:S1:T state)"
  chk "by reconcile" reconcile "$(cur tool.background:S1:T closed_by)"
  chk "the ledger names the owner-session source" owner-session "$(jq -r 'select(.obligation == "tool.background:S1:T" and .to == "abandoned") | .source' "$OB/ledger.jsonl")"
  chk "one whose owner wrote after the deadline stays open" overdue "$(cur tool.background:S4:T state)"
  chk "a dead owner with no transcript at all is quiet: abandoned" abandoned "$(cur tool.background:S5:T state)"
  chk "a live owner keeps its overdue Workflow" overdue "$(cur tool.background:S6:T state)"
  chk "a Workflow still inside its deadline outlives the dead owner" open "$(cur tool.background:S7:T state)"
  verdict; }
case_approval_pr() { X="$1"; fresh
  for _n in 9 10 11 12; do ev 2026-10-06T00:00:00Z approval.open "merge-$_n" "{\"link\":\"https://github.com/VytCepas/harbor/pull/$_n\"}"; done
  ev 2026-10-06T00:00:00Z approval.open "dns-change"
  printf MERGED > "$FIX/pr-9"; printf OPEN > "$FIX/pr-10"; printf CLOSED > "$FIX/pr-11"; printf OPEN > "$FIX/pr-12"
  mkdir -p "$HOME/.local/state/harbor/approvals"; printf '{"id":"merge-12","closed":true}\n' > "$HOME/.local/state/harbor/approvals/queue.jsonl"
  printf '[]' > "$FIX/sessions.json"; printf '[]' > "$FIX/agents.json"; rec >/dev/null
  chk "an approval whose PR is merged is closed" closed "$(cur approval:merge-9 state)"
  chk "by reconcile" reconcile "$(cur approval:merge-9 closed_by)"
  chk "the ledger names gh-pr" gh-pr "$(jq -r 'select(.obligation == "approval:merge-9" and .to == "closed") | .source' "$OB/ledger.jsonl")"
  chk "one whose PR is open stays open" open "$(cur approval:merge-10 state)"
  chk "one whose PR was closed unmerged is closed" closed "$(cur approval:merge-11 state)"
  chk "the queue still closes an approval" closed "$(cur approval:merge-12 state)"
  chk "and says so" approval-queue "$(jq -r 'select(.obligation == "approval:merge-12" and .to == "closed") | .source' "$OB/ledger.jsonl")"
  chk "an approval that names no PR stays open" open "$(cur approval:dns-change state)"
  chk "gh got the repo and number as separate arguments" "pr view 9 -R VytCepas/harbor --json state --jq .state" "$(grep '^pr view 9 ' "$FIX/gh.calls")"
  chk "gh is asked about the four PRs, not the approval without one" 4 "$(calls gh)"
  rm -f "$HOME/.local/state/harbor/approvals/queue.jsonl"
  verdict; }
case_approval_silent() { X="$1"; fresh
  ev 2026-10-06T00:00:00Z approval.open merge-9 '{"link":"https://github.com/VytCepas/harbor/pull/9"}'
  printf '[]' > "$FIX/sessions.json"; printf '[]' > "$FIX/agents.json"; rec >/dev/null   # no pr-9: gh exits 1
  chk "a gh that does not answer leaves the approval open" open "$(cur approval:merge-9 state)"
  chk "and gh-pr says it did not answer" false "$(src gh-pr ok)"
  verdict; }
t_section "owner-session: a Workflow whose dead owner is quiet past its deadline is abandoned"
t_eq "the real script" ok "$(case_lapsed "$BIN")"
redproof "outlives never lapses" case_lapsed '(($r.outlives | not) or lapsed($r))' '(($r.outlives | not))'
redproof "lapse ignores the owner's last write" case_lapsed '$w <= ($r.deadline_ts | fromdateiso8601) or' '$w <= $now or'
redproof "lapse ignores the deadline" case_lapsed '$r.deadline_ts != "" and ($r.deadline_ts | fromdateiso8601) < $now' '$r.deadline_ts != ""'
redproof "quiet owner never lapses" case_lapsed '$now - $w >= $quiet' 'false'
redproof "transcripts are never read" case_lapsed '_tm="$(fs_mtime "$_tf")"; [ -z "$_tm" ]' '_tm=""; [ -z "$_tm" ]'

t_section "approval: a merged or closed PR closes the approval waiting on it"
t_eq "the real script" ok "$(case_approval_pr "$BIN")"
redproof "approval gh-pr verdict" case_approval_pr 'answers[$r | pr_key] // "") | IN("MERGED", "CLOSED"))' 'answers[$r | pr_key] // "") | IN("NEVER"))'
redproof "approval PR comes from the link" case_approval_pr 'capture("^https://github.com/(?<r>' 'capture("^https://example.invalid/(?<r>'
t_eq "gh silent: real script" ok "$(case_approval_silent "$BIN")"
redproof "approval gh silence" case_approval_silent 'answers[$r | pr_key] // "") | IN(' 'answers[$r | pr_key] // "MERGED") | IN('

# ── a silent source flips nothing ───────────────────────────────────────────────────────────────────
silent_setup() { X="$1"; fresh
  ev 2026-10-06T01:00:00Z session.start S1; ev 2026-10-06T01:01:00Z tool.background.start S1:T1 '{"tool":"Monitor"}'
  ev 2026-10-06T01:00:00Z pr.opened VytCepas/harbor#9; ev 2026-10-06T01:00:00Z ci.job.start VytCepas/harbor:7:suites
  ev 2026-10-06T01:00:00Z agent.spawn S1:tu1 '{"session_id":"S1"}'; }
still_open() { # every row the setup made is untouched
  for _id in session:S1 tool.background:S1:T1 pr:VytCepas/harbor#9 ci:VytCepas/harbor:7:suites agent:S1:tu1; do chk "$_id still open" open "$(cur "$_id" state)"; done; }
case_silent_sessions() { silent_setup "$1"; printf '[]' > "$FIX/agents.json"   # no sessions.json: the stub exits 1
  rec >/dev/null; still_open
  chk "sessions says it did not answer" false "$(src sessions ok)"
  chk "and why" "exited 1" "$(src sessions reason)"
  verdict; }
case_silent_agents() { silent_setup "$1"; printf '[]' > "$FIX/sessions.json"      # sessions answer: S1 is not there; agents do not
  rec >/dev/null; still_open
  chk "claude-agents says it did not answer" false "$(src claude-agents ok)"
  chk "sessions did" true "$(src sessions ok)"
  verdict; }
case_silent_gh() { silent_setup "$1"; printf '[{"sessionId":"S1","pid":1}]' > "$FIX/sessions.json"; printf '[]' > "$FIX/agents.json"   # no pr-9, no run-7
  rec >/dev/null; still_open
  chk "gh-pr says it did not answer" false "$(src gh-pr ok)"
  chk "and how many reads failed" "1 of 1 reads failed (last: exited 1)" "$(src gh-pr reason)"
  chk "gh-run says it did not answer" false "$(src gh-run ok)"
  verdict; }
case_silent_sweep() { X="$1"; fresh
  { printf '%s\n' '{"verdict":"RISK","class":"worktree","subject":"old","reason":"x","action":""}'; } | sweep_rows "$((NOWE - 3600))"; rec >/dev/null
  chk "a leftover is opened" open "$(cur leftover:worktree:old state)"
  rm -f "$FIX/sweep/.helm-sweep"; rec >/dev/null
  chk "a record that cannot be read closes nothing" open "$(cur leftover:worktree:old state)"
  chk "and says so" "no sweep record" "$(src sweep reason)"
  { printf '%s\n' '{"verdict":"RISK","class":"worktree","subject":"other","reason":"x","action":""}'; } | sweep_rows "$((NOWE - 200000))"; rec >/dev/null
  chk "a stale record opens nothing" 1 "$(jq '.obligations | length' "$OB/current.json")"
  chk "a stale record closes nothing" open "$(cur leftover:worktree:old state)"
  chk "the stale record is named" "the sweep record is 55h old" "$(src sweep reason)"
  verdict; }
t_section "silence: a source that does not answer flips nothing and says why"
t_eq "sessions: real script" ok "$(case_silent_sessions "$BIN")"
redproof "sessions silence" case_silent_sessions '($src.sessions.ok // false) and ($src["claude-agents"].ok // false) and' ''
t_eq "claude-agents: real script" ok "$(case_silent_agents "$BIN")"
redproof "claude-agents silence" case_silent_agents '($src["claude-agents"].ok // false) and (alive($sid) | not)' '(alive($sid) | not)'
t_eq "gh: real script" ok "$(case_silent_gh "$BIN")"
redproof "gh-pr silence" case_silent_gh '.answers[$r.subject] // "")' '.answers[$r.subject] // "MERGED")'
redproof "gh-run silence" case_silent_gh '$src["gh-run"].answers[$r.subject] // "") == "completed"' '$src["gh-run"].answers[$r.subject] // "completed") == "completed"'
t_eq "sweep: real script" ok "$(case_silent_sweep "$BIN")"
redproof "sweep silence" case_silent_sweep '($src.sweep.ok // false) | not)' 'false)'

t_section "silence: a hang is bounded, a bad answer is refused, a spent budget reads nothing"
for _s in sessions claude gh; do
  silent_setup "$BIN"; printf '[{"sessionId":"S1","pid":1}]' > "$FIX/sessions.json"; printf '[]' > "$FIX/agents.json"; printf MERGED > "$FIX/pr-9"
  case "$_s" in sessions) printf '[]' > "$FIX/sessions.json" ;; claude) printf '[]' > "$FIX/sessions.json" ;; esac
  : > "$FIX/$_s.hang"; READ_TO=1; _t0="$(date +%s)"; out="$(rec)"; rc=$?; _dt=$(($(date +%s) - _t0))
  t_eq "a hung $_s read does not fail the run" 0 "$rc"
  t_eq "a hung $_s read is bounded (took ${_dt}s)" yes "$([ "$_dt" -lt 12 ] && echo yes || echo no)"
  case "$_s" in sessions) _k=sessions ;; claude) _k=claude-agents ;; gh) _k=gh-pr ;; esac
  t_eq "the $_k source says it timed out" false "$(src "$_k" ok)"
  t_has "with the reason" "$(src "$_k" reason)" "timed out after 1s"
  t_eq "the session row is untouched by the $_s hang" open "$(cur session:S1 state)"
done
# `exec sleep` above is the easy hang: the kill reaches the sleep. A stub that FORKS (`sleep 30` as a child of the stub's sh) keeps
# the read's stdout open after the kill, and a pipe reader waits for it: the review measured 27s for a 2s limit (harbor#1115).
case_hang_grandchild() { silent_setup "$1"; printf '[]' > "$FIX/agents.json"; printf '[]' > "$FIX/sessions.json"; printf MERGED > "$FIX/pr-9"
  for _h in $HANG2; do : > "$FIX/$_h.hang2"; done; READ_TO=1; BUDGET=100
  _t0="$(date +%s)"; rec >/dev/null; _dt=$(($(date +%s) - _t0))
  chk "the forking reads together stay under 15s (took ${_dt}s)" yes "$([ "$_dt" -lt 15 ] && echo yes || echo no)"
  chk "sessions says it timed out after 1s" "timed out after 1s" "$(src sessions reason)"
  chk "and flips nothing" open "$(cur session:S1 state)"
  verdict; }
HANG2="sessions claude gh"; t_eq "a hang that forks is bounded by the limit, not by its child: real script" ok "$(case_hang_grandchild "$BIN")"
HANG2="sessions"   # one source is enough to go red, and each unbounded read costs 30s
redproof "grandchild hang" case_hang_grandchild 'bounded() { # <seconds> <command> [args…] — its stdout; non-zero when it failed or ran over' \
  'bounded() { _bs="$1"; shift; perl -e '"'"'alarm shift; exec @ARGV or exit 127'"'"' "$_bs" "$@"; }; bounded_fixed() { # the pre-fix body is above, kept for the proof; the fixed one follows, unused'
silent_setup "$BIN"; printf 'not json' > "$FIX/sessions.json"; printf '[]' > "$FIX/agents.json"; rec >/dev/null
t_eq "a registry read that is not a list is refused" false "$(src sessions ok)"; t_eq "and flips nothing" open "$(cur session:S1 state)"
silent_setup "$BIN"; printf '{"a":1}' > "$FIX/agents.json"; printf '[]' > "$FIX/sessions.json"; rec >/dev/null
t_eq "an agents read that is not a list is refused" false "$(src claude-agents ok)"; t_eq "and flips nothing" open "$(cur session:S1 state)"
silent_setup "$BIN"; printf '[]' > "$FIX/sessions.json"; printf '[]' > "$FIX/agents.json"; printf MERGED > "$FIX/pr-9"; BUDGET=0; rec >/dev/null
t_eq "a spent budget reads nothing" 0 "$(($(calls gh) + $(calls claude) + $(calls sessions)))"
t_eq "and says so" "read budget spent" "$(src sessions reason)"; t_eq "and flips nothing" open "$(cur pr:VytCepas/harbor#9 state)"
silent_setup "$BIN"; printf 'MAYBE' > "$FIX/pr-9"; printf '[{"sessionId":"S1","pid":1}]' > "$FIX/sessions.json"; printf '[]' > "$FIX/agents.json"; rec >/dev/null
t_eq "a PR state gh does not define is no answer" open "$(cur pr:VytCepas/harbor#9 state)"

t_section "shape: sources.json is §3's map, idempotent, and nothing is read when nothing is open"
fresh; rec >/dev/null
t_eq "an empty ledger reads no source" 0 "$(($(calls gh) + $(calls claude) + $(calls sessions)))"
t_eq "sources.json holds every source" "approval-queue,claude-agents,gh-pr,gh-run,sessions,sweep" "$(jq -r 'keys | join(",")' "$OB/sources.json")"
t_eq "a source nobody asked is ok" true "$(src gh-pr ok)"
t_eq "each entry is ok, reason, ts" "ok,reason,ts" "$(jq -r '.sessions | keys_unsorted | join(",")' "$OB/sources.json")"
t_eq "ts is the run clock" "$NOW" "$(src sessions ts)"
t_eq "current.json keeps its keys" "generated_ts,obligations" "$(jq -r 'keys_unsorted | join(",")' "$OB/current.json")"
case_pr "$BIN" >/dev/null; _n="$(lines)"; rec >/dev/null
t_eq "a second reconcile adds no transition" "$_n" "$(lines)"
t_eq "every ledger line parses" 0 "$(jq -c . "$OB/ledger.jsonl" >/dev/null 2>&1; echo $?)"
t_eq "a reconcile closes the row once" 1 "$(jq -r 'select(.obligation == "pr:VytCepas/harbor#9" and .to == "closed")' "$OB/ledger.jsonl" | jq -s 'length')"
fresh; X="$BIN"; ev 2026-10-06T01:00:00Z pr.opened VytCepas/harbor#9; ev 2026-10-06T01:10:00Z pr.merged VytCepas/harbor#9; rec >/dev/null
t_eq "a row an event closed is not asked about" 0 "$(calls gh)"
t_eq "and keeps the event's closer" e2 "$(cur pr:VytCepas/harbor#9 closed_by)"

t_section "kill: killed between the ledger and current.json, the next run repairs current.json"
fresh; X="$BIN"; ev 2026-10-06T01:00:00Z pr.opened VytCepas/harbor#9; printf MERGED > "$FIX/pr-9"
FAULT=after-reconcile-ledger; ( rec ) >/dev/null 2>&1; rc=$?; FAULT=""
t_eq "killed after the ledger append" 137 "$rc"
t_eq "the ledger says closed" closed "$(jq -r 'select(.obligation == "pr:VytCepas/harbor#9") | .to' "$OB/ledger.jsonl" | tail -n 1)"
t_eq "current.json still says open" open "$(cur pr:VytCepas/harbor#9 state)"
_n="$(lines)"; ONOVER=off; run "$BIN" fold >/dev/null; ONOVER=""
t_eq "a plain fold repairs current.json from the ledger" closed "$(cur pr:VytCepas/harbor#9 state)"
t_eq "and doubles nothing" "$_n" "$(lines)"

t_section "when a row goes overdue: the fold asks the sources"
fresh; ev 2026-10-02T01:00:00Z pr.opened VytCepas/harbor#9; printf MERGED > "$FIX/pr-9"; ONOVER=off
out="$(run "$BIN" fold)"; t_eq "with the trigger off the row goes overdue" overdue "$(cur pr:VytCepas/harbor#9 state)"
t_eq "and no source is read" 0 "$(calls gh)"; t_eq "and no source map is written" no "$([ -e "$OB/sources.json" ] && echo yes || echo no)"
fresh; ev 2026-10-02T01:00:00Z pr.opened VytCepas/harbor#9; printf MERGED > "$FIX/pr-9"
out="$(run "$BIN" fold)"
t_eq "a row that goes overdue is reconciled in the same run" closed "$(cur pr:VytCepas/harbor#9 state)"
t_eq "by reconcile" reconcile "$(cur pr:VytCepas/harbor#9 closed_by)"
t_eq "and the ledger kept the overdue step" overdue "$(jq -r 'select(.obligation == "pr:VytCepas/harbor#9") | .to' "$OB/ledger.jsonl" | sed -n 2p)"
t_has "the run says why it looked" "$out" "went overdue"
fresh; ev 2026-10-06T01:00:00Z pr.opened VytCepas/harbor#9; printf MERGED > "$FIX/pr-9"; run "$BIN" fold >/dev/null
t_eq "a fold with nothing overdue reads no source" 0 "$(calls gh)"
t_eq "and leaves the row open" open "$(cur pr:VytCepas/harbor#9 state)"
t_eq "usage: an unknown mode is refused" 2 "$(run "$BIN" nope >/dev/null; echo $?)"

t_section "a reconcile that fails marks the sources stale and fails the run (harbor#1115)"
# reconcile_pass's status used to be dropped, so surface_pass published the PREVIOUS sources.json as this run's answer and the run
# exited 0. A directory where the sources tmp file goes makes the pass's last step fail, after it has read every source.
case_reconcile_fails() { X="$1"; fresh
  ev 2026-10-06T01:00:00Z pr.opened VytCepas/harbor#9; printf OPEN > "$FIX/pr-9"; printf '[]' > "$FIX/sessions.json"; printf '[]' > "$FIX/agents.json"
  sweep_rows "$NOWE" < /dev/null   # a sweep record that answers, so a clean run has no unread source
  rec >/dev/null
  chk "a clean reconcile leaves nothing unread" false "$(jq '.unread' "$HOME/.claude/cache/status-obligations.json")"
  chk "a clean reconcile writes no stale mark" false "$(jq 'has("reconcile")' "$OB/sources.json")"
  mkdir "$OB/.sources.tmp"; rc=0; rec >/dev/null || rc=$?
  chk "the run exits 1, not 0" 1 "$rc"
  chk "sources.json says the reconcile failed" false "$(src reconcile ok)"
  chk "...and that the other entries are old" 1 "$(src reconcile reason | grep -c 'earlier run')"
  chk "the entries it keeps are the previous run's" true "$(src gh-pr ok)"
  chk "the statusline cache says a source is unread (⧗?)" true "$(jq '.unread' "$HOME/.claude/cache/status-obligations.json")"
  chk "--json lists it as a source that did not answer" false "$(env HARBOR_OBLIGATION_DIR="$OB" HARBOR_STATUS_OBLIGATION_NOW="$NOW" sh "$X" show --json 2>/dev/null | jq '.sources.reconcile.ok')"
  rmdir "$OB/.sources.tmp"; rc=0; rec >/dev/null || rc=$?
  chk "the next clean run exits 0" 0 "$rc"
  chk "...and the stale mark is gone" false "$(jq 'has("reconcile")' "$OB/sources.json")"
  chk "...and the cache is no longer unread" false "$(jq '.unread' "$HOME/.claude/cache/status-obligations.json")"
  verdict; }
t_eq "real script" ok "$(case_reconcile_fails "$BIN")"
redproof "reconcile failure ignored" case_reconcile_fails 'reconcile) reconcile_pass || _rr=1 ;;' 'reconcile) reconcile_pass ;;'

t_section "inside fleet-snapshot: it runs, and its failure never fails the job"
FSN="$W/fsn"; fresh; mkdir -p "$FSN/cache" "$FSN/home" "$FSN/scratch" "$FSN/other"; X="$BIN"; FSN_TO=""; FSN_BUDGET=""
# The refresher's other jobs call gh and launchctl too; they get their own poison, so `touched` stays a verdict on this script.
for _c in gh claude launchctl; do printf '#!/bin/sh\nexit 1\n' > "$FSN/other/$_c"; chmod +x "$FSN/other/$_c"; done
printf '#!/bin/sh\necho "[{}]"\n' > "$FSN/orch"; chmod +x "$FSN/orch"
ev 2026-10-06T01:00:00Z pr.opened VytCepas/harbor#9; printf MERGED > "$FIX/pr-9"
fsn() { # <obligation dir> — the real refresher against a fake producer, every other job pinned to nothing
  env CLAUDE_CONFIG_DIR="$FSN" HARBOR_CACHE_DIR="$FSN/cache" HARBOR_ORCH_BIN="$FSN/orch" HARBOR_FLEET_FILE="$FSN/fleet.yaml" \
    HARBOR_CLEAN_HOME="$FSN/home" HARBOR_CLEAN_SCRATCH="$FSN/scratch" HARBOR_CLEAN_GH=none \
    HARBOR_EVENT_DIR="$EV" HARBOR_OBLIGATION_DIR="$1" HARBOR_STATUS_OBLIGATION_NOW="$NOW" HARBOR_STATUS_OBLIGATION_KINDS="$KINDS" \
    HARBOR_STATUS_OBLIGATION_GH="$STUBS/gh" HARBOR_STATUS_OBLIGATION_CLAUDE="$STUBS/claude" HARBOR_STATUS_OBLIGATION_SESSIONS="$STUBS/sessions" \
    HARBOR_STATUS_OBLIGATION_HOUSEKEEPING="$FSN/none.jsonl" PATH="$FSN/other:$PATH" \
    ${FSN_TO:+HARBOR_STATUS_OBLIGATION_READ_TIMEOUT="$FSN_TO"} ${FSN_BUDGET:+HARBOR_STATUS_OBLIGATION_BUDGET="$FSN_BUDGET"} \
    sh "$T_ROOT/bin/fleet-snapshot-refresh.sh" >/dev/null 2>&1
}
t_eq "no real gh, claude or launchctl was touched before the refresher ran" no "$([ -e "$T_TMP/touched" ] && echo yes || echo no)"
fsn "$OB"; rc=$?
t_eq "the refresher exits 0" 0 "$rc"
t_eq "it wrote the snapshot" yes "$([ -s "$FSN/cache/fleet-snapshot.json" ] && echo yes || echo no)"
t_eq "and reconciled the ledger inside the same run" closed "$(cur pr:VytCepas/harbor#9 state)"
: > "$W/notdir"; rm -f "$FSN/cache/fleet-snapshot.json"; fsn "$W/notdir/ob"; rc=$?
t_eq "a reconcile that cannot write its state does not fail the job" 0 "$rc"
t_eq "and the snapshot is still written" yes "$([ -s "$FSN/cache/fleet-snapshot.json" ] && echo yes || echo no)"
# The run above published #9's merge at the wall clock (harbor#1367), after this suite's pinned NOW: a fresh ledger
# replaying it is a different case, so the next two cases use PRs of their own.
ev 2026-10-06T01:00:00Z pr.opened VytCepas/harbor#21; ev 2026-10-06T01:00:00Z pr.opened VytCepas/harbor#22
rm -f "$FSN/cache/fleet-snapshot.json"; : > "$FIX/gh.hang"; rm -rf "$OB"; mkdir -p "$OB"
_t0="$(date +%s)"; FSN_TO=1; FSN_BUDGET=2; fsn "$OB"; rc=$?; _dt=$(($(date +%s) - _t0))
t_eq "a hung gh does not fail the job" 0 "$rc"
t_eq "and costs it no more than the budget (took ${_dt}s)" yes "$([ "$_dt" -lt 25 ] && echo yes || echo no)"
t_eq "the row the hung read could not judge stays open" open "$(cur pr:VytCepas/harbor#21 state)"

t_section "the INSTALLED layout: runtime-install ships the script and its register, and launchd's copy folds, caches and files a receipt (harbor#1115)"
# Every case above runs the checkout, where ../CONTRACTS sits beside bin/ and HARBOR_STATUS_OBLIGATION_KINDS is set. launchd
# runs ~/.claude/bin/fleet-snapshot-refresh.sh, which `>/dev/null || true`s this script: a copy that is not there, or cannot find its
# register, fails with no output, no cache and no receipt. So this installs into a sandbox dir and runs THAT, with no KINDS knob.
INST="$W/inst"; ICACHE="$W/icache"; IOB="$W/iob"; mkdir -p "$INST"; printf '{}' > "$INST/settings.json"   # the fixtures above stay: no `fresh`, which wipes $W
env -u CLAUDE_CONFIG_DIR sh "$T_ROOT/bin/runtime-install.sh" --apply --dir "$INST" >/dev/null 2>&1
t_eq "runtime-install ships status-obligations.sh" yes "$([ -x "$INST/bin/status-obligations.sh" ] && echo yes || echo no)"
t_eq "...and its register, beside it in bin/" yes "$([ -f "$INST/bin/obligation-kinds.tsv" ] && cmp -s "$KINDS" "$INST/bin/obligation-kinds.tsv" && echo yes || echo no)"
t_eq "...with no new top-level CONTRACTS/ in the config dir" no "$([ -e "$INST/CONTRACTS" ] && echo yes || echo no)"
rm -f "$FIX/gh.hang"; printf MERGED > "$FIX/pr-22"   # the bus still holds the PR opened above
inst_run() { # <config dir> — the installed refresher, every source a stub, no register knob
  env CLAUDE_CONFIG_DIR="$1" HARBOR_CACHE_DIR="$ICACHE" HARBOR_ORCH_BIN="$FSN/orch" HARBOR_FLEET_FILE="$FSN/fleet.yaml" \
    HARBOR_CLEAN_HOME="$FSN/home" HARBOR_CLEAN_SCRATCH="$FSN/scratch" HARBOR_CLEAN_GH=none \
    HARBOR_EVENT_DIR="$EV" HARBOR_OBLIGATION_DIR="$IOB" HARBOR_STATUS_OBLIGATION_NOW="$NOW" \
    HARBOR_STATUS_OBLIGATION_GH="$STUBS/gh" HARBOR_STATUS_OBLIGATION_CLAUDE="$STUBS/claude" HARBOR_STATUS_OBLIGATION_SESSIONS="$STUBS/sessions" \
    HARBOR_STATUS_OBLIGATION_HOUSEKEEPING="$FSN/none.jsonl" PATH="$FSN/other:$PATH" \
    sh "$1/bin/fleet-snapshot-refresh.sh" >/dev/null 2>&1
}
rm -rf "$IOB" "$ICACHE"; inst_run "$INST"; rc=$?
t_eq "the installed refresher exits 0" 0 "$rc"
t_eq "the ledger appears under HARBOR_OBLIGATION_DIR" yes "$([ -s "$IOB/ledger.jsonl" ] && echo yes || echo no)"
t_eq "the open PR was folded and then reconciled closed" closed "$(jq -r '.obligations[] | select(.id == "pr:VytCepas/harbor#22") | .state' "$IOB/current.json" 2>/dev/null)"
t_eq "the statusline cache appears" yes "$([ -s "$ICACHE/status-obligations.json" ] && echo yes || echo no)"
t_eq "the receipt appears" yes "$([ -s "$ICACHE/checks/status.obligations.json" ] && echo yes || echo no)"
t_eq "...and is green" green "$(jq -r '.verdict // .status // .state // empty' "$ICACHE/checks/status.obligations.json" 2>/dev/null)"
# RED: a register missing from the installed layout is the state before this fix; it leaves exactly the silence the review measured.
rm -rf "$IOB" "$ICACHE"; mv "$INST/bin/obligation-kinds.tsv" "$INST/bin/kinds.away"; inst_run "$INST"; rc=$?
t_eq "RED: with no register beside the script the refresher still exits 0 (the call is hidden)" 0 "$rc"
t_eq "RED: ...and nothing is written: no ledger, no cache, no receipt" "no no no" \
  "$([ -e "$IOB/ledger.jsonl" ] && echo yes || echo no) $([ -e "$ICACHE/status-obligations.json" ] && echo yes || echo no) $([ -e "$ICACHE/checks/status.obligations.json" ] && echo yes || echo no)"
mv "$INST/bin/kinds.away" "$INST/bin/obligation-kinds.tsv"
rm -rf "$IOB" "$ICACHE"; rm -f "$INST/bin/status-obligations.sh"; inst_run "$INST"
t_eq "RED: with the script not installed there is no ledger either" no "$([ -e "$IOB/ledger.jsonl" ] && echo yes || echo no)"

t_section "hermetic: no real gh, claude or launchctl ran anywhere in this suite"
t_eq "the poison was never touched" no "$([ -e "$T_TMP/touched" ] && cat "$T_TMP/touched" | head -n 3 | tr '\n' ' ' || echo no)"

t_done
