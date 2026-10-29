#!/usr/bin/env sh
# bin/test-suite-cache.sh through bin/test-suite-run.sh, against a fake git repo of tiny suites (HARBOR_ROOT), harbor#1288.
# Each section plants what it guards: a pass to be served, a byte changed in a declared input, a failing suite,
# an input the suite reads but does not declare, a run on main, a changeset that runs everything, a store
# another identity wrote. The cache is the first thing that can turn a changed input into a green run that
# never happened, so every case here is the direction that would be a false pass.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset RUNNER_TEMP GITHUB_ACTIONS GITHUB_REF RUNNER_NAME
SR="$T_ROOT/bin/test-suite-run.sh"; SC="$T_ROOT/bin/test-suite-cache.sh"
R="$T_TMP/repo"; ORD="$T_TMP/order"; ST="$T_TMP/store"
mkdir -p "$R/tests/x" "$R/tests/lib" "$R/contracts" "$R/src/a" "$R/src/b" "$R/data" "$R/docs"
g() { git -C "$R" -c user.name=t -c user.email=t@example.invalid "$@"; }
mk() { # <name> [body] — a suite that records its start, runs body, prints its count line
  printf '#!/bin/sh\necho %s >> "%s"\n%s\necho "%s: 1 passed, 0 failed"\n' "$1" "$ORD" "${2:-:}" "$1" > "$R/tests/x/$1.sh"
}
mk a; mk b; mk f 'exit 3'; mk al
mk r 'cat "$(dirname "$0")/../../data/r.txt" >/dev/null'           # names data/r.txt; declares only itself
mk dy 'd=da; cat "$(dirname "$0")/../../${d}ta/dy.txt" >/dev/null'  # builds the path: nothing to read statically
mk gt 'git -C "$T_ROOT" rev-parse HEAD >/dev/null 2>&1 || :'
mk m 'echo more >> "$(dirname "$0")/../../src/m.txt"'               # edits its own declared input while it runs
printf '%s\n' a b f al r dy gt m | sed 's|^|tests/x/|; s|$|.sh|' > "$R/contracts/suites.txt"
cat > "$R/contracts/suite-paths.txt" <<'EOF'
@no-suite docs/*
tests/x/a.sh tests/x/a.sh src/a/*
tests/x/b.sh tests/x/b.sh src/b/*
tests/x/f.sh tests/x/f.sh src/a/*
tests/x/al.sh always
tests/x/r.sh tests/x/r.sh src/a/*
tests/x/dy.sh tests/x/dy.sh src/a/*
tests/x/gt.sh tests/x/gt.sh src/a/*
tests/x/m.sh tests/x/m.sh src/m.txt src/a/*
EOF
echo core > "$R/tests/lib/core.sh"; echo a > "$R/src/a/x.txt"; echo b > "$R/src/b/x.txt"; echo r > "$R/data/r.txt"
echo dy > "$R/data/dy.txt"; echo m > "$R/src/m.txt"; echo d > "$R/docs/d.md"
g init -q -b work; g add -A; g commit -qm seed
CH='src/a/x.txt'   # a real selection: a b-only change would stand a down
# run [suite...] — the cache on, the store in T_TMP; prints suite-run's output
run() { : > "$ORD"; HARBOR_ROOT="$R" HARBOR_CHANGED="${CHG-$CH}" HARBOR_SUITE_CACHE="${CACHE-1}" HARBOR_SUITE_CACHE_DIR="${SCD:-$ST}" \
  sh "$SR" -j 2 --results "$T_TMP/res" "$@" 2>&1; }
ran() { sort "$ORD" | tr '\n' ' ' | sed 's/ $//'; }
row() { awk -F '\t' -v s="tests/x/$1.sh" '$5 == s { print $1; exit }' "$T_TMP/res"; }
key() { HARBOR_ROOT="$R" HARBOR_SUITE_CACHE_DIR="$ST" sh "$SC" key "tests/x/$1.sh" | cut -f2; }

t_section "the same key is reported cached and does not run"
O="$(run tests/x/a.sh)"
t_eq "first run: a runs" a "$(ran)"
t_has "...and its pass is recorded" "$O" "cache: recorded 1 pass(es)"
O="$(run tests/x/a.sh)"; rc=$?
t_eq "second run, nothing changed: exit 0" 0 "$rc"
t_eq "...a did not run" "" "$(ran)"
t_has "...it is reported cached" "$O" "ok: cached tests/x/a.sh"
t_eq "...and its result row says cached" cached "$(row a)"
t_eq "...carrying the recorded pass's count" 1 "$(awk -F '\t' '$1 == "cached" { print $4 }' "$T_TMP/res")"
t_has "...the summary counts it" "$O" "0 passed, 1 cached, 0 failed"

t_section "one byte changed in a declared input: it runs"
K0="$(key a)"
printf 'a!\n' > "$R/src/a/x.txt"
t_eq "the key moved" yes "$([ "$(key a)" != "$K0" ] && echo yes || echo no)"
run tests/x/a.sh > /dev/null
t_eq "uncommitted, a runs" a "$(ran)"
g commit -qam 'a byte'
run tests/x/a.sh > /dev/null
t_eq "committed, the same content: cached (the key is content, not the commit)" "" "$(ran)"
printf 'core!\n' > "$R/tests/lib/core.sh"; run tests/x/a.sh > /dev/null
t_eq "a byte in the shared test library: a runs" a "$(ran)"
printf 'core\n' > "$R/tests/lib/core.sh"
echo new > "$R/src/a/new.txt"; run tests/x/a.sh > /dev/null
t_eq "an untracked file the declaration covers: a runs" a "$(ran)"
rm -f "$R/src/a/new.txt"; printf 'a\n' > "$R/src/a/x.txt"; g commit -qam back
echo b2 > "$R/src/b/x.txt"; run tests/x/a.sh > /dev/null
t_eq "a byte in a path a does NOT declare (or name): still cached" "" "$(ran)"
echo b > "$R/src/b/x.txt"
printf 'echo extra\n' >> "$R/tests/x/a.sh"; run tests/x/a.sh > /dev/null
t_eq "a byte in the suite itself: a runs" a "$(ran)"
g commit -qam suite
HARBOR_SUITE_CACHE_SALT=s2 run tests/x/a.sh > /dev/null
t_eq "a new salt is a cold cache: a runs" a "$(ran)"

t_section "a failure is never cached"
O="$(run tests/x/f.sh)"; rc=$?
t_eq "f fails: exit 1" 1 "$rc"
O="$(run tests/x/f.sh)"; rc=$?
t_eq "f runs again, and fails again" "1 f" "$rc $(ran)"
t_hasnt "...never reported cached" "$O" "cached tests/x/f.sh"
t_eq "...and the store holds no entry for it" "" "$(grep -rl 'tests/x/f.sh' "$ST" 2>/dev/null)"
mk f; run tests/x/f.sh > /dev/null; mk f 'exit 3'; run tests/x/f.sh > /dev/null
t_eq "a pass of the old f is not a pass of the new one" "f" "$(ran)"

t_section "variable unset: no cache, nothing written, the output names no cache"
rm -rf "$ST"
O1="$(CACHE= run tests/x/a.sh)"; R1="$(ran)"; O2="$(CACHE= run tests/x/a.sh)"
t_eq "a runs both times" "a a" "$R1 $(ran)"
t_hasnt "no cache note in the output" "$O2" "note: cache"
t_hasnt "...and no cached count" "$O2" "cached"
t_eq "no store was made" no "$([ -e "$ST" ] && echo yes || echo no)"
t_eq "the rows are pass rows" pass "$(row a)"
# The runner never even calls the cache: a stub beside a copy of the runner records any call.
G="$T_TMP/gbin"; mkdir -p "$G"; cp "$T_ROOT/bin/test-suite-run.sh" "$T_ROOT/bin/test-suite-select.sh" "$T_ROOT/bin/library-log.sh" "$G/"
printf '#!/bin/sh\necho called >> "%s"\nexit 1\n' "$T_TMP/stub-called" > "$G/test-suite-cache.sh"
HARBOR_ROOT="$R" HARBOR_CHANGED="$CH" sh "$G/test-suite-run.sh" tests/x/a.sh > /dev/null 2>&1
t_eq "unset: bin/test-suite-cache.sh is never run" no "$([ -f "$T_TMP/stub-called" ] && echo yes || echo no)"
HARBOR_ROOT="$R" HARBOR_CHANGED="$CH" HARBOR_SUITE_CACHE=1 sh "$G/test-suite-run.sh" tests/x/a.sh > /dev/null 2>&1
t_eq "control: set, it is" yes "$([ -f "$T_TMP/stub-called" ] && echo yes || echo no)"

t_section "never on main, never when everything runs"
run tests/x/a.sh > /dev/null; run tests/x/a.sh > /dev/null
t_eq "control: the pass is served" "" "$(ran)"
O="$(GITHUB_REF=refs/heads/main run tests/x/a.sh)"
t_eq "a run on refs/heads/main runs a" a "$(ran)"
t_has "...and says why" "$O" "cache off — a run on main keeps a full verdict"
g checkout -q -b main; O="$(run tests/x/a.sh)"; g checkout -q work
t_eq "a checkout on main runs a" a "$(ran)"
t_has "...and says why" "$O" "the checkout is on main"
O="$(CHG='' run tests/x/a.sh)"
t_eq "an empty changeset (every suite runs) runs a" a "$(ran)"
t_has "...and says why" "$O" "cache off — every suite runs: changeset is empty"
O="$(CHG='zzz/unclassified' run tests/x/a.sh)"
t_eq "an unclassified path (every suite runs) runs a" a "$(ran)"
O="$(CHG='bin/test-suite-select.sh' run tests/x/a.sh)"
t_eq "a selector input (every suite runs) runs a" a "$(ran)"
t_has "...and says why" "$O" "selector's own inputs"
O="$(run tests/x/a.sh)"
t_eq "control: the same changeset as before is served again" "" "$(ran)"

t_section "what is never cached: always, git on the checkout"
run tests/x/al.sh tests/x/gt.sh > /dev/null; O="$(run tests/x/al.sh tests/x/gt.sh)"
t_eq "an always suite and a git -C \$T_ROOT suite run every time" "al gt" "$(ran)"
t_has "always: the key says why" "$(HARBOR_ROOT="$R" sh "$SC" key tests/x/al.sh)" "declared always"
t_has "git: the key says why" "$(HARBOR_ROOT="$R" sh "$SC" key tests/x/gt.sh)" "runs git on the checkout"

t_section "an input the suite reads but does not declare (the false pass this is built against)"
run tests/x/r.sh > /dev/null; run tests/x/r.sh > /dev/null
t_eq "control: r is served" "" "$(ran)"
t_has "the static check names data/r.txt as undeclared" "$(HARBOR_ROOT="$R" sh "$SC" undeclared tests/x/r.sh)" "data/r.txt"
echo r2 > "$R/data/r.txt"; run tests/x/r.sh > /dev/null
t_eq "a byte in data/r.txt, which r names and does not declare: r runs" r "$(ran)"
t_has "the manifest holds it" "$(HARBOR_ROOT="$R" sh "$SC" manifest tests/x/r.sh)" " data/r.txt"
# The stated limit (contracts/suite-cache.md): a path built at runtime is invisible to a static reader.
run tests/x/dy.sh > /dev/null; K0="$(key dy)"; echo dy2 > "$R/data/dy.txt"
t_eq "LIMIT: a path built at runtime does not move the key (stated, not caught)" "$K0" "$(key dy)"

t_section "an input edited while the suite ran: the pass is not kept"
O="$(run tests/x/m.sh)"
t_has "m edits src/m.txt as it runs: not recorded" "$O" "recorded 0 pass(es); 1 not, an input changed during the run"
run tests/x/m.sh > /dev/null
t_eq "...so m runs again" m "$(ran)"

t_section "a cached row is read as a run by --tally, --combine and --record"
run tests/x/a.sh tests/x/b.sh > /dev/null; CHG='src/a/x.txt
src/b/x.txt' run tests/x/a.sh tests/x/b.sh > /dev/null
CHG='src/a/x.txt
src/b/x.txt' run tests/x/a.sh tests/x/b.sh > /dev/null
t_eq "a and b both cached" "cached cached" "$(row a) $(row b)"
: > "$T_TMP/gho"; GITHUB_OUTPUT="$T_TMP/gho" sh "$SR" --tally "$T_TMP/res" k tests/x/a.sh tests/x/b.sh > /dev/null 2>&1; rc=$?
t_eq "--tally: pass, ran, the recorded counts summed" "rc=0 k=pass k_ran=true k_count=2 " "rc=$rc $(tr '\n' ' ' < "$T_TMP/gho")"
printf 'tests/x/a.sh\ntests/x/b.sh\n' > "$T_TMP/ab"
O="$(HARBOR_ROOT="$R" sh "$SR" --list "$T_TMP/ab" --combine "$T_TMP/all" "$T_TMP/res" 2>&1)"; rc=$?
t_eq "--combine: exit 0" 0 "$rc"
t_has "...counting them" "$O" "0 passed, 2 cached"
printf '# t\n77\ttests/x/a.sh\n' > "$R/tests/suite-durations.tsv"
HARBOR_ROOT="$R" sh "$SR" --record-from "$T_TMP/res" > /dev/null 2>&1
t_eq "--record keeps a's measured time, not the replayed one" 77 "$(awk -F '\t' '$2 == "tests/x/a.sh" { print $1 }' "$R/tests/suite-durations.tsv")"
rm -f "$R/tests/suite-durations.tsv"

t_section "the store: only what this identity wrote"
run tests/x/a.sh > /dev/null; run tests/x/a.sh > /dev/null
t_eq "control: served" "" "$(ran)"
E="$(find "$ST" -type f -name "$(key a)")"
t_eq "the entry is <store>/<domain>/<key>" yes "$([ -f "$E" ] && echo yes || echo no)"
cp "$E" "$T_TMP/e.keep"; printf 'garbage\n' > "$E"; run tests/x/a.sh > /dev/null
t_eq "an entry that does not parse is a miss: a runs" a "$(ran)"
cp "$T_TMP/e.keep" "$E"; sed 's|tests/x/a.sh|tests/x/b.sh|' "$T_TMP/e.keep" > "$E"; run tests/x/a.sh > /dev/null
t_eq "an entry naming another suite is a miss" a "$(ran)"
O="$(GITHUB_ACTIONS=true RUNNER_NAME=r1 run tests/x/a.sh)"
t_eq "under Actions the box's local pass is not trusted: a runs" a "$(ran)"
GITHUB_ACTIONS=true RUNNER_NAME=r1 run tests/x/a.sh > /dev/null
t_eq "...then r1's own pass is" "" "$(ran)"
GITHUB_ACTIONS=true RUNNER_NAME=r2 run tests/x/a.sh > /dev/null
t_eq "...and r2 does not trust r1's (a store per runner)" a "$(ran)"
O="$(GITHUB_ACTIONS=true RUNNER_NAME= run tests/x/a.sh)"
t_has "under Actions with no runner name: off" "$O" "cache off — under Actions with no RUNNER_NAME"
: > "$T_TMP/afile"; O="$(SCD="$T_TMP/afile/sub" run tests/x/a.sh)"   # a file where the dir would go
t_has "a store it cannot make: off" "$O" "cache off — no store this user owns"
t_eq "...and a runs" a "$(ran)"

t_section "globs match as suite-select's case patterns do"
mkdir -p "$R/src/c/d"; for p in src/c/x.txt src/c/d/y.txt src/c/a.md src/c/ab.md src/cx.txt; do echo . > "$R/$p"; done
printf 'tests/x/a.sh tests/x/a.sh src/c/*.txt src/c/?.md\n' > "$T_TMP/decl"; cat "$R/contracts/suite-paths.txt" >> "$T_TMP/decl"
cp "$R/contracts/suite-paths.txt" "$T_TMP/decl.keep"; cp "$T_TMP/decl" "$R/contracts/suite-paths.txt"
got="$(HARBOR_ROOT="$R" sh "$SC" manifest tests/x/a.sh | awk '$2 ~ /^src\/c/ { print $2 }' | sort | tr '\n' ' ')"
cm() { case "$1" in src/c/*.txt|src/c/?.md) echo "$1" ;; esac; }   # the same globs, as suite-select reads them
want="$(for p in src/c/x.txt src/c/d/y.txt src/c/a.md src/c/ab.md src/cx.txt; do cm "$p"; done | sort | tr '\n' ' ')"
t_eq "* crosses /, ? is one character, the dot is literal" "$want" "$got"
cp "$T_TMP/decl.keep" "$R/contracts/suite-paths.txt"
# The real declarations against the real tree, for suites with a wildcard: every path `case` matches is an input.
if git -C "$T_ROOT" rev-parse --git-dir > /dev/null 2>&1; then
  for s in tests/test/suite-run/suite-run.test.sh tests/status/observe/digest.test.sh tests/check/schedules/schedules.test.sh; do
    gl="$(awk -v k="$s" '$1 == k { $1 = ""; print; exit }' "$T_ROOT/contracts/suite-paths.txt")"
    sh "$SC" manifest "$s" 2>/dev/null | awk 'NR > 8 { print $2 }' | sort > "$T_TMP/m.got"
    git -C "$T_ROOT" ls-files | while IFS= read -r p; do set -f; for x in $gl; do case "$p" in $x) echo "$p"; break ;; esac; done; set +f; done | sort > "$T_TMP/m.want"
    t_eq "$s: every path its declaration covers is in its key" "" "$(comm -23 "$T_TMP/m.want" "$T_TMP/m.got" | head -3)"
  done
else
  t_eq "no checkout at T_ROOT: the real-tree comparison has nothing to read (said, not skipped silently)" no-checkout no-checkout
fi
t_done
