#!/usr/bin/env sh
# port-paths.sh's output follows CONTRACTS/logging.md (harbor#1149): the inventory is TSV on stdout and only that, with
# the log on stderr; --verify and --selftest are runs and log on stdout; a FAIL is followed by its fix, and the run
# ends with the summary. Everything is a fixture, $HOME included.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/port-paths.sh"
T="$(CDPATH='' cd -P -- "$T_TMP" && pwd -P)"; TAB="$(printf '\t')"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE XDG_CONFIG_HOME PORT_ROOT PORT_PATHS_EXEMPT
export GIT_CONFIG_NOSYSTEM=1
H="$T/home"; C="$T/cfg"; P="$H/port"; X="$T/exempt.tsv"; mkdir -p "$H/.claude" "$C" "$P"; export HOME="$H"
put() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; }
repo() { mkdir -p "$1"; git -C "$1" init -q; }
repo "$P/harbor"; put "$P/harbor/bin/a.sh" 'cd ~/harbor'; put "$P/harbor/notes.md" 'moved out of ~/harbor/bin'; git -C "$P/harbor" add -A
printf 'file\ttext\twhy\nharbor/gone.sh\tno longer here\ta row whose line is gone\n' > "$X"
pp() { HOME="$H" CLAUDE_CONFIG_DIR="$C" PORT_ROOT="$P" PORT_PATHS_EXEMPT="$X" sh "$TOOL" "$@" >"$T/out" 2>"$T/err"; echo "exit $?"; }
OUT() { cat "$T/out"; }; ERR() { cat "$T/err"; }
after_fail() { awk '/^  FAIL:/ { f = 1; next } f { print; exit }' "$T/out"; }

t_section "the inventory: TSV on stdout and nothing else, an empty stderr"
t_eq "it exits 0" "exit 0" "$(pp)"
t_eq "the header is the first line" "surface${TAB}class${TAB}file${TAB}line${TAB}literal" "$(OUT | head -1)"
t_eq "every line has five fields" 0 "$(OUT | awk -F'\t' 'NF != 5' | grep -c .)"
t_eq "no log line is mixed in" 0 "$(OUT | grep -c '^  \(ok\|FAIL\|WARN\|note\|skip\|fix\):')"
t_eq "stderr is empty" "" "$(ERR)"

t_section "an unknown argument: FAIL, its fix, the summary, exit 2, nothing on stdout"
t_eq "exit 2" "exit 2" "$(pp --no-such-flag)"
t_eq "stdout is empty" "" "$(OUT)"
t_has "the FAIL names the argument" "$(ERR)" "  FAIL: unknown argument --no-such-flag: nothing was scanned"
t_has "the fix reads the help" "$(ERR)" "  fix: sh $TOOL --help"
t_eq "the summary ends it" "port-paths: 0 ok, 1 failed, 0 warnings" "$(ERR | tail -1)"
t_eq "no legacy [port-paths] tag is left" 0 "$(ERR | grep -c '^\[port-paths\]')"

t_section "--verify with a CODE row: the note, the FAIL, its fix, the stale WARN and its fix, one summary"
t_eq "exit 1" "exit 1" "$(pp --verify)"
t_eq "the log is on stdout" "" "$(ERR)"
t_eq "the header" "── port-paths · verify" "$(OUT | head -1)"
t_has "the counts are a note" "$(OUT)" "  note: CODE=1 DOC=1 EXEMPT=0 (stale: 1)"
t_has "the FAIL says how many rows" "$(OUT)" "  FAIL: 1 executable or config literal(s) still name a pre-move path"
t_has "its fix lists them" "$(after_fail)" "  fix: sh $TOOL | awk"
t_has "a stale row is a WARN naming the file and text" "$(OUT)" '  WARN: STALE exemption: harbor/gone.sh — "no longer here" no longer appears'
t_has "and carries a fix" "$(OUT)" "  fix: delete that row from the table it lives in"
t_eq "the summary counts the failure and the warning" "port-paths: 0 ok, 1 failed, 1 warnings" "$(OUT | tail -1)"

t_section "--verify at CODE=0: an ok line and exit 0"
put "$P/harbor/bin/a.sh" 'echo fine'; git -C "$P/harbor" add -A
t_eq "exit 0" "exit 0" "$(pp --verify)"
t_has "the ok line says what held" "$(OUT)" "  ok: no CODE literal names a pre-move path (1 DOC mention(s) remain, not blocking)"
t_eq "the summary" "port-paths: 1 ok, 0 failed, 1 warnings" "$(OUT | tail -1)"

t_section "a scan that dies is exit 3 (D-29 unchecked), never a count"
t_eq "no place to write" "exit 3" "$(HOME="$H" CLAUDE_CONFIG_DIR="$C" PORT_ROOT="$P" PORT_PATHS_EXEMPT="$X" TMPDIR="$T/no-such-dir" sh "$TOOL" --verify >"$T/out" 2>"$T/err"; echo "exit $?")"
t_has "the FAIL says it is not a green" "$(OUT)" "  FAIL: the inventory scan failed: nothing was judged, and this is not a green"
t_has "its fix reruns the scan alone" "$(after_fail)" "  fix: sh $TOOL >/dev/null"
t_eq "and the summary ends it" "port-paths: 0 ok, 1 failed, 0 warnings" "$(OUT | tail -1)"

t_section "--selftest is a run"
t_eq "it passes" "exit 0" "$(pp --selftest)"
t_eq "the header" "── port-paths · selftest" "$(OUT | head -1)"
t_has "a case is an ok line" "$(OUT)" "  ok: match: shell default with \$HOME"
t_eq "the summary is the library's and counts no failure" 1 "$(OUT | tail -1 | grep -c '^port-paths: [0-9][0-9]* ok, 0 failed, 0 warnings$')"
t_eq "the old FAIL/SKIP shapes are gone" 0 "$(OUT | grep -c '^\(FAIL\|SKIP\) ')"
t_done
