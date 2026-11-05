#!/usr/bin/env sh
# bin/doc-checks-generate.sh (harbor#1437): docs/reference/checks.md is generated from the check rows of controls.tsv and the repo
# fragments. Red proofs: a fixture check row appears in the page, a hand edit makes --check red, an orphan fragment is refused.
. "$(dirname "$0")/../../lib/core.sh"; t_init
GEN="$T_ROOT/bin/doc-checks-generate.sh"
R="$T_TMP/repo"
mkrepo() { rm -rf "$R"; mkdir -p "$R/standards/naming" "$R/docs/reference/check-rows" "$R/bin"
  cp "$T_ROOT/bin/library-log.sh" "$R/bin/"
  printf '# header\n' > "$R/standards/naming/controls.tsv"
  row() { printf '%s\t%s\tcheck\tbin/x.sh\t-\t%s\tdetective\texperimental\t-\tdoc\t%s\t%s\t%s\n' "$1" warn "$2" "$3" "$4" "$5"; }
  { row alpha.one schedule - - 'the first check'; row beta.two manual tests/x/y.test.sh - 'the second check'; } >> "$R/standards/naming/controls.tsv"
  printf '# CHECKS\n\n| id | watches | schedule | notifies | red means |\n|---|---|---|---|---|\n<!-- gen:check-rows -->\n<!-- private:register -->\n\nprose\n' > "$R/docs/reference/checks.md.tmpl"
  printf 'watches: w1\nschedule: every 900s\nnotifies: desktop\nred: r1\n' > "$R/docs/reference/check-rows/alpha-one.txt"; }
g() { sh "$GEN" --root "$R" "$@" 2>&1; }

t_section "the real page is current"
t_exit "docs/reference/checks.md is what the generator makes (--check)" 0 sh "$GEN" --check
t_eq "every check row of controls.tsv is a row of the page" 0 "$(awk -F'\t' '$0 !~ /^#/ && $3 == "check" { print (($12 != "-" && $12 != "") ? $12 : $1) }' "$T_ROOT/standards/naming/controls.tsv" \
  | while IFS= read -r i; do grep -qF "| \`$i\` |" "$T_ROOT/docs/reference/checks.md" || echo "$i"; done | wc -l | tr -d ' ')"

t_section "a throwaway tree: the page follows controls.tsv and the fragments"
mkrepo; g --write >/dev/null
t_has "a fragment fills the four prose cells" "$(cat "$R/docs/reference/checks.md")" '| `alpha.one` | w1 | every 900s | desktop | r1 |'
t_has "a fixture check row with no fragment still appears, from its controls cells" "$(cat "$R/docs/reference/checks.md")" '| `beta.two` | the second check | not scheduled'
t_has "and its falsifier is the red_proof" "$(grep 'beta.two' "$R/docs/reference/checks.md")" 'tests/x/y.test.sh'
t_has "the private insertion point survives" "$(cat "$R/docs/reference/checks.md")" '<!-- private:register -->'
t_exit "freshly applied is current" 0 sh "$GEN" --root "$R" --check
printf '\nhand edit\n' >> "$R/docs/reference/checks.md"
t_exit "a hand edit makes --check red" 1 sh "$GEN" --root "$R" --check
g --write >/dev/null
t_exit "--write restores it" 0 sh "$GEN" --root "$R" --check
row() { printf '%s\twarn\tcheck\tbin/x.sh\t-\tschedule\tdetective\texperimental\t-\tdoc\t-\t-\t%s\n' "$1" "$2"; }
row gamma.three 'added with no page edit' >> "$R/standards/naming/controls.tsv"
t_exit "a new controls.tsv check row makes the page stale" 1 sh "$GEN" --root "$R" --check
g --write >/dev/null
t_has "and --write puts it on the page" "$(cat "$R/docs/reference/checks.md")" '`gamma.three`'
printf 'delta.four\twarn\tcheck\tbin/x.sh\t-\tschedule\tdetective\texperimental\t-\tdoc\t-\tdelta.old\tx\n' >> "$R/standards/naming/controls.tsv"
t_has "a row emitted under another id is listed by that id" "$(g --print)" '`delta.old`'

t_section "a fragment the register does not know is refused"
printf 'watches: a\nschedule: b\nnotifies: c\nred: d\n' > "$R/docs/reference/check-rows/orphan-id.txt"
t_exit "an orphan fragment exits 2" 2 sh "$GEN" --root "$R" --check
rm -f "$R/docs/reference/check-rows/orphan-id.txt"
printf 'watches: a\nschedule: b\n' > "$R/docs/reference/check-rows/alpha-one.txt"
t_exit "a fragment missing a cell exits 2" 2 sh "$GEN" --root "$R" --check
t_done
