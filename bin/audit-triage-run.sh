#!/usr/bin/env sh
# judge-run (harbor#44 follow-through — M5's scheduling half) — run the ledger
# JUDGE off the session path, leave one line a SessionStart hook can read in
# microseconds. M5 built the judging; nothing ever ran it.
#
#   sh audit-triage-run.sh [--live | <config-dir>] [--apply]
#
# Exit 0 = the cache was written (or would be, on a dry run). Exit 1 = the judge
# could not run. Exit 2 = bad usage. FINDINGS ARE NOT AN ERROR: this is a writer,
# not a gate, and a non-zero exit on "the box has a crit" would make a scheduled
# job's exit status mean two different things.
#
# WHY THIS EXISTS. bin/audit-triage.sh judges the guard-decision ledger and
# NOTHING RUNS IT — it is in no installer payload and no scheduled job. Measured
# 2026-08-13: it reported 10 findings, worst `crit`, over 70,702 records, and no
# human had ever seen one of them. The missing link was never the judging. It was
# that judging happened only when somebody typed the command.
#
# WHY NOT A Stop OR SessionStart HOOK, which is the obvious wiring. Measured on
# this box, same day: a full run is 7 SECONDS. That is the argument
# launchd/com.harbor.status.usage.plist already records for the usage aggregator at 10s
# — CONSTITUTION §2.11, a gate that makes ordinary work wait is a gate that gets
# switched off, and a switched-off gate protects nothing. So the judging runs
# daily off the session path and writes a cache; the session only READS it.
#
# IT REPAIRS NOTHING, for audit-triage.sh's own reason: every surface that
# tool names is one guard-selfedit.sh protects, so a version that could fix them
# would be a version that can disable the floor. The cache carries the repair
# TEXT for a human; nothing here executes it.
#
# THE CACHE IS A DATED FACT, NOT A STATUS. The first line carries the stamp and
# the counts, so a reader can separate "this box is clean" from "nobody has
# judged this box in a week". An empty or absent status file cannot tell those
# apart — which is exactly the failure the pulse plist header records about the
# fleet-snapshot job's zero-byte error log, and it is the reason session
# staleness is computed from this stamp rather than from the file's mtime alone.
#
# THE JUDGE IS RESOLVED FROM THIS SCRIPT'S OWN DIRECTORY, never from the target
# under inspection — audit-triage.sh's header explains that hole at length: a
# hostile copy in an inspected tree could redefine the reporting functions and
# make the run report nothing while exiting 0. Same trust domain, same rule.
set -u

_phys() { CDPATH= cd -P -- "$1" 2>/dev/null && pwd -P || printf '%s' "$1"; }

DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
# stdout is the cache body, which is data, so the log is on stderr (LOG_FD=2, contracts/logging.md, harbor#771).
. "$DIR/library-log.sh"
log_init judge-run; LOG_FD=2
# die <what failed> <fix> [exit] — FAIL, its fix, the summary, then the exit code the tool always had (2).
die() { log_fail "$1"; log_fix "$2"; log_end || :; exit "${3:-2}"; }
FC="$DIR/audit-triage.sh"
LIVE_DIR="$HOME/.claude"

TGT=""; APPLY=0; EXPLICIT_LIVE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --live)  TGT="$LIVE_DIR"; EXPLICIT_LIVE=1 ;;
    --apply) APPLY=1 ;;
    -h|--help)
      printf 'usage: audit-triage-run.sh [--live | <config-dir>] [--apply]\n' >&2; exit 2 ;;
    -*) die "unknown flag $1: nothing was judged" "sh $0 --help" ;;
    *)  [ -z "$TGT" ] || die "two targets given: $TGT and $1" "sh $0 [--live | <config-dir>] [--apply]"
        TGT="$1" ;;
  esac
  shift
done
[ -n "$TGT" ] || { printf 'usage: audit-triage-run.sh [--live | <config-dir>] [--apply]\n' >&2; exit 2; }
[ -d "$TGT" ] || die "not a directory: $TGT" "sh $0 --help"

# The live-dir gate, in the house idiom (lint D1/D2): compare RESOLVED paths, not
# strings — `~/.claude`, `~/.claude/` and `~/x/../.claude` are one directory and
# no two of them are one string. A write to the real box requires having NAMED it
# `--live`; passing the path literally is the accident this refuses.
if [ "$APPLY" = 1 ] && [ "$(_phys "$TGT")" = "$(_phys "$LIVE_DIR")" ] && [ "$EXPLICIT_LIVE" = 0 ]; then
  die "refusing --apply on the live config dir without an explicit --live" "sh $0 --live --apply"
fi

# The cache would be a fact about nothing without the judge.
[ -f "$FC" ] || die "no judge beside this script ($FC)" "sh bin/deploy-runtime-install.sh # installs audit-triage.sh next to audit-triage-run.sh" 1
command -v jq >/dev/null 2>&1 || die "jq is required to read the judge (no partial parse is attempted)" "$(pkg_hint jq)" 1

if [ "$EXPLICIT_LIVE" = 1 ]; then J="$(sh "$FC" --live --json 2>/dev/null)"
else                             J="$(sh "$FC" "$TGT" --json 2>/dev/null)"; fi

# An unparseable payload is NOT written as "clean". A cache that reads clean
# because the judge crashed is the absence-reads-as-healthy shape this whole
# wiring exists to remove.
printf '%s' "$J" | jq -e 'has("findings")' >/dev/null 2>&1 || {
  die "the judge produced no parseable JSON — cache NOT written" "sh $FC $TGT --json" 1
}

STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# WARNS ARE ITEMISED HERE AND STILL NOT SPOKEN AT SessionStart. Those are two
# different decisions and an earlier version conflated them: the cache carried
# `warn=N` and nothing else, so the number on the statusline could not be
# resolved back to a finding by any means. Measured 2026-09-04: the cache read
# `crit=0 warn=17`, and by the time anyone asked what the 17 were, the ledger
# generation they were computed over had been rotated away — the answer was
# unrecoverable from the box, permanently, and had to be reconstructed from a
# launchd stdout log that happens to keep two runs.
#
# The SessionStart silence is the part that was right and stays: session-verdicts.sh
# matches `crit ` alone (its § the crit loop), so these lines are inert there and a
# warn still reaches nobody mid-session. What changes is that the batch-review tier
# now HAS something to review. Same reasoning as FC-4's own: a verdict with no
# human-visible surface is not a verdict.
#
# CRITS FIRST, THEN WARNS. Both readers of this file that parse lines at all key
# on the first token, so order is for the human opening it with `cat`.
BODY="$(printf '%s' "$J" | jq -r --arg s "$STAMP" '
  "judged \($s) worst=\(.worst // "none") crit=\([.findings[]|select(.severity=="crit")]|length) warn=\([.findings[]|select(.severity=="warn")]|length) records=\(.records // 0)",
  (.findings[] | select(.severity=="crit") | "crit \(.rule)|\(.subject)|\(.repair)"),
  (.findings[] | select(.severity=="warn") | "warn \(.rule)|\(.subject)|\(.repair)")')"

OUT="$TGT/.helm-judge"
if [ "$APPLY" = 1 ]; then
  # Write via a temp file in the same directory and rename: a SessionStart hook
  # may read this at any moment, and a half-written cache is a verdict nobody
  # can trust. umask keeps it owner-only for the same reason the ledger is.
  ( umask 077; printf '%s\n' "$BODY" > "$OUT.tmp" ) || {
    die "cannot write $OUT.tmp" "ls -ld $TGT" 1; }
  mv -f "$OUT.tmp" "$OUT" || die "cannot install $OUT" "ls -ld $TGT" 1
  log_ok "wrote $OUT"
else
  log_note "DRY RUN — would write $OUT (pass --apply)"
fi
printf '%s\n' "$BODY"
log_end; exit $?
