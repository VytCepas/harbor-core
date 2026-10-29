#!/usr/bin/env sh
# eval-hook-replay.sh's output follows contracts/logging.md (harbor#771): every line is the log's shape, a FAIL is
# followed by its fix, the run ends with the summary, and the exit codes (0 a report, 1 a failed self-test,
# 2 usage) are the ones it always had. The repo, the hooks and the transcript store are fixtures.
. "$(dirname "$0")/../../lib/core.sh"; t_init
B="$T_TMP"; R="$B/repo"; mkdir -p "$R/bin" "$R/hooks" "$R/contracts" "$B/store/p"
cp "$T_ROOT/bin/eval-hook-replay.sh" "$T_ROOT/bin/library-log.sh" "$R/bin/"
TOOL="$R/bin/eval-hook-replay.sh"
printf '#!/bin/sh\nexit 0\n' > "$R/bin/test-suite-select.sh"
printf '#!/bin/sh\ngrep -q BAD "$1" && exit 1\nexit 0\n' > "$R/hooks/commit-msg"
printf 'tests/a.sh\ntests/b.sh\n' > "$R/contracts/suites.txt"
git -C "$R" init -q -b main; git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
printf 'x\n' > "$R/f"; git -C "$R" add -A; git -C "$R" commit -q -m "a clean message"
printf 'y\n' > "$R/f"; git -C "$R" commit -q -am "BAD trailer here"
# The stub fires on a merge command; the real hook's matcher is what --self-test pins.
printf '#!/bin/sh\ngrep -q "pr merge" && echo fired\nexit 0\n' > "$R/bin/govern-hook.sh"
printf '%s\n' '{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"gh pr merge 1"}}]}}' \
  '{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}' > "$B/store/p/s.jsonl"
hr() { HARBOR_CI_BASE_BRANCH=main HARBOR_SESSION_TRANSCRIPTS="$B/store" sh "$TOOL" "$@" >"$B/out" 2>"$B/err"; echo "exit $?"; }
OUT() { cat "$B/out"; }
after_fail() { awk '/^  FAIL:/ { f = 1; next } f { print; exit }' "$B/out"; }
shaped() { OUT | grep -vcE '^(── |  (ok|FAIL|WARN|note|skip|fix): |hook-replay: [0-9]+ ok, [0-9]+ failed, [0-9]+ warnings$)'; }

t_section "--commits: a header per replay, the fire as a note, the summary, exit 0"
t_eq "it exits 0" "exit 0" "$(hr --commits)"
t_has "T0a is a header" "$(OUT)" "── hook-replay · T0a  hooks/commit-msg vs every commit message on main"
t_has "T0b is a header" "$(OUT)" "── hook-replay · T0b  hooks/pre-push"
t_has "the fire is a note naming the subject" "$(OUT)" "  note: FIRE  "
t_has "the count is an ok line" "$(OUT)" "  ok: 2 message(s) replayed, 1 fired."
t_eq "the summary ends it" "hook-replay: 2 ok, 0 failed, 0 warnings" "$(OUT | tail -1)"
t_eq "every line is the log's shape" 0 "$(shaped)"
t_eq "stderr is empty" "" "$(cat "$B/err")"

t_section "--bash: the store replay reports its counts in the same shape"
t_eq "it exits 0" "exit 0" "$(hr --bash)"
t_has "T0c is a header" "$(OUT)" "── hook-replay · T0c  bin/govern-hook.sh"
t_has "the store size is an ok line" "$(OUT)" "  ok: 2 Bash command(s) in the store."
t_has "the fired count is a note" "$(OUT)" "FIRED                                      1"
t_eq "the summary ends it" "hook-replay: 1 ok, 0 failed, 0 warnings" "$(OUT | tail -1)"
t_eq "every line is the log's shape" 0 "$(shaped)"
rm -rf "$B/store"
t_eq "an absent store exits 0" "exit 0" "$(hr --bash)"
t_has "its absence is a skip" "$(OUT)" "  skip: no transcript store at"

t_section "--self-test: ok lines and the summary; a pre-filter that drops a real fire is a FAIL with its fix"
t_eq "the real hook passes it" "exit 0" "$(sh "$T_ROOT/bin/eval-hook-replay.sh" --self-test >"$B/out" 2>"$B/err"; echo "exit $?")"
t_has "a shape is an ok line" "$(OUT)" "  ok: prefilter=0 hook=0  gh pr merge 1"
t_eq "the summary" "hook-replay: 4 ok, 0 failed, 0 warnings" "$(OUT | tail -1)"
# A hook that fires on a command with no 'merge' in it: the pre-filter would have dropped a real fire.
printf '#!/bin/sh\necho fired\nexit 0\n' > "$R/bin/govern-hook.sh"
t_eq "a hook that fires on everything exits 1" "exit 1" "$(hr --self-test)"
t_has "the FAIL names the command" "$(OUT)" "  FAIL: the pre-filter would have dropped a real fire: echo hi"
t_has "its fix is on the next line" "$(after_fail)" "  fix: sh $TOOL --self-test"
t_eq "the summary counts them" 1 "$(OUT | tail -1 | grep -c '^hook-replay: [0-9]* ok, 3 failed, 0 warnings$')"

t_section "usage: an unknown flag is FAIL, its fix, the summary, exit 2"
t_eq "it exits 2" "exit 2" "$(hr --nonsuch)"
t_has "the FAIL names the flag" "$(OUT)" "  FAIL: unknown flag --nonsuch: nothing was replayed"
t_eq "its fix reads the help" "  fix: sh $TOOL --help" "$(after_fail)"
t_eq "the summary ends it" "hook-replay: 0 ok, 1 failed, 0 warnings" "$(OUT | tail -1)"
t_done
