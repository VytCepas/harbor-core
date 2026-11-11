#!/usr/bin/env sh
# format.test.sh (harbor#1278) — bin/bq-format.sh against contracts/bq-schema.tsv: no string type exists, every coded field refuses
# free text, a client-like name, a path and an e-mail, a refusal never repeats the value, and the probes catch a removed membership check.
. "$(dirname "$0")/../../lib/core.sh"; t_init
F="$T_ROOT/bin/bq-format.sh"; FX="$T_ROOT/tests/bq/fixtures/rows.json"; SCHEMA="$T_ROOT/contracts/bq-schema.tsv"
X="$T_TMP/x"; mkdir -p "$X"

t_section "1 - the schema: no string type, every range bounded"
t_exit "the real schema passes" 0 sh "$F" schema
# retype <label> <awk edit of one row> <expected text>: a copy with one row changed must be refused
retype() {
  awk -F'\t' -v OFS='\t' "$2" "$SCHEMA" > "$X/schema.tsv"
  _o="$(sh "$F" schema "$X/schema.tsv" 2>&1)" && _rc=0 || _rc=$?
  if [ "$_rc" = 1 ] && printf '%s' "$_o" | grep -qF "$3"; then t_pass; else t_fail "$1 (rc $_rc: $_o)"; fi
}
retype "a field typed string" '$1 == "decision" && $2 == "rule" { $3 = "string" } { print }' "type string is not in the grammar"
retype "a field typed STRING" '$1 == "heartbeat" && $2 == "mode" { $3 = "STRING" } { print }' "type STRING is not in the grammar"
retype "a label in a fact table" '$1 == "decision" && $2 == "rule" { $3 = "label" } { print }' "label (a string) only in a dim_ table"
retype "an int with no upper bound" '$1 == "decision" && $2 == "count" { $4 = "1.." } { print }' "wants a bounded range"
retype "a set no file names" '$1 == "decision" && $2 == "tier" { $4 = "client" } { print }' "set client is not in contracts/bq-values.tsv"
retype "a fact table without person_id" '!($1 == "session" && $2 == "person_id") { print }' "missing the common field person_id"
retype "an hour beside a person id" '$1 == "decision" && $2 == "day" { $3 = "hour" } { print }' "a time finer than a day beside a person id"
retype "a minute in a per-person table" '{ print } $1 == "heartbeat" && $2 == "day" { print "heartbeat", "seen_at", "minute", "-", "no", "x", "x" }' "a time finer than a day beside a person id"
retype "a person id in an agg_ table" '{ print } $1 == "agg_approval" && $2 == "rule" { print "agg_approval", "person_id", "rid", "-", "yes", "x", "x" }' "an agg_ table carries no person id"
for t in $(sh "$F" tables); do
  _s="$(sh "$F" bqschema "$t" | jq '[.[] | select(.type == "STRING")] | length')"
  case "$t" in dim_*) ;; *) t_eq "$t: no STRING column in its BigQuery schema" 0 "$_s" ;; esac
done
t_eq "a table for every fixture row, and the reverse" "$(sh "$F" tables | tr '\n' ' ')" "$(jq -r 'keys[]' "$FX" | tr '\n' ' ')"

t_section "2 - every fixture row is valid"
for t in $(sh "$F" tables); do
  jq -c --arg t "$t" '.[$t]' "$FX" > "$X/one.json"
  t_exit "$t fixture" 0 sh "$F" row "$t" "$X/one.json"
done

t_section "3 - no coded field takes text, a client name, a path or an e-mail"
LONG="$(printf '%0200d' 0 | tr 0 x)"
jq -n --arg long "$LONG" '["the client said", "acme-prod-bucket", "/Users/someone/x", "~/port/x", "alice@example.com", $long]' > "$X/probes.json"
NPROBE="$(jq length "$X/probes.json")"
TOTAL=0
for t in $(sh "$F" tables); do
  # one row per (coded field, probe), the fixture row with that field replaced
  awk -F'\t' -v t="$t" '$1 == t && ($3 == "code" || $3 == "codes") { print $2 "\t" $3 }' "$SCHEMA" > "$X/fields"
  [ -s "$X/fields" ] || continue
  jq -R -s -c --arg t "$t" --slurpfile fx "$FX" --slurpfile p "$X/probes.json" '
    split("\n") | map(select(length > 0) | split("\t")) as $fs
    | $fs[] as $f | $p[0][] as $v
    | $fx[0][$t] + {($f[0]): (if $f[1] == "codes" then [$v] else $v end)}' "$X/fields" > "$X/rows.jsonl"
  _n="$(wc -l < "$X/rows.jsonl" | tr -d ' ')"; TOTAL=$((TOTAL + _n))
  _o="$(sh "$F" row "$t" "$X/rows.jsonl" --keep "$X/kept" --counts "$X/counts" 2>&1)" || :
  t_eq "$t: all $_n probe rows refused" 0 "$(wc -l < "$X/kept" | tr -d ' ')"
  t_eq "$t: each as not-in-set" "{\"not-in-set\":$_n}" "$(cat "$X/counts")"
  t_hasnt "$t: the report repeats no probe" "$_o" "acme"
  case "$_o" in *alice*|*"client said"*|*xxxxxxxxxx*) t_fail "$t: a probe value is in the report" ;; *) t_pass ;; esac
done
_want="$(awk -F'\t' '$3 == "code" || $3 == "codes"' "$SCHEMA" | grep -c .)"
t_eq "every coded field of every table was probed, $NPROBE values each" "$((_want * NPROBE))" "$TOTAL"
[ "$_want" -ge 30 ] && t_pass || t_fail "only $_want coded fields found: the probe list is too thin to mean anything"

t_section "4 - numbers, keys and times take no text either"
for t in decision heartbeat activity; do
  awk -F'\t' -v t="$t" '$1 == t && $3 ~ /^(int|key|hex6|hex8|hour|minute|day)$/ { print $2 }' "$SCHEMA" > "$X/fields"
  jq -R -s -c --arg t "$t" --slurpfile fx "$FX" 'split("\n") | map(select(length > 0))[] as $f | $fx[0][$t] + {($f): "the client said"}' "$X/fields" > "$X/rows.jsonl"
  _n="$(wc -l < "$X/rows.jsonl" | tr -d ' ')"
  sh "$F" row "$t" "$X/rows.jsonl" --keep "$X/kept" --counts "$X/counts" 2>/dev/null || :
  t_eq "$t: text in each of its $_n typed fields is bad-type" "{\"bad-type\":$_n}" "$(cat "$X/counts")"
done
jq -c '.ingest_audit + {run_at: "2026-11-07T10:13:22Z"}' "$FX" > "$X/one.json"
sh "$F" row ingest_audit "$X/one.json" --counts "$X/counts" 2>/dev/null || :
t_eq "seconds where a minute is wanted" '{"ts-not-coarse":1}' "$(cat "$X/counts")"
jq -c '.decision + {count: 0}' "$FX" > "$X/one.json"
sh "$F" row decision "$X/one.json" --counts "$X/counts" 2>/dev/null || :
t_eq "a count outside its range" '{"out-of-range":1}' "$(cat "$X/counts")"
jq -c '.decision + {rule: "hub:3:200"}' "$FX" > "$X/one.json"
sh "$F" row decision "$X/one.json" --counts "$X/counts" 2>/dev/null || :
t_eq "a hub rule index past the policy's 200" '{"not-in-set":1}' "$(cat "$X/counts")"

t_section "5 - an unknown key is refused and not named"
jq -c '.decision + {"note about acme": "the client said"}' "$FX" > "$X/one.json"
_o="$(sh "$F" row decision "$X/one.json" --counts "$X/counts" 2>&1)" && _rc=0 || _rc=$?
t_eq "exit 1" 1 "$_rc"
t_eq "as unknown-key" '{"unknown-key":1}' "$(cat "$X/counts")"
t_hasnt "the key is not repeated" "$_o" "acme"
printf 'not json at all\n' > "$X/one.json"
sh "$F" row decision "$X/one.json" --counts "$X/counts" 2>/dev/null || :
t_eq "a line that is not JSON" '{"not-json":1}' "$(cat "$X/counts")"
t_exit "code refuses a file with one bad row" 1 sh "$F" code decision "$X/one.json"

t_section "6 - coding for a load"
jq -c '.decision' "$FX" > "$X/one.json"
_c="$(sh "$F" code decision "$X/one.json")"
t_eq "a person id becomes base64" "$(printf '0123456789abcdef0123456789abcdef' | xxd -r -p | base64)" "$(printf '%s' "$_c" | jq -r .person_id)"
t_eq "a rule becomes its INT64 code" "$(awk -F'\t' '$1 == "rule" && $3 == "admission.key-material-egress" { print $2 }' "$T_ROOT/contracts/bq-values.tsv")" "$(printf '%s' "$_c" | jq -r .rule)"
jq -c '.agg_approval' "$FX" > "$X/one.json"
t_eq "a hub rule gets the hub code" 1000003000 "$(sh "$F" code agg_approval "$X/one.json" | jq -r .rule)"
t_eq "no string is left in a coded fact row" 0 "$(printf '%s' "$_c" | jq '[to_entries[] | select(.key != "day" and .key != "person_id" and .key != "core" and (.value | type) == "string")] | length')"

t_section "7 - the probes catch a removed membership check"
# The mutant: bq-format.sh with member() accepting everything. The probes of section 3 must see it, or they prove nothing.
M="$T_TMP/mutant"; mkdir -p "$M"; cp "$T_ROOT/bin/library-log.sh" "$M/"
sed 's/^def member(\$sets):.*/def member($sets): true;/' "$F" > "$M/bq-format.sh"
t_eq "the mutant differs from the original in that one line" 1 "$(diff "$F" "$M/bq-format.sh" | grep -c '^>')"
jq -c '.decision + {rule: "acme-prod-bucket"}' "$FX" > "$X/one.json"
HARBOR_BQ_SCHEMA="$SCHEMA" HARBOR_BQ_VALUES="$T_ROOT/contracts/bq-values.tsv" sh "$M/bq-format.sh" row decision "$X/one.json" --keep "$X/kept" 2>/dev/null && _rc=0 || _rc=$?
t_eq "without the check a client name passes" "0 1" "$_rc $(wc -l < "$X/kept" | tr -d ' ')"
t_exit "with it, the same row is refused" 1 sh "$F" row decision "$X/one.json"
t_done
