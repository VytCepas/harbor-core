#!/usr/bin/env sh
# benchmark.sh (harbor#559) — the Stop hooks and the SessionStart integrity gate, before and after, on one synthetic input.
#   sh tests/admission/budget/benchmark.sh [--ref REF] [--n N] [--mb MB]
# --ref is the "before" tree (default origin/main), extracted with git archive; "after" is this checkout. N runs per hook
# (default 7), a synthetic transcript of MB megabytes (default 50: the turn-weighted median, since one long session
# carries most turns). Every input is generated here: no transcript, settings file or config dir of the operator's is read.
# Prints one row per hook: median and p90 wall ms, before and after, and whether stdout was byte-identical on every run.
# Exit 0 ok · 1 an output differed between before and after · 2 usage. Live: the Stop and SessionStart tables in harbor#559.
set -eu
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"; ROOT="${HERE%/tests/admission/budget}"
REF=origin/main; N=7; MB=50
while [ $# -gt 0 ]; do
  case "$1" in
    --ref) REF="$2"; shift 2 ;;
    --n) N="$2"; shift 2 ;;
    --mb) MB="$2"; shift 2 ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) sed -n '2,8p' "$0" >&2; exit 2 ;;
  esac
done
case "$N$MB" in *[!0-9]*) echo "benchmark: --n and --mb take integers" >&2; exit 2 ;; esac
for t in jq git perl awk; do command -v "$t" >/dev/null 2>&1 || { echo "benchmark: SKIP — $t is not installed"; exit 3; }; done

W="$(mktemp -d "${TMPDIR:-/tmp}/hbudget.XXXXXX")"
trap 'rm -rf "$W"' EXIT INT TERM HUP
mkdir -p "$W/before" "$W/home" "$W/state" "$W/cfg" "$W/repo"
git -C "$ROOT" archive "$REF" bin hooks | tar -x -C "$W/before"
export HOME="$W/home" HARBOR_STATUS_DIR="$W/state" HARBOR_EVENT_DIR="$W/state/events" CLAUDE_CONFIG_DIR="$W/cfg"
git -C "$W/repo" init -q && printf 'x\n' > "$W/repo/f" && git -C "$W/repo" add f && git -C "$W/repo" -c user.name=b -c user.email=b@b commit -qm x

# ── the transcript: the shapes the Stop hooks read, in the proportions of a long working session ──────────────────
# Each round: a prompt, a Bash call and its 60-line result, an Edit, and an assistant reply. Every 20th result
# carries a suite verdict line, every 50th a PR URL, every 30th a background task: the lines the rules act on.
TX="$W/transcript.jsonl"
awk -v want=$((MB * 1000000)) 'BEGIN {
  pad = "    local x = some_function(argument_one, argument_two) -- a line of ordinary file content"
  while (bytes < want) {
    i++
    out("{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"please continue with step " i "\"}}")
    out("{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"id\":\"toolu_b" i "\",\"name\":\"Bash\",\"input\":{\"command\":\"sh tests/area/part" (i % 7) ".test.sh\"}}]}}")
    body = ""
    for (k = 1; k <= 60; k++) body = body sprintf("%6d\\t%s\\n", k, pad)
    if (i % 20 == 0) body = body "part" (i % 7) ".test: 41 passed, " (i % 40 == 0) " failed\\n"
    if (i % 50 == 0) body = body "https://github.com/example/repo/pull/" i "\\n"
    if (i % 30 == 0) body = body "Command running in background with ID: t" i ". Output is being written to: /tmp/x/tasks/t" i "x.output\\n"
    out("{\"type\":\"user\",\"message\":{\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"toolu_b" i "\",\"content\":\"" body "\"}]}}")
    out("{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"id\":\"toolu_e" i "\",\"name\":\"Edit\",\"input\":{\"file_path\":\"/tmp/x/src/f" i ".txt\",\"old_string\":\"a\",\"new_string\":\"b\"}}]}}")
    out("{\"type\":\"user\",\"message\":{\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"toolu_e" i "\",\"content\":\"The file has been updated.\"}]}}")
    out("{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"Step " i " is done; see gh issue close " i " for the ticket.\"}]}}")
  }
}
function out(s) { print s; bytes += length(s) + 1 }' > "$TX"
STOP_P="$(jq -cn --arg t "$TX" --arg c "$W/repo" '{session_id:"bench-sid-0001", transcript_path:$t, cwd:$c,
  hook_event_name:"Stop", stop_hook_active:false, last_assistant_message:"Done. Ran the suite.", background_tasks:[]}')"

# ── the config dir: the B8 surfaces at the size the box carries (1,700 memory links, a skills tree, plugins) ───────
C="$W/cfg"; mkdir -p "$C/bin" "$C/skills" "$C/plugins/cache" "$C/projects"
printf '{"permissions":{"deny":[]},"hooks":{}}\n' > "$C/settings.json"
printf 'x\n' > "$C/.sec0-baseline.sha256"; printf 'x\n' > "$C/.helm-instructions.sha256"
i=0; while [ "$i" -lt 40 ]; do mkdir -p "$C/projects/real$i/memory"; printf 'note %s\n' "$i" > "$C/projects/real$i/memory/MEMORY.md"; i=$((i + 1)); done
i=0; while [ "$i" -lt 1700 ]; do mkdir -p "$C/projects/wt$i"; ln -s "$C/projects/real$((i % 40))/memory" "$C/projects/wt$i/memory"; i=$((i + 1)); done
i=0; while [ "$i" -lt 900 ]; do mkdir -p "$C/skills/s$((i / 10))"; printf 'skill %s\n' "$i" > "$C/skills/s$((i / 10))/f$i.md"; i=$((i + 1)); done

# ── the runner: N runs per side, interleaved so box load lands on both alike ───────────────────────────────────────
now_ms() { perl -MTime::HiRes=time -e 'printf "%d", time * 1000'; }
DIFF=0
row() { # <label> <relative script> <payload or -> <cwd>
  _l="$1"; _s="$2"; _p="$3"; : > "$W/t.before"; : > "$W/t.after"; _same=yes; _k=0
  while [ "$_k" -lt "$N" ]; do
    for _side in before after; do
      if [ "$_side" = before ]; then _f="$W/before/$_s"; else _f="$ROOT/$_s"; fi
      rm -rf "$W/state/sessions" "$C/cache" "$C/.helm-context" "$C/.helm-stop-gate" 2>/dev/null || :
      _t0="$(now_ms)"
      if [ "$_p" = - ]; then (cd "$4" && sh "$_f" < /dev/null > "$W/o.$_side" 2>/dev/null) || :
      else (cd "$4" && printf '%s' "$_p" | sh "$_f" > "$W/o.$_side" 2>/dev/null) || :; fi
      echo $(( $(now_ms) - _t0 )) >> "$W/t.$_side"
    done
    cmp -s "$W/o.before" "$W/o.after" || _same=no
    _k=$((_k + 1))
  done
  [ "$_same" = yes ] || DIFF=1
  _st() { sort -n "$1" | awk '{ a[NR] = $1 } END { printf "%d\t%d", a[int((NR + 1) / 2)], a[int(NR * 0.9 + 0.999)] }'; }
  printf '%s\t%s\t%s\t%s\n' "$_l" "$(_st "$W/t.before")" "$(_st "$W/t.after")" "$_same"
}
{
  printf 'hook\tbefore p50\tbefore p90\tafter p50\tafter p90\tidentical\n'
  row "Stop admission-stop" bin/admission-stop.sh "$STOP_P" "$W/repo"
  row "Stop ticket-note" hooks/ticket-note/ticket-note.sh "$STOP_P" "$W/repo"
  row "Stop reply-shape" hooks/reply-shape/reply-shape.sh "$STOP_P" "$W/repo"
  row "Stop session-state" hooks/session-state/session-state.sh "$STOP_P" "$W/repo"
  row "SessionStart admission-integrity" bin/admission-integrity.sh - "$W/repo"
} | column -t -s "$(printf '\t')"
echo "benchmark: $N runs per side, transcript $(wc -c < "$TX" | tr -d ' ') B, before=$REF, load: $(uptime | sed 's/.*load average[s]*: //')"
[ "$DIFF" -eq 0 ] || { echo "benchmark: FAIL — an output differed between before and after"; exit 1; }
