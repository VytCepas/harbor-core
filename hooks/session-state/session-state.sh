#!/usr/bin/env sh
# session-state.sh (harbor#1043, #1044) — the Stop hook that says what this session is WAITING ON.
#
# Stop fires at the end of EVERY turn (CONTRACTS/hooks.md). This hook reads the payload and the transcript,
# decides one state by ordered rules, writes the record, and appends a `session.state` event to the bus
# ONLY when the state changed. It never blocks: it prints nothing, except the one `session.save-now`
# continuation below. Exit 0 on every path; HARBOR_STATUS_DIR/session-state.off turns it off.
#
# Payload fields read (code.claude.com/docs/en/hooks, "Stop input", fetched 2026-10-10): session_id,
# transcript_path, cwd, prompt_id, stop_hook_active, last_assistant_message, background_tasks[].
#
# THE STATE, first rule that holds wins:
#   waiting-agents    a background_tasks[] entry has status "running" (the docs list no other status
#                     values; "running" is the one their example shows; "pending" counts too: it is in flight)
#   waiting-operator  the last message matches a row of session-waiting.tsv, or the turn ended on an
#                     AskUserQuestion that has no result
#   blocked           guard-stop.sh's SG-2 holds: a suite this session ran is red and no later run of it
#                     was green (the same awk, kept equal by tests/session/state/stop.test.sh)
#   done              rules 1-3 do not hold, this session committed, pushed or opened a PR, no Write/Edit
#                     came after the last such command, the tree is clean, and the branch is pushed (an
#                     upstream with nothing ahead) or a PR URL was seen. The handoff is NOT a condition:
#                     handover_at / handover_stale (yes|no) are reported beside it
#   idle              otherwise
#
# THE RECORD  $STATE/sessions/<session_id>.json: {state, since, cwd, branch, dirty, pr, background_tasks[],
# ctx_pct, handover_at, reason} + handover_stale, agents, prompt_id, updated, save_now. $STATE defaults to
# ~/.local/state/harbor. ctx_pct is what fleet-glyph.sh wrote to $STATE/ctx/<session_id>.
#
# THE EVENT  session.state, subject = session_id, data {session_id, title: <state>, evidence: <reason>}
# (the bus keeps only that allowlist). The reaction presets in CONTRACTS/event-rules.tsv follow it.
#
# SAVE-NOW  when the operator turned the `event.session-save-now` rule on (its rule file exists), the
# turn is not already a Stop-hook continuation, ctx_pct >= 90 (or >= 75 right after a commit/PR) and the
# handoff is older than the last milestone, this hook returns ONE additionalContext asking for the handoff.
# `stop_hook_active` stops a second one in the same chain; save_now in the record stops a repeat for the
# same trigger. Anything heavier than this runs detached from the dispatcher, never here.
#
# The floor never depends on this file; guard-stop.sh is not touched and not called.

set -u
trap 'exit 0' EXIT
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
[ ! -f "$HERE/manifest.tsv" ] || HERE="$HERE/../../bin"  # D-88: in the repo an engine sits beside its manifest in hooks/<engine>/; deployed, flat beside its libraries
case "${1-}" in -h|--help) sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
command -v jq >/dev/null 2>&1 || exit 0
LC_ALL=C; export LC_ALL
[ -f "$HERE/fs-lib.sh" ] && . "$HERE/fs-lib.sh" || fs_mtime() { :; }

STATE="${HARBOR_STATUS_DIR:-${HOME:-/nonexistent}/.local/state/harbor}"
[ ! -e "$STATE/session-state.off" ] || exit 0
CFG="${CLAUDE_CONFIG_DIR:-${HOME:-/nonexistent}/.claude}"

P="$(cat 2>/dev/null)" || exit 0
[ -n "$P" ] || exit 0
SID=""; TX=""; CWD=""; PID=""; ACTIVE=false; NRUN=0; TASKS="[]"; MSG=""
# One jq, shell-quoted assignments: a field can hold any byte, and @sh is the quoting that survives all of them.
# The program sits in a variable, not inside $( ): macOS bash 3.2 re-parses a brace-and-quote program there.
PAYLOAD_JQ='@sh "SID=\(.session_id // "") TX=\(.transcript_path // "") CWD=\(.cwd // "") PID=\(.prompt_id // "") ACTIVE=\(.stop_hook_active // false) NRUN=\([.background_tasks[]? | select(.status == "running" or .status == "pending")] | length) TASKS=\([.background_tasks[]? | {id: .id, type: .type, status: .status, description: ((.description // "") | .[0:80])}] | tojson) MSG=\((.last_assistant_message // "") | .[-700:])"'
eval "$(printf '%s' "$P" | jq -r "$PAYLOAD_JQ" 2>/dev/null)" || exit 0
case "$SID" in ''|*[!A-Za-z0-9_-]*) exit 0 ;; esac
case "$NRUN" in ''|*[!0-9]*) NRUN=0 ;; esac
[ -n "${TASKS:-}" ] || TASKS='[]'
NOW="$(date +%s)"

# ── the transcript, one jq pass ────────────────────────────────────────────────────────────────
# Records: CMD id command ts · BGT id task · RES id <suite verdict line> · PRU id <pull url>.
# RES and BGT are guard-stop.sh's own filters, so SG-2 below reads what that gate reads.
RED=""; MS=0; MUT=0; PRURL=""; ASKPEND=0; T0=0
if [ -n "$TX" ] && [ -r "$TX" ]; then
  T0="$(head -n 30 "$TX" 2>/dev/null | jq -r '(.timestamp? // empty) | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601? // empty' 2>/dev/null | head -n 1)"
  case "$T0" in ''|*[!0-9]*) T0=0 ;; esac
  # A WINDOW, NOT THE WHOLE FILE: a long session's transcript is hundreds of MB and jq parses ~25 MB/s. The last
  # WIN bytes decide every rule below (the last verdict per suite, the last milestone, a pending question); the
  # first, cut line goes. A suite last run before the window is therefore not seen: a deliberate trade for a hook.
  # grep keeps only the few lines a rule can use, so jq parses a fraction of the window.
  WIN="${HARBOR_STATUS_WINDOW:-3000000}"
  case "$WIN" in ''|*[!0-9]*) WIN=3000000 ;; esac
  # An AskUserQuestion is pending when it is the last thing the transcript says.
  if tail -n 1 "$TX" 2>/dev/null | grep -q '"name":"AskUserQuestion"'; then ASKPEND=1; fi
  # `jq -R` + `fromjson?`: the window's first line is cut mid-record and must not stop the parse.
  STREAM="$(tail -c "$WIN" "$TX" 2>/dev/null | grep -E '"name":"(Bash|Write|Edit|NotebookEdit)"|(passed|rules), [0-9]+ (failed|violations)|/pull/[0-9]|tasks/[A-Za-z0-9]+\.output' 2>/dev/null | jq -R -r 'fromjson? |
    if .type=="assistant" then
      ((.timestamp // "" | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601? // 0) as $t
       | .message.content[]? | select(.type=="tool_use") |
        if .name=="Bash" then "CMD\t" + (.id // "-") + "\t" + ((.input.command // "") | .[0:400] | gsub("[\n\t]"; " ")) + "\t" + ($t|tostring)
        elif .name=="Read" and ((.input.file_path // "") | test("/tasks/[A-Za-z0-9]+\\.output$")) then "CMD\t" + (.id // "-") + "\t" + .input.file_path + "\t" + ($t|tostring)
        elif (.name=="Write" or .name=="Edit" or .name=="NotebookEdit") then "MUT\t-\t" + ($t|tostring)
        else empty end)
    elif .type=="user" then
      (.message.content[]? | select(.type=="tool_result") |
        (.tool_use_id // "-") as $id |
        ((if (.content|type)=="array" then ([.content[]? | .text? // ""] | join("\n")) else (.content|tostring) end)
         | split("\n")[] | sub("^ *[0-9]+\t"; "")
         | (select(test("^Command .*Output is being written to: [^ ]*/tasks/[A-Za-z0-9]+\\.output")) | "BGT\t" + $id + "\t" + (capture("/tasks/(?<t>[A-Za-z0-9]+)\\.output") | .t)),
           (select(test("^[a-z][a-z0-9 .-]*: [0-9]+ (passed|rules), [0-9]+ (failed|violations)")) | "RES\t" + $id + "\t" + .),
           (select(test("^https://github\\.com/[^/ ]+/[^/ ]+/pull/[0-9]+$")) | "PRU\t" + $id + "\t" + .)))
    else empty end' 2>/dev/null)" || STREAM=""
  if [ -n "$STREAM" ]; then
    # SG-2, verbatim from bin/guard-stop.sh (suite_key, and SG_PAIR byte-equal, held by stop.test.sh):
    # the last verdict per suite name wins.
    SG_PAIR='
  $1 == "CMD" { if ($3 ~ /([-.]test|lint-conventions|floor-equiv|pass-score)[a-z-]*\.sh/) ran[$2] = 1
                else for (t in bg) if (index($3, "tasks/" t ".output")) ran[$2] = 1 }
  $1 == "BGT" && ($2 in ran) { bg[$3] = 1 }'
    OUT="$(printf '%s\n' "$STREAM" | awk -F '\t' "$SG_PAIR"'
      function suite_key(s) { sub(/^.* [0-9]+ /, "", s); return s }
      $1 == "CMD" && $3 ~ /(^|[ ;&|])(git (commit|push)|gh pr (create|merge))( |$)/ { ms = $4 + 0; prc[$2] = 1 }
      $1 == "MUT" { mut = $3 + 0 }
      $1 == "PRU" && ($2 in prc) { pru = $3 }
      $1 == "RES" && ($2 in ran) {
        line = $3; n = index(line, ":"); if (n < 2) next
        name = suite_key(substr(line, 1, n - 1)); rest = substr(line, n + 1); bad = 0
        if (match(rest, /[0-9]+ (failed|violations)/)) { tok = substr(rest, RSTART, RLENGTH); if (tok + 0 > 0) bad = 1 }
        last[name] = bad; text[name] = line }
      END { for (k in last) if (last[k]) { print "red\t" text[k]; break }
            print "ms\t" ms + 0; print "mut\t" mut + 0; print "pr\t" pru }')"
    while IFS="$(printf '\t')" read -r _k _v; do
      case "$_k" in red) RED="$_v" ;; ms) MS="$_v" ;; mut) MUT="$_v" ;; pr) PRURL="$_v" ;; esac
    done <<EOF
$OUT
EOF
  fi
fi

# ── git: branch, changed files, pushed?, and the handoff's freshness (a field, not a gate) ────────
# git runs under a 2 s alarm (perl); a timeout fails the whole hook open: no record, exit 0.
BRANCH=""; DIRTY=0; HANDOVER_AT=0; PUSHED=0
if [ -n "$CWD" ] && [ -d "$CWD" ]; then
  _rc=0; _gf="$STATE/.gs.$$"; mkdir -p "$STATE" 2>/dev/null
  # Output goes to a file, not a pipe: a killed git's child would otherwise hold a $( ) open until it exits.
  if command -v perl >/dev/null 2>&1; then
    GIT_OPTIONAL_LOCKS=0 perl -e 'alarm 2; exec @ARGV' git -C "$CWD" status --porcelain -b > "$_gf" 2>/dev/null || _rc=$?
  else
    GIT_OPTIONAL_LOCKS=0 git -C "$CWD" status --porcelain -b > "$_gf" 2>/dev/null || _rc=$?
  fi
  GS="$(cat "$_gf" 2>/dev/null)"; rm -f "$_gf"
  [ "$_rc" -ne 142 ] || exit 0
  if [ "$_rc" -eq 0 ]; then
    _l1="$(printf '%s\n' "$GS" | sed -n 1p)"
    BRANCH="$(printf '%s\n' "$_l1" | sed 's/^## \(No commits yet on \)\{0,1\}//; s/\.\.\..*//; s/ \[.*//')"
    DIRTY="$(printf '%s\n' "$GS" | awk 'NR > 1 && NF { n++ } END { print n + 0 }')"
    case "$_l1" in *'...'*) case "$_l1" in *ahead*|*gone*) ;; *) PUSHED=1 ;; esac ;; esac
    _top="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)" || _top=""
    if [ -n "$_top" ] && [ -f "$_top/HANDOFF.md" ]; then
      HANDOVER_AT="$(fs_mtime "$_top/HANDOFF.md")"
    fi
  fi
fi
# No HANDOFF.md: the newest file in the session's memory store, projects/<cwd with / and . as ->/memory.
if [ "${HANDOVER_AT:-0}" = 0 ] && [ -n "$CWD" ]; then
  _md="$CFG/projects/$(printf '%s' "$CWD" | sed 's#[/.]#-#g')/memory"
  _nf="$(ls -t "$_md" 2>/dev/null | sed -n 1p)"
  [ -z "$_nf" ] || HANDOVER_AT="$(fs_mtime "$_md/$_nf")"
fi
case "$HANDOVER_AT" in ''|*[!0-9]*) HANDOVER_AT=0 ;; esac

CTX=""
[ ! -r "$STATE/ctx/$SID" ] || read -r CTX < "$STATE/ctx/$SID" 2>/dev/null || :
case "$CTX" in ''|*[!0-9]*) CTX="" ;; esac

# ── the waiting-operator table ─────────────────────────────────────────────────────────────────
WAITING=""
TABLE="$HERE/session-waiting.tsv"; [ -f "$TABLE" ] || TABLE="$HERE/../CONTRACTS/session-waiting.tsv"
if [ -n "$MSG" ] && [ -f "$TABLE" ]; then
  WAITING="$(WMSG="$MSG" awk -F '\t' 'BEGIN { m = tolower(ENVIRON["WMSG"]) }
    /^#/ || NF < 2 { next }
    m ~ $2 { print $1; exit }' "$TABLE" 2>/dev/null)"
fi

# ── the rules, in order ────────────────────────────────────────────────────────────────────────
if [ "$NRUN" -gt 0 ]; then S=waiting-agents; REASON="$NRUN running"
elif [ -n "$WAITING" ]; then S=waiting-operator; REASON="$WAITING"
elif [ "$ASKPEND" = 1 ]; then S=waiting-operator; REASON="W-ask"
elif [ -n "$RED" ]; then S=blocked; REASON="$(printf '%s' "$RED" | cut -c1-120)"
elif [ "$MS" -gt 0 ] && [ "$MUT" -le "$MS" ] && [ "$DIRTY" -eq 0 ] && { [ "$PUSHED" = 1 ] || [ -n "$PRURL" ]; }; then
  S=done; REASON="committed, clean, pushed"
else S=idle; REASON=""
fi

HSTALE=no
if [ "$HANDOVER_AT" -eq 0 ] || { [ "$MS" -gt 0 ] && [ "$HANDOVER_AT" -lt "$MS" ]; }; then HSTALE=yes; fi

# ── the record and the event ───────────────────────────────────────────────────────────────────
mkdir -p "$STATE/sessions" 2>/dev/null || exit 0
REC="$STATE/sessions/$SID.json"
PREV=""; SINCE="$NOW"; PSAVE=""
if [ -r "$REC" ]; then
  eval "$(jq -r '@sh "PREV=\(.state // "") PSINCE=\(.since // 0) PSAVE=\(.save_now // "") PUPD=\(.updated // 0)"' "$REC" 2>/dev/null)" || PREV=""
  [ "$PREV" != "$S" ] || SINCE="${PSINCE:-$NOW}"
fi

# save-now: the operator's switch is the dispatcher rule file; the trigger id makes it once per trigger.
SAVE=""; SAVEMSG=""
if [ "$ACTIVE" != true ] && [ -n "$CTX" ] && [ -f "$CFG/.helm-dispatch/rules/event.session-save-now.rule" ]; then
  _ref="$MS"; [ "$_ref" -gt 0 ] || _ref="$T0"
  _why=""
  if [ "$CTX" -ge 90 ]; then _why=ctx90
  elif [ "$CTX" -ge 75 ] && [ "$MS" -gt "${PUPD:-0}" ]; then _why=ctx75-milestone; fi
  if [ -n "$_why" ] && [ "$HANDOVER_AT" -lt "$_ref" ]; then
    _trig="$_why:$_ref"
    if [ "${PSAVE:-}" != "$_trig" ]; then
      SAVE="$_trig"
      SAVEMSG="Context is at ${CTX}% of the compaction window and the handoff is older than your last commit or PR. Write the handoff now (HANDOFF.md: what changed, the evidence, what is open) so a compaction loses nothing. One short reply; do not start other work."
    fi
  fi
fi
[ -n "$SAVE" ] || SAVE="${PSAVE:-}"

jq -cn --arg state "$S" --argjson since "$SINCE" --arg cwd "$CWD" --arg branch "$BRANCH" --argjson dirty "$DIRTY" \
  --arg pr "$PRURL" --argjson tasks "$TASKS" --arg ctx "$CTX" --argjson handoff "$HANDOVER_AT" --arg reason "$REASON" \
  --argjson agents "$NRUN" --arg pid "$PID" --argjson upd "$NOW" --arg save "$SAVE" --arg hstale "$HSTALE" \
  '{state:$state, since:$since, cwd:$cwd, branch:$branch, dirty:$dirty, pr:$pr, background_tasks:$tasks,
    ctx_pct:(if $ctx == "" then null else ($ctx|tonumber) end), handover_at:$handoff, reason:$reason,
    agents:$agents, prompt_id:$pid, updated:$upd, save_now:$save, handover_stale:$hstale}' > "$REC.$$" 2>/dev/null && mv -f "$REC.$$" "$REC" 2>/dev/null
rm -f "$REC.$$" 2>/dev/null

# Leaving `done` retires the lint verdict event.session-check wrote for it (the glyph shows it until then).
[ "$PREV" != done ] || [ "$S" = done ] || rm -f "$STATE/sessions/$SID.check" 2>/dev/null

BUS="$HERE/event-bus.sh"
if [ -f "$BUS" ] && { [ "$PREV" != "$S" ] || { [ -n "$SAVEMSG" ] ; }; }; then
  # Detached: the bus costs a few processes, and a Stop hook that waits for them is one the operator turns off.
  (
    cd "${CWD:-/}" 2>/dev/null || cd /
    if [ "$PREV" != "$S" ]; then
      sh "$BUS" emit session.state "$SID" --src hook.session-state \
        --data "$(jq -cn --arg s "$SID" --arg t "$S" --arg e "$REASON" '{session_id:$s, title:$t, evidence:$e}')"
    fi
    if [ -n "$SAVEMSG" ]; then
      sh "$BUS" emit session.save-now "$SID" --src hook.session-state \
        --data "$(jq -cn --arg s "$SID" --arg t "ctx ${CTX}%" '{session_id:$s, title:$t}')"
    fi
  ) >/dev/null 2>&1 </dev/null &
fi

if [ -n "$SAVEMSG" ]; then
  jq -cn --arg m "$SAVEMSG" '{hookSpecificOutput:{hookEventName:"Stop", additionalContext:$m}}'
fi
exit 0
