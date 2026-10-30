#!/usr/bin/env sh
# admission-destroy.sh (harbor#1290): a discarding git command first snapshots the worktree it acts on to
# refs/snapshots/, then runs exactly as before; a branch switch takes none; a failure never refuses.
set -u
. "$(dirname "$0")/../../lib/core.sh"
t_init

G="$T_ROOT/bin/admission-destroy.sh"
GI="-c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false -c init.defaultBranch=main"

# _guard <cwd|-> <command> — runs the guard on a Bash payload; sets OUT, ERR, RC. `-` sends no .cwd.
_guard() {
  if [ "$1" = - ]; then jq -n --arg c "$2" '{tool_name:"Bash",tool_input:{command:$c}}'
  else jq -n --arg c "$2" --arg d "$1" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}'; fi > "$T_TMP/payload"
  sh "$G" < "$T_TMP/payload" > "$T_TMP/out" 2> "$T_TMP/err"; RC=$?
  OUT="$(cat "$T_TMP/out")"; ERR="$(cat "$T_TMP/err")"
}
_n()    { git -C "$1" for-each-ref refs/snapshots/ | wc -l | tr -d ' '; }                     # snapshots in <repo>
_last() { git -C "$1" for-each-ref --sort=-refname --count=1 --format='%(refname)' refs/snapshots/; }
_decision() { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null; }

# _repo <dir> — a, s committed on main, a branch `other`, *.log ignored.
_repo() {
  mkdir -p "$1" && git $GI -C "$1" init -q
  printf 'one\n' > "$1/a.txt"; printf 'base\n' > "$1/s.txt"; printf '*.log\n' > "$1/.gitignore"
  git $GI -C "$1" add -A && git $GI -C "$1" commit -qm init && git $GI -C "$1" branch other
}
# _dirty <dir> — an unstaged edit, a staged edit, an untracked file and an ignored one.
_dirty() {
  printf 'two\n' > "$1/a.txt"; printf 'staged\n' > "$1/s.txt"; git -C "$1" add s.txt
  printf 'new\n' > "$1/u.txt"; printf 'noise\n' > "$1/x.log"
}

R="$T_TMP/r1"; _repo "$R"; _dirty "$R"
P="$T_TMP/plain"; mkdir -p "$P"

t_section "a pathspec checkout leaves a snapshot holding the discarded edit"
_ib="$(cksum < "$R/.git/index")"
_guard "$R" "git checkout -- a.txt"
t_eq "exit" 0 "$RC"
t_eq "no prompt, no refusal" "" "$OUT"
t_eq "said nothing" "" "$ERR"
t_eq "one snapshot" 1 "$(_n "$R")"
S="$(_last "$R")"
t_eq "the discarded edit" two "$(git -C "$R" show "$S:a.txt" 2>&1)"
t_eq "the staged edit, as it is in the worktree" staged "$(git -C "$R" show "$S:s.txt" 2>&1)"
t_eq "an untracked file" new "$(git -C "$R" show "$S:u.txt" 2>&1)"
t_exit "no ignored file" 128 git -C "$R" cat-file -e "$S:x.log"
t_eq "parent is HEAD" "$(git -C "$R" rev-parse HEAD)" "$(git -C "$R" rev-parse "$S^")"
t_eq "the real index is untouched" "$_ib" "$(cksum < "$R/.git/index")"
t_eq "what is staged stays staged" s.txt "$(git -C "$R" diff --cached --name-only)"
case "$S" in refs/snapshots/[0-9]*-[0-9]*) t_pass ;; *) t_fail "ref name is refs/snapshots/<epoch>-<pid> (got $S)" ;; esac
# The command then runs as it would have, and the documented recovery brings the edit back.
git -C "$R" checkout -q -- a.txt
t_eq "the discard ran" one "$(cat "$R/a.txt")"
git -C "$R" restore --source="${S#refs/}" -- a.txt
t_eq "recovery: git restore --source=snapshots/<id> -- <path>" two "$(cat "$R/a.txt")"

t_section "a racy same-size edit is seen, as git itself sees it"
# Entry, file and index all stamped one instant: git must rehash, so only an index copy that keeps its mtime sees "two".
RR="$T_TMP/racy"; _repo "$RR"
git -C "$RR" config core.trustctime false   # else the ctime the edit moved gives it away
touch -t 202001010000 "$RR/a.txt"; git -C "$RR" add a.txt; printf 'two\n' > "$RR/a.txt"
touch -t 202001010000 "$RR/a.txt" "$RR/.git/index"
_guard "$RR" "git checkout -- a.txt"
t_eq "the racy edit is in the snapshot" two "$(git -C "$RR" show "$(_last "$RR"):a.txt" 2>&1)"

t_section "deletions, odd names, a subfolder and a linked worktree"
RE="$T_TMP/edge"; _repo "$RE"; mkdir -p "$RE/sub"
rm "$RE/s.txt"; printf 'odd\n' > "$RE/sub/we[ir]d *.txt"; printf 'two\n' > "$RE/a.txt"
_guard "$RE/sub" "git checkout -- ../a.txt"
S="$(_last "$RE")"
t_exit "a deleted file is deleted in it" 128 git -C "$RE" cat-file -e "$S:s.txt"
t_eq "an untracked name with glob characters" odd "$(git -C "$RE" show "$S:sub/we[ir]d *.txt" 2>&1)"
t_eq "from a subfolder, the whole worktree" two "$(git -C "$RE" show "$S:a.txt" 2>&1)"
git -C "$RE" worktree add -q "$T_TMP/edge-wt" other 2>/dev/null
printf 'wt-edit\n' > "$T_TMP/edge-wt/a.txt"
_b="$(_n "$RE")"; _guard "$T_TMP/edge-wt" "git restore a.txt"
t_eq "a linked worktree: one snapshot, seen from the main checkout" "$((_b + 1))" "$(_n "$RE")"
_w="$(git -C "$RE" for-each-ref --format='%(refname)' refs/snapshots/ | grep -vxF "$S")"   # the one that is not $S
t_eq "a linked worktree: its own edit" wt-edit "$(git -C "$RE" show "$_w:a.txt" 2>&1)"
t_eq "a linked worktree: the main index untouched" "" "$(git -C "$RE" diff --cached --name-only)"

t_section "a branch switch takes no snapshot"
_b="$(_n "$R")"
for _c in "git checkout other" "git switch other" "git checkout -b newbranch" "git checkout -" \
          "git switch -c x2" "git checkout --detach HEAD" "git checkout other --" "git status"; do
  _guard "$R" "$_c"
  t_eq "$_c: allowed" "0:" "$RC:$OUT"
  t_eq "$_c: no snapshot" "$_b" "$(_n "$R")"
done

t_section "every discard form takes one"
for _c in "git restore a.txt" "git checkout a.txt" "git checkout ." "git checkout -f other" "git checkout HEAD a.txt" \
          "git switch -f other" "git switch --discard-changes other" "git restore -W -S a.txt" \
          "git checkout --ours a.txt" "git -c core.x=1 --no-pager checkout -- a.txt" \
          "sh -c 'git restore a.txt'" "unbuffer git restore a.txt" "gtimeout 5 git checkout -- a.txt" "GIT""x=1 git restore a.txt"; do
  _b="$(_n "$R")"; _guard "$R" "$_c"
  t_eq "$_c: allowed silently" "0::" "$RC:$OUT:$ERR"
  t_eq "$_c: one snapshot" "$((_b + 1))" "$(_n "$R")"
done
for _c in "git reset --hard" "git clean -fd"; do
  _b="$(_n "$R")"; _guard "$R" "$_c"
  t_eq "$_c keeps its ask" ask "$(_decision)"
  t_eq "$_c: one snapshot" "$((_b + 1))" "$(_n "$R")"
done
for _c in "git restore --staged a.txt" "git clean -n" "git clean -fn" "git reset --soft HEAD" "git stash"; do
  _b="$(_n "$R")"; _guard "$R" "$_c"
  t_eq "$_c: not a discard" "$_b" "$(_n "$R")"
done
_b="$(_n "$R")"; _guard "$R" "git -C $T_TMP/nowhere-dir reset --hard"
t_eq "a -C into no repository: allowed at the same ask" ask "$(_decision)"
t_eq "a -C into no repository: no snapshot here" "$_b" "$(_n "$R")"

t_section "the worktree the command acts on, never the guard's own"
R2="$T_TMP/r2"; _repo "$R2"; _dirty "$R2"
R3="$T_TMP/r3"; _repo "$R3"; _dirty "$R3"
_guard "$P" "git -C $R2 checkout -- a.txt"
t_eq "-C from a plain folder" 1 "$(_n "$R2")"
_guard "$P" "cd $R2 && git restore a.txt"
t_eq "cd then git" 2 "$(_n "$R2")"
_guard "$T_TMP" "git -C r2 restore a.txt"
t_eq "a relative -C" 3 "$(_n "$R2")"
_guard "$R3" "git -C $R2 restore a.txt"
t_eq "-C away from a dirty cwd: the target" 4 "$(_n "$R2")"
t_eq "-C away from a dirty cwd: not the cwd" 0 "$(_n "$R3")"
_guard "$R3" "cd $R2; git checkout -- a.txt; cd $R3; git restore a.txt"
t_eq "two repos in one call: the first" 5 "$(_n "$R2")"
t_eq "two repos in one call: the second" 1 "$(_n "$R3")"
_guard "$R3" "git restore a.txt && git checkout -- a.txt"
t_eq "one repo twice in one call: one snapshot" 2 "$(_n "$R3")"
t_eq "one repo twice in one call: said nothing" "" "$ERR"
_guard "$R2/sub-does-not-matter" "git -C $R2 restore a.txt"
t_eq "an absolute -C beats an unknown cwd" 6 "$(_n "$R2")"
_guard - "git restore a.txt; git checkout -- a.txt"   # two blind discards, one line
t_eq "no .cwd: allowed" "0:" "$RC:$OUT"
t_has "no .cwd: said once" "$ERR" "[check:admission.destroy-snapshot]"
t_eq "no .cwd: one line for two discards" 1 "$(printf '%s\n' "$ERR" | grep -c 'check:admission.destroy-snapshot')"
_guard "$R3" 'cd "$(mktemp -d)" && git restore a.txt'
t_has "an unresolvable cd: said" "$ERR" "nothing was snapshotted"
t_eq "an unresolvable cd: no snapshot in the cwd" 2 "$(_n "$R3")"
for _c in "GIT_DIR=$R3/.git git restore a.txt" "git --git-dir=$R3/.git restore a.txt" "git --work-tree $R3 restore a.txt"; do
  _guard "$R3" "$_c"
  t_eq "$_c: allowed" "0:" "$RC:$OUT"
  t_has "$_c: said, not guessed" "$ERR" "nothing was snapshotted"
  t_eq "$_c: no snapshot" 2 "$(_n "$R3")"
done
printf 'echo hi\ncat > note.txt <<EOF\ngit checkout -- a.txt\nEOF\n' > "$T_TMP/hd.cmd"
_guard "$R3" "$(cat "$T_TMP/hd.cmd")"
t_eq "a heredoc body is not a discard" 2 "$(_n "$R3")"

t_section "a clean tree takes none, so nothing piles up"
R4="$T_TMP/r4"; _repo "$R4"
_guard "$R4" "git checkout -- a.txt"
t_eq "clean tree: allowed" "0:" "$RC:$OUT"
t_eq "clean tree: no snapshot" 0 "$(_n "$R4")"
printf 'x\n' > "$R4/x.log"; _guard "$R4" "git checkout -- a.txt"
t_eq "only ignored files: no snapshot" 0 "$(_n "$R4")"
# Expiry: older than 7 days goes when the next is written; younger stays.
_old="$(GIT_COMMITTER_DATE="$(( $(date +%s) - 8 * 86400 )) +0000" git $GI -C "$R4" commit-tree -m old 'HEAD^{tree}')"
_new="$(GIT_COMMITTER_DATE="$(( $(date +%s) - 6 * 86400 )) +0000" git $GI -C "$R4" commit-tree -m recent 'HEAD^{tree}')"
git -C "$R4" update-ref refs/snapshots/1-old "$_old"; git -C "$R4" update-ref refs/snapshots/2-recent "$_new"
printf 'edit\n' > "$R4/a.txt"; _guard "$R4" "git restore a.txt"
t_exit "an 8-day-old snapshot is dropped" 1 git -C "$R4" rev-parse -q --verify refs/snapshots/1-old
t_exit "a 6-day-old snapshot is kept" 0 git -C "$R4" rev-parse -q --verify refs/snapshots/2-recent
t_eq "and the new one is written" 2 "$(_n "$R4")"
touch "$R4/.git/harbor-snapshot-off"
_guard "$R4" "git restore a.txt"
t_eq "<common dir>/harbor-snapshot-off: none" 2 "$(_n "$R4")"
rm "$R4/.git/harbor-snapshot-off"

t_section "a non-repository cwd and an unwritable repository still allow the command"
_guard "$P" "git checkout -- a.txt"
t_eq "plain folder: allowed, silent" "0::" "$RC:$OUT:$ERR"
R6="$T_TMP/r6"; _repo "$R6"; _dirty "$R6"
chmod -R a-w "$R6/.git"
if [ -w "$R6/.git/objects" ]; then  # root ignores modes: make the index copy fail instead
  chmod -R u+w "$R6/.git"; mv "$R6/.git/index" "$R6/.git/index.real"; mkdir "$R6/.git/index"
fi
_guard "$R6" "git checkout -- a.txt"
t_eq "unwritable: allowed" "0:" "$RC:$OUT"
t_has "unwritable: said" "$ERR" "[check:admission.destroy-snapshot]"
t_has "unwritable: says it runs unprotected" "$ERR" "runs unprotected"
t_eq "unwritable: one line" 1 "$(printf '%s\n' "$ERR" | grep -c .)"
_guard "$R6" "git reset --hard"
t_eq "unwritable: reset --hard keeps its ask" ask "$(_decision)"
chmod -R u+w "$R6/.git"
t_eq "unwritable: no snapshot" 0 "$(_n "$R6")"

t_section "a push never publishes refs/snapshots"
# R has snapshots; R4's were made with no remote. A bare origin keeps git happy if anything ran.
git -C "$R" remote add origin "$T_TMP/origin.git" 2>/dev/null
for _c in "git push --mirror origin" "git push origin refs/*:refs/*" "git push origin +refs/snapshots/*:refs/snapshots/*" "git push origin snapshots/1-x:refs/heads/x" \
          "git -C $R push --mirror"; do
  _guard "$R" "$_c"; t_eq "$_c: denied" deny "$(_decision)"
done
t_has "the reason names the remedy" "$OUT" "update-ref --stdin"
for _c in "git push origin main" "git push -u origin HEAD" "git push --tags origin" "git push --all origin"; do
  _guard "$R" "$_c"; t_eq "$_c: allowed" "0:" "$RC:$OUT"
done
_guard "$P" "git push --mirror origin"
t_eq "no snapshots in the repo: --mirror allowed" "0:" "$RC:$OUT"
_guard - "git push --mirror origin"
t_eq "unknown repo: --mirror denied" deny "$(_decision)"
git -C "$R" config remote.origin.mirror true
_guard "$R" "git push"
t_eq "a remote configured to mirror: denied" deny "$(_decision)"
git -C "$R" config --unset remote.origin.mirror
git -C "$R" config remote.origin.push 'refs/*:refs/*'
_guard "$R" "git push origin"
t_eq "a remote whose push refspec is refs/*: denied" deny "$(_decision)"
git -C "$R" config --unset remote.origin.push
_guard "$R" "git push origin"
t_eq "the same remote, ordinary: allowed" "0:" "$RC:$OUT"

t_done
