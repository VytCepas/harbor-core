#!/usr/bin/env sh
# skill-fire.sh (harbor#293 · the tier decision's verifier) — does a candidate
# skill roster actually FIRE on the work this operator does?
#
#   sh bin/skill-fire.sh --cases <file> --skills <dir>                 plan only
#   sh bin/skill-fire.sh --cases <file> --skills <dir> --apply --live  measure
#     … --json machine-readable · --keep leave the scratch project behind
# The roster is decided by running it: reading descriptions was wrong in both directions. Exogenous: the input is a real
# session's tool calls and only whether a skill fired is scored, never answer quality. ~/.claude/skills is never touched:
# the roster is copied into a scratch project's `.claude/skills` with disable-model-invocation stripped, so a skill is
# trialled as LISTED. It costs real money and time (the dry run prints measured per-case figures); the report always
# names the roster size, since a fire-rate without it is not comparable.
# CASES FILE FORMAT - tab-separated, `#` comments and blank lines skipped:
#   <id><TAB><expected-skill-or-NONE><TAB><prompt>
# Private case files: <private layer>/evals/skill-fire/ (harbor#1273). `NONE` is a REQUIRED negative control
# (CONSTITUTION §No.2.10): only a case that must NOT fire separates a working roster from one that fires on everything.
# Removed notes: docs/explanation/code-cases/bin-skill-fire.md
set -eu

# Stdout (the per-case table and score line) is read by the suite and --json readers; the log is on stderr (harbor#771).
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/library-log.sh"
log_init skill-fire
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2
# die <what failed> <fix> <exit> — FAIL, its fix, the summary, the exit code the tool always had.
die() { log_fail "$1"; log_fix "$2"; log_end || :; exit "$3"; }

CASES=''; SKILLS=''; MODE=plan; JSON=0; KEEP=0; LIVE_OK=0
usage() { sed -n '3,7p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --cases)  [ $# -ge 2 ] || die "--cases needs a file" "sh $0 --help" 2
              shift; CASES="$1" ;;
    --skills) [ $# -ge 2 ] || die "--skills needs a directory" "sh $0 --help" 2
              shift; SKILLS="$1" ;;
    --apply)  MODE=run ;;
    --live)   LIVE_OK=1 ;;
    --keep)   KEEP=1 ;;
    --json)   JSON=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown flag $1: no session was started" "sh $0 --help" 2 ;;
  esac
  shift
done

[ -n "$CASES" ]  || { usage >&2; exit 2; }
[ -f "$CASES" ]  || die "no cases file at $CASES" "sh $0 --help" 1
[ -n "$SKILLS" ] || die "--skills is required" "sh $0 --cases $CASES --skills <dir>" 2
[ -d "$SKILLS" ] || die "no skills directory at $SKILLS" "ls $SKILLS" 1
command -v jq >/dev/null 2>&1 || die "jq is required" "$(pkg_hint jq)" 1
command -v claude >/dev/null 2>&1 || die "the claude CLI is required" "command -v claude" 1

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# ── the live gate (lint D2) ─────────────────────────────────────────────────
# Every case is a real `claude -p` and lands a transcript in $CFG/projects, so a sweep writes the live store even
# though ~/.claude/skills is untouched; D2 keys on the write. Paths are compared RESOLVED: a trailing slash bypasses
# the string form (context-injection-install.sh).
_phys() { CDPATH='' cd -P -- "$1" 2>/dev/null && pwd -P || printf '%s' "$1"; }
LIVE_DIR="$HOME/.claude"
_is_live() { [ "$(_phys "$CFG")" = "$(_phys "$LIVE_DIR")" ]; }

if [ "$MODE" = run ] && _is_live && [ "$LIVE_OK" -eq 0 ]; then
  die "refusing the live config dir without an explicit --live" "sh $0 --cases $CASES --skills $SKILLS --apply --live" 1
fi

ROSTER=0
for d in "$SKILLS"/*/; do [ -f "$d/SKILL.md" ] && ROSTER=$(( ROSTER + 1 )); done
[ "$ROSTER" -gt 0 ] || die "$SKILLS holds no SKILL.md" "ls $SKILLS" 1

N_CASE=0
while IFS='	' read -r id want prompt; do
  case "$id" in ''|'#'*) continue ;; esac
  [ -n "${prompt:-}" ] || die "case '$id' has no prompt" "sed -n '/^$id/p' $CASES" 1
  N_CASE=$(( N_CASE + 1 ))
done < "$CASES"
[ "$N_CASE" -gt 0 ] || die "no usable cases in $CASES" "sh $0 --help" 1

# A sweep with no negative control cannot tell a working roster from one that fires on everything: refuse.
if ! awk -F'	' '$1 !~ /^#/ && $2 == "NONE" { found=1 } END { exit !found }' "$CASES"; then
  die "no NONE case in $CASES — a sweep with no negative control cannot discriminate" "printf 'control\\tNONE\\tstay quiet please\\n' >> $CASES" 1
fi

if [ "$MODE" = plan ]; then
  log_head "DRY RUN"
  log_note "roster      $ROSTER skill(s) from $SKILLS"
  log_note "cases       $N_CASE (each is one real \`claude -p\` session)"
  log_note "writes      a scratch project dir, and $N_CASE session transcript(s) in ${CFG#"$HOME"/}/projects"
  # The cost goes in the plan, scaled from the measured 2026-08-28 sweep (17 proportionate cases, 98 minutes): an ORDER, not a precision.
  log_note "cost        ~$(( N_CASE * 6 )) min and order-of \$$(( N_CASE * 6 )) at the 2026-08-28 rate"
  log_note "(measured: 5.8 min and ~\$6 a PROPORTIONATE case; a small case is ~20s and ~\$0.33, and sizing off that under-priced the last sweep by two orders of magnitude)"
  log_note "to run it: sh $0 --cases $CASES --skills $SKILLS --apply"
  log_end; exit $?
fi

PROJ="${TMPDIR:-/tmp}/skill-fire.$$"
mkdir -p "$PROJ/.claude/skills"
if [ "$KEEP" -eq 0 ]; then trap 'rm -rf "$PROJ"' EXIT INT TERM; fi
for d in "$SKILLS"/*/; do
  [ -f "$d/SKILL.md" ] || continue
  n="$(basename "$d")"
  mkdir -p "$PROJ/.claude/skills/$n"
  # Strip the hide flag in the copy, never at the source: a hidden skill is absent from the listing, so the flag would measure whether the model can invoke what it cannot see.
  sed '/^disable-model-invocation: *true$/d' "$d/SKILL.md" > "$PROJ/.claude/skills/$n/SKILL.md"
done

RES="$PROJ/results.tsv"
: > "$RES"

while IFS='	' read -r id want prompt; do
  case "$id" in ''|'#'*) continue ;; esac
  # `</dev/null` is the whole measurement: this loop is fed by `done < "$CASES"`, so without it the case file becomes
  # claude's stdin and is appended to the prompt, leaking the `want` column (a sweep was voided; every case scored ok).
  # Silent and reads as success. tests/skill/fire/fire.test.sh stubs `claude` and asserts stdin arrives empty.
  out="$( cd "$PROJ" && claude -p "$prompt" --output-format json </dev/null 2>/dev/null )" || out=''
  sid="$(printf '%s' "$out" | jq -r '.session_id // empty' 2>/dev/null || true)"
  fired='-'; _inv='-'; _read='-'
  if [ -n "$sid" ]; then
    t="$(find "$CFG/projects" -name "$sid.jsonl" -type f 2>/dev/null | head -1)"
    if [ -n "$t" ]; then
      # Two ways to reach a skill; counting only the Skill tool inverted results. A hidden skill cannot be invoked, so reading
      # its SKILL.md is the only route, and this box's governance trains that. Either counts as reaching it (a control that reads
      # a SKILL.md has not stayed quiet); the report keeps `invoked` and `consulted` in separate columns.
      _inv="$(jq -r '..|objects|select(.type? == "tool_use" and .name? == "Skill")|.input.skill' "$t" 2>/dev/null | sort -u | paste -sd, - )"
      _read="$(jq -r '..|objects|select(.type? == "tool_use")|.input|tostring' "$t" 2>/dev/null \
               | grep -oE 'skills/[a-z0-9-]+/SKILL\.md' \
               | sed -E 's|skills/([a-z0-9-]+)/SKILL\.md|\1|' | sort -u | paste -sd, - )"
      fired="$(printf '%s\n%s\n' "$_inv" "$_read" | tr ',' '\n' | sed '/^$/d' | sort -u | paste -sd, - )"
      [ -n "$fired" ] || fired='-'
      [ -n "$_inv" ]  || _inv='-'
      [ -n "$_read" ] || _read='-'
    fi
  fi
  # `?` is not a missing value: it asks WHAT fires, has no right answer to score, and does not move ok/MISS/FALSE-FIRE.
  if [ "$want" = '?' ]; then
    v=open
  elif [ "$want" = NONE ]; then
    [ "$fired" = '-' ] && v=ok || v=FALSE-FIRE
  else
    case ",$fired," in *",$want,"*) v=ok ;; *) v=MISS ;; esac
  fi
  printf '%s\t%s\t%s\t%s\n' "$id" "$want" "$fired" "$v" >> "$RES"
  printf '  %-22s want=%-20s invoked=%-20s read=%-20s %s\n' "$id" "$want" "$_inv" "$_read" "$v"
  case "$v" in
    ok)         log_ok "case $id: wanted $want, fired $fired" ;;
    open)       log_note "case $id: open question, fired $fired" ;;
    MISS)       log_fail "case $id: wanted $want, fired $fired"
                log_fix "sed -n '1,12p' $SKILLS/$want/SKILL.md # sharpen the description's USE WHEN triggers, then re-run the sweep" ;;
    FALSE-FIRE) log_fail "case $id: a NONE control fired $fired"
                log_fix "sed -n '1,12p' $SKILLS/${fired%%,*}/SKILL.md # narrow the description that over-triggers, then re-run the sweep" ;;
  esac
done < "$CASES"

echo
if [ "$JSON" -eq 1 ]; then
  jq -Rs --argjson roster "$ROSTER" '
    split("\n") | map(select(length>0) | split("\t"))
    | {roster: $roster, cases: map({id:.[0], want:.[1], fired:.[2], verdict:.[3]})}
  ' "$RES"
  log_end || :; exit 0
fi

OPEN="$(awk -F'\t' '$4=="open"{n++} END{print n+0}' "$RES")"
OK="$(awk -F'	' '$4=="ok"{n++} END{print n+0}' "$RES")"
MISS="$(awk -F'	' '$4=="MISS"{n++} END{print n+0}' "$RES")"
FF="$(awk -F'	' '$4=="FALSE-FIRE"{n++} END{print n+0}' "$RES")"
printf 'roster of %s — %s ok, %s missed, %s false fire(s), %s open over %s case(s)\n' \
  "$ROSTER" "$OK" "$MISS" "$FF" "$OPEN" "$N_CASE"
printf 'A fire-rate without the roster size is not comparable; both are printed for that reason.\n'
[ "$KEEP" -eq 0 ] || printf 'kept: %s\n' "$PROJ"
log_end; exit $?
