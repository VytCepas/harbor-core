#!/usr/bin/env sh
# gate-register-derive.sh (harbor#1018, review finding 3) — the rows of harbor's protected-paths register that are
# DERIVED, never kept by hand: every file an installer ships into the config dir, every script an installer wires
# as a hook or statusline, every shim target CONTRACTS/shims.tsv links into ~/.local/bin, every file a ship.conf
# command runs, what decides the required checks' content, and everything those and the gate tools source or call,
# followed to a fixpoint.
#
#   sh bin/gate-register-derive.sh --print    the derived rows on stdout
#   sh bin/gate-register-derive.sh --check [<register>]   exit 1 when the register's derived block differs
#   sh bin/gate-register-derive.sh --write    rewrite that block between its BEGIN and END lines
#
# Payloads come from the installers' own lists (FILES, GUARDS, RECOVERY, EVENTS, GATES, SUITE, DATA, REFRESH_ONLY in
# bin/*-install.sh); a call is a non-comment line naming another bin/ file after a `/`. Over-reaching is the safe side.
set -eu
# sort order follows the locale: pinned, so the block a Mac writes is the block a Linux runner checks (harbor#1149)
LC_ALL=C; export LC_ALL
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH='' cd -- "$HERE" && pwd)"; ROOT="$(CDPATH='' cd -- "$HERE/.." && pwd)"
LOG_FD=2
. "$HERE/log-lib.sh"
log_init gate-register-derive
REG="${2:-$ROOT/.agents/protected-paths.tsv}"
CONF="$ROOT/.agents/ship.conf"
BEGIN='# BEGIN derived: bin/gate-register-derive.sh --write writes the rows to END; classify.test.sh fails when they are stale'
END='# END derived'
case "${1:-}" in
  --print|--check|--write) MODE="${1#--}" ;;
  -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) log_fail "a mode is required"; log_fix "sh $0 --check"; log_end || :; exit 2 ;;
esac
T="$(mktemp -d "${TMPDIR:-/tmp}/derive.XXXXXX")"; trap 'rm -rf "$T"' EXIT
TAB="$(printf '\t')"
ls "$ROOT/bin" > "$T/names"
calls() { # <file> → the bin/ files its code lines name after a `/`
  sed -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]#.*$//' "$1" | grep -oE '/[A-Za-z0-9_][A-Za-z0-9_.-]*\.(sh|awk|py|tsv|jq|mjs)' \
    | sed 's|^/||' | sort -u | while IFS= read -r _n; do grep -qxF "$_n" "$T/names" || continue; printf 'bin/%s\n' "$_n"; done
}
conf() { awk -v k="$1" '{ sub(/(^|[ \t])#.*/, "") } $1 == k { $1 = ""; sub(/^[ \t]+/, ""); print }' "$CONF" 2>/dev/null || :; }

# Rows are path <TAB> reason <TAB> class; a path a call reaches takes its caller's class.
# 1 · payloads, from the installers' own lists: a bare name is bin/<name>; src:dst pairs give src
for _i in "$ROOT"/bin/*-install.sh; do
  sed -n -E "s/^(FILES|GUARDS|RECOVERY|EVENTS|GATES|SUITE|DATA|REFRESH_ONLY)=[\"']([^\"']*)[\"'].*/\\2/p" "$_i" | tr ' ' '\n' \
    | awk -v i="${_i##*/}" 'NF { p = $0; sub(/:.*/, "", p); if (p !~ /\//) p = "bin/" p; print p "\tshipped by " i "\tinstalled" }'
done > "$T/seed"
# 2 · hook and statusline commands an installer wires: $DIR/bin/<x>, and floor-install's wiring table
for _i in "$ROOT"/bin/*-install.sh; do
  grep -ohE '\$DIR/bin/[A-Za-z0-9_.-]+' "$_i" | sed "s|^\\\$DIR/|| ; s|\$|	wired by ${_i##*/}	installed|"
done >> "$T/seed"
awk '/^floor_hooks\(\)/ { f = 1; next } f && /^ROWS$/ { exit } f && !/^#/ && /;/' "$ROOT/bin/floor-install.sh" | cut -d';' -f3 \
  | tr ' ' '\n' | awk 'NF && !/^-/ { print "bin/" $0 "\twired by floor-install.sh\tinstalled" }' >> "$T/seed"
# the gate tools themselves: what their calls reach must be protected too
for _g in "$ROOT"/bin/gate-*.sh; do printf 'bin/%s\tthe approval gate\tinstalled\n' "${_g##*/}"; done >> "$T/seed"
# 3 · what the box runs from this repo OUTSIDE a session, as the operator (review finding 1): every shim whose root
#     (CONTRACTS/roots.tsv) is this repo or under it, and both registers, which decide what ~/.local/bin points at
_me="$(conf repo | head -1)"; _me="${_me##*/}"
awk -F'\t' -v me="${_me:-harbor}" 'NR == FNR { if ($1 !~ /^#/ && NF >= 3) rel[$1] = $3; next }
  $1 ~ /^#/ || $1 == "name" || NF < 3 { next }
  { r = rel[$2]; if (r == me) p = $3; else if (index(r, me "/") == 1) p = substr(r, length(me) + 2) "/" $3; else next
    print p "\tlinked into ~/.local/bin as " $1 " by CONTRACTS/shims.tsv\toperator-run" }' \
  "$ROOT/CONTRACTS/roots.tsv" "$ROOT/CONTRACTS/shims.tsv" >> "$T/seed"
printf 'CONTRACTS/%s\tdecides what ~/.local/bin points at\toperator-run\n' shims.tsv roots.tsv >> "$T/seed"
# 4 · every file a ship.conf command runs: plan, apply, verify, restore, deployed run unattended (review finding 2)
for _k in plan apply verify restore deployed; do
  conf "$_k" | tr ' \t' '\n\n' | tr -d "\"'" | awk -v k="$_k" '/\// && !/^[\/$-]/ && !/\.\./ { print $0 "\truns as ship.conf " k "\tship" }'
done >> "$T/seed"
# 5 · what decides the required checks' content (review finding 4): the suite manifests, the stand-down map, the local
#     required list, the push-run skip, the runner images and the test library, and what every workflow calls, not only
#     the one ship.conf judges: the public mirror runs governance.yml inside public-ci (harbor#1149). Individual test
#     files stay open: protecting tests/** would put nearly every PR behind the click.
for _f in "$ROOT"/CONTRACTS/suites*.txt CONTRACTS/suite-paths.txt CONTRACTS/required-checks.tsv bin/ci-verified.sh; do
  printf '%s\tdecides what a required check runs\tci-gate\n' "${_f#"$ROOT"/}"
done >> "$T/seed"
for _wp in "$ROOT"/.github/workflows/*.yml; do
  [ -f "$_wp" ] || continue; _wf="${_wp##*/}"
  calls "$_wp" | sed "s|\$|	called by .github/workflows/$_wf	ci-gate|" >> "$T/seed"
done
awk -F'\t' -v r="$ROOT" '{ f = r "/" $1; if ((getline _ < f) >= 0) { close(f); print } }' "$T/seed" | sort -t "$TAB" -k1,1 -u > "$T/set"
for _d in runners tests/lib; do
  [ ! -d "$ROOT/$_d" ] || printf '%s/**\tdecides what a required check runs\tci-gate\n' "$_d" >> "$T/set"
done
sort -t "$TAB" -k1,1 -u "$T/set" > "$T/set2"; mv "$T/set2" "$T/set"

# 6 · calls and sources, to a fixpoint: a code line of a protected script naming /<file> where bin/<file> exists
while :; do
  cut -f1 "$T/set" > "$T/have"
  : > "$T/new"
  while IFS="$TAB" read -r _p _r _c; do
    case "$_p" in
      */\*\*) find "$ROOT/${_p%/\*\*}" -type f | sed "s|^$ROOT/||" ;;
      *) printf '%s\n' "$_p" ;;
    esac | while IFS= read -r _f; do
      [ -f "$ROOT/$_f" ] || continue
      case "$_f" in bin/*|*.sh|*.awk|*.py|*.jq|*.mjs) ;; *) head -c2 "$ROOT/$_f" | grep -q '^#!' || continue ;; esac
      calls "$ROOT/$_f" | while IFS= read -r _n; do
        grep -qxF "$_n" "$T/have" || printf '%s\tcalled by %s\t%s\n' "$_n" "$_f" "$_c"
      done
    done
  done < "$T/set" >> "$T/new"
  [ -s "$T/new" ] || break
  sort -t "$TAB" -k1,1 -u "$T/set" "$T/new" > "$T/set2"; mv "$T/set2" "$T/set"
done
awk -F'\t' '{ printf "%s\t%s\tderived: %s\n", $1, $3, $2 }' "$T/set" > "$T/rows"
case "$MODE" in
  print) cat "$T/rows"; exit 0 ;;
esac
grep -qxF "$BEGIN" "$REG" && grep -qxF "$END" "$REG" || { log_fail "$REG has no derived block"; log_fix "sh $0 --write"; log_end || :; exit 1; }
awk -v b="$BEGIN" -v e="$END" '$0 == b { f = 1; next } $0 == e { f = 0 } f' "$REG" > "$T/have.rows"
if [ "$MODE" = check ]; then
  if cmp -s "$T/rows" "$T/have.rows"; then log_ok "the derived block of $REG is current ($(grep -c . "$T/rows") rows)"; log_end; exit $?; fi
  diff "$T/have.rows" "$T/rows" | sed -n 's/^[<>] //p' | head -10 | while IFS= read -r _l; do log_note "differs: $_l"; done
  log_fail "the derived block of $REG is stale"; log_fix "sh $0 --write"; log_end || :; exit 1
fi
awk -v b="$BEGIN" -v e="$END" -v rows="$T/rows" '$0 == b { print; while ((getline l < rows) > 0) print l; f = 1; next } $0 == e { f = 0 } !f' "$REG" > "$T/reg"
cp "$T/reg" "$REG"
log_ok "wrote $(grep -c . "$T/rows") derived rows into $REG"
log_end
