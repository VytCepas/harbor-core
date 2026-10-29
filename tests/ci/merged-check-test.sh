#!/usr/bin/env sh
# merged-check.sh decides "is this work already in main?" by content, and `merged` is the verdict
# worktree gc deletes on (harbor#213, #226, #634). Every merge method the repo permits has an arm:
# squash (one and many commits), --no-ff, rebase replay, and none of them. Fixtures are real git.
. "$(dirname "$0")/../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/merged-check.sh"
P="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)"  # git prints resolved paths; /var is a symlink here
R="$P/repo"; mkdir -p "$R"; git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main
g() { git -C "$R" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
verdict() { sh "$TOOL" --repo "$R" main "$1" 2>/dev/null | awk '{print $1; exit}'; }  # <ref>
say() { t_eq "$3 ($1)" "$2" "$(verdict "$1")"; }  # <ref> <want> <label>
yn() { if "$@"; then echo yes; else echo no; fi; }
printf 'x\n' > "$R/base"; g add -A; g commit -qm base
BASE0="$(g rev-parse HEAD)"

t_section "a one-commit squash merge (the case git cherry gets right)"
g checkout -qb one-commit "$BASE0"
printf 'a\n' > "$R/a"; g add -A; g commit -qm a
g checkout -q main; g merge -q --squash one-commit >/dev/null 2>&1; g commit -qm "squash: one-commit"
say one-commit merged "a single-commit squash merge"

t_section "a three-commit squash merge, the defect harbor#213 is about"
g checkout -qb three-commits "$BASE0"
printf 'b1\n' > "$R/b"; g add -A; g commit -qm b1
printf 'b2\n' >> "$R/b"; g commit -qam b2
printf 'b3\n' >> "$R/b"; g commit -qam b3
g checkout -q main; g merge -q --squash three-commits >/dev/null 2>&1; g commit -qm "squash: three-commits"
say three-commits merged "a multi-commit squash merge"
t_eq "premise: the fixture holds 2+ commits" yes \
  "$(yn [ "$(g rev-list --count "$(g merge-base main three-commits)..three-commits")" -ge 2 ])"
t_eq "control: git cherry is wrong here, which is why the tool does not stop at it" yes \
  "$(yn [ "$(g cherry main three-commits | grep -c '^+')" -gt 0 ])"

t_section "a squash made against context the branch never had (harbor#634)"
# #623 and #624 on 2026-09-23: lines 2 and 4 change (adjacent lines would conflict), so the
# second squash's patch-id cannot equal its branch's and only test 5 can see it.
printf '1\n2\n3\n4\n5\n6\n7\n8\n' > "$R/ctx"; g add -A; g commit -qm ctx
CTX0="$(g rev-parse HEAD)"
edit() { sed "s/^$1\$/$1-$2/" "$R/ctx" > "$R/ctx.new" && mv "$R/ctx.new" "$R/ctx"; g commit -qam "$2"; }
g checkout -qb ctx-sibling "$CTX0"; edit 2 sibling
g checkout -qb ctx-late "$CTX0"; edit 4 late
g checkout -q main
g merge -q --squash ctx-sibling >/dev/null 2>&1; g commit -qm "squash: ctx-sibling"
g merge -q --squash ctx-late >/dev/null 2>&1; g commit -qm "squash: ctx-late"
t_exit "premise: ctx-late's tree differs from main (test 2 cannot answer)" 1 g diff --quiet main ctx-late --
LP="$(g diff "$CTX0..ctx-late" | git patch-id --stable 2>/dev/null | awk '{print $1; exit}')"
SP="$(g show main --format= | git patch-id --stable 2>/dev/null | awk '{print $1; exit}')"
t_eq "premise: the late branch has a patch-id" yes "$(yn [ -n "$LP" ])"
t_eq "premise: the squash's patch-id is not the branch's (test 4 cannot answer)" yes "$(yn [ "$LP" != "$SP" ])"
say ctx-late merged "a squash landed after a sibling changed nearby lines"
g checkout -qb ctx-unmerged "$CTX0"; edit 6 unmerged
g checkout -q main
objs() { find "$R/.git/objects" -type f -path '*/objects/??/*' | wc -l | tr -d ' '; }
O0="$(objs)"; mkdir -p "$P/tmpd"
t_eq "unmerged work of the same shape stays absent" absent \
  "$(TMPDIR="$P/tmpd" sh "$TOOL" --repo "$R" main ctx-unmerged 2>/dev/null | awk '{print $1; exit}')"
t_eq "test 5 writes no object into the repo" "$O0" "$(objs)"
t_eq "test 5 leaves no scratch store behind" "" "$(ls -A "$P/tmpd")"

t_section "genuinely unmerged work stays absent"
g checkout -qb genuinely-unmerged main
printf 'c\n' > "$R/c"; g add -A; g commit -qm c
g checkout -q main
say genuinely-unmerged absent "unmerged work"

t_section "partially merged: two commits in, one still out"
g checkout -qb partial "$BASE0"
printf 'd1\n' > "$R/d"; g add -A; g commit -qm d1
printf 'd2\n' >> "$R/d"; g commit -qam d2
g checkout -q main; g merge -q --squash partial >/dev/null 2>&1; g commit -qm "squash: partial"
say partial merged "premise: the fully merged state"
g checkout -q partial; printf 'd3-NOT-MERGED\n' >> "$R/d"; g commit -qam d3
g checkout -q main
say partial absent "a commit added after the squash merge"

t_section "a real merge, and the ref that is base"
g checkout -qb real-merge main
printf 'e\n' > "$R/e"; g add -A; g commit -qm e
g checkout -q main; g merge -q --no-ff real-merge -m "real merge" >/dev/null 2>&1
say real-merge merged "an ordinary ancestor"
say main merged "base into itself"

t_section "a rebase merge: new SHAs on main, patch-equivalent commits"
# Main moves first, or the replay reproduces the same SHAs, the branch is an ancestor and
# test 1 answers. Both premises are asserted, not assumed.
g checkout -qb rebased main
printf 'r1\n' > "$R/r1"; g add -A; g commit -qm r1
printf 'r2\n' > "$R/r2"; g add -A; g commit -qm r2
g checkout -q main
printf 'pre\n' > "$R/pre"; g add -A; g commit -qm "main moved on before the rebase landed"
BEFORE="$(g rev-parse main)"; g cherry-pick rebased~1 rebased >/dev/null 2>&1
t_eq "premise: two commits were replayed onto main" 2 "$(g rev-list --count "$BEFORE..main")"
t_exit "premise: the branch is not an ancestor of main" 1 g merge-base --is-ancestor rebased main
say rebased merged "a rebase-merged branch (test 3)"

t_section "identical content arriving by some other route"
g checkout -qb hand-applied "$BASE0"
g checkout -q main -- . 2>/dev/null || true
g add -A; g commit -qm "identical to main" 2>/dev/null || g commit -qm "identical" --allow-empty
say hand-applied merged "a tree identical to base"

t_section "the unknowns fail toward absent"
say no-such-branch-here absent "a nonexistent ref"
g checkout -q --orphan orphan-history 2>/dev/null
printf 'z\n' > "$R/z"; g add -A; g commit -qm orphan
g checkout -q main
say orphan-history absent "unrelated histories"

t_section "a git that FAILS is an unknown, not a verdict (harbor#226)"
# The shim fails ONE named subcommand and execs the real git for the rest: a blanket break
# only trips the tool's rev-parse guard and never reaches tests 3 and 4.
SHIMD="$P/shim"; mkdir -p "$SHIMD"; REALGIT="$(command -v git)"
shim() { # <subcommand>… — a git that exits 128 for these, real for everything else
  { printf '#!/bin/sh\n'
    for _s in "$@"; do printf 'for a in "$@"; do [ "$a" = %s ] && exit 128; done\n' "$_s"; done
    printf 'exec %s "$@"\n' "$REALGIT"
  } > "$SHIMD/git"; chmod +x "$SHIMD/git"
}
shimmed() { PATH="$SHIMD:$PATH" sh "${2:-$TOOL}" --repo "$R" main "$1" 2>/dev/null | awk '{print $1; exit}'; }
shim nothing-is-broken-here
t_eq "a shim breaking nothing keeps unmerged absent" absent "$(shimmed genuinely-unmerged)"
t_eq "a shim breaking nothing keeps a squash merged" merged "$(shimmed three-commits)"
shim cherry
t_eq "a failed git cherry does not reach merged" absent "$(shimmed genuinely-unmerged)"
t_eq "…and the fallthrough still answers for a real squash" merged "$(shimmed three-commits)"
shim cherry patch-id
t_eq "a failed git patch-id does not reach merged" absent "$(shimmed genuinely-unmerged)"
shim cherry diff
t_eq "a failed git diff does not reach merged" absent "$(shimmed genuinely-unmerged)"
MB="$(g merge-base main three-commits)"
DIRECT="$(g diff "$MB..three-commits" | git patch-id --stable 2>/dev/null | awk '{print $1; exit}')"
VIAVAR="$(printf '%s\n' "$(g diff "$MB..three-commits")" | git patch-id --stable 2>/dev/null | awk '{print $1; exit}')"
t_eq "the direct diff has a patch-id" yes "$(yn [ -n "$DIRECT" ])"
t_eq "a diff captured in a variable keeps its patch-id" "$DIRECT" "$VIAVAR"
# The pre-226 mutant puts both `|| true` readings back; every broken-git arm must flip to merged.
cp "$T_ROOT/bin/log-lib.sh" "$P/"  # the mutants are copies beside it, and the tool sources it from its own dir
MUT3="$P/pre-226.sh"
sed -e 's/^  if _cherry="\$(_git cherry "\$BASE" "\$REF")"; then$/  _cherry="$(_git cherry "$BASE" "$REF" || true)"; if true; then/' \
    -e 's/^  if _bd="\$(_git diff "\$MB\.\.\$REF")"; then$/  _bd="$(_git diff "$MB..$REF" || true)"; if true; then/' \
    -e 's/^  if \[ -z "\$_bp" \]; then$/  if false; then/' "$TOOL" > "$MUT3"
t_exit "the pre-226 mutant parses" 0 sh -n "$MUT3"
t_exit "the pre-226 mutant differs from the tool" 1 cmp -s "$MUT3" "$TOOL"
FLIPPED=0
for br in cherry "cherry patch-id" "cherry diff"; do
  shim $br
  [ "$(shimmed genuinely-unmerged "$MUT3")" = merged ] && FLIPPED=$((FLIPPED + 1))
done
t_eq "the pre-226 mutant flips all three broken-git arms" 3 "$FLIPPED"
g worktree add -q "$P/wt-unmerged" genuinely-unmerged 2>/dev/null
shim cherry
GC="$(HARBOR_ROOT="$R" HARBOR_BASE=main PATH="$SHIMD:$PATH" sh "$T_ROOT/bin/worktree.sh" gc 2>/dev/null)"
t_has "worktree gc reports on the fixture worktree" "$GC" 'wt-unmerged'
t_eq "worktree gc keeps unmerged work when git cherry fails" 0 "$(printf '%s\n' "$GC" | grep -c 'would remove.*wt-unmerged')"
shim nothing-is-broken-here

t_section "test 5 and its scratch store are load-bearing (harbor#634)"
MUT5="$P/no-test-5.sh"
sed 's/^  if _noop_merge "\$REF"; then$/  if false; then/' "$TOOL" > "$MUT5"
t_exit "the no-test-5 mutant parses" 0 sh -n "$MUT5"
t_exit "the no-test-5 mutant differs from the tool" 1 cmp -s "$MUT5" "$TOOL"
t_eq "with test 5 deleted, ctx-late reads absent" absent "$(sh "$MUT5" --repo "$R" main ctx-late 2>/dev/null | awk '{print $1; exit}')"
MUTS="$P/no-scratch.sh"
sed 's/GIT_OBJECT_DIRECTORY="\$SCRATCH" GIT_ALTERNATE_OBJECT_DIRECTORIES="\$ODIR" \\$/\\/' "$TOOL" > "$MUTS"
t_exit "the no-scratch mutant parses" 0 sh -n "$MUTS"
t_exit "the no-scratch mutant differs from the tool" 1 cmp -s "$MUTS" "$TOOL"
O0="$(objs)"; sh "$MUTS" --repo "$R" main ctx-unmerged >/dev/null 2>&1
t_eq "without the scratch store merge-tree writes objects (so the no-writes case can fail)" yes "$(yn [ "$(objs)" -gt "$O0" ])"
shim merge-tree
t_eq "a failed git merge-tree reads absent" absent "$(shimmed ctx-late)"
shim nothing-is-broken-here

t_section "the batch contract: one call, one line per ref, order kept"
OUT="$(sh "$TOOL" --repo "$R" main three-commits genuinely-unmerged one-commit 2>/dev/null)"
t_eq "one line per ref" 3 "$(printf '%s\n' "$OUT" | grep -c .)"
t_eq "the first line is the first ref" three-commits "$(printf '%s\n' "$OUT" | awk 'NR==1{print $2}')"
t_eq "batch verdicts agree with the per-ref calls" 2 "$(printf '%s\n' "$OUT" | awk '$1=="merged"' | grep -c .)"

t_section "usage errors are told apart from verdicts"
t_exit "a missing base ref" 2 sh "$TOOL" --repo "$R" no-such-base three-commits
t_exit "a non-repository" 2 sh "$TOOL" --repo "$P/not-a-repo" main x
t_exit "a bare invocation prints usage" 0 sh "$TOOL"
t_exit "a classification exits 0" 0 sh "$TOOL" --repo "$R" main three-commits

t_section "the arms above can fail"
MUT="$P/always.sh"
always() { printf '#!/usr/bin/env sh\nshift 2\nfor r in "$@"; do printf "%s %%s\\n" "$r"; done\n' "$1" > "$MUT"; }
count() { _w="$1"; shift; _n=0; for ref in "$@"; do [ "$(shimmed "$ref" "$MUT")" = "$_w" ] && _n=$((_n + 1)); done; echo "$_n"; }
always merged
t_eq "an always-merged tool flips all four absent arms" 4 "$(count merged genuinely-unmerged partial no-such-branch-here orphan-history)"
always absent
t_eq "an always-absent tool flips all six merged arms" 6 "$(count absent one-commit three-commits real-merge rebased hand-applied main)"

t_section "the three consumers ask this tool, not ancestry (harbor#213)"
for c in worktree.sh govern-hook.sh install-stamp.sh; do
  t_has "$c consults merged-check.sh" "$(cat "$T_ROOT/bin/$c")" 'merged-check.sh'
done
t_hasnt "worktree.sh is_merged() does not decide by ancestry" \
  "$(awk '/^is_merged\(\)/,/^}/' "$T_ROOT/bin/worktree.sh" | grep -v '^[[:space:]]*#')" 'is-ancestor'
t_has "install-stamp's refusal names the content check" "$(cat "$T_ROOT/bin/install-stamp.sh")" 'content check'
t_done
