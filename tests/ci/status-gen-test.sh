#!/usr/bin/env sh
# status-gen.sh's suite-count cache (harbor#117). STATUS.md is the one place a count may be stated,
# so the arms that matter are the invalidation ones, not the hit. Suites are three-line fakes.
. "$(dirname "$0")/../lib/core.sh"; t_init
unset HARBOR_IN_SUITE  # t_init keeps the re-entry marker; these cold runs must reach the run branch (harbor#773)
P="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)"; R="$P/repo"
mkdir -p "$R/bin" "$R/build"; cp "$T_ROOT/bin/status-gen.sh" "$T_ROOT/bin/log-lib.sh" "$R/bin/"
mk_suite() { # <name> <label> <count> — the runs.<name> file tells a cache hit from a re-run
  printf '#!/usr/bin/env sh\necho ran >> "%s/runs.%s"\necho "%s: %s passed, 0 failed"\n' "$P" "$1" "$2" "$3" > "$R/bin/$1"
  chmod +x "$R/bin/$1"
}
mk_suite floor-test.sh     floor-test     1438
mk_suite normalize-test.sh normalize-test 164
mk_suite marker-test.sh    marker-test    80
runs() { if [ -f "$P/runs.$1" ]; then wc -l < "$P/runs.$1" | tr -d ' '; else echo 0; fi; }
gen() { HARBOR_ROOT="$R" sh "$R/bin/status-gen.sh" --apply > "$P/out" 2>&1; echo $?; }
TSV="$R/build/suite-counts.tsv"

t_section "a cold run executes the suites and records their counts"
gen >/dev/null
t_eq "the cold run ran floor-test once" 1 "$(runs floor-test.sh)"
t_eq "the cold run recorded floor-test" 1 "$(grep -c '^floor-test.sh	' "$TSV")"
t_has "the recorded count is the printed one" "$(cat "$TSV")" '	1438'

t_section "a warm run serves the cache, byte-identical to cold"
gen >/dev/null
t_eq "a warm run does not re-run the suite" 1 "$(runs floor-test.sh)"
cp "$R/STATUS.md" "$P/warm.md"; rm -f "$TSV"; gen >/dev/null
t_exit "cached and uncached STATUS.md are identical" 0 cmp -s "$P/warm.md" "$R/STATUS.md"

t_section "editing ANY bin/ script invalidates the cache"
# floor-test counts PASSED assertions, so a guard regression moves it without touching the suite.
BEFORE="$(runs floor-test.sh)"
printf '# an unrelated edit\n' >> "$R/bin/normalize-test.sh"; gen >/dev/null
t_eq "a bin/ edit re-runs floor-test" yes "$([ "$(runs floor-test.sh)" -gt "$BEFORE" ] && echo yes || echo no)"
mk_suite floor-test.sh floor-test 1500; gen >/dev/null
t_has "the changed count reaches STATUS.md" "$(cat "$R/STATUS.md")" '1500'

t_section "a corrupt cache row is ignored, not trusted"
BEFORE="$(runs floor-test.sh)"
KEY="$(awk -F'\t' '$1=="floor-test.sh"{print $2; exit}' "$TSV")"
printf 'floor-test.sh\t%s\tnot-a-number\n' "$KEY" > "$TSV"; gen >/dev/null
t_eq "a non-numeric cached count re-runs the suite" yes "$([ "$(runs floor-test.sh)" -gt "$BEFORE" ] && echo yes || echo no)"
t_has "…and STATUS.md carries the real count" "$(cat "$R/STATUS.md")" '1500'

t_section "the cache lives in build/, which is never committed"
ignored() { # ask git; a non-git checkout falls back to .gitignore
  if git -C "$T_ROOT" rev-parse --git-dir >/dev/null 2>&1; then git -C "$T_ROOT" check-ignore -q build/suite-counts.tsv
  else grep -qE '^/?build/?$' "$T_ROOT/.gitignore"; fi
}
t_eq "the cache file is in build/" yes "$([ -f "$TSV" ] && echo yes || echo no)"
t_exit "git ignores build/suite-counts.tsv" 0 ignored

t_section "a suite that cannot run is unmeasured, never zero (2026-09-06)"
gen >/dev/null; cp "$R/STATUS.md" "$P/status.good"
printf '#!/usr/bin/env sh\nthis is ( not shell\n' > "$R/bin/normalize-test.sh"
rm -f "$TSV"
t_eq "--apply refuses with a suite that could not run" 1 "$(gen)"
t_exit "STATUS.md survives the refusal" 0 cmp -s "$R/STATUS.md" "$P/status.good"
t_eq "the unmeasured suite is not cached" 0 "$(awk -F'\t' '$1 == "normalize-test.sh"' "$TSV" 2>/dev/null | grep -c .)"

t_section "teeth: the same fixture with a working suite still writes"
mk_suite normalize-test.sh normalize-test 164; rm -f "$TSV"
t_eq "--apply accepts a healthy generation" 0 "$(gen)"
t_has "…and writes the count" "$(cat "$R/STATUS.md")" 'assertions | 164 |'

# harbor#727: the count-bearing suites move to tests/floor/ one group at a time, so each is
# found wherever it is today, and floor-test is the sum of its floor.<part>-test.sh parts.
M="$P/moved"; mkdir -p "$M/bin" "$M/tests/floor" "$M/build"; cp "$R/bin/status-gen.sh" "$R/bin/log-lib.sh" "$M/bin/"
mk_at() { # <path under $M> <label> <count>
  printf '#!/usr/bin/env sh\necho ran >> "%s/mruns.%s"\necho "%s: %s passed, 0 failed"\n' "$P" "$2" "$2" "$3" > "$M/$1"
}
mruns() { if [ -f "$P/mruns.$1" ]; then wc -l < "$P/mruns.$1" | tr -d ' '; else echo 0; fi; }
row() { grep -F "\`$1\` assertions" "$M/STATUS.md" 2>/dev/null | grep -oE '[0-9]+' | head -1; }  # <suite>
mgen() { HARBOR_ROOT="$M" sh "$M/bin/status-gen.sh" "$@" > "$P/mout" 2>&1; echo $?; }
mk_at tests/floor/floor-test.sh floor-test 10
mk_at tests/floor/floor.a-test.sh floor.a-test 20
mk_at tests/floor/floor.b-test.sh floor.b-test 5
mk_at tests/floor/floor-equiv-test.sh floor-equiv-test 999  # a floor-* suite that is not a part
mk_at tests/floor/normalize-test.sh normalize-test 164
mk_at bin/marker-test.sh marker-test 80

t_section "a moved suite is counted at tests/floor/, a bin/ one where it is (harbor#727)"
t_eq "--apply succeeds on the mixed layout" 0 "$(mgen --apply)"
t_eq "floor-test is the sum of its main part and floor.*-test.sh parts" 35 "$(row floor-test)"
t_eq "each floor part ran once" "1 1 1" "$(mruns floor-test) $(mruns floor.a-test) $(mruns floor.b-test)"
t_eq "floor-equiv-test is not a floor part" 0 "$(mruns floor-equiv-test)"
t_eq "normalize-test is read from tests/floor/" 164 "$(row normalize-test)"
t_eq "marker-test is still read from bin/" 80 "$(row marker-test)"
mv "$M/bin/marker-test.sh" "$M/tests/floor/marker-test.sh"; rm -f "$M/build/suite-counts.tsv"
t_eq "marker-test once it has moved" "0 80" "$(mgen --apply) $(row marker-test)"
mk_at bin/normalize-test.sh normalize-test 7
t_eq "while both exist, bin/ is the suite" "0 7" "$(mgen --apply) $(row normalize-test)"
rm -f "$M/bin/normalize-test.sh"; mgen --apply >/dev/null

t_section "a moved suite's cache is keyed on tests/ too (harbor#727)"
_b="$(mruns floor.a-test)"; mgen --apply >/dev/null
t_eq "an unchanged tree serves the cache" "$_b" "$(mruns floor.a-test)"
printf '# an edit to one part\n' >> "$M/tests/floor/floor.b-test.sh"; mgen --apply >/dev/null
t_eq "editing a tests/floor part re-runs the floor suite" "$((_b + 1))" "$(mruns floor.a-test)"

t_section "the workflow floor.shards-test reads is in the key (harbor#727)"
mkdir -p "$M/.github/workflows"; printf 'a\n' > "$M/.github/workflows/governance.yml"; mgen --apply >/dev/null
_b="$(mruns floor.a-test)"; mgen --apply >/dev/null
t_eq "an unchanged workflow serves the cache" "$_b" "$(mruns floor.a-test)"
printf 'b\n' >> "$M/.github/workflows/governance.yml"; mgen --apply >/dev/null
t_eq "editing the workflow re-runs the floor suite" "$((_b + 1))" "$(mruns floor.a-test)"
printf 'c\n' > "$P/proposed.yml"; ( HARBOR_WORKFLOW="$P/proposed.yml"; export HARBOR_WORKFLOW; mgen --apply >/dev/null )
t_eq "a proposed workflow (HARBOR_WORKFLOW) is keyed too" "$((_b + 2))" "$(mruns floor.a-test)"

t_section "one silent part unmeasures the whole floor suite (harbor#727)"
cp "$M/STATUS.md" "$P/moved.good"; rm -f "$M/build/suite-counts.tsv"
printf '#!/usr/bin/env sh\necho "no count here"\n' > "$M/tests/floor/floor.b-test.sh"
t_eq "--apply refuses" 1 "$(mgen --apply)"
t_has "…naming the silent part" "$(cat "$P/mout")" 'tests/floor/floor.b-test.sh printed NO parseable assertion count'
t_exit "STATUS.md survives the refusal" 0 cmp -s "$M/STATUS.md" "$P/moved.good"
mk_at tests/floor/floor.b-test.sh floor.b-test 5; mgen --apply >/dev/null

t_section "HARBOR_SUITE_COUNTS names a moved suite by its name (harbor#727)"
t_eq "the true supplied counts pass --check" 0 \
  "$(HARBOR_SUITE_COUNTS='floor-test=35 normalize-test=164 marker-test=80' mgen --check)"
_b="$(mruns floor.a-test)"
t_eq "a wrong supplied floor count fails --check" 1 \
  "$(HARBOR_SUITE_COUNTS='floor-test=36 normalize-test=164 marker-test=80' mgen --check)"
t_eq "…without running a part" "$_b" "$(mruns floor.a-test)"
t_eq "a key naming no suite at either path is exit 2" 2 "$(HARBOR_SUITE_COUNTS='flor-test=1' mgen --check)"
t_has "…and says where it looked" "$(cat "$P/mout")" 'no such suite bin/flor-test.sh or tests/floor/flor-test.sh'
t_done
