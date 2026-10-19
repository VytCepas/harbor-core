#!/usr/bin/env sh
# bin/lint-dev-paths.sh and lint.dev-paths: core code that names a dev-layer path (harbor#1275).
# Each case is a throwaway git checkout with its own layers.tsv; the dev paths are made up.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
DP() { HARBOR_ROOT="$1" sh "$T_ROOT/bin/lint-dev-paths.sh" "$2" 2>&1; }
red() { HARBOR_ROOT="$1" sh "$T_ROOT/bin/lint-dev-paths.sh" --check >/dev/null 2>&1; echo $?; }
mk() { # <name> <baseline> → 3 pairs: bin/a.sh (NOTES.md, DATA/), bin/b.py (NOTES.md); comments, docs, data, dev and allowed add none
  _d="$T_TMP/$1"; mkdir -p "$_d/bin" "$_d/CONTRACTS" "$_d/docs" "$_d/DATA" "$_d/tests/ok"
  printf 'path\tlayer\tnote\nbin/\tcore\t\nCONTRACTS/\tcore\t\ndocs/\tcore\t\ntests/\tcore\t\nDATA/\tdev\t\nNOTES.md\tdev\t\n.gitignore\tcore\t\n' > "$_d/CONTRACTS/layers.tsv"
  printf 'path\tdev\treason\ntests/ok/\t*\tasserts absence in the fixture\n' > "$_d/CONTRACTS/dev-paths-allow.tsv"
  printf 'cat "$ROOT/NOTES.md"\nls $ROOT/DATA/x\n  # a comment naming NOTES.md\n' > "$_d/bin/a.sh"
  printf 'open("NOTES.md")\n// DATA/ in a slash comment\n' > "$_d/bin/b.py"
  printf 'see QA-NOTES.md and MYDATA/ and NOTES.mdx\n' > "$_d/bin/near.sh"
  printf 'the dev layer keeps `NOTES.md`\n' > "$_d/docs/d.md"
  printf 'row\tNOTES.md\n' > "$_d/CONTRACTS/reg.tsv"
  printf 'cat NOTES.md\n' > "$_d/DATA/inside.sh"
  printf 'cat NOTES.md\n' > "$_d/tests/ok/t.sh"
  printf 'x\n' > "$_d/NOTES.md"
  cp "$T_ROOT/bin/lint-dev-paths.sh" "$T_ROOT/bin/layers.sh" "$T_ROOT/bin/log-lib.sh" "$_d/bin/"
  printf '%s\n' "$2" > "$_d/CONTRACTS/lint-dev-paths-baseline.txt"
  ( cd "$_d" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm x ) >/dev/null 2>&1
  printf '%s' "$_d"
}

t_section "--count counts (core code file, dev path) pairs on non-comment lines"
D="$(mk eq 3)"
t_eq "three pairs: a.sh twice, b.py once" "3" "$(DP "$D" --count)"
t_has "--list names file and dev path" "$(DP "$D" --list)" "bin/a.sh	DATA/"
t_has "...a non-shell file too" "$(DP "$D" --list)" "bin/b.py	NOTES.md"
t_hasnt "a // comment is not a read" "$(DP "$D" --list)" "bin/b.py	DATA/"
for gone in bin/near.sh docs/d.md CONTRACTS/reg.tsv DATA/inside.sh tests/ok/t.sh bin/lint-dev-paths.sh; do
  t_hasnt "...not $gone" "$(DP "$D" --list)" "$gone"
done
t_eq "the dev paths come from layers.tsv: a new dev row is looked for" "4" "$(printf 'docs/x.sh\tdev\t\n' >> "$D/CONTRACTS/layers.tsv"; printf 'sh docs/x.sh\n' >> "$D/bin/b.py"; DP "$D" --count)"

t_section "--check: red above the baseline, green at it, a nudge below it"
D="$(mk at 3)"; t_eq "equal is green" "0" "$(red "$D")"
D="$(mk over 2)"; OUT="$(DP "$D" --check)"
t_eq "above is red" "1" "$(red "$D")"
t_has "...and says the count and the baseline" "$OUT" "3 core file(s)-and-dev-path pair(s), baseline is 2"
t_has "...and the fix" "$OUT" "missing-is-fine"
D="$(mk under 9)"; OUT="$(DP "$D" --check)"
t_eq "below is still green" "0" "$(red "$D")"
t_has "...and asks for a lower baseline" "$OUT" "lower CONTRACTS/lint-dev-paths-baseline.txt to 3"
D="$(mk nobase x)"; t_eq "a non-numeric baseline is red" "1" "$(red "$D")"
mkdir -p "$T_TMP/nogit"
t_exit "a non-checkout inspected nothing and is not a pass" 2 env HARBOR_ROOT="$T_TMP/nogit" sh "$T_ROOT/bin/lint-dev-paths.sh" --check

t_section "growth is red, in a new file that was never added"
D="$(mk grow 3)"; printf 'cp x "$ROOT/DATA/y"\n' > "$D/bin/new.sh"
t_eq "an untracked core file that writes into the dev path" "1" "$(red "$D")"
D="$(mk ign 3)"; printf 'bin/new.sh\n' > "$D/.gitignore"; printf 'cat NOTES.md\n' > "$D/bin/new.sh"
t_eq "an ignored one does not count" "0" "$(red "$D")"

t_section "a register that does not parse refuses the run, never counts as clean"
D="$(mk noreason 3)"; printf 'bin/a.sh\tNOTES.md\t\n' >> "$D/CONTRACTS/dev-paths-allow.tsv"
t_eq "an allow row with no reason" "2" "$(red "$D")"
D="$(mk nodev 3)"; printf 'bin/a.sh\tOTHER.md\tbecause\n' >> "$D/CONTRACTS/dev-paths-allow.tsv"
t_eq "an allow row naming no dev row" "2" "$(red "$D")"
D="$(mk norows 3)"; printf 'path\tlayer\tnote\nbin/\tcore\t\n' > "$D/CONTRACTS/layers.tsv"
t_eq "a layers.tsv with no dev row" "2" "$(red "$D")"

t_section "lint.dev-paths runs the same check"
D="$(mk lintok 3)"
t_eq "at the baseline the rule is silent" "0" "$(vcount "$(lint1 lint.dev-paths "$D")")"
D="$(mk lintbad 2)"
t_has "above the baseline the rule reports" "$(lint1 lint.dev-paths "$D")" "VIOLATION [lint.dev-paths]"
t_done
