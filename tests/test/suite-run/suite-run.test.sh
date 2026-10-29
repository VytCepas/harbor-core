#!/usr/bin/env sh
# bin/test-suite-run.sh against a fake repo of tiny suites (HARBOR_ROOT), so no real suite runs. Each section
# plants the thing it guards — a long suite queued late, a failing suite, a worker's lost result, a pair
# of suites that only pass when they overlap — and checks that the runner notices.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset RUNNER_TEMP   # Actions sets it and suite-run puts its work dir there, not under t_init's TMPDIR (harbor#1032)
SR="$T_ROOT/bin/test-suite-run.sh"; R="$T_TMP/repo"; ORD="$T_TMP/order"
mkdir -p "$R/tests/x" "$R/contracts"
mk() { # <name> [body] — a suite that records its start, runs body, prints its count line
  printf '#!/bin/sh\necho %s >> "%s"\n%s\necho "%s: 1 passed, 0 failed"\n' "$1" "$ORD" "${2:-:}" "$1" > "$R/tests/x/$1.sh"
}
man() { printf 'tests/x/%s.sh\n' "$@" > "$R/contracts/suites.txt"; }
run() { HARBOR_ROOT="$R" HARBOR_SUITE_TIMEOUT="${TMO:-900}" sh "$SR" "$@" 2>&1; }
for s in a b c d u; do mk "$s"; done
man a b c d u
printf '# generated\n5\ttests/x/a.sh\n30\ttests/x/b.sh\n10\ttests/x/c.sh\n30\ttests/x/d.sh\n' > "$R/tests/suite-durations.tsv"

t_section "longest first, and a suite the table does not know goes first"
t_eq "the plan is unknown, then 30 30 10 5, ties in manifest order" \
  "tests/x/u.sh tests/x/b.sh tests/x/d.sh tests/x/c.sh tests/x/a.sh" "$(run --plan | tr '\n' ' ' | sed 's/ $//')"
: > "$ORD"; run -j 1 >/dev/null
t_eq "one at a time, the suites START in that order" "u b d c a" "$(tr '\n' ' ' < "$ORD" | sed 's/ $//')"
mv "$R/tests/suite-durations.tsv" "$T_TMP/dur.keep"
t_eq "with no table, manifest order" "tests/x/a.sh tests/x/b.sh tests/x/c.sh tests/x/d.sh tests/x/u.sh" "$(run --plan | tr '\n' ' ' | sed 's/ $//')"
mv "$T_TMP/dur.keep" "$R/tests/suite-durations.tsv"

t_section "all green is exit 0 with a counted summary"
O="$(run -j 3)"; rc=$?
t_eq "exit 0" 0 "$rc"
t_eq "one ok line per suite" 5 "$(printf '%s\n' "$O" | grep -c '^  ok: [0-9]*s tests/x/')"
t_has "the summary counts five" "$O" "suite-run: 5 ok, 0 failed"

t_section "a failing suite fails the run and its log tail is on the page"
mk f 'echo "the-cause-is-here"; exit 3'; man a b f
O="$(run -j 2)"; rc=$?
t_eq "exit 1" 1 "$rc"
t_has "a FAIL line names it and its exit" "$O" "tests/x/f.sh exited 3"
t_has "a fix line follows" "$O" "  fix: none automatic — see tests/x/f.sh"
t_has "the tail of its log is printed" "$O" "    the-cause-is-here"
t_eq "the others still ran" 2 "$(printf '%s\n' "$O" | grep -c '^  ok: [0-9]*s tests/x/[ab]\.sh')"

t_section "suites run at the same time (each waits for the other; one at a time deadlocks into a fail)"
mk p 'touch "$T_RV/p"; i=0; while [ ! -f "$T_RV/q" ] && [ $i -lt 40 ]; do sleep 0.25; i=$((i+1)); done; [ -f "$T_RV/q" ] || exit 1'
mk q 'touch "$T_RV/q"; i=0; while [ ! -f "$T_RV/p" ] && [ $i -lt 40 ]; do sleep 0.25; i=$((i+1)); done; [ -f "$T_RV/p" ] || exit 1'
man p q; mkdir -p "$T_TMP/rv"
rm -f "$T_TMP/rv/"*; t_exit "-j 2 runs them together" 0 env T_RV="$T_TMP/rv" HARBOR_ROOT="$R" sh "$SR" -j 2
rm -f "$T_TMP/rv/"*; t_exit "-j 1 cannot, so the control fails" 1 env T_RV="$T_TMP/rv" HARBOR_ROOT="$R" sh "$SR" -j 1

t_section "every queued suite must come back with exactly one result"
mk k ': > "$_SR_RES"'   # destroys the results the runner had collected before it
man a b k; printf '9\ttests/x/a.sh\n8\ttests/x/b.sh\n1\ttests/x/k.sh\n' > "$R/tests/suite-durations.tsv"
O="$(run -j 1)"; rc=$?
t_eq "a damaged result set fails the run" 1 "$rc"
t_has "and names the suite whose result is missing" "$O" "LOST: tests/x/a.sh"

t_section "a worker never vanishes: a lost lock race or a signal is a fail row, never LOST (harbor#1378)"
# uutils mkdir 0.10 (Ubuntu 26.04, ubuntu-latest) exits 0 when it loses a creation race; this one always loses.
UU="$T_TMP/uu"; mkdir -p "$UU"; MKD="$(command -v mkdir)"
printf '#!/bin/sh\ncase "$1" in -*) exec %s "$@" ;; esac\n%s -p -- "$@" && sleep 1\n' "$MKD" "$MKD" > "$UU/mkdir"; chmod +x "$UU/mkdir"
mk r1; mk r2; man r1 r2
O="$(PATH="$UU:$PATH" run -j 2)"; rc=$?
t_eq "where mkdir cannot lock, both workers still run their suite: exit 0, two ok" "0 2" \
  "$rc $(printf '%s\n' "$O" | grep -c '^  ok: [0-9]*s tests/x/r[12]\.sh')"
mk w 'for m in "$_SR_LOGS"/../running/*; do kill -TERM "${m##*/}"; done; sleep 5'; man w
O="$(run -j 1)"
t_has "a worker killed by TERM leaves a fail row naming the signal" "$O" "tests/x/w.sh the worker was killed by SIGTERM"
t_hasnt "...so nothing is LOST" "$O" "LOST"

t_section "the work dir: removed when green, kept when a suite failed (harbor#1032)"
wd() { find "$T_TMP/tmp" -maxdepth 1 -name 'suite-run.*' -type d | wc -l | tr -d ' '; }
man a b; N0="$(wd)"
run -j 2 >/dev/null
t_eq "a green run leaves no suite-run.* dir behind" "$N0" "$(wd)"
mk f 'exit 3'; man a f
O="$(run -j 2)"
t_eq "a red run keeps exactly one" $((N0 + 1)) "$(wd)"
t_has "...the one its FAIL line points into" "$O" "$T_TMP/tmp/suite-run."
mkdir -p "$T_TMP/rt"
O="$(RUNNER_TEMP="$T_TMP/rt" run -j 2)"
t_eq "under Actions the work dir is RUNNER_TEMP's, not TMPDIR's" "1 $((N0 + 1))" \
  "$(find "$T_TMP/rt" -maxdepth 1 -name 'suite-run.*' -type d | wc -l | tr -d ' ') $(wd)"

t_section "the pool re-reads its CPU quota before every suite (harbor#1032)"
CM="$T_TMP/cpu.max"; CON="$T_TMP/conc"
# each suite counts how many are running while it runs, and keeps the highest
for s in c1 c2 c3 c4; do mk "$s" 'mkdir -p "$T_CON/run"; : > "$T_CON/run/$$"; n=$(ls "$T_CON/run" | wc -l); echo $n >> "$T_CON/seen"; sleep 2; rm -f "$T_CON/run/$$"'; done
man c1 c2 c3 c4; rm -f "$R/tests/suite-durations.tsv"
peak() { sort -n "$CON/seen" | tail -1 | tr -d ' '; }
rm -rf "$CON"; mkdir -p "$CON"; echo '50000 100000' > "$CM"
T_CON="$CON" HARBOR_CPU_MAX="$CM" HARBOR_ROOT="$R" sh "$SR" -j 4 >/dev/null 2>&1
t_eq "half a CPU: never more than one suite at once, though --jobs is 4" 1 "$(peak)"
rm -rf "$CON"; mkdir -p "$CON"; echo '200000 100000' > "$CM"
T_CON="$CON" HARBOR_CPU_MAX="$CM" HARBOR_ROOT="$R" sh "$SR" -j 4 >/dev/null 2>&1
t_eq "control: two CPUs allow all four" 4 "$(peak)"
# xargs starts the workers together, so which suite takes the one slot first is not fixed: every suite raises the
# quota and holds until a second one has started, so the pool must widen whoever goes first (harbor#1032).
for s in c1 c2 c3 c4; do mk "$s" 'mkdir -p "$T_CON/run"; : > "$T_CON/run/$$"; n=$(ls "$T_CON/run" | wc -l); echo $n >> "$T_CON/seen"; echo "200000 100000" > "$T_CM"; i=0; while [ "$(wc -l < "$T_CON/seen" | tr -d " ")" -lt 2 ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i+1)); done; rm -f "$T_CON/run/$$"'; done
rm -rf "$CON"; mkdir -p "$CON"; echo '50000 100000' > "$CM"
T_CM="$CM" T_CON="$CON" HARBOR_CPU_MAX="$CM" HARBOR_ROOT="$R" sh "$SR" -j 4 >/dev/null 2>&1
t_eq "a quota raised mid-run (by whichever suite starts first) widens the pool for the rest" yes "$([ "$(peak)" -ge 2 ] && echo yes || echo no)"
rm -f "$R/tests/suite-durations.tsv"

t_section "include, and a stale list is refused"
man a b c
printf '# only\ntests/x/c.sh\n' > "$T_TMP/in"; t_eq "--include keeps only it" "tests/x/c.sh" "$(run --include "$T_TMP/in" --plan)"
printf 'tests/x/gone.sh\n' > "$T_TMP/stale"
t_exit "an include naming a suite that is not a candidate exits 2" 2 env HARBOR_ROOT="$R" sh "$SR" --include "$T_TMP/stale" --plan
# --exclude only ever served the macOS lane's list, gone with macOS CI (harbor#1060): it is refused, not ignored.
printf 'tests/x/b.sh\n' > "$T_TMP/ex"
t_exit "--exclude is no longer an option" 2 env HARBOR_ROOT="$R" sh "$SR" --exclude "$T_TMP/ex" --plan
t_exit "a positional suite that does not exist exits 2" 2 env HARBOR_ROOT="$R" sh "$SR" --plan tests/x/gone.sh

t_section "--select stands down what the changeset does not touch, and says so"
printf '@no-suite docs/*\ntests/x/a.sh tests/x/a.sh src/a/*\ntests/x/b.sh tests/x/b.sh src/b/*\ntests/x/c.sh always\n' > "$R/contracts/suite-paths.txt"
: > "$ORD"; O="$(HARBOR_CHANGED='src/a/f.txt' run -j 2 --select --results "$T_TMP/sel.tsv")"; rc=$?
t_eq "exit 0" 0 "$rc"
t_eq "a and c ran, b did not" "a c" "$(sort "$ORD" | tr '\n' ' ' | sed 's/ $//')"
t_has "b's stand-down is a skip line with its reason" "$O" "  skip: tests/x/b.sh stood down — no changed path matches"
t_eq "and a skip row in the results" "skip" "$(awk -F '\t' '$5 == "tests/x/b.sh" { print $1 }' "$T_TMP/sel.tsv")"

t_section "--tally: one group's verdict"
TR="$T_TMP/t.tsv"
printf 'pass\t1\t0\t4\tg1\t\npass\t2\t0\t6\tg2\t\nfail\t1\t1\t-\tg3\texited 1\nskip\t0\t-\t-\tg4\tr\nskip\t0\t-\t-\tg5\tr\npass\t1\t0\t-\tg6\t\n' > "$TR"
tally() { : > "$T_TMP/gho"; GITHUB_OUTPUT="$T_TMP/gho" sh "$SR" --tally "$TR" k "$@" >/dev/null 2>&1; echo "rc=$? $(tr '\n' ' ' < "$T_TMP/gho")"; }
t_eq "two passes: pass, ran, counts summed" "rc=0 k=pass k_ran=true k_count=10 " "$(tally g1 g2)"
t_eq "a failed member fails the group" "rc=1 k=fail k_ran=true k_count=4 " "$(tally g1 g3)"
t_eq "a member with no result fails the group" "rc=1 k=fail k_ran=true k_count=4 " "$(tally g1 g9)"
t_eq "all stood down: pass, not ran" "rc=0 k=pass k_ran=false k_count=0 " "$(tally g4 g5)"
t_eq "half ran, half stood down: refused" "rc=1 k=fail k_ran=false k_count=4 " "$(tally g1 g4)"
t_eq "a ran member with no count: refused, never summed as 0" "rc=1 k=fail k_ran=true k_count=4 " "$(tally g1 g6)"

t_section "--shard K/N: the selection split by recorded time, every suite in exactly one shard (harbor#1172)"
for s in a b c d e u; do mk "$s"; done; man a b c d e u
printf '# generated\n50\ttests/x/a.sh\n40\ttests/x/b.sh\n30\ttests/x/c.sh\n20\ttests/x/d.sh\n10\ttests/x/e.sh\n' > "$R/tests/suite-durations.tsv"
planq() { HARBOR_ROOT="$R" sh "$SR" --plan "$@" 2>/dev/null; }   # stdout only: --plan puts the shard note on stderr
plan() { planq "$@" | tr '\n' ' ' | sed 's/ $//'; }
# longest first, each to the lighter shard: a50->1 b40->2 c30->2 u30->1 d20->2 e10->1, 90 s each
t_eq "shard 1/2, its own queue order (u is unknown, so first)" "tests/x/u.sh tests/x/a.sh tests/x/e.sh" "$(plan --shard 1/2)"
t_eq "shard 2/2 is the rest" "tests/x/b.sh tests/x/c.sh tests/x/d.sh" "$(plan --shard 2/2)"
t_eq "an unknown suite weighs the table's mean (30), so with N=3 it joins c" "tests/x/u.sh tests/x/c.sh" "$(plan --shard 3/3)"
for n in 1 2 3 4 8; do
  : > "$T_TMP/union"; k=1
  while [ "$k" -le "$n" ]; do planq --shard "$k/$n" >> "$T_TMP/union"; k=$((k + 1)); done
  t_eq "N=$n: the shards' union is the unsharded plan, no suite twice" "$(planq | sort | tr '\n' ' ')" "$(sort "$T_TMP/union" | tr '\n' ' ')"
done
mv "$R/tests/suite-durations.tsv" "$T_TMP/dur.keep"
t_eq "no table: every suite weighs the same, so manifest order round robin" "tests/x/a.sh tests/x/c.sh tests/x/e.sh" "$(plan --shard 1/2)"
mv "$T_TMP/dur.keep" "$R/tests/suite-durations.tsv"
for bad in 0/2 3/2 1/0 01/2 x/2 1/2/3 2; do
  t_exit "--shard $bad is refused" 2 env HARBOR_ROOT="$R" sh "$SR" --plan --shard "$bad"
done

t_section "shard 1 starts with the linter's weight, from the table's own row (harbor#1172)"
# The linter runs in shard 1 before its suites. Same suites as above plus a 40 s lint row: a50->2 b40->1 c30->2
# u30->1 d20->2 e10->2, so shard 1 is b and u (40 + 40 + 30), shard 2 is a c d e (110).
printf '# generated\n50\ttests/x/a.sh\n40\ttests/x/b.sh\n40\tbin/lint-conventions.sh\n30\ttests/x/c.sh\n20\ttests/x/d.sh\n10\ttests/x/e.sh\n' > "$R/tests/suite-durations.tsv"
t_eq "shard 1 takes less suite time: u b" "tests/x/u.sh tests/x/b.sh" "$(plan --shard 1/2)"
t_eq "shard 2 takes the rest: a c d e" "tests/x/a.sh tests/x/c.sh tests/x/d.sh tests/x/e.sh" "$(plan --shard 2/2)"
t_has "the note shows every shard's total, linter included" "$(HARBOR_ROOT="$R" sh "$SR" --plan --shard 1/2 2>&1 >/dev/null)" "every shard: 110s 110s"
t_has "...and says what the linter weighs" "$(HARBOR_ROOT="$R" sh "$SR" --plan --shard 2/2 2>&1 >/dev/null)" "linter 40s on shard 1"
# 110s per shard needs u at 30, the mean of the five suites: a lint row in the mean would make it 33
t_eq "N=3 with the lint row: it opens shard 1, so b and u share shard 3" "tests/x/u.sh tests/x/b.sh" "$(plan --shard 3/3)"
t_eq "only shard 1 carries it: the unsharded plan lists no linter" 0 "$(planq | grep -c lint-conventions || :)"
printf 'pass\t7\t0\t1\ttests/x/a.sh\t\n' > "$T_TMP/kept.tsv"
run --record-from "$T_TMP/kept.tsv" >/dev/null
t_eq "--record-from keeps the lint row when --lint is omitted" 40 "$(awk -F '\t' '$2 == "bin/lint-conventions.sh" { print $1 }' "$R/tests/suite-durations.tsv")"
run --record-from "$T_TMP/kept.tsv" --lint 95 >/dev/null
t_eq "--lint SECS refreshes it" 95 "$(awk -F '\t' '$2 == "bin/lint-conventions.sh" { print $1 }' "$R/tests/suite-durations.tsv")"
t_exit "--lint wants whole seconds" 2 env HARBOR_ROOT="$R" sh "$SR" --record-from "$T_TMP/kept.tsv" --lint 1.5
printf '# generated\n50\ttests/x/a.sh\n40\ttests/x/b.sh\n30\ttests/x/c.sh\n20\ttests/x/d.sh\n10\ttests/x/e.sh\n' > "$R/tests/suite-durations.tsv"   # back to the table the next sections expect

t_section "shards run apart and --combine makes them one run: each suite once, or red (harbor#1172)"
for s in a b c d e u; do printf 'tests/x/%s.sh tests/x/%s.sh src/%s/*\n' "$s" "$s" "$s"; done > "$R/contracts/suite-paths.txt"
CH="$(printf 'src/a/f\nsrc/b/f\nsrc/e/f\nsrc/u/f')"   # selects a b e u; c d stand down
# a50->1 b40->2 u30->2 e10->1
: > "$ORD"; HARBOR_CHANGED="$CH" run --select --shard 1/2 --results "$T_TMP/r1" >/dev/null
t_eq "shard 1 ran a and e" "a e" "$(sort "$ORD" | tr '\n' ' ' | sed 's/ $//')"
: > "$ORD"; HARBOR_CHANGED="$CH" run --select --shard 2/2 --results "$T_TMP/r2" >/dev/null
t_eq "shard 2 ran b and u" "b u" "$(sort "$ORD" | tr '\n' ' ' | sed 's/ $//')"
t_eq "the stand-downs are shard 1's rows, not shard 2's" "2 0" \
  "$(awk -F '\t' '$1 == "skip"' "$T_TMP/r1" | grep -c .) $(awk -F '\t' '$1 == "skip"' "$T_TMP/r2" | grep -c . || :)"
t_exit "the two combine" 0 env HARBOR_ROOT="$R" sh "$SR" --combine "$T_TMP/all" "$T_TMP/r1" "$T_TMP/r2"
t_eq "...to one row per candidate" "a b c d e u" "$(cut -f5 "$T_TMP/all" | sed 's|tests/x/||; s|\.sh$||' | sort | tr '\n' ' ' | sed 's/ $//')"
t_eq "...that --tally reads as one run's" "rc=0 k=pass k_ran=true k_count=2 " \
  "$(: > "$T_TMP/gho"; GITHUB_OUTPUT="$T_TMP/gho" sh "$SR" --tally "$T_TMP/all" k tests/x/a.sh tests/x/b.sh >/dev/null 2>&1; echo "rc=$? $(tr '\n' ' ' < "$T_TMP/gho")")"
O="$(run --combine "$T_TMP/all" "$T_TMP/r1")"; rc=$?
t_eq "a shard's results missing: red" 1 "$rc"
t_has "...naming each suite no shard has" "$O" "LOST: tests/x/b.sh"
O="$(run --combine "$T_TMP/all" "$T_TMP/r1" "$T_TMP/r2" "$T_TMP/r2")"; rc=$?
t_eq "a shard's results twice: red" 1 "$rc"
t_has "...naming the suite in two" "$O" "DUPLICATE: tests/x/b.sh has 2 results"
t_eq "...and the combined row is a fail, so its group fails too" "rc=1 k=fail" \
  "$(: > "$T_TMP/gho"; GITHUB_OUTPUT="$T_TMP/gho" sh "$SR" --tally "$T_TMP/all" k tests/x/b.sh >/dev/null 2>&1; echo "rc=$? $(head -1 "$T_TMP/gho")")"
printf 'pass\t1\t0\t1\ttests/x/zz.sh\t\n' > "$T_TMP/r3"
O="$(run --combine "$T_TMP/all" "$T_TMP/r1" "$T_TMP/r2" "$T_TMP/r3")"; rc=$?
t_eq "a result for a suite that is not a candidate: red" 1 "$rc"
t_has "...named STRAY" "$O" "STRAY: tests/x/zz.sh"
t_exit "a results file that is not there: red" 1 env HARBOR_ROOT="$R" sh "$SR" --combine "$T_TMP/all" "$T_TMP/r1" "$T_TMP/r2" "$T_TMP/none"
# the two shards judged different changesets (each job reads the base for itself)
HARBOR_CHANGED='src/a/f' run --select --shard 1/2 --results "$T_TMP/r1" >/dev/null
O="$(run --combine "$T_TMP/all" "$T_TMP/r1" "$T_TMP/r2")"; rc=$?
t_eq "shards that split different selections: red" 1 "$rc"
t_has "...b stood down in one and ran in the other" "$O" "DUPLICATE: tests/x/b.sh"

t_section "--record-from: a kept results file rewrites the table and runs nothing"
printf 'pass\t7\t0\t1\ttests/x/a.sh\t\nskip\t0\t-\t-\ttests/x/b.sh\tr\n' > "$T_TMP/kept.tsv"
echo marker > "$ORD"; run --record-from "$T_TMP/kept.tsv" >/dev/null
t_eq "a takes the file's 7 s; b stood down there, so it keeps 40" "7 40" \
  "$(awk -F '\t' '$2 == "tests/x/a.sh" { a = $1 } $2 == "tests/x/b.sh" { b = $1 } END { print a, b }' "$R/tests/suite-durations.tsv")"
t_eq "no suite ran" marker "$(cat "$ORD")"
t_eq "the results file is read, not emptied" 2 "$(grep -c . "$T_TMP/kept.tsv")"
t_exit "a results file that is not there exits 2" 2 env HARBOR_ROOT="$R" sh "$SR" --record-from "$T_TMP/none.tsv"

t_section "--record rewrites the table, longest first, and drops suites the manifest lost"
mk slow 'sleep 2'; man a slow
printf '# old\n7\ttests/x/a.sh\n3\ttests/x/gone.sh\n' > "$R/tests/suite-durations.tsv"
run -j 2 --record tests/x/slow.sh >/dev/null
t_eq "a kept from before, slow added after it, gone dropped" "tests/x/a.sh tests/x/slow.sh" \
  "$(grep -v '^#' "$R/tests/suite-durations.tsv" | cut -f2 | tr '\n' ' ' | sed 's/ $//')"
t_eq "slow's time is what it measured" yes "$(awk -F '\t' '$2 == "tests/x/slow.sh" { print ($1 >= 2 && $1 <= 6) ? "yes" : $1 }' "$R/tests/suite-durations.tsv")"
t_has "it says it is generated" "$(head -1 "$R/tests/suite-durations.tsv")" "generated by bin/test-suite-run.sh --record"

t_section "the limit is for a hang, not a slow run (no timeout(1) needed)"
# A silent suite is cut off after TMO seconds without output, with its children; a suite that keeps printing is not,
# however long it takes, until the hard cap; both say "timed out" so a red is never a bare exit 124.
mk hang 'sleep 30 & echo $! > "'"$T_TMP"'/hang.pid"; wait'; man hang
S0="$(date +%s)"; O="$(TMO=2 HARBOR_SUITE_HARD_TIMEOUT=0 run -j 1)"; S1="$(date +%s)"
t_has "a silent suite fails as timed out" "$O" "timed out: no output for 2s"
t_eq "...within seconds, not the suite's own 30" yes "$([ $((S1 - S0)) -lt 15 ] && echo yes || echo no)"
t_eq "...and its child is killed too" no "$(kill -0 "$(cat "$T_TMP/hang.pid")" 2>/dev/null && echo yes || echo no)"
mk slow 'for i in 1 2 3 4 5 6; do echo tick; sleep 1; done'; man slow
O="$(TMO=3 HARBOR_SUITE_HARD_TIMEOUT=0 run -j 1)"
t_has "a suite printing every second outlives a 3s idle limit" "$O" "ok: "
t_hasnt "...and is not called timed out" "$O" "timed out"
mk chatty 'while :; do echo tick; sleep 1; done'; man chatty
O="$(TMO=3 HARBOR_SUITE_HARD_TIMEOUT=5 run -j 1)"
t_has "a suite that never stops printing hits the hard cap" "$O" "timed out: no output for 3s, or 5s in all"
# A governor waiting for a CPU slot has written no log yet: that wait is bounded by its deadline, not a hang.
G="$T_TMP/gbin"; mkdir -p "$G"; cp "$T_ROOT/bin/test-suite-run.sh" "$T_ROOT/bin/library-log.sh" "$G/"; mk gw; man gw
printf '#!/bin/sh\nshift 2; o="$1"; shift 2; sleep 4; exec "$@" > "$o" 2>&1\n' > "$G/ci-governor.sh"
O="$(HARBOR_ROOT="$R" HARBOR_SUITE_TIMEOUT=2 HARBOR_SUITE_HARD_TIMEOUT=20 sh "$G/test-suite-run.sh" -j 1 2>&1)"
t_has "a 4s wait for a slot outlives a 2s idle limit" "$O" "ok: "
t_hasnt "...and is not called timed out" "$O" "timed out"

t_section "inside the confinement: no open of /dev/stderr, no reliance on ps (harbor#555)"
# The sandbox refuses an open of /dev/stderr or /dev/fd/2 and refuses ps, so every suite died unstarted and a hung
# suite's child outlived it. A runner outside the sandbox cannot make either fail, so the first is static here
# (awk's "/dev/stderr" is awk's own and stays legal); the hang section above is the behavioural half in a session.
devopen() { grep -nE '(^|[^"])(/dev/stderr|/dev/fd/[0-9])' "$1" | grep -vE '^[0-9]+:[[:space:]]*#'; }
printf '  _sink=/dev/stderr\n  awk %s\n' "'{ print > \"/dev/stderr\" }'" > "$T_TMP/ctl.sh"
t_eq "CONTROL: the pattern finds a shell open and passes awk's" "1:  _sink=/dev/stderr" "$(devopen "$T_TMP/ctl.sh")"
t_eq "test-suite-run.sh opens no /dev/stderr or /dev/fd/N by name" "" "$(devopen "$SR")"
# ps answers nothing: a hung suite's child still dies, through the suite's own process group.
P="$T_TMP/nops"; mkdir -p "$P"; printf '#!/bin/sh\nexit 1\n' > "$P/ps"; chmod +x "$P/ps"
mk hang 'sleep 30 & echo $! > "'"$T_TMP"'/hang.pid"; wait'; man hang
O="$(PATH="$P:$PATH" TMO=2 HARBOR_SUITE_HARD_TIMEOUT=0 run -j 1)"
t_has "with ps refused, a silent suite still times out" "$O" "timed out: no output for 2s"
# Does this shell give a monitor-mode job its own group? dash with no tty declines, and then only ps walks the tree.
OWNPG="$( (set -m 2>/dev/null; sleep 5 & g=$!; set +m 2>/dev/null; kill -0 "-$g" 2>/dev/null && echo yes || echo no; kill "$g" 2>/dev/null) </dev/null)"
if [ "$OWNPG" = yes ]; then
  t_eq "...and its child is killed through the process group" no "$(kill -0 "$(cat "$T_TMP/hang.pid")" 2>/dev/null && echo yes || echo no)"
  # A stop sent to the run's own group no longer reaches a suite in its group: the worker passes it on.
  rm -f "$T_TMP/hang.pid"
  ( set -m 2>/dev/null; HARBOR_ROOT="$R" HARBOR_SUITE_TIMEOUT=900 sh "$SR" -j 1 >/dev/null 2>&1 & echo $! > "$T_TMP/run.pid"; wait ) </dev/null &
  i=0; while [ ! -s "$T_TMP/hang.pid" ] && [ $i -lt 40 ]; do sleep 0.25; i=$((i + 1)); done
  t_eq "CONTROL: the hung suite's child is running" yes "$(kill -0 "$(cat "$T_TMP/hang.pid" 2>/dev/null)" 2>/dev/null && echo yes || echo no)"
  kill -TERM "-$(cat "$T_TMP/run.pid")" 2>/dev/null; sleep 2
  t_eq "a TERM to the run's group still kills the suite's child" no "$(kill -0 "$(cat "$T_TMP/hang.pid")" 2>/dev/null && echo yes || echo no)"
  kill -9 "$(cat "$T_TMP/hang.pid")" 2>/dev/null || :
else
  printf '  note: this shell declines monitor mode without a tty (dash), so only ps walks the tree here\n'
fi
t_done
