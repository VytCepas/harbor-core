#!/usr/bin/env sh
# eval-replay-worker.sh — adjudicate ONE corpus record, print exactly ONE verdict.
# harbor#133: lifted out of eval-replay.sh's heredoc so the suite can reach it.
# Removed notes: docs/explanation/code-cases/bin-eval-replay-worker.md
# usage:  printf '%s\n' "$record" | sh eval-replay-worker.sh <replay-config-dir>
# output: <id>\t(ALLOW|BLOCK|ERROR)\t<rule-id or reason>
# `set -u` and DELIBERATELY NOT `set -e`: every jq here is expected to fail on a record that is not valid JSON, and under `-e` the worker would abort before printing the ERROR verdict.
set -u
# WHY A FILE: as a heredoc it was unreachable from the suite, so its never-drop-a-record test passed via an else branch every run (Codex, harbor#133).
# Stdout is the verdict eval-replay.sh reads as data (id<TAB>verdict<TAB>rule), so the log is on stderr (LOG_FD=2, harbor#771); an ERROR verdict is the worker succeeding at saying so, exit 0.
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/library-log.sh"
log_init replay-worker
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2
finish() { log_end || :; exit 0; }
RCFG="${1:-}"; IFS= read -r rec
id="$(printf '%s' "$rec" | jq -r .id 2>/dev/null)"
tool="$(printf '%s' "$rec" | jq -r .tool 2>/dev/null)"
kind="$(printf '%s' "$rec" | jq -r .kind 2>/dev/null)"
pay="$(printf '%s' "$rec" | jq -r .payload 2>/dev/null)"
# NEVER EXIT WITHOUT A LINE: a silent exit left the run one verdict short with no hint which record failed; a synthetic key keeps the tally honest.
[ -n "$id" ] || { printf 'unparseable-%s\tERROR\tno-id\n' "$$"
  log_warn "a record has no extractable id: it is not valid JSON"; log_fix "sh bin/eval-replay-corpus.sh --to \"\${TMPDIR:-/tmp}/corpus.jsonl\""; finish; }
case "$kind" in
  file_path) hook="$(printf '%s' "$pay" | jq -Rs '{tool_name:"Write",tool_input:{file_path:.}}' 2>/dev/null)"
             guards="admission-self-edit.sh" ;;
  *)         case "$tool" in
               Bash) hook="$(printf '%s' "$pay" | jq -Rs '{tool_name:"Bash",tool_input:{command:.}}' 2>/dev/null)"
                     guards="admission-bash.sh admission-egress.sh" ;;
               *)    hook="$(printf '%s' "$pay" | jq -Rs '{tool_name:"Write",tool_input:{content:.}}' 2>/dev/null)"
                     guards="admission-egress.sh" ;;
             esac ;;
esac
[ -n "$hook" ] || { printf '%s\tERROR\t-\n' "$id"
  log_warn "record $id: its payload could not be wrapped as a hook input"; log_fix "sh bin/eval-replay-corpus.sh --to \"\${TMPDIR:-/tmp}/corpus.jsonl\""; finish; }
# rc is THREE-valued (#47 finding 5): anything outside {0,2} is a guard that reached no verdict, and falling through to ALLOW reported a broken guard as a clean floor, more forgiving than production (admission-hook.sh maps it to DENY).
for g in $guards; do
  err="$(printf '%s' "$hook" | CLAUDE_CONFIG_DIR="$RCFG" sh "$RCFG/bin/$g" 2>&1 >/dev/null)"
  rc=$?
  case "$rc" in
    0) ;;
    2) rid="$(printf '%s' "$err" | sed -n 's/^HELM FLOOR \[\([^]]*\)\].*/\1/p' | head -1)"
       printf '%s\tBLOCK\t%s\n' "$id" "${rid:-unattributed}"
       log_ok "record $id: BLOCK ${rid:-unattributed}"; finish ;;
    *) printf '%s\tERROR\t%s-rc%s\n' "$id" "${g%.sh}" "$rc"
       log_warn "record $id: $g exited $rc, not 0 or 2: it reached no verdict"; log_fix "sh bin/admission-verify.sh --live"; finish ;;
  esac
done
printf '%s\tALLOW\t-\n' "$id"
log_ok "record $id: ALLOW"
finish
