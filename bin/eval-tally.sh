#!/usr/bin/env sh
# eval-tally.sh (harbor#293 · option A, comparative signal) — Harbor's first
# EXOGENOUS instrument: does a harness change make the work better? Two arms run
# the same task, the operator picks, this keeps score.
#
#   sh bin/eval-tally.sh record --task <id> --varied <label> --winner A|B|tie
#   sh bin/eval-tally.sh report [--days N] [--json]
#   sh bin/eval-tally.sh open                       tasks recorded with no winner yet
#
# #293 asks for SatisfactionCapture (how good was this session); this is a different signal, a comparative verdict between two arms. A and B must not
# share a field, so nothing here writes a satisfaction row. #293's falsifier is inherited: no verdicts after two weeks of use means close it on that evidence.
# WHY: every Harbor instrument is ENDOGENOUS (its input is Harbor's own output), so green proves self-consistency only (docs/explanation/
# verification-expanded.md, Endogenous and exogenous instruments). This one is EXOGENOUS because the winner is an ARGUMENT: nothing here reads a
# transcript, scores an output or asks a model. The refusal to infer is the whole instrument.
# --varied is REQUIRED: a tally with no independent variable says who won, never why.
# NOT HOST-SHARDED: `hostname` has answered both its real name and `Mac`, forking host-sharded ledgers into two halves that each read as complete.
# `record` WRITES WITHOUT AN --apply GATE: it appends one operator-typed line to a machine-local ledger, and a weekly habit behind a prompt stops (§2.11).
# INTEGERS AND LABELS ONLY, NO FREE-TEXT FIELD (#293's constraint): the ledger sits under $CFG/MEMORY, inside the tree worklog-push.sh stages for the
# private remote. The allowlist does not match AB/*.jsonl today, but safety by extension is one glob from none, so --varied is capped and control-char-refused.
# PRINTS IDS, LABELS AND COUNTS, NEVER CONTENT (CONSTITUTION §3).
# Removed notes: docs/explanation/code-cases/bin-eval-tally.md
set -eu

# stdout is data here (the report table, --json, the open list), so the log is on stderr (LOG_FD=2,
# contracts/logging.md, harbor#771).
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/library-log.sh"
log_init ab-tally
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2
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
  # --varied is a label and the cap keeps it one (otherwise it becomes the prose field this ledger lacks, harbor#293); a newline would also split one JSON record in two.
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
  # UTC and whole-second: a local-time stamp reorders rows across a DST boundary.
  _now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  jq -cn --arg at "$_now" --arg task "$TASK" --arg varied "$VARIED" \
         --arg winner "$WINNER" \
    '{at:$at, task:$task, varied:$varied, winner:$winner}' >> "$LEDGER"
  log_ok "recorded: $TASK  $VARIED  winner=$WINNER"
  log_note "ledger:   ${LEDGER#"$HOME"/}"
  log_end; exit $?
  ;;

open)
  # A row recorded with --winner tie is DECIDED. "Open" means two arms were started and the operator never came back.
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

  # THE n<5 FLOOR IS A VERIFICATION RULE, NOT A DISPLAY CHOICE: a win rate over three rows is noise wearing a percentage (CONSTITUTION §2.2).
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
