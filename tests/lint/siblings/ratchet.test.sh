#!/usr/bin/env sh
# bin/lint-siblings.sh and lint.sibling-literals: occurrences of another repo's path in the tree (harbor#966).
# Each case is a throwaway git checkout; the baseline is the only thing that differs between green and red.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
SL() { HARBOR_ROOT="$1" sh "$T_ROOT/bin/lint-siblings.sh" "$2" 2>&1; }
mk() { # <name> <baseline> → a checkout with 3 literals in 2 files, harbor's own paths, and excluded dirs
  _d="$T_TMP/$1"; mkdir -p "$_d/bin" "$_d/CONTRACTS/fixtures" "$_d/skills/x" "$_d/tests" "$_d/bin/tests" "$_d/skills/test-strength/targets"
  printf 'A=$HOME/port/zorbcorp\nB=${PORT_ROOT}/blorp\n' > "$_d/bin/a.sh"
  printf '# see ~/port/plumb/x\n' > "$_d/skills/x/SKILL.md"
  printf 'H=$HOME/port/harbor/bin\nP=$PORT_ROOT/harbor-private\nW=$PORT_ROOT/.worktrees/x\nV=$HOME/port/$repo\n' > "$_d/bin/own.sh"
  printf 'T=$HOME/port/zorbcorp\n' | tee "$_d/tests/t.sh" "$_d/CONTRACTS/fixtures/f.txt" "$_d/bin/tests/t.sh" "$_d/skills/test-strength/targets/t.sh" > /dev/null
  cp "$T_ROOT/bin/lint-siblings.sh" "$T_ROOT/bin/log-lib.sh" "$_d/bin/"
  printf '%s\n' "$2" > "$_d/CONTRACTS/lint-siblings-baseline.txt"
  ( cd "$_d" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm x ) >/dev/null 2>&1
  printf '%s' "$_d"
}
red() { HARBOR_ROOT="$1" sh "$T_ROOT/bin/lint-siblings.sh" --check >/dev/null 2>&1; echo $?; }

t_section "--count counts occurrences, in every tracked dir, and leaves harbor's own paths and excluded dirs out"
D="$(mk eq 3)"
t_eq "three literals: two in a.sh, one in skills/" "3" "$(SL "$D" --count)"
t_has "--list names file:line and the literal" "$(SL "$D" --list)" "bin/a.sh:2	\${PORT_ROOT}/blorp"
t_has "skills/ is in scope" "$(SL "$D" --list)" "skills/x/SKILL.md:1"
for gone in own.sh tests/t.sh fixtures bin/tests test-strength; do t_hasnt "...not $gone" "$(SL "$D" --list)" "$gone"; done

t_section "--check: red above the baseline, green at it, a nudge below it"
D="$(mk at 3)"; t_eq "equal is green" "0" "$(red "$D")"
D="$(mk over 2)"; OUT="$(SL "$D" --check)"
t_eq "above is red" "1" "$(red "$D")"
t_has "...and says the count and the baseline" "$OUT" "3 sibling-path literal(s) in the tree, baseline is 2"
t_has "...and the fix" "$OUT" "roots.sh --repo"
D="$(mk under 9)"; OUT="$(SL "$D" --check)"
t_eq "below is still green" "0" "$(red "$D")"
t_has "...and tells you to lower the baseline" "$OUT" "lower CONTRACTS/lint-siblings-baseline.txt to 3"
D="$(mk nobase x)"; t_eq "a non-numeric baseline is red" "1" "$(red "$D")"
mkdir -p "$T_TMP/nogit"
t_exit "a non-checkout inspected nothing and is not a pass" 2 env HARBOR_ROOT="$T_TMP/nogit" sh "$T_ROOT/bin/lint-siblings.sh" --check

t_section "growth the file count missed is red"
D="$(mk grow 3)"
printf 'cd "$HOME/port/blorp"\n' >> "$D/bin/a.sh"
t_eq "a fourth literal in a file already listed" "1" "$(red "$D")"
D="$(mk grow2 3)"
printf 'X=$HOME/port/blorp Y=$HOME/port/plumb\n' > "$D/bin/b.sh"
t_has "two on one line count twice" "$(SL "$D" --count)" "5"

t_section "every spelling is caught, in a new file that was never added"
i=0
while IFS= read -r spell; do
  i=$((i + 1)); D="$(mk sp$i 3)"; printf '%s\n' "$spell" > "$D/bin/new.sh"
  t_eq "red on: $spell" "1" "$(red "$D")"
done <<'SPELLINGS'
x="$HOME"/port/zorbcorp
x="$HOME/port"/zorbcorp
x=${PORT_ROOT:-$HOME/port}/zorbcorp
x=${HOME}/port/zorbcorp
x=$PORT/zorbcorp
x=${PORT}/zorbcorp
x=/Users/someone/port/zorbcorp
x=/home/someone/port/zorbcorp
x=~/port/zorbcorp
x=${PORT_ROOT-$HOME/port}/zorbcorp
x=$HOME/port/"zorbcorp"
x=$(sh bin/roots.sh --port-root)/zorbcorp
SPELLINGS
D="$(mk untracked 3)"; printf 'x=~/port/blorp\n' > "$D/bin/u.sh"
t_eq "an untracked file counts" "4" "$(SL "$D" --count)"
D="$(mk ign 3)"; printf 'u.sh\n' > "$D/.gitignore"; printf 'x=~/port/blorp\n' > "$D/u.sh"
t_eq "an ignored file does not" "3" "$(SL "$D" --count)"

t_section "lint.sibling-literals runs the same check"
D="$(mk lintok 3)"
t_eq "at the baseline the rule is silent" "0" "$(vcount "$(lint1 lint.sibling-literals "$D")")"
D="$(mk lintbad 2)"
t_has "above the baseline the rule reports" "$(lint1 lint.sibling-literals "$D")" "VIOLATION [lint.sibling-literals]"
t_done
