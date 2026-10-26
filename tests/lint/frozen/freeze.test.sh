#!/usr/bin/env sh
# bin/frozen-gen.sh and name.frozen: the names a stranger types are frozen, and a rename needs an alias (harbor#1276).
# Each case is a throwaway root holding copies of the real sources, so the freeze is read as the repo writes it.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
mk() { # <name> → a root with the sources frozen-gen reads, and a frozen.tsv written by --apply
  _d="$T_TMP/$1"; mkdir -p "$_d/bin" "$_d/CONTRACTS" "$_d/standards/naming" "$_d/tests/guards"
  cp "$T_ROOT/bin/frozen-gen.sh" "$T_ROOT/bin/log-lib.sh" "$T_ROOT/bin/roots.sh" "$T_ROOT"/bin/guard-*.sh "$_d/bin/"
  cp "$T_ROOT/CONTRACTS/cli.md" "$T_ROOT/CONTRACTS/pack.md" "$T_ROOT/CONTRACTS/roots.tsv" "$_d/CONTRACTS/"
  cp "$T_ROOT"/tests/guards/*.jsonl "$_d/tests/guards/"
  ( cd "$T_ROOT" && find skills -name SKILL.md -maxdepth 2 ) | while read -r _s; do mkdir -p "$_d/${_s%/*}"; cp "$T_ROOT/$_s" "$_d/$_s"; done
  printf 'id\told\tnew\tsurface\twave\tremove_by\treason\n' > "$_d/standards/naming/renames.tsv"
  HARBOR_ROOT="$_d" sh "$_d/bin/frozen-gen.sh" --apply >/dev/null 2>&1; printf '%s' "$_d"
}
FG() { HARBOR_ROOT="$1" sh "$1/bin/frozen-gen.sh" "$2" 2>&1; }
rc() { HARBOR_ROOT="$1" sh "$1/bin/frozen-gen.sh" "$2" >/dev/null 2>&1; echo $?; }
row() { grep -c "^$2:$3	$2	$3	" "$1/standards/naming/frozen.tsv"; }
share() { awk -F'\t' -v i="$2" '$1 == i { print $5 }' "$1/standards/naming/frozen.tsv"; }

t_section "the freeze is generated, and regenerating restores a deleted row"
R="$(mk gen)"
t_eq "a fresh freeze checks green" "0" "$(rc "$R" --check)"
t_eq "it holds a CLI family" "1" "$(row "$R" cli verify)"
t_eq "...a core harbor.toml key" "1" "$(row "$R" toml packs)"
t_eq "...a pack.toml key" "1" "$(row "$R" pack-toml harbor_version)"
t_eq "...an env root" "1" "$(row "$R" env HARBOR_REPO)"
t_eq "...a core skill" "1" "$(row "$R" skill skill-book)"
t_eq "...a guard rule id from the source" "1" "$(row "$R" rule bash:rm-rf-home)"
t_eq "...a rule id only a guard's table pins (cloud names its rule in a variable)" "1" "$(row "$R" rule cloud:cloud-soft)"
t_eq "...and no field path read as a rule (.tool_input.content)" "0" "$(row "$R" rule egress:input)"
t_eq "the hub seams are reserved, names only (decision 21)" "3" "$(grep -c '^reserved:' "$R/standards/naming/frozen.tsv")"
t_eq "...and their share is hub (#1278)" "hub" "$(share "$R" reserved:cli:hub)"
t_eq "a core name's share is core" "core" "$(share "$R" cli:verify)"
awk -F'\t' -v OFS='\t' '$1 == "cli:verify" { $5 = "hub" } 1' "$R/standards/naming/frozen.tsv" > "$R/f" && mv "$R/f" "$R/standards/naming/frozen.tsv"
t_eq "a hand-edited share is red" "1" "$(rc "$R" --check)"
t_has "...naming the row" "$(FG "$R" --check)" "carry no share or the wrong one: cli:verify"
awk -F'\t' -v OFS='\t' '$1 == "cli:verify" { NF = 4 } 1' "$R/standards/naming/frozen.tsv" > "$R/f" && mv "$R/f" "$R/standards/naming/frozen.tsv"
t_eq "a row with no share is red" "1" "$(rc "$R" --check)"
FG "$R" --apply >/dev/null
t_eq "...and --apply writes it back" "core" "$(share "$R" cli:verify)"
sed '/^cli:verify	/d' "$R/standards/naming/frozen.tsv" > "$R/f" && mv "$R/f" "$R/standards/naming/frozen.tsv"
t_eq "a deleted row is red" "1" "$(rc "$R" --check)"
t_has "...named as not frozen" "$(FG "$R" --check)" "are not frozen: cli:verify"
FG "$R" --apply >/dev/null
t_eq "regenerating restores it" "1" "$(row "$R" cli verify)"
t_eq "...and the check is green again" "0" "$(rc "$R" --check)"

t_section "a frozen name that leaves its source needs a renames.tsv row with an alias"
R="$(mk ren)"
sed 's/^| `harbor verify/| `harbor proof/' "$R/CONTRACTS/cli.md" > "$R/c" && mv "$R/c" "$R/CONTRACTS/cli.md"
FG "$R" --apply >/dev/null
t_eq "a renamed CLI family with no row is red" "1" "$(rc "$R" --check)"
t_has "...naming the old name" "$(FG "$R" --check)" "gone from their source with no alias: cli:verify"
t_eq "...and the frozen row stays: --apply never drops one" "1" "$(row "$R" cli verify)"
printf 'r1\tcli:verify\tcli:proof\tcli\tw1\t-\tno alias date\n' >> "$R/standards/naming/renames.tsv"
t_eq "a row with no remove_by is not an alias" "1" "$(rc "$R" --check)"
sed 's/	-	no alias date$/	2027-01-31	harbor proof reads verify until then/' "$R/standards/naming/renames.tsv" > "$R/r" && mv "$R/r" "$R/standards/naming/renames.tsv"
t_eq "with old, new and remove_by it is green" "0" "$(rc "$R" --check)"
printf 'r2\tHARBOR_REPO\tHARBOR_HOME\tenv\tw1\t2027-01-31\tbare old name\n' >> "$R/standards/naming/renames.tsv"
grep -v '^HARBOR_REPO	' "$R/CONTRACTS/roots.tsv" > "$R/x" && mv "$R/x" "$R/CONTRACTS/roots.tsv"
t_eq "a bare old name matches too" "0" "$(rc "$R" --check)"

t_section "a missing source refuses rather than reading every name as gone"
R="$(mk miss)"; rm "$R/CONTRACTS/cli.md"
t_eq "exit 2" "2" "$(rc "$R" --check)"
t_has "...naming the source" "$(FG "$R" --check)" "no CONTRACTS/cli.md"
t_eq "...and --apply writes nothing" "2" "$(rc "$R" --apply)"

t_section "lint.frozen-names runs the same check"
R="$(mk lintok)"; t_eq "a fresh freeze: silent" "0" "$(vcount "$(lint1 lint.frozen-names "$R")")"
sed '/^skill:atlas	/d' "$R/standards/naming/frozen.tsv" > "$R/f" && mv "$R/f" "$R/standards/naming/frozen.tsv"
t_has "an unfrozen name: the rule reports" "$(lint1 lint.frozen-names "$R")" "VIOLATION [lint.frozen-names]"

t_section "the repo's own freeze"
t_eq "the tree checks green" "0" "$(HARBOR_ROOT="$T_ROOT" sh "$T_ROOT/bin/frozen-gen.sh" --check >/dev/null 2>&1; echo $?)"
t_eq "none of the four moved-out names is frozen (wifi, clickup, dev-tracking, office-context)" "0" \
  "$(grep -cE '	(wifi|clickup|dev-tracking|office-context)	' "$T_ROOT/standards/naming/frozen.tsv")"
t_done
