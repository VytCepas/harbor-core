#!/usr/bin/env sh
# harbor#184 · lever 2 — a tool result that will ride in context for the rest of
# the session, named at the moment it arrives.
#
# WHY THIS IS THE LEVER. Cache reads are 58% of the bill — 8.07B cache-read
# tokens against 46M output tokens, a ratio of 176:1 — and that is not the cost of
# generating text, it is the cost of re-reading context. A large tool result is
# paid once when it arrives and again on every subsequent call in the session.
#
# THE THRESHOLD IS DERIVED, NOT PICKED, which matters because an arguable
# threshold is how a check gets switched off (§2.11). Measured across the 30
# newest transcripts on 2026-08-22 — 6,249 tool results, 88 MB, sizes only, no
# content read:
#
#   p50    542 B          the typical result is tiny
#   p75  1,972 B
#   p90 55,518 B          the distribution has a knee, not a slope
#   p95 99,602 B
#   p99 206,428 B         max 676,029 B
#
#   the top 10% of results carry 90% of all result bytes
#   665 results over 32 KB carry 92% of all result bytes
#
# So 32 KB sits just under p90 and selects the 10.6% of calls that are 92% of the
# problem. HARBOR_RESULT_BYTES overrides it — for the suite, and for a box whose
# distribution differs. It is a knob with a measured default, not a second
# ceiling, and the note prints the number so a reader can argue with it.
#
# WHAT THE MEASUREMENT ALSO SETTLED, and it is why there is no `tool:` matcher:
#
#   mcp__claude-in-chrome__browser_batch   498 calls   43.2 MB   88 KB mean
#   Read                                   133 calls   23.5 MB  181 KB mean
#   mcp__claude-in-chrome__computer        339 calls   15.1 MB   45 KB mean
#   Bash                                 4,055 calls    4.9 MB    1 KB mean
#
# `Read` is the worst per call and the browser tools are the worst in total.
# `Bash` is 4,055 calls at 1 KB — its lever is call COUNT, not result size, which
# is harbor#184's lever 1 and not this pack's business.
#
# NO SIZE IS QUOTED FROM THE RESULT ITSELF, only its length. DEAD-ENDS.md DE-16
# refused a durable corpus built out of transcript content; the same discipline
# holds here, one channel over — a length is not a payload.
#
# stdin is the hook payload; stdout is the note (empty = silence).
set -u

command -v jq >/dev/null 2>&1 || exit 0

PAYLOAD="$(cat 2>/dev/null || true)"
[ -n "$PAYLOAD" ] || exit 0

TOOL="$(printf '%s' "$PAYLOAD" | jq -r '.tool_name // empty' 2>/dev/null || true)"
BYTES="$(printf '%s' "$PAYLOAD" | jq -r '(.tool_response // empty) | tostring | utf8bytelength' 2>/dev/null || true)"
case "$BYTES" in ''|*[!0-9]*) exit 0 ;; esac

LIMIT="${HARBOR_RESULT_BYTES:-32768}"
case "$LIMIT" in ''|*[!0-9]*) LIMIT=32768 ;; esac
[ "$BYTES" -gt "$LIMIT" ] || exit 0

# A SUBAGENT RESULT IS ALREADY THE REMEDY. The ticket measures 39 Agent calls
# returning 0.04 MB into a parent context against a workflow that burned 2.06M
# subagent tokens — roughly 200:1 compression. Telling a session that the
# compressed form is too large would tax the fix to catch the problem.
case "$TOOL" in
  Agent|Task) exit 0 ;;
esac

KB=$(( BYTES / 1024 ))

# The remedy is per tool, because "read less" is not actionable and "pass limit"
# is. Each of these is the narrowing that tool actually offers.
case "$TOOL" in
  Read)
    FIX="pass offset/limit and read the part you need — Read averages 181 KB per call on this box, the worst of any tool per call" ;;
  Bash)
    FIX="bound the output at the source (head, tail, sed -n, grep -c, --limit) rather than letting the whole thing into context" ;;
  mcp__claude-in-chrome__browser_batch)
    FIX="fewer actions per batch, or get_page_text instead of read_page — this tool is 43.2 MB over 498 calls on this box, the largest single consumer of context here" ;;
  mcp__claude-in-chrome__*)
    FIX="narrow the selector or the region, and prefer a text read over a full page read" ;;
  Grep|Glob)
    FIX="add head_limit, or narrow the path and pattern" ;;
  WebFetch|WebSearch)
    FIX="a narrower prompt returns a narrower extract" ;;
  *)
    FIX="ask for less, or hand the reading to a subagent" ;;
esac

# THE NOTE DOES NOT ARGUE FOR THE THRESHOLD, it reports it. The derivation is in
# this header, where it costs nothing at runtime, and quoting it in the note would
# be a claim that goes false the moment HARBOR_RESULT_BYTES is overridden.
printf '%s returned %s KB, over this box'"'"'s %s KB result threshold. It sits in the prefix now and is re-read on every later call in the session — cache reads are 58%% of this account'"'"'s bill, at 176:1 against output tokens. Next call: %s. For a read-heavy task as a whole, a subagent returns the conclusion instead of the corpus (~200:1 measured). Once per session.\n' \
  "${TOOL:-a tool}" "$KB" "$(( LIMIT / 1024 ))" "$FIX"
