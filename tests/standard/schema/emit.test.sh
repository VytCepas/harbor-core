#!/usr/bin/env sh
# ci.schema-emit (harbor#1425): the producer validates the fixture it emits against the schema it owns, so a broken field
# is red here before yard or fleet reads it. The red proof breaks one field of a copy of the real fixture.
. "$(dirname "$0")/../../lib/core.sh"; t_init
SS="$T_ROOT/bin/standard-schema.sh"
R="$T_TMP/h"; mkdir -p "$R/contracts/schemas" "$R/fixtures/marker"
cp "$T_ROOT/contracts/seams.tsv" "$R/contracts/"; cp "$T_ROOT"/contracts/schemas/*.json "$R/contracts/schemas/"; cp "$T_ROOT/fixtures/marker/cases.json" "$R/fixtures/marker/"
S="$R/contracts/schemas/marker-cases.schema.json"; F="$R/fixtures/marker/cases.json"

t_section "the real fixture satisfies the schema harbor owns"
out="$(sh "$SS" emit --root "$T_ROOT" 2>&1)"; t_eq "emit exits 0" "0" "$?"
t_has "the fixture is named" "$out" "fixtures/marker/cases.json satisfies"

t_section "one field broken in the producer fixture is red"
jq '.cases[3].expect = "Repo"' "$F" > "$F.n" && mv "$F.n" "$F"
out="$(sh "$SS" emit --root "$R" 2>&1)"; rc=$?
t_eq "exit 1" "1" "$rc"
t_has "names the path and the value" "$out" '$.cases[3].expect: "Repo" is not one of'

t_section "a retyped field, a dropped required field and an extra case are each caught"
cp "$T_ROOT/fixtures/marker/cases.json" "$F"
jq '.cases[7].settled = "yes"' "$F" > "$F.n" && mv "$F.n" "$F"; t_has "retyped" "$(sh "$SS" emit --root "$R" 2>&1)" "settled: is string, the schema wants boolean"
cp "$T_ROOT/fixtures/marker/cases.json" "$F"
jq 'del(.cases[5].why)' "$F" > "$F.n" && mv "$F.n" "$F"; t_has "dropped" "$(sh "$SS" emit --root "$R" 2>&1)" "lacks the required field why"
cp "$T_ROOT/fixtures/marker/cases.json" "$F"
jq '.cases = []' "$F" > "$F.n" && mv "$F.n" "$F"; t_has "empty" "$(sh "$SS" emit --root "$R" 2>&1)" "has 0 items, at least 1"

t_section "restored, it is green again"
cp "$T_ROOT/fixtures/marker/cases.json" "$F"
sh "$SS" emit --root "$R" >/dev/null 2>&1; t_eq "exit 0" "0" "$?"

t_section "a schema row with no schema file, and a schema with no fixture, are red; nothing validated is unchecked"
rm "$S"; t_has "gone" "$(sh "$SS" emit --root "$R" 2>&1)" "not in the tree"
cp "$T_ROOT/contracts/schemas/marker-cases.schema.json" "$S"; jq 'del(.["x-fixture"])' "$S" > "$S.n" && mv "$S.n" "$S"
t_has "no x-fixture" "$(sh "$SS" emit --root "$R" 2>&1)" "carries no x-fixture"
awk -F'\t' 'BEGIN{OFS="\t"} /^#/||$1=="id"{print;next} {$7="-";print}' "$R/contracts/seams.tsv" > "$R/s" && mv "$R/s" "$R/contracts/seams.tsv"
sh "$SS" emit --root "$R" >/dev/null 2>&1; t_eq "no harbor-owned schema: exit 3, not a green" "3" "$?"

t_section "validate on a bare document"
printf '{"a":1}' > "$R/d.json"; printf '{"type":"object","required":["a","b"],"additionalProperties":false,"properties":{"a":{"type":"string"}}}' > "$R/s.json"
out="$(sh "$SS" validate "$R/s.json" "$R/d.json" 2>&1)"; t_eq "exit" "1" "$?"
t_has "type" "$out" '$.a: is integer, the schema wants string'
t_has "required" "$out" "lacks the required field b"
t_done
