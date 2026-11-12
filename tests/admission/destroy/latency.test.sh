#!/usr/bin/env sh
# eval-hook-latency.sh (harbor#1290): the percentile arithmetic, the budget verdict, and the two guards that keep a
# benchmark from measuring nothing (an arm that does not do what its name says). It never asserts a wall-clock figure:
# the figure is the tool's output on the box, and a timing assertion would flip with the machine.
set -u
. "$(dirname "$0")/../../lib/core.sh"
t_init

L="$T_ROOT/bin/eval-hook-latency.sh"
GI="-c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false -c init.defaultBranch=main"

t_section "stats: p50 per arm, added latency = p50(on) - p50(off), verdict against the budget"
_in='on 10
on 40
on 30
on 20
on 50
off 5
off 7
off 6
off 9
off 8'
_o="$(printf '%s\n' "$_in" | sh "$L" stats --budget-ms 50)"; _rc=$?
t_eq "exit 0 within budget" 0 "$_rc"
t_has "on p50 is the median of 10..50" "$_o" "on   n=5  min=10.0  p50=30.0"
t_has "off p50 is the median of 5..9" "$_o" "off  n=5  min=5.0  p50=7.0"
t_has "added p50 = 23" "$_o" "added p50 = 23.0 ms (on - off), budget < 50 ms: WITHIN"
_o="$(printf '%s\n' "$_in" | sh "$L" stats --budget-ms 23)"; _rc=$?
t_eq "exit 1 at the budget (strict less-than)" 1 "$_rc"
t_has "OVER" "$_o" ": OVER"
printf 'on 1\n' | sh "$L" stats > /dev/null 2>&1; t_eq "one arm is no verdict: exit 2" 2 "$?"
sh "$L" bogus > /dev/null 2>&1; t_eq "unknown command: exit 2" 2 "$?"
sh "$L" run --runs 0 > /dev/null 2>&1; t_eq "--runs 0: exit 2" 2 "$?"

t_section "run: a real hook on a dirty fixture tree, both arms sampled"
R="$T_TMP/r"; mkdir -p "$R" && git $GI -C "$R" init -q
printf 'one\n' > "$R/a.txt"; git $GI -C "$R" add -A && git $GI -C "$R" commit -qm init
printf 'two\n' > "$R/a.txt"; printf 'new\n' > "$R/u.txt"
_o="$(sh "$L" run --runs 3 --tree "$R" --budget-ms 100000 2>&1)"; _rc=$?
t_eq "exit 0 under a huge budget" 0 "$_rc"
t_has "on arm sampled 3 times" "$_o" "on   n=3"
t_has "off arm sampled 3 times" "$_o" "off  n=3"
t_eq "the benchmark leaves no snapshot behind" 0 "$(git -C "$R" for-each-ref refs/snapshots/ | wc -l | tr -d ' ')"
t_eq "and no off switch" no "$([ -e "$R/.git/harbor-snapshot-off" ] && echo yes || echo no)"
# Whether one sample lands over a zero budget is timing (a fast runner can see on <= off), so assert the exit follows the verdict printed.
_o="$(sh "$L" run --runs 1 --tree "$R" --budget-ms 0 2>&1)"; _rc=$?
case "$_o" in *": OVER"*) _want=1 ;; *) _want=0 ;; esac
t_eq "the exit follows the verdict over a zero budget" "$_want" "$_rc"

t_section "run refuses to measure a step that did not run"
C="$T_TMP/clean"; mkdir -p "$C" && git $GI -C "$C" init -q
printf 'one\n' > "$C/a.txt"; git $GI -C "$C" add -A && git $GI -C "$C" commit -qm init
_o="$(sh "$L" run --runs 1 --tree "$C" 2>&1)"; _rc=$?
t_eq "a clean tree takes no snapshot: exit 2" 2 "$_rc"
t_has "and says why" "$_o" "the ON arm took 0 snapshots"
# Red: the guard's off switch renamed in a copy, so the OFF arm still snapshots.
mkdir -p "$T_TMP/cp/bin"
for _f in eval-hook-latency.sh library-log.sh admission-destroy.sh library-admission.sh admission-normalize.awk; do cp "$T_ROOT/bin/$_f" "$T_TMP/cp/bin/"; done
sed 's/harbor-snapshot-off/harbor-snapshot-gone/' "$T_ROOT/bin/admission-destroy.sh" > "$T_TMP/cp/bin/admission-destroy.sh"
_o="$(sh "$T_TMP/cp/bin/eval-hook-latency.sh" run --runs 1 --tree "$R" 2>&1)"; _rc=$?
t_eq "a broken off switch: exit 2" 2 "$_rc"
t_has "named" "$_o" "the OFF arm still took a snapshot"

t_done
