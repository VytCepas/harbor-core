#!/usr/bin/env sh
# EQUIV (harbor#264) — replay a corpus of hook payloads through TWO guard trees
# and prove every verdict is identical. The gate that has to exist before anyone
# optimises a guard.
#
#   sh admission-equivalence.sh --baseline <bin-dir> --candidate <bin-dir> [options]
#
#   --corpus <file>      payloads to replay, one JSON object per line
#   --from-transcripts   ALSO derive payloads from this box's session transcripts
#   --coverage           which rules the corpus can even reach (baseline only)
#   --limit <n>          cap the corpus at n payloads (default: no cap)
#   --guard <name>       which guard to fire (default: admission-bash.sh)
#   --config <dir>       CLAUDE_CONFIG_DIR the guards resolve against.
#                        DEFAULT: a disposable sandbox under build/, because the
#                        live dir makes every replayed payload write a row to the
#                        real guard-decision ledger (see below).
#   --verbose            print every differing case, not just the first 20
#
# WHY THIS EXISTS. harbor#264 wants the guards to stop forking ~74 greps per
# fire, and the honest objection to every proposed fix is the same: "floor-test
# still passes" is not evidence when floor-test is the thing being optimised. Its
# 1,022 assertions are the cases somebody thought of. An optimisation that skips
# a rule breaks the cases nobody thought of, and by construction those are absent
# from the suite.
#
# So the corpus is not written, it is HARVESTED: this box holds thousands of real
# Bash commands in its session transcripts. Those are commands that actually
# occurred, including every shape the suite's author never imagined. A change that
# is verdict-identical across that corpus AND green on floor-test has been tested
# against reality as well as against intent.
#
# KNOWN LIMIT: IT PROVES AN OPTIMISATION, NOT A FIX. Every payload in the corpus
# was selected because the BASELINE blocks it, so this tool can see a candidate
# that LOSES a block and is blind to one that ADDS one. Demonstrated, not
# theorised: run against the one-flag fix for harbor#282 — which provably turns
# `cat f | CRONTAB` from ALLOW into BLOCK — it reported `603 identical, 0
# DIFFERENT`, because no corpus payload is in the set whose verdict the fix
# changes.
#
# That is the correct answer to the question this tool asks ("does the candidate
# preserve every verdict I can observe?") and the wrong instrument for the question
# a bypass fix asks ("does the candidate change the two verdicts I intend?"). The
# second needs matched pairs — same command, one variable altered — and a green run
# here must never be quoted as evidence for it.
#
# KNOWN LIMIT: THE VERDICT IS SHAPE-BLIND, and it is blind because the guard is.
# Rule ids follow `<rule>.<shape>` (lint F5), and a single rule name can carry more
# than one shape — `crontab-install` exists twice in admission-bash.sh, as
# `crontab-install.flat` at line 208 and `crontab-install.argv` at line 248 — but
# the block MESSAGE prints only `bash:crontab-install`. So a refactor that moved a
# decision from one shape to the other would be reported equivalent here.
#
# That is the right granularity, not a gap to paper over: the operator sees one
# message either way, so the product has not changed. It is recorded because it
# cost an hour — floor-equiv-test's mutation neutralised the `.flat` arm, the
# `.argv` arm still fired, the verdict was unchanged, and the suite read as "the
# harness cannot fail" when in fact the harness was right and the mutation was
# incomplete. Any future mutation testing against this file must neutralise EVERY
# shape of a rule, which is what that suite now does.
#
# THE VERDICT IS THE EXIT CODE *AND* THE RULE ID. Two guards that both block are
# not equivalent if they block for different reasons: the rule id is what the
# operator reads, what the ledger records, and what floor-verify asserts. A
# refactor that silently moves a decision from `bash:pipe-to-shell` to
# `bash:fetch-then-exec` has changed the product even though both exit 2.
#
# NOTHING IS EXECUTED, EVER. Every payload is fed to a guard on stdin exactly as
# the harness feeds it — the guard's whole job is to read JSON and decide. The
# corpus is full of destructive commands precisely because those are the ones
# worth pinning, and not one of them is run.
#
# PRIVACY (CONSTITUTION §3). A harvested corpus contains real commands and real
# absolute paths from this operator's sessions. It is written under build/, which
# is gitignored, and it is never committed, printed in full, or sent anywhere.
# fixtures/admission-corpus.jsonl is the small, hand-shaped, committable corpus so CI
# has something deterministic; harvesting is a local superset.
set -eu

# --help BEFORE ANY WORK (S4, harbor#140).
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             exit 0 ;;
esac

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
# The report is the run's log (contracts/logging.md, harbor#771); the verdict is the exit code, so stdout carries
# no data.
. "$ROOT/bin/library-log.sh"
log_init floor-equiv
# die <what failed> <fix> — a refusal or a usage error: FAIL, its fix, the summary, exit 2.
die() { log_fail "$1"; log_fix "$2"; log_end || :; exit 2; }
LIVE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
BASE=""; CAND=""; CORPUS=""; LIMIT=0; GUARD="admission-bash.sh"
# IT DEFAULTS TO A SANDBOX, AND THE LIVE DIR IS THE DANGEROUS CHOICE (PR #281
# review, P1). Every guard fire calls floor_log_decision, which appends to
# $CLAUDE_CONFIG_DIR/MEMORY/OBSERVABILITY/<host>/guard-decisions.jsonl. A
# two-tree run over 597 payloads therefore writes ~1,200 synthetic rows into the
# ledger that feeds the statusline's block count, admission-observe-report.sh and
# audit-triage.sh's recurrence counts — turning an observability record of real
# tool calls into a record of a test harness. MEASURED, not predicted: building
# this tool put 9,837 rows into the live ledger in three hours.
#
# The sandbox suppresses it by the sink's own design rather than by a new switch:
# floor_log_decision requires the sink FILE to already exist, so a fresh config
# dir is simply blind. No guard changed, no flag added to the floor.
#
# AND IT COSTS NOTHING, which is why this is the default rather than an option:
# coverage measured 57 of 61 against the live dir and 57 of 61 against the
# sandbox. The surface rules resolve against whatever config dir is given, and
# since BOTH trees get the same one, equivalence is unaffected.
#
# THE CONFIG DIR IS AN INPUT, NOT AN ASSUMPTION (found by floor-equiv-test).
# It decides which paths count as floor surfaces, so a guard fired against a
# different config dir can return a different rule — and the suite discovered
# its mutation target under one dir while this harness compared under another,
# so sections 3 and 6 mutated a rule the comparison never exercised and reported
# "identical" over it. A test must also not read the live dir (lint F4).
CFGDIR=""
FROM_TR=0; VERBOSE=0; COVERAGE_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --baseline)         BASE="${2:?--baseline needs a bin dir}"; shift 2 ;;
    --candidate)        CAND="${2:?--candidate needs a bin dir}"; shift 2 ;;
    --corpus)           CORPUS="${2:?--corpus needs a file}"; shift 2 ;;
    --limit)            LIMIT="${2:?--limit needs a number}"; shift 2 ;;
    --guard)            GUARD="${2:?--guard needs a name}"; shift 2 ;;
    --config)           CFGDIR="${2:?--config needs a dir}"; shift 2 ;;
    --from-transcripts) FROM_TR=1; shift ;;
    # COVERAGE WITHOUT A CANDIDATE. Half the fires, and it answers the question
    # you have BEFORE a refactor exists: which rules can this corpus even see?
    # Asking that first is what stops a 4-minute equivalence run from returning a
    # confident "identical" over a corpus that touches a third of the rules.
    --coverage)         COVERAGE_ONLY=1; shift ;;
    --verbose)          VERBOSE=1; shift ;;
    *) die "unknown argument: $1: nothing was compared" "sh $0 --help" ;;
  esac
done
if [ "$COVERAGE_ONLY" -eq 1 ]; then
  [ -n "$BASE" ] || die "--coverage needs --baseline" "sh $0 --help"
  CAND="$BASE"
else
  [ -n "$BASE" ] && [ -n "$CAND" ] || die "--baseline and --candidate are both required" "sh $0 --help"
fi
for d in "$BASE" "$CAND"; do
  [ -f "$d/$GUARD" ] || die "no $GUARD in $d" "sh $0 --help # --baseline and --candidate name bin dirs"
done
# The sandbox is seeded with settings.json so teeth/deny reads resolve, and with
# nothing else — in particular no MEMORY/OBSERVABILITY tree.
if [ -z "$CFGDIR" ]; then
  CFGDIR="$ROOT/build/equiv-cfg.$$"
  mkdir -p "$CFGDIR/bin"
  [ -f "$LIVE/settings.json" ] && cp "$LIVE/settings.json" "$CFGDIR/settings.json" 2>/dev/null
  SANDBOX_CFG=1
else
  SANDBOX_CFG=0
  # SAID OUT LOUD, because it is a real side effect on an audit record and the
  # operator may be doing it deliberately for a realistic surface comparison.
  # both sides resolved: a dir that does not exist is "" on both, and "" = "" warned falsely
  _fe_cfg="$(CDPATH= cd -P -- "$CFGDIR" 2>/dev/null && pwd -P)"; _fe_live="$(CDPATH= cd -P -- "$LIVE" 2>/dev/null && pwd -P)"
  if [ -n "$_fe_cfg" ] && [ "$_fe_cfg" = "$_fe_live" ]; then
    # Coverage is identical with the sandbox default (measured 57 of 61 both ways).
    log_warn "--config is the LIVE dir, so every replay will append a row to the real guard-decision ledger"
    log_fix "sh $0 --baseline $BASE --candidate $CAND # omit --config unless surface rules must resolve against the live path"
  fi
fi
command -v jq >/dev/null 2>&1 || die "jq is required" "$(pkg_hint jq)"

WORK="$ROOT/build/floor-equiv.$$"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"; [ "${SANDBOX_CFG:-0}" = 1 ] && rm -rf "$CFGDIR"' EXIT INT TERM HUP
POOL="$WORK/corpus.jsonl"
: > "$POOL"

# ── the corpus ──────────────────────────────────────────────────────────────
if [ -n "$CORPUS" ]; then
  [ -f "$CORPUS" ] || die "no corpus at $CORPUS" "ls fixtures/admission-corpus.jsonl"
  # `@HOME@` IS RENDERED TO THIS RUNNER'S HOME (harbor#602). The committed corpus
  # names the config dir by absolute path, a spelling the `$HOME` and `~` rows do
  # not cover, and it used to name ONE operator's home: on any other machine
  # those rows named a stranger's path, fired nothing, and shrank the coverage
  # figure without an error. Text substitution, not a jq round-trip — a
  # re-serialised row can change its escapes, and the guards have a parse path
  # that does not use jq. ENVIRON, not `awk -v`, which would eat backslashes.
  case "$HOME" in *'"'*|*'\'*)
    die "cannot render @HOME@ — \$HOME contains a quote or a backslash" "HOME=<a plain path> sh $0 --help" ;;
  esac
  # `{j}` IS DELETED (harbor#1149): it splits a token-shaped literal so no secret scanner
  # matches the committed corpus; the guard still receives the joined string.
  awk 'BEGIN { h = ENVIRON["HOME"] }
       { s = $0; o = ""
         while ((i = index(s, "@HOME@")) > 0) { o = o substr(s, 1, i - 1) h; s = substr(s, i + 6) }
         s = o s; o = ""
         while ((i = index(s, "{j}")) > 0) { o = o substr(s, 1, i - 1); s = substr(s, i + 3) }
         print o s }' "$CORPUS" >> "$POOL"
fi
if [ "$FROM_TR" -eq 1 ]; then
  # Every Bash command this box has issued, as a hook payload. `-c` keeps one
  # object per line; a command containing a newline stays one record because jq
  # emits it escaped.
  for f in "$LIVE"/projects/*/*.jsonl; do
    [ -f "$f" ] || continue
    jq -c 'select(.type=="assistant") | .message.content[]?
           | select(.type=="tool_use" and .name=="Bash")
           | {tool_name:"Bash", tool_input:{command:.input.command}}' "$f" 2>/dev/null || true
  done >> "$POOL"
fi
# THERE IS NO --from-ledger, AND THAT IS A MEASUREMENT, NOT AN OMISSION. The
# obvious second source is ~/.claude/MEMORY/OBSERVABILITY/*/guard-decisions.jsonl
# — 6,046 rows of decisions the installed guards really made. It cannot be a
# replay corpus: the schema is `v,ts,g,d,r,s,t,h` and the command survives only as
# `h`, a HASH. That is the right design for a ledger that records every session's
# refusals (CONSTITUTION §3), and it means the ledger can tell you WHICH RULES
# have ever fired but never WHAT to re-fire. A flag that silently yields zero rows
# is worse than no flag, so there isn't one.

# DEDUPE, because a corpus of 20,000 rows that is 300 distinct commands costs 60x
# the wall clock for the same coverage — and at ~300ms a fire, that is the
# difference between a usable gate and one nobody runs.
sort -u "$POOL" > "$WORK/uniq.jsonl"
if [ "$LIMIT" -gt 0 ]; then
  head -n "$LIMIT" "$WORK/uniq.jsonl" > "$WORK/corpus.final"
else
  cp "$WORK/uniq.jsonl" "$WORK/corpus.final"
fi
N="$(wc -l < "$WORK/corpus.final" | tr -d ' ')"
[ "$N" -gt 0 ] || die "the corpus is EMPTY — nothing was compared, which is not a pass" "sh $0 --baseline $BASE --candidate $CAND --corpus fixtures/admission-corpus.jsonl"

# ── one verdict ─────────────────────────────────────────────────────────────
# Exit code plus the rule id parsed out of whatever the guard said. A guard that
# blocks prints `HELM FLOOR [<rule>]`; one that decides prints JSON carrying a
# permissionDecision. Both are part of the verdict, so both are captured.
#
# ONE FIRE PER VERDICT, and the first cut of this function did two — once inside
# `$(... || true)` to capture the output, which swallows the status, then again to
# read the exit code. That doubled the cost of the whole harness, and a gate that
# takes twice as long is a gate that gets run half as often. The payload goes to a
# file so stdin, stdout and the status all come from a single invocation.
verdict() { # <bin-dir> <payload-json> → "<rc>|<rule-or-decision>"
  printf '%s' "$2" > "$WORK/payload.json"
  _rc=0
  CLAUDE_CONFIG_DIR="$CFGDIR" sh "$1/$GUARD" < "$WORK/payload.json" > "$WORK/out.txt" 2>&1 || _rc=$?
  _id="$(sed -n 's/.*HELM FLOOR \[\([^]]*\)\].*/\1/p' "$WORK/out.txt" | head -1)"
  if [ -z "$_id" ]; then
    _id="$(jq -r '.hookSpecificOutput.permissionDecision // empty' < "$WORK/out.txt" 2>/dev/null | head -1)"
  fi
  printf '%s|%s' "$_rc" "$_id"
}

log_head "$N payload(s), guard $GUARD"
log_note "baseline:  $BASE"
log_note "candidate: $CAND"
log_note "config:    $CFGDIR"

SAME=0; DIFF=0; SHOWN=0
: > "$WORK/seen-rules.txt"
while IFS= read -r payload; do
  [ -n "$payload" ] || continue
  _b="$(verdict "$BASE" "$payload")"
  if [ "$COVERAGE_ONLY" -eq 1 ]; then _c="$_b"; else _c="$(verdict "$CAND" "$payload")"; fi
  # Which rule the BASELINE fired — the corpus's coverage is a property of the
  # tree being compared against, not of the candidate, which may have lost rules.
  case "$_b" in
    *'|'?*) printf '%s\n' "${_b#*|}" >> "$WORK/seen-rules.txt" ;;
  esac
  if [ "$_b" = "$_c" ]; then
    SAME=$((SAME + 1))
  else
    DIFF=$((DIFF + 1))
    if [ "$VERBOSE" -eq 1 ] || [ "$SHOWN" -lt 20 ]; then
      SHOWN=$((SHOWN + 1))
      # The command, truncated: a corpus row can be a multi-kilobyte heredoc, and
      # this output is read in a terminal.
      log_note "DIFFER  baseline=$_b  candidate=$_c  $(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null | head -1 | cut -c1-140)"
    fi
  fi
done < "$WORK/corpus.final"

# ── COVERAGE, BECAUSE "0 DIFFERENT" ALONE IS UNFALSIFIABLE ──────────────────
# Measured while building this: deleting the `pipe-to-shell` block from a
# candidate guard and replaying 60 harvested payloads reported 60 identical, 0
# DIFFERENT, exit 0. The harness was working perfectly and proving nothing — the
# corpus simply held no pipe-to-shell case. A gate that answers "equivalent"
# after exercising three of sixty-nine rules is the shape CONSTITUTION §2.10
# forbids, and it is worse than no gate because it carries an approval.
#
# So the verdict is two numbers, never one: how many payloads agreed, and how
# many RULES the corpus was able to disagree about. The rule universe is derived
# from the guard's own source, so adding a rule lowers the reported coverage
# instead of silently sitting outside it.
# THE UNIVERSE IS PER-GUARD AND MAY NOT BE DERIVABLE AT ALL (PR #281 review, P2).
# The first cut matched only single-line `floor_block <g> "<msg>" <id>.<shape>`,
# which is guard-bash's spelling and not everyone's. Measured across the payload:
#
#   admission-bash.sh      61 ids, all single-line   -> derivable
#   admission-egress.sh    15 floor_block, 13 match  -> derivable but INCOMPLETE
#   admission-self-edit.sh   1 floor_block,  0 match  -> not derivable
#   admission-destroy.sh    0 floor_block            -> decides via permissionDecision
#   admission-cloud.sh      0 floor_block            -> same
#
# So `--guard admission-destroy.sh` reported `rules exercised: 1 of 0` and exited 0 —
# a ratio that reads as coverage while hiding every untested rule. Two changes:
# the ids are scraped by SHAPE SUFFIX anywhere in the file, which catches
# multi-line calls; and a universe that cannot be derived, or that is smaller than
# what was observed, is a REFUSAL rather than a number.
# AND floor_log_decision LINES ARE EXCLUDED, or the denominator is wrong. The
# widened scrape picked up `bash-clean.meta` — admission-bash.sh:1747, the ALLOW
# observation written when no rule fired at all. It is shaped exactly like a rule
# id and is not one, so coverage read `57 of 62` when the truth was 57 of 61. Wrong
# in the safe direction, and still wrong: a denominator nobody can reproduce from
# the source is the kind of number this repo generates rather than states.
_universe="$WORK/universe.txt"
_shapes='flat|argv|meta|content|path|channel'
grep -vE "floor_log_decision" "$BASE/$GUARD" 2>/dev/null \
  | grep -oE "[a-z0-9-]+\.($_shapes)([^a-z]|$)" \
  | sed -E "s/\.($_shapes)([^a-z]|$).*//" | sed 's/^/bash:/' | sort -u > "$_universe" || : > "$_universe"
M="$(wc -l < "$_universe" | tr -d ' ')"
sort -u "$WORK/seen-rules.txt" 2>/dev/null | sed '/^$/d' > "$WORK/seen.txt" || : > "$WORK/seen.txt"
# `wc -l`, NOT `grep -c . || echo 0`. The first cut used the latter and it is the
# fallback trap this repo has hit before: on an empty file `grep -c .` PRINTS 0 and
# EXITS 1, so the `|| echo 0` fired as well and SEEN became the two-line string
# "0\n0". Every downstream `[ "$SEEN" -eq 0 ]` then failed with "integer expression
# expected" — and because those tests sit in the refusal branch, the harness sailed
# past its own coverage gate and reported a clean pass. wc -l always exits 0.
SEEN="$(wc -l < "$WORK/seen.txt" | tr -d ' ')"
log_note "$SAME identical, $DIFF DIFFERENT"
log_note "rules exercised: $SEEN of $M"
if [ "$M" -eq 0 ]; then
  # It may decide via permissionDecision rather than floor_block (admission-cloud.sh, admission-destroy.sh), in which
  # case this harness cannot yet say what a corpus leaves untested for it.
  die "REFUSING TO REPORT COVERAGE — no rule ids could be derived from $GUARD; a ratio against zero reads as coverage and is not" "sh $0 --baseline $BASE --candidate $CAND --guard admission-bash.sh"
fi
if [ "$SEEN" -eq 0 ]; then
  die "REFUSING TO CALL THIS EQUIVALENT — the corpus triggered NO rule at all, so it could not have detected a deleted one" "sh $0 --baseline $BASE --candidate $CAND --corpus fixtures/admission-corpus.jsonl"
fi
if [ "$SEEN" -gt "$M" ]; then
  die "REFUSING — $SEEN rule(s) fired but only $M could be derived from the source, so the universe is provably incomplete and the coverage figure would understate what is untested" "sh $0 --coverage --baseline $BASE --guard $GUARD --verbose"
fi
if [ "$M" -gt 0 ] && [ "$SEEN" -lt "$M" ]; then
  log_note "NOT exercised ($((M - SEEN))):"
  comm -23 "$_universe" "$WORK/seen.txt" | head -"$( [ "$VERBOSE" -eq 1 ] && echo 200 || echo 8 )" | while IFS= read -r _nr; do log_note "  $_nr"; done
  [ "$VERBOSE" -eq 0 ] && [ "$((M - SEEN))" -gt 8 ] && \
    log_note "… $(( M - SEEN - 8 )) more (--verbose for all)"
  log_note "A rule the corpus never triggers is a rule this run says nothing about."
fi
if [ "$DIFF" -gt 0 ]; then
  [ "$VERBOSE" -eq 0 ] && [ "$DIFF" -gt 20 ] && \
    log_note "($((DIFF - 20)) more not shown — re-run with --verbose)"
  log_fail "the candidate is NOT equivalent to the baseline: $DIFF DIFFERENT"
  log_fix "sh $0 --baseline $BASE --candidate $CAND --guard $GUARD --verbose"
  log_end || :; exit 1
fi
log_ok "every verdict identical, exit code and rule id alike"
log_end; exit $?
