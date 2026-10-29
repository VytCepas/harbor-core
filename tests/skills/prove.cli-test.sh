#!/usr/bin/env sh
# prove (skills/test-strength/bin/prove.sh), part 4: P7 scanner honesty (absence is never coverage), P8
# the CLI surface with every spec threshold bound on both sides, P9 the lawful-but-unusual declaration,
# and P10 a planted violation wherever the engine can print a zero. Fixtures are prove-fixture.sh.
. "$(dirname "$0")/../lib/core.sh"; t_init
. "$T_ROOT/tests/skills/prove-fixture.sh"

t_section "P7 · scanner honesty: absence is never coverage"
_prove demo
t_has 'P7-1 an absent scanner is reported, in words, as no coverage' "$O" 'NOT INSTALLED — no coverage obtained, not a pass'
rc 1 'P7-2 and does not change the target own exit code'
_prove clean
rc 0 'P7-3 a clean target with the same absent scanner still exits 0'
t_has 'P7-4 and still reports the absence rather than omitting it' "$O" 'NOT INSTALLED'
_prove clean --require-scanners
rc 4 'P7-5 --require-scanners turns a missing adapter into COULD-NOT-LOOK'
_prove clean
rc 0 'P7-6 and without the flag the same run is still a pass'
# The flag must not leak across targets: a clean target run after an absent-scanner one stays PROVEN.
SCND="$T/scanleak"; rm -rf "$SCND"; mkdir -p "$SCND"; _mk3 "$SCND"
{ _base a-scan; printf '\nscanner prove-absent-scanner prove-absent-scanner --scan $WORK/doc.md\n'; } > "$SCND/a-scan.target"
_base b-clean > "$SCND/b-clean.target"
PT="$SCND" _prove b-clean --require-scanners
rc 0 'P7-7 a target declaring no scanner is unaffected by --require-scanners when run alone'
PT="$SCND" _prove a-scan --require-scanners
rc 4 'P7-8 and a target declaring an absent one is COULD-NOT-LOOK, or P7-7 proves nothing'
PT="$SCND" _prove --all --require-scanners
t_eq 'P7-9 and running them together does not repaint the clean one' yes "$(re '^  b-clean +PROVEN +exit 0$')"
t_has 'P7-10 whose measurements are still reported, not suppressed' "$O" '  GENERATED  3/3 killed'

t_section "P8 · CLI surface, selectors, and every threshold the spec names"
_prove
rc 0 'P8-1 no arguments prints usage and exits 0'
t_eq 'P8-2 usage prints something' nonempty "$([ -s "$OUT" ] && echo nonempty || echo empty)"
_prove --help
rc 0 'P8-3 --help exits 0'
_prove -h
rc 0 'P8-4 -h exits 0'
# Exit 2 is the only code whose message goes to stderr; both halves, or it is true of every message.
_prove --nosuchflag
rc 2 'P8-5 an unknown flag is USAGE'
t_eq 'P8-6 a usage error writes to stderr' nonempty "$([ -s "$ERR" ] && echo nonempty || echo empty)"
t_eq 'P8-7 and nothing to stdout' 0 "$(wc -c < "$OUT" | tr -d ' ')"
_prove nosuchtarget
rc 2 'P8-8 a selector matching no target is USAGE'
_prove demo/seed.md
rc 2 'P8-9 a path selector matching more than one target is USAGE'
_prove clean/seed.md
rc 0 'P8-10 a path selector matching exactly one target runs it'
EXT= _prove --file "$T/targets/demo.target"
rc 2 'P8-11 --file outside the repo without PROVE_ALLOW_EXTERNAL=1 is USAGE'
EXT=1 _prove --file "$T/targets/demo.target"
rc 1 'P8-12 and with it, the out-of-tree declaration runs'
_mk3 "$T/lane"
_base fastone > "$T/lane/fastone.target"
_base deepone | sed 's/^lane          fast/lane          deep/' > "$T/lane/deepone.target"
PT="$T/lane" _prove --lane fast
rc 0 'P8-13 --lane fast runs the fast target'
t_has 'P8-14 and names it' "$O" 'prove: fastone'
t_hasnt 'P8-15 and not the deep one' "$O" 'prove: deepone'
PT="$T/lane" _prove --lane deep
rc 0 'P8-16 --lane deep runs the deep target'
t_has 'P8-17 and names it' "$O" 'prove: deepone'
t_hasnt 'P8-18 and not the fast one' "$O" 'prove: fastone'
PT="$(_base sites64 'sites         64' | _mk_case ok sites64)" _prove --all
rc 0 'P8-19 sites 64, the ceiling itself, is lawful'
PT="$(_base sites65 'sites         65' | _mk_case bad sites65)" _prove --all
rc 5 'P8-20 sites 65, one over the ceiling, is REFUSED'
PT="$(_base capped 'sites         2' | _mk_case ok capped)" _prove --all
rc 0 'P8-21 a capped run still completes'
t_eq 'P8-22 a class capped from 3 sites to 2 reports capped=1' 1 "$(genfield capped)"
t_has 'P8-23 the cap is named at the class' "$O" 'capped from 3 sites'
t_has 'P8-24 and the verdict cannot read as complete' "$O" 'PROVEN (partial:'
PT="$(_base uncapped 'sites         3' | _mk_case ok uncapped)" _prove --all
rc 0 'P8-25 an uncapped run completes'
t_eq 'P8-26 an uncapped run reports capped=0' 0 "$(genfield capped)"
t_hasnt 'P8-27 and wears no partial label it has not earned' "$O" 'partial'
# The budget, both sides: budget has three sections, so runs = 1 + 1 + 1 + 3 = 6 at cost 1.
BUDD="$(_base budget | _mk_case ok budget)"
PT="$BUDD" BUD=1 _prove --all
rc 4 'P8-28 a target over PROVE_BUDGET is COULD-NOT-LOOK, never a pass'
t_has 'P8-29 and says so' "$O" 'NOT RUN'
t_has 'P8-30 naming the cause' "$O" 'over budget'
PT="$BUDD" BUD=900 _prove --all
rc 0 'P8-31 the same target under a sufficient budget runs and passes'
PT="$BUDD" BUD=6 _prove --all
rc 0 'P8-32 the budget boundary itself (cost x runs == budget) RUNS'
PT="$BUDD" BUD=5 _prove --all
rc 4 'P8-33 one below the boundary does NOT run'
PT="$BUDD" BUD=1 _prove budget
rc 0 'P8-34 a target named explicitly on the command line ignores the budget'

t_section "P9 · the valid-but-unusual declaration: check 2, turned on the format"
_prove odd
rc 0 'P9-1 a lawful declaration with comments, blank lines, sites:, omitted directives and non-ASCII is ACCEPTED'
t_has 'P9-2 and reaches a real verdict' "$O" 'VERDICT    PROVEN'
t_has 'P9-3 its baseline is green' "$O" '  BASELINE   GREEN'
t_has 'P9-4 its control is green' "$O" '  CONTROLS   1/1 green'
t_has 'P9-5 a class with no site is reported skipped, with a reason' "$O" 'no-site'
t_eq 'P9-6 odd reports one no-site class' 1 "$(genfield no-site)"
t_eq 'P9-7 a lawful odd declaration produced no inert mutant' 0 "$(genfield inert)"
t_hasnt 'P9-8 and no percentage leaked into the report' "$O" '%'
_prove --explain odd
rc 0 'P9-9 --explain parses the odd declaration without applying anything'
_prove --list
rc 0 'P9-10 --list is not refused by the odd declaration'
# The posix-shell kind, run rather than listed: a different canary (a script exiting 7) and mutators.
PT="$T/shell" _prove shreal
rc 0 'P9-11 a lawful posix-shell declaration is ACCEPTED and reaches a verdict'
t_has 'P9-12 its kind is reported as declared' "$O" 'kind=posix-shell'
t_has 'P9-13 its canary, a script and not an empty file, is killed' "$O" '  CANARY     KILLED'
t_has 'P9-14 its control is green' "$O" '  CONTROLS   1/1 green'
t_eq 'P9-15 and its shell mutators were applied and killed' yes "$(re '^  GENERATED  2/2 killed')"

t_section "P10 · a planted violation wherever the engine can print a zero"
_prove clean
t_eq 'P10-1 clean reports zero inert' 0 "$(genfield inert)"
t_eq 'P10-2 clean reports zero capped' 0 "$(genfield capped)"
t_hasnt 'P10-3 clean prints no SURVIVOR line' "$O" '    SURVIVOR  '
t_has 'P10-4 clean prints a real killed fraction' "$O" '  GENERATED  '
# A blank block is omitted header and all, so the header's absence is the zero.
t_hasnt 'P10-5 clean declares no manual, so no UNPROVEN header appears' "$O" '  UNPROVEN'
t_has 'P10-6 clean declares a scanner, so the SCANNERS header does appear' "$O" '  SCANNERS'
_prove odd
t_has 'P10-7 odd declares a manual, so the UNPROVEN header appears' "$O" '  UNPROVEN   1'
t_hasnt 'P10-8 odd declares no scanner, so no SCANNERS header appears' "$O" '  SCANNERS'
_prove demo
t_has 'P10-9 the planted eligible violation shows as exactly one survivor' "$O" '    SURVIVOR  DATE-1'
t_eq 'P10-10 and the killed fraction is a fraction, not a score' yes "$(re '^  GENERATED  2/3 killed')"
_prove overbroad
t_has 'P10-11 an over-broad rule shows 0 of 1 controls green' "$O" '  CONTROLS   0/1 green'
# --coverage is a census, counted rather than matched: `target: [a-z]` also matches `target: none`.
REALT="$T_ROOT/skills/test-strength/targets"
PT="$REALT" _prove --coverage
rc 0 'P10-12 --coverage exits 0 against the shipped targets'
t_eq 'P10-13 and prints the census footer' yes "$(re '[0-9]+ of [0-9]+ checkers have a prove target')"
t_hasnt 'P10-14 with no percentage anywhere' "$O" '%'
t_has 'P10-15 naming at least one checker with no target' "$O" 'target: none'
_covall=$(/usr/bin/grep -c 'target: ' "$OUT"); _covnone=$(/usr/bin/grep -c 'target: none' "$OUT")
t_eq 'P10-17 --coverage lists at least two checkers' yes "$([ "${_covall:-0}" -ge 2 ] && echo yes || echo no)"
# The shipped targets name no tests/ checker since the topology, casefile and platform targets left for the measurement
# pack (harbor#1149), so the resolving half is proved on a planted target that names one.
CT="$T/covt"; mkdir -p "$CT"; printf 'checker-cmd   sh tests/skills/prove-test.sh\n' > "$CT/one.target"
PT="$CT" _prove --coverage
t_eq 'P10-16 --coverage resolves a checker a target names to that target' yes "$(re '^tests/skills/prove-test\.sh +target: one$')"
PT="$T/targets" _prove --coverage
rc 0 'P10-18 --coverage exits 0 against a target set that names no repo checker'
_covall=$(/usr/bin/grep -c 'target: ' "$OUT"); _covnone=$(/usr/bin/grep -c 'target: none' "$OUT")
t_eq 'P10-19 and every one of its lines reads target: none' yes \
  "$([ "${_covall:-0}" -gt 0 ] && [ "${_covall:-0}" = "${_covnone:-0}" ] && echo yes || echo no)"
# The declared-survivor zero, planted: the generated side is fully killed first, so a survivor is the plant.
D="$({ _base plantsurv
       printf '\nplant   PSURV-1  sed -e %ss/^Alpha body\\.$/Alpha BODY./%s "$SEED" > "$MUTANT"\n' "$Q" "$Q"
       printf '        why:    a body edit the section-counting checker genuinely cannot see\n'
     } | _mk_case ok plantsurv)"
PT="$D" _prove --all
t_eq 'P10-20 the generated sweep on plantsurv is fully killed' yes "$(re '^  GENERATED  3/3 killed')"
t_has 'P10-21 a plant the checker accepts is reported as a declared survivor' "$O" '  DECLARED   0/1 killed'
t_has 'P10-22 and is named' "$O" '    SURVIVOR  PSURV-1'
t_has 'P10-23 and it reaches the VERDICT, rather than being counted and dropped' "$O" '  VERDICT    SURVIVORS'
rc 1 'P10-24 and sets the exit code, or CI reads a green run over a missed violation'
_prove clean
t_has 'P10-25 while a plant the checker DOES catch reaches PROVEN' "$O" '  DECLARED   1/1 killed'
rc 0 'P10-26 at exit 0'

t_section "P12 · the --coverage census counts the suites under tests/ (harbor#742)"
PT="$REALT" _prove --coverage
t_eq 'P12-1 the real census names a suite that moved to tests/' yes "$(re '^tests/install/roots-test\.sh +target: ')"
# A fixture root: one suite in bin/, one in tests/<area>/, one skill checker, and two files that are not suites.
CR="$T/covroot"; CT="$T/covtargets"; rm -rf "$CR" "$CT"; mkdir -p "$CR/bin" "$CR/tests/area/deep" "$CR/skills/s" "$CT"
for _cf in bin/a-test.sh tests/area/b-test.sh skills/s/check-c.sh tests/area/b-fixture.sh tests/area/deep/d-test.sh; do
  printf '#!/usr/bin/env sh\nexit 0\n' > "$CR/$_cf"
done
printf 'target        covb\nchecker-cmd   sh tests/area/b-test.sh $WORK/doc.md\n' > "$CT/covb.target"
_covrun() { PT="$CT" HR="$CR" _prove --coverage; }
_covrun
rc 0 'P12-2 --coverage exits 0 on the fixture root'
t_eq 'P12-3 the census lists a tests/<area>/ suite' yes "$(re '^tests/area/b-test\.sh +target: covb$')"
t_eq 'P12-4 beside the bin/ suite, which keeps its row' yes "$(re '^bin/a-test\.sh +target: none$')"
t_eq 'P12-5 and counts exactly the three checkers: no fixture, and nothing two levels down' yes \
  "$(re '^1 of 3 checkers have a prove target$')"
mv "$CR/bin/a-test.sh" "$CR/tests/area/a-test.sh"
_covrun
t_eq 'P12-6 a suite moved from bin/ to tests/ keeps the census total' yes "$(re '^1 of 3 checkers have a prove target$')"
t_eq 'P12-7 and is listed at its new path' yes "$(re '^tests/area/a-test\.sh +target: none$')"
t_done
