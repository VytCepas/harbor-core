#!/usr/bin/env sh
# eval-tally.sh (harbor#293 · option A, comparative signal) — Harbor's first
# EXOGENOUS instrument: does a harness change make the work better? Two arms run
# the same task, the operator picks, this keeps score.
#
#   sh bin/eval-tally.sh record --task <id> --varied <label> --winner A|B|tie
#   sh bin/eval-tally.sh report [--days N] [--json]
#   sh bin/eval-tally.sh open                       tasks recorded with no winner yet
#
# ITS TICKET IS #293 AND ITS SIGNAL IS NOT #293's. That ticket asks for
# SatisfactionCapture — how good was this session — and demands a decision before
# an implementation: VOID it, build the consumer first, or build the narrow
# explicit record only. This is the third shape applied to a DIFFERENT signal: a
# comparative verdict between two arms, not a rating of one. #293's warning that
# "A and B are different measurements and must not share a field" is why they are
# different files as well: nothing here writes a satisfaction row, and #293 stays
# open and undecided.
#
# #293's FALSIFIER IS INHERITED VERBATIM: if this surface carries no verdicts
# after two weeks of ordinary use, the honest reading is that it should not have
# been built, and it should be closed by that evidence rather than by argument.
#
# WHY THIS EXISTS. Measured 2026-08-27: 88% of bin/ line-mass is Harbor governing,
# testing or observing Harbor, and 44 test suites answer "does Harbor work". Not
# one answers "is the work better". Every such instrument is ENDOGENOUS — its
# input is Harbor's own output, so green proves self-consistency and nothing else
# (docs/explanation/verification-expanded.md § Endogenous and exogenous instruments).
#
# WHAT MAKES THIS ONE EXOGENOUS, AND IT IS ONE LINE OF CODE: the winner is an
# ARGUMENT. Nothing here reads a transcript, scores an output, or asks a model.
# The moment this script can derive a winner it stops being able to prove
# anything, because it would then be judging by the same faculty that produced
# the work. The refusal to infer is the whole instrument.
#
# --varied IS REQUIRED, and the check is not bureaucracy. A tally with no
# independent variable records which arm won and can never say why, which is a
# ledger that accumulates rows and settles no argument.
#
# NOT HOST-SHARDED, DELIBERATELY. bin/status-usage-aggregate.sh keys its ledger by
# $HOST; `hostname` on this box has been measured answering both its real name
# and a bare `Mac`, and the flip forked every host-sharded ledger into two halves
# that each read as complete. One file, no shard, no fork.
#
# `record` WRITES WITHOUT AN --apply GATE, unlike audit-triage-run.sh and
# status-usage-aggregate.sh. Those derive a whole file and can clobber; this appends one
# operator-typed line to a machine-local ledger, and CONSTITUTION §№2.11 is the
# reason to leave it ungated — a weekly habit behind a confirmation prompt is a
# habit that stops. `report` and `open` write nothing.
#
# INTEGERS AND LABELS ONLY — THERE IS NO FREE-TEXT FIELD, AND THAT IS #293's
# CONSTRAINT RATHER THAN A STYLE CHOICE. A `--note` was drafted and cut. The
# ledger lives under $CFG/MEMORY, and `worklog-push.sh` sets
# LOG_DIR="${HARBOR_LOG_DIR:-$CFG/MEMORY}" — so this file sits INSIDE the tree
# that gets staged for the private memory-store remote. It is safe today only by
# extension: the allowlist is deny-by-default and its globs are
# WORK/sessions/*/*.md, KNOWLEDGE/*.md, LEARNING/*.md, WISDOM/*.md, IDEAS.md,
# README.md, .gitignore — none of which can match AB/*.jsonl (checked
# 2026-08-28). Safety by extension is one added glob away from being no safety,
# and #293 records a harvester killed for writing prose into a directory that WAS
# inside the allowlist. So the field that would carry operator prose does not
# exist, and --varied is capped and control-char-refused below to stop it
# becoming one by drift.
#
# PRINTS IDS, LABELS AND COUNTS, NEVER CONTENT (CONSTITUTION §3). Nothing here
# reads a transcript or emits a path under $HOME.
set -eu

# stdout is data here (the report table, --json, the open list), so the log is on stderr (LOG_FD=2,
# contracts/logging.md, harbor#771).
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/library-log.sh"
log_init ab-tally; LOG_FD=2
# die <what failed> <fix> [exit] — FAIL, its fix, the summary, then the exit code the tool always had (2).
die() { log_fail "$1"; log_fix "$2"; log_end || :; exit "${3:-2}"; }

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
LEDGER_DIR="$CFG/MEMORY/AB"
LEDGER="$LEDGER_DIR/verdicts.jsonl"

usage() { sed -n '3,7p' "$0" | sed 's/^# \{0,1\}//'; }

[ $# -gt 0 ] || { usage >&2; exit 2; }
VERB="$1"; shift

TASK=''; VARIED=''; WINNER=''; DAYS=''; JSON=0
VARIED_MAX=48
while [ $# -gt 0 ]; do
  case "$1" in
    --task)   [ $# -ge 2 ] || die "--task needs a value" "sh $0 --help"
              shift; TASK="$1" ;;
    --varied) [ $# -ge 2 ] || die "--varied needs a value" "sh $0 --help"
              shift; VARIED="$1" ;;
    --winner) [ $# -ge 2 ] || die "--winner needs A, B or tie" "sh $0 --help"
              shift; WINNER="$1" ;;
    --note)   die "--note was removed — this ledger holds integers and labels only (harbor#293)" "sh $0 record --task <id> --varied <label> --winner A|B|tie" ;;
    --days)   [ $# -ge 2 ] || die "--days needs a number" "sh $0 --help"
              shift; DAYS="$1" ;;
    --json)   JSON=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown flag $1: nothing was recorded" "sh $0 --help" ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || die "jq is required" "$(pkg_hint jq)" 1

case "$VERB" in
record)
  [ -n "$TASK" ]   || die "record needs --task" "sh $0 record --task <id> --varied <label> --winner A|B|tie"
  [ -n "$VARIED" ] || die "record needs --varied — a tally with no independent variable settles nothing" "sh $0 record --task $TASK --varied <label> --winner A|B|tie"
  # --varied IS A LABEL AND THE CAP IS WHAT KEEPS IT ONE. Without a bound it
  # becomes the prose field this ledger deliberately does not have (harbor#293),
  # one long verdict at a time, and nobody would notice until the first push glob
  # widened. Control characters are refused outright: a newline would also split
  # one JSON record into two lines and silently corrupt every later read.
  if [ "${#VARIED}" -gt "$VARIED_MAX" ]; then
    die "--varied is a label, max $VARIED_MAX chars (got ${#VARIED}). Name the variable, do not describe it." "sh $0 record --task $TASK --varied <a short label> --winner A|B|tie"
  fi
  case "$VARIED" in
    *[[:cntrl:]]*) die "--varied must not contain control characters or newlines" "sh $0 record --task $TASK --varied <a plain label> --winner A|B|tie" ;;
  esac
  case "$WINNER" in
    A|B|tie) : ;;
    '') die "record needs --winner A, B or tie. This tool never infers one." "sh $0 record --task $TASK --varied $VARIED --winner A|B|tie" ;;
    *)  die "--winner must be A, B or tie (got '$WINNER')" "sh $0 record --task $TASK --varied $VARIED --winner A|B|tie" ;;
  esac
  mkdir -p "$LEDGER_DIR"
  # DATE IS UTC AND WHOLE-SECOND. A local-time stamp reorders rows across a DST
  # boundary, and this file is append-ordered by nothing but its own timestamps.
  _now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  jq -cn --arg at "$_now" --arg task "$TASK" --arg varied "$VARIED" \
         --arg winner "$WINNER" \
    '{at:$at, task:$task, varied:$varied, winner:$winner}' >> "$LEDGER"
  log_ok "recorded: $TASK  $VARIED  winner=$WINNER"
  log_note "ledger:   ${LEDGER#"$HOME"/}"
  log_end; exit $?
  ;;

open)
  # A row recorded with --winner tie is DECIDED, not open. "Open" here means a
  # task the operator started two arms on and never came back to; it exists so an
  # abandoned comparison is visible rather than quietly absent from the tally.
  [ -f "$LEDGER" ] || { log_note "no ledger yet at ${LEDGER#"$HOME"/}"; log_end; exit $?; }
  jq -r 'select(.winner == "") | .task' "$LEDGER" 2>/dev/null | sort -u
  log_ok "listed the tasks recorded with no winner"
  log_end; exit $?
  ;;

report)
  [ -f "$LEDGER" ] || { log_note "no ledger yet at ${LEDGER#"$HOME"/} — nothing has been recorded"; log_end; exit $?; }
  CUT=''
  if [ -n "$DAYS" ]; then
    # BSD `date -v-Nd`, else GNU `date -d "N days ago"` (harbor#618): each rejects the other's flag.
    CUT="$(date -u -v-"${DAYS}"d '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d "$DAYS days ago" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || :)"
    [ -n "$CUT" ] || die "could not compute a cutoff for --days $DAYS" "sh $0 report --days 7" 1
  fi

  if [ "$JSON" -eq 1 ]; then
    jq -s --arg cut "$CUT" '
      map(select($cut == "" or .at >= $cut))
      | group_by(.varied)
      | map({varied: .[0].varied,
             n: length,
             A: (map(select(.winner=="A")) | length),
             B: (map(select(.winner=="B")) | length),
             tie: (map(select(.winner=="tie")) | length)})
    ' "$LEDGER"
    log_ok "reported the tally as JSON"
    log_end; exit $?
  fi

  # THE n<5 FLOOR IS A VERIFICATION RULE, NOT A DISPLAY CHOICE. A win rate over
  # three rows is noise wearing a percentage, and printing one invites exactly the
  # confident-and-wrong conclusion this whole instrument exists to prevent
  # (CONSTITUTION §№2.2 — confidence requires source).
  jq -rs --arg cut "$CUT" '
    map(select($cut == "" or .at >= $cut))
    | if length == 0 then "no verdicts in this window"
      else ( group_by(.varied)
             | map({v: .[0].varied,
                    n: length,
                    a: (map(select(.winner=="A")) | length),
                    b: (map(select(.winner=="B")) | length),
                    t: (map(select(.winner=="tie")) | length)})
             | sort_by(-.n)
             | map( "  " + (.v | .[0:34] | . + (" " * (34 - length)))
                    + " n=" + (.n|tostring)
                    + "  A=" + (.a|tostring)
                    + " B=" + (.b|tostring)
                    + " tie=" + (.t|tostring)
                    + (if .n < 5 then "   (too few to read)"
                       elif .a > .b then "   B->A favoured"
                       elif .b > .a then "   A->B favoured"
                       else "   no separation" end) )
             | join("\n") )
      end
  ' "$LEDGER"
  echo
  echo "  A = control (the harness as it was)   B = the change under test"
  echo "  'too few to read' is the honest verdict under 5 paired runs, not a placeholder."
  log_ok "reported the tally"
  log_end; exit $?
  ;;

*) usage >&2; exit 2 ;;
esac
