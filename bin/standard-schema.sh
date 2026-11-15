#!/usr/bin/env sh
# standard-schema.sh (harbor#1425) — the producer validates its own output against the JSON Schema it owns.
#
#   sh bin/standard-schema.sh validate <schema.json> <document.json>   every finding as `<path>: <why>`; exit 1 when any
#   sh bin/standard-schema.sh emit [--root <dir>]                      every row of contracts/seams.tsv whose producer is harbor
#                                                                      and whose schema exists: the schema's `x-fixture` is validated
#   sh bin/standard-schema.sh --help
#
# THE SUBSET. jq is the only tool the floor can count on, so this reads the part of JSON Schema a seam uses: type, enum, const,
# pattern, minimum, minLength, minItems, required, properties, items, additionalProperties:false, anyOf and a local $ref
# (#/$defs/x). A keyword outside that list is ignored, never guessed at: a schema that needs more is validated by its own
# repo's CI with a full validator (yard and fleet do), and says so in its seams.tsv row.
# Exit 0 valid · 1 a finding · 2 usage · 3 unchecked (no jq, no file, not JSON): nothing is claimed green.
set -u
LC_ALL=C; export LC_ALL
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH= cd -- "$HERE" && pwd)"
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh (harbor#1392)
LOG_FD=2
. "$HERE/library-log.sh"
log_init standard-schema

usage() { awk 'NR < 2 { next } /^# THE SUBSET/ || !/^#/ { exit } { sub(/^# ?/, ""); print }' "$HERE/standard-schema.sh"; }
die() { log_fail "$2"; log_fix "$3"; log_end || :; exit "$1"; }

command -v jq >/dev/null 2>&1 || die 3 "jq is not installed, so nothing was validated" "install jq"

# The validator: a stream of `<path>: <why>` lines. $r is the root schema, for $ref.
JQ_VALIDATE='
def tn: if . == null then "null" elif type == "number" then (if . == floor then "integer" else "number" end) else type end;
def isa($t): (tn == $t) or ($t == "number" and tn == "integer");
def ref($r): if type == "object" and has("$ref") then (. as $x | $r | getpath($x["$ref"] | ltrimstr("#/") | split("/"))) else . end;
def check($s; $r; $p):
  . as $d | ($s | ref($r)) as $s
  | if ($s | type) != "object" then empty else
    ( if $s | has("anyOf") then
        (. as $d | if ([$s.anyOf[] | . as $alt | [$d | check($alt; $r; $p)] | length] | min) == 0 then empty else "\($p): matches none of anyOf" end)
      else empty end ),
    ( if $s | has("type") then
        ([$s.type] | flatten) as $ts
        | if any($ts[]; . as $t | $d | isa($t)) then empty else "\($p): is \(tn), the schema wants \($ts | join(" or "))" end
      else empty end ),
    ( if $s | has("enum") then (if . as $v | any($s.enum[]; . == $v) then empty else "\($p): \(tojson) is not one of \($s.enum | tojson)" end) else empty end ),
    ( if $s | has("const") then (if . == $s.const then empty else "\($p): is \(tojson), the schema fixes \($s.const | tojson)" end) else empty end ),
    ( if ($s | has("pattern")) and type == "string" then (if test($s.pattern) then empty else "\($p): \(tojson) does not match \($s.pattern)" end) else empty end ),
    ( if ($s | has("minLength")) and type == "string" then (if length >= $s.minLength then empty else "\($p): is shorter than \($s.minLength)" end) else empty end ),
    ( if ($s | has("minimum")) and (type == "number") then (if . >= $s.minimum then empty else "\($p): \(.) is below \($s.minimum)" end) else empty end ),
    ( if ($s | has("minItems")) and type == "array" then (if length >= $s.minItems then empty else "\($p): has \(length) items, at least \($s.minItems)" end) else empty end ),
    ( if type == "object" then
        ( ($s.required // [])[] as $k | if has($k) then empty else "\($p): lacks the required field \($k)" end ),
        ( ($s.properties // {}) | to_entries[] | . as $e | select($d | has($e.key)) | $d[$e.key] | check($e.value; $r; "\($p).\($e.key)") ),
        ( if $s.additionalProperties == false then (keys[] as $k | select((($s.properties // {}) | has($k)) | not) | "\($p): carries the field \($k), which the schema does not allow") else empty end )
      else empty end ),
    ( if type == "array" and ($s | has("items")) then (to_entries[] | .key as $i | .value | check($s.items; $r; "\($p)[\($i)]")) else empty end )
  end;
'

validate() { # <schema> <doc> → findings on stdout, exit 0/1
  [ -r "$1" ] || die 3 "no such schema: $1" "sh $HERE/standard-schema.sh --help"
  [ -r "$2" ] || die 3 "no such document: $2" "sh $HERE/standard-schema.sh --help"
  jq -e . "$1" >/dev/null 2>&1 || die 3 "$1 is not JSON" "fix the schema"
  jq -e . "$2" >/dev/null 2>&1 || { printf '%s: is not JSON\n' "$2"; return 1; }
  jq -r --slurpfile sch "$1" "$JQ_VALIDATE"'
    $sch[0] as $r | check($r; $r; "$")' "$2" > "$T/found" 2>"$T/err" || die 3 "the validator failed on $2: $(head -n 1 "$T/err")" "sh $HERE/standard-schema.sh --help"
  [ ! -s "$T/found" ] || { cat "$T/found"; return 1; }
  return 0
}

T="$(mktemp -d "${TMPDIR:-/tmp}/standard-schema.XXXXXX")" || exit 3
trap 'rm -rf "$T"' EXIT INT TERM HUP

# The first five findings of $T/out, then the count: one fix line each would bury the one that matters.
report_findings() { # <document>
  head -n 5 "$T/out" > "$T/five"
  while IFS= read -r _l; do log_fail "$1 $_l"; log_fix "fix the producer's output, or the schema if the contract changed (additive within a version)"; done < "$T/five"
  [ "$(wc -l < "$T/out")" -le 5 ] || log_note "$(($(wc -l < "$T/out") - 5)) more finding(s) in $1"
}

ROOT="$(CDPATH= cd -- "$HERE/.." && pwd)"; CMD=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --root) [ $# -ge 2 ] || die 2 "--root takes a directory" "sh $HERE/standard-schema.sh --help"; ROOT="$(CDPATH= cd -- "$2" && pwd)" || die 2 "no such directory: $2" "pass an existing --root"; shift 2 ;;
    validate|emit) CMD="$1"; shift; break ;;
    *) die 2 "unknown argument: $1" "sh $HERE/standard-schema.sh --help" ;;
  esac
done
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || die 2 "--root takes a directory" "sh $HERE/standard-schema.sh --help"; ROOT="$(CDPATH= cd -- "$2" && pwd)" || die 2 "no such directory: $2" "pass an existing --root"; shift 2 ;;
    *) break ;;
  esac
done

case "$CMD" in
  validate)
    [ $# -eq 2 ] || die 2 "validate takes <schema> <document>" "sh $HERE/standard-schema.sh validate contracts/schemas/<name>.schema.json <file>"
    log_head "validate $2"
    if validate "$1" "$2" > "$T/out"; then log_ok "$2 satisfies $1"; log_end || :; exit 0; fi
    report_findings "$2"
    log_end || :; exit 1 ;;
  emit)
    SEAMS="$ROOT/contracts/seams.tsv"
    [ -r "$SEAMS" ] || die 3 "no contracts/seams.tsv under $ROOT, so no producer was judged" "sh $HERE/standard-schema.sh emit --root <a harbor checkout>"
    log_head "emit: every harbor-owned schema against its fixture"
    _n=0; _bad=0
    awk -F'\t' '!/^#/ && $1 != "id" && NF >= 11 && $3 == "harbor" && $7 != "-" { print $7 }' "$SEAMS" | sort -u > "$T/schemas"
    while IFS= read -r _s; do
      [ -r "$ROOT/$_s" ] || { log_fail "$_s: named as a schema in contracts/seams.tsv and not in the tree"; log_fix "add $_s, or fix the schema column of its seams.tsv row"; _bad=$((_bad + 1)); continue; }
      _fx="$(jq -r '.["x-fixture"] // empty' "$ROOT/$_s")"
      [ -n "$_fx" ] || { log_fail "$_s: carries no x-fixture, so the producer validates nothing against it"; log_fix "add an x-fixture keyword naming the file the producer emits to $_s"; _bad=$((_bad + 1)); continue; }
      [ -r "$ROOT/$_fx" ] || { log_fail "$_s: its x-fixture $_fx is not in the tree"; log_fix "restore $_fx or correct x-fixture in $_s"; _bad=$((_bad + 1)); continue; }
      _n=$((_n + 1))
      if validate "$ROOT/$_s" "$ROOT/$_fx" > "$T/out"; then log_ok "$_fx satisfies $_s"
      else _bad=$((_bad + 1)); report_findings "$_fx"; fi
    done < "$T/schemas"
    [ "$_n" -gt 0 ] || [ "$_bad" -gt 0 ] || die 3 "no harbor-owned schema in contracts/seams.tsv, so nothing was validated" "give a seams.tsv row a schema"
    [ "$_bad" -eq 0 ] || { log_end || :; exit 1; }
    log_end || :; exit 0 ;;
  *) usage; exit 2 ;;
esac
