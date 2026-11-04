#!/usr/bin/env sh
# admission-replay.sh (harbor#1030) — replay the guard corpus and diff the verdicts of two runs: a refactor of the floor changes no verdict.
#
#   sh bin/admission-replay.sh run <out.tsv> [--only P]  run every tests/admission suite, or those under tests/admission/P; each table row appends `suite TAB row TAB verdict` to <out.tsv>
#   sh bin/admission-replay.sh diff <before> <after>  the rows whose verdict differs, or is missing from either run; exit 1 on any
#                                                     [--partial: <after> was made with --only, so <before> is cut to the suites it ran]
#   sh bin/admission-replay.sh --help
#
# THE CONTRACT. A run on the base commit and a run on the branch, same corpus: the diff is empty, apart from a list of intended changes
# that this tool does not know about, so a verdict that moves is a blocker to report, never an expectation to update. The log is written
# by tests/lib/table.sh (T_VERDICT_LOG); suites that assert without a table (the ledger, the installer) must pass instead, and `run`
# exits 1 when a suite fails. Exit 0 pass · 1 a failed suite or a difference · 2 usage.
set -eu
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"; . "$HERE/library-log.sh"; log_init admission-replay; ROOT="$(CDPATH='' cd -- "$HERE/.." && pwd)"
usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; }
case "${1:-}" in
  run)
    [ $# -eq 2 ] || { [ $# -eq 4 ] && [ "$3" = --only ]; } || { usage >&2; exit 2; }
    out="$2"; : > "$out"; only="${4:-}"
    set -- $(grep "^tests/admission/$only" "$ROOT/contracts/suites.txt")
    [ $# -gt 0 ] || { log_fail "no admission suite starts with tests/admission/$only"; log_fix "sh bin/admission-replay.sh run <out.tsv> --only <a directory under tests/admission/>"; exit 2; }
    T_VERDICT_LOG="$out" sh "$HERE/test-suite-run.sh" "$@"
    log_ok "$(grep -c . "$out" || :) row verdict(s) recorded in $out"; log_end ;;
  diff)
    [ $# -eq 3 ] || { [ $# -eq 4 ] && [ "$4" = --partial ]; } || { usage >&2; exit 2; }
    [ -s "$2" ] && [ -s "$3" ] || { log_fail "an empty or missing run: nothing was compared"; log_fix "sh bin/admission-replay.sh run <out.tsv> on each side first"; exit 2; }
    LC_ALL=C sort -u "$3" > "$3.sorted"
    if [ "${4:-}" = --partial ]; then
      # a run made with --only: compared with the same suites of the full run, never with all of it
      cut -f1 "$3.sorted" | LC_ALL=C sort -u > "$3.suites"
      awk -F'\t' 'NR == FNR { S[$1] = 1; next } $1 in S' "$3.suites" "$2" | LC_ALL=C sort -u > "$2.sorted"; rm -f "$3.suites"
    else LC_ALL=C sort -u "$2" > "$2.sorted"; fi
    awk -F'\t' 'NR == FNR { B[$1 FS $2] = $3; next } { k = $1 FS $2; A[k] = $3; if (!(k in B)) print "ADDED\t" k "\t-\t" $3; else if (B[k] != $3) print "DIFF\t" k "\t" B[k] "\t" $3 }
      END { for (k in B) if (!(k in A)) print "MISSING\t" k "\t" B[k] "\t-" }' "$2.sorted" "$3.sorted" | LC_ALL=C sort > "$3.diff"
    n="$(grep -c . "$3.diff" || :)"
    [ "$n" -eq 0 ] || cat "$3.diff"
    if [ "$n" -eq 0 ]; then log_ok "$(grep -c . "$2.sorted") row(s) before, $(grep -c . "$3.sorted") after, 0 differ"
    else log_fail "$(grep -c . "$2.sorted") row(s) before, $(grep -c . "$3.sorted") after, $n differ"; log_fix "a moved verdict is a blocker: report it, do not update an expectation"; fi
    rm -f "$2.sorted" "$3.sorted" "$3.diff"
    log_end ;;
  -h|--help) usage ;;
  *) usage >&2; exit 2 ;;
esac
