#!/usr/bin/env sh
# bin/lint-core-writes.sh and lint.core-writes: core scripts that write into the checkout (harbor#1275).
# Each case is a throwaway git checkout with its own layers.tsv.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
CW() { HARBOR_SCOPE_ROOT="$1" sh "$T_ROOT/bin/lint-core-writes.sh" "$2" 2>&1; }
red() { HARBOR_SCOPE_ROOT="$1" sh "$T_ROOT/bin/lint-core-writes.sh" --check >/dev/null 2>&1; echo $?; }
mk() { # <name> <baseline> → 5 hits: bin/a.sh (out.txt, b.txt, state.tsv, d/), bin/b.sh (>> stray.log); every other shape adds none
  _d="$T_TMP/$1"; mkdir -p "$_d/bin" "$_d/contracts" "$_d/docs" "$_d/tests" "$_d/DEV"
  printf 'path\tlayer\tnote\nbin/\tcore\t\ncontracts/\tcore\t\ndocs/\tcore\t\ntests/\tcore\t\n.gitignore\tcore\t\nDEV/\tdev\t\n' > "$_d/contracts/layers.tsv"
  printf 'path\ttarget\treason\nbin/allowed.sh\t*\tthe operator asked for the file\n' > "$_d/contracts/core-writes-allow.tsv"
  printf '/build/\n' > "$_d/.gitignore"
  cat > "$_d/bin/a.sh" <<'EOF'
ROOT="${HARBOR_SCOPE_ROOT:-${HARBOR_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}}"
echo x > "$ROOT/out.txt"
cp src "$ROOT/b.txt"
OUT="${BASE_X:-$ROOT/state.tsv}"; printf 'r\n' >> "$OUT"
mkdir -p "$ROOT/d"
# echo x > "$ROOT/comment.txt"
echo x > "$ROOT/build/cache"
echo x > /tmp/elsewhere
cat "$ROOT/in" > /tmp/copy
cp "$ROOT/src" /tmp/copy
echo x > "$ROOT/docs/gen.md"
mkdir -p "$ROOT/docs"
sh "$ROOT/bin/x.sh" 2>"$W/err"
mkdir -p "$(dirname "$ROOT/bin/tool")"
EOF
  printf '#!/bin/sh\nROOT=$(cd "$(dirname "$0")/.." && pwd)\necho more >> "$ROOT/stray.log"\n' > "$_d/bin/b.sh"
  printf 'ROOT="$HOME/.config/x"\necho x > "$ROOT/token.json"\n' > "$_d/bin/foreign.sh"
  printf 'ROOT=".."; echo x > "$ROOT/q"\n' > "$_d/bin/allowed.sh"
  printf 'ROOT="$(cd "$(dirname "$0")/.." && pwd)"\necho x > "$ROOT/in-test"\n' > "$_d/tests/t.sh"
  printf 'echo x > "$ROOT/in-doc"\n' > "$_d/docs/d.md"
  printf 'ROOT=$(cd "$(dirname "$0")/.." && pwd)\necho x > "$ROOT/DEV/note"\n' > "$_d/bin/dev.sh"
  printf 'old\n' > "$_d/docs/gen.md"; printf 'x\n' > "$_d/DEV/note"
  cp "$T_ROOT/bin/lint-core-writes.sh" "$T_ROOT/bin/scope-layers.sh" "$T_ROOT/bin/library-log.sh" "$_d/bin/"
  printf '%s\n' "$2" > "$_d/contracts/lint-core-writes-baseline.txt"
  ( cd "$_d" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm x ) >/dev/null 2>&1
  printf '%s' "$_d"
}

t_section "--count counts (core script, in-tree target) pairs"
D="$(mk eq 6)"; L="$(CW "$D" --list)"
t_eq "six pairs: a.sh four, b.sh one, dev.sh one" "6" "$(CW "$D" --count)"
t_has "a redirect to \$ROOT" "$L" "bin/a.sh	out.txt"
t_has "the last argument of cp" "$L" "bin/a.sh	b.txt"
t_has "a variable built from \$ROOT, written through" "$L" "bin/a.sh	state.tsv"
t_has "a mkdir of a directory the tree does not track" "$L" "bin/a.sh	d/"
t_has "an append, in a script found by its shebang" "$L" "bin/b.sh	stray.log"
t_has "a tracked dev-layer target counts: a core clone lacks it" "$L" "bin/dev.sh	DEV/note"
for gone in comment.txt build/cache elsewhere docs/gen.md token.json in-test in-doc 'bin/x.sh' 'bin/tool'; do
  t_hasnt "...not $gone" "$L" "$gone"
done
t_hasnt "an allow-listed script" "$L" "bin/allowed.sh"
t_hasnt "a source is not a target" "$L" "in	"

t_section "--check: red above the baseline, green at it, a nudge below it"
D="$(mk at 6)"; t_eq "equal is green" "0" "$(red "$D")"
D="$(mk over 5)"; OUT="$(CW "$D" --check)"
t_eq "above is red" "1" "$(red "$D")"
t_has "...and says the count and the baseline" "$OUT" "6 core file(s)-and-target pair(s) write into the tree, baseline is 5"
t_has "...and the fix" "$OUT" "state directory"
D="$(mk under 9)"; OUT="$(CW "$D" --check)"
t_eq "below is still green" "0" "$(red "$D")"
t_has "...and asks for a lower baseline" "$OUT" "lower contracts/lint-core-writes-baseline.txt to 6"
D="$(mk nobase x)"; t_eq "a non-numeric baseline is red" "1" "$(red "$D")"
mkdir -p "$T_TMP/nogit"
t_exit "a non-checkout inspected nothing and is not a pass" 2 env HARBOR_SCOPE_ROOT="$T_TMP/nogit" sh "$T_ROOT/bin/lint-core-writes.sh" --check

t_section "growth is red, in a new file that was never added"
D="$(mk grow 6)"; printf 'ROOT=$(cd "$(dirname "$0")/.." && pwd)\ntee "$ROOT/new.out" < /dev/null\n' > "$D/bin/new.sh"
t_eq "an untracked core script that tees into the tree" "1" "$(red "$D")"
D="$(mk ign 6)"; printf 'bin/new.sh\n' >> "$D/.gitignore"; printf 'ROOT=$(cd "$(dirname "$0")/.." && pwd)\ntee "$ROOT/new.out" < /dev/null\n' > "$D/bin/new.sh"
t_eq "an ignored one does not count" "0" "$(red "$D")"
D="$(mk igntarget 6)"; printf '/new.out\n' >> "$D/.gitignore"; printf 'ROOT=$(cd "$(dirname "$0")/.." && pwd)\ntee "$ROOT/new.out" < /dev/null\n' > "$D/bin/new.sh"
t_eq "a gitignored target does not count" "0" "$(red "$D")"

t_section "a register that does not parse refuses the run, never counts as clean"
D="$(mk noreason 6)"; printf 'bin/a.sh\tout.txt\t\n' >> "$D/contracts/core-writes-allow.tsv"
t_eq "an allow row with no reason" "2" "$(red "$D")"
D="$(mk allowrow 6)"; printf 'bin/a.sh\tout.txt\tthe operator asked for it\n' >> "$D/contracts/core-writes-allow.tsv"
t_eq "an allow row with a reason removes its pair" "5" "$(CW "$D" --count)"

t_section "lint.core-writes runs the same check"
D="$(mk lintok 6)"
t_eq "at the baseline the rule is silent" "0" "$(vcount "$(lint1 lint.core-writes "$D")")"
D="$(mk lintbad 5)"
t_has "above the baseline the rule reports" "$(lint1 lint.core-writes "$D")" "VIOLATION [lint.core-writes]"
t_done
