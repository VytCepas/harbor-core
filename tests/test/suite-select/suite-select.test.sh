#!/usr/bin/env sh
# test-suite-select.sh decides which suites do NOT run, and a defect there reads as a shorter green
# run (CI-2, harbor#150). Every case but the last section runs on a throwaway root.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset RUNNER_TEMP   # CI exports it; the Actions case below sets its own (test contract rule 1)
SEL="$T_ROOT/bin/test-suite-select.sh"
R="$T_TMP/root"; mkdir -p "$R/contracts" "$R/bin"
cat > "$R/contracts/suites.txt" <<'MAN'
# a manifest
always-test.sh
alpha-test.sh
beta-test.sh
floor-test.sh
undeclared-test.sh
MAN
# undeclared-test.sh is absent here on purpose: an undeclared suite must run.
cat > "$R/contracts/suite-paths.txt" <<'DECL'
# declarations
always-test.sh   always
alpha-test.sh    bin/* docs/*
beta-test.sh     fixtures/* tests/*
floor-test.sh    bin/* docs/generated/status.md
@no-suite        *.md skills/*
DECL
for s in always alpha beta floor undeclared; do
  printf '#!/usr/bin/env sh\nprintf "%s-test: 7 passed, 0 failed\\n"\n' "$s" > "$R/bin/$s-test.sh"
done
# CWD holds a skills/ tree AND top-level .md files, so a selector that lost `set -f` expands its
# @no-suite globs here. Both halves: an unmatched glob stays literal in sh (2026-08-06).
CWD="$T_TMP/cwd"; mkdir -p "$CWD/skills/example-skill" "$CWD/skills/measurement-debug" "$CWD/docs/generated"
: > "$CWD/README.md"; : > "$CWD/docs/generated/status.md"
sel() { _c="$1"; shift; ( cd "$CWD" && HARBOR_SCOPE_ROOT="$R" HARBOR_TEST_CHANGED="$_c" sh "$SEL" "$@" ) 2>&1; }
verdict() { sel "$1" --list | awk -v s="$2" '$2 == s { print $1; exit }'; }  # <changeset> <suite>
runs() { sel "$1" --list | grep -c '^RUN'; }  # 5 = every fixture suite runs

t_section "the decision"
t_eq "an 'always' suite runs for any change" RUN "$(verdict 'skills/example-skill/SKILL.md' always-test.sh)"
t_eq "a path matching a declared glob selects its suite" RUN "$(verdict 'bin/guard-bash.sh' alpha-test.sh)"
t_eq "a suite no changed path matches stands down (the saving itself)" SKIP "$(verdict 'skills/example-skill/SKILL.md' alpha-test.sh)"
t_eq "'*' crosses '/': bin/* selects a nested path" RUN "$(verdict 'bin/nested/deep/thing.sh' alpha-test.sh)"
t_eq "a suite with no declaration runs: silence means run" RUN "$(verdict 'skills/example-skill/SKILL.md' undeclared-test.sh)"

t_section "noglob (the measured 2026-08-06 defect)"
t_eq "skills/example-skill/SKILL.md is classified by the @no-suite globs" SKIP "$(verdict 'skills/example-skill/SKILL.md' beta-test.sh)"
t_hasnt "a @no-suite path is not reported unclassified" "$(sel 'skills/example-skill/SKILL.md' --list)" 'unclassified'
t_has "an unclassified path is reported unclassified" "$(sel 'newdir/thing.conf' --list)" 'unclassified'

t_section "every uncertainty runs everything"
t_eq "an empty changeset" 5 "$(runs '')"
t_eq "an unclassified path" 5 "$(runs 'newdir/thing.conf')"
t_eq "a change to the declarations" 5 "$(runs 'contracts/suite-paths.txt')"
t_eq "a change to the selector" 5 "$(runs 'bin/test-suite-select.sh')"
t_eq "a workflow change" 5 "$(runs '.github/workflows/governance.yml')"
t_eq "a change to the linter" 5 "$(runs 'bin/lint-conventions.sh')"
t_eq "a change to the parallel runner" 5 "$(runs 'bin/test-suite-run.sh')"
t_has "a change to the required-group list is the selector's own input" "$(sel 'contracts/suites-tally.txt' --list)" "selector's own inputs"
t_has "a change to the dash list is the selector's own input" "$(sel 'contracts/suites-dash.txt' --list)" "selector's own inputs"
# beta declares tests/*, so only the SELF list makes this path run everything (harbor#667).
t_eq "a change to the selector's own suite" 5 "$(runs 'tests/test/suite-select/suite-select.test.sh')"
t_has "…and says it is the selector's own input" "$(sel 'tests/test/suite-select/suite-select.test.sh' --list)" "selector's own inputs"
t_has "the unclassified fallback names the path" "$(sel 'newdir/thing.conf' --list)" 'newdir/thing.conf'
R2="$T_TMP/root-nodecl"; mkdir -p "$R2/contracts" "$R2/bin"; cp "$R/contracts/suites.txt" "$R2/contracts/"
t_eq "a missing suite-paths.txt stands nothing down" 5 \
  "$( ( cd "$CWD" && HARBOR_SCOPE_ROOT="$R2" HARBOR_TEST_CHANGED='skills/example-skill/SKILL.md' sh "$SEL" --list ) 2>&1 | grep -c '^RUN')"

t_section "@no-suite classifies, it never suppresses"
t_eq "docs/generated/status.md still selects the suite that declares it" RUN "$(verdict 'docs/generated/status.md' floor-test.sh)"
t_eq "docs/generated/status.md selects no suite that does not declare it" SKIP "$(verdict 'docs/generated/status.md' beta-test.sh)"

t_section "--run"
GO="$T_TMP/gh-output"; GS="$T_TMP/gh-summary"; RO="$T_TMP/run.out"
run() { # <changeset> <suite> → exit code; log in $RO
  : > "$GO"; : > "$GS"
  ( cd "$CWD" && HARBOR_SCOPE_ROOT="$R" HARBOR_TEST_CHANGED="$1" GITHUB_OUTPUT="$GO" GITHUB_STEP_SUMMARY="$GS" \
      sh "$SEL" --run "$2" ) > "$RO" 2>&1
  echo $?
}
t_eq "a stand-down still exits 0" 0 "$(run 'skills/example-skill/SKILL.md' alpha-test.sh)"
t_has "a stand-down says so in the log" "$(cat "$RO")" 'STOOD DOWN'
t_eq "a stand-down publishes ran=false" 1 "$(grep -cFx 'ran=false' "$GO")"
t_has "a stand-down writes a job summary line" "$(cat "$GS")" 'stood down'
t_eq "a passing selected suite exits 0" 0 "$(run 'bin/x.sh' alpha-test.sh)"
t_eq "a suite it ran publishes ran=true" 1 "$(grep -cFx 'ran=true' "$GO")"
t_eq "the suite's printed count is published" 1 "$(grep -cFx 'count=7' "$GO")"
printf '#!/usr/bin/env sh\nprintf "alpha-test: 1 passed, 1 failed\\n"\nexit 1\n' > "$R/bin/alpha-test.sh"
t_eq "a red suite stays red through the wrapper" 1 "$(run 'bin/x.sh' alpha-test.sh)"
# harbor#774 (contracts/logging.md): a failed --run ends by naming the file that keeps the suite's output.
KEPT="$TMPDIR/alpha-test.sh.out"
t_eq "a red run's last line names the kept output" "log: $KEPT" "$(tail -1 "$RO")"
t_has "…a file that holds the suite's full output" "$(cat "$KEPT" 2>/dev/null)" 'alpha-test: 1 passed, 1 failed'
t_has "…and the run says what failed, and where, first" "$(cat "$RO")" "  FAIL: bin/alpha-test.sh exited 1 — its full output is kept at $KEPT"
t_has "…with the fix line the contract wants after a FAIL" "$(cat "$RO")" '  fix: none automatic — see bin/alpha-test.sh'
t_has "…and a summary that agrees with the exit code" "$(cat "$RO")" 'suite-select: 0 ok, 1 failed, 0 warnings'
_rt="$T_TMP/runner-temp"; mkdir -p "$_rt"
( cd "$CWD" && HARBOR_SCOPE_ROOT="$R" HARBOR_TEST_CHANGED='bin/x.sh' RUNNER_TEMP="$_rt" sh "$SEL" --run alpha-test.sh ) > "$RO" 2>&1
t_eq "under Actions the kept output is in RUNNER_TEMP, and named" "log: $_rt/alpha-test.sh.out" "$(tail -1 "$RO")"
printf '#!/usr/bin/env sh\nprintf "alpha-test: 7 passed, 0 failed\\n"\n' > "$R/bin/alpha-test.sh"
run 'bin/x.sh' alpha-test.sh >/dev/null
t_eq "a green run prints nothing new: the suite's summary is still its last line" 'alpha-test: 7 passed, 0 failed' "$(tail -1 "$RO")"
t_hasnt "…and no log line" "$(cat "$RO")" 'log: '
t_eq "…its step outputs keep their bytes" 'ran=true count=7' "$(tr '\n' ' ' < "$GO" | sed 's/ $//')"
printf '#!/usr/bin/env sh\necho "no count here"\n' > "$R/bin/floor-test.sh"
t_eq "a count-bearing suite that prints no count fails" 1 "$(run 'bin/x.sh' floor-test.sh)"
t_eq "…and its last line names the kept output too" "log: $TMPDIR/floor-test.sh.out" "$(tail -1 "$RO")"
t_eq "a suite that carries no count is not failed for it" 0 "$(run 'bin/x.sh' undeclared-test.sh)"

t_section "--run of a manifest PATH runs that file, not a bin/ namesake (harbor#695)"
mkdir -p "$R/skills/demo/bin"
printf '#!/usr/bin/env sh\n: > "%s/ran-path"\nprintf "demo-test: 3 passed, 0 failed\\n"\n' "$T_TMP" > "$R/skills/demo/bin/demo-test.sh"
printf '#!/usr/bin/env sh\n: > "%s/ran-decoy"\nexit 0\n' "$T_TMP" > "$R/bin/demo-test.sh"
t_eq "a path entry exits 0" 0 "$(run 'bin/x.sh' skills/demo/bin/demo-test.sh)"
t_eq "the file at the path ran" yes "$([ -f "$T_TMP/ran-path" ] && echo yes || echo no)"
t_eq "the bin/ decoy did not run" no "$([ -f "$T_TMP/ran-decoy" ] && echo yes || echo no)"
printf '#!/usr/bin/env sh\nexit 1\n' > "$R/skills/demo/bin/demo-test.sh"
t_eq "a failing suite given by path stays red" 1 "$(run 'bin/x.sh' skills/demo/bin/demo-test.sh)"
t_eq "a path that does not exist is a usage error" 2 "$(run 'bin/x.sh' skills/demo/bin/absent-test.sh)"
rm -rf "$R/skills" "$R/bin/demo-test.sh"
t_eq "a suite name that names no file is a usage error" 2 "$(run 'bin/x.sh' nope-test.sh)"

t_section "--run of a moved suite keys its count on the basename (harbor#727)"
mkdir -p "$R/tests/admission/baseline" "$R/tests/admission/normalize" "$R/tests/scope/marker" "$R/tests/other"
tsuite() { printf '#!/usr/bin/env sh\n%s\n' "$2" > "$R/$1"; }  # <path> <body>
tsuite tests/admission/baseline/x.test.sh 'echo "x.test: 4 passed, 0 failed"'
tsuite tests/admission/normalize/normalize.test.sh 'echo "normalize.test: 9 passed, 0 failed"'
tsuite tests/scope/marker/marker.test.sh 'echo "no count here"'
tsuite tests/admission/baseline/quiet.test.sh 'echo "no count here"'
tsuite tests/other/plain-test.sh 'echo "no count here"'
t_eq "a floor part exits 0" 0 "$(run 'bin/x.sh' tests/admission/baseline/x.test.sh)"
t_eq "…and publishes its count" 1 "$(grep -cFx 'count=4' "$GO")"
t_eq "a moved normalize-test publishes its count" "0 1" "$(run 'bin/x.sh' tests/admission/normalize/normalize.test.sh) $(grep -cFx 'count=9' "$GO")"
t_eq "a moved count-bearing suite that prints no count fails" 1 "$(run 'bin/x.sh' tests/scope/marker/marker.test.sh)"
t_has "…naming it" "$(cat "$RO")" 'tests/scope/marker/marker.test.sh printed no assertion count'
t_eq "a floor part that prints no count fails" 1 "$(run 'bin/x.sh' tests/admission/baseline/quiet.test.sh)"
t_eq "a moved suite that carries no count is not failed for it" 0 "$(run 'bin/x.sh' tests/other/plain-test.sh)"
t_eq "--shard is retired: a leftover spelling is a usage error" 2 \
  "$( ( cd "$CWD" && HARBOR_SCOPE_ROOT="$R" HARBOR_TEST_CHANGED='bin/x.sh' sh "$SEL" --run floor-test.sh --shard 0/3 ) > "$RO" 2>&1; echo $?)"
t_has "…that names the retirement" "$(cat "$RO")" '--shard was retired in harbor#727'

t_section "--sum: one job's suite counts (harbor#727)"
sum() { : > "$GO"; ( GITHUB_OUTPUT="$GO" sh "$SEL" --sum "$@" ) > "$RO" 2>&1; echo $?; }
t_eq "every suite ran: exit 0" 0 "$(sum true:3 true:4 true:5)"
t_eq "…its line keeps its bytes (CI reads it, harbor#774)" 'summed 3 suite count(s): 3 + 4 + 5 = 12' "$(cat "$RO")"
t_eq "…publishes the sum" 1 "$(grep -cFx 'count=12' "$GO")"
t_eq "…and ran=true" 1 "$(grep -cFx 'ran=true' "$GO")"
t_eq "every suite stood down: exit 0" 0 "$(sum false: false:)"
t_eq "…publishes ran=false and no count" "1 0" "$(grep -cFx 'ran=false' "$GO") $(grep -c '^count=' "$GO")"
t_eq "…and says so in the same bytes" 'every suite stood down; no count to sum' "$(cat "$RO")"
t_eq "one ran and one stood down is refused" 1 "$(sum true:3 false:)"
t_eq "a suite that ran with no count is refused, never summed as 0" 1 "$(sum true:3 true:)"
t_eq "…and publishes no count" 0 "$(grep -c '^count=' "$GO")"
t_eq "a non-numeric count is refused" 1 "$(sum true:3 true:x)"
t_eq "a malformed term is a usage error" 2 "$(sum true:3 maybe:4)"
t_eq "no terms is a usage error" 2 "$(sum)"

t_section "rows appended to the selector's inputs narrow; anything else runs everything (harbor#150)"
# A real git root: the verdict is judged from the diff against the merge base, as in CI.
G="$T_TMP/groot"; mkdir -p "$G/contracts" "$G/bin" "$G/docs" "$G/newdir"
gq() { git -C "$G" -c user.name=t -c user.email=t@example.invalid "$@" >/dev/null 2>&1; }
printf 'always-test.sh\nalpha-test.sh\nbeta-test.sh\ntests/test/suite-run/suite-run.test.sh\n' > "$G/contracts/suites.txt"
printf '# decl\nalways-test.sh always\nalpha-test.sh bin/*\nbeta-test.sh docs/*\ntests/test/suite-run/suite-run.test.sh nothing/*\n@no-suite *.md\n' > "$G/contracts/suite-paths.txt"
: > "$G/bin/a.sh"; : > "$G/bin/test-suite-run.sh"; : > "$G/docs/d.txt"; : > "$G/newdir/old.conf"
gq init -q -b main; gq add -A; gq commit -q -m base
glane() { gq checkout -q -B lane main; "$@"; gq add -A; gq commit -q -m lane; }  # <edit-fn>: one lane commit
gsel() { ( cd "$CWD" && HARBOR_SCOPE_ROOT="$G" HARBOR_CI_BASE=main sh "$SEL" --list ) 2>&1; }
gv() { gsel | awk -v s="$1" '$2 == s { print $1; exit }'; }  # <suite> → RUN|SKIP
app() { printf 'gamma-test.sh\n' >> "$G/contracts/suites.txt"; printf 'gamma-test.sh gamma/*%s\n' "${1:-}" >> "$G/contracts/suite-paths.txt"; mkdir -p "$G/gamma"; : > "$G/gamma/g.sh"; }
glane app
L="$(gsel)"
t_eq "appended rows: the appended suite runs" RUN "$(gv gamma-test.sh)"
t_has "…because it was appended" "$(printf '%s\n' "$L" | grep ' gamma-test.sh ')" 'appended to the selector'
t_eq "…the selector's own suite runs" RUN "$(gv tests/test/suite-run/suite-run.test.sh)"
t_eq "…a suite nothing selects stands down" SKIP "$(gv alpha-test.sh)"
t_eq "…and so does the other one: not everything" SKIP "$(gv beta-test.sh)"
t_hasnt "…and the fallback is not taken" "$L" "selector's own inputs ("
edit_row() { sed 's|^beta-test.sh docs/\*$|beta-test.sh docs/* other/*|' "$G/contracts/suite-paths.txt" > "$G/x" && mv "$G/x" "$G/contracts/suite-paths.txt"; app; }
glane edit_row
# A row that only GROWS selects its suite more, never less (harbor#1149): that suite runs, not everything.
L="$(gsel)"
t_eq "a row that only grew: its suite runs" RUN "$(gv beta-test.sh)"
t_has "…because its declaration grew" "$(printf '%s\n' "$L" | grep ' beta-test.sh ')" 'its declaration only grew'
t_eq "…the selector's own suite runs" RUN "$(gv tests/test/suite-run/suite-run.test.sh)"
t_eq "…an unrelated suite stands down: not everything" SKIP "$(gv alpha-test.sh)"
t_hasnt "…and the fallback is not taken" "$L" "selector's own inputs ("
shrink_row() { sed 's|^alpha-test.sh bin/\*$|alpha-test.sh other/*|' "$G/contracts/suite-paths.txt" > "$G/x" && mv "$G/x" "$G/contracts/suite-paths.txt"; }
glane shrink_row
t_eq "a row that lost a glob runs everything" RUN "$(gv beta-test.sh)"
t_has "…and names the file" "$(gsel)" "selector's own inputs (contracts/suite-paths.txt: a line removed or edited"
grow_at() { sed 's|^@no-suite \*\.md$|@no-suite *.md bin/*|' "$G/contracts/suite-paths.txt" > "$G/x" && mv "$G/x" "$G/contracts/suite-paths.txt"; }
glane grow_at
t_eq "a grown @ row (@no-suite would hide paths) runs everything" RUN "$(gv beta-test.sh)"
grow_always() { sed 's|^always-test.sh always$|always-test.sh always bin/*|' "$G/contracts/suite-paths.txt" > "$G/x" && mv "$G/x" "$G/contracts/suite-paths.txt"; }
glane grow_always
t_eq "a grown always row runs everything" RUN "$(gv beta-test.sh)"
to_always() { sed 's|^beta-test.sh docs/\*$|beta-test.sh docs/* always|' "$G/contracts/suite-paths.txt" > "$G/x" && mv "$G/x" "$G/contracts/suite-paths.txt"; }
glane to_always
t_eq "a row grown into always runs everything" RUN "$(gv alpha-test.sh)"
grow_old() { sed 's|^beta-test.sh docs/\*$|beta-test.sh docs/* newdir/*|' "$G/contracts/suite-paths.txt" > "$G/x" && mv "$G/x" "$G/contracts/suite-paths.txt"; echo x >> "$G/newdir/old.conf"; }
glane grow_old
t_eq "a grown row cannot classify a path that already existed" RUN "$(gv alpha-test.sh)"
t_has "…which stays unclassified" "$(gsel)" 'no declaration mentions newdir/old.conf'
grow_new() { sed 's|^beta-test.sh docs/\*$|beta-test.sh docs/* newdir/*|' "$G/contracts/suite-paths.txt" > "$G/x" && mv "$G/x" "$G/contracts/suite-paths.txt"; : > "$G/newdir/new2.conf"; }
glane grow_new
t_eq "a grown row may classify a path the changeset adds" SKIP "$(gv alpha-test.sh)"
grow_manifest() { sed 's|^beta-test.sh$|beta-test.sh x|' "$G/contracts/suites.txt" > "$G/x" && mv "$G/x" "$G/contracts/suites.txt"; }
glane grow_manifest
t_eq "an edited manifest row runs everything (growth is suite-paths.txt only)" RUN "$(gv alpha-test.sh)"
drop_row() { grep -v '^beta-test.sh' "$G/contracts/suite-paths.txt" > "$G/x" && mv "$G/x" "$G/contracts/suite-paths.txt"; app; }
glane drop_row
t_eq "a removed declaration row runs everything" RUN "$(gv alpha-test.sh)"
drop_man() { grep -v '^beta-test.sh' "$G/contracts/suites.txt" > "$G/x" && mv "$G/x" "$G/contracts/suites.txt"; app; }
glane drop_man
t_eq "a removed manifest row runs everything" RUN "$(gv alpha-test.sh)"
t_has "…and names the manifest" "$(gsel)" "selector's own inputs (contracts/suites.txt"
reuse() { printf 'alpha-test.sh docs/*\n' >> "$G/contracts/suite-paths.txt"; }  # first row wins, but it is refused
glane reuse
t_eq "an appended row that reuses a key runs everything" RUN "$(gv beta-test.sh)"
old_file() { app ' newdir/*'; echo x >> "$G/newdir/old.conf"; }
glane old_file
t_eq "an appended row cannot classify a path that already existed" RUN "$(gv beta-test.sh)"
t_has "…which stays unclassified" "$(gsel)" 'no declaration mentions newdir/old.conf'
new_file() { app ' newdir/*'; : > "$G/newdir/new.conf"; }
glane new_file
t_eq "an appended row may classify a path the changeset adds" SKIP "$(gv beta-test.sh)"
move_floor() { app ' newdir2/*'; mkdir -p "$G/newdir2"; git -C "$G" mv bin/a.sh newdir2/a.sh; }
glane move_floor
t_eq "moving a declared file into a newly classified directory still selects the old path's declarers" RUN "$(gv alpha-test.sh)"
gq checkout -q main
t_eq "a changeset naming the manifest while git sees no change in it runs everything" RUN \
  "$( ( cd "$CWD" && HARBOR_SCOPE_ROOT="$G" HARBOR_CI_BASE=main HARBOR_TEST_CHANGED='contracts/suites.txt' sh "$SEL" --list ) 2>&1 | awk '$2 == "alpha-test.sh" { print $1 }')"
other_self() { app; echo 'echo x' >> "$G/bin/test-suite-run.sh"; }  # a pure addition, to a file that is not APPENDABLE
glane other_self
t_eq "appended rows beside another selector input run everything" RUN "$(gv beta-test.sh)"
t_has "…and name that input" "$(gsel)" "selector's own inputs (bin/test-suite-run.sh)"

t_section "uncommitted work is part of the local changeset; an unreachable base still runs everything"
gq checkout -q -B wip main
echo x >> "$G/docs/d.txt"
t_eq "an uncommitted edit selects its declarer" RUN "$(gv beta-test.sh)"
t_eq "…and only it: not everything" SKIP "$(gv alpha-test.sh)"
gq checkout -q -- docs/d.txt; : > "$G/docs/new.txt"
t_eq "an untracked new file selects its declarer" RUN "$(gv beta-test.sh)"
t_eq "…and only it" SKIP "$(gv alpha-test.sh)"
t_eq "an unreachable base runs everything, whatever the working tree" RUN \
  "$( ( cd "$CWD" && HARBOR_SCOPE_ROOT="$G" HARBOR_CI_BASE=no-such-ref sh "$SEL" --list ) 2>&1 | awk '$2 == "alpha-test.sh" { print $1 }')"
rm -f "$G/docs/new.txt"; gq checkout -q main
t_eq "a clean tree on the base itself still runs everything" RUN "$(gv alpha-test.sh)"

t_section ".github/CODEOWNERS is not a selector input; a workflow still is (harbor#150)"
t_has "CODEOWNERS is judged like any path" "$(sel '.github/CODEOWNERS' --list)" 'no declaration mentions .github/CODEOWNERS'
t_has "a workflow is still the selector's own input" "$(sel '.github/workflows/governance.yml' --list)" "selector's own inputs"
t_has "an unknown .github/ file is still unclassified" "$(sel '.github/dependabot.yml' --list)" 'unclassified'

t_section "the real contracts/suite-paths.txt"
real() { HARBOR_TEST_CHANGED="$1" sh "$SEL" --list 2>&1; }
N_MAN="$(grep -cvE '^[[:space:]]*(#|$)' "$T_ROOT/contracts/suites.txt")"
t_eq "the real manifest lists suites" yes "$([ "$N_MAN" -gt 0 ] && echo yes || echo no)"
t_eq "every real manifest suite reaches a verdict" "$N_MAN" "$(real 'skills/example-skill/SKILL.md' | grep -cE '^(RUN|SKIP)')"
t_eq "a skills-only change does not select the floor (harbor#150)" SKIP \
  "$(real 'skills/example-skill/SKILL.md' | awk '$2 == "tests/admission/baseline/baseline.test.sh" { print $1 }')"
t_eq "a guard change selects the floor" RUN "$(real 'bin/guard-bash.sh' | awk '$2 == "tests/admission/baseline/baseline.test.sh" { print $1 }')"
# harbor#150: each declaration added to stop a known owner's path running everything.
rv() { real "$1" | awk -v s="$2" '$2 == s { print $1; exit }'; }  # <path> <suite>
t_eq "the naming registry is classified, not run-everything" SKIP "$(rv standards/naming/exemptions.tsv tests/admission/baseline/baseline.test.sh)"
t_eq "…and its always-run owner still runs" RUN "$(rv standards/naming/exemptions.tsv tests/lint/name/name.test.sh)"
t_eq "…and a suite that names a registry file still runs for it" RUN "$(rv standards/naming/controls.tsv tests/scope/pack/pack.test.sh)"
t_eq "registries/coverage-incidents.tsv is classified, not run-everything" SKIP "$(rv registries/coverage-incidents.tsv tests/admission/baseline/baseline.test.sh)"
t_eq "CODEOWNERS selects the suite that checks it is current" RUN "$(rv .github/CODEOWNERS tests/gate/approval/classify.test.sh)"
t_eq "…and nothing that does not declare it" SKIP "$(rv .github/CODEOWNERS tests/admission/baseline/baseline.test.sh)"

# THE LISTS THE WORKFLOW READS (harbor#961): CI tallies its required groups from suites-tally.txt
# and runs suites-dash.txt under dash, so a suite that moves (W2) and leaves a stale line here
# fails here, by name, before the required relays go red with "has no result".
reg_findings() { # <root> -> one finding per line; empty when both lists resolve
  ( cd "$1" || exit 1
    _ls() { grep -vE '^[[:space:]]*(#|$)' "$1" 2>/dev/null || :; }
    _ls contracts/suites.txt | awk '{ print $1 }' > "$T_TMP/reg.man"
    _ls contracts/suites-quick.txt | awk '{ print $1 }' > "$T_TMP/reg.quick"
    [ -n "$(_ls contracts/suites-tally.txt)" ] || echo "tally: contracts/suites-tally.txt is missing or names no suite"
    [ -n "$(_ls contracts/suites-dash.txt)" ] || echo "dash: contracts/suites-dash.txt is missing or names no suite"
    _ls contracts/suites-tally.txt | while read -r _g _w _rest; do
      [ -n "$_w" ] || { echo "tally: group $_g names no suite"; continue; }
      set +f; _n=0
      for _f in $_w; do
        [ -f "$_f" ] || continue; _n=$((_n + 1))
        grep -Fxq -- "$_f" "$T_TMP/reg.man" || echo "tally: $_g's $_f is not in contracts/suites.txt"
        grep -Fxq -- "$_f" "$T_TMP/reg.quick" || echo "tally: $_g's $_f is not in contracts/suites-quick.txt"
      done
      [ "$_n" -gt 0 ] || echo "tally: $_g's $_w matches no file on disk"
    done
    _ls contracts/suites-dash.txt | awk '{ print $1 }' | while IFS= read -r _f; do
      [ -f "$_f" ] || echo "dash: $_f is not on disk"
      grep -Fxq -- "$_f" "$T_TMP/reg.man" || echo "dash: $_f is not in contracts/suites.txt"
    done )
}
t_section "the lists the workflow reads its groups and dash suites from (harbor#961)"
t_eq "every suites-tally.txt and suites-dash.txt line resolves to a manifest suite the pool runs" none \
  "$(reg_findings "$T_ROOT" | grep . || printf 'none')"
RG="$T_TMP/reg-root"; mkdir -p "$RG/contracts" "$RG/tests/a"
for _s in x-test y.one-test y.two-test d-test; do : > "$RG/tests/a/$_s.sh"; done
printf 'tests/a/x-test.sh\ntests/a/y.one-test.sh\ntests/a/y.two-test.sh\ntests/a/d-test.sh\n' > "$RG/contracts/suites.txt"
printf 'tests/a/x-test.sh\ntests/a/y.one-test.sh\ntests/a/y.two-test.sh\n' > "$RG/contracts/suites-quick.txt"
printf 'g1 tests/a/x-test.sh\ng2 tests/a/y.*-test.sh   # a glob\n' > "$RG/contracts/suites-tally.txt"
printf 'tests/a/x-test.sh\n' > "$RG/contracts/suites-dash.txt"
t_eq "a well-formed control has no finding" none "$(reg_findings "$RG" | grep . || printf 'none')"
t_has "a tally entry left behind by a move" "$(printf 'g1 tests/old/x-test.sh\n' >> "$RG/contracts/suites-tally.txt"; reg_findings "$RG")" \
  "tally: g1's tests/old/x-test.sh matches no file on disk"
printf 'g1 tests/a/x-test.sh\ng2 tests/a/y.*-test.sh   # a glob\n' > "$RG/contracts/suites-tally.txt"
t_has "a dash suite left behind by a move" "$(printf 'tests/old/x-test.sh\n' >> "$RG/contracts/suites-dash.txt"; reg_findings "$RG")" \
  "dash: tests/old/x-test.sh is not on disk"
t_has "an empty dash list" "$(printf '# none\n' > "$RG/contracts/suites-dash.txt"; reg_findings "$RG")" \
  "dash: contracts/suites-dash.txt is missing or names no suite"
t_done
