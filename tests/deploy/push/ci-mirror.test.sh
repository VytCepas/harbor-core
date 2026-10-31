#!/usr/bin/env sh
# bin/ci-mirror.sh: a harbor PR's core files to the public harbor-core repo, behind deploy-push's gates (harbor#1149).
# The "remote" is a local bare repo reached through an insteadOf rewrite of a github.com URL; gh is a stub over that bare
# repo. No network. The "secret" below is a made-up word and the "token" a made-up string, never real.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset HARBOR_TEST_IN_SUITE HARBOR_IN_SUITE GH_TOKEN GITHUB_TOKEN
GIT_AUTHOR_NAME=t; GIT_AUTHOR_EMAIL=t@t.test; GIT_COMMITTER_NAME=t; GIT_COMMITTER_EMAIL=t@t.test
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
REALGIT="$(command -v git)"
HDR='id	kind	pattern	note'
LHDR='path	layer	note'
mkdir -p "$T_TMP/pv"; { printf '%s\n' "$HDR"; printf 'k1\tword\tZorblax\tn\n'; } > "$T_TMP/pv/leaks.tsv"
HARBOR_SCOPE_PRIVATE="$T_TMP/pv"; export HARBOR_SCOPE_PRIVATE
mkdir -p "$T_TMP/pv/inject.d/box"; printf '# name\tpath\twhat\nzorbcorp\t~/zorbcorp\ta made-up workload repo\n' > "$T_TMP/pv/inject.d/box/projects.tsv"
TOKEN="mirrortok-Qm4xV7nB2c"; TOKB64="$(printf 'x-access-token:%s' "$TOKEN" | base64 | tr -d '\n')"
HARBOR_CORE_SLUG=test/harbor-core; HARBOR_SLUG=test/harbor; export HARBOR_CORE_SLUG HARBOR_SLUG
STUB="$T_TMP/stub"; mkdir -p "$STUB"; export STUB

# git wrapper: records the argv and the auth header of every fetch and push, then runs the real git.
printf '#!/bin/sh\ncase " $* " in *" push "*|*" fetch "*) echo "ARGV $* HDR ${GIT_CONFIG_KEY_0:-}=${GIT_CONFIG_VALUE_0:-}" >> "$STUB/git.log" ;; esac\nexec %s "$@"\n' "$REALGIT" > "$T_BIN/git"
chmod +x "$T_BIN/git"
# gh stub: PR state in $STUB, branches in the bare repo $BARE. Records every call with the GH_TOKEN it ran with.
cat > "$T_BIN/gh" <<'STUBEOF'
#!/bin/sh
echo "gh $* | GH_TOKEN=${GH_TOKEN:-}" >> "$STUB/gh.log"
br() { printf '%s' "$*" | sed -n 's/.*--head \([^ ]*\).*/\1/p'; }
case "$1 $2" in
  "pr view") cat "$STUB/head_sha" ;;
  "pr list")
    [ -f "$STUB/pr_number" ] || exit 0
    case "$*" in *headRefOid*) git -C "$BARE" rev-parse -q --verify "refs/heads/$(br "$@")" ;; *) cat "$STUB/pr_number" ;; esac ;;
  "pr create") git -C "$BARE" rev-parse -q --verify "refs/heads/$(br "$@")" >/dev/null || exit 1; echo 1 > "$STUB/pr_number"; echo "$*" > "$STUB/pr_create" ;;
  "pr edit") echo "$*" > "$STUB/pr_edit" ;;
  "pr close") [ -f "$STUB/pr_number" ] || exit 1; rm "$STUB/pr_number" ;;
  "run list") sha="$(printf '%s' "$*" | sed -n 's/.*headSha == "\([0-9a-f]*\)".*/\1/p')"
              [ ! -f "$STUB/runs" ] || awk -F'\t' -v s="$sha" '$1 == s { print ($5 == "" ? "governance" : $5) "\t" $2 "\t" $3 "\t" $4 }' "$STUB/runs" ;;
  "api -X") case "$3" in
      POST) echo "$*" >> "$STUB/status.log"
            st=''; de=''; for a in "$@"; do case "$a" in state=*) st="${a#state=}" ;; description=*) de="${a#description=}" ;; esac; done
            printf '%s\t%s\n' "$st" "$de" > "$STUB/cur_status" ;;
      DELETE) git -C "$BARE" update-ref -d "refs/heads/${4#repos/*/git/refs/heads/}" ;;
    esac ;;
  api\ repos/*/statuses) [ ! -f "$STUB/cur_status" ] || cat "$STUB/cur_status" ;;
  api\ repos/*) git -C "$BARE" rev-parse -q --verify "refs/heads/${2#repos/*/git/ref/heads/}" >/dev/null ;;
  *) echo "gh stub: unhandled $*" >&2; exit 9 ;;
esac
STUBEOF
chmod +x "$T_BIN/gh"

mk() { # <name> → a harbor source checkout (origin test/harbor): core bin and docs, a dev notes file, the tools under test
  _d="$T_TMP/$1"; mkdir -p "$_d/bin" "$_d/contracts" "$_d/docs/explanation" "$_d/docs" "$_d/EVALS-DATA"
  cp "$T_ROOT/bin/ci-mirror.sh" "$T_ROOT/bin/deploy-push.sh" "$T_ROOT/bin/scope-layers.sh" "$T_ROOT/bin/lint-leaks.sh" "$T_ROOT/bin/library-log.sh" "$_d/bin/"
  cp "$T_ROOT/bin/lint-domain.sh" "$T_ROOT/bin/scope-roots.sh" "$T_ROOT/bin/eval-pass-score.sh" "$_d/bin/"
  : > "$_d/bin/status-generate.sh"
  # redteam-corpus's row reads --print; a stub stands in for the check (its own suite is tests/eval/redteam-corpus/redteam-corpus.test.sh)
  printf '#!/bin/sh\n[ "$RTSTUB_RED" = 1 ] && { echo "  FAIL: stub: 1 not accepted"; exit 1; }\necho "  ok: stub"\n' > "$_d/bin/eval-redteam-corpus.sh"
  cp "$T_ROOT/contracts/leak-patterns.tsv" "$T_ROOT/contracts/roots.tsv" "$_d/contracts/"
  printf 'id\tpattern\tnote\nquuxtool\tquuxtool\tfixture\n' > "$_d/contracts/domain-terms.tsv"
  printf 'path\tterm\treason\n' > "$_d/contracts/domain-allow.tsv"
  printf '| | pass 1 | pass 2 | pass 3 |\n|---|---|---|---|\n| criticals | 0 | 0 | 0 |\n' > "$_d/docs/explanation/admission-baseline.md"
  printf '# header\n#\ntest/harbor\n' > "$_d/contracts/repo-slug.txt"
  printf '# fixture\n%s\nbin/\tcore\ttools\ncontracts/\tcore\tcontracts\ndocs/\tcore\tdocs\nEVALS-DATA/\tdev\tbulk\nFLOOR.md\tcore\tpasses\nNOTES.md\tdev\tnotes\nREADME.md\tcore\treadme\n' "$LHDR" > "$_d/contracts/layers.tsv"
  printf 'hello\n' > "$_d/docs/a.md"; printf 'a client Zorblax here\n' > "$_d/NOTES.md"; printf 'Zorblax data\n' > "$_d/EVALS-DATA/e.txt"
  printf 'readme\n' > "$_d/README.md"
  ( cd "$_d" && git init -q . && git remote add origin https://github.com/test/harbor.git && git add -A && git commit -qm src ) >/dev/null 2>&1
  printf '%s' "$_d"
}
base() { git -C "$1" symbolic-ref --short HEAD; }
pr() { # <src> <file> <content>: a PR head one commit above the source's branch; the source stays checked out where it was
  _b="$(base "$1")"; git -C "$1" checkout -q -b "pr-$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')" >/dev/null 2>&1
  printf '%s\n' "$3" > "$1/$2"; git -C "$1" add -A >/dev/null 2>&1; git -C "$1" commit -qm pr >/dev/null 2>&1
  git -C "$1" rev-parse HEAD > "$STUB/head_sha"; git -C "$1" checkout -q "$_b" >/dev/null 2>&1; cat "$STUB/head_sha"
}
core() { # <name> → sets BARE and MIR: a bare harbor-core with a seeded main, and a clean checkout whose origin is its GitHub URL
  BARE="$T_TMP/core-$1.git"; MIR="$T_TMP/mir-$1"; export BARE
  git init -q --bare -b main "$BARE" >/dev/null 2>&1
  _s="$T_TMP/seed-$1"; git init -q -b main "$_s" >/dev/null 2>&1; printf 'seed\n' > "$_s/SEED.md"
  ( cd "$_s" && git add -A && git commit -qm seed && git push -q "$BARE" main ) >/dev/null 2>&1
  git clone -q "$BARE" "$MIR" >/dev/null 2>&1
  git -C "$MIR" remote set-url origin https://github.com/test/harbor-core.git
  git -C "$MIR" config "url.$BARE.insteadOf" https://github.com/test/harbor-core.git
  rm -f "$STUB/pr_number" "$STUB/pr_create" "$STUB/pr_edit" "$STUB/gh.log" "$STUB/git.log" "$STUB/status.log" "$STUB/runs" "$STUB/cur_status"
}
run() { # <src> args... → OUT, RC; the token is set unless NOTOKEN=1
  _s="$1"; shift
  if [ "${NOTOKEN:-0}" = 1 ]; then OUT="$(HARBOR_CORE_MIRROR_DIR="$MIR" sh "$_s/bin/ci-mirror.sh" "$@" 2>&1)"; RC=$?
  else OUT="$(HARBOR_CORE_MIRROR_TOKEN="$TOKEN" HARBOR_CORE_MIRROR_DIR="$MIR" sh "$_s/bin/ci-mirror.sh" "$@" 2>&1)"; RC=$?; fi
  [ -z "${CMDBG:-}" ] || printf '== rc=%s %s\n%s\n' "$RC" "$*" "$OUT" >> "$CMDBG"
  NOTOKEN=0
}
tip() { git -C "$BARE" rev-parse -q --verify "refs/heads/$1" 2>/dev/null || echo none; }
nbranches() { git -C "$BARE" for-each-ref --format='%(refname)' refs/heads/ci | wc -l | tr -d ' '; }
gitcalls() { cat "$STUB/git.log" 2>/dev/null | grep -c "$1" || :; }
ghcalls() { grep -c "$1" "$STUB/gh.log" 2>/dev/null || :; }

t_section "a green PR: its base then its core set land on ci/harbor-<pr>, above main, and a PR is opened into ci/base-<pr>"
S="$(mk green)"; core green; HEAD7="$(pr "$S" docs/pr7.md 'from the pr')"
MAIN0="$(tip main)"
run "$S" 7
t_eq "the mirror is green" "0" "$RC"
t_eq "...main of harbor-core is untouched" "$MAIN0" "$(tip main)"
t_eq "...the branch is two commits above main, the base then the head" "$MAIN0" "$(git -C "$BARE" rev-parse refs/heads/ci/harbor-7~2)"
t_eq "...ci/base-7 is the first of them" "$(git -C "$BARE" rev-parse refs/heads/ci/harbor-7~1)" "$(tip ci/base-7)"
t_has "...it names the PR's base sha" "$(git -C "$BARE" log -1 --format=%B refs/heads/ci/base-7)" "$(git -C "$S" rev-parse HEAD)"
# the point of the base (harbor#1149): hosted CI diffs only what the PR changed, however stale harbor-core main is
t_eq "...the head differs from its base by the PR's own file alone" "docs/pr7.md" "$(git -C "$BARE" diff --name-only refs/heads/ci/base-7 refs/heads/ci/harbor-7)"
t_has "...while against harbor-core main everything differs" "$(git -C "$BARE" diff --name-only main refs/heads/ci/harbor-7 | tr '\n' ' ')" "docs/a.md"
FILES="$(git -C "$BARE" ls-tree -r --name-only refs/heads/ci/harbor-7 | tr '\n' ' ')"
t_has "...it holds the PR head's own file" "$FILES" "docs/pr7.md"
t_hasnt "...and no dev path" "$FILES" "EVALS-DATA"
t_hasnt "...nor the dev notes" "$FILES" "NOTES.md"
t_has "...the snapshot names the PR head's sha" "$(git -C "$BARE" log -1 --format=%B refs/heads/ci/harbor-7)" "$HEAD7"
t_eq "...the source file the PR did not touch is the PR head's too" "hello" "$(git -C "$BARE" show refs/heads/ci/harbor-7:docs/a.md)"
t_has "...the exported slug is harbor-core's, not harbor's" "$(git -C "$BARE" show refs/heads/ci/harbor-7:contracts/repo-slug.txt)" "test/harbor-core"
t_has "the PR is titled harbor#7" "$(cat "$STUB/pr_create")" "--title harbor#7"
t_has "...opened into the base branch from the mirror branch" "$(cat "$STUB/pr_create")" "--base ci/base-7 --head ci/harbor-7"
t_has "...with the mirror token, on harbor-core" "$(grep 'pr create' "$STUB/gh.log")" "GH_TOKEN=$TOKEN"
t_hasnt "the token is in no argv git ran" "$(sed 's/ HDR .*//' "$STUB/git.log")" "$TOKEN"
t_hasnt "...nor its encoding" "$(sed 's/ HDR .*//' "$STUB/git.log")" "$TOKB64"
t_has "...it rides as a header in git's environment" "$(grep ' push ' "$STUB/git.log")" "HDR http.extraHeader=Authorization: Basic $TOKB64"
t_hasnt "...the remote URL does not carry it" "$(git -C "$MIR" config --get remote.origin.url)" "$TOKEN"
t_hasnt "...the checkout's config does not" "$(git -C "$MIR" config --list)" "$TOKEN"
t_hasnt "...and the output does not" "$OUT" "$TOKEN"
t_hasnt "no push in the run is forced" "$(grep ' push ' "$STUB/git.log" | sed 's/ HDR .*//')" "force"
t_hasnt "...nor a '+' refspec" "$(grep ' push ' "$STUB/git.log" | sed 's/ HDR .*//')" "+"
t_eq "the harbor checkout's worktree list is back to one" "1" "$(git -C "$S" worktree list | wc -l | tr -d ' ')"

t_section "a second mirror of the same PR is a fast-forward, and updates the PR rather than opening another"
TIP1="$(tip ci/harbor-7)"
HEAD7B="$(pr "$S" docs/pr7.md 'from the pr, amended')"
run "$S" 7
t_eq "the second mirror is green" "0" "$RC"
t_eq "...the old tip is an ancestor of the new one" "0" "$(git -C "$BARE" merge-base --is-ancestor "$TIP1" refs/heads/ci/harbor-7; echo $?)"
t_eq "...two commits further, the base again then the head" "$TIP1" "$(git -C "$BARE" rev-parse refs/heads/ci/harbor-7~2)"
t_eq "...ci/base-7 moved by a fast-forward too" "$(git -C "$BARE" rev-parse refs/heads/ci/harbor-7~1)" "$(tip ci/base-7)"
t_has "...the edit points the PR at the base branch" "$(cat "$STUB/pr_edit")" "--base ci/base-7"
t_eq "...the PR was edited" "1" "$(ghcalls 'pr edit')"
t_eq "...and opened only once" "1" "$(ghcalls 'pr create')"
# harbor-core's main moves (deploy-push does that); the next mirror carries it and still fast-forwards.
TIP2="$(tip ci/harbor-7)"
( cd "$T_TMP/seed-green" && printf 'more\n' > MORE.md && git add -A && git commit -qm more && git push -q "$BARE" main ) >/dev/null 2>&1
NEWMAIN="$(tip main)"
run "$S" 7
t_eq "a moved main: the mirror is green" "0" "$RC"
t_eq "...main is an ancestor of the branch" "0" "$(git -C "$BARE" merge-base --is-ancestor "$NEWMAIN" refs/heads/ci/harbor-7; echo $?)"
t_eq "...and the previous tip still is too (no rewrite)" "0" "$(git -C "$BARE" merge-base --is-ancestor "$TIP2" refs/heads/ci/harbor-7; echo $?)"
t_hasnt "...the tree is the PR head's core set, not main's extra file" "$(git -C "$BARE" ls-tree -r --name-only refs/heads/ci/harbor-7)" "MORE.md"

t_section "any red gate: nothing leaves the machine"
redcase() { # <label> <gate row text> — expects RC/OUT from the run just made, on a core with no mirror branch
  t_eq "$1: refused" "1" "$RC"
  t_has "$1: names the red row" "$OUT" "$2"
  t_eq "$1: no branch reached harbor-core" "0" "$(nbranches)"
  t_eq "$1: no PR was opened or edited" "0" "$(( $(ghcalls 'pr create') + $(ghcalls 'pr edit') ))"
  t_eq "$1: git never pushed" "0" "$(gitcalls ' push ')"
}
S="$(mk leak)"; core leak; pr "$S" docs/leak.md 'owned by Zorblax' >/dev/null
run "$S" 7; redcase "a leak" "release gate · leak gate 0: red"
t_hasnt "...the output never prints the pattern" "$OUT" "Zorblax"
SEC="$(printf '%s%s%s' ghp_ Zq8LmN2pR7tY4wXc9Vb K3jHs6DfG1aQe5UoI)"
S="$(mk sec)"; core sec; pr "$S" docs/tok.md "pat $SEC" >/dev/null
run "$S" 7; redcase "a secret (gitleaks)" "release gate · secrets 0: red"
S="$(mk dom)"; core dom; pr "$S" docs/dom.md 'we run quuxtool here' >/dev/null
run "$S" 7; redcase "a domain term" "release gate · domain ratchet 0: red"
S="$(mk rt)"; core rt; pr "$S" docs/ok.md 'fine' >/dev/null
RTSTUB_RED=1; export RTSTUB_RED; run "$S" 7; redcase "a red redteam corpus" "release gate · redteam-corpus: red"; unset RTSTUB_RED
S="$(mk ps)"; core ps
printf '| | pass 1 | pass 2 | pass 3 |\n|---|---|---|---|\n| criticals | 0 | 0 | 2 |\n' > "$S/docs/explanation/admission-baseline.md"; git -C "$S" commit -qam floor >/dev/null 2>&1
pr "$S" docs/ok.md 'fine' >/dev/null
run "$S" 7; redcase "a pass-score with open criticals" "release gate · pass-score: red"
S="$(mk hist)"; core hist
( cd "$T_TMP/seed-hist" && printf 'old Zorblax\n' > OLD.md && git add -A && git commit -qm 'old leak' && git push -q "$BARE" main ) >/dev/null 2>&1
git -C "$MIR" pull -q >/dev/null 2>&1; rm -f "$STUB/git.log"; pr "$S" docs/ok.md 'fine' >/dev/null
run "$S" 7; redcase "a leak already in harbor-core's published history" "release gate · export history: red"

t_section "a red gate on a later mirror leaves the branch where the last green one put it"
S="$(mk later)"; core later; pr "$S" docs/ok.md 'fine' >/dev/null
run "$S" 7; t_eq "the first mirror is green" "0" "$RC"
GOOD="$(tip ci/harbor-7)"
pr "$S" docs/leak.md 'owned by Zorblax' >/dev/null
run "$S" 7
t_eq "the leaking one is refused" "1" "$RC"
t_eq "...the published tip did not move" "$GOOD" "$(tip ci/harbor-7)"
t_eq "...and the PR was not edited" "0" "$(ghcalls 'pr edit')"

t_section "the control: with the gate check broken the mirror DOES leave (the cases above can fail)"
S="$(mk broken)"; core broken; pr "$S" docs/leak.md 'owned by Zorblax' >/dev/null
sed -e 's/^gate "\$TDIR" || refuse.*$/gate "$TDIR" || :/' -e 's/^if git -C "\$TDIR" diff --quiet.*; then$/if false; then/' "$S/bin/ci-mirror.sh" > "$S/bin/cm.new"; mv "$S/bin/cm.new" "$S/bin/ci-mirror.sh"
t_eq "positive control: both mutations landed" "2" "$(grep -c -e '^gate "\$TDIR" || :$' -e '^if false; then$' "$S/bin/ci-mirror.sh" | tr -d ' ')"
run "$S" 7
t_eq "the mutant pushes although the gate was red" "2" "$(nbranches)"

t_section "a missing token, a dry run, and a bad mirror checkout"
S="$(mk misc)"; core misc; pr "$S" docs/ok.md 'fine' >/dev/null
NOTOKEN=1; run "$S" 7
t_eq "no token: refused" "1" "$RC"
t_has "...and says which variable" "$OUT" "HARBOR_CORE_MIRROR_TOKEN"
t_eq "...nothing pushed" "0" "$(nbranches)"
NOTOKEN=1; run "$S" --dry-run 7
t_eq "a dry run needs no token and is green" "0" "$RC"
t_eq "...pushes nothing" "0" "$(nbranches)"
t_eq "...calls no gh create or edit" "0" "$(( $(ghcalls 'pr create') + $(ghcalls 'pr edit') ))"
t_eq "...and runs no git fetch or push" "0" "$(gitcalls ARGV)"
S2="$(mk dryleak)"; pr "$S2" docs/leak.md 'owned by Zorblax' >/dev/null
NOTOKEN=1; run "$S2" --dry-run 7
t_eq "a dry run of a leaking PR is red" "1" "$RC"
printf 'stray\n' > "$MIR/stray"
run "$S" 7
t_eq "a dirty mirror checkout is refused" "1" "$RC"
t_eq "...nothing pushed" "0" "$(nbranches)"
rm "$MIR/stray"
git -C "$MIR" remote set-url origin https://github.com/someone/else.git
run "$S" 7
t_eq "a mirror checkout whose origin is not harbor-core is refused" "1" "$RC"
t_eq "...nothing pushed" "0" "$(nbranches)"
HARBOR_CORE_MIRROR_DIR="$T_TMP/none" sh "$S/bin/ci-mirror.sh" 7 >/dev/null 2>&1; t_eq "no mirror checkout is refused" "1" "$?"
HARBOR_CORE_MIRROR_TOKEN="$TOKEN" sh "$S/bin/ci-mirror.sh" 7 >/dev/null 2>&1; t_eq "an unset HARBOR_CORE_MIRROR_DIR is refused" "1" "$?"
sh "$S/bin/ci-mirror.sh" >/dev/null 2>&1; t_eq "no PR number is a usage error" "2" "$?"
sh "$S/bin/ci-mirror.sh" abc >/dev/null 2>&1; t_eq "a non-numeric PR is a usage error" "2" "$?"
sh "$S/bin/ci-mirror.sh" --bogus 7 >/dev/null 2>&1; t_eq "an unknown option is a usage error" "2" "$?"
sh "$S/bin/ci-mirror.sh" --close --dry-run 7 >/dev/null 2>&1; t_eq "--dry-run with --close is a usage error" "2" "$?"

t_section "--status: the run's conclusion for the mirror head becomes public-ci on the harbor PR head"
S="$(mk status)"; core status; HS="$(pr "$S" docs/ok.md 'fine')"
run "$S" 7; MS="$(tip ci/harbor-7)"
setstatus() { run "$S" --status 7; }
printf '%s\tcompleted\tsuccess\thttps://runs.test/1\n%s\tcompleted\tsuccess\thttps://runs.test/2\n' "$MS" "$MS" > "$STUB/runs"
rm -f "$STUB/status.log"; setstatus
t_eq "all runs green: exit 0" "0" "$RC"
t_has "...state success" "$(cat "$STUB/status.log")" "state=success"
t_has "...context public-ci" "$(cat "$STUB/status.log")" "context=public-ci"
t_has "...on the harbor PR head" "$(cat "$STUB/status.log")" "statuses/$HS"
t_has "...linked to the run" "$(cat "$STUB/status.log")" "target_url=https://runs.test/2"
printf '%s\tcompleted\tsuccess\thttps://runs.test/1\n%s\tcompleted\tfailure\thttps://runs.test/2\n' "$MS" "$MS" > "$STUB/runs"
rm -f "$STUB/status.log"; setstatus
t_has "one failed run: state failure" "$(cat "$STUB/status.log")" "state=failure"
t_has "...linked to the failing run" "$(cat "$STUB/status.log")" "target_url=https://runs.test/2"
printf '%s\tcompleted\tsuccess\thttps://runs.test/1\n%s\tin_progress\t\thttps://runs.test/2\n' "$MS" "$MS" > "$STUB/runs"
rm -f "$STUB/status.log"; setstatus
t_has "one run still going: state pending" "$(cat "$STUB/status.log")" "state=pending"
# 2026-10-22, #1344: two runs of one workflow started together, concurrency cancelled one, and public-ci read it as red.
printf '%s\tcompleted\tcancelled\thttps://runs.test/c\tgovernance\n%s\tin_progress\t\thttps://runs.test/2\tgovernance\n' "$MS" "$MS" > "$STUB/runs"
rm -f "$STUB/status.log"; setstatus
t_has "a cancelled run its workflow replaced: pending, not failure" "$(cat "$STUB/status.log")" "state=pending"
printf '%s\tcompleted\tcancelled\thttps://runs.test/c\tgovernance\n%s\tcompleted\tsuccess\thttps://runs.test/2\tgovernance\n' "$MS" "$MS" > "$STUB/runs"
rm -f "$STUB/status.log"; setstatus
t_has "...and success once the replacement is green" "$(cat "$STUB/status.log")" "state=success"
printf '%s\tcompleted\tcancelled\thttps://runs.test/c\tgovernance\n%s\tcompleted\tsuccess\thttps://runs.test/2\tstranger-install\n' "$MS" "$MS" > "$STUB/runs"
rm -f "$STUB/status.log"; setstatus
t_has "a cancelled run nothing replaced is still failure" "$(cat "$STUB/status.log")" "state=failure"
printf '%s\tcompleted\tfailure\thttps://runs.test/old\n' "0000000000000000000000000000000000000000" > "$STUB/runs"
rm -f "$STUB/status.log"; setstatus
t_has "only an older commit's run: pending, never its failure" "$(cat "$STUB/status.log")" "state=pending"
t_hasnt "...and not linked to the old run" "$(cat "$STUB/status.log")" "runs.test/old"
t_has "the harbor-core reads carry the mirror token" "$(grep 'run list' "$STUB/gh.log" | tail -1)" "GH_TOKEN=$TOKEN"
t_hasnt "the harbor status write does not" "$(grep 'statuses' "$STUB/gh.log" | tail -1)" "$TOKEN"
t_hasnt "...and the output never prints the token" "$OUT" "$TOKEN"
rm -f "$STUB/pr_number"; rm -f "$STUB/status.log"; setstatus
t_has "no mirror PR: pending" "$(cat "$STUB/status.log")" "state=pending"
NOTOKEN=1; run "$S" --status 7
t_eq "--status without the token is refused" "1" "$RC"

t_section "no core file differs from the PR's base: the mirror run sets public-ci success, and --status keeps it"
S="$(mk same)"; core same
( cd "$S" && sh bin/deploy-push.sh "$MIR" ) >/dev/null 2>&1 && git -C "$MIR" push -q origin main >/dev/null 2>&1
t_has "harbor-core main holds the source's core set" "$(git -C "$BARE" ls-tree -r --name-only main)" "docs/a.md"
pr "$S" docs/core.md 'a core change' >/dev/null
run "$S" 7; t_eq "a core change first: mirrored, head and base" "2" "$(nbranches)"
HD="$(pr "$S" NOTES.md 'a dev-only change')"
rm -f "$STUB/status.log"; run "$S" 7
t_eq "a dev-only head: green" "0" "$RC"
t_has "...public-ci success on that head" "$(cat "$STUB/status.log")" "statuses/$HD"
t_has "...state success" "$(cat "$STUB/status.log")" "state=success"
t_has "...saying why" "$(cat "$STUB/status.log")" "description=no core file differs from the PR's base"
t_eq "...the mirror the earlier head left is gone" "0" "$(nbranches)"
t_eq "...and its PR closed" "no" "$([ -f "$STUB/pr_number" ] && echo yes || echo no)"
rm -f "$STUB/status.log"; run "$S" --status 7
t_eq "--status after it: green" "0" "$RC"
t_eq "...writes nothing, so success is not reset to pending" "no" "$([ -f "$STUB/status.log" ] && echo yes || echo no)"
t_has "...and says success" "$OUT" "public-ci success"

t_section "--close: the mirror PR is closed and its branch deleted; a repeat is harmless"
S="$(mk close)"; core close; pr "$S" docs/ok.md 'fine' >/dev/null
run "$S" 7
t_eq "the mirror exists first, head and base" "2" "$(nbranches)"
run "$S" --close 7
t_eq "--close is green" "0" "$RC"
t_eq "...the branch is gone from harbor-core" "none" "$(tip ci/harbor-7)"
t_eq "...and so is its base branch" "none" "$(tip ci/base-7)"
t_eq "...the PR is closed" "no" "$([ -f "$STUB/pr_number" ] && echo yes || echo no)"
t_eq "...main is untouched" "$(git -C "$BARE" rev-parse refs/heads/main)" "$(tip main)"
run "$S" --close 7
t_eq "closing again is green" "0" "$RC"
NOTOKEN=1; run "$S" --close 7
t_eq "--close without the token is refused" "1" "$RC"

t_section "the base is pushed to the public repo, so it passes the leak gate too"
S="$(mk baseleak)"; core baseleak
printf 'a Zorblax line\n' > "$S/docs/leak.md"; git -C "$S" add -A >/dev/null 2>&1; git -C "$S" commit -qm leak >/dev/null 2>&1
git -C "$S" checkout -q -b fixer >/dev/null 2>&1; git -C "$S" rm -q docs/leak.md >/dev/null 2>&1; git -C "$S" commit -qm unleak >/dev/null 2>&1
git -C "$S" rev-parse HEAD > "$STUB/head_sha"; git -C "$S" checkout -q - >/dev/null 2>&1
run "$S" 7
t_eq "a PR that removes a leak from its base: refused" "1" "$RC"
t_has "...naming the base" "$OUT" "the PR's base"
t_eq "...nothing pushed" "0" "$(nbranches)"
t_done
