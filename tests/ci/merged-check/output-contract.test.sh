#!/usr/bin/env sh
# gate-merged-check.sh's output follows contracts/logging.md (harbor#771): stdout is the verdict lines worktree.sh,
# govern-hook.sh and deploy-install-stamp.sh parse, and only those; the run log is on stderr; a refused base is a FAIL
# with its fix and exit 2. Fixtures are real git.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/gate-merged-check.sh"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE; export GIT_CONFIG_NOSYSTEM=1
R="$T_TMP/repo"; mkdir -p "$R"; git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main
g() { git -C "$R" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
printf 'x\n' > "$R/base"; g add -A; g commit -qm base; B0="$(g rev-parse HEAD)"
g checkout -qb unmerged "$B0"; printf 'u\n' > "$R/u"; g add -A; g commit -qm u; g checkout -q main
run() { sh "$TOOL" "$@" >"$T_TMP/out" 2>"$T_TMP/err"; echo "exit $?"; }
OUT() { cat "$T_TMP/out"; }; ERR() { cat "$T_TMP/err"; }
after_fail() { awk '/^  FAIL:/ { f = 1; next } f { print; exit }' "$T_TMP/err"; }

t_section "verdicts: data on stdout, the log on stderr"
t_eq "exit 0" "exit 0" "$(run --repo "$R" main main unmerged)"
t_eq "stdout is exactly the verdict lines" "merged main
absent unmerged" "$(OUT)"
t_eq "the header names the base" "── merged-check · main against 2 ref(s)" "$(ERR | head -1)"
t_has "a merged ref is an ok line" "$(ERR)" "  ok: merged main: its content is already in main"
t_has "an absent ref is a note" "$(ERR)" "  note: absent unmerged: its content is not in main"
t_eq "the summary counts the merged ref" "merged-check: 1 ok, 0 failed, 0 warnings" "$(ERR | tail -1)"

t_section "an unusable base: FAIL, its fix, the summary, exit 2, nothing on stdout"
t_eq "exit 2" "exit 2" "$(run --repo "$R" no-such-base unmerged)"
t_eq "stdout is empty" "" "$(OUT)"
t_has "the FAIL names the base" "$(ERR)" "  FAIL: base ref not found: no-such-base"
t_has "its fix" "$(after_fail)" "  fix: git -C $R fetch origin"
t_eq "the summary ends it" "merged-check: 0 ok, 1 failed, 0 warnings" "$(ERR | tail -1)"

t_section "not a repository: FAIL, its fix, exit 2"
t_eq "exit 2" "exit 2" "$(run --repo "$T_TMP/nowhere" main x)"
t_has "the FAIL" "$(ERR)" "  FAIL: not a git repository: $T_TMP/nowhere"
t_has "its fix" "$(after_fail)" "  fix: sh $TOOL --repo"
t_eq "the summary" "merged-check: 0 ok, 1 failed, 0 warnings" "$(ERR | tail -1)"
t_done
