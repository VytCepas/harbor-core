#!/usr/bin/env sh
# standard-frozen-generate.sh (harbor#1276, #949) - the names a stranger types or reads, frozen in standards/naming/frozen.tsv.
#
#   sh standard-frozen-generate.sh --list    every name the sources hold now: kind TAB name, sorted
#   sh standard-frozen-generate.sh --apply   add each name not yet frozen, dated today; a frozen row is never dropped or redated
#   sh standard-frozen-generate.sh --check   red on a name not yet frozen, and on a frozen name gone from its source with no
#                              renames.tsv row (old = the name or <kind>:<name>, remove_by set) carrying its alias
#
# The sources: CLI families (contracts/cli.md), core harbor.toml keys (scope-roots.sh --conf-keys), pack.toml keys
# (contracts/pack.md), env roots (contracts/roots.tsv), core skills (skills/*/SKILL.md), guard rule ids
# (<id>.<shape> in bin/guard-*.sh, as floor-equiv.sh reads them, plus the ids tests/guards/*.jsonl pins). The hub seams are reserved, names only (decision 21).
# Append-only on purpose: a regenerated file that dropped a vanished name would make every rename look clean.
set -eu
case "${1:-}" in -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac

case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
ROOT="${HARBOR_SCOPE_ROOT:-${HARBOR_ROOT:-$(CDPATH= cd -- "$SRC/.." && pwd)}}"
FROZEN="${FROZEN_FILE:-$ROOT/standards/naming/frozen.tsv}"
RENAMES="${RENAMES_FILE:-$ROOT/standards/naming/renames.tsv}"
. "$SRC/library-log.sh"
log_init frozen-gen
LOG_FD=2
T="$(mktemp -d "${TMPDIR:-/tmp}/harbor.XXXXXX")"; trap 'rm -rf "$T"' EXIT INT TERM

# Each source is required: a missing one would read as "every name it held vanished".
need() { [ -f "$ROOT/$1" ] || { log_fail "no $1, so its names cannot be read"; log_nofix "the header of bin/standard-frozen-generate.sh"; log_end || :; exit 2; }; }

names() {
  need contracts/cli.md; need contracts/pack.md; need contracts/roots.tsv; need bin/scope-roots.sh
  grep -o '^| `harbor [a-z][a-z-]*' "$ROOT/contracts/cli.md" | sed 's/^| `harbor /cli	/'
  HARBOR_SCOPE_ROOT="$ROOT" sh "$ROOT/bin/scope-roots.sh" --conf-keys | sed 's/^/toml	/'
  sed -n 's/^pack\.toml[[:space:]][[:space:]]*\([a-z_, ]*\) - .*/\1/p' "$ROOT/contracts/pack.md" | tr ',' '\n' | tr -d ' ' | grep -v '^$' | sed 's/^/pack-toml	/'
  grep -vE '^[[:space:]]*(#|$)' "$ROOT/contracts/roots.tsv" | sed 1d | cut -f1 | sed 's/^/env	/'
  for _d in "$ROOT"/skills/*/; do [ -f "$_d/SKILL.md" ] && { _s="${_d%/}"; printf 'skill\t%s\n' "${_s##*/}"; }; done
  for _g in "$ROOT"/bin/guard-*.sh; do
    _n="${_g##*/guard-}"; _n="${_n%.sh}"; [ "$_n" != lib ] || continue
    # a field path (.tool_input.content, .message.content) is not a rule: the id starts the word
    grep -vE '^[[:space:]]*#|floor_log_decision' "$_g" | grep -oE '(^|[^._A-Za-z0-9])[a-z0-9-]+\.(flat|argv|meta|content|path|channel)([^a-z]|$)' |
      sed -E 's/^[^a-z0-9]//; s/\.(flat|argv|meta|content|path|channel)([^a-z]|$).*//' | sed "s/^/rule	$_n:/"
  done
  # the ids each guard's table pins, which also covers guards that name a rule in a variable (cloud, destroy, deliverables)
  # harbor#961 W2: a moved table sits in tests/admission/<guard>/, so its guard is the directory, not the file name
  for _j in "$ROOT"/tests/guards/*.jsonl "$ROOT"/tests/admission/*/*.jsonl; do
    [ -f "$_j" ] || continue
    case "$_j" in "$ROOT"/tests/admission/*) _n="${_j%/*}"; _n="${_n##*/}" ;; *) _n="${_j##*/}"; _n="${_n%%.*}" ;; esac
    jq -r '.rule // empty' "$_j" 2>/dev/null | grep -vx none | sed "s/^/rule	$_n:/" || :
  done
  printf 'reserved\tcli:hub\nreserved\ttoml:[hub]\nreserved\tpath:hub/\n'
}
frozen() { [ -f "$FROZEN" ] && grep -vE '^[[:space:]]*(#|$)' "$FROZEN" | sed 1d || :; }   # id kind name since share
# The share a frozen name belongs to (#1278): core ships every source above, and only the hub seams are the hub's.
# workload and personal are the other two values; no core source holds one.
share() { awk -F'\t' -v OFS='\t' '{ print $1, $2, $3, $4, ($2 == "reserved" ? "hub" : "core") }'; }

names | LC_ALL=C sort -u > "$T/now"
[ -s "$T/now" ] || { log_fail "no name was read from any source"; log_nofix "the header of bin/standard-frozen-generate.sh"; log_end || :; exit 2; }
frozen | cut -f2,3 | LC_ALL=C sort -u > "$T/was"
LC_ALL=C comm -23 "$T/now" "$T/was" > "$T/new"

case "${1:-}" in
  --list) cat "$T/now"; exit 0 ;;
  --apply)
    _d="$(date +%Y-%m-%d)"
    { printf '# frozen.tsv (harbor#1276) - the names a stranger types or reads. Written by bin/standard-frozen-generate.sh --apply, never by hand.\n'
      printf '#\n# WHY THIS FILE EXISTS. A name a stranger types is an interface: renaming it breaks their scripts and habits.\n'
      printf '# A row is added when its name first appears and never dropped; renaming one needs a renames.tsv row with its alias.\n'
      printf '# Columns: id (<kind>:<name>), kind, name, since (the date it was first frozen), share (core, hub, workload\n'
      printf '# or personal: whose surface it is).\n#\n# standard_version: 2.0.0\n#\n'
      printf 'id\tkind\tname\tsince\tshare\n'
      { frozen; awk -F'\t' -v d="$_d" '{ print $1 ":" $2 "\t" $1 "\t" $2 "\t" d }' "$T/new"; } | share | LC_ALL=C sort -t "$(printf '\t')" -k1,1; } > "$T/out"
    cat "$T/out" > "$FROZEN"
    log_ok "$(wc -l < "$T/new" | tr -d ' ') name(s) frozen, $(wc -l < "$T/was" | tr -d ' ') already were"
    log_end; exit $? ;;
  --check) ;;
  *) echo "usage: standard-frozen-generate.sh --list | --apply | --check" >&2; exit 2 ;;
esac

[ -f "$FROZEN" ] || { log_fail "no ${FROZEN#$ROOT/}"; log_fix "sh bin/standard-frozen-generate.sh --apply"; log_end || :; exit 1; }
if [ -s "$T/new" ]; then
  log_fail "$(wc -l < "$T/new" | tr -d ' ') name(s) a stranger can type are not frozen: $(head -5 "$T/new" | tr '\t' ':' | tr '\n' ' ')"
  log_fix "sh bin/standard-frozen-generate.sh --apply"
fi
# a renamed name: renames.tsv old is the bare name or <kind>:<name>, with a remove_by date for its alias
{ [ -f "$RENAMES" ] && grep -vE '^[[:space:]]*(#|$)' "$RENAMES" | sed 1d | awk -F'\t' '$6 != "" && $6 != "-" { print $2 }' || :; } > "$T/renamed"
LC_ALL=C comm -13 "$T/now" "$T/was" | grep -v '^reserved	' | awk -F'\t' -v rf="$T/renamed" '
  BEGIN { while ((getline r < rf) > 0) R[r] = 1 }
  !(($2 in R) || (($1 ":" $2) in R)) { print $1 ":" $2 }' > "$T/gone" || :
if [ -s "$T/gone" ]; then
  log_fail "$(wc -l < "$T/gone" | tr -d ' ') frozen name(s) are gone from their source with no alias: $(head -5 "$T/gone" | tr '\n' ' ')"
  log_fix "restore the name, or add a standards/naming/renames.tsv row (old = <kind>:<name>, new, remove_by) and keep the old name working until then"
fi
frozen | cut -f1-5 > "$T/rows"; share < "$T/rows" | cut -f1-5 > "$T/want"
LC_ALL=C comm -23 "$T/rows" "$T/want" | cut -f1 > "$T/badshare" || :
if [ -s "$T/badshare" ]; then
  log_fail "$(wc -l < "$T/badshare" | tr -d ' ') frozen row(s) carry no share or the wrong one: $(head -5 "$T/badshare" | tr '\n' ' ')"
  log_fix "sh bin/standard-frozen-generate.sh --apply"
fi
[ -s "$T/new" ] || [ -s "$T/gone" ] || [ -s "$T/badshare" ] || log_ok "$(wc -l < "$T/was" | tr -d ' ') frozen name(s), each still in its source or renamed with an alias"
log_end
