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
# THE QUESTION: CONSTITUTION §2.11 says a false positive is a defect, not safety (a guard firing on ordinary work gets switched off). Injecting a rule
# at the moment it applies is void if that is most moments, and a unit test holds only the cases its author thought of; history answers it.
# THREE REPLAYS, each against its own real traffic: commit-msg (every commit message on the base branch), pre-push (every commit's changeset through the
# hook's selector), govern-hook (every Bash command in the transcript store). Replaying commits through the merge hook would be a category error.
# READ-ONLY. The transcript store is private: only counts are reported in full, and a command is printed only when it FIRES, truncated.
# Removed notes: docs/explanation/code-cases/bin-eval-hook-replay.md
set -eu

# --help BEFORE ANY WORK (S4, harbor#140): the text is the header read from THIS file, so help cannot drift; a sweep of `bin/*.sh --help` once ran
# past five minutes on scripts that treated the flag as a request to do work.
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
# The report is the run's log (contracts/logging.md, harbor#771); there is no data on stdout.
. "$ROOT/bin/library-log.sh"
log_init hook-replay
die() { log_fail "$1"; log_fix "$2"; log_end || :; exit "$3"; }
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SRC_DIR="${HARBOR_SESSION_TRANSCRIPTS:-$CFG/projects}"
BASE="${HARBOR_CI_BASE_BRANCH:-origin/main}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/harbor.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT INT TERM

MODE=all
case "${1:-}" in
  --commits) MODE=commits ;;
  --bash) MODE=bash ;;
  --self-test) MODE=selftest ;;
  '') ;;
  *) die "unknown flag $1: nothing was replayed" "sh $0 --help" 2 ;;
esac

# SELF-TEST: a measurement tool that cannot be wrong is a tool nobody checked.
if [ "$MODE" = selftest ]; then
  fail=0
  # The pre-filter excludes any command with no 'merge' substring (govern-hook's matcher needs the literal `pr merge`). That is the one claim that could
  # silently drop real fires, so it is asserted here rather than argued.
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

# T0a · commit-msg against every real commit message
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
  # Every fire is for a human to adjudicate: the hook's pattern IS the definition of a violation, so a second regex would be the same judgement again.
  [ "$fired" -eq 0 ] || log_note "Each fire is either a genuine pre-rule trailer or a false positive. Read them."
fi

# T0b · the pre-push gate against every real changeset
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

# T0c · the govern-hook matcher against every real Bash command
if [ "$MODE" = all ] || [ "$MODE" = bash ]; then
  log_head "T0c  bin/govern-hook.sh vs every Bash command in the transcript store"
  if [ ! -d "$SRC_DIR" ]; then
    log_skip "no transcript store at ${SRC_DIR#"$HOME"/} — nothing to replay."
  else
    # One command per line as a ready-made hook payload: jq escapes newlines inside the JSON string, so a heredoc stays ONE record (counting raw lines
    # inflated the denominator and flattered the fire rate). The pre-filter is PROVABLY EQUIVALENT, not a sample: the matcher needs a `gh` segment containing
    # `pr merge`, so a command with no `merge` cannot fire; --self-test asserts it and both sides of the split are printed.
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
