#!/usr/bin/env sh
# hooks/post-commit and hooks/post-merge (harbor#1043, PR 2): driven by REAL git in a scratch repo
# whose core.hooksPath is this checkout's hooks/, which is how the box wires them. A commit puts
# git.commit on the bus with the new sha; a merge puts git.merge with the sha HEAD ends at; a squash
# merge moves nothing and emits nothing; and git never sees a producer fail.
. "$(dirname "$0")/../../lib/core.sh"; t_init
BUS="$T_TMP/bus"; export HARBOR_EVENT_DIR="$BUS"
HOOKS="$T_ROOT/hooks"
R="$T_TMP/work/scratch-repo"; mkdir -p "$R"
git() { command git -c user.name=t -c user.email=t@t.invalid -c commit.gpgsign=false -c init.defaultBranch=main "$@"; }
g() { git -C "$R" "$@"; }
lines() { cat "$BUS"/*.jsonl 2>/dev/null; }
kinds() { lines | jq -r '"\(.kind) \(.subject)"' | tr '\n' ';'; }

g init -q
g config core.hooksPath "$HOOKS"

t_section "a commit emits git.commit, subject = the new sha"
printf a > "$R/a"; g add a
out="$(g commit -q -m "first" 2>&1)"; rc=$?
t_eq "git commit exits 0" 0 "$rc"
t_eq "...and git printed nothing the hook added" "" "$out"
sha1="$(g rev-parse HEAD)"
t_eq "one event: git.commit <sha>" "git.commit $sha1;" "$(kinds)"
t_eq "src is git.post-commit, data is empty" "git.post-commit {}" "$(lines | jq -r '"\(.src) \(.data | tojson)"')"
t_eq "repo is the repo's name" scratch-repo "$(lines | jq -r .repo)"
t_eq "the subject is a full sha" yes "$(lines | jq -r .subject | grep -Eq '^[0-9a-f]{40}$' && echo yes || echo no)"
printf b >> "$R/a"; g add a; g commit -q -m "second"; sha2="$(g rev-parse HEAD)"
g commit -q --amend -m "second, amended"; sha2b="$(g rev-parse HEAD)"
t_eq "each commit and the amend is its own event, in order" "git.commit $sha1;git.commit $sha2;git.commit $sha2b;" "$(kinds)"
t_hasnt "no commit message is in the bus" "$(lines)" "amended"
g checkout -q -b cp-src; printf c > "$R/c"; g add c; g commit -q -m "cp"; csrc="$(g rev-parse HEAD)"; g checkout -q main
rm -rf "$BUS"; g cherry-pick "$csrc" >/dev/null 2>&1; csha="$(g rev-parse HEAD)"
t_eq "a cherry-pick is a commit: git.commit at its new sha" "git.commit $csha;" "$(kinds)"
g reset -q --hard "$sha2b"

t_section "a merge emits git.merge, subject = the sha HEAD is at afterwards"
g checkout -q -b side; printf s > "$R/s"; g add s; g commit -q -m "side"
g checkout -q main; printf m > "$R/m"; g add m; g commit -q -m "main moves"
rm -rf "$BUS"
out="$(g merge --no-ff -q side -m "merge side" 2>&1)"; rc=$?
t_eq "git merge exits 0" 0 "$rc"
msha="$(g rev-parse HEAD)"
# Measured: git runs post-merge for a merge commit and NOT post-commit, so it is one event, git.merge.
t_eq "one event: git.merge <the merge commit>" "git.merge $msha;" "$(kinds)"
t_eq "...from git.post-merge" git.post-merge "$(lines | jq -r 'select(.kind == "git.merge") | .src')"
rm -rf "$BUS"
g checkout -q -b ff-side; printf f > "$R/f"; g add f; g commit -q -m "ff"; fsha="$(g rev-parse HEAD)"
rm -rf "$BUS"; g checkout -q main; g reset -q --hard HEAD
git -C "$R" merge -q ff-side 2>&1
t_eq "a fast-forward emits git.merge at the new tip" "git.merge $fsha;" "$(kinds)"

t_section "a squash merge moves nothing and emits no git.merge"
g checkout -q -b sq; printf q > "$R/q"; g add q; g commit -q -m "sq"
g checkout -q main; rm -rf "$BUS"; before="$(g rev-parse HEAD)"
g merge --squash -q sq >/dev/null 2>&1; rc=$?
t_eq "git merge --squash exits 0" 0 "$rc"
t_eq "HEAD did not move" "$before" "$(g rev-parse HEAD)"
t_eq "no event" 0 "$(lines | grep -c .)"

t_section "a worktree reports its repo, not its own directory"
g worktree add -q "$T_TMP/work/the-linked-tree" -b wt-branch 2>/dev/null
rm -rf "$BUS"; printf w > "$T_TMP/work/the-linked-tree/w"; git -C "$T_TMP/work/the-linked-tree" add w
git -C "$T_TMP/work/the-linked-tree" commit -q -m "in the worktree"
t_eq "repo is scratch-repo" scratch-repo "$(lines | jq -r .repo)"

t_section "a rebase or cherry-pick sequence replays commits without emitting (harbor#1114 finding 3)"
# A replayed commit is a rewrite of one that has its event already. Real git, real rebases, in the
# main tree and in a linked worktree (where the state dir is .git/worktrees/<n>/, not .git/).
g checkout -q main; g reset -q --hard HEAD
mk_topic() { # <repo dir> <branch> <n> <file prefix> — a branch of N one-file commits off main's current tip
  git -C "$1" checkout -q -b "$2"
  _i=1; while [ "$_i" -le "$3" ]; do printf '%s' "$_i" > "$1/$4$_i"; git -C "$1" add "$4$_i"; git -C "$1" commit -q -m "$4$_i"; _i=$((_i + 1)); done; }
mk_topic "$R" rb-topic 6 rb
g checkout -q main; printf x > "$R/rb-main"; g add rb-main; g commit -q -m "main moves for the rebase"
g checkout -q rb-topic
rm -rf "$BUS"; out="$(g rebase main 2>&1)"; rc=$?
t_eq "a 6-commit rebase exits 0" 0 "$rc"
t_eq "...and rewrote 6 commits (the topic really was replayed)" 6 "$(g rev-list --count main..rb-topic)"
t_eq "...and emitted no git.commit" 0 "$(lines | grep -c . || :)"
printf n > "$R/after-rebase"; g add after-rebase; g commit -q -m "after the rebase"; nsha="$(g rev-parse HEAD)"
t_eq "the next ordinary commit emits again (the state is gone)" "git.commit $nsha;" "$(kinds)"

# the same in a linked worktree
WT="$T_TMP/work/rebase-wt"
g checkout -q main; g worktree add -q "$WT" -b wt-topic main 2>/dev/null
mk_topic "$WT" wt-topic-x 5 wt 2>/dev/null || { git -C "$WT" checkout -q -b wt-topic-x; }
g checkout -q main; printf y > "$R/wt-main"; g add wt-main; g commit -q -m "main moves again"
rm -rf "$BUS"; git -C "$WT" rebase main >/dev/null 2>&1; rc=$?
t_eq "a rebase inside a linked worktree exits 0" 0 "$rc"
t_eq "...replayed commits there (wt-topic-x is 5 ahead of main)" 5 "$(g rev-list --count main..wt-topic-x)"
t_eq "...emitted no git.commit (the guard reads that worktree's own state dir)" 0 "$(lines | grep -c . || :)"
printf z > "$WT/wt-after"; git -C "$WT" add wt-after; git -C "$WT" commit -q -m "after, in the worktree"
t_eq "...and the worktree's next commit emits" 1 "$(lines | grep -c . || :)"

# a rebase that stops on a conflict: the commit the operator makes to finish it is part of the replay
g checkout -q main; printf one > "$R/cf"; g add cf; g commit -q -m "cf base"
g checkout -q -b cf-topic; printf two > "$R/cf"; g add cf; g commit -q -m "cf topic"
g checkout -q main; printf three > "$R/cf"; g add cf; g commit -q -m "cf main"
g checkout -q cf-topic; rm -rf "$BUS"
g rebase main >/dev/null 2>&1; printf resolved > "$R/cf"; g add cf
GIT_EDITOR=true g rebase --continue >/dev/null 2>&1
t_eq "a conflicted rebase, resolved and continued, emitted no git.commit" 0 "$(lines | grep -c . || :)"
t_eq "...and the rebase finished" no "$([ -e "$(g rev-parse --git-path rebase-merge)" ] && echo yes || echo no)"

# a multi-commit cherry-pick runs through the sequencer; a single one is a plain new commit (tested above)
g checkout -q main; mk_topic "$R" seq-src 3 cpm; g checkout -q main
rm -rf "$BUS"; g cherry-pick seq-src~3..seq-src >"$T_TMP/cpo" 2>&1; rc=$?
t_eq "a 3-commit cherry-pick exits 0" 0 "$rc"
t_eq "...landed 3 commits on main" 3 "$(g log --format=%s -3 | grep -c '^cpm')"
t_eq "...and emitted no git.commit" 0 "$(lines | grep -c . || :)"

t_section "a producer that cannot work never breaks git"
printf x > "$R/x"; g add x
rm -rf "$BUS"; : > "$BUS"   # the bus dir is a FILE: nothing can be written under it
g commit -q -m "bus is a file" >"$T_TMP/o" 2>"$T_TMP/e"; rc=$?
t_eq "the commit still exits 0" 0 "$rc"
t_eq "...printing nothing" "" "$(cat "$T_TMP/o")$(cat "$T_TMP/e")"
t_eq "...and the commit exists" "bus is a file" "$(g log -1 --format=%s)"
rm -f "$BUS"
# A hooks dir that was copied without its bus (a foreign repo pointing core.hooksPath at it).
FH="$T_TMP/foreign/hooks"; mkdir -p "$FH" "$T_TMP/foreign/bin"; cp "$HOOKS/lib.sh" "$HOOKS/post-commit" "$HOOKS/post-merge" "$FH/"
g config core.hooksPath "$FH"; printf y > "$R/y"; g add y
g commit -q -m "no bus beside the hooks" >"$T_TMP/o" 2>"$T_TMP/e"; rc=$?
t_eq "no bin/event-bus.sh beside hooks/: exit 0" 0 "$rc"
t_eq "...nothing printed, nothing emitted" "0 " "$(lines | grep -c .) $(cat "$T_TMP/o")$(cat "$T_TMP/e")"
rm -f "$FH/lib.sh"; printf z > "$R/z"; g add z
g commit -q -m "no lib" >"$T_TMP/o" 2>"$T_TMP/e"; rc=$?
t_eq "no lib.sh beside the hook: exit 0, nothing printed" "0 " "$rc $(cat "$T_TMP/o")$(cat "$T_TMP/e")"
t_done
