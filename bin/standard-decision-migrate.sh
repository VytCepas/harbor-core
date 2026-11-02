#!/usr/bin/env sh
# standard-decision-migrate.sh (harbor#1429) — move a repo's decision records onto the one shared shape, mechanically.
#
#   sh bin/standard-decision-migrate.sh --root <repo> records          write the shape into docs/decisions/NNNN-*.md
#   sh bin/standard-decision-migrate.sh --root <repo> --check records  report what would change; writes nothing
#   sh bin/standard-decision-migrate.sh --system <name> qualify <file>...   write bare D-<n> as <name>/D-<n> in those files
#   sh bin/standard-decision-migrate.sh --help
#
#   records   A record that opens with front matter gains `supersedes: -` and `superseded_by: -` after its `date:` line when it
#             lacks them; nothing else in it changes. A record with a legacy header (`**Date:**` / `**Status:**`, `- Status:` /
#             `- Date:` bullets, or plain `Status:` / `Date:` lines) gains front matter in front of its unchanged text:
#             alias D-<n> from its file number, status in MADR words, date, supersedes and superseded_by from `Supersedes:` and
#             `Superseded-by:` lines. "Superseded in part" and "supersedes in part" keep the record accepted and name the
#             reviser in `revised_by`, as harbor's records do; the legacy lines stay where they were, verbatim.
#   qualify   For a document read outside its repo (contracts/decision-reach.tsv): D-<n> becomes <system>/D-<n>.
#   Both are idempotent: a second run changes nothing (--check exits 1 while anything would change).
#   exit 0 done / nothing to do · 1 --check found work · 2 usage
set -eu
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH='' cd -- "$HERE" && pwd)"
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2
. "$HERE/library-log.sh"
log_init standard-decision-migrate
usage() { awk 'NR < 2 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$HERE/${0##*/}"; }
die2() { log_fail "$1"; log_fix "sh $0 --help"; log_end || :; exit 2; }

ROOT=""; SYSTEM=""; CHECK=0; MODE=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --check) CHECK=1 ;;
    --root) [ $# -ge 2 ] || die2 "--root wants a directory"; ROOT="$2"; shift ;;
    --system) [ $# -ge 2 ] || die2 "--system wants a name"; SYSTEM="$2"; shift ;;
    records|qualify) MODE="$1"; shift; break ;;
    *) die2 "unknown argument: $1" ;;
  esac
  shift
done
[ -n "$MODE" ] || die2 "no mode: records or qualify"
TMP="${TMPDIR:-/tmp}/sdm.$$"; trap 'rm -f "$TMP" "$TMP.new"' EXIT INT TERM
CHANGED=0
# put <file> <new content file>: replace the file when it differs, count it, say so
put() {
  cmp -s "$1" "$TMP.new" && return 0
  CHANGED=$((CHANGED + 1)); printf '%s %s\n' "$([ "$CHECK" = 1 ] && echo would-change || echo changed)" "$1"
  [ "$CHECK" = 1 ] || cat "$TMP.new" > "$1"
}

if [ "$MODE" = records ]; then
  [ -n "$ROOT" ] && [ -d "$ROOT/docs/decisions" ] || die2 "--root wants a repo with a docs/decisions/"
  for f in "$ROOT"/docs/decisions/[0-9][0-9][0-9][0-9]-*.md; do
    [ -f "$f" ] || continue
    n="${f##*/}"; n="${n%%-*}"
    if [ "$(sed -n 1p "$f")" = "---" ]; then
      # front matter already: add the two supersession fields, with the none value, after `date:` (before the closing rule if none)
      awk -v sup="$(sed -n '2,/^---$/p' "$f" | grep -c '^supersedes:' || :)" -v by="$(sed -n '2,/^---$/p' "$f" | grep -c '^superseded_by:' || :)" '
        NR == 1 { print; infm = 1; next }
        infm && /^date:/ { print; if (!sup) print "supersedes: -"; if (!by) print "superseded_by: -"; added = 1; next }
        infm && $0 == "---" { if (!added) { if (!sup) print "supersedes: -"; if (!by) print "superseded_by: -" } infm = 0; print; next }
        { print }' "$f" > "$TMP.new"
    else
      # legacy header → front matter in front of the unchanged text
      awk -v num="$n" '
        function lower(x) { return tolower(x) }
        function refs(x,  out, m) { out = ""; while (match(x, /ADR-[0-9]+/)) { m = substr(x, RSTART + 4, RLENGTH - 4) + 0
            out = out (out == "" ? "" : ", ") "D-" m; x = substr(x, RSTART + RLENGTH) } return out }
        NR <= 20 && /^(\*\*Status:\*\*|- Status:|Status:)/ && st == "" { st = $0; sub(/^(\*\*Status:\*\*|- Status:|Status:) */, "", st) }
        NR <= 20 && /^(\*\*Date:\*\*|- Date:|Date:)/ && dt == "" { dt = $0; sub(/^(\*\*Date:\*\*|- Date:|Date:) */, "", dt); if (match(dt, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) dt = substr(dt, RSTART, RLENGTH) }
        NR <= 20 && /^(- )?Supersedes( in part)?:/ && ss == "" { ss = $0 }
        NR <= 20 && /^(- )?Superseded-by:/ && sb == "" { sb = $0 }
        { line[NR] = $0 }
        END {
          t = lower(st); gsub(/\*/, "", t); head = t; sub(/[^a-z].*/, "", head)
          part = (t ~ /in part/)
          status = head
          if (head == "superseded" && part) status = "accepted"
          revby = ""
          if (part || (head == "accepted" && t ~ /superseded/)) { x = st; i = index(lower(x), "superseded"); revby = refs(substr(x, i)) }
          sup = "-"; if (ss != "" && ss !~ /in part|portion|parts? of/) { r = refs(ss); if (r != "") sup = r }
          by = "-"; if (sb != "") { r = refs(sb); if (r != "") by = r }
          if (status == "superseded" && by == "-") status = "superseded"
          if (st == "" || dt == "") { print "ERR " (st == "" ? "no Status line" : "no Date line") > "/dev/stderr"; exit 3 }
          print "---"; print "kind: decision-record"; print "status: " status; print "alias: D-" (num + 0); print "date: " dt
          print "supersedes: " sup; print "superseded_by: " by; if (revby != "") print "revised_by: " revby
          print "---"; print ""
          for (i = 1; i <= NR; i++) print line[i] }
      ' "$f" > "$TMP.new" || { log_fail "$f: no Status or Date line to read, so no front matter was written"; log_fix "add the front matter to $f by hand"; log_end || :; exit 2; }
    fi
    put "$f"
  done
else
  [ -n "$SYSTEM" ] || die2 "qualify wants --system <name>"
  for f in "$@"; do
    [ -f "$f" ] || die2 "no such file: $f"
    cp "$f" "$TMP.new"
    # a pass consumes the character after each id, so adjacent ids need a second pass; qualified ones are skipped (their `/`)
    for _pass in 1 2 3; do
      sed -E "s#(^|[^A-Za-z0-9_/-])D-([0-9]+)([^0-9A-Za-z]|\$)#\\1$SYSTEM/D-\\2\\3#g" "$TMP.new" > "$TMP"; cat "$TMP" > "$TMP.new"
    done
    put "$f"
  done
fi
[ "$CHECK" = 0 ] || [ "$CHANGED" = 0 ] || exit 1
log_ok "$MODE: $CHANGED file(s) $([ "$CHECK" = 1 ] && echo would change || echo changed)"; log_end || :
