#!/usr/bin/env sh
# M2 · DoctrineReplay (harbor#44) — measure a rule change against real traffic.
#
#   sh bin/eval-replay.sh --baseline    # record today's verdicts as the reference
#   sh bin/eval-replay.sh               # re-run and report the DELTA vs the baseline
#   sh bin/eval-replay.sh --report      # per-rule counts for the current run only
#
# THE DELIVERABLE IS THE DELTA, NOT THE RATE. An absolute "the floor blocks 7.6%
# of real traffic" is interesting once; what decides whether a rule change is an
# improvement is which records CHANGED verdict. Twelve passes argued that
# question. This measures it.
#
# THE SELF-CHECK IS NOT OPTIONAL. Three separate ad-hoc replay harnesses were
# written while designing this, and all three silently produced wrong numbers:
# `xargs` interprets " and ' unless given -0 (zero records), BSD `xargs -I` reads
# lines rather than NUL records and conflicts with -P (one record), and a third
# mis-scoped its exit-code test (70% where the truth was 4%). EVERY ONE rendered
# as a plausible result — "0 blocked" reads exactly like a clean floor. So this
# script asserts its own record count and REFUSES to report on a short run.
#
# WHAT A BLOCK MEANS. These are commands the operator actually ran and, by
# default, wanted to run — so every block on real traffic is a FALSE-POSITIVE
# CANDIDATE until adjudicated, which is CONSTITUTION rule 2 ("a false positive is
# a defect, not safety") made measurable.
#
# LABELS HAVE TWO SCOPES, AND THE RULE SCOPE IS THE ONE THAT PAYS. A first cut
# keyed adjudications only on the record id, which meant `key-material-read`
# firing six times cost six identical judgements — and a corpus that grows makes
# that worse, not better. So:
#
#   rule    <guard:rule>   verdict [note]   — settles EVERY occurrence at once
#   record  <payload-hash> verdict [note]   — settles one command; overrides the rule
#
# verdict is `false-positive` (the rule is wrong here) or `correct-block` (the
# rule is right and the command was genuinely dangerous). A record label wins
# over a rule label, because "this rule is generally wrong BUT this one instance
# was a real catch" is exactly the case a single scope cannot express.
#
# The record key is a hash of the PAYLOAD, so it survives rule renames and corpus
# rebuilds. Editing a command by one byte makes a new record and a new
# adjudication, which is correct: it is a different command.
#
# THE UNREVIEWED COUNT IS ALWAYS REPORTED. A false-positive rate computed over
# only the labelled subset is a number that flatters itself.
set -eu

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
while [ "${CFG%/}" != "$CFG" ] && [ "$CFG" != "/" ]; do CFG="${CFG%/}"; done
DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# The report is the run's log (contracts/logging.md, harbor#771); there is no data on stdout.
. "$DIR/library-log.sh"
log_init replay
# die <what failed> <fix> [exit] — FAIL, its fix, the summary, then the exit code the tool always had.
die() { log_fail "$1"; log_fix "$2"; log_end || :; exit "${3:-1}"; }
# notes: each stdin line as a note, for the tables awk builds.
notes() { while IFS= read -r _nl; do log_note "$_nl"; done; }
RP="$CFG/.helm-replay"
BASELINE="$RP/baseline.tsv"
LABELS="$RP/labels.tsv"
MODE=diff
LIMIT=0
JOBS=6
EXCL_LIST=""

while [ $# -gt 0 ]; do
  case "$1" in
    --baseline) MODE=baseline ;;
    --report)   MODE=report ;;
    --labels)   MODE=labels ;;
    --limit)    shift; LIMIT="${1:-0}" ;;
    # Collected into a file, not a string (pass-2 review): the string was expanded
    # unquoted on the way to the builder, so a pattern was pathname-expanded
    # against the caller's cwd and the exclusion silently vanished, and a pattern
    # containing a space became an "unknown option" error.
    --exclude)  shift; EXCL_LIST="$EXCL_LIST${1:-}
" ;;
    --jobs)     shift; JOBS="${1:-6}" ;;
    -h|--help)
      echo "usage: eval-replay.sh [--baseline|--report|--labels] [--limit N] [--jobs N] [--exclude <glob>]..."
      echo "  --exclude drops a project dir from the corpus. The per-project census is"
      echo "  printed on every run, so a corpus dominated by one project is visible."
      echo "  The corpus is rebuilt from the transcripts on every run and deleted"
      echo "  on exit. Only $BASELINE persists, and it holds hashes, not commands."
      exit 0 ;;
    *) die "unknown option $1: nothing was replayed" "sh $0 --help" ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || die "jq is required" "$(pkg_hint jq)"

TMP="${TMPDIR:-/tmp}/helm-replay.$$"
mkdir -p "$TMP"
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT INT TERM
umask 077

# A THROWAWAY config dir, never the operator's. The guards resolve their own
# config dir from CLAUDE_CONFIG_DIR, and three floor-test invocations were
# silently pointing guards at the live ~/.claude until lint F4 caught them.
RCFG="$TMP/cfg"; mkdir -p "$RCFG/bin"
for g in library-admission.sh admission-bash.sh admission-egress.sh admission-self-edit.sh floor-normalize.awk; do
  cp "$DIR/$g" "$RCFG/bin/$g"
done
printf '{"permissions":{"allow":[],"deny":[]}}\n' > "$RCFG/settings.json"

# ── the corpus is built HERE, into $TMP, and dies with the trap ─────────────
# Owner decision 2026-07-28: no durable corpus, ever. Materialising it would
# turn 481 mixed transcript files into one greppable store of every command the
# operator has typed, and it would outlive the 30-day GC that deletes the
# transcripts. Rebuilding costs ~30-60s; that is the price of the artifact not
# existing. The baseline that DOES persist carries payload hashes and verdicts
# and no command text — the same stance L1 takes, for the same reason.
printf '%s' "$EXCL_LIST" > "$TMP/excl"
set -- --to "$TMP/in.jsonl"
[ "$LIMIT" -gt 0 ] && set -- "$@" --limit "$LIMIT"
[ -s "$TMP/excl" ] && set -- "$@" --exclude-file "$TMP/excl"
sh "$DIR/eval-replay-corpus.sh" "$@" > "$TMP/build.log" 2>&1 || {
  cat "$TMP/build.log"; die "corpus build failed" "sh $DIR/eval-replay-corpus.sh --to \"\${TMPDIR:-/tmp}/corpus.jsonl\""; }
# The builder's report, less its own summary: this run ends with the one summary.
grep -v '^replay-corpus: [0-9]* ok, ' "$TMP/build.log"
IN="$(wc -l < "$TMP/in.jsonl" | tr -d ' ')"
[ "$IN" -gt 0 ] || die "corpus is empty" "sh $DIR/eval-replay-corpus.sh --to \"\${TMPDIR:-/tmp}/corpus.jsonl\" # read its census"

# ── the worker ──────────────────────────────────────────────────────────────
# bin/eval-replay-worker.sh, NOT a heredoc into $TMP. It lived here as a heredoc until
# harbor#133, which made it unreachable from the suite — replay-test guarded its
# never-drop-a-record assertion on a `$TMP` path that never existed and passed via
# the `else` branch every run. The worker is a tracked file so the suite can
# invoke the code that actually ships.
WORKER="$DIR/eval-replay-worker.sh"
[ -f "$WORKER" ] || die "bin/eval-replay-worker.sh is missing: $WORKER" "git checkout -- bin/eval-replay-worker.sh"

# Bounded job pool. `&` + `wait` rather than xargs -P, because xargs' quoting is
# what broke every earlier attempt and a shell-quoted JSON record cannot survive
# it. Each worker appends one line; appends of this size are atomic.
: > "$TMP/out.tsv"
n=0
while IFS= read -r rec; do
  [ -n "$rec" ] || continue
  # The record goes on STDIN, never argv (#47 finding 8): a command-line
  # argument is visible to every user on the box via the process table, which
  # would expose the whole corpus the ephemeral design exists to avoid writing down.
  printf '%s\n' "$rec" | sh "$WORKER" "$RCFG" >> "$TMP/out.tsv" 2>/dev/null &
  n=$((n + 1))
  [ "$((n % JOBS))" -eq 0 ] && wait
done < "$TMP/in.jsonl"
wait

# ── THE SELF-CHECK ──────────────────────────────────────────────────────────
GOT="$(wc -l < "$TMP/out.tsv" | tr -d ' ')"
if [ "$GOT" != "$IN" ]; then
  # A short run reports 'no regressions' from records it never ran.
  die "REFUSING TO REPORT — produced $GOT verdicts for $IN records" "sh $0 --report --jobs 1" 2
fi
ERRS="$(grep -c '	ERROR	' "$TMP/out.tsv" 2>/dev/null | head -1 | tr -d ' \n')"
case "$ERRS" in ''|*[!0-9]*) ERRS=0 ;; esac

sort "$TMP/out.tsv" > "$TMP/now.tsv"
BLOCKS="$(grep -c '	BLOCK	' "$TMP/now.tsv" 2>/dev/null | head -1 | tr -d ' \n')"
case "$BLOCKS" in ''|*[!0-9]*) BLOCKS=0 ;; esac

# Classify every block against the labels. Comments and blank lines are skipped
# so the file can carry the reasoning next to the judgement — an adjudication
# without its reason is one nobody can re-check.
classify() { # -> $TMP/classified.tsv : id<TAB>rule<TAB>{fp|correct|unreviewed}
  : > "$TMP/classified.tsv"
  awk -F'\t' -v labels="$LABELS" '
    BEGIN {
      while ((getline line < labels) > 0) {
        if (line ~ /^[[:space:]]*#/ || line ~ /^[[:space:]]*$/) continue
        n = split(line, f, "\t")
        if (n < 3) continue
        if (f[1] == "rule")   rl[f[2]] = f[3]
        if (f[1] == "record") rc[f[2]] = f[3]
      }
    }
    $2 == "BLOCK" {
      v = "unreviewed"
      if ($3 in rl) v = (rl[$3] == "false-positive") ? "fp" : "correct"
      # A record label OVERRIDES its rule label, never the other way round.
      if ($1 in rc) v = (rc[$1] == "false-positive") ? "fp" : "correct"
      print $1 "\t" $3 "\t" v
    }' "$TMP/now.tsv" > "$TMP/classified.tsv"
}

cnt() { grep -c "	$1\$" "$TMP/classified.tsv" 2>/dev/null | head -1 | tr -d ' \n'; }

summary() {
  classify
  FP="$(cnt fp)";   case "$FP" in ''|*[!0-9]*) FP=0 ;; esac
  OK="$(cnt correct)"; case "$OK" in ''|*[!0-9]*) OK=0 ;; esac
  UR="$(cnt unreviewed)"; case "$UR" in ''|*[!0-9]*) UR=0 ;; esac

  log_head "$(printf '%s records · %s blocked (%s%%) · %s unparseable' \
    "$IN" "$BLOCKS" "$(awk -v b="$BLOCKS" -v t="$IN" 'BEGIN{printf "%.1f", (t>0?100*b/t:0)}')" "$ERRS")"
  # The NO-VERDICT banner goes BEFORE the early return (pass-2 review): it sat
  # after `[ "$BLOCKS" -gt 0 ] || return 0`, so a run where EVERY guard failed —
  # zero blocks, the exact case it was written for — returned silently reporting
  # "0 blocked", which reads as a clean floor.
  if [ "$ERRS" -gt 0 ]; then
    # Neither allows nor blocks: a run with many of them measures nothing.
    log_warn "$ERRS record(s) produced NO VERDICT — a guard failed to run"
    log_fix "sh bin/floor-verify.sh --live"
  fi
  [ "$BLOCKS" -gt 0 ] || return 0
  log_note "of those: $FP adjudicated FALSE POSITIVE · $OK adjudicated CORRECT · $UR UNREVIEWED"
  if [ "$UR" -gt 0 ]; then
    log_warn "the false-positive rate below counts only what has been judged; $UR block(s) have not been looked at and could move it either way"
    log_fix "sh $0 --labels"
  fi
  log_note "false-positive rate (judged only): $(awk -v f="$FP" -v t="$IN" 'BEGIN{printf "%.2f", (t>0?100*f/t:0)}')%"

  log_head "rules firing on REAL traffic"
  awk -F'\t' '{print $3 "\t" $2}' "$TMP/classified.tsv" | sort | uniq -c | sort -rn \
    | awk '{ tag = ($2=="fp") ? "FALSE POSITIVE" : ($2=="correct") ? "correct" : "unreviewed"
             printf "%5d  %-34s %s\n", $1, $3, tag }' | notes
}

case "$MODE" in
  baseline)
    [ -d "$RP" ] || mkdir -p "$RP"; chmod 0700 "$RP"
    cp "$TMP/now.tsv" "$BASELINE"; chmod 0600 "$BASELINE"
    summary
    log_ok "baseline written: $BASELINE"
    ;;
  report)
    summary
    ;;
  labels)
    # The ADJUDICATION QUEUE, ordered by how much each judgement buys. One line
    # of labels.tsv against the top rule settles more blocks than a dozen
    # record-level judgements, which is the whole reason the rule scope exists.
    summary
    log_head "adjudication queue — highest leverage first"
    log_note "Append a line to $LABELS to settle a whole rule at once:"
    awk -F'\t' '$3=="unreviewed"{print $2}' "$TMP/classified.tsv" | sort | uniq -c | sort -rn \
      | awk '{ printf "rule\t%s\tfalse-positive\t# settles %s block(s) — replace with correct-block if the rule is right\n", $2, $1 }' | notes
    log_note "(a \`record <hash> <verdict>\` line overrides the rule label for one command)"
    ;;
  diff)
    [ -f "$BASELINE" ] || die "no baseline at $BASELINE" "sh $0 --baseline"
    summary
    # A join on id: the record ids are stable across corpus rebuilds because they
    # hash the payload, so a delta survives adding new traffic.
    # Temp files, NOT `<(...)`: process substitution is a bashism and the floor's
    # language rule is pure POSIX sh. It parsed fine under an interactive zsh and
    # died under /bin/sh, which is the shell every hook actually runs.
    sort -k1,1 "$BASELINE" > "$TMP/b.sorted"
    sort -k1,1 "$TMP/now.tsv" > "$TMP/n.sorted"
    join -t"$(printf '\t')" -j1 -o 0,1.2,1.3,2.2,2.3 \
      "$TMP/b.sorted" "$TMP/n.sorted" > "$TMP/j.tsv" 2>/dev/null || true
    # COVERAGE FIRST (#47 finding 4). `join` emits only matching ids, so a
    # baseline built from a different corpus produced an EMPTY join — reported as
    # "newly BLOCKED 0" and exit 0, i.e. a perfectly clean delta from a
    # comparison that never happened. That is the exact failure this tool exists
    # to prevent, reproduced inside the tool itself.
    # DISTINCT ids, not join rows (pass-2 review): a duplicate id makes join emit
    # a cartesian product, which inflated "overlap" past 100% and could mask a
    # minority overlap as full coverage.
    JOINED="$(cut -f1 "$TMP/j.tsv" | sort -u | wc -l | tr -d ' ')"
    BASE_N="$(cut -f1 "$BASELINE" | sort -u | wc -l | tr -d ' ')"
    log_note "coverage: $JOINED of $BASE_N baseline records matched this run ($(awk -v a="$JOINED" -v b="$BASE_N" 'BEGIN{printf "%.0f",(b>0?100*a/b:0)}')% overlap)"
    if [ "$JOINED" -eq 0 ]; then
      # A clean delta from a comparison that never happened is the worst output here.
      die "REFUSING TO REPORT A DELTA — the baseline and this run share no records" "sh $0 --baseline" 2
    fi
    if [ "$(awk -v a="$JOINED" -v b="$BASE_N" 'BEGIN{print (b>0 && 100*a/b < 70) ? 1 : 0}')" = 1 ]; then
      log_warn "under 70% overlap — this delta is computed on a minority of the baseline; treat \"newly BLOCKED 0\" as unproven, not as clean"
      log_fix "sh $0 --baseline"
    fi
    NEWB="$(awk -F'\t' '$2=="ALLOW" && $4=="BLOCK"' "$TMP/j.tsv" | wc -l | tr -d ' ')"
    NEWA="$(awk -F'\t' '$2=="BLOCK" && $4=="ALLOW"' "$TMP/j.tsv" | wc -l | tr -d ' ')"
    CHG="$(awk -F'\t' '$2=="BLOCK" && $4=="BLOCK" && $3!=$5' "$TMP/j.tsv" | wc -l | tr -d ' ')"
    log_head "delta vs baseline"
    log_note "newly ALLOWED  $NEWA   (a fix — or a new hole; the labels decide which)"
    log_note "re-attributed  $CHG   (same verdict, different rule)"
    if [ "$NEWB" -gt 0 ]; then
      log_note "rules newly firing:"
      awk -F'\t' '$2=="ALLOW" && $4=="BLOCK"{print $5}' "$TMP/j.tsv" | sort | uniq -c | sort -rn \
        | awk '{printf "%5d  %s\n", $1, $2}' | notes
    fi
    if [ "$NEWA" -gt 0 ]; then
      log_note "rules that stopped firing:"
      awk -F'\t' '$2=="BLOCK" && $4=="ALLOW"{print $3}' "$TMP/j.tsv" | sort | uniq -c | sort -rn \
        | awk '{printf "%5d  %s\n", $1, $2}' | notes
    fi
    # The verdict is deliberately NOT automatic. A newly-blocked count of zero is
    # not "safe to ship" — it is "no real command in this corpus changed verdict",
    # which is a narrower claim, and encoding a fix stays human-gated
    # (CONSTITUTION: the system may propose in batch, never promote its own
    # observations into a rule).
    log_note "This is evidence, not a verdict. $IN records is what the corpus covers; a rule can still be wrong about traffic no one has run yet."
    if [ "$NEWB" -eq 0 ]; then
      log_ok "newly BLOCKED  0   (regression candidates: real commands that used to work)"
    else
      log_fail "newly BLOCKED  $NEWB   (regression candidates: real commands that used to work)"
      log_fix "sh $0 --labels"
      log_end || :; exit 3
    fi
    ;;
esac
log_end; exit $?
