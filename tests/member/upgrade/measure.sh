#!/usr/bin/env sh
# measure.sh (harbor#1278) — runs bin/member-upgrade.sh over the labelled corpus and prints precision and recall per clause.
#   sh measure.sh [--hook FILE] [--set dev|holdout|all] [--clean] [--errors] [--tsv] [--pct]
#   --hook FILE a copy of the hook to measure (default bin/member-upgrade.sh); --set S: corpus/<S>.jsonl (default all)
#   --clean leaves out rows labelled "ambiguous"; --errors lists every wrong row with the label's reason; --tsv one line per row
#   --pct one line of whole percents, rounded down: precision and recall of clause 1, clause 2, decides alone (the suite's floors)
# The hook runs as on a member laptop: `env -i`, PATH=/usr/bin:/bin, a transcript built from the row's tool list.
# Clause 1 = the Upgrade line (expected = should_upgrade). Clause 2 = the second reader (expected = decides and no Agent or Task call).
# "decides alone" feeds the same reply, padded past the length gate, with one tool and no agent, so only the regex is judged.
set -u
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(CDPATH='' cd -- "$HERE/../../.." && pwd)"
HOOK="$ROOT/bin/member-upgrade.sh"; SET=all; CLEAN=0; ERR=0; TSV=0; PCT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --hook) HOOK="$2"; shift ;; --set) SET="$2"; shift ;; --clean) CLEAN=1 ;; --errors) ERR=1 ;; --tsv) TSV=1 ;; --pct) PCT=1 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; *) echo "measure.sh: unknown $1" >&2; exit 2 ;;
  esac; shift
done
case "$SET" in dev|holdout) FILES="$HERE/corpus/$SET.jsonl" ;; all) FILES="$HERE/corpus/dev.jsonl $HERE/corpus/holdout.jsonl" ;; *) echo "measure.sh: --set dev|holdout|all" >&2; exit 2 ;; esac
TMP="$(mktemp -d "${TMPDIR:-/tmp}/measure.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
PAD="pad pad pad pad pad pad pad pad pad pad pad pad pad pad pad pad pad pad pad pad pad pad pad pad pad pad pad pad pad pad pad pad pad pad pad pad pad pad pad pad pad pad"

fires() { # <row json> <tools filter> <reply filter> — prints the hook's reason ("" when it stays quiet)
  printf '%s' "$1" | jq -c '{type:"user",message:{content:"do the work"}}, '"$2" > "$TMP/tx.jsonl"
  printf '%s' "$1" | jq -c --arg t "$TMP/tx.jsonl" '{session_id:"s",transcript_path:$t,last_assistant_message:('"$3"'),stop_hook_active:false}' \
    | env -i PATH=/usr/bin:/bin sh "$HOOK" | jq -r '.reason // ""'
}
USE='(.tools[] | {type:"assistant",message:{content:[{type:"tool_use",name:.}]}})'
ONE='{type:"assistant",message:{content:[{type:"tool_use",name:"Bash"}]}}'

for F in $FILES; do
  N="$(wc -l < "$F" | tr -d ' ')"; i=1
  while [ "$i" -le "$N" ]; do
    ROW="$(sed -n "${i}p" "$F")"; i=$((i + 1))
    [ "$CLEAN" = 0 ] || [ "$(printf '%s' "$ROW" | jq -r .ambiguous)" != true ] || continue
    R="$(fires "$ROW" "$USE" '.reply')"
    D="$(fires "$ROW" "$ONE" '"'"$PAD"'\n" + .reply')"
    f1=0; f2=0; fd=0
    case "$R" in *'starting "Upgrade:"'*) f1=1 ;; esac
    case "$R" in *'no second agent'*) f2=1 ;; esac
    case "$D" in *'no second agent'*) fd=1 ;; esac
    printf '%s' "$ROW" | jq -r --argjson f1 "$f1" --argjson f2 "$f2" --argjson fd "$fd" --arg r "$R" '
      ([.tools[] | select(. == "Agent" or . == "Task")] | length) as $a
      | [.id, (if .ambiguous then "amb" else "-" end), (if .should_upgrade then 1 else 0 end), $f1,
         (if .decides and $a == 0 then 1 else 0 end), $f2, (if .decides then 1 else 0 end), $fd, .why] | @tsv'
  done
done > "$TMP/rows.tsv"

[ "$TSV" = 0 ] || { cat "$TMP/rows.tsv"; exit 0; }
[ "$ERR" = 0 ] || awk -F'\t' '
  $3 != $4 { printf "%-5s clause1 %s  (label: %s)\n", $1, ($4 ? "FALSE POSITIVE" : "MISSED"), $9 }
  $5 != $6 { printf "%-5s clause2 %s  (label: %s)\n", $1, ($6 ? "FALSE POSITIVE" : "MISSED"), $9 }
  $7 != $8 { printf "%-5s decides-alone %s  (label: %s)\n", $1, ($8 ? "FALSE POSITIVE" : "MISSED"), $9 }' "$TMP/rows.tsv"

awk -F'\t' -v set="$SET" -v clean="$CLEAN" -v pct="$PCT" '
  function row(name, tp, fp, fn, tn,   p, r) {
    p = (tp + fp) ? 100 * tp / (tp + fp) : 0; r = (tp + fn) ? 100 * tp / (tp + fn) : 0
    printf "%-26s TP %3d  FP %3d  FN %3d  TN %3d   precision %5.1f%%  recall %5.1f%%\n", name, tp, fp, fn, tn, p, r
  }
  { n++
    if ($3 && $4) a_tp++; else if (!$3 && $4) a_fp++; else if ($3 && !$4) a_fn++; else a_tn++
    if ($5 && $6) b_tp++; else if (!$5 && $6) b_fp++; else if ($5 && !$6) b_fn++; else b_tn++
    if ($7 && $8) d_tp++; else if (!$7 && $8) d_fp++; else if ($7 && !$8) d_fn++; else d_tn++ }
  END { if (pct) { printf "%d %d %d %d %d %d\n", 100 * a_tp / (a_tp + a_fp), 100 * a_tp / (a_tp + a_fn), 100 * b_tp / (b_tp + b_fp), 100 * b_tp / (b_tp + b_fn), 100 * d_tp / (d_tp + d_fp), 100 * d_tp / (d_tp + d_fn); exit }
        printf "set=%s%s rows=%d\n", set, (clean ? " (ambiguous rows left out)" : ""), n
        row("clause 1  Upgrade line", a_tp, a_fp, a_fn, a_tn)
        row("clause 2  second reader", b_tp, b_fp, b_fn, b_tn)
        row("decides, regex alone", d_tp, d_fp, d_fn, d_tn) }' "$TMP/rows.tsv"
