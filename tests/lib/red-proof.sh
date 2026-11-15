#!/usr/bin/env sh
# tests/lib/red-proof.sh [--write] [root] — controls.tsv red_proof for admission rules, derived from the guard tables (harbor#1392).
# A rule's red_proof is the suite that runs the table holding a row that fires it (want not allow); the guard's own
# tests/guards/<g>.jsonl first, then its parts in path order. Prints `<guard>:<rule> TAB <suite>`; --write sets column 11
# of every admission row whose `emitted` the tables fire, leaving rows no table names as typed. tests/lib/check.sh
# (test.red-proof-derived) fails when the column and this derivation differ.
set -eu
W=0; [ "${1:-}" != --write ] || { W=1; shift; }
R="${1:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}"
G="$R/tests/guards"; A="$R/tests/admission"; CTL="$R/standards/naming/controls.tsv"

suite() { # <guard> <table> — the suite tests/lib/check.sh routing requires beside a table, if it exists
  case "$2" in
    "$A"/*) _s="${2%.jsonl}.test.sh" ;;
    "$G/$1.jsonl") _s="$A/$1/$1.test.sh"; [ -f "$_s" ] || _s="$G/$1-test.sh" ;;
    *) _n="$(basename "$2" .jsonl)"; _s="$A/$1/${_n#*.}.test.sh"; [ -f "$_s" ] || _s="$G/$_n-test.sh" ;;
  esac
  [ ! -f "$_s" ] || printf '%s' "${_s#"$R"/}"
}

derive() {
  for _g in $(jq -r '.guard' "$G/guards.jsonl" 2>/dev/null); do
    { [ ! -f "$G/$_g.jsonl" ] || echo "$G/$_g.jsonl"
      { find "$G" -name "$_g.*.jsonl" ! -name '*.msg.jsonl'; find "$A/$_g" -name '*.jsonl' ! -name message.jsonl; } 2>/dev/null | sort
    } | while IFS= read -r _t; do
      _s="$(suite "$_g" "$_t")"; [ -n "$_s" ] || continue
      jq -r --arg g "$_g" --arg s "$_s" 'select(.rule != null and .rule != "none" and .want != "allow") | "\($g):\(.rule)\t\($s)"' "$_t"
    done
  done | awk -F'\t' '!seen[$1]++'
}

[ "$W" = 1 ] || { derive; exit 0; }
_d="$(mktemp "${TMPDIR:-/tmp}/red-proof.XXXXXX")"; trap 'rm -f "$_d" "$_d.new"' EXIT
derive > "$_d"
awk -F'\t' -v OFS='\t' 'NR == FNR { p[$1] = $2; next }
  !/^#/ && $3 == "admission" && ($12 in p) { $11 = p[$12] } { print }' "$_d" "$CTL" > "$_d.new"
cat "$_d.new" > "$CTL"
