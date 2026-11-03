#!/usr/bin/env sh
# M2 · DoctrineReplay (harbor#44) — measure a rule change against real traffic.
#
#   sh bin/eval-replay.sh --baseline    # record today's verdicts as the reference
#   sh bin/eval-replay.sh               # re-run and report the DELTA vs the baseline
#   sh bin/eval-replay.sh --report      # per-rule counts for the current run only
#   sh bin/eval-replay.sh --since 14 --report   # only transcripts modified in the last 14 days
#
# THE DELIVERABLE IS THE DELTA, NOT THE RATE: what decides whether a rule change is an improvement is which records CHANGED verdict.
# THE SELF-CHECK IS NOT OPTIONAL: three ad-hoc harnesses silently produced wrong numbers (xargs eats quotes without -0; BSD `xargs -I` reads lines and
# conflicts with -P; a mis-scoped exit-code test said 70% for a true 4%), each reading as a plausible result. So this asserts its own record count and
# REFUSES to report on a short run.
# A BLOCK on real traffic is a FALSE-POSITIVE CANDIDATE until adjudicated: the operator ran these commands and wanted to (CONSTITUTION rule 2).
# LABELS HAVE TWO SCOPES, and the rule scope pays (one judgement settles every occurrence):
#   rule    <guard:rule>   verdict [note]   settles EVERY occurrence at once
#   record  <payload-hash> verdict [note]   settles one command; overrides the rule
# verdict is `false-positive` or `correct-block`. The record key hashes the PAYLOAD, so it survives rule renames and rebuilds; a one-byte edit is a new record.
# THE UNREVIEWED COUNT IS ALWAYS REPORTED: a rate over only the labelled subset flatters itself.
# Removed notes: docs/explanation/code-cases/bin-eval-replay.md
set -eu

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
while [ "${CFG%/}" != "$CFG" ] && [ "$CFG" != "/" ]; do CFG="${CFG%/}"; done
DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# The report is the run's log (contracts/logging.md, harbor#771); there is no data on stdout.
. "$DIR/library-log.sh"
log_init replay
die() { log_fail "$1"; log_fix "$2"; log_end || :; exit "${3:-1}"; }
notes() { while IFS= read -r _nl; do log_note "$_nl"; done; }
RP="$CFG/.helm-replay"
BASELINE="$RP/baseline.tsv"
LABELS="$RP/labels.tsv"
MODE=diff
LIMIT=0
SINCE=0
JOBS=6
EXCL_LIST=""

while [ $# -gt 0 ]; do
  case "$1" in
    --baseline) MODE=baseline ;;
    --report)   MODE=report ;;
    --labels)   MODE=labels ;;
    --limit)    shift; LIMIT="${1:-0}" ;;
    # A time window on the transcripts read (harbor#1420): --limit cannot pick recent records.
    --since)    shift; SINCE="${1:-0}" ;;
    # Collected into a file, not a string (pass-2 review): an unquoted string was pathname-expanded against the caller's cwd and a pattern with a space broke the builder.
    --exclude)  shift; EXCL_LIST="$EXCL_LIST${1:-}
" ;;
    --jobs)     shift; JOBS="${1:-6}" ;;
    -h|--help)
      echo "usage: eval-replay.sh [--baseline|--report|--labels] [--limit N] [--since DAYS] [--jobs N] [--exclude <glob>]..."
      echo "  --exclude drops a project dir from the corpus. The per-project census is"
      echo "  printed on every run, so a corpus dominated by one project is visible."
      echo "  --since limits the corpus to transcripts modified in the last DAYS days."
      echo "  The corpus is rebuilt from the transcripts on every run and deleted"
      echo "  on exit. Only $BASELINE persists, and it holds hashes, not commands."
      exit 0 ;;
    *) die "unknown option $1: nothing was replayed" "sh $0 --help" ;;
  esac
  shift
done

case "$SINCE" in ''|*[!0-9]*) die "--since takes a whole number of days: $SINCE" "sh $0 --since 14 --report" ;; esac
command -v jq >/dev/null 2>&1 || die "jq is required" "$(pkg_hint jq)"

TMP="${TMPDIR:-/tmp}/helm-replay.$$"
mkdir -p "$TMP"
# Kill-safe (harbor#1420): a signal kills every descendant, found by walking `ps` (dash ignores `set -m` process groups), then removes both scratch dirs.
BPID=""
cleanup() {
  [ -z "$BPID" ] || rm -rf "${TMPDIR:-/tmp}/helm-replay-build.$BPID" 2>/dev/null
  chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"
}
descendants() { # <pid> -> every descendant pid, one per line
  ps -A -o pid= -o ppid= 2>/dev/null | awk -v root="$1" '{ par[$1] = $2 }
    END { for (p in par) { q = p; while (q in par) { if (par[q] == root) { print p; break }; q = par[q] } } }'
}
on_signal() {
  trap '' INT TERM HUP
  # A pass can miss a child the builder spawns between the snapshot and the kill, so repeat until none is left.
  _n=0
  while [ "$_n" -lt 10 ]; do
    _kids=""; for _k in $(descendants "$$"); do kill -0 "$_k" 2>/dev/null && _kids="$_kids $_k"; done
    [ -n "$_kids" ] || break
    # shellcheck disable=SC2086
    kill -s TERM $_kids 2>/dev/null || :
    _n=$((_n + 1)); sleep 0.1
  done
  exit 143
}
trap cleanup EXIT
trap on_signal INT TERM HUP
umask 077

# A THROWAWAY config dir, never the operator's: three floor-test invocations once pointed guards at the live ~/.claude until lint F4 caught them.
RCFG="$TMP/cfg"; mkdir -p "$RCFG/bin"
for g in library-admission.sh admission-bash.sh admission-egress.sh admission-self-edit.sh admission-normalize.awk; do
  cp "$DIR/$g" "$RCFG/bin/$g"
done
printf '{"permissions":{"allow":[],"deny":[]}}\n' > "$RCFG/settings.json"

# ── the corpus is built HERE, into $TMP, and dies with the trap ─────────────
# Owner decision 2026-07-28: no durable corpus, ever (it would outlive the 30-day transcript GC and be one greppable store of every command typed).
# Rebuilding costs ~30-60s. The baseline that does persist holds payload hashes and verdicts, no command text.
printf '%s' "$EXCL_LIST" > "$TMP/excl"
set -- --to "$TMP/in.jsonl"
[ "$LIMIT" -gt 0 ] && set -- "$@" --limit "$LIMIT"
[ -s "$TMP/excl" ] && set -- "$@" --exclude-file "$TMP/excl"
[ "$SINCE" -gt 0 ] && set -- "$@" --since "$SINCE"
# Background + wait, so the trap fires at once instead of after the builder.
sh "$DIR/eval-replay-corpus.sh" "$@" > "$TMP/build.log" 2>&1 &
BPID=$!
wait "$BPID" 2>/dev/null || {
  cat "$TMP/build.log"; die "corpus build failed" "sh $DIR/eval-replay-corpus.sh --to \"\${TMPDIR:-/tmp}/corpus.jsonl\""; }
grep -v '^replay-corpus: [0-9]* ok, ' "$TMP/build.log"
IN="$(wc -l < "$TMP/in.jsonl" | tr -d ' ')"
[ "$IN" -gt 0 ] || die "corpus is empty" "sh $DIR/eval-replay-corpus.sh --to \"\${TMPDIR:-/tmp}/corpus.jsonl\" # read its census"

# ── the worker ──────────────────────────────────────────────────────────────
# bin/eval-replay-worker.sh, NOT a heredoc: as a heredoc (until harbor#133) it was unreachable from the suite, so replay-test's never-drop-a-record
# assertion guarded a `$TMP` path that never existed and passed via the else branch every run.
WORKER="$DIR/eval-replay-worker.sh"
[ -f "$WORKER" ] || die "bin/eval-replay-worker.sh is missing: $WORKER" "git checkout -- bin/eval-replay-worker.sh"

# Bounded job pool with `&` + `wait`, not xargs -P (its quoting broke every earlier attempt). Each worker appends one line; appends this size are atomic.
: > "$TMP/out.tsv"
n=0
while IFS= read -r rec; do
  [ -n "$rec" ] || continue
  # The record goes on STDIN, never argv (#47 finding 8): argv is visible to every user via the process table.
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

# Classify every block against the labels; comments and blank lines in the file are skipped so it can carry the reasoning beside the judgement.
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
  # The NO-VERDICT banner goes BEFORE the early return (pass-2 review): after it, a run where EVERY guard failed returned silently as "0 blocked", reading as a clean floor.
  if [ "$ERRS" -gt 0 ]; then
    log_warn "$ERRS record(s) produced NO VERDICT — a guard failed to run"
    log_fix "sh bin/admission-verify.sh --live"
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
    # The ADJUDICATION QUEUE, ordered by how much each judgement buys: one rule-level label settles more blocks than a dozen record-level ones.
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
    # A join on id: record ids hash the payload, so a delta survives new traffic. Temp files, NOT `<(...)`: process substitution is a bashism and hooks run /bin/sh.
    sort -k1,1 "$BASELINE" > "$TMP/b.sorted"
    sort -k1,1 "$TMP/now.tsv" > "$TMP/n.sorted"
    join -t"$(printf '\t')" -j1 -o 0,1.2,1.3,2.2,2.3 \
      "$TMP/b.sorted" "$TMP/n.sorted" > "$TMP/j.tsv" 2>/dev/null || true
    # COVERAGE FIRST (#47 finding 4): `join` emits only matching ids, so a baseline from a different corpus gave an EMPTY join, reported as "newly BLOCKED 0"
    # and exit 0. DISTINCT ids, not join rows (pass-2 review): a duplicate id makes join a cartesian product that inflated overlap past 100%.
    JOINED="$(cut -f1 "$TMP/j.tsv" | sort -u | wc -l | tr -d ' ')"
    BASE_N="$(cut -f1 "$BASELINE" | sort -u | wc -l | tr -d ' ')"
    log_note "coverage: $JOINED of $BASE_N baseline records matched this run ($(awk -v a="$JOINED" -v b="$BASE_N" 'BEGIN{printf "%.0f",(b>0?100*a/b:0)}')% overlap)"
    if [ "$JOINED" -eq 0 ]; then
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
    # The verdict is deliberately NOT automatic: zero newly-blocked means "no real command in this corpus changed verdict", a narrower claim than "safe to ship",
    # and encoding a fix stays human-gated (CONSTITUTION).
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
