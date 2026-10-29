#!/usr/bin/env sh
# The stream registry (harbor#1181): every row names a writer that exists and whose source still holds the row's
# needle, ids are unique and the enums closed. STREAMS_TSV points it at another copy (the break-it cases below).
. "$(dirname "$0")/../lib/core.sh"; t_init
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REG="${STREAMS_TSV:-$ROOT/CONTRACTS/streams.tsv}"

# registry_defects <file> — prints one line per defect, nothing when the registry is sound.
# awk index(), never grep: this box's grep skips files it judges binary (failure-observe.sh is one).
registry_defects() {
  awk -F'\t' -v root="$ROOT" '
    /^#/ || NF == 0 { next }
    !hdr { hdr = 1; if ($1 != "id" || NF != 10) print "header: want 10 columns starting with id"; next }
    {
      if (NF != 10) { print "row " NR ": " NF " columns, want 10"; next }
      for (i = 1; i <= 10; i++) if ($i == "") print "row " NR ": blank column " i
      if (seen[$1]++) print "row " NR ": duplicate id " $1
      if ($6 !~ /^(rotate-1|archive|prune-14d|prune-15d|none|overwrite|rewrite-merge|truncate-prune|git)$/) print $1 ": bad retention " $6
      if ($7 !~ /^(digest-only|derived|free-text|secret-adjacent)$/) print $1 ": bad sensitivity " $7
      if ($8 !~ /^(open|warn|closed)$/) print $1 ": bad on_fail " $8
      if ($9 !~ /^(spill|block)$/) print $1 ": bad target_on_fail " $9
      if ($10 !~ /^[0-8]$/) print $1 ": bad lane " $10
      w = root "/" $3
      found = 0
      while ((getline line < w) > 0) if (index(line, $4)) { found = 1; break }
      close(w)
      if (!found) print $1 ": " $3 " does not exist or no longer names " $4
      n++
    }
    END { if (n < 1) print "no rows: an empty registry registers nothing" }' "$1"
}

t_section "the registry as committed"
t_eq "every row is sound" "" "$(registry_defects "$REG")"
t_eq "the guard ledger is registered" yes "$(awk -F'\t' '$1=="guard.decisions"{print "yes"}' "$REG")"
t_eq "approvals are the streams that fail closed" "approvals approvals.queue" \
  "$(awk -F'\t' '!/^#/ && $9=="block"{printf "%s%s", s, $1; s=" "}' "$REG")"

# unregistered_emits <dir> <registry> — every `harbor_emit <id>` call in <dir> whose id has no registry row.
unregistered_emits() {
  find "$1" -type f ! -name stream-lib.sh -exec awk '
    { while (match($0, /harbor_emit[ \t]+[a-z0-9.-]+/)) {
        s = substr($0, RSTART, RLENGTH); sub(/harbor_emit[ \t]+/, "", s); print s; $0 = substr($0, RSTART + RLENGTH) } }' {} + \
    | sort -u | while IFS= read -r _id; do
        awk -F'\t' -v i="$_id" '!/^#/ && $1 == i { f = 1 } END { exit !f }' "$2" || printf '%s\n' "$_id"
      done
}
t_section "every harbor_emit call names a registered stream (lane 3)"
t_eq "bin/ emits only registered streams" "" "$(unregistered_emits "$ROOT/bin" "$REG")"
mkdir -p "$T_TMP/fx"; printf 'harbor_emit no.such.stream "{}"\nharbor_emit events "{}"\n' > "$T_TMP/fx/x.sh"
t_eq "break-it: an unregistered id is named, a registered one is not" no.such.stream "$(unregistered_emits "$T_TMP/fx" "$REG")"

t_section "break-it: each defect class is caught"
BAD="$T_TMP/streams.tsv"
_mut() { awk -F'\t' -v OFS='\t' "$1" "$REG" > "$BAD"; registry_defects "$BAD"; }
t_has "a writer that no longer names its sink" "$(_mut '$1=="events"{$4="NO-SUCH-NEEDLE"}1')" 'events: bin/event-bus.sh does not exist or no longer names'
t_has "a writer that does not exist" "$(_mut '$1=="sweep"{$3="bin/no-such.sh"}1')" 'sweep: bin/no-such.sh does not exist'
t_has "a duplicate id" "$(_mut '$1=="ci.lost"{$1="ci.reruns"}1')" 'duplicate id ci.reruns'
t_has "an open enum" "$(_mut '$1=="usage.daily"{$9="maybe"}1')" 'usage.daily: bad target_on_fail maybe'
t_has "a short row" "$(_mut '$1=="dispatch"{NF=9}1')" '9 columns, want 10'
t_has "an empty registry" "$(awk '/^#/ || $1=="id"' "$REG" > "$BAD"; registry_defects "$BAD")" 'no rows'
t_done
