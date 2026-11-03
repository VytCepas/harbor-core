#!/usr/bin/env sh
# bin/standard-inventory.sh facts and uncalled (harbor#1431, harbor#1432): the env and bin registers are held both ways. Red proofs on a
# throwaway tree: a name read with no row, a row nothing reads, a kill-switch naming no control, a name in two registers, a file with no
# row, a row with no file, an uncalled file in the retirement report. The real tree reads clean.
. "$(dirname "$0")/../../lib/core.sh"; t_init
INV="$T_ROOT/bin/standard-inventory.sh"
R="$T_TMP/repo"
ENVH='var	repo	kind	default	meaning	stability	owner	controls'
BINH='path	form	layer	purpose	ticket'
mkrepo() {
  rm -rf "$R"; mkdir -p "$R/bin" "$R/contracts" "$R/standards/naming"
  cp "$T_ROOT/bin/standard-register.sh" "$T_ROOT/bin/library-log.sh" "$INV" "$R/bin/"
  cp "$T_ROOT/standards/naming/schemas.tsv" "$R/standards/naming/"
  printf 'var\tbase\trel\tbreaks\tshared\n' > "$R/contracts/roots.tsv"
  printf '%s\n' "$ENVH" > "$R/contracts/env.tsv"
  printf '%s\n%s\n%s\n' "$BINH" 'bin/standard-register.sh	command	floor	the reader	-' 'bin/library-log.sh	library	floor	the log	-' > "$R/contracts/bin.tsv"
  printf 'bin/standard-inventory.sh	command	floor	this	-\n' >> "$R/contracts/bin.tsv"
  printf '#!/usr/bin/env sh\necho "${HARBOR_TEST_FIXTURE_X:-1}"\n' > "$R/bin/fixture-x.sh"
}
facts() { sh "$R/bin/standard-inventory.sh" --root "$R" facts 2>&1; }

t_section "the real tree reads clean, both registers, both ways"
t_eq "no finding on this checkout" "" "$(sh "$INV" --root "$T_ROOT" facts 2>&1)"

t_section "env: a name read in code with no row is red"
mkrepo
out="$(facts)"
t_has "the unregistered name is a finding" "$out" 'var:HARBOR_TEST_FIXTURE_X'
t_has "it names the file that reads it" "$out" 'read in bin/fixture-x.sh'
printf 'HARBOR_TEST_FIXTURE_X\tharbor\tvalue\t1\ta fixture value\texperimental\tstandard\t-\n' >> "$R/contracts/env.tsv"
t_hasnt "a row clears it" "$(facts; echo end)" 'var:HARBOR_TEST_FIXTURE_X'

t_section "env: a row nothing reads is red"
printf 'HARBOR_TEST_FIXTURE_GONE\tharbor\tvalue\t-\tread by nothing\texperimental\tstandard\t-\n' >> "$R/contracts/env.tsv"
t_has "the unread row is a finding" "$(facts)" 'row:HARBOR_TEST_FIXTURE_GONE'
printf '#!/usr/bin/env sh\n# HARBOR_TEST_FIXTURE_GONE appears in a comment only\n' > "$R/bin/fixture-y.sh"
t_has "a comment is not a reader" "$(facts)" 'row:HARBOR_TEST_FIXTURE_GONE'
printf 'echo "$HARBOR_TEST_FIXTURE_GONE"\n' >> "$R/bin/fixture-y.sh"
t_hasnt "a code line is" "$(facts; echo end)" 'row:HARBOR_TEST_FIXTURE_GONE'
printf 'HARBOR_TEST_FIXTURE_T\tharbor\ttest-only\t-\tset by a suite\texperimental\tstandard\t-\n' >> "$R/contracts/env.tsv"
mkdir -p "$R/tests"; printf 'HARBOR_TEST_FIXTURE_T=1 sh x\n' > "$R/tests/a.test.sh"
t_hasnt "a test-only row is read by a test" "$(facts; echo end)" 'row:HARBOR_TEST_FIXTURE_T'

t_section "env: a kill-switch names the controls it switches"
printf 'HARBOR_TEST_FIXTURE_OFF\tharbor\tkill-switch\t-\tturns the fixture guard off\texperimental\tstandard\t-\n' >> "$R/contracts/env.tsv"
printf 'echo "$HARBOR_TEST_FIXTURE_OFF"\n' >> "$R/bin/fixture-x.sh"
t_has "a kill-switch row with no control is red" "$(facts)" 'switch:HARBOR_TEST_FIXTURE_OFF'
sed -i.bak 's/^\(HARBOR_TEST_FIXTURE_OFF.*\)-$/\1admission.kill-switch-first/' "$R/contracts/env.tsv"; rm -f "$R/contracts/env.tsv.bak"
t_hasnt "naming a control clears it" "$(facts; echo end)" 'switch:HARBOR_TEST_FIXTURE_OFF'
t_has "the control id must resolve in controls.tsv (the schema reference)" "$(sh "$T_ROOT/bin/standard-register.sh" schema contracts/env.tsv)" 'controls>standards/naming/controls.tsv:id'

t_section "env: a name registered in roots.tsv is registered there once"
printf 'HARBOR_TEST_FIXTURE_X\tREPOS\tx\tnothing\t\n' >> "$R/contracts/roots.tsv"
t_has "a name in both registers is red" "$(facts)" 'dup:HARBOR_TEST_FIXTURE_X'
t_hasnt "a root-only name needs no env row" "$(sed -i.bak '/^HARBOR_TEST_FIXTURE_X/d' "$R/contracts/env.tsv"; rm -f "$R/contracts/env.tsv.bak"; facts; echo end)" 'var:HARBOR_TEST_FIXTURE_X'

t_section "env: a kind outside the closed set is red"
printf 'HARBOR_TEST_FIXTURE_K\tharbor\twhatever\t-\tk\texperimental\tstandard\t-\n' >> "$R/contracts/env.tsv"
t_has "kind" "$(facts)" 'kind:HARBOR_TEST_FIXTURE_K'

t_section "bin: a file with no row is red, a row with no file is red"
mkrepo
t_has "bin/fixture-x.sh has no row" "$(facts)" 'file:bin/fixture-x.sh'
printf 'bin/fixture-x.sh\tcommand\tfloor\ta fixture script\t-\nbin/fixture-gone.sh\tcommand\tfloor\tno file\t-\n' >> "$R/contracts/bin.tsv"
out="$(facts)"
t_hasnt "a row clears the file finding" "$out" 'file:bin/fixture-x.sh'
t_has "a row with no file is red" "$out" 'row:bin/fixture-gone.sh'
printf 'bin/fixture-z.sh\tgadget\tfloor\tbad form\t-\n' >> "$R/contracts/bin.tsv"; : > "$R/bin/fixture-z.sh"
t_has "a form outside the set is red" "$(facts)" 'form:bin/fixture-z.sh'

t_section "bin: the layer is floor (sh), trio (Python) or tool (TypeScript), and it must agree with the file's language"
mkrepo
printf 'bin/fixture-x.sh\tcommand\tfloor\ta fixture script\t-\nbin/fixture-py.py\tcommand\ttrio\ta python script\t-\nbin/fixture-ts.ts\tcommand\ttool\ta ts script\t-\n' >> "$R/contracts/bin.tsv"
: > "$R/bin/fixture-py.py"; : > "$R/bin/fixture-ts.ts"
t_hasnt "a layer that matches the language is clean" "$(facts; echo end)" 'layer:'
sed -i.bak 's/^bin\/fixture-py.py\tcommand\ttrio/bin\/fixture-py.py\tcommand\tfloor/' "$R/contracts/bin.tsv"; rm -f "$R/contracts/bin.tsv.bak"
t_has "a Python file filed as floor is red" "$(facts)" 'layer:bin/fixture-py.py'
sed -i.bak 's/^bin\/fixture-py.py\tcommand\tfloor/bin\/fixture-py.py\tcommand\tgadget/' "$R/contracts/bin.tsv"; rm -f "$R/contracts/bin.tsv.bak"
t_has "a layer outside the set is red" "$(facts)" 'layer:bin/fixture-py.py'
sed -i.bak 's/^bin\/fixture-py.py\tcommand\tgadget/bin\/fixture-py.py\tcommand\t-/' "$R/contracts/bin.tsv"; rm -f "$R/contracts/bin.tsv.bak"
t_has "an empty layer is red" "$(facts)" 'layer:bin/fixture-py.py'
t_has "the schema row carries the layer column" "$(sh "$T_ROOT/bin/standard-register.sh" schema contracts/bin.tsv)" 'path form layer purpose ticket'
t_eq "every row of the real register carries a layer" "0" "$(awk -F'\t' '!/^#/ && $1 != "path" && ($3 == "" || $3 == "-")' "$T_ROOT/contracts/bin.tsv" | wc -l | tr -d ' ')"

t_section "bin: an uncalled file is a retirement proposal, never a deletion"
mkrepo; mkdir -p "$R/hooks" "$R/cfg"
printf 'bin/fixture-x.sh\tcommand\tfloor\ta fixture script\t-\nbin/fixture-called.sh\tcommand\tfloor\ta called script\t-\n' >> "$R/contracts/bin.tsv"
printf '#!/usr/bin/env sh\ntrue\n' > "$R/bin/fixture-called.sh"
printf '#!/usr/bin/env sh\nsh bin/fixture-called.sh\n' > "$R/hooks/pre"
unc() { sh "$R/bin/standard-inventory.sh" --root "$R" --config-dir "$R/cfg" --today 2026-11-02 uncalled 2>&1; }
out="$(unc)"
t_has "the uncalled file is in the report" "$out" 'bin/fixture-x.sh'
t_hasnt "a called file is not" "$out" 'fixture-called.sh'
t_eq "it is still there" yes "$([ -f "$R/bin/fixture-x.sh" ] && echo yes || echo no)"
t_exit "a proposal not seen before exits 1" 1 sh "$R/bin/standard-inventory.sh" --root "$R" --config-dir "$R/cfg-fresh" --today 2026-11-03 uncalled
t_exit "the same proposal a day later is standing and exits 0" 0 sh "$R/bin/standard-inventory.sh" --root "$R" --config-dir "$R/cfg-fresh" --today 2026-11-04 uncalled
out="$(unc)"
t_has "a standing one is a count with an age, not a relist" "$out" 'standing'
t_has "the receipt is filed for the findings channel" "$(ls "$R/cfg/cache/checks" 2>/dev/null)" 'standard.script-uncalled.json'
printf 'fixture-x.sh   VERB  typed by a person\n' > "$R/contracts/idle-tools.txt"
t_hasnt "a declared VERB is not a candidate" "$(sh "$R/bin/standard-inventory.sh" --root "$R" --config-dir "$R/cfg2" uncalled 2>&1; echo end)" 'bin/fixture-x.sh'

t_section "the sweep agrees with lint.tool-has-caller on the real tree"
callers="$(sh "$INV" --root "$T_ROOT" callers)"
undeclared=""
for f in $(printf '%s\n' "$callers" | awk -F'\t' '$2 == "-" && $1 ~ /\.sh$/ { sub("bin/", "", $1); print $1 }'); do
  grep -q "^${f}[[:space:]]" "$T_ROOT/contracts/idle-tools.txt" || undeclared="$undeclared $f"
done
t_eq "every .sh file the sweep finds uncalled is declared in contracts/idle-tools.txt" "" "${undeclared# }"
t_done
