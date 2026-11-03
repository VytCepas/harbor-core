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
# WHY: harbor#264 optimises guards, and "floor-test passes" is no evidence when floor-test is what is being optimised, so the corpus is
# harvested from real transcripts, not written. Nothing is executed: payloads go to the guard on stdin.
# LIMIT: proves an optimisation, not a fix. Every corpus payload is one the BASELINE blocks, so a candidate that LOSES a block is seen
# and one that ADDS a block is not (the harbor#282 fix reported 603 identical). A bypass fix needs matched pairs.
# LIMIT: shape-blind, as the guard is: `crontab-install.flat` and `crontab-install.argv` both print `bash:crontab-install`, so a
# mutation test must neutralise EVERY shape of a rule. The verdict is exit code AND rule id.
# PRIVACY (CONSTITUTION §3): a harvested corpus holds real commands and paths; it lives under build/ (gitignored), never committed.
# Removed notes: docs/explanation/code-cases/bin-admission-equivalence.md
set -eu

# --help BEFORE ANY WORK (S4, harbor#140).
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             exit 0 ;;
esac

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
# The report is the run's log (contracts/logging.md, harbor#771); the verdict is the exit code.
. "$ROOT/bin/library-log.sh"
log_init floor-equiv
die() { log_fail "$1"; log_fix "$2"; log_end || :; exit 2; }
LIVE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
BASE=""; CAND=""; CORPUS=""; LIMIT=0; GUARD="admission-bash.sh"
# The default config is a disposable sandbox: every guard fire appends to $CLAUDE_CONFIG_DIR/MEMORY/OBSERVABILITY/<host>/guard-decisions.jsonl,
# so the live dir would fill the real ledger with synthetic rows (PR #281). The config dir is an input because it decides which paths
# count as floor surfaces; a test must not read the live dir (lint F4).
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
if [ -z "$CFGDIR" ]; then
  CFGDIR="$ROOT/build/equiv-cfg.$$"
  mkdir -p "$CFGDIR/bin"
  [ -f "$LIVE/settings.json" ] && cp "$LIVE/settings.json" "$CFGDIR/settings.json" 2>/dev/null
  SANDBOX_CFG=1
else
  SANDBOX_CFG=0
  # Said out loud, it writes to an audit record. Both sides resolved: a missing dir is "" on both, and "" = "" warned falsely.
  _fe_cfg="$(CDPATH= cd -P -- "$CFGDIR" 2>/dev/null && pwd -P)"; _fe_live="$(CDPATH= cd -P -- "$LIVE" 2>/dev/null && pwd -P)"
  if [ -n "$_fe_cfg" ] && [ "$_fe_cfg" = "$_fe_live" ]; then
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

if [ -n "$CORPUS" ]; then
  [ -f "$CORPUS" ] || die "no corpus at $CORPUS" "ls fixtures/admission-corpus.jsonl"
  # `@HOME@` renders to this runner's home (harbor#602). Text substitution, not jq (re-serialising can change escapes); ENVIRON, not `awk -v`.
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
  for f in "$LIVE"/projects/*/*.jsonl; do
    [ -f "$f" ] || continue
    jq -c 'select(.type=="assistant") | .message.content[]?
           | select(.type=="tool_use" and .name=="Bash")
           | {tool_name:"Bash", tool_input:{command:.input.command}}' "$f" 2>/dev/null || true
  done >> "$POOL"
fi
# No --from-ledger: guard-decisions.jsonl keeps the command only as a hash (CONSTITUTION §3), so it cannot be replayed.

# Dedupe: a 20,000-row corpus can be 300 distinct commands.
sort -u "$POOL" > "$WORK/uniq.jsonl"
if [ "$LIMIT" -gt 0 ]; then
  head -n "$LIMIT" "$WORK/uniq.jsonl" > "$WORK/corpus.final"
else
  cp "$WORK/uniq.jsonl" "$WORK/corpus.final"
fi
N="$(wc -l < "$WORK/corpus.final" | tr -d ' ')"
[ "$N" -gt 0 ] || die "the corpus is EMPTY — nothing was compared, which is not a pass" "sh $0 --baseline $BASE --candidate $CAND --corpus fixtures/admission-corpus.jsonl"

# One fire per verdict, payload in a file: `$(... || true)` swallows the status.
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
  case "$_b" in
    *'|'?*) printf '%s\n' "${_b#*|}" >> "$WORK/seen-rules.txt" ;;
  esac
  if [ "$_b" = "$_c" ]; then
    SAME=$((SAME + 1))
  else
    DIFF=$((DIFF + 1))
    if [ "$VERBOSE" -eq 1 ] || [ "$SHOWN" -lt 20 ]; then
      SHOWN=$((SHOWN + 1))
      log_note "DIFFER  baseline=$_b  candidate=$_c  $(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null | head -1 | cut -c1-140)"
    fi
  fi
done < "$WORK/corpus.final"

# Coverage, because "0 DIFFERENT" alone is unfalsifiable (CONSTITUTION §2.10). The universe is scraped from the guard source by shape
# suffix, so a new rule lowers coverage; floor_log_decision lines are excluded (`bash-clean.meta` is an ALLOW observation, not a rule).
# A universe that cannot be derived, or is smaller than what was observed, is a REFUSAL, not a number (PR #281).
_universe="$WORK/universe.txt"
_shapes='flat|argv|meta|content|path|channel'
grep -vE "floor_log_decision" "$BASE/$GUARD" 2>/dev/null \
  | grep -oE "[a-z0-9-]+\.($_shapes)([^a-z]|$)" \
  | sed -E "s/\.($_shapes)([^a-z]|$).*//" | sed 's/^/bash:/' | sort -u > "$_universe" || : > "$_universe"
M="$(wc -l < "$_universe" | tr -d ' ')"
sort -u "$WORK/seen-rules.txt" 2>/dev/null | sed '/^$/d' > "$WORK/seen.txt" || : > "$WORK/seen.txt"
# wc -l, not `grep -c . || echo 0`: on an empty file grep prints 0 AND exits 1, so SEEN became two lines and the refusal tests errored.
SEEN="$(wc -l < "$WORK/seen.txt" | tr -d ' ')"
log_note "$SAME identical, $DIFF DIFFERENT"
log_note "rules exercised: $SEEN of $M"
if [ "$M" -eq 0 ]; then
  # A guard that decides via permissionDecision has no derivable universe.
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
