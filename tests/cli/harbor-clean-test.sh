#!/usr/bin/env sh
# harbor-clean: mostly REFUSALS. Every KEEP class is planted, --apply runs, and the plant must survive (harbor#456, #724).
# The box is $T_TMP/box, never the sandbox HOME; the D2 gate is aimed at the sandbox HOME's .claude.
# Scratch, cache and gh are pinned, and the GitHub layer answers from a recorded gh stub.
. "$(dirname "$0")/../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/harbor-clean.sh"
H="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)/box"; CFG="$H/.claude"; SCR="$T_TMP/scratch"
mkdir -p "$CFG" "$SCR"
export HARBOR_CLEAN_SCRATCH="$SCR" HARBOR_CACHE_DIR="$CFG/cache" HARBOR_CLEAN_GH=none
run()   { HARBOR_CLEAN_HOME="$H" CLAUDE_CONFIG_DIR="$CFG" sh "$TOOL" "$@" 2>&1; }
apply() { HARBOR_CLEAN_HOME="$H" CLAUDE_CONFIG_DIR="$CFG" sh "$TOOL" --apply "$@" >/dev/null 2>&1; }
with()  { env HARBOR_CLEAN_HOME="$H" CLAUDE_CONFIG_DIR="$CFG" "$@" 2>&1; }  # never `VAR=x fn`: it persists under sh
there() { if [ -e "$1" ]; then echo present; else echo gone; fi; }

# Sacred: each must survive --apply with its content intact.
mkdir -p "$CFG/security/agent-sdk-venv" "$CFG/.helm-replay" "$CFG/backups" "$CFG/MEMORY" "$CFG/projects" "$CFG/.helm-pins"
printf 'venv\n'    > "$CFG/security/agent-sdk-venv/pyvenv.cfg"
printf 'corpus\n'  > "$CFG/.helm-replay/baseline.tsv"
printf 'backup\n'  > "$CFG/backups/settings.json.20260101"
printf 'note\n'    > "$CFG/MEMORY/IDENTITY.md"
printf 'session\n' > "$CFG/projects/a.jsonl"
printf 'pin\n'     > "$CFG/.helm-pins/one"
mkdir -p "$CFG/session-env/empty-a" "$CFG/session-env/empty-b" "$CFG/session-env/busy"
printf 'live\n' > "$CFG/session-env/busy/env"
printf 'old\n' > "$CFG/settings.json.bak.20260729T000000Z"
mkdir -p "$H/actions-runner/_diag" "$H/actions-runner/_work/repo"
printf 'old log\n'   > "$H/actions-runner/_diag/old.log"; touch -t 202601010000 "$H/actions-runner/_diag/old.log"
printf 'fresh log\n' > "$H/actions-runner/_diag/fresh.log"
printf 'checkout\n'  > "$H/actions-runner/_work/repo/file"
printf '<html>\n' > "$H/report.html"

# A repo with a LANDED branch and an unmerged LIVE one, and a real origin/main.
R="$H/proj"; mkdir -p "$R"; git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main
g() { git -C "$R" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
printf 'v1\n' > "$R/f.txt"; g add f.txt; g commit -qm v1
git init -q --bare "$T_TMP/origin.git"; g remote add origin "$T_TMP/origin.git"; g push -q origin main
g branch landed main
g checkout -q -b live main; printf 'v2\n' > "$R/g.txt"; g add g.txt; g commit -qm v2; g checkout -q main
keep() { printf '%s\n' "$1" | grep '^  KEEP '; }  # <report> — its KEEP lines

t_section "0 the override is honoured, so the real box is never the subject"
out="$(run)"
t_has "the report names the fixture home" "$out" "$H"
t_has "a default run announces a dry run" "$out" "DRY RUN"

t_section "1 the default is a dry run"
run >/dev/null
t_eq "an empty session dir survives a plain run" present "$(there "$CFG/session-env/empty-a")"

t_section "2 every sacred path is reported as KEEP"
out="$(run)"
for want in agent-sdk-venv .helm-replay backups MEMORY projects .helm-pins; do
  t_has "sacred path reported as KEEP: $want" "$(keep "$out")" "$want"
done

t_section "3 --apply leaves every sacred path intact"
apply
for f in security/agent-sdk-venv/pyvenv.cfg .helm-replay/baseline.tsv backups/settings.json.20260101 \
         MEMORY/IDENTITY.md projects/a.jsonl .helm-pins/one; do
  t_eq "--apply keeps .claude/$f" present "$(there "$CFG/$f")"
done

t_section "4 a non-empty session dir survives --apply; the empty ones go"
t_eq "the session dir holding state survives" present "$(there "$CFG/session-env/busy/env")"
t_eq "an empty session dir is removed" gone "$(there "$CFG/session-env/empty-a")"

t_section "5 a loose backup is kept, never deleted"
t_eq "--apply keeps the loose backup" present "$(there "$CFG/settings.json.bak.20260729T000000Z")"
t_has "the loose backup is reported" "$(run)" "loose-backups"
. "$T_ROOT/tests/lib/linux-sim.sh"; gnu_stat_stub "$T_TMP/gstat"
gsz() { with PATH="$T_TMP/gstat:$PATH" sh "$TOOL" --json "$1" | jq -r --arg s "$2" 'select(.subject == $s) | .bytes'; }
t_eq "under GNU stat (Linux, harbor#618) a loose deliverable's size is its bytes" 7 "$(gsz loose-deliverables report.html)"
t_eq "...and a loose backup's" 4 "$(gsz loose-backups .claude/settings.json.bak.20260729T000000Z)"

t_section "6 the age floor is real"
t_eq "a log newer than the floor survives" present "$(there "$H/actions-runner/_diag/fresh.log")"
t_eq "a log past the floor is removed" gone "$(there "$H/actions-runner/_diag/old.log")"

t_section "7 runner _work is a checkout, not residue"
t_eq "--apply keeps the _work checkout" present "$(there "$H/actions-runner/_work/repo/file")"
t_has "runner _work is reported as KEEP" "$(keep "$(run)")" "runner-work"

t_section "8 a loose document is kept, and the row says MOVE"
t_eq "--apply keeps the loose document" present "$(there "$H/report.html")"
t_has "the row says to move it" "$(run)" "MOVE, never delete"

t_section "9 the branch predicate discriminates: landed goes, live stays"
t_exit "the unlanded branch survives" 0 git -C "$R" rev-parse --verify live
t_exit "the landed branch is deleted" 128 git -C "$R" rev-parse --verify landed

t_section "10 core.bare on a working checkout is DAMAGE, not deleted"
git -C "$R" config core.bare true
out="$(run)"
t_has "core.bare=true is reported" "$out" "core.bare=true"
t_has "and named as damage" "$out" "DAMAGE, not residue"
apply
t_eq "--apply keeps the damaged repo" present "$(there "$R/.git")"
git -C "$R" config --unset core.bare

t_section "11 a prunable worktree registration is found and pruned"
git -C "$R" worktree add -q "$T_TMP/wt" -b wt-branch main 2>/dev/null; rm -rf "$T_TMP/wt"
t_has "the dead registration is detected" "$(run prunable-worktrees)" "prunable"
apply prunable-worktrees
t_eq "--apply prunes it" 0 "$(git -C "$R" worktree list | grep -c prunable)"

t_section "12 --json emits KEEP rows too"
j="$(run --json)"
t_has "--json carries KEEP rows" "$j" '"verdict":"KEEP"'
if command -v jq >/dev/null 2>&1; then
  t_eq "--json is line-delimited valid JSON" 0 "$(printf '%s\n' "$j" | jq -R 'select(length > 0) | fromjson' >/dev/null 2>&1; echo $?)"
else echo "  SKIP --json line check: no jq on this host"; fi

t_section "13 --list names every class; an unknown flag is a usage error"
t_has "--list names the classes" "$(run --list | tr '\n' ' ')" "landed-branches"
t_exit "an unknown flag exits 2" 2 env HARBOR_CLEAN_HOME="$H" sh "$TOOL" --nonsense

t_section "14 the D2 gate: --apply alone refuses the live config dir"
# Live here is the sandbox HOME's .claude, created so the gate's own dir test cannot pass vacuously.
mkdir -p "$HOME/.claude/session-env/empty-live"
out="$(env -u CLAUDE_CONFIG_DIR HARBOR_CLEAN_HOME="$HOME" sh "$TOOL" --apply 2>&1)"; rc=$?
t_eq "--apply on the live dir exits 1" 1 "$rc"
t_has "the refusal uses D2's house idiom" "$out" "explicit --live"
t_has "and names the flags that would proceed" "$out" "--apply --live"
t_eq "the refused run touched nothing" present "$(there "$HOME/.claude/session-env/empty-live")"
t_has "a dry run of the live dir still reports" "$(env -u CLAUDE_CONFIG_DIR HARBOR_CLEAN_HOME="$HOME" sh "$TOOL" 2>&1)" "DRY RUN"

t_section "15 control: the fixture dir is not the live dir, so --apply needs no --live"
out="$(run --apply session-env)"; rc=$?
t_eq "--apply on a non-live dir exits 0" 0 "$rc"
t_hasnt "and prints no live refusal" "$out" "explicit --live"

# The GitHub layer and the sweep count: every class sits beside a LOOKALIKE that must not count.
command -v jq >/dev/null 2>&1 || { echo "harbor-clean-test: jq absent; the GitHub-layer cases read --json with it" >&2; exit 1; }
NOWS="$(date +%s)"
iso() { date -u -r "$1" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d "@$1" '+%Y-%m-%dT%H:%M:%SZ'; }
ago() { printf '%s' $(( NOWS - $1 * 86400 )); }

GR="$H/widget"; mkdir -p "$GR"; git init -q "$GR"; git -C "$GR" symbolic-ref HEAD refs/heads/main
gg() { git -C "$GR" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
commit() { # <file> <days-ago> — dated for real, because every idle rule reads it
  printf '%s\n' "$1" > "$GR/$1"; gg add "$1"
  GIT_AUTHOR_DATE="$(ago "$2") +0000" GIT_COMMITTER_DATE="$(ago "$2") +0000" gg commit -qm "$1"
  git -C "$GR" rev-parse HEAD
}
printf 'build.log\n' > "$GR/.gitignore"; gg add .gitignore
C0="$(commit base 40)"
git -C "$GR" remote add origin https://github.com/acme/widget.git
git -C "$GR" update-ref refs/remotes/origin/main "$C0"
gg branch landed2 main
gg checkout -q -b merged-clean main;    M1="$(commit m1 20)"
gg checkout -q -b merged-after main;    A1="$(commit a1 20)"; A2="$(commit a2 10)"
gg checkout -q -b open-pr main;         O1="$(commit o1 20)"
gg checkout -q -b lonely main;          commit l1 30 >/dev/null
gg checkout -q -b fresh-local main;     commit f1 0 >/dev/null
gg checkout -q -b pushed-idle main;     P1="$(commit p1 30)"
git -C "$GR" update-ref refs/remotes/origin/pushed-idle "$P1"
gg checkout -q -b wt-done main;         W1="$(commit w1 20)"
gg checkout -q -b wt-dirty main;        D1="$(commit d1 20)"
gg checkout -q -b wt-open main;         E1="$(commit e1 20)"
gg checkout -q -b after-pushed main;    Q1="$(commit q1 20)"; Q2="$(commit q2 10)"
git -C "$GR" update-ref refs/remotes/origin/after-pushed "$Q2"
gg checkout -q -b wt-after-pushed main; R1="$(commit r1 20)"; R2="$(commit r2 10)"
git -C "$GR" update-ref refs/remotes/origin/wt-after-pushed "$R2"
gg checkout -q -b wt-after-local main;  T1="$(commit t1 20)"; commit t2 10 >/dev/null
gg checkout -q main
# `gg`, not bare git: commit-tree needs an author and a runner has no global identity, so N1 came back empty and
# the "behind GitHub" row never existed (harbor#865).
N1="$(gg commit-tree -p "$C0" -m next "$(git -C "$GR" rev-parse 'main^{tree}')")"  # GitHub main moved on
for b in wt-done wt-dirty wt-open wt-after-pushed wt-after-local; do gg worktree add -q "$H/widget-$b" "$b"; done
printf 'unsaved\n' > "$H/widget-wt-dirty/unsaved.txt"
printf 'wip\n' >> "$GR/base"; GIT_COMMITTER_DATE="$(ago 20) +0000" gg stash push -q -m "old wip"
printf 'stray\n' > "$GR/notes.txt"; touch -t 202601010000 "$GR/notes.txt"
printf 'log\n'   > "$GR/build.log"; touch -t 202601010000 "$GR/build.log"

STUB="$T_TMP/stub"; mkdir -p "$STUB"; export STUB
printf '{"defaultBranchRef":{"name":"main"}}\n' > "$STUB/repo.json"
cat > "$STUB/branches.json" <<JSON
[{"name":"main","commit":{"sha":"$N1"}}, {"name":"merged-clean","commit":{"sha":"$M1"}},
 {"name":"merged-moved","commit":{"sha":"$A2"}}, {"name":"open-pr","commit":{"sha":"$O1"}},
 {"name":"no-pr-remote","commit":{"sha":"$P1"}}]
JSON
pr() { printf '{"number":%s,"state":"%s","headRefName":"%s","headRefOid":"%s","updatedAt":"%s"}' "$1" "$2" "$3" "$4" "$(iso "$(ago "$5")")"; }
printf '[%s]\n' "$(pr 22 MERGED wt-after-local "$T1" 9),$(pr 21 MERGED wt-after-pushed "$R1" 9),$(pr 20 MERGED after-pushed "$Q1" 9),\
$(pr 7 MERGED merged-moved "$A1" 9),$(pr 6 OPEN wt-open "$E1" 5),$(pr 5 MERGED wt-dirty "$D1" 9),$(pr 4 MERGED wt-done "$W1" 9),\
$(pr 3 OPEN open-pr "$O1" 3),$(pr 2 MERGED merged-after "$A1" 9),$(pr 1 MERGED merged-clean "$M1" 9)" > "$STUB/prs.json"
cat > "$STUB/open.json" <<JSON
[{"number":8,"headRefName":"brand-new","updatedAt":"$(iso "$NOWS")","isDraft":false,"mergeable":"MERGEABLE","statusCheckRollup":[{"conclusion":"SUCCESS"}]},
 {"number":6,"headRefName":"wt-open","updatedAt":"$(iso "$(ago 5)")","isDraft":false,"mergeable":"MERGEABLE","statusCheckRollup":[{"conclusion":"SUCCESS"},{"conclusion":"FAILURE"}]},
 {"number":3,"headRefName":"open-pr","updatedAt":"$(iso "$(ago 3)")","isDraft":false,"mergeable":"MERGEABLE","statusCheckRollup":[{"conclusion":"SUCCESS"},{"state":"SUCCESS"}]}]
JSON
iss() { printf '{"number":%s,"updatedAt":"%s","body":"%s","subIssuesSummary":{"total":%s,"completed":%s},"closedByPullRequestsReferences":{"nodes":[%s]}}' \
  "$1" "$(iso "$NOWS")" "$2" "$3" "$4" "$5"; }
M='{"state":"MERGED"}'
printf '{"data":{"repository":{"issues":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[%s]}}}}\n' \
  "$(iss 10 '## Done when\n- [x] one\n- [X] two' 0 0 ''),$(iss 11 '## Done when\n- [x] one\n- [ ] two' 0 0 ''),$(iss 12 epic 2 2 ''),$(iss 13 x 3 1 "$M"),$(iss 14 '## Done when\n- [x] one\n- [ ] two' 2 2 "$M")" \
  > "$STUB/issues.json"
cat > "$T_BIN/gh" <<'GHSTUB'
#!/bin/sh
case "$*" in
  "repo view acme/widget --json defaultBranchRef") cat "$STUB/repo.json" ;;
  "api repos/acme/widget/branches?per_page=100 --paginate") cat "$STUB/branches.json" ;;
  "pr list -R acme/widget --state all "*)
    echo x >> "$STUB/prs.calls"
    [ "${STUB_FAIL:-}" = prs ] && exit 1
    [ "${STUB_FAIL:-}" = prs404 ] && { echo "HTTP 404: Not Found" >&2; exit 1; }
    [ "${STUB_FAIL:-}" = prs502 ] && { echo "HTTP 502: Bad Gateway" >&2; exit 1; }
    [ "${STUB_FAIL:-}" = prs504once ] && [ "$(wc -l < "$STUB/prs.calls")" -le 1 ] && { echo "HTTP 504: Gateway Timeout" >&2; exit 1; }
    cat "$STUB/prs.json" ;;
  "pr list -R acme/widget --state open "*) cat "$STUB/open.json" ;;
  "api graphql --paginate -f owner=acme -f name=widget "*) cat "$STUB/issues.json" ;;
  *) echo "gh stub: unexpected call: $*" >&2; exit 1 ;;
esac
GHSTUB
chmod +x "$T_BIN/gh"
GHR() { with HARBOR_CLEAN_GH="$T_BIN/gh" sh "$TOOL" "$@"; }
J="$(GHR --json)"
rows() { printf '%s\n' "$J" | jq -r --arg v "$1" --arg c "$2" --arg s "$3" \
  'select(.verdict == $v and .class == $c and (.subject | contains($s))) | .verdict' | wc -l | tr -d ' '; }  # <verdict> <class> <subject>
any()  { printf '%s\n' "$J" | jq -r --arg c "$1" --arg s "$2" 'select(.class == $c and (.subject | contains($s))) | .verdict' | wc -l | tr -d ' '; }
why()  { printf '%s\n' "$J" | jq -r --arg c "$1" --arg s "$2" 'select(.class == $c and .subject == $s) | .reason'; }

t_section "16 one row per repository, however many worktrees it has"
t_eq "a landed branch is reported once" 1 \
  "$(printf '%s\n' "$J" | jq -r 'select(.class == "landed-branches" and (.subject | endswith(" landed2"))) | .subject' | wc -l | tr -d ' ')"

t_section "17 a squash-merged branch is DECIDE; work after the merge is RISK"
t_eq "the merged PR carried every commit: DECIDE" 1 "$(rows DECIDE pr-branches 'widget merged-clean')"
t_eq "commits after the merge: RISK" 1 "$(rows RISK pr-branches 'widget merged-after')"
t_eq "work after the merge is not offered for deletion" 0 "$(rows DECIDE pr-branches 'widget merged-after')"
t_eq "a branch with an OPEN PR is not counted" 0 "$(any pr-branches 'widget open-pr')"

t_section "18 the only copy is RISK; fresh and pushed lookalikes are not"
t_eq "a month-old branch on no remote and in no PR: RISK" 1 "$(rows RISK pr-branches 'widget lonely')"
t_eq "a branch made today is not idle" 0 "$(any pr-branches 'widget fresh-local')"
t_eq "a pushed branch is not the only copy" 0 "$(rows RISK pr-branches 'widget pushed-idle')"
t_eq "a pushed branch with no PR for 30d: DECIDE" 1 "$(rows DECIDE pr-branches 'widget pushed-idle')"

t_section "19 worktrees: merged+clean DECIDE, merged+dirty RISK, open nothing"
t_eq "a clean worktree whose PR merged: DECIDE" 1 "$(rows DECIDE finished-worktrees 'widget-wt-done')"
t_eq "uncommitted changes in a finished worktree: RISK" 1 "$(rows RISK finished-worktrees 'widget-wt-dirty')"
t_eq "a worktree with an OPEN PR is not counted" 0 "$(any finished-worktrees 'widget-wt-open')"
t_eq "a worktree's branch is not ALSO a branch row" 0 "$(any pr-branches 'widget wt-done')"
GHR --apply >/dev/null  # --apply never acts on DECIDE
t_eq "--apply keeps a DECIDE worktree" present "$(there "$H/widget-wt-done")"
t_exit "--apply keeps a DECIDE branch" 0 git -C "$GR" rev-parse --verify -q merged-clean

t_section "20 remote branches: at the merged head DECIDE; moved says look"
t_eq "a GitHub branch left at its merged head: DECIDE" 1 "$(rows DECIDE remote-branches 'acme/widget merged-clean')"
t_has "a branch that moved after its PR is flagged as moved" \
  "$(printf '%s\n' "$J" | jq -r 'select(.class == "remote-branches" and (.subject | contains("merged-moved"))) | .reason')" "moved after"
t_eq "a GitHub branch with an OPEN PR is not counted" 0 "$(any remote-branches 'open-pr')"
t_eq "an undated no-PR GitHub branch is not counted" 0 "$(any remote-branches 'no-pr-remote')"

t_section "21 the main checkout behind GitHub, stash, stray; ignored is not"
t_eq "a main checkout behind GitHub: DECIDE" 1 "$(rows DECIDE stale-checkouts 'widget main')"
t_eq "a 20-day-old stash: RISK" 1 "$(rows RISK old-stashes 'widget stash@{0}')"
t_eq "an old untracked file: DECIDE" 1 "$(rows DECIDE stray-files 'widget notes.txt')"
t_eq "an IGNORED file is not stray" 0 "$(any stray-files 'build.log')"

t_section "22 PRs: green a while DECIDE, red DECIDE, brand new not"
t_has "a green, mergeable PR 3 days old waits on you" "$(why waiting-prs 'acme/widget #3')" "green and mergeable"
t_has "a PR with one failing check is CI red" "$(why waiting-prs 'acme/widget #6')" "CI red"
t_eq "a PR green for minutes is not waiting" 0 "$(any waiting-prs 'acme/widget #8')"

t_section "23 issues: all ticked, all children closed, merged PR; an open box is not done"
for n in 10 12 13; do t_eq "issue #$n says it is done: DECIDE" 1 "$(rows DECIDE closable-issues "acme/widget #$n")"; done
t_eq "an issue with an UNTICKED box is not offered" 0 "$(any closable-issues 'acme/widget #11')"
t_eq "closed sub-issues do not outvote an UNTICKED box (harbor#603)" 0 "$(any closable-issues 'acme/widget #14')"

t_section "23b work after a merge is RISK only while no remote holds it"
t_eq "pushed work after a merge: DECIDE" 1 "$(rows DECIDE pr-branches 'widget after-pushed')"
t_eq "pushed work after a merge is not the only copy" 0 "$(rows RISK pr-branches 'widget after-pushed')"
t_eq "a worktree whose later work is pushed: DECIDE" 1 "$(rows DECIDE finished-worktrees 'widget-wt-after-pushed')"
t_eq "a worktree whose later work is NOT pushed: RISK" 1 "$(rows RISK finished-worktrees 'widget-wt-after-local')"

t_section "23c a worktree an install root links into is KEEP, never DECIDE (harbor#922)"
# ~/.local/lib/quuxmail shape: idle, no PR, and the runtime behind ~/.local/bin. Reached by a relative chain via an alias.
unset HARBOR_LOCAL_BIN  # the root is the fixture home's .local/bin, as roots.tsv declares
gg checkout -q -b wt-installed main; mkdir -p "$GR/bin"; printf 'tool\n' > "$GR/bin/tool"; gg add bin/tool
GIT_AUTHOR_DATE="$(ago 30) +0000" GIT_COMMITTER_DATE="$(ago 30) +0000" gg commit -qm tool
gg checkout -q -b wt-idle main; commit idle 30 >/dev/null; gg checkout -q main
for b in wt-installed wt-idle; do gg worktree add -q "$H/widget-$b" "$b"; done
ln -s "$H" "$T_TMP/alias"; mkdir -p "$H/.local/bin" "$H/shims"
ln -s "$T_TMP/alias/widget-wt-installed/bin/tool" "$H/shims/tool"
ln -s ../../shims/tool "$H/.local/bin/tool"
ln -s "$H/widget-wt-done/w1" "$H/.local/bin/done-tool"
ln -s /bin/sh "$H/.local/bin/unrelated"
Ji="$(GHR --json finished-worktrees)"
wi() { printf '%s\n' "$Ji" | jq -r --arg s "$1" 'select(.class == "finished-worktrees" and .subject == $s) | .verdict + " " + .reason'; }
t_eq "an idle worktree an install-root link resolves into is KEEP, naming the link" \
  "KEEP install target: .local/bin/tool resolves into it" "$(wi widget-wt-installed)"
t_eq "...and so is one whose PR merged" "KEEP install target: .local/bin/done-tool resolves into it" "$(wi widget-wt-done)"
t_eq "control: an idle worktree nothing links into is still DECIDE" "DECIDE no PR and no commit for 30d" "$(wi widget-wt-idle)"
rm -f "$H/.local/bin/done-tool"  # wt-done is a DECIDE fixture again for every later section

t_section "24 a failed GitHub read is UNREAD, never clean (harbor#626)"
Ju="$(with HARBOR_CLEAN_GH="$T_BIN/gh" STUB_FAIL=prs sh "$TOOL" --json)"
t_has "a failed PR read reports the repo unread" "$Ju" '"class":"unread"'
t_has "a good read does judge branch rows" "$J" '"class":"pr-branches"'
t_hasnt "branch rows are not judged without the PR list" "$Ju" '"class":"pr-branches"'
t_has "--record carries unread=1" "$(with HARBOR_CLEAN_GH="$T_BIN/gh" STUB_FAIL=prs sh "$TOOL" --record | tail -n 1)" "unread=1"
t_has "a PR list at its limit is unread too" "$(with HARBOR_CLEAN_GH="$T_BIN/gh" HARBOR_CLEAN_PR_LIMIT=7 sh "$TOOL" --json)" '"class":"unread"'

t_section "24b a transient 5xx is retried, a 4xx is not (the sweep undercounted)"
rc() { : > "$STUB/prs.calls"; _o="$(with HARBOR_CLEAN_GH="$T_BIN/gh" HARBOR_CLEAN_RETRY_WAIT=0 STUB_FAIL="$1" sh "$TOOL" --record | tail -n 1)"; printf '%s %s' "$(wc -l < "$STUB/prs.calls" | tr -d ' ')" "$(printf '%s' "$_o" | grep -o 'unread=[0-9]*')"; }
t_eq "one 504 then success reads the repo whole" "2 unread=0" "$(rc prs504once)"
t_eq "a permanent 502 gives up after 3 tries, unread" "3 unread=1" "$(rc prs502)"
t_eq "a 404 is not retried, unread" "1 unread=1" "$(rc prs404)"

t_section "25 the keep list turns a row into KEEP, with the operator's reason"
printf 'pr-branches\twidget lonely\tparked on purpose\n' > "$CFG/.helm-sweep-keep"
t_eq "a kept row is KEEP with its reason" "KEEP kept by the operator: parked on purpose" \
  "$(GHR --json | jq -r 'select(.class == "pr-branches" and (.subject | contains("widget lonely"))) | .verdict + " " + .reason')"
rm -f "$CFG/.helm-sweep-keep"

t_section "26 scratch: dead and quiet counts; live and recent do not"
mkdir -p "$SCR/proj/sess-dead" "$SCR/proj/sess-live" "$SCR/proj/sess-recent" "$CFG/sessions"
printf 'x\n' > "$SCR/proj/sess-dead/f"; touch -t 202601010000 "$SCR/proj/sess-dead/f"
printf 'x\n' > "$SCR/proj/sess-live/f"; touch -t 202601010000 "$SCR/proj/sess-live/f"
printf 'x\n' > "$SCR/proj/sess-recent/f"
printf '{"pid":%s,"sessionId":"sess-live","cwd":"/nowhere"}\n' "$$" > "$CFG/sessions/$$.json"
Js="$(run --json old-scratch)"
t_has "a dead session's quiet scratch is listed" "$Js" sess-dead
t_hasnt "a LIVE session's scratch is not listed" "$Js" sess-live
t_hasnt "scratch touched today is not listed" "$Js" sess-recent
t_eq "a full run aggregates scratch into one row" "1 session scratch dir(s) under $SCR" \
  "$(run --json | jq -r 'select(.class == "old-scratch") | .subject')"
t_eq "a run without --apply leaves scratch alone" present "$(there "$SCR/proj/sess-dead")"

t_section "27 downloads: 30 days old and lock files count; a new download does not"
mkdir -p "$H/Downloads"
printf 'z\n' > "$H/Downloads/old.zip"; touch -t 202601010000 "$H/Downloads/old.zip"
printf 'z\n' > "$H/Downloads/new.zip"
printf 'l\n' > "$H/"'~$report.docx'; touch -t 202601010000 "$H/"'~$report.docx'
Jd="$(run --json old-downloads)"
t_has "a download 30+ days old is listed" "$Jd" old.zip
t_hasnt "a NEW download is not listed" "$Jd" new.zip
t_has "an old Office lock file is listed" "$Jd" '~$report.docx'

t_section "28 --record: the line, the count, due, and the rows"
REC="$(GHR --record | tail -n 1)"
t_eq "--record prints the sweep line" match "$(case "$REC" in ("sweep items="*" due=1 at="*"[check:sweep]") echo match ;; (*) printf '%s' "$REC" ;; esac)"
t_eq "--record writes .helm-sweep" present "$(there "$CFG/.helm-sweep")"
t_eq "items= equals the DECIDE+RISK rows it wrote" \
  "$(jq -r 'select(.verdict == "DECIDE" or .verdict == "RISK") | .verdict' "$CFG/.helm-sweep.jsonl" | wc -l | tr -d ' ')" \
  "$(sed -n 's/.*items=\([0-9]*\).*/\1/p' "$CFG/.helm-sweep")"
t_eq ".helm-sweep.jsonl is line-delimited valid JSON" 0 "$(jq -R 'select(length > 0) | fromjson' "$CFG/.helm-sweep.jsonl" >/dev/null 2>&1; echo $?)"
t_eq "--record releases its lock" gone "$(there "$CFG/.helm-sweep.lock")"
t_has "RISK rows alone make the count due" "$(with HARBOR_CLEAN_GH="$T_BIN/gh" HARBOR_CLEAN_DUE=100000 sh "$TOOL" --record | tail -n 1)" " due=1 "
t_eq "a few DECIDE rows and no RISK are not due" match \
  "$(case "$(with HARBOR_CLEAN_DUE=100000 sh "$TOOL" --record loose-deliverables | tail -n 1)" in (*" risk=0 "*" due=0 "*) echo match ;; (*) echo no ;; esac)"

t_section "29 --if-due: a slot passed since the last record, or nothing happens"
# Pinned in UTC: 2026-01-15 12:00, slots 09 and 16, so the latest slot is 09:00 that day.
N12=1768478400; S09=1768467600
rif() { with TZ=UTC HARBOR_NOW="$N12" sh "$TOOL" --record --if-due loose-deliverables >/dev/null; }
printf 'sweep items=0 at=%s\n' "$((S09 + 60))" > "$CFG/.helm-sweep"; rif
t_eq "--if-due stands down within a covered slot" "sweep items=0 at=$((S09 + 60))" "$(cat "$CFG/.helm-sweep")"
printf 'sweep items=0 at=%s\n' "$((S09 - 60))" > "$CFG/.helm-sweep"; rif
t_has "--if-due runs once a slot has passed" "$(cat "$CFG/.helm-sweep")" " at=$N12"
printf 'sweep items=0 at=%s\n' "$((S09 - 16 * 3600 + 60))" > "$CFG/.helm-sweep"   # yesterday 17:00
with TZ=UTC HARBOR_NOW="$((S09 - 3600))" sh "$TOOL" --record --if-due loose-deliverables >/dev/null
t_eq "08:00 sees yesterday's 16:00 as covered" "sweep items=0 at=$((S09 - 16 * 3600 + 60))" "$(cat "$CFG/.helm-sweep")"
rm -f "$CFG/.helm-sweep"; mkdir "$CFG/.helm-sweep.lock"; run --record loose-deliverables >/dev/null
t_eq "--record stands down on a held lock" gone "$(there "$CFG/.helm-sweep")"
touch -t 202601010000 "$CFG/.helm-sweep.lock"; run --record loose-deliverables >/dev/null
t_eq "a 31-minute-old lock is dead and does not block" present "$(there "$CFG/.helm-sweep")"

t_section "30 --record refuses --apply, and the live dir without --live"
t_exit "--record --apply exits 2" 2 env HARBOR_CLEAN_HOME="$H" CLAUDE_CONFIG_DIR="$CFG" sh "$TOOL" --record --apply
mkdir -p "$HOME/.claude"  # the sandbox's live dir must exist, or the refusal is not what is tested
t_has "--record on the live dir refuses" "$(env -u CLAUDE_CONFIG_DIR HARBOR_CLEAN_HOME="$HOME" sh "$TOOL" --record 2>&1)" "--record --live"
t_eq "and records nothing there" gone "$(there "$HOME/.claude/.helm-sweep")"

t_section "31 an unreadable directory does not kill --apply mid-run"
mkdir -p "$H/locked/inner" "$H/actions-runner/_diag/locked"
printf 'x' > "$H/.DS_Store"
printf 'x' > "$H/actions-runner/_diag/stale.log"; touch -t 202601010000 "$H/actions-runner/_diag/stale.log"
chmod 000 "$H/locked" "$H/actions-runner/_diag/locked"
out="$(run --apply runner-diag ds-store)"; rc=$?
chmod 755 "$H/locked" "$H/actions-runner/_diag/locked"
t_eq "--apply exits 0 past an unreadable dir" 0 "$rc"
t_eq "the .DS_Store is removed" gone "$(there "$H/.DS_Store")"
t_eq "the stale runner log is removed" gone "$(there "$H/actions-runner/_diag/stale.log")"
t_has "--apply reaches its summary line" "$out" "reclaimable row"

t_section "32 a repo under the port root is found without a bridge (harbor#619)"
P="$H/port/deep"; mkdir -p "$P"; git init -q "$P"; git -C "$P" symbolic-ref HEAD refs/heads/main
gp() { git -C "$P" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
printf 'v1\n' > "$P/f.txt"; gp add f.txt; gp commit -qm v1
git init -q --bare "$T_TMP/origin-deep.git"; gp remote add origin "$T_TMP/origin-deep.git"; gp push -q origin main
gp branch shipped main
t_has "the landed branch under port/ is found" "$(run landed-branches)" "port/deep shipped"

t_section "33 the .DS_Store walk never enters a folder macOS guards (harbor#658)"
H6="$T_TMP/h658"; GUARDED="Library Music Pictures Movies Desktop Documents Downloads .Trash"
for d in $GUARDED plain; do mkdir -p "$H6/$d"; printf 'x' > "$H6/$d/.DS_Store"; done
t_has "only the control is counted" "$(HARBOR_CLEAN_HOME="$H6" CLAUDE_CONFIG_DIR="$CFG" sh "$TOOL" ds-store 2>&1)" "1 .DS_Store file(s)"
HARBOR_CLEAN_HOME="$H6" CLAUDE_CONFIG_DIR="$CFG" sh "$TOOL" --apply ds-store >/dev/null 2>&1
t_eq "--apply removes the control" gone "$(there "$H6/plain/.DS_Store")"
t_eq "--apply leaves all 8 guarded folders alone" 8 "$(for d in $GUARDED; do [ -f "$H6/$d/.DS_Store" ] && echo x; done | grep -c x)"

t_section "34 a GitHub read that hangs dies with everything it started (harbor#768)"
# A wrapper gh forks a child and hangs. The bound used to TERM the wrapper alone, so its child outlived it.
KID="$T_TMP/gh-kid.pid"; GHH="$T_TMP/ghhang"; mkdir -p "$GHH"
printf '#!/bin/sh\nsleep 7770 & printf "%%s\\n" "$!" >> "%s"\nwait\n' "$KID" > "$GHH/gh"; chmod +x "$GHH/gh"
settle() { _sa=x; _si=0; while [ -n "$_sa" ] && [ "$_si" -lt 20 ]; do  # <pidfile>: alive after up to 2s
  _sa="$(for _p in $(cat "$1"); do kill -0 "$_p" 2>/dev/null && printf '%s ' "$_p"; done)"; [ -z "$_sa" ] || sleep 0.1
  _si=$((_si + 1)); done; printf '%s' "$_sa"; }
reap() { for _p in $(cat "$KID"); do kill -9 "$_p" 2>/dev/null; done; }  # a red run leaks nothing
: > "$KID"
t_has "a read past its bound leaves its repo unread" "$(with HARBOR_CLEAN_GH="$GHH/gh" HARBOR_CLEAN_BOUND=1 sh "$TOOL" --json)" '"class":"unread"'
t_eq "the wrapper recorded its child, or the next row is vacuous" 1 "$(grep -c . "$KID")"
t_eq "at the bound the wrapper's child dies too" '' "$(settle "$KID")"
reap; : > "$KID"
env HARBOR_CLEAN_HOME="$H" CLAUDE_CONFIG_DIR="$CFG" HARBOR_CLEAN_GH="$GHH/gh" HARBOR_CLEAN_BOUND=60 \
  sh "$TOOL" --json >/dev/null 2>&1 &  # env, never `with … &`: $! would be a subshell, not harbor-clean
_hp=$!; _hi=0; while [ ! -s "$KID" ] && [ "$_hi" -lt 100 ]; do sleep 0.1; _hi=$((_hi + 1)); done
kill -TERM "$_hp"; wait "$_hp" 2>/dev/null
t_eq "a TERM mid-read reached the read, or the next row is vacuous" 1 "$(grep -c . "$KID")"
t_eq "…and the read's child dies with harbor-clean, not 60s later" '' "$(settle "$KID")"
reap
t_done
