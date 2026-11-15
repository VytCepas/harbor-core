#!/usr/bin/env sh
# drift.test.sh (harbor#1278) — contracts/bq-values.tsv equals its sources and is append-only: a value a source gained, a row
# deleted by hand and a renumbered code are each red, and the sets carry what the floor and the hub vocabulary name.
. "$(dirname "$0")/../../lib/core.sh"; t_init
F="$T_ROOT/bin/bq-format.sh"; V="$T_ROOT/contracts/bq-values.tsv"; X="$T_TMP/x"; mkdir -p "$X"
HARBOR_BQ_VALUES_BASE="$V"; export HARBOR_BQ_VALUES_BASE

t_section "1 - the file matches its sources"
t_exit "values --check is green" 0 sh "$F" values --check
t_eq "every code is used once" 0 "$(awk -F'\t' '!/^#/ && $1 != "set" && seen[$2]++' "$V" | grep -c . || true)"

t_section "2 - drift either way is red"
awk -F'\t' '!($1 == "tier" && $3 == "low")' "$V" > "$X/fewer.tsv"
t_exit "a value its source names, missing here" 1 env HARBOR_BQ_VALUES="$X/fewer.tsv" HARBOR_BQ_VALUES_BASE="$X/fewer.tsv" sh "$F" values --check
awk -F'\t' -v OFS='\t' '{ print } END { print "tier", 99999, "acme-tier", "live", "by hand" }' "$V" > "$X/more.tsv"
t_exit "a live value no source names" 1 env HARBOR_BQ_VALUES="$X/more.tsv" HARBOR_BQ_VALUES_BASE="$X/more.tsv" sh "$F" values --check
awk -F'\t' -v OFS='\t' '$1 == "tier" && $3 == "low" { $2 = 88888 } { print }' "$V" > "$X/renum.tsv"
t_exit "a renumbered code, against the base" 1 env HARBOR_BQ_VALUES="$X/renum.tsv" sh "$F" values --check

t_section "3 - --write keeps codes and only appends"
cp "$V" "$X/w.tsv"
awk -F'\t' -v OFS='\t' '{ print } END { print "tier", 99999, "gone-tier", "live", "by hand" }' "$V" > "$X/w.tsv"
HARBOR_BQ_VALUES="$X/w.tsv" sh "$F" values --write >/dev/null 2>&1
t_eq "a value no source names is kept, retired" "99999 retired" "$(awk -F'\t' '$3 == "gone-tier" { print $2, $4 }' "$X/w.tsv")"
t_eq "every old code keeps its value" "" "$(awk -F'\t' 'FILENAME == ARGV[1] { if ($1 != "set" && $0 !~ /^#/) c[$1 FS $3] = $2; next } ($1 FS $3) in c && c[$1 FS $3] != $2' "$V" "$X/w.tsv")"
t_exit "a retired value still validates" 0 env HARBOR_BQ_VALUES="$X/w.tsv" sh "$F" values --check

t_section "4 - the sets carry their sources"
for g in $(sed -n "s/^FLOOR_OBS_GUARDS='\(.*\)'\$/\1/p" "$T_ROOT/bin/library-admission.sh"); do
  awk -F'\t' -v g="$g" '$1 == "guard" && $3 == g { f = 1 } END { exit !f }' "$V" && t_pass || t_fail "guard $g is missing"
done
for k in $(awk -F'\t' '$1 == "kind" { print $2 }' "$T_ROOT/contracts/hub-vocabulary.tsv"); do
  awk -F'\t' -v k="$k" '$1 == "hub_kind" && $3 == k { f = 1 } END { exit !f }' "$V" && t_pass || t_fail "kind $k is missing"
done
for r in admission.key-material-egress egress-clean subagent-contract bash-clean hub-hook; do
  awk -F'\t' -v r="$r" '$1 == "rule" && $3 == r { f = 1 } END { exit !f }' "$V" && t_pass || t_fail "rule $r is missing"
done
# The member side's sets (D9) are a second copy: held equal here, so a laptop never sends a value BigQuery refuses.
HV="$T_ROOT/contracts/hub-vocabulary.tsv"
for s in tool verb_class; do
  t_eq "hub vocabulary $s equals the BigQuery set" "$(awk -F'\t' -v s="$s" '$1 == s && $4 == "live" { print $3 }' "$V" | sort | tr '\n' ' ')" \
    "$(awk -F'\t' -v s="$s" '$1 == s { print $2 }' "$HV" | sort | tr '\n' ' ')"
done
t_eq "every hub vocabulary verdict is a BigQuery verdict" "" "$(awk -F'\t' 'FILENAME == ARGV[1] { if ($1 == "verdict") v[$3] = 1; next } $1 == "verdict" && !($2 in v) { print $2 }' "$V" "$HV")"
t_eq "no value holds a space, slash or @" 0 "$(awk -F'\t' '!/^#/ && $1 != "set" && $3 ~ /[ \/@~]/' "$V" | grep -c . || true)"
t_done
