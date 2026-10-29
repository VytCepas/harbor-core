#!/usr/bin/env sh
# Helm L0 tooling (harbor#44, M2 support) — is that workflow actually running,
# or is it wedged?
#
# WHY. A background workflow reports nothing until it finishes, so "still going"
# and "died twenty minutes ago" look identical from the outside. During M2's
# design that ambiguity cost real time: two of four probes had never been given
# a concurrency slot and the other two were mid-grind, and the only way to tell
# was hand-reading file mtimes. This makes the same judgement in one command.
#
#   sh bin/session-workflow-progress.sh              # the most recent run
#   sh bin/session-workflow-progress.sh <run-id>     # a specific run
#   sh bin/session-workflow-progress.sh --all        # every run that still has live agents
#
# LIVENESS IS INFERRED FROM WRITE RECENCY, and that is the honest limit of it: an
# agent thinking hard between tool calls looks identical to one that is hung. The
# thresholds below are therefore reported, never enforced — this prints a state,
# it does not kill anything.
set -eu

. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/library-log.sh"
log_init wf-progress

ACTIVE_S=90        # wrote within this → definitely working
SLOW_S=420         # wrote within this → probably a long tool call or a long think

MODE=one
RUN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --all) MODE=all ;;
    -h|--help)
      echo "usage: session-workflow-progress.sh [<run-id>] [--all]"
      echo "  Reports per-agent liveness for background workflow runs."
      exit 0 ;;
    -*) log_fail "unknown option $1"; log_fix "sh $0 --help"; log_end || :; exit 1 ;;
    *)  RUN="$1" ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || { log_fail "jq is required and is not on PATH"; log_fix "$(pkg_hint jq)"; log_end || :; exit 1; }

# LIVE_DIR names the operator's real config dir deliberately: subagent
# transcripts are written there by Claude Code itself and nowhere else, so a
# CLAUDE_CONFIG_DIR override would point this reader at a directory that never
# contains any. Read-only throughout — this script opens nothing for writing.
LIVE_DIR="$HOME/.claude"
ROOT="$LIVE_DIR/projects"
[ -d "$ROOT" ] || {
  log_fail "no $ROOT (Claude Code writes subagent transcripts there)"
  log_nofix "bin/session-workflow-progress.sh (run a background workflow in Claude Code first)"
  log_end || :; exit 1; }

# `find | sort` on mtime rather than `ls -t`: the workflow dirs live under a
# per-session path that varies, so there is no single parent to list.
DIRS="$(find "$ROOT" -type d -name 'wf_*' 2>/dev/null || true)"
[ -n "$DIRS" ] || { log_note "no workflow runs found under $ROOT"; log_end; exit $?; }

# VALIDATE THE OUTPUT, NEVER THE EXIT CODE — the rule already written at
# bin/alert-probe.sh:93 and applied here late. `stat -f` means "format" to BSD stat and
# "file system status" to GNU stat, so on Linux the first call PRINTS a block of
# filesystem fields to stdout and THEN fails, and an `||` chain appends the
# second call's answer to that garbage. Both call sites below were reading it:
# `pick` interpolated a MULTI-LINE value into a single tab-separated row, which
# breaks the row structure `sort -rn | cut -f2-` depends on and can select a
# garbage path as "newest"; `age_of` fed it to arithmetic, which aborts the script
# under `set -eu`. Measured 2026-09-06 on GNU coreutils 9.4.
#
# The `|| echo 0` in each caller is KEPT rather than folded in here, because the
# two want opposite things from an unreadable file: 0 is the oldest possible SORT
# KEY (never picked as newest) but the largest possible AGE (reads as stalled).
# Both are the safe direction for their own caller, and a shared default could
# only be right for one. Digits or nothing is this function's whole contract.
mtime() { # <file> -> epoch seconds, or empty
  _v="$(stat -f %m "$1" 2>/dev/null || true)"
  case "$_v" in ''|*[!0-9]*) _v="$(stat -c %Y "$1" 2>/dev/null || true)" ;; esac
  case "$_v" in ''|*[!0-9]*) _v="" ;; esac
  printf '%s' "$_v"
}

pick() {
  if [ -n "$RUN" ]; then
    printf '%s\n' "$DIRS" | grep -F "$RUN" || true
    return
  fi
  # newest by journal mtime
  for d in $DIRS; do
    [ -f "$d/journal.jsonl" ] || continue
    _pm="$(mtime "$d/journal.jsonl")"
    printf '%s\t%s\n' "${_pm:-0}" "$d"
  done | sort -rn | { [ "$MODE" = all ] && cat || head -1; } | cut -f2-
}

NOW="$(date +%s)"
age_of() { # <file> -> seconds since last write
  _m="$(mtime "$1")"
  echo $(( NOW - ${_m:-0} ))
}
human() { # <seconds>
  if   [ "$1" -lt 60 ];   then printf '%ss' "$1"
  elif [ "$1" -lt 3600 ]; then printf '%sm%ss' $(( $1 / 60 )) $(( $1 % 60 ))
  else printf '%sh%sm' $(( $1 / 3600 )) $(( ($1 % 3600) / 60 ))
  fi
}

STALLED_ANY=0
for D in $(pick); do
  [ -d "$D" ] || continue
  J="$D/journal.jsonl"
  [ -f "$J" ] || continue

  STARTED="$(grep -c '"type":"started"' "$J" 2>/dev/null | head -1 | tr -d ' \n')"
  DONE="$(grep -c '"type":"result"' "$J" 2>/dev/null | head -1 | tr -d ' \n')"
  case "$STARTED" in ''|*[!0-9]*) STARTED=0 ;; esac
  case "$DONE"    in ''|*[!0-9]*) DONE=0 ;; esac

  log_head "${D##*/}"
  log_note "started $STARTED · finished $DONE · outstanding $(( STARTED - DONE )) · journal last wrote $(human "$(age_of "$J")") ago"

  # Which agentIds have already returned — those are DONE regardless of mtime.
  FIN="$(jq -r 'select(.type=="result") | .agentId' "$J" 2>/dev/null | tr '\n' ' ')"

  for A in "$D"/agent-*.jsonl; do
    [ -f "$A" ] || continue
    id="${A##*/agent-}"; id="${id%.jsonl}"
    age="$(age_of "$A")"
    calls="$(grep -c '"type":"tool_use"' "$A" 2>/dev/null | head -1 | tr -d ' \n')"
    case "$calls" in ''|*[!0-9]*) calls=0 ;; esac
    sz="$(wc -c < "$A" 2>/dev/null | tr -d ' ')"

    case " $FIN " in
      *" $id "*) state="DONE" ;;
      *) if   [ "$age" -le "$ACTIVE_S" ]; then state="ACTIVE"
         elif [ "$age" -le "$SLOW_S"   ]; then state="SLOW"
         else state="STALLED"; STALLED_ANY=1
         fi ;;
    esac

    # The last tool it reached for is the single most useful progress signal:
    # "still on Bash" after twenty minutes means a command is hanging, not that
    # the model is thinking.
    last="$(grep -o '"name":"[A-Za-z_]*"' "$A" 2>/dev/null | tail -1 | cut -d'"' -f4)"
    _msg="$state $id  $calls calls · $(( sz / 1024 ))KB · last write $(human "$age") · last tool ${last:-—}"
    case "$state" in
      DONE|ACTIVE) log_ok "$_msg" ;;
      SLOW)        log_note "$_msg" ;;
      *)           log_warn "$_msg"
                   log_fix "tail -c 2000 $A  # then TaskStop $id if it is wedged" ;;
    esac
  done
done

if [ "$STALLED_ANY" = 1 ]; then
  log_note "one or more agents have not written in over $(human "$SLOW_S"): a SUSPICION, not a verdict, since a long tool call looks the same"
  # Exit 3 is this tool's own contract for a suspected stall; it is not a failed check, so the summary says 0 failed.
  log_end || :; exit 3
fi
log_end; exit $?
