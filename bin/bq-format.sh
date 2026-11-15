#!/usr/bin/env sh
# bq-format.sh (harbor#1278) — harbor's BigQuery rows against contracts/bq-schema.tsv. Reads and reports; writes only what --keep, --counts and --write name.
#   sh bq-format.sh schema [file]                          the schema: every type in the grammar, every range bounded, every set known
#   sh bq-format.sh row <table> <file> [--keep F] [--counts F]   each row (one JSON object per line, or one array) against its table;
#                                                          --keep writes the valid rows, --counts the refused rows by reason, as JSON
#   sh bq-format.sh code <table> <file>                    the rows coded for a load: a set value becomes its INT64 code, hex its
#                                                          base64. Refuses the whole file if any row is invalid
#   sh bq-format.sh bqschema <table>                       the table's BigQuery JSON schema, generated from the schema file
#   sh bq-format.sh layout <table>                         partition=<field> cluster=<fields>: the first time field, and person_id
#   sh bq-format.sh tables                                 the table names, one per line
#   sh bq-format.sh values --print|--check|--write         the value sets from their sources, against contracts/bq-values.tsv
# A finding names the row, the reason (set ingest_reason) and the field, never the value: a refused value must not leave through its
# own report. An unknown key is not named either, since a key can be text too.
# Exit 0 valid, 1 refused, 2 usage, 3 unchecked: a schema or value file that can't be read, so nothing was judged.
set -eu
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(CDPATH='' cd -- "$HERE/.." && pwd)"
SCHEMA="${HARBOR_BQ_SCHEMA:-$ROOT/contracts/bq-schema.tsv}"
VALUES="${HARBOR_BQ_VALUES:-$ROOT/contracts/bq-values.tsv}"
LOG_FD=2; export LOG_FD
. "$HERE/library-log.sh"
log_init bq-format

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
unchecked() { log_fail "unchecked — $1, so nothing was judged"; log_nofix "contracts/bq-schema.tsv"; log_end || :; exit 3; }
command -v jq >/dev/null 2>&1 || unchecked "jq is missing"

W=''
trap '[ -z "$W" ] || rm -rf "$W"' EXIT
trap 'exit 130' INT HUP TERM
work() { [ -n "$W" ] || W="$(mktemp -d "${TMPDIR:-/tmp}/bq-format.XXXXXX")"; }
# refuse <findings-file> <summary> <fix>: each finding as a note, then one FAIL and its fix, exit 1. A loop over a file, not a pipe:
# a pipe's right side is a subshell, and the counts would die with it.
refuse() {
  while IFS= read -r _l; do log_note "$_l"; done < "$1"
  log_fail "$2"; log_fix "$3"; log_end || :; exit 1
}

# The schema as JSON: {table: [{field, type, set, lo, hi, nullable}]}, in file order.
schema_json() { # <file>
  awk -F'\t' '/^#/ || NF == 0 || $1 == "table" { next } { print }' "$1" | jq -R -s '
    split("\n") | map(select(length > 0) | split("\t"))
    | map({table: .[0], field: .[1], type: .[2], set: .[3], nullable: (.[4] == "yes"), nf: length}
          + (if (.[3] // "") | test("^-?[0-9.]+\\.\\.-?[0-9.]+$")
             then (.[3] | split("..") | {lo: (.[0] | tonumber), hi: (.[1] | tonumber)}) else {} end))
    | group_by(.table) | map({key: .[0].table, value: .}) | from_entries'
}
# The values as JSON: {set: {value: code}}, retired values included: a laptop on an older core still loads.
values_json() {
  awk -F'\t' '/^#/ || NF == 0 || $1 == "set" { next } { print }' "$VALUES" | jq -R -s '
    split("\n") | map(select(length > 0) | split("\t")) | group_by(.[0])
    | map({key: .[0][0], value: (map({key: .[2], value: (.[1] | tonumber)}) | from_entries)}) | from_entries'
}

# Shared jq. The hub forms (D6): an admin-written rule or pack id never reaches BigQuery, only its place in the signed policy.
JQ_DEFS='
def hubrule: type == "string" and test("^hub:[1-9][0-9]{0,5}:(0|[1-9][0-9]?|1[0-9]{2})$");
def hubpack: type == "string" and test("^hubpack:(0|[1-9][0-9]?|1[0-9]{2})$");
def dyn($s): if $s == "rule" or $s == "check" then hubrule elif $s == "pack" then hubpack else false end;
# MEMBERSHIP: a value is in one of the sets the field names, or in the hub form of one of them. Nothing else passes.
def member($sets): . as $x | any(($sets | split("|"))[]; . as $s | (($vv[0][$s] // {}) | has($x)) or ($x | dyn($s)));
def utc: test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$") and ((try fromdateiso8601 catch null) != null);
def timecheck($re): if type != "string" then ["bad-type"] elif (utc | not) then ["bad-type"] elif test($re) then [] else ["ts-not-coarse"] end;
def hexw($n): if type == "string" and test("^[0-9a-f]{" + ($n | tostring) + "}$") then [] else ["bad-type"] end;
def val($f):
  if $f.type == "code" then (if type != "string" then ["bad-type"] elif member($f.set) then [] else ["not-in-set"] end)
  elif $f.type == "codes" then
    (if type != "array" or length > 200 then ["bad-type"]
     elif all(.[]; type == "string") | not then ["bad-type"]
     elif all(.[]; member($f.set)) then [] else ["not-in-set"] end)
  elif $f.type == "int" then
    (if type != "number" or . != floor then ["bad-type"] elif . < $f.lo or . > $f.hi then ["out-of-range"] else [] end)
  elif $f.type == "float" then
    (if type != "number" or isinfinite or isnan then ["bad-type"] elif . < $f.lo or . > $f.hi then ["out-of-range"] else [] end)
  elif $f.type == "bool" then (if type == "boolean" then [] else ["bad-type"] end)
  elif $f.type == "hour" then timecheck("T[0-9]{2}:00:00Z$")
  elif $f.type == "minute" then timecheck(":00Z$")
  elif $f.type == "day" then
    (if type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$") and (((. + "T00:00:00Z") | try fromdateiso8601 catch null) != null)
     then [] else ["bad-type"] end)
  elif $f.type == "rid" then hexw(32)
  elif $f.type == "hex6" then hexw(12)
  elif $f.type == "hex8" then hexw(16)
  elif $f.type == "label" then (if type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$") then [] else ["bad-type"] end)
  else ["bad-type"] end;
# one row: its findings, [{r, f}], in field order
def judge($fs):
  . as $row
  | if type != "object" then [{r: "bad-type", f: "-"}] else
      ([keys[] | select(. as $k | $fs | map(.field) | index($k) | not)] | map({r: "unknown-key", f: "-"}) | unique)
      + ($fs | map(. as $f
          | if ($row[$f.field] // null) == null then (if $f.nullable then [] else [{r: "missing-key", f: $f.field}] end)
            else ($row[$f.field] | val($f) | map({r: ., f: $f.field})) end) | add // [])
    end;
'

# hex to base64, for BYTES in a JSON load
JQ_CODE='
def nib: explode | map(if . >= 97 then . - 87 else . - 48 end);
def b64: nib as $n | [range(0; $n | length; 2) | $n[.] * 16 + $n[. + 1]] as $b
  | "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" as $a
  | [range(0; $b | length; 3) as $i | $b[$i:$i + 3] as $c | ($c | length) as $l
     | ($c[0] * 65536 + ($c[1] // 0) * 256 + ($c[2] // 0)) as $v
     | ([18, 12, 6, 0] | map(($v / pow(2; .) | floor) % 64) | map($a[.:. + 1]) | join("")) as $s
     | if $l == 3 then $s elif $l == 2 then $s[0:3] + "=" else $s[0:2] + "==" end] | join("");
# the hub forms get codes no static value uses: rule and check 1e9 + serial * 1000 + index, pack 3e9 + index
def hubcode: if test("^hub:") then (split(":") | 1000000000 + (.[1] | tonumber) * 1000 + (.[2] | tonumber))
             else (split(":") | 3000000000 + (.[1] | tonumber)) end;
def code1($sets): . as $x | (first(($sets | split("|"))[] as $s | ($vv[0][$s] // {})[$x] // empty) // ($x | hubcode));
def encode($fs): . as $row | reduce $fs[] as $f ({};
  if ($row[$f.field] // null) == null then . + {($f.field): null}
  elif $f.type == "code" then . + {($f.field): ($row[$f.field] | code1($f.set))}
  elif $f.type == "codes" then . + {($f.field): ($row[$f.field] | map(code1($f.set)))}
  elif $f.type == "rid" or $f.type == "hex6" or $f.type == "hex8" then . + {($f.field): ($row[$f.field] | b64)}
  else . + {($f.field): $row[$f.field]} end);
'

need_schema() {
  [ -r "$SCHEMA" ] || unchecked "the schema $SCHEMA can't be read"
  work; schema_json "$SCHEMA" > "$W/schema.json" 2>/dev/null || unchecked "the schema $SCHEMA does not parse"
}
need_values() {
  [ -r "$VALUES" ] || unchecked "the value sets $VALUES can't be read"
  work; values_json > "$W/values.json" 2>/dev/null || unchecked "the value sets $VALUES do not parse"
}
need_table() { # <table>
  jq -e --arg t "$1" 'has($t)' "$W/schema.json" >/dev/null || { log_fail "no table $1 in the schema"; log_nofix "sh $0 tables"; log_end || :; exit 2; }
}
# rows of a file as one array: a JSON array, or one value per line. A line that is not JSON is a row refused as not-json.
rows_of() { # <file> <out>
  if jq -e 'type == "array"' "$1" >/dev/null 2>&1; then jq -c '.' "$1" > "$2"
  else jq -R -s -c 'split("\n") | map(select(length > 0) | (fromjson? // {"\u0000not-json": true}))' "$1" > "$2"; fi
}

cmd_schema() {
  _f="${1:-$SCHEMA}"
  [ -r "$_f" ] || unchecked "the schema $_f can't be read"
  need_values
  _out="$(schema_json "$_f" | jq -r --slurpfile vv "$W/values.json" '
    ($vv[0]) as $V
    | ["code", "codes", "int", "float", "bool", "hour", "minute", "day", "rid", "hex6", "hex8", "label"] as $types
    | to_entries[] | .key as $t | .value as $fs
    | ($fs[] | . as $f
        | (if .nf != 7 then "\($t).\(.field): not 7 columns" else empty end),
          (if ($types | index($f.type)) == null then "\($t).\($f.field): type \($f.type) is not in the grammar (no string type exists)" else empty end),
          (if ($f.type == "code" or $f.type == "codes")
             and ([($f.set | split("|"))[] | . as $s | select((($V | has($s)) or $s == "pack") | not)] | length) > 0
           then "\($t).\($f.field): set \($f.set) is not in contracts/bq-values.tsv" else empty end),
          (if ($f.type == "int" or $f.type == "float") and (($f.lo == null) or ($f.hi == null) or $f.lo > $f.hi)
           then "\($t).\($f.field): \($f.type) wants a bounded range a..b" else empty end),
          (if $f.type == "label" and ($t | startswith("dim_") | not) then "\($t).\($f.field): label (a string) only in a dim_ table" else empty end)),
      (($fs | map(.field)) as $n | if ($n | length) != ($n | unique | length) then "\($t): a field listed twice" else empty end),
      (if ($t | startswith("dim_") or startswith("ingest_") or startswith("agg_")) then empty
       else (["schema_v", "source", "person_id", "core", "load_id", "day"] - ($fs | map(.field)))[]
            | "\($t): missing the common field \(.)" end),
      # D4 (legal/dpia.md R3): a row that names a person is a day. Finer times live only in agg_ tables, which name nobody.
      (if ($fs | any(.type == "rid")) and ($fs | any(.type == "hour" or .type == "minute"))
       then "\($t): a time finer than a day beside a person id: per-person rows are day grain (D4)" else empty end),
      (if ($t | startswith("agg_")) and ($fs | any(.type == "rid")) then "\($t): an agg_ table carries no person id" else empty end),
      (if ($t | startswith("agg_")) and ($fs | any(.field == "people") | not) then "\($t): an agg_ table counts its people, for small-cell suppression" else empty end)')" || unchecked "the schema check failed to run"
  if [ -n "$_out" ]; then
    printf '%s\n' "$_out" > "$W/findings"
    refuse "$W/findings" "the schema breaks its grammar" "none automatic — see the header of contracts/bq-schema.tsv"
  fi
  log_ok "$(schema_json "$_f" | jq length) tables, every field typed in the grammar"
  log_end || :
}

cmd_row() { # <table> <file> [--keep F] [--counts F]
  [ $# -ge 2 ] || usage
  _t="$1"; _in="$2"; shift 2; _keep=''; _counts=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --keep) [ $# -ge 2 ] || usage; _keep="$2"; shift ;;
      --counts) [ $# -ge 2 ] || usage; _counts="$2"; shift ;;
      *) usage ;;
    esac; shift
  done
  [ -r "$_in" ] || unchecked "$_in can't be read"
  need_schema; need_values; need_table "$_t"
  rows_of "$_in" "$W/rows.json"
  jq -c --arg t "$_t" --slurpfile s "$W/schema.json" --slurpfile vv "$W/values.json" "$JQ_DEFS"'
    ($vv[0]) as $V | ($s[0][$t]) as $fs
    | to_entries | map({n: (.key + 1), row: .value, f: (if (.value | type) == "object" and (.value | has("\u0000not-json"))
                                                       then [{r: "not-json", f: "-"}] else (.value | judge($fs)) end)})' \
    "$W/rows.json" > "$W/judged.json" || unchecked "the row check failed to run"
  [ -z "$_keep" ] || jq -c '.[] | select(.f == []) | .row' "$W/judged.json" > "$_keep"
  [ -z "$_counts" ] || jq -c '[.[] | select(.f != []) | .f[0].r] | group_by(.) | map({key: .[0], value: length}) | from_entries' "$W/judged.json" > "$_counts"
  _bad="$(jq '[.[] | select(.f != [])] | length' "$W/judged.json")"
  _all="$(jq 'length' "$W/judged.json")"
  if [ "$_bad" -gt 0 ]; then
    jq -r '.[] | select(.f != []) | . as $x | .f[] | "row \($x.n): \(.r) \(.f)"' "$W/judged.json" | head -n 200 > "$W/findings"
    refuse "$W/findings" "$_bad of $_all row(s) refused for $_t" "none automatic — see the table $_t in contracts/bq-schema.tsv"
  fi
  log_ok "$_t: $_all row(s) valid"; log_end || :
}

cmd_code() { # <table> <file>
  [ $# -eq 2 ] || usage
  sh "$0" row "$1" "$2" >/dev/null 2>&1 || { _rc=$?; [ "$_rc" = 1 ] && { log_fail "$2 has rows $1 refuses: nothing was coded"; log_nofix "sh $0 row $1 $2"; log_end || :; exit 1; }; exit "$_rc"; }
  need_schema; need_values
  rows_of "$2" "$W/rows.json"
  jq -c --arg t "$1" --slurpfile s "$W/schema.json" --slurpfile vv "$W/values.json" "$JQ_CODE"'
    ($vv[0]) as $V | ($s[0][$t]) as $fs | .[] | encode($fs)' "$W/rows.json"
}

cmd_bqschema() { # <table>
  [ $# -eq 1 ] || usage
  need_schema; need_table "$1"
  jq --arg t "$1" '.[$t] | map({name: .field,
    type: ({code: "INT64", codes: "INT64", int: "INT64", float: "FLOAT64", bool: "BOOL", hour: "TIMESTAMP", minute: "TIMESTAMP",
            day: "DATE", rid: "BYTES", hex6: "BYTES", hex8: "BYTES", label: "STRING"}[.type]),
    mode: (if .type == "codes" then "REPEATED" elif .nullable then "NULLABLE" else "REQUIRED" end)})' "$W/schema.json"
}

cmd_layout() { # <table>
  [ $# -eq 1 ] || usage
  need_schema; need_table "$1"
  # a dim_ table is never partitioned: partition expiry (D5) would drop what a code means
  jq -r --arg t "$1" '.[$t] | (if ($t | startswith("dim_")) then "" else (map(select((.type == "hour" or .type == "day" or .type == "minute") and (.nullable | not))) | first | .field // "") end) as $p
    | (map(select(.field == "person_id" or .field == "rule")) | map(.field) | .[:1]) as $c
    | "partition=\($p) cluster=\($c | join(","))"' "$W/schema.json"
}

# ── the value sets: one generator, its sources named per row (logging-design §4.2) ──
LIB="$ROOT/bin/library-admission.sh"; VOCAB="$ROOT/contracts/hub-vocabulary.tsv"
src_values() {
  lit() { _ls="$1"; _lsrc="$2"; shift 2; for _lv in "$@"; do printf '%s\t%s\t%s\n' "$_ls" "$_lv" "$_lsrc"; done; }
  vocab() { awk -F'\t' -v s="$1" -v o="$2" '!/^#/ && $1 == s { print o "\t" $2 "\tcontracts/hub-vocabulary.tsv" }' "$VOCAB"; }
  obs() { sed -n "s/^$1='\\(.*\\)'\$/\\1/p" "$LIB" | tr ' ' '\n' | awk -v s="$2" 'NF { print s "\t" $1 "\tbin/library-admission.sh '"$1"'" }'; }
  lit source "logging-design 4.2" member-hub operator-mac
  vocab kind hub_kind; lit hub_kind "logging-design F2: a Mac ledger row" guard
  for _s in tier target outcome mode reason; do vocab "$_s" "$_s"; done
  obs FLOOR_OBS_GUARDS guard; lit guard "floor_log_decision: an unlisted guard" other
  obs FLOOR_OBS_VERDICTS verdict; lit verdict "floor_log_decision: an unlisted verdict" other
  obs FLOOR_OBS_SHAPES shape
  obs FLOOR_OBS_TOOLS tool; lit tool "logging-design 4.2: tools the floor does not name" Read Grep Glob Skill
  obs HARBOR_ADMISSION_CLASSES verb_class; lit verb_class "member activity: a call that is not a shell command" na
  lit confinement "floor_log_decision c (- is na)" na off confined unconfined
  grep -oE '_e=[a-z-]+' "$ROOT/hooks/failure-observe/failure-observe.sh" | sed 's/^_e=//' | awk 'NF { print "error_class\t" $1 "\thooks/failure-observe/failure-observe.sh" }'
  awk -F'\t' '!/^#/ && $1 != "kind" && $1 !~ /</ && NF { print "bus_kind\t" $1 "\tcontracts/event-kinds.tsv" }' "$ROOT/contracts/event-kinds.tsv"
  lit model "usage.jsonl values, read 2026-11-09; synthetic is <synthetic>" claude-fable-5 claude-fable-5-1 claude-haiku-4-5-20251001 \
    claude-haiku-5-5 claude-opus-4-8 claude-opus-5 claude-opus-5-5 claude-sonnet-5 claude-sonnet-5-5 synthetic other
  lit entry "usage.jsonl values, read 2026-11-09" claude-desktop claude-vscode cli sdk-cli other
  lit ingest_reason "bin/bq-format.sh and the loaders" unknown-key missing-key bad-type not-in-set out-of-range ts-not-coarse \
    not-json author-mismatch scrub-hit no-id bad-event excluded
  # check: every literal a member sender records, plus every rule (a passed rule is recorded as its check, member-dispatch.sh)
  grep -ohE 'check=[a-z0-9][a-z0-9-]*' "$ROOT"/bin/*.sh | sed 's/^check=//' | awk 'NF { print "check\t" $1 "\tbin/*.sh check=" }'
  grep -ohE 'check: "[a-z0-9-]+"' "$ROOT/bin/hub-events.sh" | sed 's/^check: "//; s/"$//' | awk 'NF { print "check\t" $1 "\tbin/hub-events.sh" }'
  # rule: every control id; every guard-ledger rule token, a <token>.<shape> literal at its call site (library-admission.sh
  # property 4); the admission.<token> a member guard reports when it has no control (floor_member_report); and hub-hook.
  awk -F'\t' '!/^#/ && $1 != "id" && NF { print "rule\t" $1 "\tstandards/naming/controls.tsv" }' "$ROOT/standards/naming/controls.tsv"
  # the ledger writes a control's token without its family (context.subagent-contract is r=subagent-contract)
  awk -F'\t' '!/^#/ && $1 != "id" && $1 ~ /\./ { t = $1; sub(/^[^.]*\./, "", t); print "rule\t" t "\tstandards/naming/controls.tsv, the id less its family" }' "$ROOT/standards/naming/controls.tsv"
  { grep -ohE '(^|[^a-z0-9.-])[a-z0-9][a-z0-9-]{0,39}\.(argv|flat|path|channel|content|meta)([^a-z0-9.-]|$)' "$ROOT"/bin/*.sh "$ROOT"/hooks/*/*.sh \
      | sed -E 's/^[^a-z0-9]//; s/\.(argv|flat|path|channel|content|meta).*$//'; echo unclassified; } | sort -u \
    | awk 'NF { print "rule\t" $1 "\tbin, hooks: <token>.<shape>"; print "rule\tadmission." $1 "\tfloor_member_report: admission.<token>" }'
  grep -v '^#' "$ROOT/contracts/member-guards.tsv" | cut -f2 | tr ' ' '\n' | sed -n 's/\.sh$//p' \
    | awk 'NF { print "rule\tadmission." $1 "\tmember-dispatch.sh run_guard: admission.<guard>" }'
  lit rule "member-dispatch.sh: a hub hook's verdict" hub-hook
}
# one row per set and value, the first source kept
src_rows() { src_values | awk -F'\t' '$2 ~ /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/ && !seen[$1 FS $2]++'; }

values_merged() { # the file --write would leave: old codes kept, new values appended, vanished values retired
  work; src_rows > "$W/src.tsv"
  if [ -r "$VALUES" ]; then awk -F'\t' '/^#/ || NF == 0 || $1 == "set" { next } { print }' "$VALUES" > "$W/old.tsv"; else : > "$W/old.tsv"; fi
  awk -F'\t' -v OFS='\t' '
    FILENAME == ARGV[1] { code[$1 FS $3] = $2; old[++n] = $1 FS $3; if ($2 + 0 > max) max = $2 + 0; next }
    { src[$1 FS $2] = $3; if (!(($1 FS $2) in code)) { new[++m] = $1 FS $2 } }
    END {
      for (i = 1; i <= n; i++) { k = old[i]; split(k, p, FS); st = (k in src) ? "live" : "retired"
        print p[1], code[k], p[2], st, ((k in src) ? src[k] : "retired: no source names it") }
      for (j = 1; j <= m; j++) { k = new[j]; split(k, p, FS); print p[1], ++max, p[2], "live", src[k] }
    }' "$W/old.tsv" "$W/src.tsv"
}
VALUES_HEAD='# bq-values.tsv (harbor#1278) — the closed value sets of contracts/bq-schema.tsv, each code an INT64 that dim_enum maps back.
#
# WHY THIS FILE EXISTS. A fact table holds codes, never strings, so a value no set names has no way into BigQuery (logging-design 4.2).
# GENERATED by sh bin/bq-format.sh values --write from the source each row names; --check is red when a source and this file differ.
# APPEND-ONLY: a code never changes meaning. A value its source dropped stays, marked retired, so an older laptop still loads; a value
# no commit knows is refused and counted, never coerced, so a newer laptop shows as drift.
#
# COLUMNS  set <TAB> code <TAB> value <TAB> state (live | retired) <TAB> source
set	code	value	state	source'
cmd_values() {
  case "${1:-}" in
    --print) src_rows ;;
    --write)
      work; values_merged > "$W/new.tsv"
      { printf '%s\n' "$VALUES_HEAD"; cat "$W/new.tsv"; } > "$W/out.tsv" && mv "$W/out.tsv" "$VALUES"
      log_ok "$(wc -l < "$W/new.tsv" | tr -d ' ') values written to $VALUES"; log_end || : ;;
    --check)
      [ -r "$VALUES" ] || unchecked "$VALUES can't be read"
      work; values_merged > "$W/new.tsv"
      awk -F'\t' '/^#/ || NF == 0 || $1 == "set" { next } { print }' "$VALUES" > "$W/cur.tsv"
      : > "$W/findings"
      cmp -s "$W/new.tsv" "$W/cur.tsv" || { diff "$W/cur.tsv" "$W/new.tsv" || :; } | grep '^[<>]' | head -n 20 | sed 's/^/drift: /' >> "$W/findings"
      awk -F'\t' '$1 != "" && seen[$2]++ { print "code " $2 " is used twice" }' "$W/cur.tsv" >> "$W/findings"
      # append-only, against the base: a code the base gave a value must still mean that value
      # HARBOR_BQ_VALUES_BASE names a base file directly, for a test
      _base="${HARBOR_CI_BASE:-origin/main}"
      if { [ -n "${HARBOR_BQ_VALUES_BASE:-}" ] && cp "$HARBOR_BQ_VALUES_BASE" "$W/base.tsv"; } \
         || { [ -z "${HARBOR_BQ_VALUES_BASE:-}" ] && git -C "$ROOT" show "$_base:contracts/bq-values.tsv" > "$W/base.tsv" 2>/dev/null; }; then
        awk -F'\t' 'FILENAME == ARGV[1] { if ($0 !~ /^#/ && $1 != "set") c[$1 FS $3] = $2; next }
          /^#/ || $1 == "set" { next } { k = $1 FS $3; if (!(k in c) || c[k] != $2) print "the base gives " $1 " " $3 " code " $2 ": it was renumbered or removed" }' \
          "$W/cur.tsv" "$W/base.tsv" | head -n 20 >> "$W/findings"
      fi
      [ ! -s "$W/findings" ] || refuse "$W/findings" "contracts/bq-values.tsv differs from its sources or its base" "sh bin/bq-format.sh values --write (a renumbered code is restored by hand)"
      log_ok "contracts/bq-values.tsv matches its sources, codes unchanged"; log_end || : ;;
    *) usage ;;
  esac
}

verb="${1:-}"; [ -n "$verb" ] || usage
shift
case "$verb" in
  -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  schema) cmd_schema "$@" ;;
  row) cmd_row "$@" ;;
  code) cmd_code "$@" ;;
  bqschema) cmd_bqschema "$@" ;;
  layout) cmd_layout "$@" ;;
  tables) need_schema; jq -r 'keys[]' "$W/schema.json" ;;
  values) cmd_values "$@" ;;
  *) usage ;;
esac
