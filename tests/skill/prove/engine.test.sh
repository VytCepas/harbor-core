#!/usr/bin/env sh
# prove (skills/test-strength/bin/prove.sh), part 2: P3 plants violations IN THE ENGINE and asserts the
# answer changes; P4 asserts a run leaves the repo untouched and that the engine's own tripwire and
# the hasher it rests on can fire. Part 1 is prove-test.sh; fixtures are prove-fixture.sh.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/skills/prove-fixture.sh"
NOOPD="$(mk_noop)"; NOCTL="$(mk_nocontrol)"; BREDD="$(mk_baselinered)"; EXIT9D="$(mk_exit9)"; CMDOK="$(mk_cmdok)"

# Each mutant: the sed applied (else the arm is vacuous), the pristine engine answers as expected,
# and the mutated one does not. The seds key to spec-pinned literals (cmp -s, SURVIVED, CONTROL-RED).
mutate() { # <label> <sed> — writes $T/prove-mut.sh
  sed "$2" "$ENGINE" > "$T/prove-mut.sh"
  t_eq "$1: the planted sed changed prove.sh" changed "$(cmp -s "$ENGINE" "$T/prove-mut.sh" && echo unchanged || echo changed)"
}
engmut() { # <label> <sed> <pristine-rc> <mutated-rc> <args…> — on the exit code
  _l=$1; _mpt="$PT"; mutate "$1" "$2"; _e=$3; _m=$4; shift 4
  PT="$_mpt"; _prove "$@"; rc "$_e" "$_l: the pristine engine"
  PT="$_mpt"; _run_engine "$T/prove-mut.sh" "$@"; rc "$_m" "$_l: the mutated engine answers differently"
}
engmut_txt() { # <label> <sed> <pin> <args…> — on the report: a renamed verdict moves no exit code
  _l=$1; _pin=$3; _mpt="$PT"; mutate "$1" "$2"; shift 3
  PT="$_mpt"; _prove "$@"; t_has "$_l: the pristine report carries the pin" "$O" "$_pin"
  PT="$_mpt"; _run_engine "$T/prove-mut.sh" "$@"; t_hasnt "$_l: the mutated report lacks it" "$O" "$_pin"
}
engmut_fires() { # <label> <sed> <pin> <mutated-rc> <args…> — a tripwire: silent pristine, fires mutated
  _l=$1; _pin=$3; _m=$4; _mpt="$PT"; mutate "$1" "$2"; shift 4
  PT="$_mpt"; _prove "$@"; t_hasnt "$_l: the pristine report does not fire" "$O" "$_pin"
  PT="$_mpt"; _run_engine "$T/prove-mut.sh" "$@"; t_has "$_l: the mutated report fires" "$O" "$_pin"
  rc "$_m" "$_l: and the tripwire bites"
}

t_section "P3 · violations planted IN THE ENGINE: the answer must CHANGE"
# P3-1 reaches both inertness sites and not the repo tripwire, which a global s/cmp -s/ would trip.
P3_1_SED='s/if cmp -s "$SEED" "$_mf"; then/if false; then/
s/if cmp -s "$SEED" "$MUTANT"; then/if false; then/'
PT="$NOOPD" engmut 'P3-1 the inertness check (cmp -s)' "$P3_1_SED" 4 1 --all
PT="$NOCTL" engmut 'P3-2 the zero-control refusal' '/no control declared/d' 5 0 --all
PT="$T/targets" engmut_txt 'P3-3 the control-red outcome' 's/CONTROL-RED/PROVEN/g' '  VERDICT    CONTROL-RED' overbroad
PT="$T/targets" engmut_txt 'P3-4 the canary' 's/SURVIVED/KILLED/g' '  CANARY     SURVIVED' always-green
PT="$T/targets" engmut_txt 'P3-5 the SURVIVORS verdict' 's/SURVIVORS/PROVEN/g' '  VERDICT    SURVIVORS' demo
PT="$T/targets" engmut 'P3-6 the max() aggregation' 's/-gt/-lt/g' 3 2 demo overbroad
PT="$BREDD" engmut 'P3-7 the baseline-green precondition' 's/RED/GREEN/g' 4 5 --all
# Anchored to the assignment: a global rename moves the self-test expectation with it (P3-4 covers that).
mutate 'P3-8 the canary assignment' 's/CANARY=SURVIVED/CANARY=KILLED/'
_run_engine "$T/prove-mut.sh" --self-test
rc 1 'P3-8 a mutated engine own --self-test must FAIL'
# The run counter holds by construction, so only a skipped phase can show it; cmd controls count their own.
PT="$CMDOK" engmut_fires 'P3-9 the run-counter tripwire' \
  's|^        RUNS=$((RUNS + 1))$|        :|' 'run counter mismatch' 4 --all

t_section "P4 · read-only: a mutation engine that edits the repo is a live defect"
# Built with find, never grep: ugrep skips gitignored and binary files, so its silence proves nothing.
manifest() {
  find "$T_ROOT/bin" "$T_ROOT/contracts" "$T_ROOT/fixtures" "$T_ROOT/hooks" "$T_ROOT/skills" "$T_ROOT/vendor" \
       -type f -print0 2>/dev/null | xargs -0 shasum 2>/dev/null | sort
}
M0="$T/m0"; M1="$T/m1"
manifest > "$M0"
G0="$(cd "$T_ROOT" && git status --porcelain 2>/dev/null)"
t_eq 'P4-1 the manifest is not empty' nonempty "$([ -s "$M0" ] && echo nonempty || echo empty)"
_prove demo; _prove clean; _prove odd
PT="$EXIT9D" _prove --all; PT="$NOOPD" _prove --all
manifest > "$M1"
t_eq 'P4-2 no file under bin/contracts/fixtures/hooks/skills/vendor changed during a run' same \
  "$(cmp -s "$M0" "$M1" && echo same || echo changed)"
# Equality, not emptiness: an untracked file is the ordinary state of a branch.
t_eq 'P4-3 git status did not change during a run' "$G0" "$(cd "$T_ROOT" && git status --porcelain 2>/dev/null)"
rm -rf "$T/w2"; mkdir -p "$T/w2"
PT="$EXIT9D" WRK="$T/w2" _prove --all
t_eq 'P4-4 a run ending in COULD-NOT-LOOK leaves no workspace behind' 0 \
  "$(find "$T/w2" -maxdepth 1 -name 'prove.*' 2>/dev/null | wc -l | tr -d ' ')"
rm -rf "$T/w3"; mkdir -p "$T/w3"
WRK="$T/w3" _prove demo --only DATE-1 --keep
WS=$(awk '$1 == "workspace" { print $2; exit }' "$OUT")
t_eq 'P4-5 --keep retains the workspace it names' kept "$([ -n "${WS:-}" ] && [ -d "${WS:-/nonexistent}" ] && echo kept || echo gone)"
t_exit 'P4-6 --keep leaves mutants/DATE-1' 0 test -e "${WS:-/nonexistent}/mutants/DATE-1"
t_exit 'P4-7 --keep leaves mutants/DATE-1.diff, the file the survivor line points at' 0 test -f "${WS:-/nonexistent}/mutants/DATE-1.diff"
manifest > "$M1"
t_eq 'P4-8 the repo is unchanged under a --keep run' same "$(cmp -s "$M0" "$M1" && echo same || echo changed)"
rm -rf "$T/w3"

# The engine's own tripwire, made to fire against a SCRATCH tree carrying the six names it hashes.
FR="$T/fakeroot"; rm -rf "$FR"
for _d in bin contracts fixtures hooks skills vendor; do mkdir -p "$FR/$_d"; printf 'placeholder\n' > "$FR/$_d/keep.txt"; done
TRIPD="$(_base tripwire | _mk_case ok tripwire)"
TRIP='prove: TRIPWIRE  repo modified during run:'
HR="$FR" PT="$TRIPD" _prove --all
rc 0 'P4-9 a run whose workspace is OUTSIDE the hashed tree exits on its own verdict'
t_hasnt 'P4-10 and fires no tripwire' "$O" 'prove: TRIPWIRE'
HR="$FR" PT="$TRIPD" WRK="$FR/skills" _prove --all
t_has 'P4-11 a run that writes inside the hashed tree trips the read-only wire' "$O" 'prove: TRIPWIRE  repo modified during run:'
rc 4 'P4-12 and the tripwire raises the process exit to COULD-NOT-LOOK'

# With no hasher the manifest is empty, and two empty manifests compare equal: the tripwire goes blind.
FARM="$T/hbin"; rm -rf "$FARM"; mkdir -p "$FARM"
ln -s /usr/bin/* "$FARM/" 2>/dev/null; ln -s /bin/* "$FARM/" 2>/dev/null
cp -R "$FARM" "$T/hbin-nosha"; rm -f "$T/hbin-nosha/shasum"
cp -R "$FARM" "$T/hbin-none";  rm -f "$T/hbin-none/shasum" "$T/hbin-none/cksum"
t_eq 'P4-13a the PATH farm carries shasum, cksum and sh' yes \
  "$([ -e "$FARM/shasum" ] && [ -e "$FARM/cksum" ] && [ -e "$FARM/sh" ] && echo yes || echo no)"
HR="$FR" PT="$TRIPD" WRK="$FR/skills" PTH="$FARM" _prove --all
t_has 'P4-13 the PATH farm reproduces the tripwire, so a red below is the hasher' "$O" "$TRIP"
HR="$FR" PT="$TRIPD" WRK="$FR/skills" PTH="$T/hbin-nosha" _prove --all
t_has 'P4-14 with shasum absent the manifest falls back and the tripwire still fires' "$O" "$TRIP"
rc 4 'P4-15 and still raises the process exit'
HR="$FR" PT="$TRIPD" WRK="$T/work" PTH="$T/hbin-none" _prove --all
rc 4 'P4-16 with NEITHER hasher the run is COULD-NOT-LOOK, never a silent pass'
manifest > "$M1"
t_eq 'P4-17 the tripwire and hasher arms left the real repo untouched' same "$(cmp -s "$M0" "$M1" && echo same || echo changed)"
t_done
