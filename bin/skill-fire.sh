#!/usr/bin/env sh
# skill-fire.sh (harbor#293 · the tier decision's verifier) — does a candidate
# skill roster actually FIRE on the work this operator does?
#
#   sh bin/skill-fire.sh --cases <file> --skills <dir>                 plan only
#   sh bin/skill-fire.sh --cases <file> --skills <dir> --apply --live  measure
#     … --json machine-readable · --keep leave the scratch project behind
#
# WHY THIS EXISTS. Every argument about which skills to keep has been settled by
# reading descriptions and guessing. Measured 2026-08-28, guessing was wrong in
# both directions: 25 of 27 vendored skills had never been opened in 600
# sessions, AND a skill that looked dead fired as the first tool call the moment
# it was listed against a proportionate task. Neither fact was predictable from
# the SKILL.md. So the roster is decided by running it.
#
# THE MEASUREMENT IS EXOGENOUS (DOCTRINE/verification-expanded.md). The input is
# a real session's real tool calls, not this repo's opinion of what should have
# happened. Nothing here scores an answer's quality — only whether the skill
# fired — because quality is a judgement and `sh` cannot make one.
#
# IT NEVER TOUCHES ~/.claude/skills. The candidate roster is copied into a
# scratch project's `.claude/skills`, which Claude Code reads as a project-scoped
# skill directory. That is also what makes `disable-model-invocation` testable
# from both sides: the copy is rewritten with the flag stripped, so a skill can
# be trialled as LISTED without the live box ever being modified. guard-selfedit
# refuses a live-skills edit and it is right to; this is the route that does not
# need one.
#
# IT COSTS REAL MONEY AND REAL TIME, AND THE FIRST ESTIMATE HERE WAS WRONG BY
# TWO ORDERS OF MAGNITUDE. This header said "~20s and ~$0.33 for a small case",
# which was true of a small case and worthless as a planning number, because a
# sweep worth running is made of PROPORTIONATE cases and those are what a skill
# has to fire on. Measured 2026-08-28 over 17 proportionate cases against a
# roster of 39: 98 minutes wall clock, 5.8 minutes a case, 699k output tokens
# and ~32M of cache reads — on the order of $100, not $6. The estimate was
# quoted twice while planning off it and under-priced the sweep both times.
# So the DRY RUN now prints the measured per-case figures rather than a
# reassuring sentence, because the plan output is where the decision is made and
# a number nobody sees cannot inform it.
#
# THE CONFOUND IS PRINTED, NEVER HIDDEN. A roster of one is an easier choice than
# a roster of thirty, so a skill that fires alone may lose against its siblings.
# The report always names the roster size, because a fire-rate without it is a
# number nobody can compare.
#
# CASES FILE FORMAT — tab-separated, `#` comments and blank lines skipped:
#   <id><TAB><expected-skill-or-NONE><TAB><prompt>
# The operator's own case files are private data: <private layer>/evals/skill-fire/ (harbor#1273).
# `NONE` is a REQUIRED negative control, not an optional extra: a roster that
# fires on everything is as useless as one that fires on nothing, and only a case
# that must NOT fire can tell those apart (CONSTITUTION §No.2.10).
set -eu

# The per-case table and the score line on stdout are the report the suite and --json readers consume, so they
# stay byte-identical; the log is on stderr (LOG_FD=2, CONTRACTS/logging.md, harbor#771).
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/log-lib.sh"
log_init skill-fire; LOG_FD=2
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
# THIS DOES NOT WRITE THE CONFIG DIR ITSELF, AND IT WRITES IT ANYWAY. The roster
# copy goes to a scratch project under TMPDIR and ~/.claude/skills is never
# touched — that much the header has always claimed and it is true. What the
# first cut missed is the SESSIONS: every case is a real `claude -p`, and every
# one of those lands a transcript in $CFG/projects/<slug>/. A ten-case sweep
# therefore deposits ten sessions in the live store, which is the surface
# store-check.sh bounds and B8 pins. D2 keys on the write, not on the intent,
# and it was right to flag this.
# Paths are compared RESOLVED, never as strings: a trailing slash is a measured
# bypass of the string form (inject-install.sh records it).
_phys() { CDPATH='' cd -P -- "$1" 2>/dev/null && pwd -P || printf '%s' "$1"; }
LIVE_DIR="$HOME/.claude"
_is_live() { [ "$(_phys "$CFG")" = "$(_phys "$LIVE_DIR")" ]; }

if [ "$MODE" = run ] && _is_live && [ "$LIVE_OK" -eq 0 ]; then
  # Each case is a real session and lands a transcript in $CFG/projects.
  die "refusing the live config dir without an explicit --live" "sh $0 --cases $CASES --skills $SKILLS --apply --live" 1
fi

# ── the roster ──────────────────────────────────────────────────────────────
ROSTER=0
for d in "$SKILLS"/*/; do [ -f "$d/SKILL.md" ] && ROSTER=$(( ROSTER + 1 )); done
[ "$ROSTER" -gt 0 ] || die "$SKILLS holds no SKILL.md" "ls $SKILLS" 1

# ── the cases ───────────────────────────────────────────────────────────────
# Read with `read -r` on a tab IFS rather than cut, so a prompt may contain
# anything but a tab, including the quotes and apostrophes a real task carries.
N_CASE=0
while IFS='	' read -r id want prompt; do
  case "$id" in ''|'#'*) continue ;; esac
  [ -n "${prompt:-}" ] || die "case '$id' has no prompt" "sed -n '/^$id/p' $CASES" 1
  N_CASE=$(( N_CASE + 1 ))
done < "$CASES"
[ "$N_CASE" -gt 0 ] || die "no usable cases in $CASES" "sh $0 --help" 1

# A sweep with no negative control cannot tell a working roster from one that
# fires on everything, so refuse rather than report a number that means nothing.
if ! awk -F'	' '$1 !~ /^#/ && $2 == "NONE" { found=1 } END { exit !found }' "$CASES"; then
  die "no NONE case in $CASES — a sweep with no negative control cannot discriminate" "printf 'control\\tNONE\\tstay quiet please\\n' >> $CASES" 1
fi

if [ "$MODE" = plan ]; then
  log_head "DRY RUN"
  log_note "roster      $ROSTER skill(s) from $SKILLS"
  log_note "cases       $N_CASE (each is one real \`claude -p\` session)"
  log_note "writes      a scratch project dir, and $N_CASE session transcript(s) in ${CFG#"$HOME"/}/projects"
  # THE COST GOES IN THE PLAN, NOT IN A HEADER NOBODY OPENS. Derived from the
  # 2026-08-28 sweep — 17 proportionate cases, 98 minutes, ~$100 — so it scales
  # with the case count the operator actually passed rather than reassuring them
  # with a small-case figure. Stated as an ORDER, not a precision: the real
  # driver is how proportionate the cases are, which no script can read.
  log_note "cost        ~$(( N_CASE * 6 )) min and order-of \$$(( N_CASE * 6 )) at the 2026-08-28 rate"
  log_note "(measured: 5.8 min and ~\$6 a PROPORTIONATE case; a small case is ~20s and ~\$0.33, and sizing off that under-priced the last sweep by two orders of magnitude)"
  log_note "to run it: sh $0 --cases $CASES --skills $SKILLS --apply"
  log_end; exit $?
fi

# ── the sandbox project ─────────────────────────────────────────────────────
PROJ="${TMPDIR:-/tmp}/skill-fire.$$"
mkdir -p "$PROJ/.claude/skills"
if [ "$KEEP" -eq 0 ]; then trap 'rm -rf "$PROJ"' EXIT INT TERM; fi
for d in "$SKILLS"/*/; do
  [ -f "$d/SKILL.md" ] || continue
  n="$(basename "$d")"
  mkdir -p "$PROJ/.claude/skills/$n"
  # STRIP THE HIDE FLAG IN THE COPY, NEVER AT THE SOURCE. A hidden skill is
  # absent from the model's listing, so leaving the flag on would measure
  # "can the model invoke what it cannot see", whose answer is known and is no.
  sed '/^disable-model-invocation: *true$/d' "$d/SKILL.md" > "$PROJ/.claude/skills/$n/SKILL.md"
done

RES="$PROJ/results.tsv"
: > "$RES"

while IFS='	' read -r id want prompt; do
  case "$id" in ''|'#'*) continue ;; esac
  # `</dev/null` IS THE WHOLE MEASUREMENT, AND ITS ABSENCE VOIDED A $100 SWEEP.
  # This loop is fed by `done < "$CASES"`, so without an explicit redirect the
  # case file IS this command's stdin — and `claude -p` appends what it finds
  # there to the prompt. Measured 2026-08-28: every one of the 17 sessions
  # received the entire fixture, header and all, which includes the `want`
  # column. The model was handed the answer key and the five named cases all
  # scored `ok`. Reproduced out of band: `claude -p "print any codeword" <f`
  # prints the file's codeword, `<`/dev/null` prints NONE.
  #
  # THE LEAK IS SILENT AND IT READS AS SUCCESS. Nothing errored, the exit code
  # was 0, and a contaminated sweep scores BETTER than a clean one — which is
  # why this is a comment and not a one-word fix. tests/obs/skill-fire-test.sh stubs
  # `claude` and asserts stdin arrives empty, because that is the only evidence
  # that this line still does its job.
  out="$( cd "$PROJ" && claude -p "$prompt" --output-format json </dev/null 2>/dev/null )" || out=''
  sid="$(printf '%s' "$out" | jq -r '.session_id // empty' 2>/dev/null || true)"
  fired='-'; _inv='-'; _read='-'
  if [ -n "$sid" ]; then
    # The transcript path is derived from the cwd, and the harness's own slug
    # rules are not ours to restate — find it by name instead of building it.
    t="$(find "$CFG/projects" -name "$sid.jsonl" -type f 2>/dev/null | head -1)"
    if [ -n "$t" ]; then
      # TWO WAYS TO REACH A SKILL, AND COUNTING ONE OF THEM INVERTED A RESULT.
      # Measured 2026-08-28 on the clean sweep: `red-team-big` scored MISS while
      # its session's fourth tool call was
      # `cat ~/.claude/skills/red-team/SKILL.md`, and `council-decision` scored
      # silent having read council's. Both HAD routed to the right skill — by
      # path, not by the Skill tool — and the report called them failures.
      #
      # THE CAUSE IS THIS BOX'S OWN GOVERNANCE, which is why it is not an
      # oddity to wave away. The injected project pointer tells every session
      # "read its .claude/skills/ … do not conclude the capability is absent
      # because you cannot see it", and the hidden tier trains the same habit:
      # a hidden skill cannot be invoked, so reading its file is the ONLY route.
      # A roster measured only by Skill-tool calls therefore scores the box's
      # own doctrine as a failure to route.
      _inv="$(jq -r '..|objects|select(.type? == "tool_use" and .name? == "Skill")|.input.skill' "$t" 2>/dev/null | sort -u | paste -sd, - )"
      _read="$(jq -r '..|objects|select(.type? == "tool_use")|.input|tostring' "$t" 2>/dev/null \
               | grep -oE 'skills/[a-z0-9-]+/SKILL\.md' \
               | sed -E 's|skills/([a-z0-9-]+)/SKILL\.md|\1|' | sort -u | paste -sd, - )"
      # The verdict counts EITHER as reaching the skill — a control that reads a
      # SKILL.md has not stayed quiet — while the report keeps them in separate
      # columns, because "invoked" and "consulted" are different claims and
      # collapsing them is how the first version got the answer wrong.
      fired="$(printf '%s\n%s\n' "$_inv" "$_read" | tr ',' '\n' | sed '/^$/d' | sort -u | paste -sd, - )"
      [ -n "$fired" ] || fired='-'
      [ -n "$_inv" ]  || _inv='-'
      [ -n "$_read" ] || _read='-'
    fi
  fi
  # THREE EXPECTATION KINDS, AND `?` IS NOT A MISSING VALUE. A case can ask
  # "does X fire" (a name), "does anything fire" (NONE, the control), or
  # "WHAT fires" (`?`). The third has no right answer to score against: writing
  # a guess into the column and then scoring the run against it measures the
  # guess, not the roster, which is the same defect as inventing a case to
  # flatter a skill. `?` rows are reported and read by a human, and they do not
  # move ok/MISS/FALSE-FIRE either way.
  if [ "$want" = '?' ]; then
    v=open
  elif [ "$want" = NONE ]; then
    [ "$fired" = '-' ] && v=ok || v=FALSE-FIRE
  else
    case ",$fired," in *",$want,"*) v=ok ;; *) v=MISS ;; esac
  fi
  printf '%s\t%s\t%s\t%s\n' "$id" "$want" "$fired" "$v" >> "$RES"
  # BOTH ROUTES IN THE REPORT. `invoked` is the Skill tool; `read` is a session
  # that opened the SKILL.md instead. A single `fired` column hid the second and
  # turned two correct routings into a MISS and a silent case.
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
  # --json has always exited 0 whatever the scores; the exit code stays, and the summary still counts them.
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
