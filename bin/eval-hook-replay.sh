#!/usr/bin/env sh
# eval-hook-replay.sh (harbor#7) — measure the hook layer against REAL traffic, not
# against a fixture someone wrote while thinking about the hook.
#
#   sh bin/eval-hook-replay.sh              all three replays
#   sh bin/eval-hook-replay.sh --commits    the two git-hook replays only (no transcript read)
#   sh bin/eval-hook-replay.sh --bash       the govern-hook matcher only
#   sh bin/eval-hook-replay.sh --self-test  prove this tool's own classifier discriminates
#   HARBOR_SESSION_TRANSCRIPTS   override the transcript store (default: <config>/projects)
#
# THE QUESTION THIS ANSWERS, AND WHY IT IS THE ONE THAT DECIDES ADOPTION.
# CONSTITUTION §2.11: a false positive is a defect, not safety — a guard that
# fires on ordinary work gets switched off, and a disabled guard protects
# nothing. Every argument for injecting a rule at the moment it applies is void
# if "the moment it applies" turns out to be most moments. That is not
# answerable from a unit test, because a unit test contains exactly the cases
# its author thought of. It is answerable from history, and harbor has history.
#
# THREE REPLAYS, EACH AGAINST ITS OWN REAL TRAFFIC. A hook is judged by the
# stream it actually sits in, and the three hooks sit in three different ones:
#   commit-msg   every commit message on the base branch
#   pre-push     every commit's changeset, through the selector the hook uses
#   govern-hook  every Bash command in the transcript store
# Replaying commits through the merge hook would be a category error — it fires
# on a command, not on a commit — and getting that wrong would produce a
# confident number about nothing.
#
# READ-ONLY. It writes no file and mutates no repo. It reads the transcript
# store, which is private: only counts are reported in full, and a command is
# printed only when it FIRES, truncated, because a fire is the thing a human has
# to adjudicate and the other 10,000 are not.
set -eu

# --help BEFORE ANY WORK (S4, harbor#140). Placed immediately after strict mode
# so it is the first executable line: a --help that reaches an argument parser is
# a --help that a script with no parser ignores, and this file had none. Measured
# 2026-08-20: a sweep of `bin/*.sh --help` ran past five minutes because at least
# one script treated the flag as a request to do work, and five of the scripts
# with no --help at all are mutators. The text is the header, read out of THIS
# file at runtime, so a help message cannot drift from what the script says it is.
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
# The report is the run's log (contracts/logging.md, harbor#771); there is no data on stdout.
. "$ROOT/bin/library-log.sh"
log_init hook-replay
# die <what failed> <fix> <exit> — FAIL, its fix, the summary, the exit code the tool always had.
die() { log_fail "$1"; log_fix "$2"; log_end || :; exit "$3"; }
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SRC_DIR="${HARBOR_SESSION_TRANSCRIPTS:-${HARBOR_TRANSCRIPTS:-$CFG/projects}}"
BASE="${HARBOR_CI_BASE_BRANCH:-${HARBOR_BASE_BRANCH:-origin/main}}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/harbor.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT INT TERM

MODE=all
case "${1:-}" in
  --commits) MODE=commits ;;
  --bash) MODE=bash ;;
  --self-test) MODE=selftest ;;
  '') ;;
  *) die "unknown flag $1: nothing was replayed" "sh $0 --help" 2 ;;
esac

# ════════════════════════════════════════════════════════════════════════════
# SELF-TEST — a measurement tool that cannot be wrong is a tool nobody checked.
# ════════════════════════════════════════════════════════════════════════════
if [ "$MODE" = selftest ]; then
  fail=0
  # The pre-filter below excludes any command with no 'merge' substring, on the
  # grounds that govern-hook's matcher requires the literal phrase 'pr merge'.
  # That is the one claim in this file that could silently drop real fires, so
  # it is asserted rather than argued: a command the filter excludes must also
  # be one the hook does not fire on.
  for c in 'gh pr merge 1' 'echo hi' 'git rebase main' 'gh pr list'; do
    pre=1; case "$c" in *merge*) pre=0 ;; esac
    got=1
    printf '%s' "$c" | jq -Rs '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:.}}' \
      | CLAUDE_PROJECT_DIR="$ROOT" sh "$ROOT/bin/govern-hook.sh" 2>/dev/null | grep -q . && got=0
    if [ "$pre" -eq 1 ] && [ "$got" -eq 0 ]; then
      log_fail "the pre-filter would have dropped a real fire: $c"
      log_fix "sh $0 --self-test # then read the pre-filter in T0c against bin/govern-hook.sh's matcher"; fail=1
    else
      log_ok "prefilter=$pre hook=$got  $c"
    fi
  done
  [ "$fail" -eq 0 ] || { log_end || :; exit 1; }
  log_note "the merge pre-filter is sound on these shapes."
  log_end; exit $?
fi

command -v jq >/dev/null 2>&1 || die "jq is required" "$(pkg_hint jq)" 2

# ════════════════════════════════════════════════════════════════════════════
# T0a · commit-msg against every real commit message
# ════════════════════════════════════════════════════════════════════════════
if [ "$MODE" = all ] || [ "$MODE" = commits ]; then
  log_head "T0a  hooks/commit-msg vs every commit message on $BASE"
  n=0; fired=0
  git -C "$ROOT" log --format=%H "$BASE" > "$TMP/shas"
  while IFS= read -r sha; do
    [ -n "$sha" ] || continue
    n=$(( n + 1 ))
    git -C "$ROOT" log -1 --format=%B "$sha" > "$TMP/msg"
    if ! sh "$ROOT/hooks/commit-msg" "$TMP/msg" >/dev/null 2>&1; then
      fired=$(( fired + 1 ))
      log_note "FIRE  $(printf '%s' "$sha" | cut -c1-8)  $(git -C "$ROOT" log -1 --format=%s "$sha" | cut -c1-52)"
    fi
  done < "$TMP/shas"
  log_ok "$n message(s) replayed, $fired fired."
  # EVERY FIRE HERE IS FOR A HUMAN TO ADJUDICATE, and this tool deliberately does
  # not adjudicate for them. The hook's pattern IS the definition of a violation,
  # so a second regex asking "but was it REALLY a trailer?" would be the same
  # judgement wearing a machine's clothes.
  [ "$fired" -eq 0 ] || log_note "Each fire is either a genuine pre-rule trailer or a false positive. Read them."
fi

# ════════════════════════════════════════════════════════════════════════════
# T0b · the pre-push gate against every real changeset
# ════════════════════════════════════════════════════════════════════════════
if [ "$MODE" = all ] || [ "$MODE" = commits ]; then
  log_head "T0b  hooks/pre-push (via bin/test-suite-select.sh) vs every real changeset"
  total_suites="$(grep -cvE '^[[:space:]]*(#|$)' "$ROOT/contracts/suites.txt")"
  n=0; allsel=0; cheap=0; sum=0
  : > "$TMP/dist"
  while IFS= read -r sha; do
    [ -n "$sha" ] || continue
    changed="$(git -C "$ROOT" diff-tree --no-commit-id --name-only -r "$sha" 2>/dev/null || true)"
    [ -n "$changed" ] || continue
    n=$(( n + 1 ))
    sel="$(HARBOR_TEST_CHANGED="$changed" sh "$ROOT/bin/test-suite-select.sh" --list 2>/dev/null | grep -c '^RUN ' || true)"
    sel="${sel:-0}"
    sum=$(( sum + sel ))
    printf '%s\n' "$sel" >> "$TMP/dist"
    [ "$sel" -ge "$total_suites" ] && allsel=$(( allsel + 1 ))
    [ "$sel" -le 3 ] && cheap=$(( cheap + 1 ))
  done < "$TMP/shas"
  med="$(sort -n "$TMP/dist" | awk '{a[NR]=$1} END{print (NR? a[int((NR+1)/2)] : 0)}')"
  log_ok "$n changeset(s) replayed against $total_suites suites."
  log_note "median suites selected      $med"
  log_note "mean                        $(( n > 0 ? sum / n : 0 ))"
  log_note "selected EVERYTHING         $allsel  ($(( n > 0 ? allsel * 100 / n : 0 ))%)"
  log_note "selected 3 or fewer         $cheap  ($(( n > 0 ? cheap * 100 / n : 0 ))%)"
  log_note "A push gate is only affordable while the cheap lane is the common one."
fi

# ════════════════════════════════════════════════════════════════════════════
# T0c · the govern-hook matcher against every real Bash command
# ════════════════════════════════════════════════════════════════════════════
if [ "$MODE" = all ] || [ "$MODE" = bash ]; then
  log_head "T0c  bin/govern-hook.sh vs every Bash command in the transcript store"
  if [ ! -d "$SRC_DIR" ]; then
    log_skip "no transcript store at ${SRC_DIR#"$HOME"/} — nothing to replay."
  else
    # ONE COMMAND PER LINE, AS A READY-MADE HOOK PAYLOAD. jq emits the compact
    # envelope directly, so a command containing newlines stays ONE record — its
    # newlines are escaped inside the JSON string. Extracting raw command text
    # and counting lines would have inflated the denominator with every heredoc
    # and every multi-line script in the store, which makes the fire RATE look
    # better than it is: the flattering direction, and therefore the one to be
    # suspicious of.
    #
    # THE PRE-FILTER IS PROVABLY EQUIVALENT, NOT A SAMPLE. The hook's matcher
    # requires a segment whose first word is `gh` and which contains the literal
    # `pr merge`, so a command with no `merge` substring anywhere cannot fire.
    # `--self-test` asserts that rather than asking to be believed, and both
    # sides of the split are printed — a cap that is not reported reads as full
    # coverage.
    : > "$TMP/cmds"; : > "$TMP/fire"
    for f in "$SRC_DIR"/*/*.jsonl; do
      [ -f "$f" ] || continue
      jq -c '
        select(type=="object")
        | .message?.content?
        | select(type=="array") | .[]
        | select(.type=="tool_use" and .name=="Bash")
        | select((.input.command // "") != "")
        | {hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:.input.command}}' \
        "$f" 2>/dev/null >> "$TMP/cmds" || true
    done
    if [ -s "$TMP/cmds" ]; then
      total="$(wc -l < "$TMP/cmds" | tr -d ' ')"
      cand=0; fired=0
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        case "$line" in *merge*) ;; *) continue ;; esac
        cand=$(( cand + 1 ))
        out="$(printf '%s' "$line" | CLAUDE_PROJECT_DIR="$ROOT" sh "$ROOT/bin/govern-hook.sh" 2>/dev/null || true)"
        if [ -n "$out" ]; then
          fired=$(( fired + 1 ))
          printf '%s\n' "$(printf '%s' "$line" | jq -r '.tool_input.command' 2>/dev/null | tr '\n' ' ' | cut -c1-88)" >> "$TMP/fire"
        fi
      done < "$TMP/cmds"
      log_ok "$total Bash command(s) in the store."
      log_note "contained \"merge\" (the sound pre-filter)   $cand"
      log_note "provably excluded, cannot fire             $(( total - cand ))"
      log_note "FIRED                                      $fired   ($(( total > 0 ? fired * 1000 / total : 0 )) per 1000 commands)"
      if [ "$fired" -gt 0 ]; then
        log_note "every fire, for adjudication:"
        sort -u "$TMP/fire" | while IFS= read -r _fl; do log_note "  $_fl"; done
      fi
    else
      log_skip "no Bash records extracted."
    fi
  fi
fi

log_end; exit $?
