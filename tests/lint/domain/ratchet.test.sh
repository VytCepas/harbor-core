#!/usr/bin/env sh
# bin/lint-domain.sh and lint.domain: core files that name a workload tool (harbor#1274).
# Each case is a throwaway git checkout with its own registers; the terms are made up, so this file names no real tool.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
DM() { HARBOR_ROOT="$1" sh "$T_ROOT/bin/lint-domain.sh" "$2" 2>&1; }
red() { HARBOR_ROOT="$1" sh "$T_ROOT/bin/lint-domain.sh" "${2:---check}" >/dev/null 2>&1; echo $?; }
mk() { # <name> <baseline> → 3 pairs: bin/a.sh (acme, ledgr), docs/d.md (acme); dev, allowed and near-miss files add none
  _d="$T_TMP/$1"; mkdir -p "$_d/bin" "$_d/CONTRACTS" "$_d/docs/ok" "$_d/notes"
  printf 'path\tlayer\tnote\nbin/\tcore\t\nCONTRACTS/\tcore\t\ndocs/\tcore\t\nnotes/\tdev\t\n.gitignore\tcore\t\n' > "$_d/CONTRACTS/layers.tsv"
  printf '# terms\nid\tpattern\tnote\nacme\tacmetool\ta made-up tool\nledgr\tfoo ledger\ta made-up two-word tool\n' > "$_d/CONTRACTS/domain-terms.tsv"
  printf 'path\tterm\treason\ndocs/ok/\t*\tharbor logic in the fixture\ndocs/one.md\tledgr\tonly this term is allowed here\n' > "$_d/CONTRACTS/domain-allow.tsv"
  printf 'x=acmetool; y=ACMETOOL\n# foo ledger\n' > "$_d/bin/a.sh"
  printf 'uses Acmetool\n' > "$_d/docs/d.md"
  printf 'acmetool\n' > "$_d/notes/n.md"
  printf 'acmetool and foo ledger\n' > "$_d/docs/ok/x.md"
  printf 'foo ledger\n' > "$_d/docs/one.md"
  printf 'acmetoolkit, xacmetool, foo-ledgers\n' > "$_d/docs/near.md"
  cp "$T_ROOT/bin/lint-domain.sh" "$T_ROOT/bin/layers.sh" "$T_ROOT/bin/log-lib.sh" "$_d/bin/"
  printf '%s\n' "$2" > "$_d/CONTRACTS/lint-domain-baseline.txt"
  ( cd "$_d" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm x ) >/dev/null 2>&1
  printf '%s' "$_d"
}

t_section "--count counts (core file, term) pairs, case-insensitive whole words, core only"
D="$(mk eq 3)"
t_eq "three pairs: a.sh twice (two terms, one counted once each), d.md once" "3" "$(DM "$D" --count)"
t_has "--list names file and term id" "$(DM "$D" --list)" "bin/a.sh	ledgr"
t_has "...in any case" "$(DM "$D" --list)" "docs/d.md	acme"
for gone in notes/n.md docs/ok/x.md docs/near.md CONTRACTS/domain-terms.tsv CONTRACTS/domain-allow.tsv; do
  t_hasnt "...not $gone" "$(DM "$D" --list)" "$gone"
done
t_hasnt "an allow row for one term spares only that term" "$(DM "$D" --list)" "docs/one.md"
printf 'acmetool\n' >> "$D/docs/one.md"
t_has "...and the other term in the same file still counts" "$(DM "$D" --list)" "docs/one.md	acme"

t_section "--check: red above the baseline, green at it, a nudge below it"
D="$(mk at 3)"; t_eq "equal is green" "0" "$(red "$D")"
D="$(mk over 2)"; OUT="$(DM "$D" --check)"
t_eq "above is red" "1" "$(red "$D")"
t_has "...and says the count and the limit" "$OUT" "3 core file(s)-and-term pair(s) name a workload tool, the limit is 2"
t_has "...and the fix" "$OUT" "harbor#1273"
D="$(mk under 9)"; OUT="$(DM "$D" --check)"
t_eq "below is still green" "0" "$(red "$D")"
t_has "...and asks for a lower baseline" "$OUT" "lower CONTRACTS/lint-domain-baseline.txt to 3"
D="$(mk nobase x)"; t_eq "a non-numeric baseline is red" "1" "$(red "$D")"
mkdir -p "$T_TMP/nogit"
t_exit "a non-checkout inspected nothing and is not a pass" 2 env HARBOR_ROOT="$T_TMP/nogit" sh "$T_ROOT/bin/lint-domain.sh" --check

t_section "--zero is the export gate: red on any hit"
D="$(mk zero 9)"; t_eq "three hits under a baseline of 9 are still red" "1" "$(red "$D" --zero)"
rm "$D/bin/a.sh" "$D/docs/d.md"; t_eq "none is green" "0" "$(red "$D" --zero)"

t_section "growth is red, in a new file that was never added"
D="$(mk grow 3)"; printf 'foo ledger\n' > "$D/docs/new.md"
t_eq "an untracked core file counts" "1" "$(red "$D")"
D="$(mk ign 3)"; printf 'docs/new.md\n' > "$D/.gitignore"; printf 'foo ledger\n' > "$D/docs/new.md"
t_eq "an ignored one does not" "0" "$(red "$D")"
D="$(mk more 3)"; printf 'foo ledger\n' >> "$D/docs/d.md"
t_eq "a second term in a listed file is a new pair" "1" "$(red "$D")"
D="$(mk same 3)"; printf 'acmetool again\n' >> "$D/docs/d.md"
t_eq "the same term again in the same file is not" "0" "$(red "$D")"

t_section "a register that does not parse refuses the run, never counts as clean"
D="$(mk noreason 3)"; printf 'docs/d.md\tacme\t\n' >> "$D/CONTRACTS/domain-allow.tsv"
t_eq "an allow row with no reason" "2" "$(red "$D")"
D="$(mk noterm 3)"; printf 'docs/d.md\tnope\tbecause\n' >> "$D/CONTRACTS/domain-allow.tsv"
t_eq "an allow row naming no such term" "2" "$(red "$D")"
D="$(mk dup 3)"; printf 'acme\tother\tdup\n' >> "$D/CONTRACTS/domain-terms.tsv"
t_eq "a term id twice" "2" "$(red "$D")"
D="$(mk noterms 3)"; rm "$D/CONTRACTS/domain-terms.tsv"
t_eq "no terms register" "2" "$(red "$D")"

t_section "lint.domain runs the same check"
D="$(mk lintok 3)"
t_eq "at the baseline the rule is silent" "0" "$(vcount "$(lint1 lint.domain "$D")")"
D="$(mk lintbad 2)"
t_has "above the baseline the rule reports" "$(lint1 lint.domain "$D")" "VIOLATION [lint.domain]"
t_done
