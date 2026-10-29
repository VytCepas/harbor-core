#!/usr/bin/env sh
# bin/lint-layout-map.sh and lint.layout-map: every tracked top-level entry has a row (harbor#1272).
# Each case is a throwaway git checkout with its own map, kinds.tsv and layers.tsv.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
LM() { HARBOR_ROOT="$1" sh "$T_ROOT/bin/lint-layout-map.sh" "$2" 2>&1; }
red() { HARBOR_ROOT="$1" sh "$T_ROOT/bin/lint-layout-map.sh" --check >/dev/null 2>&1; echo $?; }
mk() { # <name> → a checkout with folder bin/, folder docs/, root file README.md and a complete map
  _d="$T_TMP/$1"; mkdir -p "$_d/bin" "$_d/contracts" "$_d/docs" "$_d/standards/naming"
  printf 'id\tfolder\nscript\tbin/\nexplanation\tdocs/\n' > "$_d/standards/naming/kinds.tsv"
  printf 'path\tlayer\tnote\nbin/\tcore\t\ndocs/\tcore\t\ncontracts/\tcore\t\nstandards/\tcore\t\nREADME.md\tcore\t\nOLD.md\tdev\t\n' > "$_d/contracts/layers.tsv"
  printf '# unregistered-kinds: config\nentry\tkind\tlayer\tnote\nbin/\tscript\tsource\tthe tools\ndocs/\texplanation\tsource\tdocs\ncontracts/\tconfig\tsource\tregisters\nstandards/\tconfig\tsource\tkinds\nREADME.md\texplanation\tsource\tstart\n' > "$_d/contracts/layout-map.tsv"
  printf 'x\n' > "$_d/README.md"; printf 'x\n' > "$_d/docs/a.md"
  cp "$T_ROOT/bin/lint-layout-map.sh" "$T_ROOT/bin/scope-layers.sh" "$T_ROOT/bin/library-log.sh" "$_d/bin/"
  ( cd "$_d" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm x ) >/dev/null 2>&1
  printf '%s' "$_d"
}
addrow() { printf '%s\n' "$2" >> "$1/contracts/layout-map.tsv"; }

t_section "a complete map is green"
D="$(mk ok)"; t_eq "every entry has a row" "0" "$(red "$D")"
t_has "...and says how many" "$(LM "$D" --check)" "covers 5 tracked top-level entries"

t_section "a tracked entry with no row is red"
D="$(mk newdir)"; mkdir "$D/newdir"; printf 'x\n' > "$D/newdir/f"; ( cd "$D" && git add -A )
t_eq "a new top-level folder" "1" "$(red "$D")"
t_has "...named" "$(LM "$D" --check)" "newdir/ is tracked and not in the map"
D="$(mk newfile)"; printf 'x\n' > "$D/STRAY.md"; ( cd "$D" && git add -A )
t_eq "a new root file" "1" "$(red "$D")"
D="$(mk untracked)"; printf 'x\n' > "$D/LOOSE.md"
t_eq "an untracked file is not an entry" "0" "$(red "$D")"

t_section "a row naming nothing tracked is red"
D="$(mk stale)"; addrow "$D" "GONE.md	explanation	source	removed"
t_eq "a row for an entry that is not tracked" "1" "$(red "$D")"
t_has "...named" "$(LM "$D" --check)" "the map names GONE.md"
D="$(mk dup)"; addrow "$D" "bin/	script	source	again"
t_eq "two rows for one entry" "1" "$(red "$D")"

t_section "a kind or layer the registers do not have is red"
D="$(mk badkind)"; sed 's/^bin\/	script/bin\/	nonsense/' "$D/contracts/layout-map.tsv" > "$D/m" && mv "$D/m" "$D/contracts/layout-map.tsv"
t_eq "an unknown kind" "1" "$(red "$D")"
D="$(mk badlayer)"; sed 's/^bin\/	script	source/bin\/	script	core/' "$D/contracts/layout-map.tsv" > "$D/m" && mv "$D/m" "$D/contracts/layout-map.tsv"
t_eq "core is the ship class, not a layer" "1" "$(red "$D")"
D="$(mk short)"; addrow "$D" "docs/x	script	source"
t_eq "a row with three fields" "1" "$(red "$D")"

t_section "ship is read from layers.tsv, never stored"
D="$(mk ship)"; t_has "--list adds the ship class" "$(LM "$D" --list)" "bin/	script	source	core"
sed 's/^README.md\tcore/README.md\tdev/' "$D/contracts/layers.tsv" > "$D/l" && mv "$D/l" "$D/contracts/layers.tsv"
t_has "...and follows a change there" "$(LM "$D" --list)" "README.md	explanation	source	dev"

t_section "nothing inspected is not a pass"
mkdir -p "$T_TMP/nogit/contracts" "$T_TMP/nogit/bin"; cp "$T_TMP/ok/contracts/layout-map.tsv" "$T_TMP/nogit/contracts/"
t_exit "a non-checkout" 2 env HARBOR_ROOT="$T_TMP/nogit" sh "$T_ROOT/bin/lint-layout-map.sh" --check
D="$(mk nomap)"; rm "$D/contracts/layout-map.tsv"; t_eq "a missing map" "2" "$(red "$D")"

t_section "lint.layout-map runs the same check"
D="$(mk lintok)"; t_eq "complete: silent" "0" "$(vcount "$(lint1 lint.layout-map "$D")")"
D="$(mk lintbad)"; printf 'x\n' > "$D/STRAY.md"; ( cd "$D" && git add -A )
t_has "an unmapped entry: the rule reports" "$(lint1 lint.layout-map "$D")" "VIOLATION [lint.layout-map]"
t_done
