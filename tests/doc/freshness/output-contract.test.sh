#!/usr/bin/env sh
# doc-freshness.sh's output follows contracts/logging.md (harbor#771): stdout is the report's table and only that
# (status-dashboard-generate.sh reads it); the run log is on stderr; a stale document is a WARN with its fix; the run ends
# with the summary. A fixture git repo stands in for the tree, so no real document's age is read.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE; export GIT_CONFIG_NOSYSTEM=1
R="$T_TMP/r"; mkdir -p "$R/bin"; cp "$T_ROOT/bin/doc-freshness.sh" "$T_ROOT/bin/library-log.sh" "$R/bin/"
git -C "$R" init -q; git -C "$R" config user.email t@t; git -C "$R" config user.name t
printf 'x\n' > "$R/FRESH.md"; printf 'x\n' > "$R/OLD.md"; printf 'todo: later\n' > "$R/NOTES.md"
git -C "$R" add -A
GIT_COMMITTER_DATE="2020-01-01T00:00:00Z" GIT_AUTHOR_DATE="2020-01-01T00:00:00Z" git -C "$R" commit -q -m old -- OLD.md
git -C "$R" commit -q -m new
export HARBOR_TELOS_DIR="$T_TMP/no-telos"
run() { sh "$R/bin/doc-freshness.sh" "$@" >"$T_TMP/out" 2>"$T_TMP/err"; echo "exit $?"; }
OUT() { cat "$T_TMP/out"; }; ERR() { cat "$T_TMP/err"; }

t_section "the report: the table on stdout, the log on stderr"
t_eq "exit 0 (age is a priority signal)" "exit 0" "$(run)"
t_eq "stdout starts with the table header" "DOCUMENT" "$(OUT | head -1 | awk '{print $1}')"
t_has "the stale document is a table row" "$(OUT)" "OLD.md"
t_eq "no log line is mixed into stdout" 0 "$(OUT | grep -c '^  \(ok\|FAIL\|WARN\|note\|skip\|fix\):')"
t_eq "the header is on stderr" "── freshness · documents, stalest first" "$(ERR | head -1)"
t_has "a stale document is a WARN" "$(ERR)" "  WARN: 1 document(s) past threshold"
t_has "with its fix" "$(ERR)" "  fix: sh $R/bin/doc-freshness.sh"
t_has "an absent working context is a note" "$(ERR)" "  note: working context ABSENT"
t_eq "the summary ends stderr" "freshness: 0 ok, 0 failed, 1 warnings" "$(ERR | tail -1)"
t_eq "no legacy prose is left on stdout" 0 "$(OUT | grep -c 'Nothing past\|document(s) past\|Open questions')"

t_section "nothing stale: an ok line"
git -C "$R" rm -q -f OLD.md; git -C "$R" commit -q -m drop
run >/dev/null
t_has "the ok line" "$(ERR)" "  ok: nothing past its threshold"
t_eq "the summary" "freshness: 1 ok, 0 failed, 0 warnings" "$(ERR | tail -1)"

t_section "--open: the markers on stdout, the log on stderr"
t_eq "exit 0" "exit 0" "$(run --open)"
t_has "a marker line is data" "$(OUT)" "NOTES.md:1:"
t_eq "no log line on stdout" 0 "$(OUT | grep -c '^  \(ok\|FAIL\|WARN\|note\|skip\|fix\):')"
t_eq "the header" "── freshness · open markers (TBD / TODO / OPEN / undecided / awaiting)" "$(ERR | head -1)"
t_eq "the summary" "freshness: 0 ok, 0 failed, 0 warnings" "$(ERR | tail -1)"

t_section "a usage error: FAIL, its fix, exit 2, nothing on stdout"
t_eq "exit 2" "exit 2" "$(run --bogus)"
t_eq "stdout is empty" "" "$(OUT)"
t_has "the FAIL names the flag" "$(ERR)" "  FAIL: unknown flag --bogus (accepts: --open)"
t_eq "the next line is its fix" "  fix: sh $R/bin/doc-freshness.sh --help" "$(awk '/^  FAIL:/ { f = 1; next } f { print; exit }' "$T_TMP/err")"
t_eq "an extra operand exits 2" "exit 2" "$(run --open stray)"
t_has "and is named" "$(ERR)" "  FAIL: unexpected argument stray"
t_done
