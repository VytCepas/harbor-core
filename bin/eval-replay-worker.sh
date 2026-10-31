#!/usr/bin/env sh
# eval-replay-worker.sh — adjudicate ONE corpus record, print exactly ONE verdict.
# harbor#133 — lifted out of eval-replay.sh's heredoc so the suite can reach it.
#
# usage:  printf '%s\n' "$record" | sh eval-replay-worker.sh <replay-config-dir>
# output: <id>\t(ALLOW|BLOCK|ERROR)\t<rule-id or reason>
#
# `set -u` and DELIBERATELY NOT `set -e`. Every jq below is expected to fail on a
# record that is not valid JSON — that is the whole path this file exists to keep
# honest — and under `-e` the assignment `id="$(jq …)"` would abort the worker
# before it could print the ERROR verdict, reproducing the silent drop as an even
# quieter one. The `rc=$?` after the guard call fails the same way under `-e`.
set -u
#
# WHY THIS IS A FILE AND NOT A HEREDOC INSIDE eval-replay.sh. It used to be written to
# `$TMP/one.sh` under eval-replay.sh's own private temp dir and deleted by its EXIT
# trap. That made it UNREACHABLE from the suite: replay-test's assertion on the
# never-drop-a-record property guarded it with `[ -f "$TMP/rp/one.sh" ]`, a path
# that never existed, so the test took its `else ok` branch on every run and
# reverting the fix would still have passed (Codex, harbor#133). A test that
# cannot fail is worse than no test, and the untestability was the heredoc — so
# the heredoc is gone rather than worked around.
#
# Invoked per record with the record as a single line on stdin: every attempt to
# stream records through xargs failed on the quoting, and a replay that loses
# records reports "no regressions" from an empty run.
# Stdout is the verdict, which eval-replay.sh reads as data (id<TAB>verdict<TAB>rule), so the log is on stderr (LOG_FD=2,
# contracts/logging.md, harbor#771); eval-replay.sh discards it. A record with no verdict is a WARN, not a failure of
# the worker: the ERROR verdict is the worker succeeding at saying so, and the exit code stays 0 as it always was.
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/library-log.sh"
log_init replay-worker; LOG_FD=2
finish() { log_end || :; exit 0; }
RCFG="${1:-}"; IFS= read -r rec
id="$(printf '%s' "$rec" | jq -r .id 2>/dev/null)"
tool="$(printf '%s' "$rec" | jq -r .tool 2>/dev/null)"
kind="$(printf '%s' "$rec" | jq -r .kind 2>/dev/null)"
pay="$(printf '%s' "$rec" | jq -r .payload 2>/dev/null)"
# NEVER EXIT WITHOUT A LINE. This used to `exit 0` on an unextractable id, which
# for a record that is not valid JSON meant the worker produced NOTHING — and the
# run came back one verdict short of the corpus with no indication why. The
# self-check in eval-replay.sh caught the arithmetic and refused to report, which is the
# only reason the defect surfaced at all; the count is not a substitute for saying
# which record failed. A synthetic key keeps the tally honest without inventing a
# join key that could collide with a real payload hash.
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
# rc is THREE-valued, not two (#47 finding 5). Anything outside {0,2} is a guard
# that did not reach a verdict — a syntax error, a missing interpreter, a kill —
# and the first cut fell through to ALLOW. A broken guard then reported "0
# blocked", which reads exactly like a clean floor. admission-hook.sh maps the same
# class to a DENY for precisely this reason; the replay must not be more
# forgiving than production.
for g in $guards; do
  err="$(printf '%s' "$hook" | CLAUDE_CONFIG_DIR="$RCFG" sh "$RCFG/bin/$g" 2>&1 >/dev/null)"
  rc=$?
  case "$rc" in
    0) ;;
    2) rid="$(printf '%s' "$err" | sed -n 's/^HELM FLOOR \[\([^]]*\)\].*/\1/p' | head -1)"
       printf '%s\tBLOCK\t%s\n' "$id" "${rid:-unattributed}"
       log_ok "record $id: BLOCK ${rid:-unattributed}"; finish ;;
    *) printf '%s\tERROR\t%s-rc%s\n' "$id" "${g%.sh}" "$rc"
       log_warn "record $id: $g exited $rc, not 0 or 2: it reached no verdict"; log_fix "sh bin/floor-verify.sh --live"; finish ;;
  esac
done
printf '%s\tALLOW\t-\n' "$id"
log_ok "record $id: ALLOW"
finish
