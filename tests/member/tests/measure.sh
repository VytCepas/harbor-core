#!/usr/bin/env sh
# measure.sh (harbor#1278) — runs bin/member-tests.sh over the labelled change corpus and prints precision and recall.
#   sh measure.sh [--hook FILE] [--set dev|holdout|audit|all] [--errors] [--tsv] [--pct]
#   --hook FILE a copy of the hook to measure (default bin/member-tests.sh); --set S: corpus/<S>.jsonl (default all)
#   --errors lists every wrong row with the label's reason; --tsv one line per row
#   --pct one line of whole percents, rounded down: block precision, block recall, architecture accuracy (the suite's floors)
# Each row builds a scratch git repo as a laptop has it: files committed, some dirty at the prompt, the prompt-time snapshot, the turn's writes
# (`path` writes 5 lines, `path:N` N lines; a write outside the project goes beside it), an optional commit, then the Stop hook runs under
# `env -i`, PATH=/usr/bin:/bin, with a registry of one row (or none for an unregistered project).
# Block = the hook printed a decision. Architecture = which test-writing case its reason names, judged on rows that should block.
set -u
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(CDPATH='' cd -- "$HERE/../../.." && pwd)"
HOOK="$ROOT/bin/member-tests.sh"; SET=all; ERR=0; TSV=0; PCT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --hook) HOOK="$2"; shift ;; --set) SET="$2"; shift ;; --errors) ERR=1 ;; --tsv) TSV=1 ;; --pct) PCT=1 ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; *) echo "measure.sh: unknown $1" >&2; exit 2 ;;
  esac; shift
done
case "$SET" in dev|holdout|audit) FILES="$HERE/corpus/$SET.jsonl" ;; all) FILES="$HERE/corpus/dev.jsonl $HERE/corpus/holdout.jsonl $HERE/corpus/audit.jsonl" ;; *) echo "measure.sh: --set dev|holdout|audit|all" >&2; exit 2 ;; esac
TMP="$(mktemp -d "${TMPDIR:-/tmp}/measure-tests.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
MB="$TMP/bin"; mkdir -p "$MB"
cp "$HOOK" "$MB/member-tests.sh"
for f in library-log.sh library-git-safe.sh scope-roots.sh; do cp "$ROOT/bin/$f" "$MB/"; done
cp "$ROOT/contracts/roots.tsv" "$ROOT/contracts/agent-architectures.tsv" "$MB/"
export GIT_AUTHOR_NAME=m GIT_AUTHOR_EMAIL=m@example.invalid GIT_COMMITTER_NAME=m GIT_COMMITTER_EMAIL=m@example.invalid

lines() { _i=0; while [ "$_i" -lt "$1" ]; do printf 'line %s\n' "$_i"; _i=$((_i + 1)); done; }
# <file> <n>: append n lines; a write that is refused (a sandbox guarding .github/workflows or .env) fails the run, never a quiet true negative
put() { { mkdir -p "$(dirname "$1")" && lines "$2" >> "$1"; } 2>/dev/null || : > "$TMP/refused"; }

run_row() { # <row json> -> "<verdict> <arch>"
  _R="$TMP/r"; rm -rf "$_R"; mkdir -p "$_R/port/harbor-private" "$_R/home" "$_R/outside" "$_R/port/proj"
  _P="$_R/port/proj"; git -C "$_P" init -q
  if [ "$(printf '%s' "$1" | jq -r .registered)" = true ]; then
    printf 'proj\tproj\tworkload\t-\tstream-aligned\tx-as-a-service\t-\t-\tyes\t-\ta project\n' > "$_R/port/harbor-private/repos.tsv"
  else printf 'other\tother\tworkload\t-\tstream-aligned\tx-as-a-service\t-\t-\tyes\t-\tsomeone else\n' > "$_R/port/harbor-private/repos.tsv"; fi
  for f in $(printf '%s' "$1" | jq -r '.before[]'); do put "$_P/$f" 30; done
  put "$_P/.keep" 1
  git -C "$_P" add -A; git -C "$_P" commit -qm base
  for f in $(printf '%s' "$1" | jq -r '.dirty[]'); do put "$_P/$f" 2; done
  _E="env -i PATH=/usr/bin:/bin HOME=$_R/home PORT_ROOT=$_R/port HARBOR_SCOPE_PRIVATE=$_R/port/harbor-private TMPDIR=$TMP"
  printf '{"session_id":"s1"}' | $_E sh "$MB/member-tests.sh" snap
  for t in $(printf '%s' "$1" | jq -r '.touched[]'); do
    case "$t" in
      mv:*) _mv="${t#mv:}"; mkdir -p "$(dirname "$_P/${_mv#*>}")"; mv "$_P/${_mv%%>*}" "$_P/${_mv#*>}" ;;
      rm:*) rm -f "$_P/${t#rm:}" ;;
      *:*) put "$_P/${t%:*}" "${t##*:}" ;;
      *) put "$_P/$t" 5 ;;
    esac
  done
  for t in $(printf '%s' "$1" | jq -r '.outside[]'); do put "$_R/outside/$(basename "$t")" 5; done
  [ "$(printf '%s' "$1" | jq -r .commit)" != true ] || { git -C "$_P" add -A; git -C "$_P" commit -qm turn; }
  _O="$(printf '{"session_id":"s1","stop_hook_active":false}' | $_E sh "$MB/member-tests.sh" | jq -r '.reason // ""')"
  case "$_O" in
    *"member.tests:"*test-writing-trivial*) echo "1 trivial" ;;
    *"member.tests:"*test-writing:*) echo "1 full" ;;
    *"member.tests:"*) echo "1 named-none" ;;
    *) echo "0 -" ;;
  esac
}

for F in $FILES; do
  N="$(wc -l < "$F" | tr -d ' ')"; i=1
  while [ "$i" -le "$N" ]; do
    ROW="$(sed -n "${i}p" "$F")"; i=$((i + 1))
    set -- $(run_row "$ROW")
    printf '%s' "$ROW" | jq -r --arg b "$1" --arg a "$2" '[.id, (if .should_block then 1 else 0 end), $b, .arch, $a, .why] | @tsv'
  done
done > "$TMP/rows.tsv"

[ ! -e "$TMP/refused" ] || { echo "measure.sh: a write was refused (a sandbox?): the numbers would be wrong, run it where .github/ and .env can be written" >&2; exit 2; }
[ "$TSV" = 0 ] || { cat "$TMP/rows.tsv"; exit 0; }
[ "$ERR" = 0 ] || awk -F'\t' '
  $2 != $3 { printf "%-5s block %s  (label: %s)\n", $1, ($3 ? "FALSE POSITIVE" : "MISSED"), $6 }
  $2 == 1 && $3 == 1 && $4 != $5 { printf "%-5s architecture %s, label %s  (label: %s)\n", $1, $5, $4, $6 }' "$TMP/rows.tsv"

awk -F'\t' -v set="$SET" -v pct="$PCT" '
  { n++; if ($2 && $3) tp++; else if (!$2 && $3) fp++; else if ($2 && !$3) fn++; else tn++
    if ($2 && $3) { at++; if ($4 == $5) ac++ } }
  END { p = (tp + fp) ? 100 * tp / (tp + fp) : 0; r = (tp + fn) ? 100 * tp / (tp + fn) : 0; a = at ? 100 * ac / at : 0
        if (pct) { printf "%d %d %d\n", p, r, a; exit }
        printf "set=%s rows=%d\n", set, n
        printf "%-26s TP %3d  FP %3d  FN %3d  TN %3d   precision %5.1f%%  recall %5.1f%%\n", "send back (block)", tp, fp, fn, tn, p, r
        printf "%-26s %d of %d correct (%5.1f%%)\n", "architecture named", ac, at, a }' "$TMP/rows.tsv"
